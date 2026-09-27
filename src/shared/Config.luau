--!strict
-- Storm Chaser Simulator: every balance value lives here.
-- Designers: edit numbers/tables in this file only. Adding a zone, pet, egg, storm, event,
-- decoration, quest or product needs no code changes elsewhere (ids must be unique).
-- Economy formulas that consume these values live in EconomyMath.luau (see DESIGN.md).

local Types = require(script.Parent.Types)

local rgb = Color3.fromRGB

local Config = {}

Config.GameName = "Storm Chaser Simulator"
Config.DataStoreName = "StormChaser_PlayerData_v1"
Config.DataVersion = 3

-------------------------------------------------------------------------------
-- Core economy
-------------------------------------------------------------------------------
Config.Economy = {
	StartingCharge = 0,
	SellRate = 1, -- Charge per Static converted
	ShinyBaseChance = 1 / 150, -- per catch, multiplied by luck
	ShinyValueMult = 5,
	HoldToCatchLevel = 2, -- Catch Speed level that unlocks hold-to-catch
	MaxPets = 300,
	BaseEquipSlots = 3,
	PassExtraSlots = 3,
	TeleportCooldown = 2,
	-- Fraction of theoretical income a real player achieves (walking between spirits, sell trips).
	-- Used for "N minutes of income" rewards and offline earnings.
	IncomeEfficiency = 0.55,
	AvgSpiritValue = 3.3, -- expected base value of a spawned spirit in a zone (for estimates)
	PassXPPerCatch = 0.2,
	PassXPPerHatch = 5,
}

Config.Tutorial = {
	CatchesNeeded = 6,
	BonusCharge = 25, -- granted after the first sell so the first upgrade is instantly affordable
}

-------------------------------------------------------------------------------
-- Rarities
-------------------------------------------------------------------------------
Config.Rarities = {
	{ id = "Common", name = "Common", order = 1, color = rgb(205, 212, 222), announce = false, shake = 0 },
	{ id = "Uncommon", name = "Uncommon", order = 2, color = rgb(92, 224, 112), announce = false, shake = 0 },
	{ id = "Rare", name = "Rare", order = 3, color = rgb(64, 156, 255), announce = false, shake = 0.2 },
	{ id = "Epic", name = "Epic", order = 4, color = rgb(176, 92, 255), announce = false, shake = 0.4 },
	{ id = "Legendary", name = "Legendary", order = 5, color = rgb(255, 196, 40), announce = true, shake = 0.7 },
	{ id = "Mythic", name = "Mythic", order = 6, color = rgb(255, 64, 140), announce = true, shake = 1 },
	{ id = "Secret", name = "Secret", order = 7, color = rgb(24, 255, 226), announce = true, shake = 1.4 },
} :: { Types.Rarity }

-------------------------------------------------------------------------------
-- Upgrade tracks (reset on Ascend)
-------------------------------------------------------------------------------
Config.Upgrades = {
	{
		id = "JarCapacity",
		name = "Storm Jar",
		description = "Hold more Static before you need to sell.",
		icon = "JAR",
		maxLevel = 60,
		baseCost = 15,
		costGrowth = 1.62,
		mode = "exp",
		base = 30,
		perLevel = 1.55,
		unit = "Static",
	},
	{
		id = "CatchSpeed",
		name = "Catch Rod",
		description = "Catch spirits faster. Level 2 unlocks hold-to-catch.",
		icon = "ROD",
		maxLevel = 30,
		baseCost = 20,
		costGrowth = 1.9,
		mode = "decay",
		base = 0.7,
		perLevel = 0.93,
		min = 0.12,
		unit = "s",
	},
	{
		id = "WalkSpeed",
		name = "Storm Boots",
		description = "Run faster between spirits.",
		icon = "BOOT",
		maxLevel = 20,
		baseCost = 30,
		costGrowth = 2.1,
		mode = "linear",
		base = 18,
		perLevel = 1.3,
		max = 44,
		unit = "speed",
	},
	{
		id = "CatchRange",
		name = "Vacuum Nozzle",
		description = "Reach spirits from further away.",
		icon = "RANGE",
		maxLevel = 20,
		baseCost = 40,
		costGrowth = 2.2,
		mode = "linear",
		base = 16,
		perLevel = 1.6,
		max = 48,
		unit = "studs",
	},
	{
		id = "Luck",
		name = "Lucky Charm",
		description = "More shiny spirits and rare pet drops.",
		icon = "LUCK",
		maxLevel = 25,
		baseCost = 75,
		costGrowth = 2.3,
		mode = "linear",
		base = 1,
		perLevel = 0.1,
		unit = "x",
	},
} :: { Types.UpgradeDef }

-------------------------------------------------------------------------------
-- Spirits
-------------------------------------------------------------------------------
local function spirit(
	id: string,
	name: string,
	value: number,
	rarity: string,
	color: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
	size: number
): Types.SpiritDef
	return { id = id, name = name, value = value, rarity = rarity, color = color, shape = shape, size = size }
end

