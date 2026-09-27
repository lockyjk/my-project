--!strict
-- Pure economy formulas. No Roblox services, no side effects, fully unit tested.
-- Every constant comes from Config; see DESIGN.md "Economy formulas".

local Config = require(script.Parent.Config)
local Defs = require(script.Parent.Defs)
local Types = require(script.Parent.Types)

local EconomyMath = {}

-------------------------------------------------------------------------------
-- Upgrades
-------------------------------------------------------------------------------

-- Cost to buy the next level when currently at `level`.
function EconomyMath.upgradeCost(def: Types.UpgradeDef, level: number): number
	return math.floor(def.baseCost * def.costGrowth ^ level)
end

function EconomyMath.upgradeValue(def: Types.UpgradeDef, level: number): number
	local v
	if def.mode == "linear" then
		v = def.base + def.perLevel * level
	else
		v = def.base * def.perLevel ^ level
	end
	if def.min then
		v = math.max(def.min, v)
	end
	if def.max then
		v = math.min(def.max, v)
	end
	return v
end

local function up(id: string, level: number): number
	return EconomyMath.upgradeValue(Defs.Upgrade[id], level)
end

function EconomyMath.jarCapacity(level: number, capacityBonus: number): number
	return math.floor(up("JarCapacity", level) * (1 + capacityBonus))
end

function EconomyMath.catchCooldown(level: number, speedBonus: number, speedPotion: number): number
	local def = Defs.Upgrade.CatchSpeed
	local cd = up("CatchSpeed", level) * math.max(0.4, 1 - speedBonus)
	return math.max((def.min or 0.1) * 0.8, cd / speedPotion)
end

function EconomyMath.walkSpeed(level: number, speedPotion: number): number
	return up("WalkSpeed", level) * speedPotion
end

function EconomyMath.catchRange(level: number): number
	return up("CatchRange", level)
end

-- Catch luck (shiny + direct pet drops)
function EconomyMath.catchLuck(level: number, additive: number, multiplier: number): number
	return (up("Luck", level) + additive) * multiplier
end

-------------------------------------------------------------------------------
-- Multipliers
-------------------------------------------------------------------------------

export type MultContext = {
	ascensions: number,
	petBonus: number, -- sum of equipped pet powers
	additive: number, -- asc tree + decorations + index + friend + premium
	doubleCharge: boolean,
	potion: number, -- 1 or potion mult
	storm: number, -- 1 or storm chargeMult
	event: number, -- 1 or live-event chargeMult
}

function EconomyMath.ascensionBonus(ascensions: number): number
	return ascensions * Config.Ascension.ChargeBonusPerAscension
end

function EconomyMath.chargeMultiplier(ctx: MultContext): number
	return (1 + EconomyMath.ascensionBonus(ctx.ascensions))
		* (1 + ctx.petBonus)
		* (1 + ctx.additive)
		* (if ctx.doubleCharge then 2 else 1)
		* ctx.potion
		* ctx.storm
		* ctx.event
end

function EconomyMath.zoneValueMult(zone: Types.ZoneDef, bestZoneMult: number): number
	if zone.bestZoneScale then
		return bestZoneMult * zone.bestZoneScale
	end
	return zone.valueMult
end

-- Static gained for one catch
function EconomyMath.spiritValue(baseValue: number, zoneMult: number, shiny: boolean, chargeMult: number): number
	local v = baseValue * zoneMult * chargeMult
	if shiny then
		v *= Config.Economy.ShinyValueMult
	end
	return math.max(1, math.floor(v + 0.5))
end

function EconomyMath.shinyChance(luck: number): number
	return math.min(0.5, Config.Economy.ShinyBaseChance * luck)
end

-- Rough online Charge/second for a player, used to scale time-based rewards.
function EconomyMath.estimatedIncomePerSecond(cooldown: number, zoneMult: number, chargeMult: number): number
	return (1 / cooldown) * Config.Economy.AvgSpiritValue * zoneMult * chargeMult * Config.Economy.IncomeEfficiency
end

function EconomyMath.minutesOfIncome(incomePerSecond: number, minutes: number): number
	return math.floor(incomePerSecond * 60 * minutes)
end

function EconomyMath.offlineEarnings(secondsAway: number, incomePerSecond: number, capHours: number): number
	if secondsAway < Config.Offline.MinSeconds then
		return 0
	end
	local seconds = math.min(secondsAway, capHours * 3600)
	return math.floor(seconds * incomePerSecond * Config.Offline.IncomeFraction)
end

-------------------------------------------------------------------------------
-- Ascension
-------------------------------------------------------------------------------

function EconomyMath.ascensionCost(ascensions: number): number
	return Config.Ascension.BaseCost * Config.Ascension.CostGrowth ^ ascensions
end

