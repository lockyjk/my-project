--!strict
-- Zones, gates, teleports, spirit spawning (pooled, capped, per-zone subscriptions),
-- server-validated catching and selling.
--
-- Spirits are logical server entities (id, type, position). Only clients in a zone receive
-- that zone's spirits; clients render them from a local model pool.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local EconomyMath = require(Shared.EconomyMath)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.WorldLayout)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local WeatherEventService = require(script.Parent.WeatherEventService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local ZoneService = {}

type Spirit = { id: number, def: string, zone: string, pos: Vector3, storm: boolean }
type ZoneState = {
	spirits: { [number]: Spirit },
	count: number,
	spawnAcc: number,
	subscribers: { [Player]: boolean },
}

local zoneStates: { [string]: ZoneState } = {}
local spiritIndex: { [number]: Spirit } = {}
local nextId = 0
local rng = Random.new()

-- Injected by PetService to avoid a require cycle (catch pet drops)
ZoneService.onPetDrop = nil :: ((Player, string) -> ())?
ZoneService.hasVip = function(_player: Player): boolean
	return false
end

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function root(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

function ZoneService.canAccess(player: Player, zoneId: string): boolean
	local data = DataService.get(player)
	local def = Defs.Zone[zoneId]
	if not data or not def then
		return false
	end
	if def.vipOnly then
		local session = DataService.session(player)
		return session ~= nil and session.Passes.VIP == true
	end
	return data.UnlockedZones[zoneId] == true
end

-------------------------------------------------------------------------------
-- Spirits
-------------------------------------------------------------------------------

local function encode(s: Spirit): { any }
	-- compact: {id, def, x, y, z}
	return { s.id, s.def, math.floor(s.pos.X * 10) / 10, math.floor(s.pos.Y * 10) / 10, math.floor(s.pos.Z * 10) / 10 }
end

local function subscribersOf(state: ZoneState): { Player }
	local list = {}
	for p in state.subscribers do
		table.insert(list, p)
	end
	return list
end

local function spawnTable(zone: Types.ZoneDef): { Types.SpawnEntry }
	local weather = WeatherEventService.current()
	if #weather.extraSpawns == 0 then
		return zone.spawns
	end
	local list = table.clone(zone.spawns)
	for _, extra in weather.extraSpawns do
		table.insert(list, extra)
	end
	return list
end

local function spawnOne(zone: Types.ZoneDef, state: ZoneState): Spirit
	local layout = WorldLayout.Zones[zone.id]
	local entries = spawnTable(zone)
	local pick = entries[EconomyMath.pickWeighted(entries, rng:NextNumber())]
	local def = Defs.Spirit[pick.spirit]
	local half = layout.size / 2 - 14
	local pos = layout.center
		+ Vector3.new(rng:NextNumber(-half, half), 2 + def.size * 0.6, rng:NextNumber(-half, half))
	nextId += 1
	local spirit: Spirit = { id = nextId, def = def.id, zone = zone.id, pos = pos, storm = def.storm ~= nil }
	state.spirits[spirit.id] = spirit
	state.count += 1
	spiritIndex[spirit.id] = spirit
	return spirit
end

local function removeSpirit(spirit: Spirit)
	local state = zoneStates[spirit.zone]
	if state.spirits[spirit.id] then
		state.spirits[spirit.id] = nil
		state.count -= 1
	end
	spiritIndex[spirit.id] = nil
end

local function targetCount(zone: Types.ZoneDef, state: ZoneState): number
	local players = 0
	for _ in state.subscribers do
		players += 1
	end
	if players == 0 then
		return 0
	end
	return math.min(zone.maxSpirits, zone.spiritsPerPlayer * players + 6)
end

local function spawnTick(dt: number)
	local weather = WeatherEventService.current()
	for _, zone in Config.Zones do
		local state = zoneStates[zone.id]
		local target = targetCount(zone, state)
		if state.count < target then
			state.spawnAcc += dt * weather.spawnMult / zone.respawnSeconds
			-- refill quickly when a zone is nearly empty (someone just arrived)
			if state.count < target * 0.5 then
				state.spawnAcc += 2
			end
			local batch = {}
			while state.spawnAcc >= 1 and state.count < target do
				state.spawnAcc -= 1
				table.insert(batch, encode(spawnOne(zone, state)))
			end
			if #batch > 0 then
				Net.Server.fireList("Spirits", subscribersOf(state), "spawn", zone.id, batch)
			end
		else
			state.spawnAcc = 0
		end
		-- Storm spirits vanish when their storm ends
		if not weather.storm then
			local gone = {}
			for id, s in state.spirits do
				if s.storm then
					table.insert(gone, id)
				end
			end
			if #gone > 0 then
				for _, id in gone do
					removeSpirit(state.spirits[id])
				end
				Net.Server.fireList("Spirits", subscribersOf(state), "despawn", zone.id, gone)
			end
		end
	end
end

local function setPlayerZone(player: Player, zoneId: string?)
	local session = DataService.session(player)
	if not session or session.Zone == zoneId then
		return
	end
	local old = session.Zone
	if old and zoneStates[old] then
		zoneStates[old].subscribers[player] = nil
	end
	session.Zone = zoneId
	DataService.pushSession(player, "Zone", zoneId or "")
	if zoneId and zoneStates[zoneId] then
		local state = zoneStates[zoneId]
		state.subscribers[player] = true
		local list = {}
		for _, s in state.spirits do
			table.insert(list, encode(s))
		end
		Net.Server.fire("Spirits", player, "snapshot", zoneId, list)
		local def = Defs.Zone[zoneId]
		if def and def.index > 0 and ZoneService.canAccess(player, zoneId) then
			local data = DataService.get(player)
			if data and data.LastZone ~= zoneId then
				data.LastZone = zoneId
				DataService.markDirty(player, "LastZone")
			end
		end
		GameEvents.ZoneEntered:Fire(player, zoneId)
	else
		Net.Server.fire("Spirits", player, "snapshot", "", {})
	end
end

-------------------------------------------------------------------------------
-- Catching & selling
-------------------------------------------------------------------------------

function ZoneService.catch(player: Player, spiritId: number): boolean
	local data = DataService.get(player)
	local session = DataService.session(player)
	local derived = StatsService.get(player)
	local spirit = spiritIndex[spiritId]
	local hrp = root(player)
	if not data or not session or not derived or not spirit or not hrp then
		return false
	end
	if not ZoneService.canAccess(player, spirit.zone) then
		return false
	end
	-- distance (flat) with latency slack
	local delta = hrp.Position - spirit.pos
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if flat > derived.Range + Config.Security.CatchRangeTolerance or math.abs(delta.Y) > 40 then
		return false
	end
	-- cooldown
	local t = os.clock()
	if t - session.LastCatch < derived.Cooldown * Config.Security.CatchCooldownTolerance then
		return false
	end
	-- jar
	if data.Static >= derived.Capacity then
		if session.Passes.AutoSell then
			CurrencyService.sell(player)
		else
			if t - session.LastJarFullNotice > 4 then
				session.LastJarFullNotice = t
				Net.Server.fire("Notify", player, "JarFull", "Your Storm Jar is full! Tap HOME to sell.")
			end
			return false
		end
	end
	session.LastCatch = t

	removeSpirit(spirit)
	local state = zoneStates[spirit.zone]
	Net.Server.fireList("Spirits", subscribersOf(state), "despawn", spirit.zone, { spirit.id })

	local def = Defs.Spirit[spirit.def]
	local zoneDef = Defs.Zone[spirit.zone]
	local zoneMult = EconomyMath.zoneValueMult(zoneDef, derived.BestZoneMult)
	local shiny = rng:NextNumber() < EconomyMath.shinyChance(derived.Luck)
	local amount = EconomyMath.spiritValue(def.value, zoneMult, shiny, derived.ChargeMult)
	if derived.DoubleCatch > 0 and rng:NextNumber() < derived.DoubleCatch then
		amount *= 2
	end
	local stored = CurrencyService.addStatic(player, amount)

	data.Stats.Caught += 1
	if shiny then
		data.Stats.Shinies += 1
	end
	if spirit.storm then
		data.Stats.StormCatches += 1
	end
	DataService.markDirty(player, "Stats")

	Net.Server.fire("CatchFx", player, spirit.id, stored, shiny, def.rarity)
	GameEvents.Caught:Fire(player, def.id, spirit.zone, shiny, stored, spirit.storm)

	-- Rare catch: storm spirits can drop a Stormling directly
	if def.petDrop and ZoneService.onPetDrop then
		local chance = def.petDrop.chance * derived.Luck
		if rng:NextNumber() < chance then
			ZoneService.onPetDrop(player, def.petDrop.pet)
		end
	end

	if session.Passes.AutoSell and data.Static >= derived.Capacity then
		CurrencyService.sell(player)
	end
	return true
end

local function sellCheck()
	for _, player in Players:GetPlayers() do
		local session = DataService.session(player)
		local data = DataService.get(player)
		local hrp = root(player)
		if session and data and hrp and session.Plot and data.Static > 0 then
			local plot = WorldLayout.Plots[session.Plot]
			local d = hrp.Position - plot.converter
			if Vector3.new(d.X, 0, d.Z).Magnitude <= Config.Security.SellRadius and math.abs(d.Y) < 12 then
				CurrencyService.sell(player)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Gates & teleports
-------------------------------------------------------------------------------

function ZoneService.unlock(player: Player, zoneId: string): (boolean, string?)
	local data = DataService.get(player)
	local def = Defs.Zone[zoneId]
	if not data or not def or def.index <= 0 then
		return false, "Unknown zone"
	end
	if data.UnlockedZones[zoneId] then
		return false, "Already unlocked"
	end
	local prev = Defs.MainZones[def.index - 1]
	if prev and not data.UnlockedZones[prev.id] then
		return false, `Unlock {prev.name} first`
	end
	if not CurrencyService.spend(player, def.gateCost, "Gate", zoneId) then
		return false, "Not enough Charge"
	end
	data.UnlockedZones[zoneId] = true
	DataService.markDirty(player, "UnlockedZones")
	StatsService.refresh(player)
	GameEvents.ZoneUnlocked:Fire(player, zoneId)
	Net.Server.fire("Notify", player, "ZoneUnlocked", def.name)
	return true
end

function ZoneService.teleport(player: Player, target: string): (boolean, string?)
	local session = DataService.session(player)
	local data = DataService.get(player)
	local character = player.Character
	if not session or not data or not character then
		return false, "Not ready"
	end
	if os.clock() - session.LastTeleport < Config.Economy.TeleportCooldown then
		return false, "Teleport recharging"
	end
	local cf: CFrame
	if target == "Home" then
		if not session.Plot then
			return false, "No island yet"
		end
		cf = WorldLayout.Plots[session.Plot].spawn
	elseif target == "Hub" then
		cf = CFrame.new(WorldLayout.Hub + Vector3.new(0, 5, 20))
	else
		if target == "Back" then
			target = data.LastZone
		end
		local layout = WorldLayout.Zones[target]
		if not layout or not ZoneService.canAccess(player, target) then
			return false, "Zone locked"
		end
		cf = layout.spawn
	end
	session.LastTeleport = os.clock()
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 5)
	end)
	character:PivotTo(cf)
	return true
