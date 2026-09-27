--!strict
-- Deterministic pacing simulator for an idealised free player (no passes, no potions, no storms).
-- Used by Pacing.spec to hold the balance targets, and by `scripts/simulate.sh` to print a timeline.
--
-- Player model: catches at 1/cooldown scaled by a movement factor, sells when the jar is full
-- (teleport home + back = SellTripSeconds), buys the next gate as soon as affordable, otherwise
-- the cheapest upgrade while it costs < SaveRatio of the next gate, and hatches a few eggs per zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))

local PacingSim = {}

export type Event = { t: number, text: string }
export type Result = {
	firstPurchase: number?,
	zoneTimes: { [number]: number },
	ascendTime: number?,
	events: { Event },
}

local SELL_TRIP = 7
local SELL_EVERY = 45 -- players head home at least this often even if the jar is not full
local SAVE_RATIO = 0.35
local EGGS_PER_ZONE = 6

function PacingSim.run(maxSeconds: number, seed: number?, verbose: boolean?): Result
	local rng = Random.new(seed or 7)
	local levels: { [string]: number } = {}
	for _, u in Config.Upgrades do
		levels[u.id] = 0
	end
	local charge, static = Config.Economy.StartingCharge, 0
	local zone = 1
	local pets: { number } = {}
	local catches = 0
	local sold = false
	local result: Result = { zoneTimes = { [1] = 0 }, events = {} }
	local function log(t: number, text: string)
		table.insert(result.events, { t = t, text = text })
	end

	local dt = 0.5
	local t = 0
	local tripLeft = 0
	local sinceSell = 0
	local catchAcc = 0
	local hatchedInZone = 0
	while t < maxSeconds do
		t += dt
		local zoneDef = Defs.MainZones[zone]
		local petBonus = EconomyMath.bestPowers(pets, Config.Economy.BaseEquipSlots)
		local mult = EconomyMath.chargeMultiplier({
			ascensions = 0,
			petBonus = petBonus,
			additive = 0,
			doubleCharge = false,
			potion = 1,
			storm = 1,
			event = 1,
		})
		local capacity = EconomyMath.jarCapacity(levels.JarCapacity, 0)
		local cooldown = EconomyMath.catchCooldown(levels.CatchSpeed, 0, 1)
		local walk = EconomyMath.walkSpeed(levels.WalkSpeed, 1)
		local range = EconomyMath.catchRange(levels.CatchRange)
		local movement = math.min(0.95, 0.6 * (walk / 18) ^ 0.3 * (range / 16) ^ 0.4)

		if verbose and t % 120 == 0 then
			log(t, string.format("  zone %d charge %.0f cap %d cd %.2f mv %.2f pets +%.2f lv %s", zone, charge, capacity, cooldown, movement, petBonus,
				`J{levels.JarCapacity} C{levels.CatchSpeed} W{levels.WalkSpeed} R{levels.CatchRange} L{levels.Luck}`))
		end
		if tripLeft > 0 then
			tripLeft -= dt
			if tripLeft <= 0 then
				charge += static
				static = 0
				if not sold then
					sold = true
					charge += Config.Tutorial.BonusCharge
				end
			end
		else
			catchAcc += dt / cooldown * movement
			while catchAcc >= 1 do
				catchAcc -= 1
				catches += 1
				local base = Config.Economy.AvgSpiritValue
				static = math.min(capacity, static + EconomyMath.spiritValue(base, zoneDef.valueMult, false, mult))
			end
			local tutorialSell = not sold and catches >= Config.Tutorial.CatchesNeeded
			sinceSell += dt
			if static >= capacity or tutorialSell or (sinceSell >= SELL_EVERY and static > 0) then
				tripLeft = SELL_TRIP
				sinceSell = 0
			end
		end

		-- spending
		local bought = true
		while bought do
			bought = false
			local nextZone = Defs.MainZones[zone + 1]
			if nextZone and charge >= nextZone.gateCost then
				charge -= nextZone.gateCost
				zone += 1
				hatchedInZone = 0
				result.zoneTimes[zone] = t
				log(t, `Unlocked {nextZone.name}`)
				bought = true
				continue
			end
			local egg = Defs.Egg[zoneDef.egg or ""]
			if egg and hatchedInZone < EGGS_PER_ZONE and charge >= egg.cost * 4 then
				charge -= egg.cost
				hatchedInZone += 1
				local odds = EconomyMath.eggOdds(egg, 1)
				local petId = EconomyMath.pickFromOdds(odds, rng:NextNumber())
				table.insert(pets, EconomyMath.petPower(petId, 1))
				bought = true
				continue
			end
			local cheapest, cheapestCost = nil, math.huge
			for _, u in Config.Upgrades do
				if levels[u.id] < u.maxLevel then
					local c = EconomyMath.upgradeCost(u, levels[u.id])
					if c < cheapestCost then
						cheapest, cheapestCost = u, c
					end
				end
			end
			local limit = if nextZone then nextZone.gateCost * SAVE_RATIO else math.huge
			limit = math.min(limit, EconomyMath.ascensionCost(0) * SAVE_RATIO)
			if cheapest and charge >= cheapestCost and cheapestCost <= limit then
				charge -= cheapestCost
				levels[cheapest.id] += 1
				if result.firstPurchase == nil then
					result.firstPurchase = t
					log(t, `First purchase: {cheapest.name}`)
				end
				bought = true
			end
		end

		if charge >= EconomyMath.ascensionCost(0) and result.ascendTime == nil then
			result.ascendTime = t
			log(t, "Can Ascend")
			break
		end
	end
	return result
end

return PacingSim
