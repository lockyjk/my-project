--!strict
-- Central networking. Every remote is declared here with a runtime payload schema and a rate
-- limit. The server validates every client payload before any handler runs; invalid or
-- over-limit calls are dropped. Clients and server use the same names, so typos fail loudly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-------------------------------------------------------------------------------
-- Payload validators
-------------------------------------------------------------------------------
export type Check = (any) -> boolean

local t = {}

function t.number(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function t.int(v: any): boolean
	return t.number(v) and v % 1 == 0
end

function t.boolean(v: any): boolean
	return type(v) == "boolean"
end

function t.string(maxLength: number): Check
	return function(v: any): boolean
		return type(v) == "string" and #v <= maxLength and utf8.len(v) ~= nil
	end
end

t.id = t.string(64)

function t.range(lo: number, hi: number): Check
	return function(v: any): boolean
		return t.int(v) and v >= lo and v <= hi
	end
end

function t.optional(check: Check): Check
	return function(v: any): boolean
		return v == nil or check(v)
	end
end

function t.array(check: Check, maxLength: number): Check
	return function(v: any): boolean
		if type(v) ~= "table" then
			return false
		end
		local n = 0
		for k, item in v do
			n += 1
			if type(k) ~= "number" or k ~= n or not check(item) then
				return false
			end
		end
		return n <= maxLength
	end
end

function t.oneOf(values: { any }): Check
	return function(v: any): boolean
		return table.find(values, v) ~= nil
	end
end

function t.vector(v: any): boolean
	return typeof(v) == "Vector3" and v == v and v.Magnitude < 1e6
end

function t.any(_v: any): boolean
	return true
end

Net.t = t

-------------------------------------------------------------------------------
-- Remote definitions
-- kind: "Function" (client invokes, server returns) | "Event" (client fires) | "Push" (server fires)
-- rate: max calls per second per player (token bucket with burst = rate * 2)
-------------------------------------------------------------------------------
export type RemoteDef = { kind: "Function" | "Event" | "Push" | "Unreliable", args: { Check }?, rate: number? }

local defs: { [string]: RemoteDef } = {
	-- Rolling
	Roll = { kind = "Function", args = { t.boolean }, rate = 4 }, -- (useToken)
	-- Collection
	Equip = { kind = "Function", args = { t.id, t.boolean }, rate = 10 },
	EquipBest = { kind = "Function", args = {}, rate = 2 },
	SendToZoo = { kind = "Function", args = { t.id, t.optional(t.id) }, rate = 10 },
	RemoveFromZoo = { kind = "Function", args = { t.id }, rate = 10 },
	FillZoo = { kind = "Function", args = {}, rate = 2 },
	SellBrainrots = { kind = "Function", args = { t.array(t.id, 200) }, rate = 2 },
	LockBrainrot = { kind = "Function", args = { t.id, t.boolean }, rate = 10 },
	LevelUpBrainrot = { kind = "Function", args = { t.id }, rate = 8 },
	-- Zoo
	UnlockHabitat = { kind = "Function", args = { t.id }, rate = 3 },
	UpgradeHabitat = { kind = "Function", args = { t.id }, rate = 4 },
	CollectZoo = { kind = "Function", args = {}, rate = 3 },
	PetBrainrot = { kind = "Function", args = { t.id }, rate = 6 },
	BuyDecoration = { kind = "Function", args = { t.id }, rate = 3 },
	TeleportTo = { kind = "Function", args = { t.oneOf({ "Zoo", "Arena", "Machine", "Spawn" }) }, rate = 1 },
	-- Progression / economy
	BuyUpgrade = { kind = "Function", args = { t.id }, rate = 8 },
	ClaimDaily = { kind = "Function", args = {}, rate = 2 },
	GemShopBuy = { kind = "Function", args = { t.id }, rate = 3 },
	PromptProduct = { kind = "Function", args = { t.id }, rate = 2 },
	PromptPass = { kind = "Function", args = { t.id }, rate = 2 },
	SetSetting = { kind = "Function", args = { t.id, t.any }, rate = 6 },
	-- Arena
	ArenaEnter = { kind = "Function", args = { t.optional(t.id) }, rate = 2 },
	ArenaLeave = { kind = "Function", args = {}, rate = 2 },
	PlayerAction = {
		kind = "Event",
		args = { t.oneOf({ "Attack", "Dodge", "Heal", "Rally", "Ultimate" }), t.optional(t.vector) },
		rate = 12,
	},
	-- Server -> client
	State = { kind = "Push" }, -- (patch: { [key]: value })
	Inventory = { kind = "Push" }, -- ("full", inv) | ("set", uid, item?)
	Notify = { kind = "Push" }, -- (text, color?)
	Reward = { kind = "Push" }, -- (title, lines)
	WelcomeBack = { kind = "Push" }, -- (coins, secondsAway)
	Announce = { kind = "Push" }, -- (text, color) server-wide shout (rare rolls, events)
	Battle = { kind = "Push" }, -- (state) arena / invasion status for the HUD
	CombatEvents = { kind = "Push" }, -- ({ event }) batched per tick
	CombatSnap = { kind = "Unreliable" }, -- (battleId, buffer) unit positions
}

Net.Definitions = defs

-------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------
local FOLDER_NAME = "Remotes"

local function folder(): Folder
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not f then
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = ReplicatedStorage
			f = created
		end
		return f :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function getRemote(name: string): Instance
	local def = defs[name]
	assert(def, `Unknown remote {name}`)
	local f = folder()
	local existing = f:FindFirstChild(name)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local remote: Instance = if def.kind == "Function"
			then Instance.new("RemoteFunction")
			elseif def.kind == "Unreliable" then Instance.new("UnreliableRemoteEvent")
			else Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = f
		return remote
	end
	return f:WaitForChild(name)
end

-------------------------------------------------------------------------------
-- Server
-------------------------------------------------------------------------------
local Server = {}
Net.Server = Server

type Bucket = { tokens: number, last: number, strikes: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, name: string, rate: number): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local b = perPlayer[name]
	if not b then
		b = { tokens = rate * 2, last = now, strikes = 0 }
		perPlayer[name] = b
	end
	b.tokens = math.min(rate * 2, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then
		b.strikes += 1
		if b.strikes % 50 == 1 then
			warn(`[Net] rate limit: {player.Name} -> {name}`)
		end
		return false
	end
	b.tokens -= 1
	return true
end

local function validate(player: Player, name: string, def: RemoteDef, args: { any }, n: number): boolean
	local schema: { Check } = def.args or {}
	if n > #schema then
		warn(`[Net] {player.Name} sent too many args to {name}`)
		return false
	end
	for i, check in schema do
		if not check(args[i]) then
			warn(`[Net] {player.Name} sent invalid arg #{i} to {name}`)
			return false
		end
	end
	return allow(player, name, def.rate or 30)
end

Server.onViolation = nil :: ((Player, string) -> ())?

-- Client -> server event
function Server.on(name: string, handler: (Player, ...any) -> ())
	local def = defs[name]
	assert(def and def.kind == "Event", `{name} is not an Event`)
	local remote = getRemote(name) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		local args = table.pack(...)
		if not validate(player, name, def, args, args.n) then
			return
		end
		local ok, err = pcall(handler :: any, player, table.unpack(args, 1, args.n))
		if not ok then
			warn(`[Net] {name} handler error: {err}`)
		end
	end)
end

-- Client -> server function. Handler returns (ok: boolean, ...)
function Server.handle(name: string, handler: (Player, ...any) -> ...any)
	local def = defs[name]
	assert(def and def.kind == "Function", `{name} is not a Function`)
	local remote = getRemote(name) :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, ...: any): ...any
		local args = table.pack(...)
		if not validate(player, name, def, args, args.n) then
			return false, "Slow down!"
		end
		local results = table.pack(pcall(handler, player, table.unpack(args, 1, args.n)))
		if not results[1] then
			warn(`[Net] {name} handler error: {results[2]}`)
			return false, "Something went wrong"
		end
		return table.unpack(results, 2, results.n)
	end