Config.Spirits = {
	-- Drizzle Meadows
	spirit("Droplet", "Droplet", 2, "Common", rgb(120, 190, 255), "Ball", 2),
	spirit("PuffWisp", "Puff Wisp", 4, "Uncommon", rgb(235, 245, 255), "Block", 2.4),
	spirit("DrizzleSprite", "Drizzle Sprite", 10, "Rare", rgb(80, 140, 255), "Ball", 2.8),
	spirit("RainbowMote", "Rainbow Mote", 28, "Epic", rgb(255, 140, 220), "Block", 3.2),
	-- Breezy Bluffs
	spirit("Gustling", "Gustling", 2, "Common", rgb(200, 255, 230), "Block", 2.2),
	spirit("LeafTwirl", "Leaf Twirl", 4, "Uncommon", rgb(120, 220, 100), "Wedge", 2.6),
	spirit("Zephyr", "Zephyr", 10, "Rare", rgb(170, 255, 240), "Ball", 3),
	spirit("KiteWisp", "Kite Wisp", 28, "Epic", rgb(255, 120, 90), "Wedge", 3.4),
	-- Thunder Peaks
	spirit("Spark", "Spark", 2, "Common", rgb(255, 240, 90), "Ball", 2.4),
	spirit("StaticBolt", "Static Bolt", 4, "Uncommon", rgb(255, 210, 40), "Wedge", 2.8),
	spirit("Thunderhead", "Thunderhead", 10, "Rare", rgb(110, 110, 150), "Block", 3.4),
	spirit("BallLightning", "Ball Lightning", 28, "Epic", rgb(180, 240, 255), "Ball", 3.8),
	-- Hailstone Hollow
	spirit("Hailstone", "Hailstone", 2, "Common", rgb(225, 240, 255), "Ball", 2.6),
	spirit("SleetPip", "Sleet Pip", 4, "Uncommon", rgb(170, 200, 230), "Block", 3),
	spirit("IcePebble", "Ice Pebble", 10, "Rare", rgb(140, 220, 255), "Ball", 3.6),
	spirit("GlacierHeart", "Glacier Heart", 28, "Epic", rgb(60, 180, 255), "Block", 4),
	-- Frozen Squall
	spirit("FlakeSprite", "Flake Sprite", 2, "Common", rgb(255, 255, 255), "Wedge", 2.8),
	spirit("FrostWisp", "Frost Wisp", 4, "Uncommon", rgb(190, 235, 255), "Ball", 3.2),
	spirit("Whiteout", "Whiteout", 10, "Rare", rgb(240, 248, 255), "Block", 3.8),
	spirit("BlizzardCore", "Blizzard Core", 28, "Epic", rgb(90, 160, 255), "Ball", 4.4),
	-- Monsoon Marsh
	spirit("Raindrop", "Raindrop", 2, "Common", rgb(70, 130, 220), "Ball", 3),
	spirit("BogMist", "Bog Mist", 4, "Uncommon", rgb(130, 170, 120), "Block", 3.4),
	spirit("MonsoonEel", "Monsoon Eel", 10, "Rare", rgb(40, 110, 170), "Cylinder", 4),
	spirit("TyphoonPearl", "Typhoon Pearl", 28, "Epic", rgb(240, 230, 255), "Ball", 4.6),
	-- Sandstorm Dunes
	spirit("DustDevil", "Dust Devil", 2, "Common", rgb(230, 200, 140), "Cylinder", 3.2),
	spirit("GritSprite", "Grit Sprite", 4, "Uncommon", rgb(200, 160, 100), "Block", 3.6),
	spirit("Mirage", "Mirage", 10, "Rare", rgb(255, 230, 170), "Ball", 4.2),
	spirit("HaboobSpirit", "Haboob Spirit", 28, "Epic", rgb(180, 110, 60), "Block", 5),
	-- Aurora Rift
	spirit("AuroraRibbon", "Aurora Ribbon", 2, "Common", rgb(100, 255, 180), "Wedge", 3.4),
	spirit("StarGlimmer", "Star Glimmer", 4, "Uncommon", rgb(255, 250, 200), "Ball", 3.8),
	spirit("PolarVeil", "Polar Veil", 10, "Rare", rgb(160, 120, 255), "Block", 4.4),
	spirit("SolarFlare", "Solar Flare", 28, "Epic", rgb(255, 120, 40), "Ball", 5.2),
	-- Cyclone Canyon
	spirit("Whirl", "Whirl", 2, "Common", rgb(200, 220, 230), "Cylinder", 3.6),
	spirit("Updraft", "Updraft", 4, "Uncommon", rgb(160, 230, 255), "Wedge", 4),
	spirit("FunnelFiend", "Funnel Fiend", 10, "Rare", rgb(120, 130, 150), "Cylinder", 4.8),
	spirit("CycloneEye", "Cyclone Eye", 28, "Epic", rgb(90, 255, 200), "Ball", 5.6),
	-- Eye of the Storm
	spirit("CalmOrb", "Calm Orb", 2, "Common", rgb(230, 240, 255), "Ball", 3.8),
	spirit("StormCrown", "Storm Crown", 4, "Uncommon", rgb(255, 215, 80), "Block", 4.2),
	spirit("TempestWraith", "Tempest Wraith", 10, "Rare", rgb(90, 60, 160), "Wedge", 5),
	spirit("HeartOfStorm", "Heart of the Storm", 28, "Epic", rgb(255, 60, 120), "Ball", 6),
	-- Rainbow Lagoon (VIP side zone)
	spirit("PrismWisp", "Prism Wisp", 2.4, "Uncommon", rgb(255, 170, 255), "Block", 3),
	spirit("Halo", "Halo", 12, "Rare", rgb(255, 255, 180), "Cylinder", 3.6),
	-- Storm-only spirits (spawn in every zone while the storm is active, values scale with zone)
	spirit("Voltwing", "Voltwing", 40, "Legendary", rgb(255, 255, 120), "Wedge", 4),
	spirit("Frostfang", "Frostfang", 40, "Legendary", rgb(150, 230, 255), "Wedge", 4),
	spirit("AuroraMoth", "Aurora Moth", 40, "Legendary", rgb(130, 255, 200), "Wedge", 4),
	spirit("TwisterImp", "Twister Imp", 40, "Legendary", rgb(190, 190, 200), "Cylinder", 4),
	-- Live-event spirits
	spirit("PetalWisp", "Petal Wisp", 20, "Epic", rgb(255, 170, 200), "Ball", 3.4),
}

-- Direct pet drops from storm spirits ("rare catches"). Chance is per catch, multiplied by luck.
local petDrops: { [string]: { pet: string, chance: number } } = {
	Voltwing = { pet = "Voltling", chance = 1 / 400 },
	Frostfang = { pet = "Frostkit", chance = 1 / 400 },
	AuroraMoth = { pet = "Glowmoth", chance = 1 / 400 },
	TwisterImp = { pet = "Spinnaroo", chance = 1 / 400 },
}
for _, s in Config.Spirits do
	local drop = petDrops[s.id]
	if drop then
		s.petDrop = drop
	end
end
for _, id in { "Voltwing", "Frostfang", "AuroraMoth", "TwisterImp" } do
	for _, s in Config.Spirits do
		if s.id == id then
			s.storm = if id == "Voltwing"
				then "Thunderstorm"
				elseif id == "Frostfang" then "Blizzard"
				elseif id == "AuroraMoth" then "Aurora"
				else "Tornado"
		end
	end
end

-------------------------------------------------------------------------------
-- Zones (each ~4.3x the last). index 0 = VIP side zone.
-------------------------------------------------------------------------------
local function spawns(a: string, b: string, c: string, d: string): { Types.SpawnEntry }
	return {
		{ spirit = a, weight = 70 },
		{ spirit = b, weight = 22 },
		{ spirit = c, weight = 6.5 },
		{ spirit = d, weight = 1.5 },
	}
end

Config.Zones = {
	{
		id = "DrizzleMeadows",
		index = 1,
		name = "Drizzle Meadows",
		gateCost = 0,
		valueMult = 1,
		spawns = spawns("Droplet", "PuffWisp", "DrizzleSprite", "RainbowMote"),
		egg = "DrizzleEgg",
		maxSpirits = 40,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(120, 214, 110),
		accent = rgb(110, 180, 255),
	},
	{
		id = "BreezyBluffs",
		index = 2,
		name = "Breezy Bluffs",
		gateCost = 200,
		valueMult = 4,
		spawns = spawns("Gustling", "LeafTwirl", "Zephyr", "KiteWisp"),
		egg = "BreezeEgg",
		maxSpirits = 40,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(170, 230, 120),
		accent = rgb(200, 255, 235),
	},
	{
		id = "ThunderPeaks",
		index = 3,
		name = "Thunder Peaks",
		gateCost = 2500,
		valueMult = 17,
		spawns = spawns("Spark", "StaticBolt", "Thunderhead", "BallLightning"),
		egg = "ThunderEgg",
		maxSpirits = 42,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(96, 96, 124),
		accent = rgb(255, 230, 60),
	},
	{
		id = "HailstoneHollow",
		index = 4,
		name = "Hailstone Hollow",
		gateCost = 30000,
		valueMult = 75,
		spawns = spawns("Hailstone", "SleetPip", "IcePebble", "GlacierHeart"),
		egg = "HailEgg",
		maxSpirits = 42,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(190, 214, 235),
		accent = rgb(120, 200, 255),
	},
	{
		id = "FrozenSquall",
		index = 5,
		name = "Frozen Squall",
		gateCost = 300000,
		valueMult = 330,
		spawns = spawns("FlakeSprite", "FrostWisp", "Whiteout", "BlizzardCore"),
		egg = "FrostEgg",
		maxSpirits = 44,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(236, 244, 255),
		accent = rgb(90, 160, 255),
	},
	{
		id = "MonsoonMarsh",
		index = 6,
		name = "Monsoon Marsh",
		gateCost = 4e6,
		valueMult = 1450,
		spawns = spawns("Raindrop", "BogMist", "MonsoonEel", "TyphoonPearl"),
		egg = "MonsoonEgg",
		maxSpirits = 44,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(86, 140, 96),
		accent = rgb(60, 130, 220),
	},
	{
		id = "SandstormDunes",
		index = 7,
		name = "Sandstorm Dunes",
		gateCost = 1.5e8,
		valueMult = 6400,
		spawns = spawns("DustDevil", "GritSprite", "Mirage", "HaboobSpirit"),
		egg = "DuneEgg",
		maxSpirits = 46,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(236, 204, 140),
		accent = rgb(200, 120, 60),
	},
	{
		id = "AuroraRift",
		index = 8,
		name = "Aurora Rift",
		gateCost = 2e9,
		valueMult = 28000,
		spawns = spawns("AuroraRibbon", "StarGlimmer", "PolarVeil", "SolarFlare"),
		egg = "AuroraEgg",
		maxSpirits = 46,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(40, 50, 90),
		accent = rgb(100, 255, 180),
	},
	{
		id = "CycloneCanyon",
		index = 9,
		name = "Cyclone Canyon",
		gateCost = 3e10,
		valueMult = 124000,
		spawns = spawns("Whirl", "Updraft", "FunnelFiend", "CycloneEye"),
		egg = "CycloneEgg",
		maxSpirits = 48,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(150, 120, 100),
		accent = rgb(160, 230, 255),
	},
	{
		id = "EyeOfTheStorm",
		index = 10,
		name = "Eye of the Storm",
		gateCost = 4.5e11,
		valueMult = 550000,
		spawns = spawns("CalmOrb", "StormCrown", "TempestWraith", "HeartOfStorm"),
		egg = "EyeEgg",
		maxSpirits = 50,
		spiritsPerPlayer = 8,
		respawnSeconds = 1.2,
		ground = rgb(60, 40, 90),
		accent = rgb(255, 60, 120),
	},
	{
		id = "RainbowLagoon",
		index = 0,
		name = "Rainbow Lagoon (VIP)",
		gateCost = 0,
		valueMult = 1,
		vipOnly = true,
		bestZoneScale = 1.15, -- spirits are worth 1.15x your best unlocked zone
		spawns = {
			{ spirit = "PrismWisp", weight = 85 },
			{ spirit = "Halo", weight = 15 },
		},
		maxSpirits = 30,
		spiritsPerPlayer = 6,
		respawnSeconds = 1.2,
		ground = rgb(255, 200, 240),
		accent = rgb(160, 255, 255),
	},
} :: { Types.ZoneDef }

