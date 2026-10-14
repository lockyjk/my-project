--!strict
-- Arena difficulties. All arenas share the one giant stadium; picking an arena re-themes the
-- battlefield (floor material, fog, sky tint) and scales every monster by statMult and every
-- reward by rewardMult. Unlock = level requirement + previous arena's boss defeated.
--
-- Waves are plain data. Monsters inside a wave also get +WaveGrowth stats per wave number.
local Types = require(script.Parent.Types)

local rgb = Color3.fromRGB

-- The classic 10-wave ladder: small monsters → elite → mini boss → giant boss.
local function standardWaves(boss: string, mix: { normal: string, fast: string, ranged: string }): { Types.WaveDef }
	return {
		{ spawns = { { monster = mix.normal, count = 10 } } },
		{ spawns = { { monster = mix.normal, count = 14 }, { monster = mix.fast, count = 6 } } },
		{ label = "ELITE", spawns = { { monster = "RockBrute", count = 1 }, { monster = mix.normal, count = 8 } } },
		{
			spawns = {
				{ monster = mix.normal, count = 16 },
				{ monster = mix.fast, count = 10 },
				{ monster = mix.ranged, count = 4 },
			},
		},
		{ label = "MINI BOSS", spawns = { { monster = "KingGoober", count = 1 }, { monster = mix.normal, count = 10 } } },
		{ spawns = { { monster = mix.fast, count = 16 }, { monster = mix.ranged, count = 8 } } },
		{
			label = "ELITES",
			spawns = {
				{ monster = "RockBrute", count = 3 },
				{ monster = mix.normal, count = 14 },
				{ monster = mix.ranged, count = 6 },
			},
		},
		{ spawns = { { monster = mix.fast, count = 20 }, { monster = mix.ranged, count = 10 } } },
		{
			label = "FINAL STAND",
			spawns = {
				{ monster = "RockBrute", count = 4 },
				{ monster = mix.fast, count = 14 },
				{ monster = mix.ranged, count = 10 },
			},
		},
		{ label = "GIANT BOSS", boss = true, spawns = { { monster = boss, count = 1 } } },
	}
end

local basicMix = { normal = "Goober", fast = "Imp", ranged = "Spitter" }

local list: { Types.ArenaDef } = {
	{
		id = "GreenFields",
		name = "Green Fields",
		order = 1,
		description = "A sunny battlefield. Perfect for your very first fight.",
		requiredLevel = 1,
		recommendedPower = 250,
		statMult = 1,
		rewardMult = 1,
		floorMaterial = Enum.Material.Grass,
		floorColor = rgb(96, 170, 70),
		skyTint = rgb(255, 255, 255),
		fogColor = rgb(200, 225, 255),
		waves = standardWaves("ForestTitan", basicMix),
	},
	{
		id = "DesertColosseum",
		name = "Desert Colosseum",
		order = 2,
		description = "Scorching sand and a colossus buried beneath it.",
		requiredLevel = 8,
		requiresArena = "GreenFields",
		recommendedPower = 1800,
		statMult = 6,
		rewardMult = 5,
		floorMaterial = Enum.Material.Sand,
		floorColor = rgb(226, 196, 130),
		skyTint = rgb(255, 235, 200),
		fogColor = rgb(255, 225, 170),
		waves = standardWaves("SandColossus", basicMix),
	},
	{
		id = "FrozenWasteland",
		name = "Frozen Wasteland",
		order = 3,
		description = "Blizzards, black ice and a colossus with a frozen heart.",
		requiredLevel = 16,
		requiresArena = "DesertColosseum",
		recommendedPower = 9000,
		statMult = 30,
		rewardMult = 22,
		floorMaterial = Enum.Material.Snow,
		floorColor = rgb(235, 245, 255),
		skyTint = rgb(210, 230, 255),
		fogColor = rgb(220, 235, 255),
		waves = standardWaves("IceColossus", basicMix),
	},
	{
		id = "VolcanicArena",
		name = "Volcanic Arena",
		order = 4,
		description = "Rivers of lava. Home of the Volcano Titan.",
		requiredLevel = 25,
		requiresArena = "FrozenWasteland",
		recommendedPower = 45000,
		statMult = 150,
		rewardMult = 100,
		floorMaterial = Enum.Material.Basalt,
		floorColor = rgb(60, 50, 50),
		skyTint = rgb(255, 180, 140),
		fogColor = rgb(120, 60, 40),
		waves = standardWaves("LavaBeast", basicMix),
	},
	{
		id = "VoidArena",
		name = "Void Arena",
		order = 5,
		description = "Reality is thin here. Something is watching.",
		requiredLevel = 35,
		requiresArena = "VolcanicArena",
		recommendedPower = 240000,
		statMult = 800,
		rewardMult = 450,
		floorMaterial = Enum.Material.Slate,
		floorColor = rgb(40, 30, 60),
		skyTint = rgb(200, 160, 255),
		fogColor = rgb(40, 20, 70),
		waves = standardWaves("VoidMonster", basicMix),
	},
	{
		id = "TitanArena",
		name = "Ancient Titan Arena",
		order = 6,
		description = "The final arena. The last dragon of the Titan Age awaits.",
		requiredLevel = 50,
		requiresArena = "VoidArena",
		recommendedPower = 1200000,
		statMult = 4000,
		rewardMult = 2000,
		floorMaterial = Enum.Material.Limestone,
		floorColor = rgb(230, 215, 170),
		skyTint = rgb(255, 225, 170),
		fogColor = rgb(255, 210, 150),
		waves = standardWaves("AncientDragon", basicMix),
	},
}

local byId: { [string]: Types.ArenaDef } = {}
for _, a in list do
	byId[a.id] = a
end

return {
	List = list,
	ById = byId,
	WaveGrowth = 0.08, -- +8% monster HP/attack per wave number
	IntermissionSeconds = 5,
	StartCountdown = 8,
	MaxAliveMonsters = 36, -- the rest of a wave trickles in as monsters die
	SpawnInterval = 0.35,
	WaveClearCoins = 20, -- × wave × rewardMult
	VictoryLingerSeconds = 12,
}
