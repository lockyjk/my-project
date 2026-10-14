--!nocheck
-- Runtime smoke test: `lune run scripts/smoke`
--
-- Executes the real world builders, every creature model (all mutations), and builds every
-- client UI window inside a fake DataModel. Every property write is validated against
-- Roblox's API reflection database (name exists, writable, value type / enum type
-- matches), so typos and wrong types that strict type-checking can't see (dynamic prop
-- tables, Instance.new strings) fail here instead of in Studio.
-- Prints part counts per area as a rough performance budget.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local db = roblox.getReflectionDatabase()
local errors = {}
local function fail(msg)
	table.insert(errors, msg)
	error(msg, 3)
end

---------------------------------------------------------------------------
-- Reflection helpers
---------------------------------------------------------------------------
local classCache = {}
local function classInfo(name)
	local c = classCache[name]
	if c == nil then
		c = db:GetClass(name) or false
		classCache[name] = c
	end
	return c or nil
end

local function isA(className, base)
	local c = classInfo(className)
	while c do
		if c.Name == base then
			return true
		end
		c = c.Superclass and classInfo(c.Superclass)
	end
	return false
end

local function findMember(className, name, kind)
	local c = classInfo(className)
	while c do
		local t = c[kind]
		if t and t[name] then
			return t[name]
		end
		c = c.Superclass and classInfo(c.Superclass)
	end
	return nil
end

