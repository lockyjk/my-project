--!strict
-- Player data: loading/saving (session-locked, retried, never overwrites newer data),
-- reconciliation with the template, and replication of state to the owning client.
--
-- Other services mutate `DataService.get(player)` directly and then call `push(player, …)`
-- with the keys they changed. Inventory changes go through InventoryService, which uses
-- `pushInventory` for small deltas instead of re-sending the whole collection.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Signal = require(Modules.Signal)
local Types = require(Modules.Types)
local SessionStore = require(script.Parent.Parent.Util.SessionStore)

local DataService = {}

DataService.Loaded = Signal.new() :: Signal.Signal<Player, Types.PlayerData, number>
DataService.Releasing = Signal.new() :: Signal.Signal<Player, Types.PlayerData>

local store: any = nil
local profiles: { [Player]: SessionStore.Profile } = {}
local ready: { [Player]: boolean } = {}

local function now(): number
	return DateTime.now().UnixTimestamp
end

function DataService.template(): Types.PlayerData
	local habitats = {}
	for _, h in GameConfig.Habitats do
		habitats[h.id] = { unlocked = h.cost == 0 and h.requiresArena == nil, level = 1, slots = {} }
	end
	local upgrades = {}
	for id in GameConfig.Upgrades do
		upgrades[id] = 0
	end
	return {
		version = GameConfig.SaveVersion,
		coins = GameConfig.Start.Coins,
		gems = GameConfig.Start.Gems,
		tokens = GameConfig.Start.Tokens,
		essence = 0,
		bossTokens = 0,
		level = 1,
		xp = 0,
		inventory = {},
		nextUid = 1,
		equipped = {},
		zoo = { habitats = habitats, decorations = {}, bank = 0 },
		upgrades = upgrades,
		pity = {},
		totalRolls = 0,
		seenRollAnim = false,
		index = {},
		arena = { beaten = {}, bestWave = {}, bossKills = {} },
		daily = { day = 0, last = 0 },
		boosts = {},
		settings = { music = true, sfx = true, skipRoll = false, autoRoll = false },
		passes = {},
		receipts = {},
		stats = { rolls = 0, kills = 0, bossKills = 0, coinsEarned = 0, playSeconds = 0 },
		lastOnline = 0,
		firstJoin = 0,
	}
end

-- Fill in keys added to the template since this save was written (deep, tables only).
local function reconcile(target: any, template: any)
	for k, v in template do
		if target[k] == nil then
			target[k] = if type(v) == "table" then table.clone(v) else v
			if type(v) == "table" then
				reconcile(target[k], v)
			end
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
			-- only recurse into record-like tables (not lists / id maps that start empty)
			reconcile(target[k], v)
		end
	end
end

local function migrate(data: any): any
	data.version = data.version or 1
	-- future: if data.version < 2 then ... end
	data.version = GameConfig.SaveVersion
	return data
end

local function prepare(raw: any): Types.PlayerData
	local template = DataService.template()
	if raw == nil then
		local fresh = template
		fresh.firstJoin = now()
		return fresh
	end
	local data = migrate(raw)
	reconcile(data, template)
	-- remove references to Brainrots that no longer exist in config (renamed/deleted rows)
	return data
end

function DataService.get(player: Player): Types.PlayerData?
	local p = profiles[player]
	if p and ready[player] then
		return p.Data
	end
	return nil
end

-- Waits (briefly) for a player's data; nil if they left or loading failed
function DataService.await(player: Player, timeout: number?): Types.PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local d = DataService.get(player)
		if d then
			return d
		end
		task.wait(0.1)
	end
	return nil
end

local HIDDEN = { inventory = true, receipts = true }

function DataService.snapshot(data: Types.PlayerData): { [string]: any }
	local out = {}
	for k, v in data :: any do
		if not HIDDEN[k] then
			out[k] = v
		end
	end
	return out
end