end

-- Keep players out of zones they have not unlocked (e.g. glitching past a gate)
local function trackZones()
	for _, player in Players:GetPlayers() do
		local hrp = root(player)
		local session = DataService.session(player)
		if hrp and session and DataService.isLoaded(player) then
			local zoneId = WorldLayout.zoneAt(hrp.Position)
			if zoneId and not ZoneService.canAccess(player, zoneId) then
				local data = DataService.get(player)
				local back = if data then WorldLayout.Zones[data.LastZone] else nil
				if player.Character then
					player.Character:PivotTo((back or WorldLayout.Zones.DrizzleMeadows).spawn)
				end
				zoneId = if data then data.LastZone else "DrizzleMeadows"
			end
			if not zoneId and WorldLayout.plotAt(hrp.Position) then
				zoneId = nil
			end
			setPlayerZone(player, zoneId)
		end
	end
end

function ZoneService.spawnFor(player: Player): CFrame
	local data = DataService.get(player)
	local session = DataService.session(player)
	if data and not data.Flags.TutorialDone then
		return WorldLayout.Zones.DrizzleMeadows.spawn
	end
	if session and session.Plot then
		return WorldLayout.Plots[session.Plot].spawn
	end
	return WorldLayout.Zones.DrizzleMeadows.spawn
