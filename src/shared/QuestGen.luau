--!strict
-- Deterministic quest rotation. Each player gets their own daily/weekly picks from a seed of
-- (period index, userId), so quests are stable across servers and rejoins within a period.
-- Targets scale with the player's progress so they stay meaningful. Pure + unit tested.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local QuestGen = {}

export type Context = {
	userId: number,
	incomePerSecond: number, -- steady Charge/s, for "Earn" quests
	unlockedZones: { string }, -- main zone ids the player can visit
}

local function niceRound(n: number): number
	if n < 10 then
		return math.max(1, math.floor(n + 0.5))
	end
	local magnitude = 10 ^ math.floor(math.log10(n))
	local step = magnitude / 2
	return math.floor(n / step + 0.5) * step
end

local function pool(daily: boolean): { Types.QuestTemplate }
	local out = {}
	for _, t in Config.Quests.Templates do
		if (daily and t.daily) or (not daily and t.weekly) then
			table.insert(out, t)
		end
	end
	return out
end

function QuestGen.target(template: Types.QuestTemplate, ctx: Context): number
	if template.kind == "Earn" then
		-- base = minutes of steady income
		return niceRound(math.max(100, ctx.incomePerSecond * 60 * template.base))
	end
	return niceRound(template.base * template.scale)
end

-- Generate `count` distinct quests for a period (day index or week index)
function QuestGen.generate(period: number, daily: boolean, ctx: Context): { Types.QuestState }
	local templates = pool(daily)
	local count = math.min(if daily then Config.Quests.DailyCount else Config.Quests.WeeklyCount, #templates)
	local rng = Random.new(period * 7919 + ctx.userId * 104729 + (if daily then 1 else 2))
	local picked: { Types.QuestState } = {}
	local usedKinds: { [string]: boolean } = {}
	local order = table.clone(templates)
	-- Fisher-Yates shuffle with the seeded RNG
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, t in order do
		if #picked >= count then
			break
		end
		if not usedKinds[t.kind] then
			usedKinds[t.kind] = true
			local zone: string? = nil
			if t.kind == "Explore" then
				if #ctx.unlockedZones == 0 then
					continue
				end
				zone = ctx.unlockedZones[rng:NextInteger(1, #ctx.unlockedZones)]
			end
			table.insert(picked, { template = t.id, target = QuestGen.target(t, ctx), progress = 0, claimed = false, zone = zone })
		end
	end
	return picked
end

-- Which quest kinds a game event advances. Returns the amount to add for a given quest.
function QuestGen.progressFor(template: Types.QuestTemplate, quest: Types.QuestState, kind: string, amount: number, zone: string?): number
	if template.kind == kind then
		if kind == "Explore" then
			return 0
		end
		return amount
	end
	-- Explore quests count catches inside the chosen zone
	if template.kind == "Explore" and kind == "Catch" and zone ~= nil and zone == quest.zone then
		return amount
	end
	return 0
end

QuestGen.niceRound = niceRound

return QuestGen