-------------------------------------------------------------------------------
-- Pets (Stormlings). power = additive Charge bonus at tier 1.
-- Zone egg pets use RarityPower[rarity] * EggPowerGrowth^(zone-1).
-------------------------------------------------------------------------------
Config.RarityPower = {
	Common = 0.10,
	Uncommon = 0.18,
	Rare = 0.35,
	Epic = 0.8,
	Legendary = 2.0,
	Mythic = 6,
	Secret = 25,
} :: { [string]: number }
Config.EggPowerGrowth = 2.4

Config.Pets = {} :: { Types.PetDef }

local function addPet(
	id: string,
	name: string,
	rarity: string,
	power: number,
	color: Color3,
	accent: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
	tradeable: boolean?
)
	table.insert(Config.Pets, {
		id = id,
		name = name,
		rarity = rarity,
		power = power,
		color = color,
		accent = accent,
		shape = shape,
		tradeable = if tradeable == nil then true else tradeable,
	})
end

type ZonePet = {
	id: string,
	name: string,
	rarity: string,
	weight: number,
	color: Color3,
	accent: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
}
type ZoneEgg = { egg: string, zone: number, cost: number, name: string, pets: { ZonePet } }

local function zp(
	id: string,
	name: string,
	rarity: string,
	weight: number,
	color: Color3,
	accent: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge"
): ZonePet
	return { id = id, name = name, rarity = rarity, weight = weight, color = color, accent = accent, shape = shape }
end