end

function ZoneService.init()
	for _, z in Config.Zones do
		zoneStates[z.id] = { spirits = {}, count = 0, spawnAcc = 0, subscribers = {} }
	end
end

function ZoneService.start()
	Net.Server.on("CatchSpirit", function(player: Player, spiritId: number)
		ZoneService.catch(player, spiritId)
	end)
	Net.Server.handle("UnlockZone", ZoneService.unlock)
	Net.Server.handle("Teleport", ZoneService.teleport)

	Players.PlayerRemoving:Connect(function(player)
		for _, state in zoneStates do
			state.subscribers[player] = nil
		end
	end)

	-- Move characters to the right spawn once data is loaded
	local function placeCharacter(player: Player, character: Model)
		task.defer(function()
			local hrp = character:WaitForChild("HumanoidRootPart", 10)
			if hrp and DataService.waitFor(player) then
				local cf = ZoneService.spawnFor(player)
				pcall(function()
					player:RequestStreamAroundAsync(cf.Position, 5)
				end)
				character:PivotTo(cf)
			end
		end)
	end
	DataService.Loaded:Connect(function(player)
		player.CharacterAdded:Connect(function(c)
			placeCharacter(player, c)
		end)
		if player.Character then
			placeCharacter(player, player.Character)
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local t = os.clock()
			spawnTick(t - last)
			last = t
			sellCheck()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			trackZones()
		end
	end)
end

ZoneService._now = now

return ZoneService
