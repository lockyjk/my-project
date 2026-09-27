--!strict
-- Computes each player's derived stats (capacity, cooldown, multipliers...) from saved data,
-- passes, potions, decorations, storms, events and social boosts. Everything that needs a
-- number like "current Charge multiplier" reads it from here, so there is one formula path.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local EconomyMath = require(Shared.EconomyMath)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local WeatherEventService = require(script.Parent.WeatherEventService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local StatsService = {}

export type Derived = {
	Capacity: number,
	Cooldown: number,
	WalkSpeed: number,
	Range: number,
	Luck: number, -- catch luck (shinies, pet drops)
	EggLuck: number, -- multiplies Rare+ egg weights
	ChargeMult: number,
	PetBonus: number,
	Additive: number,
	Slots: number,
	BestZoneMult: number,
	IncomePerSecond: number,
	OfflineHours: number,
	EggDiscount: number,
	FusionJobs: number,
	DoubleCatch: number,
	HoldToCatch: boolean,
	Boosts: { [string]: number }, -- active potion stat -> expiry
	Breakdown: { [string]: number }, -- for the UI "why is my multiplier X" panel
}

local function now(): number
	return DateTime.now().UnixTimestamp
end

function StatsService.decorationBonus(data: Types.ProfileData, stat: string): number
	local counts: { [string]: number } = {}
	local total = 0
	for _, placed in data.Island.Placed do
		local def = Defs.Decoration[placed.id]
		if def and def.boost and def.boost.stat == stat then
			counts[def.id] = (counts[def.id] or 0) + 1
			if counts[def.id] <= (def.maxBoosting or 1) then
				total += def.boost.amount
			end
		end
	end
	return total
end

function StatsService.equippedPetBonus(data: Types.ProfileData): number
	local total = 0
	for _, uid in data.Equipped do
		local pet = data.Pets[uid]
		if pet then
			total += EconomyMath.petPower(pet.id, pet.tier)
		end
	end
	return total
end

function StatsService.bestZoneMult(data: Types.ProfileData): number
	local best = 1
	for _, z in Defs.MainZones do
		if data.UnlockedZones[z.id] then
			best = math.max(best, z.valueMult)
		end
	end
	return best
end

function StatsService.potionMult(data: Types.ProfileData, stat: string): number
	local expiry = data.Boosts[stat]
	if expiry and expiry > now() then
		for _, p in Config.Potions do
			if p.stat == stat then
				return p.mult
			end
		end
	end
	return 1
end

function StatsService.compute(player: Player): Derived?
	local data = DataService.get(player)
	local session = DataService.session(player)
	if not data or not session then
		return nil
	end
	local passes = session.Passes
	local weather = WeatherEventService.current()
	local tree = data.AscTree

	local indexBonus = 0
	for _ in data.IndexRewards do
		indexBonus += Config.Index.ChargeBonusPerEgg
	end

	local breakdown = {
		Ascension = EconomyMath.ascensionBonus(data.Ascensions),
		Pets = StatsService.equippedPetBonus(data),
		Tree = EconomyMath.ascStat(tree, "Charge"),
		Decorations = StatsService.decorationBonus(data, "Charge"),
		Index = indexBonus,
		Friends = session.FriendBoost,
		Premium = if session.Premium then Config.Premium.ChargeBonus else 0,
		Storm = weather.chargeMult,
		Potion = StatsService.potionMult(data, "Charge"),
		DoubleCharge = if passes.DoubleCharge then 2 else 1,
	}
	local additive = breakdown.Tree + breakdown.Decorations + breakdown.Index + breakdown.Friends + breakdown.Premium
	local chargeMult = EconomyMath.chargeMultiplier({
		ascensions = data.Ascensions,
		petBonus = breakdown.Pets,
		additive = additive,
		doubleCharge = passes.DoubleCharge == true,
		potion = breakdown.Potion,
		storm = weather.chargeMult,
		event = 1, -- event multipliers are folded into weather.chargeMult
	})

	local speedPotion = StatsService.potionMult(data, "Speed")
	local luckPotion = StatsService.potionMult(data, "Luck")
	local vipLuck = if passes.VIP then Config.Hatch.VipLuckBonus else 0
	local capacity = EconomyMath.jarCapacity(
		data.Upgrades.JarCapacity or 0,
		EconomyMath.ascStat(tree, "Capacity") + StatsService.decorationBonus(data, "Capacity")
	)
	local cooldown = EconomyMath.catchCooldown(data.Upgrades.CatchSpeed or 0, EconomyMath.ascStat(tree, "CatchSpeed"), speedPotion)
	local luck = EconomyMath.catchLuck(
		data.Upgrades.Luck or 0,
		EconomyMath.ascStat(tree, "Luck") + StatsService.decorationBonus(data, "Luck") + vipLuck,
		luckPotion * weather.luckMult
	)
	local eggLuck = (1 + vipLuck + EconomyMath.ascStat(tree, "Luck") * 0.5)
		* (if passes.LuckyHatch then Config.Hatch.LuckyHatchMult else 1)
		* luckPotion
		* weather.luckMult
	local bestZone = StatsService.bestZoneMult(data)

	-- Offline/"minutes of income" estimates exclude temporary boosts (potions, storms)
	local steadyMult = chargeMult / (breakdown.Potion * weather.chargeMult)
	local baseCooldown = EconomyMath.catchCooldown(data.Upgrades.CatchSpeed or 0, EconomyMath.ascStat(tree, "CatchSpeed"), 1)

	local boosts = {}
	for stat, expiry in data.Boosts do
		if expiry > now() then
			boosts[stat] = expiry
		end
	end

	return {
		Capacity = capacity,
		Cooldown = cooldown,
		WalkSpeed = EconomyMath.walkSpeed(data.Upgrades.WalkSpeed or 0, speedPotion),
		Range = EconomyMath.catchRange(data.Upgrades.CatchRange or 0),
		Luck = luck,
		EggLuck = eggLuck,
		ChargeMult = chargeMult,
		PetBonus = breakdown.Pets,
		Additive = additive,
		Slots = Config.Economy.BaseEquipSlots
			+ (if passes.ExtraSlots then Config.Economy.PassExtraSlots else 0)
			+ math.floor(EconomyMath.ascStat(tree, "Slots")),
		BestZoneMult = bestZone,
		IncomePerSecond = EconomyMath.estimatedIncomePerSecond(baseCooldown, bestZone, steadyMult),
		OfflineHours = Config.Offline.BaseHours
			+ EconomyMath.ascStat(tree, "OfflineHours")
			+ StatsService.decorationBonus(data, "OfflineHours"),
		EggDiscount = EconomyMath.ascStat(tree, "EggDiscount"),
		FusionJobs = Config.Fusion.MaxJobs + math.floor(EconomyMath.ascStat(tree, "FusionJobs")),
		DoubleCatch = EconomyMath.ascStat(tree, "DoubleCatch"),
		HoldToCatch = (data.Upgrades.CatchSpeed or 0) >= Config.Economy.HoldToCatchLevel,
		Boosts = boosts,
		Breakdown = breakdown,
	}
end

function StatsService.get(player: Player): Derived?
	local session = DataService.session(player)
	if not session then
		return nil
	end
	if not session.Derived.Capacity then
		StatsService.refresh(player)
	end
	return session.Derived :: any
end

local function applyCharacter(player: Player, derived: Derived)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = derived.WalkSpeed
	end
end

function StatsService.refresh(player: Player)
	local derived = StatsService.compute(player)
	local session = DataService.session(player)
	if not derived or not session then
		return
	end
	session.Derived = derived :: any
	applyCharacter(player, derived)
	DataService.pushSession(player, "Derived", derived)
end

function StatsService.refreshAll()
	for _, p in Players:GetPlayers() do
		StatsService.refresh(p)
	end
end

function StatsService.init() end

function StatsService.start()
	DataService.Loaded:Connect(function(player)
		StatsService.refresh(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			local d = StatsService.get(player)
			if d then
				applyCharacter(player, d)
			end
		end)
		if player.Character then
			local d = StatsService.get(player)
			if d then
				applyCharacter(player, d)
			end
		end
	end)
	GameEvents.WeatherChanged:Connect(StatsService.refreshAll)
	-- Potions expire; re-check periodically
	task.spawn(function()
		while true do
			task.wait(5)
			local t = now()
			for _, player in Players:GetPlayers() do
				local session = DataService.session(player)
				local d = session and session.Derived
				if d and d.Boosts then
					for _, expiry in d.Boosts do
						if expiry <= t then
							StatsService.refresh(player)
							break
						end
					end
				end
			end
		end
	end)
end

return StatsService