-- Zone eggs: weight = relative odds (the UI shows exact %). Power comes from rarity + zone.
local zoneEggs: { ZoneEgg } = {
	{
		egg = "DrizzleEgg",
		zone = 1,
		cost = 60,
		name = "Drizzle Egg",
		pets = {
			zp("DropletPup", "Droplet Pup", "Common", 60, rgb(120, 190, 255), rgb(255, 255, 255), "Ball"),
			zp("PuddleFrog", "Puddle Frog", "Uncommon", 28, rgb(90, 200, 150), rgb(40, 90, 70), "Block"),
			zp("MizzleMouse", "Mizzle Mouse", "Rare", 9, rgb(180, 200, 230), rgb(255, 150, 180), "Ball"),
			zp("RainbowSnail", "Rainbow Snail", "Epic", 2.5, rgb(255, 150, 220), rgb(255, 240, 120), "Block"),
			zp("DrizzleDrake", "Drizzle Drake", "Legendary", 0.5, rgb(60, 110, 255), rgb(190, 240, 255), "Wedge"),
		},
	},
	{
		egg = "BreezeEgg",
		zone = 2,
		cost = 250,
		name = "Breeze Egg",
		pets = {
			zp("GustBunny", "Gust Bunny", "Common", 60, rgb(235, 255, 245), rgb(160, 230, 200), "Ball"),
			zp("LeafFox", "Leaf Fox", "Uncommon", 28, rgb(130, 210, 90), rgb(255, 170, 70), "Wedge"),
			zp("KiteOwl", "Kite Owl", "Rare", 9, rgb(255, 130, 100), rgb(255, 230, 150), "Block"),
			zp("ZephyrCat", "Zephyr Cat", "Epic", 2.5, rgb(170, 255, 240), rgb(80, 150, 255), "Ball"),
			zp("Breezeback", "Breezeback Whale", "Legendary", 0.5, rgb(140, 200, 255), rgb(255, 255, 255), "Cylinder"),
		},
	},
	{
		egg = "ThunderEgg",
		zone = 3,
		cost = 1500,
		name = "Thunder Egg",
		pets = {
			zp("SparkChick", "Spark Chick", "Common", 60, rgb(255, 240, 90), rgb(255, 170, 40), "Ball"),
			zp("StaticPup", "Static Pup", "Uncommon", 27.5, rgb(255, 220, 60), rgb(90, 90, 120), "Block"),
			zp("BoltFerret", "Bolt Ferret", "Rare", 9, rgb(255, 250, 180), rgb(60, 60, 90), "Cylinder"),
			zp("ThunderRam", "Thunder Ram", "Epic", 3, rgb(110, 110, 150), rgb(255, 240, 80), "Block"),
			zp("Stormcaller", "Stormcaller Lion", "Legendary", 0.49, rgb(255, 200, 40), rgb(80, 60, 160), "Block"),
			zp("VoltaicDragon", "Voltaic Dragon", "Mythic", 0.01, rgb(80, 220, 255), rgb(255, 255, 120), "Wedge"),
		},
	},
	{
		egg = "HailEgg",
		zone = 4,
		cost = 9000,
		name = "Hail Egg",
		pets = {
			zp("HailHamster", "Hail Hamster", "Common", 60, rgb(230, 240, 255), rgb(200, 160, 120), "Ball"),
			zp("SleetSeal", "Sleet Seal", "Uncommon", 27.5, rgb(170, 200, 230), rgb(60, 70, 90), "Cylinder"),
			zp("PebblePenguin", "Pebble Penguin", "Rare", 9, rgb(40, 50, 70), rgb(255, 255, 255), "Ball"),
			zp("GlacierGoat", "Glacier Goat", "Epic", 3, rgb(140, 220, 255), rgb(240, 250, 255), "Block"),
			zp("HailHydra", "Hailstorm Hydra", "Legendary", 0.49, rgb(60, 170, 255), rgb(220, 255, 255), "Wedge"),
			zp("CrystalColossus", "Crystal Colossus", "Mythic", 0.01, rgb(180, 240, 255), rgb(120, 90, 255), "Block"),
		},
	},
	{
		egg = "FrostEgg",
		zone = 5,
		cost = 55000,
		name = "Frost Egg",
		pets = {
			zp("FlurryFox", "Flurry Fox", "Common", 60, rgb(255, 255, 255), rgb(150, 200, 255), "Wedge"),
			zp("FrostMoth", "Frost Moth", "Uncommon", 27.5, rgb(190, 235, 255), rgb(100, 160, 255), "Wedge"),
			zp("SnowshoeHare", "Snowshoe Hare", "Rare", 9, rgb(245, 245, 250), rgb(180, 140, 110), "Ball"),
			zp("IcicleYeti", "Icicle Yeti", "Epic", 3, rgb(220, 240, 255), rgb(60, 140, 255), "Block"),
			zp("BlizzardWolf", "Blizzard Wolf", "Legendary", 0.49, rgb(170, 200, 255), rgb(40, 60, 120), "Wedge"),
			zp("WhiteoutWyrm", "Whiteout Wyrm", "Mythic", 0.01, rgb(255, 255, 255), rgb(90, 200, 255), "Cylinder"),
		},
	},
	{
		egg = "MonsoonEgg",
		zone = 6,
		cost = 5e5,
		name = "Monsoon Egg",
		pets = {
			zp("RainNewt", "Rain Newt", "Common", 60, rgb(70, 160, 120), rgb(255, 200, 60), "Cylinder"),
			zp("MarshTurtle", "Marsh Turtle", "Uncommon", 27.5, rgb(90, 130, 80), rgb(160, 200, 120), "Block"),
			zp("MonsoonKoi", "Monsoon Koi", "Rare", 9, rgb(255, 130, 60), rgb(255, 255, 255), "Ball"),
			zp("TyphoonOtter", "Typhoon Otter", "Epic", 3, rgb(130, 90, 60), rgb(90, 170, 255), "Ball"),
			zp("TidalSerpent", "Tidal Serpent", "Legendary", 0.49, rgb(30, 110, 200), rgb(120, 255, 230), "Cylinder"),
			zp("DelugeLeviathan", "Deluge Leviathan", "Mythic", 0.01, rgb(20, 60, 140), rgb(100, 220, 255), "Wedge"),
		},
	},
	{
		egg = "DuneEgg",
		zone = 7,
		cost = 2e7,
		name = "Dune Egg",
		pets = {
			zp("DustMite", "Dust Mite", "Common", 60, rgb(220, 190, 140), rgb(120, 90, 60), "Ball"),
			zp("GritGecko", "Grit Gecko", "Uncommon", 27.5, rgb(200, 160, 90), rgb(90, 180, 90), "Wedge"),
			zp("MirageCamel", "Mirage Camel", "Rare", 9, rgb(240, 210, 150), rgb(255, 255, 220), "Block"),
			zp("HaboobHawk", "Haboob Hawk", "Epic", 3, rgb(170, 100, 50), rgb(255, 210, 120), "Wedge"),
			zp("SandSphinx", "Sandstorm Sphinx", "Legendary", 0.49, rgb(255, 210, 110), rgb(60, 110, 200), "Block"),
			zp("SciroccoScarab", "Scirocco Scarab", "Mythic", 0.01, rgb(40, 200, 150), rgb(255, 200, 40), "Ball"),
		},
	},
	{
		egg = "AuroraEgg",
		zone = 8,
		cost = 2.5e8,
		name = "Aurora Egg",
		pets = {
			zp("GlimmerBat", "Glimmer Bat", "Common", 60, rgb(60, 60, 110), rgb(255, 250, 200), "Wedge"),
			zp("VeilJelly", "Veil Jelly", "Uncommon", 27.5, rgb(170, 130, 255), rgb(120, 255, 220), "Ball"),
			zp("PolarLynx", "Polar Lynx", "Rare", 9, rgb(230, 240, 255), rgb(100, 255, 180), "Block"),
			zp("AuroraStag", "Aurora Stag", "Epic", 3, rgb(100, 255, 180), rgb(170, 110, 255), "Block"),
			zp("SolarPhoenix", "Solar Phoenix", "Legendary", 0.49, rgb(255, 120, 40), rgb(255, 240, 90), "Wedge"),
			zp("BorealisKirin", "Borealis Kirin", "Mythic", 0.01, rgb(80, 255, 200), rgb(255, 120, 255), "Wedge"),
		},
	},
	{
		egg = "CycloneEgg",
		zone = 9,
		cost = 3.5e9,
		name = "Cyclone Egg",
		pets = {
			zp("WhirlWeasel", "Whirl Weasel", "Common", 60, rgb(200, 210, 220), rgb(120, 130, 150), "Cylinder"),
			zp("UpdraftEagle", "Updraft Eagle", "Uncommon", 27.5, rgb(160, 120, 80), rgb(255, 255, 255), "Wedge"),
			zp("FunnelFox", "Funnel Fox", "Rare", 9, rgb(120, 130, 150), rgb(255, 150, 60), "Wedge"),
			zp("CycloneManta", "Cyclone Manta", "Epic", 3, rgb(60, 200, 190), rgb(20, 60, 80), "Wedge"),
			zp("VortexGriffin", "Vortex Griffin", "Legendary", 0.49, rgb(240, 200, 90), rgb(120, 220, 255), "Block"),
			zp("MaelstromTitan", "Maelstrom Titan", "Mythic", 0.01, rgb(40, 50, 80), rgb(90, 255, 230), "Block"),
		},
	},
	{
		egg = "EyeEgg",
		zone = 10,
		cost = 5e10,
		name = "Eye Egg",
		pets = {
			zp("CalmKitten", "Calm Kitten", "Common", 60, rgb(235, 240, 255), rgb(255, 190, 220), "Ball"),
			zp("CrownCorgi", "Crown Corgi", "Uncommon", 27.5, rgb(240, 170, 90), rgb(255, 220, 80), "Block"),
			zp("TempestStallion", "Tempest Stallion", "Rare", 9, rgb(80, 60, 150), rgb(200, 200, 255), "Block"),
			zp("EyewallOwl", "Eyewall Owl", "Epic", 3, rgb(60, 40, 90), rgb(255, 60, 120), "Ball"),
			zp("StormheartDragon", "Stormheart Dragon", "Legendary", 0.4899, rgb(255, 60, 120), rgb(255, 230, 120), "Wedge"),
			zp("EyeOfEternity", "Eye of Eternity", "Mythic", 0.01, rgb(255, 255, 255), rgb(255, 50, 100), "Ball"),
			zp("Nullstorm", "Nullstorm", "Secret", 0.0001, rgb(10, 10, 20), rgb(24, 255, 226), "Block"),
		},
	},
}

Config.Eggs = {} :: { Types.EggDef }
for _, row in zoneEggs do
	local entries: { Types.EggEntry } = {}
	for _, p in row.pets do
		local power = Config.RarityPower[p.rarity] * Config.EggPowerGrowth ^ (row.zone - 1)
		addPet(p.id, p.name, p.rarity, power, p.color, p.accent, p.shape)
		table.insert(entries, { pet = p.id, weight = p.weight })
	end
	local zoneId = ""
	for _, z in Config.Zones do
		if z.index == row.zone then
			zoneId = z.id
		end
	end
	table.insert(Config.Eggs, { id = row.egg, name = row.name, currency = "Charge", cost = row.cost, pets = entries, zone = zoneId })
end