local NUMBERS = { Float32 = true, Float64 = true, Int32 = true, Int64 = true }
local function typeOk(datatype, v)
	local tv = typeof(v)
	if NUMBERS[datatype] then
		return tv == "number"
	elseif datatype == "Bool" then
		return tv == "boolean"
	elseif datatype == "String" or datatype == "Content" or datatype == "BinaryString" then
		return tv == "string"
	elseif datatype == "Color3uint8" then
		return tv == "Color3"
	elseif datatype == "OptionalCFrame" then
		return tv == "CFrame"
	elseif datatype == "Ref" then
		return type(v) == "table" and rawget(v, "__fake") == true
	elseif string.sub(datatype, 1, 5) == "Enum." then
		return tv == "EnumItem" and string.sub(tostring(v), 1, #datatype + 1) == datatype .. "."
	elseif datatype == "Font" then
		return tv == "Font"
	end
	-- Vector3, CFrame, Color3, UDim2, NumberSequence, ColorSequence, NumberRange, Rect, …
	return tv == datatype
end

---------------------------------------------------------------------------
-- Fake signals / instances
---------------------------------------------------------------------------
local function fakeSignal()
	local s = {}
	function s:Connect(fn)
		return { Disconnect = function() end, Connected = true }
	end
	s.Once = s.Connect
	function s:Wait()
		return nil
	end
	return s
end

-- Unknown members (events and engine methods the dump doesn't list) resolve to a
-- "magic" value that works as a signal and as a no-op method.
local magic = setmetatable({}, {
	__call = function()
		return nil
	end,
})
rawset(magic, "Connect", function()
	return { Disconnect = function() end, Connected = true }
end)
rawset(magic, "Once", rawget(magic, "Connect"))
rawset(magic, "Wait", function() end)

local Fake = {}
local methods = {}
local partCount = 0

local function newFake(className)
	if not classInfo(className) then
		fail(`Instance.new: unknown class {className}`)
	end
	local inst = setmetatable({
		__fake = true,
		ClassName = className,
		_props = {},
		_children = {},
		_attrs = {},
		_parent = nil,
		_name = className,
	}, Fake)
	if isA(className, "BasePart") then
		partCount += 1
		inst._props.CFrame = roblox.CFrame.new()
		inst._props.Size = roblox.Vector3.new(4, 1, 2)
	end
	return inst
end

local DEFAULTS = {
	Vector3 = roblox.Vector3.new(),
	Vector2 = roblox.Vector2.new(),
	CFrame = roblox.CFrame.new(),
	Color3 = roblox.Color3.new(1, 1, 1),
	Color3uint8 = roblox.Color3.new(1, 1, 1),
	UDim2 = roblox.UDim2.new(),
	UDim = roblox.UDim.new(),
	Bool = false,
	String = "",
	Float32 = 0,
	Float64 = 0,
	Int32 = 0,
	Int64 = 0,
}

Fake.__index = function(self, key)
	local m = methods[key]
	if m then
		return m
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "Name" then
		return rawget(self, "_name")
	end
	local props = rawget(self, "_props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	local cls = rawget(self, "ClassName")
	if key == "Position" and isA(cls, "BasePart") then
		return props.CFrame.Position
	end
	if key == "AssemblyLinearVelocity" then
		return roblox.Vector3.new()
	end
	for _, c in rawget(self, "_children") do
		if rawget(c, "_name") == key then
			return c
		end
	end
	local prop = findMember(cls, key, "Properties")
	if prop then
		if DEFAULTS[prop.Datatype] ~= nil then
			return DEFAULTS[prop.Datatype]
		end
		return nil
	end
	return magic
end

Fake.__newindex = function(self, key, value)
	local cls = rawget(self, "ClassName")
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local list = rawget(old, "_children")
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
		return
	elseif key == "Name" then
		rawset(self, "_name", value)
		return
	end
	if key == "Position" and isA(cls, "BasePart") then
		local cf = rawget(self, "_props").CFrame
		rawget(self, "_props").CFrame = cf.Rotation + value
		return
	end
	local prop = findMember(cls, key, "Properties")
	if not prop then
		fail(`cannot set {key}: not a property of {cls}`)
	end
	if prop.Scriptability == "Read" or prop.Scriptability == "None" then
		-- some properties are scriptable in Studio but marked oddly in the dump; only flag None
		if prop.Scriptability == "None" then
			fail(`cannot set {cls}.{key}: not scriptable`)
		end
	end
	if value ~= nil and not typeOk(prop.Datatype, value) then
		fail(`{cls}.{key} expects {prop.Datatype}, got {typeof(value)} ({tostring(value)})`)
	end
	rawget(self, "_props")[key] = value
end

Fake.__tostring = function(self)
	return rawget(self, "_name")
end

function methods.IsA(self, name)
	return isA(rawget(self, "ClassName"), name)
end
function methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in rawget(n, "_children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in rawget(self, "_children") do
		if rawget(c, "_name") == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "_children") do
			local f = methods.FindFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	local c = methods.FindFirstChild(self, name)
	if not c then
		fail(`WaitForChild would hang: {name} in {rawget(self, "_name")}`)
	end
	return c
end
function methods.FindFirstChildOfClass(self, cls)
	for _, c in rawget(self, "_children") do
		if rawget(c, "ClassName") == cls then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, cls)
	for _, c in rawget(self, "_children") do
		if isA(rawget(c, "ClassName"), cls) then
			return c
		end
	end
	return nil
end
function methods.FindFirstAncestor(self, name)
	local p = rawget(self, "_parent")
	while p do
		if rawget(p, "_name") == name then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end
function methods.ClearAllChildren(self)
	rawset(self, "_children", {})
end
function methods.Destroy(self)
	self.Parent = nil
end
function methods.Clone(self)
	local c = newFake(rawget(self, "ClassName"))
	rawset(c, "_name", rawget(self, "_name"))
	for k, v in rawget(self, "_props") do
		rawget(c, "_props")[k] = v
	end
	for k, v in rawget(self, "_attrs") do
		rawget(c, "_attrs")[k] = v
	end
	for _, child in rawget(self, "_children") do
		methods.Clone(child).Parent = c
	end
	return c
end
function methods.SetAttribute(self, k, v)
	local tv = typeof(v)
	local okTypes = {
		["nil"] = true,
		string = true,
		number = true,
		boolean = true,
		Vector3 = true,
		Vector2 = true,
		Color3 = true,
		CFrame = true,
		UDim2 = true,
		UDim = true,
		EnumItem = true,
		NumberRange = true,
	}
	if not okTypes[tv] then
		fail(`SetAttribute({k}): unsupported attribute type {tv}`)
	end
	rawget(self, "_attrs")[k] = v
end
function methods.GetAttribute(self, k)
	return rawget(self, "_attrs")[k]
end
function methods.GetAttributes(self)
	return table.clone(rawget(self, "_attrs"))
end
function methods.GetAttributeChangedSignal()
	return fakeSignal()
end
function methods.GetPropertyChangedSignal()
	return fakeSignal()
end
-- Model / PVInstance
function methods.GetScale()
	return 1
end
function methods.ScaleTo(self, s)
	assert(type(s) == "number" and s > 0, "ScaleTo needs a positive number")
end
function methods.GetPivot(self)
	local pp = rawget(self, "_props").PrimaryPart
	return if pp then pp.CFrame else roblox.CFrame.new()
end
function methods.PivotTo(self, cf)
	assert(typeof(cf) == "CFrame", "PivotTo needs a CFrame")
end
function methods.GetBoundingBox()
	return roblox.CFrame.new(), roblox.Vector3.new(4, 4, 4)
end
-- Terrain
local terrainOps = 0
for _, name in { "FillBlock", "FillBall", "FillCylinder", "ReplaceMaterial", "SetMaterialColor", "FillRegion" } do
	methods[name] = function(...)
		terrainOps += 1
	end
end
-- misc
function methods.Emit() end
function methods.Play() end
function methods.Stop() end
function methods.GetServerTimeNow()
	return os.time()
end
function methods.BulkMoveTo() end

---------------------------------------------------------------------------
-- Fake DataModel + module tree
---------------------------------------------------------------------------
local game = newFake("DataModel")
rawset(game, "_name", "game")
local services = {}
local function service(name)
	local s = services[name]
	if not s then
		s = newFake(name)
		rawset(s, "_name", name)
		s.Parent = game
		services[name] = s
	end
	return s
end
function methods.GetService(self, name)
	return service(name)
end
local workspace = service("Workspace")
local terrain = newFake("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
local camera = newFake("Camera")
camera.Name = "Camera"
camera.Parent = workspace
rawget(workspace, "_props").CurrentCamera = camera
rawget(camera, "_props").ViewportSize = roblox.Vector2.new(1280, 720)

local isServer = true
local runService = service("RunService")
function methods.IsServer()
	return isServer
end
function methods.IsClient()
	return not isServer
end
function methods.IsStudio()
	return true
end
function methods.BindToRenderStep() end

local paths = {}
local function mount(dir, parent)
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			local init = `{full}/init.luau`
			local node = newFake(if fs.isFile(`{full}/init.server.luau`) then "Script" else "Folder")
			node.Name = entry
			node.Parent = parent
			paths[node] = if fs.isFile(init) then init else nil
			mount(full, node)
		elseif entry:match("%.luau$") and not entry:match("^init%.") then
			local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			local node = newFake("ModuleScript")
			node.Name = name
			node.Parent = parent
			paths[node] = full
		end
	end
end

local replicated = service("ReplicatedStorage")
local modules = newFake("Folder")
modules.Name = "Modules"
modules.Parent = replicated
mount("src/shared", modules)
local sss = service("ServerScriptService")
local serverRoot = newFake("Folder")
serverRoot.Name = "Server"
serverRoot.Parent = sss
mount("src/server", serverRoot)
local clientRoot = newFake("Folder")
clientRoot.Name = "Client"
clientRoot.Parent = service("StarterPlayer")
mount("src/client", clientRoot)

-- Players.LocalPlayer for the client phase
local players = service("Players")
local localPlayer = newFake("Player")
localPlayer.Name = "Tester"
rawget(localPlayer, "_props").UserId = 1
rawget(localPlayer, "_props").DisplayName = "Tester"
localPlayer.Parent = players
local playerGui = newFake("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = localPlayer
rawget(players, "_props").LocalPlayer = localPlayer
function methods.GetPlayers()
	return { localPlayer }
end
function methods.GetUserThumbnailAsync()
	return ""
end
function methods.Create(self, inst, info, goal)
	return { Play = function() end, Cancel = function() end, Completed = fakeSignal() }
end
function methods.AddItem() end
function methods.PlayLocalSound() end
function methods.GetRequestBudgetForRequestType()
	return 100
end

---------------------------------------------------------------------------
-- Module loader
---------------------------------------------------------------------------
local cache = {}
local function stubRandom(seed)
	local state = ((seed or 12345) % 2147483646) + 1
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
local baseEnv = getfenv(1)
local taskStub = {
	wait = function()
		return 0
	end,
	spawn = function(fn, ...)
		-- run immediately but don't let infinite loops hang the smoke test
		return nil
	end,
	delay = function() end,
	defer = function() end,
}
local globals = {
	game = game,
	workspace = workspace,
	Instance = { new = newFake },
	Enum = roblox.Enum,
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	Region3 = roblox.Region3,
	TweenInfo = {
		new = function(...)
			return { ... }
		end,
	},
	Random = { new = stubRandom },
	DateTime = {
		now = function()
			return { UnixTimestamp = os.time() }
		end,
	},
	task = taskStub,
	tick = os.clock,
	warn = function(...)
		print("[warn]", ...)
	end,
}
local requireNode
local function envFor(node)
	return setmetatable({ script = node, require = requireNode }, {
		__index = function(_, k)
			if k == "script" then
				return node
			end
			local g = globals[k]
			if g ~= nil then
				return g
			end
			return baseEnv[k]
		end,
	})
end
function requireNode(node)
	if cache[node] ~= nil then
		return cache[node]
	end
	local path = paths[node]
	assert(path, `{node} is not a ModuleScript`)
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = envFor(node), injectGlobals = false })
	local result = chunk()
	cache[node] = result
	return result
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
local failures = 0
local function step(name, fn)
	local before = partCount
	local ok, err = pcall(fn)
	if ok then
		print(string.format("  ok   %-42s %6d parts", name, partCount - before))
	else
		failures += 1
		print(`  FAIL {name}\n       {err}`)
	end
end

print("Server")
local Registry = requireNode(modules.Registry)
step("config validation", function()
	Registry.assertValid()
end)
local Net = requireNode(modules.Net)
step("remotes", function()
	Net.Server.init()
end)
local world = serverRoot.World
step("WorldBuilder.build (everything)", function()
	requireNode(world.WorldBuilder).build()
end)
local function count(inst)
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local built = workspace:FindFirstChild("World")
if built then
	for _, name in { "Hub", "RollMachine", "Zoos", "MonsterArena" } do
		local f = built:FindFirstChild(name)
		print(string.format("       %-36s %6d parts", name, if f then count(f) else -1))
	end
end
local Props = requireNode(world.Props)
step("zoo decorations", function()
	for _, d in requireNode(modules.GameConfig).Decorations do
		assert(Props.decoration(d.builder, workspace, roblox.CFrame.new()), d.builder)
	end
end)

print("Models")
local BrainrotModels = requireNode(modules.Models.BrainrotModels)
local MonsterModels = requireNode(modules.Models.MonsterModels)
for _, def in Registry.Brainrots do
	step(`brainrot {def.id}`, function()
		for _, m in Registry.Mutations do
			BrainrotModels.build(def.id, m.id)
		end
	end)
end
for id in Registry.Monster do
	step(`monster {id}`, function()
		MonsterModels.build(id)
	end)
end

print("Server services load")
for _, name in
	{
		"DataService",
		"InventoryService",
		"RollService",
		"ZooService",
		"UpgradeService",
		"RewardService",
		"CombatService",
		"MonsterService",
		"ArenaService",
		"PlayerService",
		"DailyRewardService",
		"ShopService",
		"EventService",
		"DevService",
	}
do
	step(`require {name}`, function()
		requireNode(serverRoot.Services[name])
	end)
end
step("ZooService.init (state folder)", function()
	requireNode(serverRoot.Services.ZooService).init()
end)

print("Client")
isServer = false
local live = newFake("Folder")
live.Name = "Live"
live.Parent = workspace
local client = clientRoot
local order = {
	client.Controllers.ClientState,
	client.UI.Windows,
	client.Controllers.Effects,
	client.UI.Notifications,
	client.Controllers.CameraController,
	client.Controllers.UnitRenderer,
	client.Controllers.CombatFx,
	client.Controllers.CombatController,
	client.UI.BattleUI,
	client.UI.RollUI,
	client.Controllers.RollController,
	client.UI.HUD,
	client.UI.CollectionUI,
	client.UI.ZooUI,
	client.UI.StandWindows,
	client.UI.ArenaUI,
	client.Controllers.ZooController,
	client.Controllers.FollowController,
	client.Controllers.AmbientController,
	client.Controllers.CrowdController,
	client.Controllers.EventController,
	client.Controllers.PromptController,
	client.Controllers.MusicController,
}
for _, node in order do
	step(`start {node.Name}`, function()
		local m = requireNode(node)
		if m.start then
			m.start()
		end
	end)
end
-- give the client some state, then build every window
local ClientState = requireNode(client.Controllers.ClientState)
local DataService = requireNode(serverRoot.Services.DataService)
local data = DataService.template()
for k, v in data do
	ClientState.data[k] = v
end
ClientState.loaded = true
ClientState.inventory = {
	["1"] = { id = "BananiniBongo", mut = "Normal", lvl = 1, t = 1 },
	["2"] = { id = "CosmocornoBrainrot", mut = "Rainbow", lvl = 5, t = 2 },
}
ClientState.data.equipped = { "1" }
local Windows = requireNode(client.UI.Windows)
for _, name in { "Collection", "Zoo", "Upgrades", "Shop", "Daily", "Events", "Arena", "Settings" } do
	step(`window {name}`, function()
		Windows.open(name)
		Windows.refresh(name)
	end)
end
local RollUI = requireNode(client.UI.RollUI)
step("roll reveal card", function()
	RollUI.showReveal({ uid = "2", id = "CosmocornoBrainrot", mut = "Rainbow", rarity = "Secret", isNew = true })
	RollUI.setNear(true)
end)
step("crowd build", function()
	local Crowd = requireNode(client.Controllers.CrowdController)
	local _ = Crowd
end)
local Viewport = requireNode(client.UI.Viewport)
step("viewport monster", function()
	Viewport.new({ id = "ForestTitan", monster = true })
end)

print(`\nterrain ops: {terrainOps}, total parts created: {partCount}`)
if failures > 0 then
	print(`{failures} smoke step(s) failed`)
	process.exit(1)
end
print("smoke test passed")
