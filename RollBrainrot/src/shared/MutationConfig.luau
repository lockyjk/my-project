--!strict
-- Mutations (variants) are rolled independently of rarity, so a Golden Bananini Bongo and a
-- Rainbow Cosmocorno are both possible. "Normal" must stay first; its chance takes up
-- whatever the other rows leave (chances are normalised).
local Types = require(script.Parent.Types)

local list: { Types.MutationDef } = {
	{ id = "Normal", order = 1, chance = 0.899, statMult = 1, incomeMult = 1, tintAlpha = 0, prefix = "" },
	{
		id = "Golden",
		order = 2,
		chance = 0.07,
		statMult = 2,
		incomeMult = 2,
		color = Color3.fromRGB(255, 200, 40),
		tintAlpha = 0.75,
		material = Enum.Material.Foil,
		reflectance = 0.25,
		sparkle = Color3.fromRGB(255, 230, 120),
		prefix = "Golden",
	},
	{
		id = "Diamond",
		order = 3,
		chance = 0.02,
		statMult = 5,
		incomeMult = 5,
		color = Color3.fromRGB(150, 240, 255),
		tintAlpha = 0.8,
		material = Enum.Material.Glass,
		reflectance = 0.35,
		sparkle = Color3.fromRGB(200, 250, 255),
		prefix = "Diamond",
	},
	{
		id = "Rainbow",
		order = 4,
		chance = 0.008,
		statMult = 10,
		incomeMult = 10,
		tintAlpha = 0.7,
		rainbow = true,
		sparkle = Color3.fromRGB(255, 255, 255),
		prefix = "Rainbow",
	},
	{
		id = "Shadow",
		order = 5,
		chance = 0.0025,
		statMult = 15,
		incomeMult = 15,
		color = Color3.fromRGB(28, 20, 40),
		tintAlpha = 0.85,
		material = Enum.Material.SmoothPlastic,
		sparkle = Color3.fromRGB(150, 60, 255),
		prefix = "Shadow",
	},
	{
		id = "Cosmic",
		order = 6,
		chance = 0.0005,
		statMult = 25,
		incomeMult = 25,
		color = Color3.fromRGB(40, 30, 120),
		tintAlpha = 0.8,
		material = Enum.Material.Neon,
		sparkle = Color3.fromRGB(120, 220, 255),
		prefix = "Cosmic",
	},
}

local byId: { [string]: Types.MutationDef } = {}
for _, m in list do
	byId[m.id] = m
end

return {
	List = list,
	ById = byId,
}