-- Storm, special, premium and event pets (explicit power values)
addPet("Voltling", "Voltling", "Legendary", 30, rgb(255, 250, 120), rgb(80, 80, 140), "Wedge")
addPet("Frostkit", "Frostkit", "Legendary", 30, rgb(170, 230, 255), rgb(255, 255, 255), "Ball")
addPet("Glowmoth", "Glowmoth", "Legendary", 30, rgb(120, 255, 190), rgb(200, 120, 255), "Wedge")
addPet("Spinnaroo", "Spinnaroo", "Legendary", 30, rgb(190, 190, 200), rgb(90, 90, 110), "Cylinder")
addPet("StormPup", "Storm Pup", "Rare", 4, rgb(90, 100, 140), rgb(255, 240, 90), "Ball")
addPet("CloudCub", "Cloud Cub", "Epic", 9, rgb(240, 245, 255), rgb(160, 200, 255), "Ball")
addPet("GroupGust", "Group Gust", "Rare", 2, rgb(110, 220, 255), rgb(255, 255, 255), "Ball", false)
addPet("StarterSquall", "Starter Squall", "Epic", 4, rgb(90, 180, 255), rgb(255, 220, 80), "Block", false)
addPet("PassPup", "Pass Pup", "Epic", 12, rgb(255, 210, 90), rgb(90, 60, 200), "Ball", false)
addPet("SeasonSovereign", "Season Sovereign", "Mythic", 150, rgb(255, 215, 80), rgb(255, 60, 140), "Wedge", false)
addPet("StreakSprite", "Streak Sprite", "Rare", 3, rgb(255, 170, 60), rgb(255, 255, 255), "Ball")
addPet("StreakSerpent", "Streak Serpent", "Epic", 8, rgb(255, 120, 60), rgb(255, 230, 120), "Cylinder")
addPet("StreakPhoenix", "Streak Phoenix", "Legendary", 20, rgb(255, 90, 40), rgb(255, 240, 90), "Wedge")
addPet("TempestTiger", "Tempest Tiger", "Epic", 10, rgb(255, 140, 40), rgb(40, 40, 60), "Block")
addPet("TempestTitan", "Tempest Titan", "Legendary", 25, rgb(60, 60, 110), rgb(255, 230, 80), "Block")
addPet("TempestQueen", "Tempest Queen", "Mythic", 80, rgb(200, 90, 255), rgb(255, 255, 255), "Wedge")
addPet("PetalPuff", "Petal Puff", "Rare", 3, rgb(255, 180, 210), rgb(255, 255, 255), "Ball")
addPet("BlossomBear", "Blossom Bear", "Epic", 7, rgb(255, 150, 190), rgb(120, 200, 90), "Block")
addPet("SpringSylph", "Spring Sylph", "Legendary", 22, rgb(170, 255, 170), rgb(255, 160, 220), "Wedge")

local extraEggs: { Types.EggDef } = {
	-- Storm eggs: Charge-priced, hatchable only during their storm at the Storm Altar.
	{
		id = "StormEgg",
		name = "Storm Egg",
		currency = "Charge",
		cost = 2500,
		storm = "*", -- any active storm
		zone = "DrizzleMeadows",
		pets = {
			{ pet = "StormPup", weight = 70 },
			{ pet = "CloudCub", weight = 27 },
			{ pet = "Voltling", weight = 0.75 },
			{ pet = "Frostkit", weight = 0.75 },
			{ pet = "Glowmoth", weight = 0.75 },
			{ pet = "Spinnaroo", weight = 0.75 },
		},
	},
	-- Day-7 login streak egg: free, guaranteed Rare or better.
	{
		id = "StreakEgg",
		name = "Streak Egg",
		currency = "Free",
		cost = 0,
		hidden = true,
		pets = {
			{ pet = "StreakSprite", weight = 70 },
			{ pet = "StreakSerpent", weight = 25 },
			{ pet = "StreakPhoenix", weight = 5 },
		},
	},
	-- Premium (paid random item). Odds are always shown before purchase.
	-- No Secret pets in paid eggs by design.
	{
		id = "TempestEgg",
		name = "Tempest Egg",
		currency = "Robux",
		cost = 0,
		product = "TempestEgg1",
		zone = "DrizzleMeadows",
		pets = {
			{ pet = "TempestTiger", weight = 75 },
			{ pet = "TempestTitan", weight = 23 },
			{ pet = "TempestQueen", weight = 2 },
		},
	},
	-- Live event egg (see LiveEvents)
	{
		id = "BlossomEgg",
		name = "Blossom Egg",
		currency = "Charge",
		cost = 5000,
		event = "BlossomBreeze",
		zone = "DrizzleMeadows",
		pets = {
			{ pet = "PetalPuff", weight = 75 },
			{ pet = "BlossomBear", weight = 23.5 },
			{ pet = "SpringSylph", weight = 1.5 },
		},
	},
}
for _, e in extraEggs do
	table.insert(Config.Eggs, e)
end

-- Players in regions where paid random items are restricted (PolicyService) cannot buy Robux eggs.
-- If a Robux egg receipt ever arrives for them anyway, they get this fixed (non-random) pet instead.
Config.RestrictedEggFallbackPet = "TempestTiger"

Config.Hatch = {
	AnimationSeconds = 3.2,
	FastAnimationSeconds = 1.2, -- Faster Hatch pass
	TripleHatchAscensions = 1, -- x3 hatch unlocks after the first Ascension
	StandRadius = 22, -- studs from an egg stand to hatch
	LuckyHatchMult = 1.5, -- Lucky Hatch pass: rare-or-better weights x1.5
	VipLuckBonus = 0.2,
}

-------------------------------------------------------------------------------
-- Fusion: 3 identical Stormlings (same pet + tier) -> 1 of the next tier
-------------------------------------------------------------------------------
Config.Fusion = {
	Required = 3,
	MaxJobs = 1, -- + AscTree "FusionBay"
	Tiers = {
		{ name = "Base", powerMult = 1, seconds = 0, scale = 1 },
		{ name = "Charged", powerMult = 3.5, seconds = 120, scale = 1.25 },
		{ name = "Supercharged", powerMult = 12.25, seconds = 600, scale = 1.5 },
		{ name = "Tempest", powerMult = 43, seconds = 2400, scale = 1.8 },
	},
}

-------------------------------------------------------------------------------
-- Ascension (rebirth)
-------------------------------------------------------------------------------
Config.Ascension = {
	BaseCost = 2e8,
	CostGrowth = 4.5,
	ChargeBonusPerAscension = 0.6, -- +60% Charge per Ascension (additive)
	BaseTokens = 3,
	TokensPerAscension = 1, -- later ascensions give more tokens
	OverflowTokenCap = 5, -- +1 token per doubling of Charge above the cost
	KeepsZones = true,
	KeepsPets = true,
}

Config.AscTree = {
	{ id = "StormHeart", name = "Storm Heart", description = "+15% Charge", maxLevel = 25, cost = 1, costGrowth = 1.25, stat = "Charge", perLevel = 0.15 },
	{ id = "DeepJar", name = "Deep Jar", description = "+20% jar capacity", maxLevel = 15, cost = 1, costGrowth = 1.3, stat = "Capacity", perLevel = 0.2 },
	{ id = "QuickRod", name = "Quick Rod", description = "-3% catch cooldown", maxLevel = 10, cost = 2, costGrowth = 1.3, stat = "CatchSpeed", perLevel = 0.03 },
	{ id = "LuckyClouds", name = "Lucky Clouds", description = "+10% luck", maxLevel = 15, cost = 2, costGrowth = 1.3, stat = "Luck", perLevel = 0.1 },
	{ id = "HeadStart", name = "Head Start", description = "Start each Ascension with +1 level in every upgrade", maxLevel = 5, cost = 3, costGrowth = 1.6, stat = "HeadStart", perLevel = 1, requires = "StormHeart" },
	{ id = "DoubleCatch", name = "Double Catch", description = "+4% chance to catch double", maxLevel = 10, cost = 3, costGrowth = 1.4, stat = "DoubleCatch", perLevel = 0.04, requires = "QuickRod" },
	{ id = "ExtraSlot", name = "Stormling Leash", description = "+1 pet equip slot", maxLevel = 3, cost = 6, costGrowth = 2, stat = "Slots", perLevel = 1, requires = "LuckyClouds" },
	{ id = "SkyCellar", name = "Sky Cellar", description = "+1h offline earnings cap", maxLevel = 8, cost = 2, costGrowth = 1.35, stat = "OfflineHours", perLevel = 1 },
	{ id = "EggBargain", name = "Egg Bargain", description = "-4% Charge egg cost", maxLevel = 10, cost = 2, costGrowth = 1.35, stat = "EggDiscount", perLevel = 0.04 },
	{ id = "FusionBay", name = "Fusion Bay", description = "+1 simultaneous fusion", maxLevel = 2, cost = 5, costGrowth = 2, stat = "FusionJobs", perLevel = 1, requires = "EggBargain" },
} :: { Types.AscNode }

