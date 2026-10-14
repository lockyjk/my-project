--!strict
-- Rarity tiers, ordered from most common to rarest. Add a tier by appending a row: every
-- system (rolls, UI filters, colours, reveal effects, pity) reads this list.
--
-- weight      : base roll weight in percent (normalised, so they need not sum to 100)
-- luckAffected: luck multiplies this tier's weight before normalising
-- fxTier      : 1 simple, 2 blue, 3 purple, 4 gold + shake, 5 red/pink strong, 6 secret
local Types = require(script.Parent.Types)

local list: { Types.RarityDef } = {
	{
		id = "Common",
		order = 1,
		weight = 60,
		color = Color3.fromRGB(200, 204, 212),
		glow = Color3.fromRGB(255, 255, 255),
		luckAffected = false,
		fxTier = 1,
		sellMult = 1,
		upgradeCostMult = 1,
	},
	{
		id = "Uncommon",
		order = 2,
		weight = 25,
		color = Color3.fromRGB(92, 214, 104),
		glow = Color3.fromRGB(150, 255, 150),
		luckAffected = false,
		fxTier = 1,
		sellMult = 2,
		upgradeCostMult = 1.5,
	},
	{
		id = "Rare",
		order = 3,
		weight = 10,
		color = Color3.fromRGB(70, 150, 255),
		glow = Color3.fromRGB(120, 190, 255),
		luckAffected = true,
		fxTier = 2,
		sellMult = 4,
		upgradeCostMult = 2.5,
	},
	{
		id = "Epic",
		order = 4,
		weight = 4,
		color = Color3.fromRGB(178, 82, 255),
		glow = Color3.fromRGB(210, 140, 255),
		luckAffected = true,
		fxTier = 3,
		sellMult = 10,
		upgradeCostMult = 4,
	},
	{
		id = "Legendary",
		order = 5,
		weight = 0.8,
		color = Color3.fromRGB(255, 196, 40),
		glow = Color3.fromRGB(255, 230, 120),
		luckAffected = true,
		fxTier = 4,
		sellMult = 30,
		upgradeCostMult = 7,
	},
	{
		id = "Mythic",
		order = 6,
		weight = 0.19,
		color = Color3.fromRGB(255, 60, 120),
		glow = Color3.fromRGB(255, 130, 190),
		luckAffected = true,
		fxTier = 5,
		sellMult = 100,
		upgradeCostMult = 12,
	},
	{
		id = "Secret",
		order = 7,
		weight = 0.01,
		color = Color3.fromRGB(30, 255, 230),
		glow = Color3.fromRGB(190, 120, 255),
		luckAffected = true,
		fxTier = 6,
		sellMult = 500,
		upgradeCostMult = 20,
	},
}

local byId: { [string]: Types.RarityDef } = {}
for _, r in list do
	byId[r.id] = r
end

return {
	List = list,
	ById = byId,
}