function EconomyMath.ascensionTokens(ascensions: number, charge: number): number
	local cost = EconomyMath.ascensionCost(ascensions)
	local base = Config.Ascension.BaseTokens + Config.Ascension.TokensPerAscension * ascensions
	local overflow = 0
	if charge > cost then
		overflow = math.min(Config.Ascension.OverflowTokenCap, math.floor(math.log(charge / cost, 2)))
	end
	return base + overflow
end

function EconomyMath.ascNodeCost(node: Types.AscNode, level: number): number
	return math.floor(node.cost * node.costGrowth ^ level + 0.5)
end

function EconomyMath.ascStat(tree: { [string]: number }, stat: string): number
	local total = 0
	for id, level in tree do
		local node = Defs.AscNode[id]
		if node and node.stat == stat then
			total += node.perLevel * math.min(level, node.maxLevel)
		end
	end
	return total
end

-------------------------------------------------------------------------------
-- Pets
-------------------------------------------------------------------------------

function EconomyMath.petPower(petId: string, tier: number): number
	local def = Defs.Pet[petId]
	if not def then
		return 0
	end
	local t = Config.Fusion.Tiers[math.clamp(tier, 1, #Config.Fusion.Tiers)]
	return def.power * t.powerMult
end

-- Sum the best `slots` powers from a list of pet powers (used for "equip best")
function EconomyMath.bestPowers(powers: { number }, slots: number): number
	local sorted = table.clone(powers)
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local total = 0
	for i = 1, math.min(slots, #sorted) do
		total += sorted[i]
	end
	return total
end

-- Score for the "rarest Stormling" leaderboard: rarity dominates, then tier, then power.
function EconomyMath.petScore(petId: string, tier: number): number
	local def = Defs.Pet[petId]
	if not def then
		return 0
	end
	return Defs.rarityOrder(def.rarity) * 1000 + tier * 100 + math.min(99, math.floor(math.log10(def.power + 1) * 10))
end

-------------------------------------------------------------------------------
-- Eggs / weighted random
-------------------------------------------------------------------------------

export type Odds = { pet: string, chance: number, baseChance: number }

-- Final odds for an egg. `luck` multiplies weights of Rare-or-better pets.
function EconomyMath.eggOdds(egg: Types.EggDef, luck: number): { Odds }
	local baseTotal, total = 0, 0
	local weights = {}
	for i, entry in egg.pets do
		local def = Defs.Pet[entry.pet]
		local w = entry.weight
		if def and Defs.rarityOrder(def.rarity) >= 3 then
			w *= luck
		end
		weights[i] = w
		baseTotal += entry.weight
		total += w
	end
	local out = {}
	for i, entry in egg.pets do
		table.insert(out, { pet = entry.pet, chance = weights[i] / total, baseChance = entry.weight / baseTotal })
	end
	return out
end

-- Pick from odds using a uniform [0,1) sample.
function EconomyMath.pickFromOdds(odds: { Odds }, u: number): string
	local acc = 0
	for _, o in odds do
		acc += o.chance
		if u < acc then
			return o.pet
		end
	end
	return odds[#odds].pet
end

function EconomyMath.pickWeighted(entries: { any }, u: number): number
	local total = 0
	for _, e in entries do
		total += e.weight
	end
	local target = u * total
	local acc = 0
	for i, e in entries do
		acc += e.weight
		if target < acc then
			return i
		end
	end
	return #entries
end

function EconomyMath.eggCost(egg: Types.EggDef, discount: number): number
	return math.floor(egg.cost * math.max(0.3, 1 - discount))
end

-------------------------------------------------------------------------------
-- Storm Pass
-------------------------------------------------------------------------------

function EconomyMath.passXPForTier(tier: number): number
	return Config.StormPass.XPBase + Config.StormPass.XPStep * (tier - 1)
end

-- Returns completed tier count (0..Tiers), XP into the next tier, XP needed for it
function EconomyMath.passTier(xp: number): (number, number, number)
	local remaining = xp
	for t = 1, Config.StormPass.Tiers do
		local need = EconomyMath.passXPForTier(t)
		if remaining < need then
			return t - 1, remaining, need
		end
		remaining -= need
	end
	return Config.StormPass.Tiers, 0, 0
end

function EconomyMath.passTotalXPForTier(tier: number): number
	local total = 0
	for t = 1, tier do
		total += EconomyMath.passXPForTier(t)
	end
	return total
end

-------------------------------------------------------------------------------
-- Leaderboard encoding (OrderedDataStore needs integers < 2^53)
-------------------------------------------------------------------------------

function EconomyMath.encodeLog(value: number): number
	if value <= 0 then
		return 0
	end
	return math.floor(math.log10(value + 1) * 1e8)
end

function EconomyMath.decodeLog(encoded: number): number
	return 10 ^ (encoded / 1e8) - 1
end

return EconomyMath