-------------------------------------------------------------------------------
-- Weather storms: server-wide, every CycleSeconds aligned to UTC so players can plan
-------------------------------------------------------------------------------
Config.Weather = {
	CycleSeconds = 600,
	ActiveSeconds = 240,
	Order = { "Thunderstorm", "Blizzard", "Aurora", "Tornado" },
	StormSpiritWeight = 3, -- weight of the storm spirit added to each zone's table (base total = 100)
}

Config.Storms = {
	{
		id = "Thunderstorm",
		name = "Thunderstorm",
		description = "Voltwings crackle through every zone. +50% Charge!",
		chargeMult = 1.5,
		spawnMult = 1.3,
		spirits = { { spirit = "Voltwing", weight = 3 } },
		sky = rgb(60, 60, 90),
		fog = rgb(90, 90, 120),
	},
	{
		id = "Blizzard",
		name = "Blizzard",
		description = "Frostfangs ride the snow. Spirits spawn twice as fast!",
		chargeMult = 1.25,
		spawnMult = 2,
		spirits = { { spirit = "Frostfang", weight = 3 } },
		sky = rgb(200, 220, 240),
		fog = rgb(230, 240, 255),
	},
	{
		id = "Aurora",
		name = "Aurora",
		description = "Aurora Moths glow overhead. Double luck!",
		chargeMult = 1.25,
		spawnMult = 1.3,
		spirits = { { spirit = "AuroraMoth", weight = 3 } },
		sky = rgb(30, 40, 80),
		fog = rgb(60, 120, 110),
	},
	{
		id = "Tornado",
		name = "Tornado",
		description = "Twister Imps spin everywhere. +75% Charge!",
		chargeMult = 1.75,
		spawnMult = 1.5,
		spirits = { { spirit = "TwisterImp", weight = 3 } },
		sky = rgb(120, 120, 110),
		fog = rgb(150, 145, 130),
	},
} :: { Types.StormDef }
Config.StormLuckMult = { Aurora = 2 } :: { [string]: number }

-------------------------------------------------------------------------------
-- Live / seasonal events: add a table entry, nothing else. Times are UTC unix seconds.
-------------------------------------------------------------------------------
Config.LiveEvents = {
	{
		id = "BlossomBreeze",
		name = "Blossom Breeze",
		description = "Petal Wisps drift through every zone and the Blossom Egg is open!",
		startUnix = 1774224000, -- 2026-03-23 00:00 UTC
		endUnix = 1775433600, -- 2026-04-06 00:00 UTC
		chargeMult = 1.2,
		spawnMult = 1.1,
		spirits = { { spirit = "PetalWisp", weight = 2 } },
		egg = "BlossomEgg",
		color = rgb(255, 170, 210),
	},
} :: { Types.LiveEventDef }

-------------------------------------------------------------------------------
-- Retention
-------------------------------------------------------------------------------
Config.DailyStreak = {
	-- index = streak day (1..7); after day 7 the cycle repeats and keeps the streak count
	Rewards = {
		{ chargeMinutes = 3 },
		{ potions = { LuckPotion = 1 } },
		{ chargeMinutes = 8, passXP = 100 },
		{ potions = { ChargePotion = 1 } },
		{ chargeMinutes = 15 },
		{ potions = { SpeedPotion = 2 }, fusionSkips = 1 },
		{ egg = "StreakEgg", chargeMinutes = 20 },
	} :: { Types.Reward },
}

Config.Gifts = {
	-- session playtime (minutes) -> reward
	{ minutes = 5, reward = { chargeMinutes = 2 } :: Types.Reward },
	{ minutes = 10, reward = { potions = { SpeedPotion = 1 } } :: Types.Reward },
	{ minutes = 15, reward = { chargeMinutes = 5 } :: Types.Reward },
	{ minutes = 30, reward = { potions = { LuckPotion = 1 }, passXP = 150 } :: Types.Reward },
	{ minutes = 60, reward = { potions = { ChargePotion = 1 }, chargeMinutes = 15, fusionSkips = 1 } :: Types.Reward },
}