-- Send changed top-level keys to the client
function DataService.push(player: Player, ...: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	local patch = {}
	for _, key in { ... } do
		patch[key] = (data :: any)[key]
	end
	Net.Server.fire("State", player, patch)
end

function DataService.pushAll(player: Player)
	local data = DataService.get(player)
	if data then
		Net.Server.fire("State", player, DataService.snapshot(data))
		Net.Server.fire("Inventory", player, "full", data.inventory)
	end
end

function DataService.pushInventory(player: Player, uid: string)
	local data = DataService.get(player)
	if data then
		Net.Server.fire("Inventory", player, "set", uid, data.inventory[uid])
	end
end

-------------------------------------------------------------------------------
-- Currency helpers (no multipliers here; see RewardService for boosted income)
-------------------------------------------------------------------------------
export type Currency = "coins" | "gems" | "tokens" | "essence" | "bossTokens"

function DataService.add(player: Player, currency: Currency, amount: number)
	local data = DataService.get(player)
	if not data or amount ~= amount or amount <= 0 then
		return
	end
	local d = data :: any
	d[currency] = math.floor((d[currency] or 0) + amount)
	if currency == "coins" then
		data.stats.coinsEarned += amount
	end
	DataService.push(player, currency)
	DataService.updateLeaderstats(player)
end

function DataService.canAfford(player: Player, currency: Currency, amount: number): boolean
	local data = DataService.get(player)
	return data ~= nil and ((data :: any)[currency] or 0) >= amount
end

function DataService.spend(player: Player, currency: Currency, amount: number): boolean
	local data = DataService.get(player)
	if not data or amount < 0 or amount ~= amount then
		return false
	end
	local d = data :: any
	if (d[currency] or 0) < amount then
		return false
	end
	d[currency] -= amount
	DataService.push(player, currency)
	DataService.updateLeaderstats(player)
	return true
end

-- Timed boosts ---------------------------------------------------------------
function DataService.boostActive(data: Types.PlayerData, id: string): boolean
	return (data.boosts[id] or 0) > now()
end

function DataService.addBoost(player: Player, id: string, minutes: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local start = math.max(now(), data.boosts[id] or 0)
	data.boosts[id] = start + math.floor(minutes * 60)
	DataService.push(player, "boosts")
end

function DataService.hasPass(player: Player, id: string): boolean
	local data = DataService.get(player)
	return data ~= nil and data.passes[id] == true
end

function DataService.newUid(data: Types.PlayerData): string
	local uid = tostring(data.nextUid)
	data.nextUid += 1
	return uid
end

-------------------------------------------------------------------------------
-- Leaderstats + public attributes (other clients read these)
-------------------------------------------------------------------------------
local leaderPower: { [Player]: number } = {}

function DataService.setPower(player: Player, power: number)
	leaderPower[player] = power
	DataService.updateLeaderstats(player)
end

function DataService.updateLeaderstats(player: Player)
	local data = DataService.get(player)
	local ls = player:FindFirstChild("leaderstats")
	if not data or not ls then
		return
	end
	local coins = ls:FindFirstChild("Coins") :: IntValue?
	local power = ls:FindFirstChild("Power") :: IntValue?
	if coins then
		coins.Value = math.min(data.coins, 2 ^ 53)
	end
	if power then
		power.Value = leaderPower[player] or 0
	end
end

local function makeLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = ls
	local power = Instance.new("IntValue")
	power.Name = "Power"
	power.Parent = ls
	ls.Parent = player
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	makeLeaderstats(player)
	local profile = store:Load(`player_{player.UserId}`, player.UserId, prepare)
	if not profile then
		player:Kick("Your data could not be loaded. Please rejoin in a moment (your progress is safe).")
		return
	end
	if not player.Parent then
		profile:Release()
		return
	end
	profiles[player] = profile
	profile.OnLockLost:Connect(function()
		player:Kick("Your data was opened on another server. Please rejoin.")
	end)
	local data = profile.Data :: Types.PlayerData
	local away = if data.lastOnline > 0 then now() - data.lastOnline else 0
	data.lastOnline = now()
	ready[player] = true
	DataService.Loaded:Fire(player, data, away)
	DataService.pushAll(player)
	DataService.updateLeaderstats(player)
end

local function release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data :: Types.PlayerData
	if ready[player] then
		DataService.Releasing:Fire(player, data)
		data.lastOnline = now()
	end
	ready[player] = nil
	profiles[player] = nil
	leaderPower[player] = nil
	profile:Release()
end

function DataService.init()
	store = SessionStore.new(GameConfig.DataStoreName)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(release)
	store:StartAutoSave(GameConfig.AutoSaveSeconds)
	-- keep lastOnline fresh so a server crash still pays sensible offline earnings
	task.spawn(function()
		while true do
			task.wait(30)
			for player, profile in profiles do
				if ready[player] then
					local data = profile.Data :: Types.PlayerData
					data.lastOnline = now()
					data.stats.playSeconds += 30
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and store.Mock then
			return
		end
		for _, player in Players:GetPlayers() do
			task.spawn(release, player)
		end
		store:ReleaseAll()
	end)
end

DataService._encode = function(v: any): string
	return HttpService:JSONEncode(v)
end

return DataService
