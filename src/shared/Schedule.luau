--!strict
-- Pure time-based schedules: storms, live events, days/weeks, Storm Pass season.
-- Everything is derived from UTC unix time so every server agrees without messaging.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Schedule = {}

local DAY = 86400
local WEEK = 7 * DAY
local MONDAY_OFFSET = 4 * DAY -- 1970-01-01 was a Thursday

function Schedule.dayIndex(unix: number): number
	return math.floor(unix / DAY)
end

-- Weeks start Monday 00:00 UTC
function Schedule.weekIndex(unix: number): number
	return math.floor((unix - MONDAY_OFFSET) / WEEK)
end

function Schedule.secondsUntilNextDay(unix: number): number
	return DAY - unix % DAY
end

function Schedule.secondsUntilNextWeek(unix: number): number
	return WEEK - (unix - MONDAY_OFFSET) % WEEK
end

export type StormState = {
	active: string?, -- storm id while active
	slot: number,
	endsAt: number, -- when the active storm ends (or 0)
	nextStorm: string, -- next storm to start
	nextStartsAt: number,
}

function Schedule.stormForSlot(slot: number): string
	local order = Config.Weather.Order
	return order[slot % #order + 1]
end

function Schedule.storm(unix: number): StormState
	local cycle = Config.Weather.CycleSeconds
	local slot = math.floor(unix / cycle)
	local slotStart = slot * cycle
	local into = unix - slotStart
	local isActive = into < Config.Weather.ActiveSeconds
	return {
		active = if isActive then Schedule.stormForSlot(slot) else nil,
		slot = slot,
		endsAt = if isActive then slotStart + Config.Weather.ActiveSeconds else 0,
		nextStorm = Schedule.stormForSlot(slot + 1),
		nextStartsAt = slotStart + cycle,
	}
end

function Schedule.activeEvents(unix: number): { Types.LiveEventDef }
	local out = {}
	for _, ev in Config.LiveEvents do
		if unix >= ev.startUnix and unix < ev.endUnix then
			table.insert(out, ev)
		end
	end
	return out
end

-- Storm Pass seasons roll automatically every Config.StormPass.Days starting at StartUnix.
-- Returns (seasonIndex, secondsLeft). seasonIndex is 0 before the first season starts.
function Schedule.passSeason(unix: number): (number, number)
	local start = Config.StormPass.StartUnix
	local length = Config.StormPass.Days * DAY
	if unix < start then
		return 0, 0
	end
	local index = math.floor((unix - start) / length) + 1
	return index, start + index * length - unix
end

function Schedule.passSeasonId(index: number): string
	return "S" .. tostring(index)
end

function Schedule.passSeasonName(index: number): string
	local name = Config.StormPass.SeasonNames[index]
	return `Season {index}` .. (if name then ": " .. name else "")
end

return Schedule