Config.Quests = {
	DailyCount = 3,
	WeeklyCount = 5,
	Templates = {
		{ id = "D_Catch", kind = "Catch", text = "Catch {n} spirits", base = 150, scale = 1, reward = { chargeMinutes = 5, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Shiny", kind = "CatchShiny", text = "Catch {n} shiny spirits", base = 2, scale = 1, reward = { chargeMinutes = 6, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Hatch", kind = "Hatch", text = "Hatch {n} eggs", base = 5, scale = 1, reward = { chargeMinutes = 5, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Earn", kind = "Earn", text = "Earn {n} Charge", base = 10, scale = 1, reward = { chargeMinutes = 5, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Sell", kind = "Sell", text = "Sell your jar {n} times", base = 6, scale = 1, reward = { chargeMinutes = 4, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Fuse", kind = "Fuse", text = "Start {n} fusion", base = 1, scale = 1, reward = { chargeMinutes = 6, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Explore", kind = "Explore", text = "Catch {n} spirits in {zone}", base = 40, scale = 1, reward = { chargeMinutes = 5, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Storm", kind = "CatchStorm", text = "Catch {n} storm spirits", base = 8, scale = 1, reward = { chargeMinutes = 7, passXP = 180 }, daily = true, weekly = false },
		{ id = "D_Play", kind = "PlayMinutes", text = "Play for {n} minutes", base = 15, scale = 1, reward = { chargeMinutes = 5, passXP = 150 }, daily = true, weekly = false },
		{ id = "D_Upgrade", kind = "Upgrade", text = "Buy {n} upgrades", base = 4, scale = 1, reward = { chargeMinutes = 5, passXP = 150 }, daily = true, weekly = false },
		{ id = "W_Catch", kind = "Catch", text = "Catch {n} spirits", base = 2500, scale = 1, reward = { chargeMinutes = 30, passXP = 600 }, daily = false, weekly = true },
		{ id = "W_Hatch", kind = "Hatch", text = "Hatch {n} eggs", base = 60, scale = 1, reward = { chargeMinutes = 30, passXP = 600, potions = { LuckPotion = 1 } }, daily = false, weekly = true },
		{ id = "W_Fuse", kind = "Fuse", text = "Start {n} fusions", base = 5, scale = 1, reward = { chargeMinutes = 30, passXP = 600, fusionSkips = 1 }, daily = false, weekly = true },
		{ id = "W_Earn", kind = "Earn", text = "Earn {n} Charge", base = 180, scale = 1, reward = { chargeMinutes = 40, passXP = 600 }, daily = false, weekly = true },
		{ id = "W_Storm", kind = "CatchStorm", text = "Catch {n} storm spirits", base = 120, scale = 1, reward = { chargeMinutes = 35, passXP = 700, potions = { ChargePotion = 1 } }, daily = false, weekly = true },
		{ id = "W_Upgrade", kind = "Upgrade", text = "Buy {n} upgrades", base = 40, scale = 1, reward = { chargeMinutes = 30, passXP = 600 }, daily = false, weekly = true },
		{ id = "W_Play", kind = "PlayMinutes", text = "Play for {n} minutes", base = 180, scale = 1, reward = { chargeMinutes = 30, passXP = 600 }, daily = false, weekly = true },
		{ id = "W_Shiny", kind = "CatchShiny", text = "Catch {n} shiny spirits", base = 25, scale = 1, reward = { chargeMinutes = 30, passXP = 600 }, daily = false, weekly = true },
	} :: { Types.QuestTemplate },
}

-- Achievements: generated from (stat, targets) rows. Rewards grow per tier.
Config.Achievements = {} :: { Types.AchievementDef }
type AchievementRow = { stat: string, name: string, targets: { number } }
local achievementRows: { AchievementRow } = {
	{ stat = "Caught", name = "Spirit Catcher", targets = { 100, 1000, 10000, 100000, 1000000 } },
	{ stat = "Hatched", name = "Egg Cracker", targets = { 10, 100, 1000, 10000 } },
	{ stat = "Fused", name = "Fusion Adept", targets = { 1, 10, 100 } },
	{ stat = "Ascensions", name = "Sky Ascender", targets = { 1, 5, 10, 25, 50 } },
	{ stat = "LifetimeCharge", name = "Power Plant", targets = { 1e3, 1e6, 1e9, 1e12, 1e15 } },
	{ stat = "ZonesUnlocked", name = "Explorer", targets = { 2, 5, 10 } },
	{ stat = "StormCatches", name = "Storm Chaser", targets = { 10, 100, 1000 } },
	{ stat = "Shinies", name = "Shiny Hunter", targets = { 1, 100, 1000 } },
	{ stat = "Trades", name = "Trader", targets = { 1, 10 } },
	{ stat = "DecorationsPlaced", name = "Island Architect", targets = { 1, 10, 30 } },
	{ stat = "IndexCount", name = "Collector", targets = { 10, 30, 60 } },
}
for _, row in achievementRows do
	local stat, name = row.stat, row.name
	for i, target in row.targets do
		table.insert(Config.Achievements, {
			id = `{stat}_{i}`,
			name = `{name} {string.rep("I", math.min(i, 3))}{if i > 3 then tostring(i) else ""}`,
			stat = stat,
			target = target,
			reward = { chargeMinutes = 3 * i, passXP = 100 * i, tokens = if i >= 4 then 1 else nil },
		})
	end
end

Config.Index = {
	ChargeBonusPerEgg = 0.05, -- permanent +5% Charge for each egg whose pets are all discovered
	CompletionReward = { chargeMinutes = 10, tokens = 1 } :: Types.Reward,
}

Config.Offline = {
	BaseHours = 8,
	MinSeconds = 300,
	IncomeFraction = 0.15, -- of estimated online income
}

Config.FriendBoost = { PerFriend = 0.10, MaxFriends = 1 }

Config.Group = {
	GroupId = 0, -- TODO: set to your Roblox group id
	Reward = { pet = "GroupGust", chargeMinutes = 10 } :: Types.Reward,
}

Config.Premium = {
	ChargeBonus = 0.10,
	DailyReward = { chargeMinutes = 5, passXP = 50 } :: Types.Reward,
}

Config.Trade = {
	MaxPets = 12,
	MinPlayMinutes = 20, -- total playtime before a player can trade (anti-alt)
	RequestTimeout = 30,
	ConfirmDelay = 3, -- seconds after both are Ready before Confirm activates
	Cooldown = 10,
	HistoryLength = 20,
}

Config.Leaderboards = {
	WriteSeconds = 120,
	RefreshSeconds = 90,
	Top = 50,
	Boards = {
		{ id = "Charge", name = "Lifetime Charge", store = "LB_LifetimeCharge_v1", stat = "LifetimeCharge", log = true },
		{ id = "Ascensions", name = "Ascensions", store = "LB_Ascensions_v1", stat = "Ascensions", log = false },
		{ id = "Rarest", name = "Rarest Stormling", store = "LB_Rarest_v1", stat = "BestPetScore", log = false },
	},
}

-------------------------------------------------------------------------------
-- Island building
-------------------------------------------------------------------------------
Config.Island = {
	CellSize = 8,
	Sizes = { -- level -> grid cells per side and Charge cost to reach it
		{ cells = 6, cost = 0 },
		{ cells = 8, cost = 5000 },
		{ cells = 10, cost = 400000 },
		{ cells = 12, cost = 6e7 },
		{ cells = 14, cost = 1.5e10 },
	},
	MaxPlaced = 60,
	SellRefund = 0.5,
}

Config.Decorations = {
	{ id = "CloudBench", name = "Cloud Bench", cost = 300, size = Vector2.new(2, 1), height = 3, color = rgb(240, 245, 255), shape = "Block" },
	{ id = "StormLantern", name = "Storm Lantern", cost = 800, size = Vector2.new(1, 1), height = 7, color = rgb(255, 230, 120), shape = "Cylinder" },
	{ id = "CloudTree", name = "Cloud Tree", cost = 1200, size = Vector2.new(2, 2), height = 12, color = rgb(120, 214, 110), shape = "Ball" },
	{ id = "RainBarrel", name = "Rain Barrel", cost = 2500, size = Vector2.new(1, 1), height = 5, color = rgb(90, 140, 200), shape = "Cylinder", boost = { stat = "OfflineHours", amount = 1 }, maxBoosting = 3 },
	{ id = "LightningRod", name = "Lightning Rod", cost = 15000, size = Vector2.new(1, 1), height = 14, color = rgb(255, 240, 90), shape = "Cylinder", boost = { stat = "Charge", amount = 0.03 }, maxBoosting = 5, unlockZone = 3 },
	{ id = "Fountain", name = "Sky Fountain", cost = 8000, size = Vector2.new(2, 2), height = 6, color = rgb(160, 220, 255), shape = "Cylinder" },
	{ id = "JarRack", name = "Jar Rack", cost = 90000, size = Vector2.new(2, 1), height = 6, color = rgb(180, 130, 90), shape = "Block", boost = { stat = "Capacity", amount = 0.1 }, maxBoosting = 3, unlockZone = 4 },
	{ id = "WindChime", name = "Wind Chime", cost = 900000, size = Vector2.new(1, 1), height = 9, color = rgb(200, 255, 240), shape = "Wedge", boost = { stat = "Luck", amount = 0.05 }, maxBoosting = 4, unlockZone = 5 },
	{ id = "RainbowArch", name = "Rainbow Arch", cost = 2.5e7, size = Vector2.new(3, 1), height = 10, color = rgb(255, 140, 220), shape = "Block", boost = { stat = "Charge", amount = 0.05 }, maxBoosting = 3, unlockZone = 6 },
	{ id = "AuroraCrystal", name = "Aurora Crystal", cost = 6e9, size = Vector2.new(1, 1), height = 10, color = rgb(100, 255, 190), shape = "Wedge", boost = { stat = "Luck", amount = 0.1 }, maxBoosting = 2, unlockZone = 8 },
	{ id = "StormTotem", name = "Storm Totem", cost = 3e12, size = Vector2.new(2, 2), height = 16, color = rgb(90, 60, 160), shape = "Block", boost = { stat = "Charge", amount = 0.08 }, maxBoosting = 2, unlockZone = 10 },
} :: { Types.DecorationDef }

-------------------------------------------------------------------------------
-- Boost potions
-------------------------------------------------------------------------------
Config.Potions = {
	{ id = "LuckPotion", name = "Luck Potion", stat = "Luck", mult = 2, seconds = 900, color = rgb(90, 230, 110) },
	{ id = "SpeedPotion", name = "Speed Potion", stat = "Speed", mult = 1.3, seconds = 900, color = rgb(90, 190, 255) },
	{ id = "ChargePotion", name = "2x Charge Potion", stat = "Charge", mult = 2, seconds = 900, color = rgb(255, 210, 60) },
} :: { Types.PotionDef }
Config.MaxBoostSeconds = 4 * 3600

-------------------------------------------------------------------------------
-- Storm Pass (seasonal battle pass)
-------------------------------------------------------------------------------
Config.StormPass = {
	Season = "S1",
	SeasonName = "Season 1: First Flash",
	StartUnix = 1788220800, -- 2026-09-01 00:00 UTC
	Days = 30,
	Tiers = 50,
	XPBase = 400, -- XP for tier t = XPBase + XPStep*(t-1)
	XPStep = 20,
	-- Explicit milestone rewards; other tiers use the pattern in StormPassMath.
	Milestones = {
		[10] = { free = { potions = { LuckPotion = 2 } }, premium = { pet = "CloudCub", chargeMinutes = 30 } },
		[20] = { free = { decoration = "StormLantern" }, premium = { potions = { ChargePotion = 3 }, fusionSkips = 2 } },
		[25] = { free = { pet = "PassPup" }, premium = { pet = "PassPup", chargeMinutes = 60 } },
		[30] = { free = { potions = { ChargePotion = 2 } }, premium = { decoration = "RainbowArch", chargeMinutes = 60 } },
		[40] = { free = { fusionSkips = 1, chargeMinutes = 30 }, premium = { pet = "TempestTitan" } },
		[50] = { free = { tokens = 3, chargeMinutes = 60 }, premium = { pet = "SeasonSovereign", tokens = 5 } },
	} :: { [number]: Types.PassTierReward },
}

-------------------------------------------------------------------------------
-- Monetization. Set real asset ids before publishing (0 = not configured).
-- priceHint is display-only; the UI fetches the real price from MarketplaceService.
-------------------------------------------------------------------------------
Config.GamePasses = {
	{ key = "DoubleCharge", id = 0, name = "2x Charge", description = "Permanently doubles all Charge you earn.", priceHint = 299 },
	{ key = "AutoCatch", id = 0, name = "Auto-Catch", description = "Your jar catches nearby spirits on its own.", priceHint = 249 },
	{ key = "AutoSell", id = 0, name = "Auto-Sell", description = "Your jar sells itself when full, anywhere.", priceHint = 199 },
	{ key = "ExtraSlots", id = 0, name = "+3 Pet Slots", description = "Equip 3 more Stormlings.", priceHint = 349 },
	{ key = "VIP", id = 0, name = "VIP", description = "VIP chat tag, Rainbow Lagoon side zone, +20% luck.", priceHint = 399 },
	{ key = "LuckyHatch", id = 0, name = "Lucky Hatch", description = "Rare-or-better pets are 1.5x as likely from eggs.", priceHint = 199 },
	{ key = "FasterHatch", id = 0, name = "Faster Hatch", description = "Egg animations play much faster.", priceHint = 149 },
} :: { Types.PassDef }

Config.Products = {
	{ key = "ChargePackS", id = 0, name = "Charge Pouch", description = "30 minutes of your current income.", priceHint = 49, kind = "ChargePack", minutes = 30 },
	{ key = "ChargePackM", id = 0, name = "Charge Crate", description = "3 hours of your current income.", priceHint = 199, kind = "ChargePack", minutes = 180 },
	{ key = "ChargePackL", id = 0, name = "Charge Vault", description = "12 hours of your current income.", priceHint = 549, kind = "ChargePack", minutes = 720 },
	{ key = "LuckPotion1", id = 0, name = "Luck Potion", description = "2x luck for 15 minutes.", priceHint = 39, kind = "Potion", potion = "LuckPotion", count = 1 },
	{ key = "SpeedPotion1", id = 0, name = "Speed Potion", description = "Faster walking and catching for 15 minutes.", priceHint = 29, kind = "Potion", potion = "SpeedPotion", count = 1 },
	{ key = "ChargePotion1", id = 0, name = "2x Charge Potion", description = "2x Charge for 15 minutes.", priceHint = 49, kind = "Potion", potion = "ChargePotion", count = 1 },
	{ key = "ChargePotion5", id = 0, name = "2x Charge Potion x5", description = "Five 15-minute 2x Charge potions.", priceHint = 199, kind = "Potion", potion = "ChargePotion", count = 5 },
	{ key = "TempestEgg1", id = 0, name = "Tempest Egg", description = "Hatch one Tempest Egg. Odds shown in the egg menu.", priceHint = 99, kind = "Egg", egg = "TempestEgg", count = 1 },
	{ key = "TempestEgg3", id = 0, name = "Tempest Egg x3", description = "Hatch three Tempest Eggs. Odds shown in the egg menu.", priceHint = 279, kind = "Egg", egg = "TempestEgg", count = 3 },
	{ key = "PassSkip", id = 0, name = "Skip a Tier", description = "Instantly gain one Storm Pass tier.", priceHint = 79, kind = "PassSkip" },
	{ key = "PassPremium", id = 0, name = "Premium Storm Pass", description = "Unlocks the premium track for this season.", priceHint = 399, kind = "PassPremium" },
	{ key = "InstantFusion", id = 0, name = "Instant Fusion", description = "Finishes your oldest running fusion now.", priceHint = 29, kind = "InstantFusion" },
	{ key = "StarterPack", id = 0, name = "Starter Pack", description = "One-time bundle for new chasers.", priceHint = 99, kind = "StarterPack" },
} :: { Types.ProductDef }

Config.StarterPack = {
	Contents = { pet = "StarterSquall", potions = { ChargePotion = 3, LuckPotion = 3 }, chargeMinutes = 60 } :: Types.Reward,
	-- For the honest "worth if bought separately" line: product keys and counts that match the contents
	ValueOf = { { key = "ChargePotion1", count = 3 }, { key = "LuckPotion1", count = 3 }, { key = "ChargePackS", count = 2 } },
	OfferAfterSeconds = 180, -- shown once, after the tutorial, never again automatically
}

-------------------------------------------------------------------------------
-- Security / anti-exploit tolerances
-------------------------------------------------------------------------------
Config.Security = {
	CatchRangeTolerance = 6, -- studs of extra slack for latency
	CatchCooldownTolerance = 0.8, -- fraction of the cooldown that must pass
	SellRadius = 9,
	MaxRemoteRate = 30, -- default events per second per remote per player
	AdminUserIds = {} :: { number }, -- can use /dev commands in live servers
}

-------------------------------------------------------------------------------
-- "Size simulator" feel: things grow as you progress (cosmetic only)
-------------------------------------------------------------------------------
Config.SizeFeel = {
	Enabled = true,
	AvatarScalePerAscension = 0.08,
	AvatarMaxScale = 2.2,
	JarScaleBase = 1,
	JarScalePerLevel = 0.04,
	JarMaxScale = 3,
}

-------------------------------------------------------------------------------
-- World layout (placeholder builder)
-------------------------------------------------------------------------------
Config.World = {
	ZoneSize = 220,
	ZoneSpacing = 300,
	ZoneStart = Vector3.new(0, 100, 0),
	PlotRadius = 170,
	PlotCount = 12,
	PlotCenter = Vector3.new(0, 100, -420),
	HubSize = 90,
}

Config.Sounds = {
	-- Asset ids for audio. Leave "" to skip the cue. Replace with your own uploaded sounds.
	Catch = "",
	CatchRare = "",
	Sell = "",
	Upgrade = "",
	HatchShake = "",
	HatchReveal = "",
	Legendary = "",
	StormStart = "",
	Click = "",
	Music = "",
}

return Config
