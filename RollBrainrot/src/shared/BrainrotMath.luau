--!strict
-- Pure formulas for Brainrot stats, combat power, income, costs and player progression.
-- No Roblox services here, so everything is unit tested under Lune.

local GameConfig = require(script.Parent.GameConfig)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Types)

local BrainrotMath = {}

export type Stats = {
	hp: number,
	attack: number,
	defense: number,
	speed: number, -- studs/s
	range: number, -- studs
	cooldown: number,
}

local function mutationOf(id: string?): Types.MutationDef
	return Registry.Mutation[id or "Normal"] or Registry.Mutation.Normal
end

function BrainrotMath.levelMult(level: number): number
	return 1 + GameConfig.Leveling.StatPerLevel * (math.max(1, level) - 1)
end

function BrainrotMath.stats(def: Types.BrainrotDef, mutationId: string?, level: number): Stats
	local mult = mutationOf(mutationId).statMult * BrainrotMath.levelMult(level)
	return {
		hp = math.floor(def.hp * mult),
		attack = math.floor(def.attack * mult * 10 + 0.5) / 10,
		defense = math.floor(def.defense * mult),
		speed = GameConfig.SpeedTiers[def.speed] or 14,
		range = GameConfig.RangeTiers[def.range] or 4,
		cooldown = def.cooldown,
	}
end

-- One number that says "how strong is this Brainrot": damage per second, toughness, defence.
function BrainrotMath.combatPower(def: Types.BrainrotDef, mutationId: string?, level: number): number
	local s = BrainrotMath.stats(def, mutationId, level)
	return math.floor((s.attack / s.cooldown) * 5 + s.hp / 6 + s.defense * 1.5)
end

function BrainrotMath.instancePower(inst: Types.BrainrotInstance): number
	local def = Registry.Brainrot[inst.id]
	if not def then
		return 0
	end
	return BrainrotMath.combatPower(def, inst.mut, inst.lvl)
end

-- Coins per minute, before habitat/upgrade/decoration multipliers.
function BrainrotMath.baseIncome(def: Types.BrainrotDef, mutationId: string?, level: number): number
	local mut = mutationOf(mutationId)
	return def.zooIncome * mut.incomeMult * (1 + GameConfig.Leveling.IncomePerLevel * (math.max(1, level) - 1))
end

function BrainrotMath.sellValue(def: Types.BrainrotDef, mutationId: string?, level: number): number
	local mut = mutationOf(mutationId)
	return math.floor(def.sellValue * mut.incomeMult * (1 + 0.1 * (math.max(1, level) - 1)))
end

-- Cost of going from `level` to `level + 1`. Returns nil at max level.
function BrainrotMath.levelUpCost(def: Types.BrainrotDef, level: number): (number?, number?)
	local L = GameConfig.Leveling
	if level >= L.MaxLevel then
		return nil, nil
	end
	local rarity = Registry.Rarity[def.rarity]
	local coins = math.floor(L.BaseCoinCost * rarity.upgradeCostMult * L.CostGrowth ^ (level - 1))
	local essence = math.floor(L.EssencePerLevel * level * rarity.order / 2)
	return coins, essence
end

-------------------------------------------------------------------------------
-- Upgrades
-------------------------------------------------------------------------------
function BrainrotMath.upgradeValue(def: GameConfig.UpgradeDef, level: number): number
	return def.base + def.perLevel * math.clamp(level, 0, def.maxLevel)
end

function BrainrotMath.upgradeCost(def: GameConfig.UpgradeDef, level: number): number?
	if level >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.costGrowth ^ level)
end

-------------------------------------------------------------------------------
-- Habitats
-------------------------------------------------------------------------------
function BrainrotMath.habitatSlots(def: GameConfig.HabitatDef, level: number): number
	return def.baseSlots + def.slotsPerLevel * (math.max(1, level) - 1)
end

function BrainrotMath.habitatUpgradeCost(def: GameConfig.HabitatDef, level: number): number?
	if level >= def.maxLevel then
		return nil
	end
	return math.floor(def.upgradeBaseCost * def.upgradeGrowth ^ (level - 1))
end

function BrainrotMath.habitatIncomeMult(def: GameConfig.HabitatDef, level: number): number
	return 1 + def.incomePerLevel * (math.max(1, level) - 1)
end

-- Income of one Brainrot placed in a habitat (coins/min, before global multipliers)
function BrainrotMath.placedIncome(inst: Types.BrainrotInstance, habitat: GameConfig.HabitatDef, habitatLevel: number): number
	local def = Registry.Brainrot[inst.id]
	if not def then
		return 0
	end
	local affinity = if def.habitat == habitat.id then 1 + GameConfig.Zoo.AffinityBonus else 1
	return BrainrotMath.baseIncome(def, inst.mut, inst.lvl) * BrainrotMath.habitatIncomeMult(habitat, habitatLevel) * affinity
end

-------------------------------------------------------------------------------
-- Player
-------------------------------------------------------------------------------
function BrainrotMath.xpToNext(level: number): number
	local P = GameConfig.Player
	return math.floor(P.XpBase * level ^ P.XpExponent)
end

-- Adds xp; returns new level, leftover xp, levels gained
function BrainrotMath.applyXp(level: number, xp: number, gained: number): (number, number, number)
	local P = GameConfig.Player
	xp += gained
	local ups = 0
	while level < P.MaxLevel and xp >= BrainrotMath.xpToNext(level) do
		xp -= BrainrotMath.xpToNext(level)
		level += 1
		ups += 1
	end
	if level >= P.MaxLevel then
		xp = 0
	end
	return level, xp, ups
end

function BrainrotMath.playerMaxHealth(level: number, powerMult: number): number
	local P = GameConfig.Player
	return math.floor((P.BaseHealth + P.HealthPerLevel * (level - 1)) * powerMult)
end

function BrainrotMath.playerAttack(level: number, powerMult: number): number
	local P = GameConfig.Player
	return math.floor((P.BaseAttack + P.AttackPerLevel * (level - 1)) * powerMult)
end

-- Monster stats for a given arena + wave (+ world event multiplier)
function BrainrotMath.monsterScale(arenaStatMult: number, wave: number, waveGrowth: number, eventMult: number): number
	return arenaStatMult * (1 + waveGrowth * (wave - 1)) * eventMult
end

return BrainrotMath
