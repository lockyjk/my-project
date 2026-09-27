--!strict
-- Default saved data for a brand new player. Missing keys in old saves are filled from this
-- by Migrations.reconcile, so adding a field here is enough for simple additions.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local DataTemplate = {}

function DataTemplate.new(): Types.ProfileData
	local upgrades = {}
	for _, u in Config.Upgrades do
		upgrades[u.id] = 0
	end
	return {
		DataVersion = Config.DataVersion,
		Charge = Config.Economy.StartingCharge,
		Static = 0,
		LifetimeCharge = 0,
		Upgrades = upgrades,
		UnlockedZones = { DrizzleMeadows = true },
		LastZone = "DrizzleMeadows",
		Pets = {},
		Equipped = {},
		Ascensions = 0,
		Tokens = 0,
		AscTree = {},
		Fusions = {},
		FusionSkips = 0,
		Index = {},
		IndexRewards = {},
		Achievements = {},
		Stats = {
			Caught = 0,
			Shinies = 0,
			StormCatches = 0,
			Hatched = 0,
			Fused = 0,
			Sold = 0,
			Upgrades = 0,
			Trades = 0,
			PlaySeconds = 0,
			DecorationsPlaced = 0,
			BestPetScore = 0,
			IndexCount = 0,
		},
		Daily = { Streak = 0, LastClaimDay = -1 },
		Quests = { DailyDay = -1, Daily = {}, WeeklyWeek = -1, Weekly = {} },
		Pass = { Season = "", XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
		Boosts = {},
		Potions = {},
		Island = { Size = 1, Placed = {}, Owned = {} },
		Purchases = { Receipts = {}, ReceiptOrder = {}, StarterPack = false, FirstPurchaseAt = 0, RobuxSpent = 0 },
		Flags = {},
		Settings = { AutoDelete = {}, Music = true, Sfx = true, AutoCatch = true, HidePets = false },
		FirstJoin = 0,
		LastLogin = 0,
		LastLogout = 0,
		LoginCount = 0,
		TradeHistory = {},
		EventProgress = {},
		BestPet = "",
		BestPetTier = 0,
	}
end

return DataTemplate
