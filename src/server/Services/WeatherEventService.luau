--!strict
-- Server-wide storms (every Config.Weather.CycleSeconds, UTC aligned) and live events.
-- Pure schedule math lives in Shared/Schedule; this service broadcasts state changes and
-- exposes the combined modifiers the rest of the server applies.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Net = require(Shared.Net)
local Schedule = require(Shared.Schedule)
local Types = require(Shared.Types)

local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local WeatherEventService = {}

export type Modifiers = {
	storm: Types.StormDef?,
	events: { Types.LiveEventDef },
	chargeMult: number,
	spawnMult: number,
	luckMult: number,
	extraSpawns: { Types.SpawnEntry },
	stormEndsAt: number,
	nextStorm: string,
	nextStartsAt: number,
}

local current: Modifiers = {
	storm = nil,
	events = {},
	chargeMult = 1,
	spawnMult = 1,
	luckMult = 1,
	extraSpawns = {},
	stormEndsAt = 0,
	nextStorm = Config.Weather.Order[1],
	nextStartsAt = 0,
}
local lastKey = ""

-- Overrides for testing in Studio (/storm command)
local forcedStorm: string? = nil
local forcedUntil = 0

local function compute(now: number): Modifiers
	local state = Schedule.storm(now)
	local stormId = state.active
	local endsAt = state.endsAt
	if forcedStorm and now < forcedUntil then
		stormId = forcedStorm
		endsAt = forcedUntil
	end
	local storm = if stormId then Defs.Storm[stormId] else nil
	local events = Schedule.activeEvents(now)

	local m: Modifiers = {
		storm = storm,
		events = events,
		chargeMult = 1,
		spawnMult = 1,
		luckMult = 1,
		extraSpawns = {},
		stormEndsAt = endsAt,
		nextStorm = state.nextStorm,
		nextStartsAt = state.nextStartsAt,
	}
	if storm then
		m.chargeMult *= storm.chargeMult
		m.spawnMult *= storm.spawnMult
		m.luckMult *= Config.StormLuckMult[storm.id] or 1
		for _, s in storm.spirits do
			table.insert(m.extraSpawns, s)
		end
	end
	for _, ev in events do
		m.chargeMult *= ev.chargeMult or 1
		m.spawnMult *= ev.spawnMult or 1
		m.luckMult *= ev.luckMult or 1
		if ev.spirits then
			for _, s in ev.spirits do
				table.insert(m.extraSpawns, s)
			end
		end
	end
	return m
end

function WeatherEventService.current(): Modifiers
	return current
end

function WeatherEventService.isEventActive(eventId: string): boolean
	for _, ev in current.events do
		if ev.id == eventId then
			return true
		end
	end
	return false
end

function WeatherEventService.clientState(): { [string]: any }
	local eventIds = {}
	for _, ev in current.events do
		table.insert(eventIds, { id = ev.id, endsAt = ev.endUnix })
	end
	return {
		storm = if current.storm then current.storm.id else nil,
		stormEndsAt = current.stormEndsAt,
		nextStorm = current.nextStorm,
		nextStartsAt = current.nextStartsAt,
		events = eventIds,
	}
end

function WeatherEventService.forceStorm(stormId: string?, seconds: number)
	forcedStorm = stormId
	forcedUntil = DateTime.now().UnixTimestamp + seconds
end

local function tick()
	local now = DateTime.now().UnixTimestamp
	local m = compute(now)
	local eventKey = {}
	for _, ev in m.events do
		table.insert(eventKey, ev.id)
	end
	local key = `{if m.storm then m.storm.id else "-"}|{table.concat(eventKey, ",")}|{m.nextStartsAt}`
	current = m
	if key ~= lastKey then
		local stormStarted = m.storm ~= nil and not string.find(lastKey, m.storm.id, 1, true)
		lastKey = key
		Net.Server.fireAll("Weather", WeatherEventService.clientState())
		GameEvents.WeatherChanged:Fire()
		if stormStarted and m.storm then
			Net.Server.fireAll("Announce", `A {m.storm.name} rolls in! {m.storm.description}`, "Legendary")
		end
	end
end

function WeatherEventService.init() end

function WeatherEventService.start()
	tick()
	Players.PlayerAdded:Connect(function(player)
		Net.Server.fire("Weather", player, WeatherEventService.clientState())
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return WeatherEventService
