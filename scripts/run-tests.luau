--!nocheck
-- Headless test runner: `lune run scripts/run-tests` (or scripts/test.sh).
-- Emulates the Rojo tree (script.Parent, game:GetService) for pure modules and provides a
-- TestEZ-compatible describe/it/expect so the same *.spec.luau files also run in Studio via TestEZ.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

---------------------------------------------------------------------------
-- Virtual instance tree
---------------------------------------------------------------------------
local Node = {}
Node.__index = function(self, key)
	local method = rawget(Node, key)
	if method then
		return method
	end
	local children = rawget(self, "_children")
	local child = children[key]
	if child then
		return child
	end
	error(`{key} is not a valid member of {rawget(self, "Name")}`, 2)
end

local function newNode(name, parent, path)
	local node = setmetatable({ Name = name, Parent = parent, _children = {}, _path = path }, Node)
	if parent then
		rawget(parent, "_children")[name] = node
	end
	return node
end

function Node:FindFirstChild(name)
	return rawget(self, "_children")[name]
end

function Node:WaitForChild(name)
	return self[name]
end

function Node:GetChildren()
	local out = {}
	for _, c in rawget(self, "_children") do
		table.insert(out, c)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

function Node:IsA(className)
	return className == "ModuleScript" and rawget(self, "_path") ~= nil
end

local function mount(dir, parent)
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			local init = `{full}/init.luau`
			local node = newNode(entry, parent, if fs.isFile(init) then init else nil)
			mount(full, node)
		elseif entry:match("%.luau$") and not entry:match("^init%.") then
			local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			if not entry:match("%.server%.luau$") and not entry:match("%.client%.luau$") then
				newNode(name, parent, full)
			end
		end
	end
end

local gameNode = newNode("game", nil, nil)
local replicated = newNode("ReplicatedStorage", gameNode, nil)
local serverStorage = newNode("ServerStorage", gameNode, nil)
local shared = newNode("Shared", replicated, nil)
mount("src/shared", shared)
local testsNode = newNode("Tests", serverStorage, nil)
mount("tests", testsNode)

function gameNode:GetService(name)
	return self[name]
end

---------------------------------------------------------------------------
-- Module loading
---------------------------------------------------------------------------
local cache = {}
local baseEnv = getfenv(1)

local function stubRandom(seed)
	local state = (seed or os.time()) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 16807) % 2147483647
		local u = state / 2147483647
		if a then
			return a + (b - a) * u
		end
		return u
	end
	function r:NextInteger(a, b)
		return math.floor(self:NextNumber() * (b - a + 1)) + a
	end
	return r
end

local globals = {
	game = gameNode,
	Color3 = roblox.Color3,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	UDim2 = roblox.UDim2,
	Random = { new = stubRandom },
	DateTime = {
		now = function()
			return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 }
		end,
	},
	tick = os.clock,
	warn = function(...)
		print("[warn]", ...)
	end,
}

local requireNode

local function makeEnv(node)
	local env = setmetatable({ script = node, require = requireNode }, {
		__index = function(_, k)
			if k == "script" then
				return node
			elseif k == "require" then
				return requireNode
			end
			local g = globals[k]
			if g ~= nil then
				return g
			end
			return baseEnv[k]
		end,
	})
	return env
end

function requireNode(node)
	if type(node) ~= "table" then
		error("require expects a module node, got " .. typeof(node))
	end
	if cache[node] ~= nil then
		return cache[node]
	end
	local path = rawget(node, "_path")
	assert(path, `{node.Name} is not a ModuleScript`)
	local source = fs.readFile(path)
	local chunk = luau.load(source, { debugName = path, environment = makeEnv(node), injectGlobals = false })
	local result = chunk()
	cache[node] = result
	return result
end

---------------------------------------------------------------------------
-- TestEZ-compatible expectations
---------------------------------------------------------------------------
local function fmt(v)
	if type(v) == "string" then
		return `"{v}"`
	end
	return tostring(v)
end

local function expect(value)
	local negate = false
	local e = {}
	local function check(ok, message)
		if negate then
			ok = not ok
			message = "NOT " .. message
		end
		if not ok then
			error(message, 3)
		end
		return e
	end
	local chain = setmetatable({}, {
		__index = function(self, key)
			if key == "never" then
				negate = not negate
				return self
			elseif key == "to" or key == "be" or key == "been" or key == "have" or key == "was" or key == "at" then
				return self
			elseif key == "equal" then
				return function(expected)
					return check(value == expected, `expected {fmt(value)} to equal {fmt(expected)}`)
				end
			elseif key == "near" then
				return function(expected, limit)
					limit = limit or 1e-7
					return check(
						math.abs(value - expected) <= limit,
						`expected {fmt(value)} to be near {fmt(expected)} (±{limit})`
					)
				end
			elseif key == "ok" then
				return function()
					return check(value ~= nil and value ~= false, `expected {fmt(value)} to be ok`)
				end
			elseif key == "a" or key == "an" then
				return function(typeName)
					return check(typeof(value) == typeName, `expected {fmt(value)} to be a {typeName}`)
				end
			elseif key == "throw" then
				return function(substring)
					local ok, err = pcall(value)
					local matches = not ok and (substring == nil or tostring(err):find(substring, 1, true) ~= nil)
					return check(matches, `expected function to throw {substring or ""}`)
				end
			end
			error("Unknown expectation " .. key, 2)
		end,
	})
	return chain
end

---------------------------------------------------------------------------
-- describe / it
---------------------------------------------------------------------------
local results = { passed = 0, failed = 0, failures = {} }
local stack = {}
local hooks = {}

local function fullName(name)
	local parts = table.clone(stack)
	table.insert(parts, name)
	return table.concat(parts, " > ")
end

local function describe(name, fn)
	table.insert(stack, name)
	table.insert(hooks, { beforeEach = {}, afterEach = {} })
	fn()
	table.remove(hooks)
	table.remove(stack)
end

local function it(name, fn)
	for _, h in hooks do
		for _, f in h.beforeEach do
			f()
		end
	end
	local ok, err = pcall(fn)
	for _, h in hooks do
		for _, f in h.afterEach do
			f()
		end
	end
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, { name = fullName(name), err = tostring(err) })
	end
end

globals.describe = describe
globals.it = it
globals.expect = expect
globals.beforeEach = function(fn)
	table.insert(hooks[#hooks].beforeEach, fn)
end
globals.afterEach = function(fn)
	table.insert(hooks[#hooks].afterEach, fn)
end
globals.beforeAll = function(fn)
	fn()
end
globals.afterAll = function(fn)
	fn()
end
globals.FOCUS = function() end
globals.SKIP = function() end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
local filter = process.args[1]
local loaderOnly = process.env.LOADER_ONLY == "1"
for _, node in testsNode:GetChildren() do
	if not loaderOnly and node.Name:match("%.spec$") and (filter == nil or node.Name:find(filter, 1, true)) then
		table.insert(stack, node.Name)
		local ok, err = pcall(function()
			requireNode(node)()
		end)
		if not ok then
			results.failed += 1
			table.insert(results.failures, { name = node.Name .. " (load)", err = tostring(err) })
		end
		table.remove(stack)
	end
end

if loaderOnly then
	return { require = requireNode, shared = shared, tests = testsNode }
end
for _, f in results.failures do
	print(`FAIL {f.name}\n     {f.err}`)
end
print(`\n{results.passed} passed, {results.failed} failed`)
if results.failed > 0 then
	process.exit(1)
end

return { require = requireNode, shared = shared }
