--!strict
-- Pure rolling maths: rarity odds with luck, pity, mutation odds and Brainrot pick.
-- The server is the only caller that rolls for real; the client uses `odds()` for display.

local GameConfig = require(script.Parent.GameConfig)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Types)

local RollMath = {}

export type Rng = Random
export type Odds = { { rarity: Types.RarityDef, chance: number } }

-- Probability of each rarity at the given luck (luck multiplies luckAffected weights)
function RollMath.odds(luck: number, minOrder: number?): Odds
	local total = 0
	local rows: Odds = {}
	for _, r in Registry.Rarities do
		local w = if minOrder and r.order < minOrder then 0 else r.weight
		if r.luckAffected then
			w *= math.max(1, luck)
		end
		total += w
		table.insert(rows, { rarity = r, chance = w })
	end
	for _, row in rows do
		row.chance = if total > 0 then row.chance / total else 0
	end
	return rows
end

function RollMath.pickRarity(rng: Rng, luck: number, minOrder: number?): Types.RarityDef
	local rows = RollMath.odds(luck, minOrder)
	local x = rng:NextNumber()
	local acc = 0
	for _, row in rows do
		acc += row.chance
		if x < acc then
			return row.rarity
		end
	end
	-- floating point slack: return the rarest allowed
	for i = #rows, 1, -1 do
		if rows[i].chance > 0 then
			return rows[i].rarity
		end
	end
	return Registry.Rarities[1]
end

-- Luck nudges mutations slightly (square root) so it stays special
function RollMath.mutationOdds(luck: number): { { mutation: Types.MutationDef, chance: number } }
	local rows = {}
	local special = 0
	local boost = math.sqrt(math.max(1, luck))
	for i, m in Registry.Mutations do
		if i > 1 then
			local c = m.chance * boost
			special += c
			table.insert(rows, { mutation = m, chance = c })
		end
	end
	special = math.min(special, 0.6)
	local scale = 1
	local raw = 0
	for _, row in rows do
		raw += row.chance
	end
	if raw > 0 then
		scale = special / raw
	end
	for _, row in rows do
		row.chance *= scale
	end
	table.insert(rows, 1, { mutation = Registry.Mutations[1], chance = 1 - special })
	return rows
end

function RollMath.pickMutation(rng: Rng, luck: number): Types.MutationDef
	local x = rng:NextNumber()
	local acc = 0
	for _, row in RollMath.mutationOdds(luck) do
		acc += row.chance
		if x < acc then
			return row.mutation
		end
	end
	return Registry.Mutations[1]
end

function RollMath.pickBrainrot(rng: Rng, rarity: Types.RarityDef): Types.BrainrotDef
	local pool = Registry.RollPool[rarity.id]
	return pool[rng:NextInteger(1, #pool)]
end

-- Pity: is the next roll forced? `count` = rolls since the last minRarity-or-better result
function RollMath.pityForced(count: number): boolean
	return count + 1 >= GameConfig.Roll.Pity.threshold
end

function RollMath.pityMinOrder(): number
	return Registry.Rarity[GameConfig.Roll.Pity.minRarity].order
end

export type RollResult = {
	brainrot: Types.BrainrotDef,
	rarity: Types.RarityDef,
	mutation: Types.MutationDef,
	pityHit: boolean,
}

-- One complete roll. Returns the result and the new pity count.
function RollMath.roll(rng: Rng, luck: number, pityCount: number, forcedMinOrder: number?): (RollResult, number)
	local forced = RollMath.pityForced(pityCount)
	local minOrder = forcedMinOrder
	if forced then
		minOrder = math.max(minOrder or 0, RollMath.pityMinOrder())
	end
	local rarity = RollMath.pickRarity(rng, luck, minOrder)
	local brainrot = RollMath.pickBrainrot(rng, rarity)
	local mutation = RollMath.pickMutation(rng, luck)
	local newPity = if rarity.order >= RollMath.pityMinOrder() then 0 else pityCount + 1
	return { brainrot = brainrot, rarity = rarity, mutation = mutation, pityHit = forced }, newPity
end

return RollMath
