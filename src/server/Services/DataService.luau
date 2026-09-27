--!strict
-- Loads, saves and replicates player data. All other services read/write data through here.
-- Replication: services mutate DataService.get(player) and call markDirty(player, key);
-- dirty top-level keys are batched and pushed to that client once per frame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local DataTemplate = require(Shared.DataTemplate)
local Migrations = require(Shared.Migrations)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local SessionStore = require(script.Parent.Parent.Util.SessionStore)

local DataService = {}

-- Runtime-only state per player (never saved)
export type Session = {
	JoinClock: number,
	JoinUnix: number,
	Passes: { [string]: boolean },
	Zone: string?, -- zone the character is standing in ("Home" on islands)
	LastCatch: number,
	LastTeleport: number,
	LastJarFullNotice: number,
	Derived: { [string]: any },
	FriendBoost: number,
	Premium: boolean,
	GiftsClaimed: { [number]: boolean },
	Policy: { PaidRandomItemsRestricted: boolean, PaidItemTradingAllowed: boolean },
	Plot: number?,
	TradeLockedUntil: number,
	PendingInstantFusion: string?,
	PlayCounted: number, -- seconds of this session already added to Stats.PlaySeconds
}

DataService.Loaded = Signal.new() :: Signal.Signal<Player, Types.ProfileData>
DataService.Removing = Signal.new() :: Signal.Signal<Player, Types.ProfileData>

local store: any = nil
local profiles: { [Player]: SessionStore.Profile } = {}
local sessions: { [Player]: Session } = {}
local dirty: { [Player]: { [string]: boolean } } = {}

-- Keys that never go to the client, or are sanitised
local function clientValue(key: string, value: any): any
	if key == "Purchases" then
		return { StarterPack = value.StarterPack, FirstPurchaseAt = value.FirstPurchaseAt }
	end
	return value
end

function DataService.get(player: Player): Types.ProfileData?
	local p = profiles[player]
	return if p then p.Data else nil
end

function DataService.session(player: Player): Session?
	return sessions[player]
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Yields until the player's data is loaded (or they leave / timeout)
function DataService.waitFor(player: Player, timeout: number?): Types.ProfileData?
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.get(player)
end

function DataService.markDirty(player: Player, key: string)
	local d = dirty[player]
	if d then
		d[key] = true
	end
end

-- Push a runtime (non-saved) value to the client state under a pseudo-key
function DataService.pushSession(player: Player, key: string, value: any)
	Net.Server.fire("State", player, { [key] = value })
end

-- Forces an immediate save. Returns true if durably written.
function DataService.save(player: Player): boolean
	local p = profiles[player]
	if not p then
		return false
	end
	return p:Save()
end

local function unixNow(): number
	return DateTime.now().UnixTimestamp
end

local function prepare(raw: any): any
	local data = raw
	if type(data) ~= "table" then
		data = DataTemplate.new()
		return data
	end
	Migrations.migrate(data, Config.DataVersion, unixNow())
	Migrations.reconcile(data, DataTemplate.new() :: any)
	return data
end

local function onPlayerAdded(player: Player)
	sessions[player] = {
		JoinClock = os.clock(),
		JoinUnix = unixNow(),
		Passes = {},
		Zone = nil,
		LastCatch = 0,
		LastTeleport = 0,
		LastJarFullNotice = 0,
		Derived = {},
		FriendBoost = 0,
		Premium = player.MembershipType == Enum.MembershipType.Premium,
		GiftsClaimed = {},
		Policy = { PaidRandomItemsRestricted = true, PaidItemTradingAllowed = false }, -- safest defaults until fetched
		Plot = nil,
		TradeLockedUntil = 0,
		PendingInstantFusion = nil,
		PlayCounted = 0,
	}
	dirty[player] = {}

	local profile = store:Load(`Player_{player.UserId}`, player.UserId, prepare)
	if not profile then
		player:Kick("We couldn't load your data. Please rejoin in a moment. Your progress is safe.")
		return
	end
	if player.Parent ~= Players then
		profile:Release()
		return
	end
	profile.OnLockLost:Connect(function()
		profiles[player] = nil
		player:Kick("Your data was opened in another server. Please rejoin.")
	end)
	profiles[player] = profile

	local data: Types.ProfileData = profile.Data
	local now = unixNow()
	if data.FirstJoin == 0 then
		data.FirstJoin = now
	end
	data.LoginCount += 1
	-- LastLogin is updated by RetentionService after it reads the previous value

	-- Full initial sync
	local snapshot = {}
	for key, value in data :: any do
		snapshot[key] = clientValue(key, value)
	end
	snapshot.Loaded = true
	Net.Server.fire("State", player, snapshot)
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		local data: Types.ProfileData = profile.Data
		local session = sessions[player]
		if session then
			data.Stats.PlaySeconds += math.floor(os.clock() - session.JoinClock) - session.PlayCounted
			session.PlayCounted = math.floor(os.clock() - session.JoinClock)
		end
		data.LastLogout = unixNow()
		DataService.Removing:Fire(player, data)
		profiles[player] = nil
		profile:Release()
	end
	sessions[player] = nil
	dirty[player] = nil
end

function DataService.init()
	store = SessionStore.new(Config.DataStoreName)
	DataService.IsMock = store.Mock
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	-- Batched replication
	RunService.Heartbeat:Connect(function()
		for player, keys in dirty do
			if next(keys) then
				local profile = profiles[player]
				if profile then
					local payload = {}
					for key in keys do
						payload[key] = clientValue(key, (profile.Data :: any)[key])
					end
					Net.Server.fire("State", player, payload)
				end
				table.clear(keys)
			end
		end
	end)

	-- Track play time into saved stats every minute so crashes lose little
	task.spawn(function()
		while true do
			task.wait(60)
			for player, profile in profiles do
				local session = sessions[player]
				if session then
					local elapsed = math.floor(os.clock() - session.JoinClock)
					local data: Types.ProfileData = profile.Data
					data.Stats.PlaySeconds += elapsed - session.PlayCounted
					session.PlayCounted = elapsed
				end
			end
		end
	end)

	store:StartAutoSave(60)
	game:BindToClose(function()
		for player in profiles do
			task.spawn(onPlayerRemoving, player)
		end
		store:ReleaseAll()
	end)
end

return DataService