end

function Server.fire(name: string, player: Player, ...: any)
	assert(defs[name] and defs[name].kind == "Push", `{name} is not a Push`)
	local remote = getRemote(name) :: RemoteEvent
	remote:FireClient(player, ...)
end

function Server.fireAll(name: string, ...: any)
	assert(defs[name] and defs[name].kind == "Push", `{name} is not a Push`)
	local remote = getRemote(name) :: RemoteEvent
	remote:FireAllClients(...)
end

-- Unreliable push (dropped packets are fine; keep payloads under ~900 bytes)
function Server.fireUnreliable(name: string, player: Player, ...: any)
	assert(defs[name] and defs[name].kind == "Unreliable", `{name} is not Unreliable`)
	local remote = getRemote(name) :: UnreliableRemoteEvent
	remote:FireClient(player, ...)
end

function Server.fireList(name: string, players: { Player }, ...: any)
	local remote = getRemote(name) :: RemoteEvent
	for _, p in players do
		remote:FireClient(p, ...)
	end
end

function Server.init()
	for name in defs do
		getRemote(name)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

-------------------------------------------------------------------------------
-- Client
-------------------------------------------------------------------------------
local Client = {}
Net.Client = Client

function Client.fire(name: string, ...: any)
	assert(defs[name] and defs[name].kind == "Event", `{name} is not an Event`)
	local remote = getRemote(name) :: RemoteEvent
	remote:FireServer(...)
end

function Client.invoke(name: string, ...: any): ...any
	assert(defs[name] and defs[name].kind == "Function", `{name} is not a Function`)
	local remote = getRemote(name) :: RemoteFunction
	return remote:InvokeServer(...)
end

function Client.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local def = defs[name]
	assert(def and (def.kind == "Push" or def.kind == "Unreliable"), `{name} is not a Push`)
	local remote = getRemote(name) :: any
	return remote.OnClientEvent:Connect(handler)
end

return Net
