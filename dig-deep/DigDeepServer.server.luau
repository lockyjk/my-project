--[[
	⛏  DIG DEEP  ·  SERVER
	Paste this into a Script in ServerScriptService.
	It builds the whole world when the server starts, so start from an empty Baseplate place.
	Pair it with DigDeepClient (a LocalScript in StarterPlayer > StarterPlayerScripts).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

pcall(function()
	workspace.FallenPartsDestroyHeight = -4000
end)

-- Remove the template's baseplate and spawn first, before any character can land on them.
for _, child in workspace:GetChildren() do
	if child:IsA("SpawnLocation") or child.Name == "Baseplate" then
		child:Destroy()
	end
end

--------------------------------------------------------------------------------
-- TUNING
--------------------------------------------------------------------------------
-- Surface height. The mine digs down 3000 studs from here, so the place file sets
-- Workspace.FallenPartsDestroyHeight to -4000 (the script also tries to, below).
local TOP = 100
local BLOCK = 6 -- studs per block
local GRID = 24 -- the mine is GRID x GRID blocks wide
local MAX_DEPTH = 500 -- rows; bedrock below
local REACH = 20 -- studs from your root part to a block's centre
local PART_CAP = 11000 -- an earthquake resets the mine once this many blocks exist
local QUAKE_EVERY = 30 * 60
local QUAKE_WARNING = 20
local RUSH_EVERY = 12 * 60 -- a Gold Rush starts every 12 minutes on the UTC clock...
local RUSH_LENGTH = 90 -- ...and lasts this many seconds
local RUSH_MULT = 3 -- ore chance multiplier during a rush
local GEODE_CHANCE = 1 / 260
local GEODE_MIN_DEPTH = 20
local ELEVATOR_STEP = 25
local FRIEND_BONUS = 0.1
local TREASURE_BONUS = 0.1 -- +10% ore value per unique treasure found
local ASCEND_BONUS = 0.5 -- +50% ore value per Ascension
local AUTOSAVE_EVERY = 90
local DATA_STORE = "DigDeep_v1"

-- Ores. value = coins per block before bonuses. hp = block health multiplier.
-- tier drives popup size (1 common .. 6 mythic). announce = tell the whole server.
local ORES = {
	Coal = { name = "Coal", value = 5, hp = 1.3, color = { 45, 45, 50 }, material = "Slate", tier = 1 },
	Copper = { name = "Copper", value = 12, hp = 1.4, color = { 206, 122, 72 }, material = "Metal", tier = 1 },
	Iron = { name = "Iron", value = 30, hp = 1.5, color = { 208, 192, 176 }, material = "Metal", tier = 2 },
	Silver = { name = "Silver", value = 70, hp = 1.6, color = { 222, 228, 238 }, material = "Metal", tier = 2 },
	Gold = { name = "Gold", value = 160, hp = 1.7, color = { 255, 196, 40 }, material = "Foil", tier = 3 },
	Ruby = { name = "Ruby", value = 450, hp = 2, color = { 230, 35, 70 }, material = "Glass", tier = 3, glow = true },
	Sapphire = { name = "Sapphire", value = 450, hp = 2, color = { 45, 100, 235 }, material = "Glass", tier = 3, glow = true },
	Obsidian = { name = "Obsidian", value = 600, hp = 2.5, color = { 42, 22, 62 }, material = "Glass", tier = 3 },
	Emerald = { name = "Emerald", value = 1200, hp = 2.2, color = { 40, 210, 120 }, material = "Glass", tier = 4, glow = true },
	Firestone = { name = "Firestone", value = 3500, hp = 2.6, color = { 255, 120, 30 }, material = "Neon", tier = 4, glow = true },
	Amethyst = { name = "Amethyst", value = 4000, hp = 2.4, color = { 165, 85, 235 }, material = "Glass", tier = 4, glow = true },
	Diamond = { name = "Diamond", value = 12000, hp = 3, color = { 175, 240, 255 }, material = "Glass", tier = 5, glow = true },
	Moonstone = { name = "Moonstone", value = 30000, hp = 3.2, color = { 225, 235, 255 }, material = "Neon", tier = 5, glow = true, announce = true },
	Voidstone = { name = "Voidstone", value = 40000, hp = 2.6, color = { 110, 40, 185 }, material = "Neon", tier = 5, glow = true },
	Starshard = { name = "Starshard", value = 150000, hp = 3.2, color = { 255, 235, 140 }, material = "Neon", tier = 6, glow = true, announce = true },
	Corium = { name = "Corium", value = 90000, hp = 2.2, color = { 255, 84, 40 }, material = "Neon", tier = 5, glow = true },
	Singularity = { name = "Singularity", value = 1500000, hp = 5, color = { 235, 70, 255 }, material = "Neon", tier = 6, glow = true, announce = true },
}

-- Layers, top to bottom. from = first row. hp = base block health. value = coins for a plain block.
-- tint = colour grading while you are in this layer.
local LAYERS = {
	{ name = "Topsoil", band = { 172, 108, 66 }, alt = { material = "Mud", color = { 96, 68, 46 } }, from = 0, hp = 3, value = 1, color = { 118, 84, 56 }, material = "Ground", tint = { 255, 244, 228 },
		ores = { { id = "Coal", chance = 0.06 }, { id = "Copper", chance = 0.03 } } },
	{ name = "Stone", band = { 168, 156, 136 }, alt = { material = "Rock", color = { 112, 112, 116 } }, from = 20, hp = 8, value = 2, color = { 125, 125, 130 }, material = "Slate", tint = { 236, 240, 255 },
		ores = { { id = "Coal", chance = 0.04 }, { id = "Copper", chance = 0.04 }, { id = "Iron", chance = 0.04 }, { id = "Silver", chance = 0.015 } } },
	{ name = "Deepstone", band = { 92, 104, 138 }, alt = { material = "Slate", color = { 58, 60, 74 } }, from = 60, hp = 16, value = 5, color = { 72, 74, 88 }, material = "Basalt", tint = { 214, 224, 255 },
		ores = { { id = "Iron", chance = 0.04 }, { id = "Silver", chance = 0.03 }, { id = "Gold", chance = 0.025 }, { id = "Ruby", chance = 0.008 }, { id = "Sapphire", chance = 0.008 } } },
	{ name = "Magma Rock", band = { 150, 62, 30 }, alt = { material = "Basalt", color = { 50, 32, 28 } }, from = 120, hp = 50, value = 12, color = { 70, 40, 34 }, material = "CrackedLava", tint = { 255, 212, 186 },
		ores = { { id = "Gold", chance = 0.03 }, { id = "Obsidian", chance = 0.03 }, { id = "Emerald", chance = 0.015 }, { id = "Firestone", chance = 0.007 } } },
	{ name = "Crystal Caves", band = { 126, 148, 226 }, alt = { material = "Ice", color = { 110, 150, 205 } }, from = 200, hp = 160, value = 30, color = { 66, 86, 130 }, material = "Glacier", tint = { 206, 224, 255 },
		ores = { { id = "Amethyst", chance = 0.03 }, { id = "Diamond", chance = 0.01 }, { id = "Moonstone", chance = 0.004 } } },
	{ name = "The Void", band = { 76, 34, 110 }, alt = { material = "Basalt", color = { 22, 16, 34 } }, from = 300, hp = 520, value = 80, color = { 30, 22, 44 }, material = "Slate", tint = { 222, 196, 255 },
		ores = { { id = "Voidstone", chance = 0.03 }, { id = "Starshard", chance = 0.008 }, { id = "Singularity", chance = 0.0008 } } },
	{ name = "The Core", band = { 255, 120, 40 }, alt = { material = "CrackedLava", color = { 90, 30, 16 } }, from = 420, hp = 1500, value = 240, color = { 60, 20, 14 }, material = "Basalt", tint = { 255, 200, 170 },
		ores = { { id = "Starshard", chance = 0.01 }, { id = "Corium", chance = 0.02 }, { id = "Singularity", chance = 0.002 } } },
}

local PICKS = {
	{ name = "Rusty Pick", dmg = 1, speed = 0.45, price = 0, color = { 150, 96, 62 }, material = "CorrodedMetal" },
	{ name = "Stone Pick", dmg = 2, speed = 0.42, price = 40, color = { 140, 140, 144 }, material = "Slate" },
	{ name = "Iron Pick", dmg = 4, speed = 0.40, price = 700, color = { 205, 205, 212 }, material = "Metal" },
	{ name = "Golden Pick", dmg = 8, speed = 0.36, price = 8000, color = { 255, 200, 45 }, material = "Foil" },
	{ name = "Diamond Pick", dmg = 16, speed = 0.33, price = 22000, color = { 150, 235, 255 }, material = "Glass", glow = true },
	{ name = "Magma Pick", dmg = 34, speed = 0.30, price = 150000, color = { 255, 105, 25 }, material = "Neon", glow = true },
	{ name = "Crystal Pick", dmg = 75, speed = 0.27, price = 1000000, color = { 175, 95, 255 }, material = "Glass", glow = true },
	{ name = "Void Pick", dmg = 170, speed = 0.24, price = 8000000, color = { 80, 10, 140 }, material = "Neon", glow = true },
	{ name = "Starforged Pick", dmg = 400, speed = 0.20, price = 60000000, color = { 255, 240, 165 }, material = "Neon", glow = true },
	{ name = "Core Breaker", dmg = 1100, speed = 0.18, price = 450000000, color = { 255, 90, 40 }, material = "Neon", glow = true },
}

local BAGS = {
	{ name = "Pouch", capacity = 20, price = 0, color = { 165, 124, 84 } },
	{ name = "Satchel", capacity = 50, price = 90, color = { 125, 82, 52 } },
	{ name = "Rucksack", capacity = 120, price = 1500, color = { 74, 112, 64 } },
	{ name = "Miner's Pack", capacity = 300, price = 9000, color = { 205, 145, 45 } },
	{ name = "Ore Hauler", capacity = 750, price = 60000, color = { 92, 94, 112 } },
	{ name = "Gem Vault", capacity = 2000, price = 400000, color = { 60, 160, 222 }, trim = { 160, 240, 255 } },
	{ name = "Bottomless Bag", capacity = 6000, price = 3000000, color = { 122, 42, 165 }, trim = { 255, 120, 255 } },
	{ name = "Pocket Dimension", capacity = 20000, price = 25000000, color = { 22, 20, 32 }, trim = { 140, 90, 255 } },
}

-- Treasures, in museum order. chance is per block broken at or below `depth` metres.
local TREASURES = {
	{ id = "OldBoot", name = "Old Boot", depth = 0, chance = 1 / 350, reward = 60, color = { 150, 100, 60 }, hint = "Somewhere near the top" },
	{ id = "AncientCoin", name = "Ancient Coin", depth = 15, chance = 1 / 700, reward = 400, color = { 240, 190, 70 }, hint = "Deeper than 15m" },
	{ id = "FossilSkull", name = "Fossil Skull", depth = 45, chance = 1 / 1400, reward = 3000, color = { 230, 220, 192 }, hint = "Deeper than 45m" },
	{ id = "GoldenIdol", name = "Golden Idol", depth = 90, chance = 1 / 2400, reward = 30000, color = { 255, 200, 50 }, hint = "Deeper than 90m" },
	{ id = "DragonEgg", name = "Dragon Egg", depth = 160, chance = 1 / 4000, reward = 300000, color = { 255, 90, 60 }, hint = "Deeper than 160m" },
	{ id = "Meteorite", name = "Meteorite", depth = 250, chance = 1 / 6500, reward = 2500000, color = { 255, 140, 60 }, hint = "Deeper than 250m" },
	{ id = "CrownOfTheDeep", name = "Crown of the Deep", depth = 360, chance = 1 / 12000, reward = 40000000, color = { 120, 200, 255 }, hint = "Deeper than 360m" },
	{ id = "RubberDuck", name = "Rubber Duck", depth = 0, chance = 1 / 40000, reward = 1000000, color = { 255, 220, 40 }, hint = "Anywhere... if you're lucky" },
}

-- Daily chest base reward by pickaxe tier, so it stays useful as you progress.
local DAILY = { 100, 300, 1500, 8000, 25000, 120000, 700000, 5000000, 35000000, 250000000 }

-- Rough coins per minute of digging for each pickaxe tier. Coin packs, codes and the spin wheel
-- pay "N minutes of digging", so rewards stay useful at every stage of the game.
local INCOME = { 30, 90, 300, 1100, 3500, 14000, 60000, 350000, 2000000, 12000000 }

--------------------------------------------------------------------------------
-- MONETIZATION
-- Create each pass / product on the Creator Dashboard and paste its id here.
-- While an id is 0: in a live game the item shows "Coming soon"; in Studio, buying it
-- grants it for free (this session only) so you can test everything.
--------------------------------------------------------------------------------
local PASSES = {
	{ key = "VIP", id = 0, price = 399, name = "VIP", icon = "👑", desc = "+25% ore value, a VIP tag and a sparkling VIP pickaxe" },
	{ key = "DoubleCoins", id = 0, price = 349, name = "2x Coins", icon = "💰", desc = "Everything you sell is worth double" },
	{ key = "AutoMine", id = 0, price = 299, name = "Auto Mine", icon = "🤖", desc = "Dig without clicking. Toggle it any time" },
	{ key = "SellAnywhere", id = 0, price = 249, name = "Sell Anywhere", icon = "🛒", desc = "Sell your bag from anywhere with one tap" },
	{ key = "Lucky", id = 0, price = 299, name = "Lucky Miner", icon = "🍀", desc = "2x treasure luck and better egg odds" },
	{ key = "FastMine", id = 0, price = 249, name = "Fast Swings", icon = "⚡", desc = "Swing your pickaxe 25% faster" },
	{ key = "InfiniteBag", id = 0, price = 799, name = "Infinite Backpack", icon = "♾️", desc = "Your backpack never fills up" },
	{ key = "MorePets", id = 0, price = 349, name = "+2 Pet Slots", icon = "🐾", desc = "Equip 5 pets instead of 3" },
}
local PRODUCTS = {
	{ key = "Starter", id = 0, price = 99, name = "Starter Pack", icon = "🎁", desc = "Starter Pup pet, 15 min of every potion and a coin bundle", starter = true },
	{ key = "CoinsS", id = 0, price = 49, name = "Pile of Coins", icon = "🪙", coinMinutes = 20 },
	{ key = "CoinsM", id = 0, price = 199, name = "Sack of Coins", icon = "💰", coinMinutes = 120 },
	{ key = "CoinsL", id = 0, price = 599, name = "Vault of Coins", icon = "🏦", coinMinutes = 480 },
	{ key = "PotionCoins", id = 0, price = 39, name = "2x Coins Potion", icon = "🧪", potion = "Coins", minutes = 15 },
	{ key = "PotionLuck", id = 0, price = 39, name = "Luck Potion", icon = "🍀", potion = "Luck", minutes = 15 },
	{ key = "PotionSpeed", id = 0, price = 39, name = "Speed Potion", icon = "⚡", potion = "Speed", minutes = 15 },
	{ key = "NextPick", id = 0, price = 149, name = "Instant Pickaxe", icon = "⛏", desc = "Skip straight to your next pickaxe" },
}

--------------------------------------------------------------------------------
-- PETS, EGGS, LEVELS, SPIN WHEEL, CODES
-- Eggs cost coins only (never Robux), so there are no paid random items.
--------------------------------------------------------------------------------
local PETS = {
	Mole = { name = "Mole", rarity = "Common", boost = 0.05, color = { 150, 108, 78 }, accent = { 255, 170, 170 }, ears = "round", icon = "🐹" },
	Bunny = { name = "Bunny", rarity = "Uncommon", boost = 0.1, color = { 240, 238, 242 }, accent = { 255, 170, 195 }, ears = "long", icon = "🐰" },
	PebblePup = { name = "Pebble Pup", rarity = "Rare", boost = 0.2, color = { 150, 150, 162 }, accent = { 90, 90, 104 }, ears = "pointy", tail = true, icon = "🐶" },
	GoldenMole = { name = "Golden Mole", rarity = "Legendary", boost = 0.5, color = { 255, 200, 60 }, accent = { 255, 240, 170 }, ears = "round", glow = true, icon = "🌟" },
	Bat = { name = "Cave Bat", rarity = "Common", boost = 0.25, color = { 84, 64, 112 }, accent = { 255, 140, 200 }, ears = "pointy", wings = true, icon = "🦇" },
	Slime = { name = "Slime", rarity = "Uncommon", boost = 0.4, color = { 90, 222, 124 }, accent = { 40, 140, 70 }, ears = "none", jelly = true, icon = "🟢" },
	RockGolem = { name = "Rock Golem", rarity = "Rare", boost = 0.7, color = { 124, 114, 104 }, accent = { 255, 170, 60 }, ears = "none", horns = true, icon = "🗿" },
	LavaPup = { name = "Lava Pup", rarity = "Legendary", boost = 1.5, color = { 255, 92, 32 }, accent = { 255, 222, 92 }, ears = "pointy", tail = true, glow = true, icon = "🔥" },
	CrystalFox = { name = "Crystal Fox", rarity = "Common", boost = 1, color = { 140, 210, 255 }, accent = { 255, 255, 255 }, ears = "pointy", tail = true, icon = "🦊" },
	GemOwl = { name = "Gem Owl", rarity = "Uncommon", boost = 1.5, color = { 170, 110, 255 }, accent = { 255, 222, 122 }, ears = "pointy", wings = true, icon = "🦉" },
	PrismDragon = { name = "Prism Dragon", rarity = "Rare", boost = 2.5, color = { 255, 122, 222 }, accent = { 122, 255, 240 }, ears = "none", horns = true, wings = true, tail = true, icon = "🐲" },
	DiamondDragon = { name = "Diamond Dragon", rarity = "Legendary", boost = 6, color = { 205, 245, 255 }, accent = { 120, 200, 255 }, ears = "none", horns = true, wings = true, tail = true, glow = true, icon = "💎" },
	ShadowCat = { name = "Shadow Cat", rarity = "Common", boost = 3, color = { 44, 34, 64 }, accent = { 182, 122, 255 }, ears = "pointy", tail = true, icon = "🐈‍⬛" },
	VoidWisp = { name = "Void Wisp", rarity = "Uncommon", boost = 5, color = { 112, 42, 202 }, accent = { 232, 182, 255 }, ears = "none", glow = true, icon = "👻" },
	NebulaSerpent = { name = "Nebula Serpent", rarity = "Rare", boost = 8, color = { 62, 22, 122 }, accent = { 255, 122, 222 }, ears = "none", horns = true, tail = true, glow = true, icon = "🐍" },
	SingularitySpirit = { name = "Singularity Spirit", rarity = "Legendary", boost = 18, color = { 24, 24, 28 }, accent = { 255, 255, 255 }, ears = "none", wings = true, glow = true, icon = "✨" },
	StarterPup = { name = "Starter Pup", rarity = "Exclusive", boost = 0.5, color = { 255, 202, 122 }, accent = { 255, 122, 82 }, ears = "round", tail = true, icon = "🐕" },
}
local RARITY_COLORS = { Common = { 200, 200, 210 }, Uncommon = { 110, 230, 130 }, Rare = { 80, 170, 255 }, Legendary = { 255, 200, 50 }, Exclusive = { 255, 110, 200 } }
local EGGS = {
	{ id = "DirtEgg", name = "Dirt Egg", price = 250, depth = 0, color = { 176, 124, 82 }, spots = { 120, 80, 50 }, pets = { { "Mole", 60 }, { "Bunny", 28 }, { "PebblePup", 10 }, { "GoldenMole", 2 } } },
	{ id = "CaveEgg", name = "Cave Egg", price = 6000, depth = 60, color = { 92, 92, 112 }, spots = { 255, 140, 60 }, pets = { { "Bat", 60 }, { "Slime", 28 }, { "RockGolem", 10 }, { "LavaPup", 2 } } },
	{ id = "CrystalEgg", name = "Crystal Egg", price = 250000, depth = 200, color = { 152, 202, 255 }, spots = { 255, 140, 230 }, pets = { { "CrystalFox", 60 }, { "GemOwl", 28 }, { "PrismDragon", 10 }, { "DiamondDragon", 2 } } },
	{ id = "VoidEgg", name = "Void Egg", price = 25000000, depth = 300, color = { 44, 22, 74 }, spots = { 202, 142, 255 }, pets = { { "ShadowCat", 60 }, { "VoidWisp", 28 }, { "NebulaSerpent", 10 }, { "SingularitySpirit", 2 } } },
}
local PET_SLOTS = 3
local MAX_PETS = 50
local LEVEL_BONUS = 0.01 -- +1% ore value per level
local SPIN_COOLDOWN = 20 * 60
local SPIN = {
	{ label = "Coins", icon = "🪙", weight = 30, coinMinutes = 3, color = { 255, 206, 70 } },
	{ label = "2x Coins", icon = "🧪", weight = 14, potion = "Coins", minutes = 10, color = { 255, 150, 60 } },
	{ label = "Big Coins", icon = "💰", weight = 18, coinMinutes = 8, color = { 110, 220, 110 } },
	{ label = "Luck", icon = "🍀", weight = 14, potion = "Luck", minutes = 10, color = { 80, 200, 150 } },
	{ label = "Huge Coins", icon = "🏦", weight = 7, coinMinutes = 25, color = { 80, 160, 255 } },
	{ label = "Speed", icon = "⚡", weight = 14, potion = "Speed", minutes = 10, color = { 170, 110, 255 } },
	{ label = "Free Egg", icon = "🥚", weight = 2.5, egg = true, color = { 255, 120, 190 } },
	{ label = "JACKPOT", icon = "💎", weight = 0.5, coinMinutes = 120, color = { 255, 80, 80 } },
}
-- Codes are case-insensitive. Post new ones in your group/social to bring players back.
local CODES = {
	RELEASE = { coinMinutes = 10 },
	DIGDEEP = { potion = "Luck", minutes = 15 },
	GOLDRUSH = { potion = "Coins", minutes = 15 },
	THANKYOU = { coinMinutes = 30 },
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local rng = Random.new()

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function material(name)
	return Enum.Material[name]
end

local function W(x, y, z)
	return Vector3.new(x, TOP + y, z)
end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi" }
local function fmt(n)
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	local s
	if v >= 100 then
		s = tostring(math.floor(v))
	elseif v >= 10 then
		s = string.format("%.1f", math.floor(v * 10) / 10)
	else
		s = string.format("%.2f", math.floor(v * 100) / 100)
	end
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s .. SUFFIX[i]
end

local function newPart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	if parent then
		p.Parent = parent
	end
	return p
end

local function addLight(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

-- A floating label. lines = { {name, text, size, color}, ... }
local function billboard(adornee, height, lines, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = maxDistance or 70
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local total = 0
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = line[1]
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, line[3] + 4)
		label.Font = Enum.Font.FredokaOne
		label.Text = line[2]
		label.TextSize = line[3]
		label.TextColor3 = line[4]
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(20, 18, 24)
		stroke.Transparency = 0.15
		stroke.Parent = label
		label.Parent = gui
		total += line[3] + 4
	end
	gui.Size = UDim2.fromOffset(280, total)
	gui.Parent = adornee
	return gui
end

local function signText(part, face, text, color)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0.4
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 20, 14)
	stroke.Parent = label
	label.Parent = sg
	sg.Parent = part
	return sg
end

local function prompt(parent, kind, action, objectText, hold, tier)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = objectText
	p.HoldDuration = hold
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p:SetAttribute("Kind", kind)
	if tier then
		p:SetAttribute("Tier", tier)
	end
	p.Parent = parent
	return p
end

--------------------------------------------------------------------------------
-- MODELS (pickaxes, bags, treasures)
--------------------------------------------------------------------------------
local function piece(model, props)
	local p = newPart(props)
	p.CanCollide = false
	p.Parent = model
	return p
end

-- Pickaxe built along +Z (handle) with the head across X, centred on the handle.
local function buildPick(tier)
	local P = PICKS[tier]
	local m = Instance.new("Model")
	m.Name = P.name
	local wood = Color3.fromRGB(112, 74, 46)
	local handle = piece(m, { Name = "Handle", Size = Vector3.new(0.35, 0.35, 4.4), CFrame = CFrame.new(), Color = wood, Material = Enum.Material.Wood })
	piece(m, { Name = "Grip", Size = Vector3.new(0.45, 0.45, 1.1), CFrame = CFrame.new(0, 0, -1.55), Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.Fabric })
	local head = piece(m, { Name = "Head", Size = Vector3.new(3.2, 0.55, 0.7), CFrame = CFrame.new(0, 0, 2.05), Color = rgb(P.color), Material = material(P.material) })
	local tipColor = rgb(P.color):Lerp(Color3.new(1, 1, 1), 0.35)
	piece(m, { Name = "TipA", Size = Vector3.new(0.7, 0.4, 0.5), CFrame = CFrame.new(1.9, 0, 2.05), Color = tipColor, Material = material(P.material) })
	piece(m, { Name = "TipB", Size = Vector3.new(0.7, 0.4, 0.5), CFrame = CFrame.new(-1.9, 0, 2.05), Color = tipColor, Material = material(P.material) })
	piece(m, { Name = "Collar", Size = Vector3.new(0.6, 0.7, 0.9), CFrame = CFrame.new(0, 0, 2.05), Color = Color3.fromRGB(70, 66, 64), Material = Enum.Material.Metal })
	if P.glow then
		addLight(head, rgb(P.color), 8, 1.2)
	end
	m.PrimaryPart = handle
	return m
end

local function buildBag(tier, s)
	local B = BAGS[tier]
	local m = Instance.new("Model")
	m.Name = B.name
	local color = rgb(B.color)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.3)
	local body = piece(m, { Name = "Body", Size = Vector3.new(2, 2.4, 1.1) * s, CFrame = CFrame.new(), Color = color, Material = Enum.Material.Fabric })
	piece(m, { Name = "Flap", Size = Vector3.new(2.1, 0.7, 1.2) * s, CFrame = CFrame.new(0, 0.95 * s, 0), Color = dark, Material = Enum.Material.Fabric })
	piece(m, { Name = "Pocket", Size = Vector3.new(1.4, 0.8, 0.3) * s, CFrame = CFrame.new(0, -0.45 * s, 0.6 * s), Color = dark, Material = Enum.Material.Fabric })
	piece(m, { Name = "Buckle", Size = Vector3.new(0.35, 0.35, 0.1) * s, CFrame = CFrame.new(0, 0.75 * s, 0.62 * s), Color = Color3.fromRGB(230, 190, 80), Material = Enum.Material.Metal })
	if B.trim then
		local trim = piece(m, { Name = "Trim", Size = Vector3.new(2.05, 0.14, 1.15) * s, CFrame = CFrame.new(0, 0.1 * s, 0), Color = rgb(B.trim), Material = Enum.Material.Neon })
		addLight(trim, rgb(B.trim), 6, 0.8)
	end
	m.PrimaryPart = body
	return m
end

local TREASURE_BUILDERS = {}

TREASURE_BUILDERS.OldBoot = function(m)
	local leather = Color3.fromRGB(110, 72, 45)
	local foot = piece(m, { Size = Vector3.new(2.5, 0.8, 1.1), CFrame = CFrame.new(0.25, -0.35, 0), Color = leather, Material = Enum.Material.Fabric })
	piece(m, { Size = Vector3.new(2.7, 0.35, 1.2), CFrame = CFrame.new(0.25, -0.9, 0), Color = Color3.fromRGB(55, 38, 28), Material = Enum.Material.Wood })
	piece(m, { Size = Vector3.new(1.15, 1.9, 1.05), CFrame = CFrame.new(-0.45, 0.8, 0), Color = leather, Material = Enum.Material.Fabric })
	piece(m, { Size = Vector3.new(1.25, 0.3, 1.15), CFrame = CFrame.new(-0.45, 1.8, 0), Color = Color3.fromRGB(80, 52, 34), Material = Enum.Material.Fabric })
	piece(m, { Size = Vector3.new(0.12, 0.9, 0.75), CFrame = CFrame.new(0.15, 0.35, 0), Color = Color3.fromRGB(235, 225, 200), Material = Enum.Material.Fabric })
	return foot
end

TREASURE_BUILDERS.AncientCoin = function(m)
	local disc = piece(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 2.6, 2.6), CFrame = CFrame.new(), Color = Color3.fromRGB(235, 185, 60), Material = Enum.Material.Foil })
	piece(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.42, 1.8, 1.8), CFrame = CFrame.new(), Color = Color3.fromRGB(200, 145, 40), Material = Enum.Material.Foil })
	piece(m, { Size = Vector3.new(0.5, 0.5, 0.5), CFrame = CFrame.new(), Color = Color3.fromRGB(20, 16, 12), Material = Enum.Material.SmoothPlastic })
	addLight(disc, Color3.fromRGB(255, 200, 90), 7, 0.8)
	return disc
end

TREASURE_BUILDERS.FossilSkull = function(m)
	local bone = Color3.fromRGB(228, 218, 190)
	local skull = piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(), Color = bone, Material = Enum.Material.Limestone })
	piece(m, { Size = Vector3.new(1.6, 0.6, 1.4), CFrame = CFrame.new(0, -1.1, -0.5), Color = bone, Material = Enum.Material.Limestone })
	for _, x in { -0.5, 0.5 } do
		piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = CFrame.new(x, 0.15, -0.98), Color = Color3.fromRGB(25, 20, 18), Material = Enum.Material.SmoothPlastic })
	end
	piece(m, { Size = Vector3.new(0.3, 0.4, 0.2), CFrame = CFrame.new(0, -0.4, -1.15), Color = Color3.fromRGB(25, 20, 18), Material = Enum.Material.SmoothPlastic })
	return skull
end

TREASURE_BUILDERS.GoldenIdol = function(m)
	local gold = Color3.fromRGB(245, 188, 50)
	piece(m, { Size = Vector3.new(1.8, 0.5, 1.8), CFrame = CFrame.new(0, -1.4, 0), Color = gold:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Foil })
	local body = piece(m, { Size = Vector3.new(1.3, 1.6, 1), CFrame = CFrame.new(0, -0.35, 0), Color = gold, Material = Enum.Material.Foil })
	piece(m, { Size = Vector3.new(1.1, 1.1, 1.1), CFrame = CFrame.new(0, 1, 0), Color = gold, Material = Enum.Material.Foil })
	piece(m, { Size = Vector3.new(1.6, 0.35, 1.3), CFrame = CFrame.new(0, 1.7, 0), Color = gold:Lerp(Color3.new(1, 1, 1), 0.2), Material = Enum.Material.Foil })
	for _, x in { -0.25, 0.25 } do
		piece(m, { Size = Vector3.new(0.2, 0.2, 0.1), CFrame = CFrame.new(x, 1.05, -0.56), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon })
	end
	addLight(body, Color3.fromRGB(255, 200, 80), 9, 1)
	return body
end

TREASURE_BUILDERS.DragonEgg = function(m)
	local shell = piece(m, { Size = Vector3.new(2.2, 3, 2.2), CFrame = CFrame.new(), Color = Color3.fromRGB(150, 30, 42), Material = Enum.Material.SmoothPlastic, Reflectance = 0.1 })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	for _, pos in { Vector3.new(0.9, 0.4, -0.6), Vector3.new(-0.8, -0.5, -0.7), Vector3.new(0.2, 1, 0.8), Vector3.new(-0.7, 0.2, 0.85), Vector3.new(0.75, -0.7, 0.6) } do
		piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = CFrame.new(pos), Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon })
	end
	addLight(shell, Color3.fromRGB(255, 110, 50), 10, 1.4)
	return shell
end

TREASURE_BUILDERS.Meteorite = function(m)
	local r = Random.new(7)
	local rock = piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(2.8, 2.8, 2.8), CFrame = CFrame.new(), Color = Color3.fromRGB(55, 45, 45), Material = Enum.Material.Basalt })
	piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = CFrame.new(1, 0.8, 0.3), Color = Color3.fromRGB(50, 40, 40), Material = Enum.Material.Basalt })
	for _ = 1, 5 do
		local dir = r:NextUnitVector()
		local cf = CFrame.lookAt(dir * 1.2, dir * 3) * CFrame.Angles(0, 0, r:NextNumber() * math.pi)
		piece(m, { Size = Vector3.new(0.25, 1.4, 0.3), CFrame = cf, Color = Color3.fromRGB(255, 120, 30), Material = Enum.Material.Neon })
	end
	addLight(rock, Color3.fromRGB(255, 120, 40), 12, 1.6)
	return rock
end

TREASURE_BUILDERS.CrownOfTheDeep = function(m)
	local gold = Color3.fromRGB(250, 196, 60)
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local band = piece(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 2.8, 2.8), CFrame = upright, Color = gold, Material = Enum.Material.Foil })
	piece(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.05, 2.3, 2.3), CFrame = upright, Color = Color3.fromRGB(70, 20, 50), Material = Enum.Material.Fabric })
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local x, z = math.cos(a) * 1.25, math.sin(a) * 1.25
		piece(m, { Size = Vector3.new(0.35, 0.8, 0.35), CFrame = CFrame.new(x, 0.8, z), Color = gold, Material = Enum.Material.Foil })
		local gem = if i % 2 == 0 then Color3.fromRGB(80, 170, 255) else Color3.fromRGB(255, 60, 90)
		piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = CFrame.new(x, 1.3, z), Color = gem, Material = Enum.Material.Neon })
	end
	addLight(band, Color3.fromRGB(140, 200, 255), 12, 1.5)
	return band
end

TREASURE_BUILDERS.RubberDuck = function(m)
	local yellow = Color3.fromRGB(255, 215, 40)
	local body = piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = CFrame.new(), Color = yellow, Material = Enum.Material.SmoothPlastic })
	piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), CFrame = CFrame.new(0, 1.25, -0.55), Color = yellow, Material = Enum.Material.SmoothPlastic })
	piece(m, { Size = Vector3.new(0.9, 0.3, 0.7), CFrame = CFrame.new(0, 1.1, -1.4), Color = Color3.fromRGB(255, 130, 30), Material = Enum.Material.SmoothPlastic })
	for _, x in { -0.35, 0.35 } do
		piece(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.25, 0.25, 0.25), CFrame = CFrame.new(x, 1.45, -1.2), Color = Color3.fromRGB(15, 15, 15), Material = Enum.Material.SmoothPlastic })
	end
	piece(m, { Size = Vector3.new(0.8, 0.6, 0.5), CFrame = CFrame.new(0, 0.5, 1.05) * CFrame.Angles(math.rad(-30), 0, 0), Color = yellow, Material = Enum.Material.SmoothPlastic })
	return body
end

local treasureFolder = Instance.new("Folder")
treasureFolder.Name = "DigTreasures"
for _, T in TREASURES do
	local m = Instance.new("Model")
	m.Name = T.id
	m.PrimaryPart = TREASURE_BUILDERS[T.id](m)
	m.Parent = treasureFolder
end
treasureFolder.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- REMOTES + CLIENT CONFIG
--------------------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "DigRemotes"
local Remotes = {}
for _, name in { "Hit", "Surface", "Mined", "Treasure", "Geode", "Sold", "Notify", "Announce", "Bought", "Reward", "Action", "Hatched", "LevelUp", "SpinResult", "Purchased" } do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remoteFolder
	Remotes[name] = r
end

do
	local cfg = {
		top = TOP, block = BLOCK, grid = GRID, maxDepth = MAX_DEPTH, reach = REACH,
		rushEvery = RUSH_EVERY, rushLength = RUSH_LENGTH, elevatorStep = ELEVATOR_STEP, treasureBonus = TREASURE_BONUS,
		layers = {}, ores = {}, picks = {}, bags = {}, treasures = {}, treasureOrder = {},
		passes = PASSES, products = PRODUCTS, pets = PETS, eggs = EGGS, rarityColors = RARITY_COLORS,
		petSlots = PET_SLOTS, maxPets = MAX_PETS, spin = SPIN, spinCooldown = SPIN_COOLDOWN, income = INCOME,
		levelBonus = LEVEL_BONUS, ascendBonus = ASCEND_BONUS,
	}
	for _, L in LAYERS do
		table.insert(cfg.layers, { name = L.name, from = L.from, tint = L.tint, color = L.color })
	end
	for id, O in ORES do
		cfg.ores[id] = { name = O.name, color = O.color, tier = O.tier }
	end
	for _, P in PICKS do
		table.insert(cfg.picks, { name = P.name, dmg = P.dmg, speed = P.speed, price = P.price })
	end
	for _, B in BAGS do
		table.insert(cfg.bags, { name = B.name, capacity = B.capacity, price = B.price })
	end
	for _, T in TREASURES do
		cfg.treasures[T.id] = { name = T.name, depth = T.depth, hint = T.hint, color = T.color }
		table.insert(cfg.treasureOrder, T.id)
	end
	local value = Instance.new("StringValue")
	value.Name = "DigConfig"
	value.Value = HttpService:JSONEncode(cfg)
	value.Parent = remoteFolder
end

--------------------------------------------------------------------------------
-- WORLD
--------------------------------------------------------------------------------
local PIT = GRID * BLOCK / 2 -- half-width of the mine in studs (72)
local EDGE = 300
local SELL_POS = W(0, 0, -90)
local SPAWN_POS = W(0, 0, -122)
local CHEST_POS = W(-16, 0, -121)

local town = Instance.new("Folder")
town.Name = "Town"
town.Parent = workspace

local function buildWorld()
	local wood = Color3.fromRGB(122, 84, 54)
	local darkWood = Color3.fromRGB(84, 58, 40)
	local stone = Color3.fromRGB(150, 150, 156)

	-- Lighting. Technology = Future is set in the place file (scripts can't change it).
	Lighting.ClockTime = 14.4
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(86, 84, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 142)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 206)
	Lighting.ExposureCompensation = 0.15
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.3
	atmo.Offset = 0.22
	atmo.Color = Color3.fromRGB(199, 214, 234)
	atmo.Decay = Color3.fromRGB(104, 118, 150)
	atmo.Glare = 0.35
	atmo.Haze = 1.4
	atmo.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.StarCount = 3000
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 30
	bloom.Threshold = 1.15
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.07
	rays.Spread = 0.55
	rays.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WorldGrade"
	grade.Saturation = 0.12
	grade.Contrast = 0.06
	grade.TintColor = Color3.fromRGB(255, 251, 244)
	grade.Parent = Lighting

	-- Terrain: real grass (with swaying blades), paths, a lake, hills and mountains.
	local terrain = workspace.Terrain
	terrain:Clear()
	pcall(function()
		terrain.Decoration = true
	end)
	terrain.WaterColor = Color3.fromRGB(38, 120, 140)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 158, 72))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(84, 138, 62))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(118, 116, 112))
	terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(146, 138, 124))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(122, 94, 66))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(214, 196, 148))
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(240, 244, 250))
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.65
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain

	-- Ground surrounds the mine. It is 8 studs thick (2 voxels) so the mine's top row sits flush with the grass.
	local function ground(cx, cz, sx, sz, mat)
		terrain:FillBlock(CFrame.new(W(cx, -4, cz)), Vector3.new(sx, 8, sz), mat)
	end
	ground(0, (PIT + EDGE) / 2, EDGE * 2, EDGE - PIT, Enum.Material.Grass)
	ground(0, -(PIT + EDGE) / 2, EDGE * 2, EDGE - PIT, Enum.Material.Grass)
	ground(-(PIT + EDGE) / 2, 0, EDGE - PIT, PIT * 2, Enum.Material.Grass)
	ground((PIT + EDGE) / 2, 0, EDGE - PIT, PIT * 2, Enum.Material.Grass)

	-- Cobblestone paths through town, and a dirt apron around the dig site
	ground(0, -PIT - 4, PIT * 2 + 8, 8, Enum.Material.Ground)
	ground(0, PIT + 4, PIT * 2 + 8, 8, Enum.Material.Ground)
	ground(-PIT - 4, 0, 8, PIT * 2, Enum.Material.Ground)
	ground(PIT + 4, 0, 8, PIT * 2, Enum.Material.Ground)
	ground(0, -113, 264, 12, Enum.Material.Cobblestone)
	ground(0, -104, 16, 40, Enum.Material.Cobblestone)
	ground(0, -90, 120, 12, Enum.Material.Cobblestone)
	ground(0, -130, 36, 20, Enum.Material.Cobblestone)
	ground(0, -142, 20, 8, Enum.Material.Cobblestone)
	ground(78, -131, 10, 26, Enum.Material.Cobblestone)
	ground(-83, -131, 10, 26, Enum.Material.Cobblestone)

	-- Lake with a sandy shore
	local lake = W(176, 0, 150)
	terrain:FillBall(lake - Vector3.new(0, 10, 0), 44, Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(lake + Vector3.new(0, 12, 0)), Vector3.new(120, 24, 120), Enum.Material.Air)
	terrain:FillBall(lake - Vector3.new(0, 12, 0), 38, Enum.Material.Water)
	terrain:FillBlock(CFrame.new(lake + Vector3.new(0, 12, 0)), Vector3.new(120, 24, 120), Enum.Material.Air)

	-- Pit rim: log border so the dig site reads clearly
	local logColor = Color3.fromRGB(104, 72, 46)
	local function log(cf, length)
		newPart({ Name = "RimLog", Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, 1.6, 1.6), CFrame = cf, Color = logColor, Material = Enum.Material.Wood }, town)
	end
	log(CFrame.new(W(0, 0.5, PIT + 1)), PIT * 2 + 4)
	log(CFrame.new(W(0, 0.5, -PIT - 1)), PIT * 2 + 4)
	log(CFrame.new(W(PIT + 1, 0.5, 0)) * CFrame.Angles(0, math.rad(90), 0), PIT * 2 + 4)
	log(CFrame.new(W(-PIT - 1, 0.5, 0)) * CFrame.Angles(0, math.rad(90), 0), PIT * 2 + 4)

	-- Hanging lanterns around the pit
	local e = PIT + 3
	for _, c in { { -e, -e }, { e, -e }, { -e, e }, { e, e }, { 0, e }, { -e, 0 }, { e, 0 }, { 30, -e }, { -30, -e } } do
		local inward = Vector3.new(-math.sign(c[1]), 0, -math.sign(c[2]))
		if inward.Magnitude > 0 then
			inward = inward.Unit
		end
		local base = W(c[1], 0, c[2])
		newPart({ Name = "LanternPost", Size = Vector3.new(0.8, 10, 0.8), Position = base + Vector3.new(0, 5, 0), Color = darkWood, Material = Enum.Material.Wood }, town)
		newPart({ Name = "LanternArm", Size = Vector3.new(0.45, 0.45, 2.6), CFrame = CFrame.lookAt(base + Vector3.new(0, 9.6, 0) + inward * 1.2, base + Vector3.new(0, 9.6, 0) + inward * 3), Color = darkWood, Material = Enum.Material.Wood }, town)
		local hang = base + Vector3.new(0, 8, 0) + inward * 2.3
		newPart({ Name = "LanternChain", Size = Vector3.new(0.12, 1.2, 0.12), Position = hang + Vector3.new(0, 1.1, 0), Color = Color3.fromRGB(40, 40, 44), Material = Enum.Material.Metal, CanCollide = false }, town)
		newPart({ Name = "LanternCap", Size = Vector3.new(1.3, 0.3, 1.3), Position = hang + Vector3.new(0, 0.55, 0), Color = Color3.fromRGB(40, 40, 44), Material = Enum.Material.Metal, CanCollide = false }, town)
		local lamp = newPart({ Name = "Lantern", Size = Vector3.new(1, 1, 1), Position = hang, Color = Color3.fromRGB(255, 196, 110), Material = Enum.Material.Neon, CanCollide = false }, town)
		newPart({ Name = "LanternBase", Size = Vector3.new(1.2, 0.25, 1.2), Position = hang - Vector3.new(0, 0.6, 0), Color = Color3.fromRGB(40, 40, 44), Material = Enum.Material.Metal, CanCollide = false }, town)
		addLight(lamp, Color3.fromRGB(255, 184, 104), 22, 1.3)
	end

	-- Mine headframe: an A-frame tower with a big wheel over the pit, the landmark you see from spawn.
	do
		local hx, hz = PIT + 12, -30
		local top = W(hx, 34, hz)
		local timber = Color3.fromRGB(92, 64, 42)
		local function beam(a, b, thick)
			local len = (b - a).Magnitude
			newPart({ Name = "HeadframeBeam", Size = Vector3.new(thick, thick, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = timber, Material = Enum.Material.Wood }, town)
		end
		local feet = { W(hx - 7, 0, hz - 7), W(hx + 7, 0, hz - 7), W(hx - 7, 0, hz + 7), W(hx + 7, 0, hz + 7) }
		for _, f in feet do
			beam(f, top + (f - W(hx, 0, hz)) * 0.18 + Vector3.new(0, -1, 0), 1.3)
			newPart({ Name = "Footing", Size = Vector3.new(2.6, 1, 2.6), Position = f + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(120, 118, 114), Material = Enum.Material.Cobblestone }, town)
		end
		for _, hgt in { 10, 22 } do
			local k = 1 - hgt / 34 * 0.82
			local corners = {}
			for i, f in feet do
				local flat = W(hx, 0, hz) + (f - W(hx, 0, hz)) * k
				corners[i] = Vector3.new(flat.X, TOP + hgt, flat.Z)
			end
			beam(corners[1], corners[2], 0.9)
			beam(corners[3], corners[4], 0.9)
			beam(corners[1], corners[3], 0.9)
			beam(corners[2], corners[4], 0.9)
		end
		newPart({ Name = "HeadframeDeck", Size = Vector3.new(6, 0.8, 6), Position = top - Vector3.new(0, 1.2, 0), Color = timber, Material = Enum.Material.WoodPlanks }, town)
		local wheelCF = CFrame.new(top + Vector3.new(0, 3.4, 0))
		newPart({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 8, 8), CFrame = wheelCF * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(64, 60, 58), Material = Enum.Material.Metal }, town)
		newPart({ Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 1.6, 1.6), CFrame = wheelCF * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(180, 140, 70), Material = Enum.Material.Metal }, town)
		for i = 0, 3 do
			newPart({ Name = "Spoke", Size = Vector3.new(0.3, 7.4, 0.3), CFrame = wheelCF * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(i * 45), 0, 0), Color = Color3.fromRGB(90, 86, 82), Material = Enum.Material.Metal }, town)
		end
		newPart({ Name = "Rope", Size = Vector3.new(0.2, 36, 0.2), Position = top + Vector3.new(-2.6, -16, 2.6), Color = Color3.fromRGB(150, 120, 80), Material = Enum.Material.Fabric, CanCollide = false }, town)
		newPart({ Name = "Bucket", Size = Vector3.new(2.2, 2, 2.2), Position = top + Vector3.new(-2.6, -34.5, 2.6), Color = Color3.fromRGB(110, 76, 48), Material = Enum.Material.WoodPlanks, CanCollide = false }, town)
	end

	-- Street lamps along the main path
	for _, x in { -118, -70, -22, 22, 70, 118 } do
		local base = W(x, 0, -118)
		newPart({ Name = "StreetLampPole", Size = Vector3.new(0.6, 11, 0.6), Position = base + Vector3.new(0, 5.5, 0), Color = Color3.fromRGB(44, 44, 48), Material = Enum.Material.Metal }, town)
		newPart({ Name = "StreetLampBase", Size = Vector3.new(1.4, 1, 1.4), Position = base + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(44, 44, 48), Material = Enum.Material.Metal }, town)
		local bulb = newPart({ Name = "StreetLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = base + Vector3.new(0, 11.4, 0), Color = Color3.fromRGB(255, 226, 170), Material = Enum.Material.Neon, CanCollide = false }, town)
		addLight(bulb, Color3.fromRGB(255, 214, 160), 26, 1)
	end

	-- Pit sign
	newPart({ Name = "SignPost", Size = Vector3.new(0.8, 9, 0.8), Position = W(-22, 4.5, -PIT - 4), Color = darkWood, Material = Enum.Material.Wood }, town)
	newPart({ Name = "SignPost", Size = Vector3.new(0.8, 9, 0.8), Position = W(-8, 4.5, -PIT - 4), Color = darkWood, Material = Enum.Material.Wood }, town)
	local pitSign = newPart({ Name = "PitSign", Size = Vector3.new(16, 4, 0.6), Position = W(-15, 7, -PIT - 4), Color = wood, Material = Enum.Material.WoodPlanks }, town)
	signText(pitSign, Enum.NormalId.Front, "⛏ THE PIT ⛏", Color3.fromRGB(255, 225, 150))

	-- Spawn (rotated so players face the pit)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DigSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(SPAWN_POS + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = stone
	spawn.Material = Enum.Material.Cobblestone
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = town

	-- Sell pad + mine cart
	local ring = newPart({ Name = "SellRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 17, 17), CFrame = CFrame.new(SELL_POS + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(120, 84, 30), Material = Enum.Material.Metal, CanCollide = false }, town)
	ring.CanQuery = false
	local pad = newPart({ Name = "SellPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 15, 15), CFrame = CFrame.new(SELL_POS + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 196, 60), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false }, town)
	CollectionService:AddTag(pad, "SellPad")
	addLight(pad, Color3.fromRGB(255, 200, 90), 14, 0.8)
	billboard(pad, 7, { { "Title", "💰 SELL", 30, Color3.fromRGB(255, 214, 90) }, { "Sub", "Step on the pad to sell your ore", 15, Color3.fromRGB(240, 240, 240) } }, 90)
	do
		local k = SELL_POS + Vector3.new(-13, 0, 0)
		local plank = Color3.fromRGB(140, 98, 60)
		newPart({ Name = "KioskFloor", Size = Vector3.new(7, 0.4, 7), Position = k + Vector3.new(0, 0.2, 0), Color = plank, Material = Enum.Material.WoodPlanks }, town)
		for _, dx in { -3.2, 3.2 } do
			for _, dz in { -3.2, 3.2 } do
				newPart({ Name = "KioskPost", Size = Vector3.new(0.6, 8, 0.6), Position = k + Vector3.new(dx, 4, dz), Color = darkWood, Material = Enum.Material.Wood }, town)
			end
		end
		newPart({ Name = "KioskCounter", Size = Vector3.new(0.9, 3.4, 6.4), Position = k + Vector3.new(3.1, 1.7, 0), Color = plank, Material = Enum.Material.WoodPlanks }, town)
		newPart({ Name = "KioskCounterTop", Size = Vector3.new(1.6, 0.3, 7), Position = k + Vector3.new(3.1, 3.5, 0), Color = darkWood, Material = Enum.Material.Wood }, town)
		newPart({ Name = "KioskRoof", Size = Vector3.new(8.4, 0.5, 8.4), CFrame = CFrame.new(k + Vector3.new(0.4, 8.4, 0)) * CFrame.Angles(0, 0, math.rad(-10)), Color = Color3.fromRGB(196, 150, 50), Material = Enum.Material.Fabric }, town)
		-- balance scale on the counter
		local scaleBase = k + Vector3.new(3.1, 3.65, 1.5)
		newPart({ Name = "ScalePost", Size = Vector3.new(0.25, 1.8, 0.25), Position = scaleBase + Vector3.new(0, 0.9, 0), Color = Color3.fromRGB(230, 180, 70), Material = Enum.Material.Foil }, town)
		newPart({ Name = "ScaleBeam", Size = Vector3.new(0.2, 0.2, 2.4), Position = scaleBase + Vector3.new(0, 1.8, 0), Color = Color3.fromRGB(230, 180, 70), Material = Enum.Material.Foil }, town)
		for _, dz in { -1.1, 1.1 } do
			newPart({ Name = "ScalePan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1, 1), CFrame = CFrame.new(scaleBase + Vector3.new(0, 1.1, dz)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(230, 180, 70), Material = Enum.Material.Foil }, town)
		end
		for i = 1, 5 do
			newPart({ Name = "CoinStack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 0.7, 0.7), CFrame = CFrame.new(k + Vector3.new(3.1, 3.7 + i * 0.18, -1.6)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil }, town)
		end
		local board = newPart({ Name = "KioskSign", Size = Vector3.new(0.4, 2, 7.4), Position = k + Vector3.new(3.4, 6.7, 0), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
		signText(board, Enum.NormalId.Right, "ORE EXCHANGE", Color3.fromRGB(255, 220, 120))
		local lamp = newPart({ Name = "KioskLamp", Size = Vector3.new(0.8, 0.8, 0.8), Position = k + Vector3.new(0, 7.4, 0), Color = Color3.fromRGB(255, 210, 140), Material = Enum.Material.Neon, CanCollide = false }, town)
		addLight(lamp, Color3.fromRGB(255, 200, 130), 14, 1)
	end
	local cartPos = SELL_POS + Vector3.new(12, 0, 0)
	newPart({ Name = "Cart", Size = Vector3.new(6, 2.6, 4), Position = cartPos + Vector3.new(0, 2.2, 0), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
	newPart({ Name = "CartRim", Size = Vector3.new(6.4, 0.4, 4.4), Position = cartPos + Vector3.new(0, 3.6, 0), Color = Color3.fromRGB(80, 80, 88), Material = Enum.Material.Metal }, town)
	for _, wx in { -2, 2 } do
		for _, wz in { -2.1, 2.1 } do
			newPart({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.8, 1.8), CFrame = CFrame.new(cartPos + Vector3.new(wx, 0.9, wz)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal }, town)
		end
	end
	local cartRng = Random.new(3)
	for _ = 1, 9 do
		local o = ORES[({ "Coal", "Copper", "Iron", "Gold", "Ruby", "Emerald" })[cartRng:NextInteger(1, 6)]]
		newPart({ Name = "Ore", Shape = Enum.PartType.Ball, Size = Vector3.one * cartRng:NextNumber(1, 1.6), Position = cartPos + Vector3.new(cartRng:NextNumber(-2, 2), 3.9, cartRng:NextNumber(-1.2, 1.2)), Color = rgb(o.color), Material = material(o.material), CanCollide = false }, town)
	end

	-- Market stalls: pickaxes on the left of the path, backpacks on the right.
	-- Market stalls face the spawn plaza, with their back walls towards the quarry.
	local function stall(centerX, count, roofA, title)
		local length = count * 12 + 4
		newPart({ Name = "StallWall", Size = Vector3.new(length, 10.4, 1), Position = W(centerX, 5.2, -97.5), Color = wood, Material = Enum.Material.WoodPlanks }, town)
		newPart({ Name = "StallTrim", Size = Vector3.new(length + 0.4, 0.6, 1.4), Position = W(centerX, 10.5, -97.5), Color = darkWood, Material = Enum.Material.Wood }, town)
		newPart({ Name = "StallFloor", Size = Vector3.new(length, 0.4, 10), Position = W(centerX, 0.2, -102.5), Color = Color3.fromRGB(150, 110, 72), Material = Enum.Material.WoodPlanks }, town)
		for i = 1, count do
			local x = centerX - length / 2 + 2 + (i - 0.5) * 12
			local color = if i % 2 == 0 then roofA else Color3.fromRGB(245, 236, 216)
			newPart({ Name = "Awning", Size = Vector3.new(12, 0.5, 10), CFrame = CFrame.new(W(x, 11, -102.4)) * CFrame.Angles(math.rad(-16), 0, 0), Color = color, Material = Enum.Material.Fabric }, town)
			-- scalloped valance along the front edge
			newPart({ Name = "Valance", Size = Vector3.new(12, 1.1, 0.25), Position = W(x, 9, -107.2), Color = color, Material = Enum.Material.Fabric, CanCollide = false }, town)
		end
		for j = 0, count do
			local x = centerX - length / 2 + 2 + j * 12
			newPart({ Name = "StallPost", Size = Vector3.new(0.7, 9.8, 0.7), Position = W(x, 4.9, -107), Color = darkWood, Material = Enum.Material.Wood }, town)
		end
		local board = newPart({ Name = "StallSign", Size = Vector3.new(26, 4.6, 0.6), Position = W(centerX, 14.2, -97.2), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
		newPart({ Name = "StallSignFrame", Size = Vector3.new(27, 5.4, 0.4), Position = W(centerX, 14.2, -96.9), Color = Color3.fromRGB(60, 40, 26), Material = Enum.Material.Wood }, town)
		signText(board, Enum.NormalId.Front, title, Color3.fromRGB(255, 230, 160))
	end

	local function pedestal(x, z, kind, tier, name, stats, price)
		local cloth = if kind == "Pick" then Color3.fromRGB(150, 32, 40) else Color3.fromRGB(34, 64, 140)
		local base = newPart({ Name = "Pedestal", Size = Vector3.new(5.4, 3, 5.4), Position = W(x, 1.9, z), Color = Color3.fromRGB(128, 88, 54), Material = Enum.Material.WoodPlanks }, town)
		newPart({ Name = "PedestalCloth", Size = Vector3.new(6, 0.3, 6), Position = W(x, 3.5, z), Color = cloth, Material = Enum.Material.Fabric }, town)
		newPart({ Name = "PedestalDrape", Size = Vector3.new(6, 1.4, 0.2), Position = W(x, 2.8, z - 3), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false }, town)
		newPart({ Name = "PedestalTrim", Size = Vector3.new(6.1, 0.18, 0.25), Position = W(x, 2.1, z - 3.02), Color = Color3.fromRGB(230, 180, 70), Material = Enum.Material.Foil, CanCollide = false }, town)
		billboard(base, 8.5, {
			{ "Title", name, 20, Color3.fromRGB(255, 255, 255) },
			{ "Stats", stats, 14, Color3.fromRGB(205, 210, 220) },
			{ "Price", if price == 0 then "FREE" else "💰 " .. fmt(price), 18, Color3.fromRGB(255, 214, 90) },
		}, 45)
		local p = prompt(base, kind, "Buy", name, 0, tier)
		CollectionService:AddTag(p, "ShopItem")
		return base
	end

	local pickStart = -24
	stall(pickStart - (#PICKS - 1) * 6, #PICKS, Color3.fromRGB(205, 62, 52), "⛏ PICKAXES")
	for i, P in PICKS do
		local x = pickStart - (i - 1) * 12
		pedestal(x, -104, "Pick", i, P.name, `⛏ {fmt(P.dmg)} power · {string.format("%.1f", 1 / P.speed)} swings/s`, P.price)
		local model = buildPick(i)
		model:PivotTo(CFrame.new(W(x, 5.9, -104)) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, math.rad(20), 0))
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		CollectionService:AddTag(model, "Spin")
		model.Parent = town
	end

	local bagStart = 24
	stall(bagStart + (#BAGS - 1) * 6, #BAGS, Color3.fromRGB(52, 110, 205), "🎒 BACKPACKS")
	for i, B in BAGS do
		local x = bagStart + (i - 1) * 12
		pedestal(x, -104, "Bag", i, B.name, `🎒 holds {fmt(B.capacity)} blocks`, B.price)
		local model = buildBag(i, 1.1)
		model:PivotTo(CFrame.new(W(x, 5.6, -104)))
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		CollectionService:AddTag(model, "Spin")
		model.Parent = town
	end

	-- Elevator
	local ex, ez = 44, -84
	local platform = newPart({ Name = "ElevatorPlatform", Size = Vector3.new(8, 0.6, 8), Position = W(ex, 0.3, ez), Color = Color3.fromRGB(90, 92, 100), Material = Enum.Material.DiamondPlate }, town)
	for _, dx in { -3.8, 3.8 } do
		for _, dz in { -3.8, 3.8 } do
			newPart({ Name = "ElevatorPost", Size = Vector3.new(0.7, 14, 0.7), Position = W(ex + dx, 7, ez + dz), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal }, town)
			local strip = newPart({ Name = "ElevatorLight", Size = Vector3.new(0.3, 10, 0.3), Position = W(ex + dx * 0.93, 7, ez + dz * 0.93), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Neon, CanCollide = false }, town)
			strip.CanQuery = false
		end
	end
	newPart({ Name = "ElevatorTop", Size = Vector3.new(8.8, 0.8, 8.8), Position = W(ex, 14.2, ez), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal }, town)
	newPart({ Name = "ElevatorWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 4, 4), CFrame = CFrame.new(W(ex, 16.4, ez)), Color = Color3.fromRGB(150, 110, 60), Material = Enum.Material.Metal }, town)
	CollectionService:AddTag(platform, "Elevator")
	billboard(platform, 16, { { "Title", "⬇ ELEVATOR", 24, Color3.fromRGB(255, 214, 90) }, { "Sub", "Unlocks at " .. ELEVATOR_STEP .. "m", 15, Color3.fromRGB(240, 240, 240) } }, 80)
	prompt(platform, "Elevator", "Ride down", "Elevator", 0.4)

	-- Daily chest
	local chest = newPart({ Name = "DailyChest", Size = Vector3.new(4, 2.4, 3), Position = CHEST_POS + Vector3.new(0, 1.2, 0), Color = Color3.fromRGB(140, 86, 44), Material = Enum.Material.WoodPlanks }, town)
	newPart({ Name = "ChestLid", Size = Vector3.new(4.2, 1, 3.2), Position = CHEST_POS + Vector3.new(0, 2.9, 0), Color = Color3.fromRGB(120, 72, 36), Material = Enum.Material.WoodPlanks }, town)
	for _, dx in { -1.4, 1.4 } do
		newPart({ Name = "ChestBand", Size = Vector3.new(0.4, 3.5, 3.3), Position = CHEST_POS + Vector3.new(dx, 1.75, 0), Color = Color3.fromRGB(240, 190, 70), Material = Enum.Material.Foil, CanCollide = false }, town)
	end
	local lock = newPart({ Name = "ChestLock", Size = Vector3.new(0.7, 0.8, 0.3), Position = CHEST_POS + Vector3.new(0, 2.4, 1.65), Color = Color3.fromRGB(255, 210, 80), Material = Enum.Material.Foil, CanCollide = false }, town)
	addLight(lock, Color3.fromRGB(255, 210, 100), 10, 0.9)
	CollectionService:AddTag(chest, "DailyChest")
	billboard(chest, 5, { { "Title", "🎁 DAILY CHEST", 20, Color3.fromRGB(255, 214, 90) }, { "Sub", "", 15, Color3.fromRGB(240, 240, 240) } }, 60)
	prompt(chest, "Daily", "Open", "Daily Chest", 0.3)

	-- Fountain in the town square behind spawn
	do
		local f = W(0, 0, -137)
		local stoneCol = Color3.fromRGB(176, 170, 160)
		newPart({ Name = "FountainBasin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 13, 13), CFrame = CFrame.new(f + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = stoneCol, Material = Enum.Material.Cobblestone }, town)
		newPart({ Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 11.6, 11.6), CFrame = CFrame.new(f + Vector3.new(0, 1.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 160, 200), Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.3, CanCollide = false }, town)
		newPart({ Name = "FountainPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 1.6, 1.6), CFrame = CFrame.new(f + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = stoneCol, Material = Enum.Material.Marble }, town)
		newPart({ Name = "FountainBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 5, 5), CFrame = CFrame.new(f + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = stoneCol, Material = Enum.Material.Marble }, town)
		local gem = newPart({ Name = "FountainGem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = f + Vector3.new(0, 7.3, 0), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.Neon, CanCollide = false }, town)
		addLight(gem, Color3.fromRGB(120, 210, 255), 16, 1)
		local spray = Instance.new("ParticleEmitter")
		spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.9) })
		spray.Lifetime = NumberRange.new(0.8, 1.1)
		spray.Speed = NumberRange.new(9, 11)
		spray.SpreadAngle = Vector2.new(18, 18)
		spray.Acceleration = Vector3.new(0, -30, 0)
		spray.Rate = 60
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = gem
		for k = 0, 3 do
			local ang = math.pi / 4 + k * math.pi / 2
			newPart({ Name = "Bench", Size = Vector3.new(4.5, 0.5, 1.4), CFrame = CFrame.new(f + Vector3.new(math.cos(ang) * 11, 1.3, math.sin(ang) * 11)) * CFrame.Angles(0, -ang + math.pi / 2, 0), Color = Color3.fromRGB(128, 88, 54), Material = Enum.Material.WoodPlanks }, town)
			newPart({ Name = "BenchLegs", Size = Vector3.new(3.6, 1.1, 0.8), CFrame = CFrame.new(f + Vector3.new(math.cos(ang) * 11, 0.55, math.sin(ang) * 11)) * CFrame.Angles(0, -ang + math.pi / 2, 0), Color = Color3.fromRGB(70, 70, 74), Material = Enum.Material.Metal }, town)
		end
	end

	-- Ascension shrine: dark obsidian platform with a floating star crystal
	do
		local c = W(78, 0, -150)
		newPart({ Name = "ShrineBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 16, 16), CFrame = CFrame.new(c + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(34, 26, 46), Material = Enum.Material.Basalt }, town)
		newPart({ Name = "ShrineRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 12, 12), CFrame = CFrame.new(c + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(170, 110, 255), Material = Enum.Material.Neon, CanCollide = false }, town)
		local altar = newPart({ Name = "ShrineAltar", Size = Vector3.new(4, 3.2, 4), Position = c + Vector3.new(0, 2.8, 0), Color = Color3.fromRGB(44, 34, 60), Material = Enum.Material.Basalt }, town)
		newPart({ Name = "ShrineAltarStep", Size = Vector3.new(5.6, 0.8, 5.6), Position = c + Vector3.new(0, 1.6, 0), Color = Color3.fromRGB(56, 44, 74), Material = Enum.Material.Basalt }, town)
		newPart({ Name = "ShrineAltarTop", Size = Vector3.new(4.6, 0.4, 4.6), Position = c + Vector3.new(0, 4.6, 0), Color = Color3.fromRGB(170, 110, 255), Material = Enum.Material.Neon, CanCollide = false }, town)
		for i = 1, 4 do
			local ang = i / 4 * math.pi * 2 + math.pi / 4
			newPart({ Name = "ShrineSpire", Size = Vector3.new(0.9, 9, 0.9), CFrame = CFrame.new(c + Vector3.new(math.cos(ang) * 6.5, 4.5, math.sin(ang) * 6.5)) * CFrame.Angles(0, ang, 0), Color = Color3.fromRGB(40, 30, 56), Material = Enum.Material.Basalt }, town)
			local tip = newPart({ Name = "ShrineSpireTip", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), Position = c + Vector3.new(math.cos(ang) * 6.5, 9.2, math.sin(ang) * 6.5), Color = Color3.fromRGB(190, 130, 255), Material = Enum.Material.Neon, CanCollide = false }, town)
			tip.CanQuery = false
		end
		local star = Instance.new("Model")
		star.Name = "ShrineStar"
		local core = piece(star, { Size = Vector3.new(1.6, 3.2, 1.6), CFrame = CFrame.new(), Color = Color3.fromRGB(215, 170, 255), Material = Enum.Material.Neon })
		piece(star, { Size = Vector3.new(3.2, 1.6, 1.6), CFrame = CFrame.Angles(0, 0, math.rad(45)), Color = Color3.fromRGB(190, 140, 255), Material = Enum.Material.Glass, Transparency = 0.2 })
		piece(star, { Size = Vector3.new(1.6, 1.6, 3.2), CFrame = CFrame.Angles(math.rad(45), 0, 0), Color = Color3.fromRGB(190, 140, 255), Material = Enum.Material.Glass, Transparency = 0.2 })
		addLight(core, Color3.fromRGB(190, 130, 255), 22, 2)
		star.PrimaryPart = core
		star:PivotTo(CFrame.new(c + Vector3.new(0, 7.5, 0)))
		CollectionService:AddTag(star, "Spin")
		star.Parent = town
		CollectionService:AddTag(altar, "Shrine")
		billboard(altar, 9, { { "Title", "⭐ ASCENSION", 22, Color3.fromRGB(215, 175, 255) }, { "Sub", "Reach bedrock (" .. MAX_DEPTH .. "m) to unlock", 14, Color3.fromRGB(235, 235, 245) } }, 70)
		prompt(altar, "Ascend", "Ascend", "Ascension Shrine", 2)
	end

	-- Pet shop: four egg stands (odds shown on each, like every simulator)
	do
		local plank = Color3.fromRGB(140, 98, 60)
		newPart({ Name = "PetShopFloor", Size = Vector3.new(64, 0.4, 18), Position = W(-83, 0.2, -150), Color = Color3.fromRGB(236, 214, 170), Material = Enum.Material.WoodPlanks }, town)
		newPart({ Name = "PetShopBack", Size = Vector3.new(64, 12, 1), Position = W(-83, 6, -159.5), Color = Color3.fromRGB(255, 200, 220), Material = Enum.Material.WoodPlanks }, town)
		local board = newPart({ Name = "PetShopSign", Size = Vector3.new(26, 5, 0.6), Position = W(-83, 14.6, -159.2), Color = Color3.fromRGB(120, 60, 90), Material = Enum.Material.WoodPlanks }, town)
		signText(board, Enum.NormalId.Front, "🥚 PET SHOP", Color3.fromRGB(255, 230, 245))
		for i = 0, 5 do
			newPart({ Name = "PetShopAwning", Size = Vector3.new(64 / 6, 0.5, 8), CFrame = CFrame.new(W(-83 - 32 + (i + 0.5) * 64 / 6, 12.4, -156)) * CFrame.Angles(math.rad(-18), 0, 0), Color = if i % 2 == 0 then Color3.fromRGB(255, 120, 170) else Color3.fromRGB(255, 244, 250), Material = Enum.Material.Fabric }, town)
		end
		for i, egg in EGGS do
			local x = -104 + (i - 1) * 14
			local base = newPart({ Name = "EggStand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 7, 7), CFrame = CFrame.new(W(x, 1.6, -150)) * CFrame.Angles(0, 0, math.rad(90)), Color = plank, Material = Enum.Material.WoodPlanks }, town)
			local eggRing = newPart({ Name = "EggRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 7.4, 7.4), CFrame = CFrame.new(W(x, 2.9, -150)) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(egg.spots), Material = Enum.Material.Neon, CanCollide = false }, town)
			eggRing.CanQuery = false
			local model = Instance.new("Model")
			model.Name = egg.id
			local shell = piece(model, { Size = Vector3.new(4.6, 6, 4.6), CFrame = CFrame.new(), Color = rgb(egg.color), Material = Enum.Material.SmoothPlastic, Reflectance = 0.05 })
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = shell
			local er = Random.new(i * 17)
			for _ = 1, 7 do
				local a, h = er:NextNumber(0, math.pi * 2), er:NextNumber(-0.7, 0.8)
				local r = math.sqrt(1 - h * h)
				piece(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * er:NextNumber(0.8, 1.3), CFrame = CFrame.new(math.cos(a) * r * 2.2, h * 2.9, math.sin(a) * r * 2.2), Color = rgb(egg.spots), Material = Enum.Material.SmoothPlastic })
			end
			addLight(shell, rgb(egg.spots), 10, 0.8)
			model.PrimaryPart = shell
			model:PivotTo(CFrame.new(W(x, 6.6, -150)))
			CollectionService:AddTag(model, "Spin")
			model.Parent = town
			local odds = {}
			for _, entry in egg.pets do
				table.insert(odds, `{PETS[entry[1]].name} {entry[2]}%`)
			end
			base:SetAttribute("Egg", i)
			CollectionService:AddTag(base, "EggStand")
			billboard(base, 9.5, {
				{ "Title", egg.name, 20, Color3.fromRGB(255, 255, 255) },
				{ "Price", "💰 " .. fmt(egg.price), 18, Color3.fromRGB(255, 214, 90) },
				{ "Odds1", odds[1] .. " · " .. odds[2], 12, Color3.fromRGB(215, 215, 225) },
				{ "Odds2", odds[3] .. " · " .. odds[4], 12, rgb(RARITY_COLORS.Legendary) },
			}, 45)
			local pr = prompt(base, "Egg", "Hatch", egg.name, 0.3)
			pr:SetAttribute("Egg", i)
		end
	end

	-- Museum: a small marble temple with steps, columns, a frieze and a pediment
	local mz = -164
	local marble = Color3.fromRGB(238, 234, 226)
	newPart({ Name = "MuseumFloor", Size = Vector3.new(106, 1, 30), Position = W(0, 0.5, mz), Color = marble, Material = Enum.Material.Marble }, town)
	newPart({ Name = "MuseumStep", Size = Vector3.new(106, 0.5, 2.5), Position = W(0, 0.25, mz + 16.2), Color = marble, Material = Enum.Material.Marble }, town)
	newPart({ Name = "MuseumWall", Size = Vector3.new(106, 18.6, 1.5), Position = W(0, 10.3, mz - 14.5), Color = Color3.fromRGB(214, 204, 190), Material = Enum.Material.Marble }, town)
	for _, x in { -53, 53 } do
		newPart({ Name = "MuseumSideWall", Size = Vector3.new(1.5, 18.6, 29), Position = W(x, 10.3, mz), Color = Color3.fromRGB(214, 204, 190), Material = Enum.Material.Marble }, town)
	end
	for _, x in { -48, -32, -16, 16, 32, 48 } do
		newPart({ Name = "PillarBase", Size = Vector3.new(3.2, 0.8, 3.2), Position = W(x, 1.4, mz + 13), Color = marble, Material = Enum.Material.Marble }, town)
		newPart({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14.2, 2.4, 2.4), CFrame = CFrame.new(W(x, 8.9, mz + 13)) * CFrame.Angles(0, 0, math.rad(90)), Color = marble, Material = Enum.Material.Marble }, town)
		newPart({ Name = "PillarCap", Size = Vector3.new(3.2, 0.8, 3.2), Position = W(x, 16.4, mz + 13), Color = marble, Material = Enum.Material.Marble }, town)
	end
	local frieze = newPart({ Name = "MuseumFrieze", Size = Vector3.new(110, 3, 2.4), Position = W(0, 18.3, mz + 13.4), Color = marble, Material = Enum.Material.Marble }, town)
	signText(frieze, Enum.NormalId.Back, "MUSEUM OF THE DEEP", Color3.fromRGB(120, 90, 50))
	newPart({ Name = "MuseumRoof", Size = Vector3.new(112, 1.2, 34), Position = W(0, 20.4, mz - 0.6), Color = marble, Material = Enum.Material.Marble }, town)
	for side = -1, 1, 2 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Pediment"
		wedge.Anchored = true
		wedge.Size = Vector3.new(2.4, 8, 56)
		wedge.CFrame = CFrame.new(W(side * 28, 25, mz + 13.4)) * CFrame.Angles(0, math.rad(-90 * side), 0)
		wedge.Color = marble
		wedge.Material = Enum.Material.Marble
		wedge.Parent = town
		local slope = Instance.new("WedgePart")
		slope.Name = "RoofSlope"
		slope.Anchored = true
		slope.Size = Vector3.new(30, 8, 56)
		slope.CFrame = CFrame.new(W(side * 28, 25, mz - 2.6)) * CFrame.Angles(0, math.rad(-90 * side), 0)
		slope.Color = Color3.fromRGB(170, 74, 58)
		slope.Material = Enum.Material.ClayRoofTiles
		slope.Parent = town
	end
	local progress = newPart({ Name = "MuseumProgress", Size = Vector3.new(1, 1, 1), Position = W(0, 3, mz + 12), Transparency = 1, CanCollide = false }, town)
	progress.CanQuery = false
	CollectionService:AddTag(progress, "MuseumSign")
	billboard(progress, 1.5, { { "Title", "0 / " .. #TREASURES .. " treasures found", 20, Color3.fromRGB(255, 255, 255) }, { "Sub", "Each new treasure: +10% ore value forever", 14, Color3.fromRGB(255, 214, 90) } }, 80)
	for i, T in TREASURES do
		local x = -42 + (i - 1) * 12
		local base = newPart({ Name = "MuseumPedestal", Size = Vector3.new(5, 4, 5), Position = W(x, 3, mz - 4), Color = Color3.fromRGB(245, 242, 236), Material = Enum.Material.Marble }, town)
		newPart({ Name = "MuseumPedestalTop", Size = Vector3.new(5.6, 0.4, 5.6), Position = W(x, 5.2, mz - 4), Color = Color3.fromRGB(200, 170, 110), Material = Enum.Material.Foil }, town)
		base:SetAttribute("Treasure", T.id)
		CollectionService:AddTag(base, "MuseumItem")
		billboard(base, 8.5, { { "Title", "???", 18, Color3.fromRGB(255, 255, 255) }, { "Sub", T.hint, 13, Color3.fromRGB(200, 200, 210) } }, 45)
		local display = treasureFolder[T.id]:Clone()
		display.Name = "Display_" .. T.id
		display:SetAttribute("Treasure", T.id)
		display:PivotTo(CFrame.new(W(x, 8, mz - 4)))
		display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		CollectionService:AddTag(display, "Spin")
		CollectionService:AddTag(display, "MuseumDisplay")
		display.Parent = town
	end

	-- Scenery: terrain mountains ring the world, rolling hills, trees, bushes, rocks and flowers.
	local sr = Random.new(42)
	for i = 1, 20 do
		local a = (i / 20) * math.pi * 2 + sr:NextNumber(-0.08, 0.08)
		local dist = sr:NextNumber(315, 370)
		local r = sr:NextNumber(62, 100)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local c = W(dir.X * dist, -r * 0.5, dir.Z * dist)
		terrain:FillBall(c, r, Enum.Material.Rock)
		terrain:FillBall(c - Vector3.new(0, r * 0.25, 0) - dir * r * 0.25, r * 0.9, Enum.Material.Grass)
		-- a ridge of smaller peaks gives each mountain a jagged silhouette
		local peak = c
		for k = 1, 3 do
			local rk = r * (0.62 - k * 0.1)
			local p2 = c + side * sr:NextNumber(-r * 0.6, r * 0.6) + dir * sr:NextNumber(0, r * 0.3) + Vector3.new(0, r * (0.35 + k * 0.17), 0)
			terrain:FillBall(p2, rk, Enum.Material.Rock)
			if p2.Y + rk > peak.Y then
				peak = p2 + Vector3.new(0, rk, 0)
			end
		end
		if peak.Y - TOP > 55 then
			terrain:FillBall(peak - Vector3.new(0, 7, 0), 11, Enum.Material.Snow)
		end
	end
	local function blocked(x, z, pad)
		pad = pad or 0
		if math.abs(x) < PIT + 16 + pad and math.abs(z) < PIT + 16 + pad then
			return true
		end
		if (Vector2.new(x, z) - Vector2.new(176, 150)).Magnitude < 52 + pad then
			return true
		end
		if x > PIT and x < PIT + 26 and z > -46 and z < -14 then
			return true
		end
		return x > -145 - pad and x < 145 + pad and z > -195 - pad and z < -70 + pad
	end
	for _ = 1, 16 do
		local x, z = sr:NextNumber(-250, 250), sr:NextNumber(-250, 250)
		local r = sr:NextNumber(24, 42)
		if not blocked(x, z, r) then
			terrain:FillBall(W(x, -r * 0.78, z), r, Enum.Material.Grass)
		end
	end
	local function oak(x, z)
		local h = sr:NextNumber(9, 15)
		local lean = CFrame.Angles(sr:NextNumber(-0.06, 0.06), 0, sr:NextNumber(-0.06, 0.06))
		newPart({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h + 2, 1.8, 1.8), CFrame = CFrame.new(W(x, h / 2 - 1, z)) * lean * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(98, 70, 48), Material = Enum.Material.Wood }, town)
		local crown = W(x, h + 2, z)
		local size = sr:NextNumber(5.5, 8)
		terrain:FillBall(crown, size, Enum.Material.LeafyGrass)
		for _ = 1, 3 do
			terrain:FillBall(crown + Vector3.new(sr:NextNumber(-4, 4), sr:NextNumber(-2, 3), sr:NextNumber(-4, 4)), size * sr:NextNumber(0.55, 0.75), Enum.Material.LeafyGrass)
		end
	end
	local function pine(x, z)
		local h = sr:NextNumber(14, 22)
		newPart({ Name = "PineTrunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 1.4, 1.4), CFrame = CFrame.new(W(x, h / 2 - 1, z)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(86, 60, 42), Material = Enum.Material.Wood }, town)
		local r = sr:NextNumber(5, 6.5)
		local y = 5
		while r > 1.4 do
			terrain:FillBall(W(x, y, z), r, Enum.Material.Grass)
			y += r * 0.9
			r *= 0.72
		end
	end
	local placed, tries = 0, 0
	while placed < 11 and tries < 2000 do
		tries += 1
		local gx, gz = sr:NextNumber(-250, 250), sr:NextNumber(-250, 250)
		if not blocked(gx, gz, 20) then
			placed += 1
			local pines = sr:NextNumber() < 0.5
			for _ = 1, sr:NextInteger(5, 9) do
				local x, z = gx + sr:NextNumber(-24, 24), gz + sr:NextNumber(-24, 24)
				if not blocked(x, z, 4) then
					if pines == (sr:NextNumber() < 0.8) then
						pine(x, z)
					else
						oak(x, z)
					end
				end
			end
		end
	end
	placed, tries = 0, 0
	while placed < 16 and tries < 2000 do
		tries += 1
		local x, z = sr:NextNumber(-270, 270), sr:NextNumber(-270, 270)
		if not blocked(x, z, 4) then
			placed += 1
			oak(x, z)
		end
	end
	-- Patchy ground: lusher grass and bare earth break up the flat green.
	for _ = 1, 60 do
		local x, z = sr:NextNumber(-280, 280), sr:NextNumber(-280, 280)
		if not blocked(x, z, 6) then
			local r = sr:NextNumber(8, 20)
			terrain:FillBall(W(x, -r + 1.5, z), r, if sr:NextNumber() < 0.8 then Enum.Material.LeafyGrass else Enum.Material.Ground)
		end
	end
	placed, tries = 0, 0
	while placed < 45 and tries < 2000 do
		tries += 1
		local x, z = sr:NextNumber(-270, 270), sr:NextNumber(-270, 270)
		if not blocked(x, z) then
			placed += 1
			local r = sr:NextNumber(2.5, 4.5)
			terrain:FillBall(W(x, -r * 0.2, z), r, if placed % 3 == 0 then Enum.Material.Rock else Enum.Material.LeafyGrass)
		end
	end
	-- Bushes and rocks right around town so it doesn't look bare
	for _, spot in { { -140, -80 }, { 140, -80 }, { -60, -190 }, { 60, -190 }, { -150, -150 }, { 150, -150 }, { -88, -70 }, { 88, -70 } } do
		terrain:FillBall(W(spot[1], -1, spot[2]), sr:NextNumber(3, 4.5), Enum.Material.LeafyGrass)
		terrain:FillBall(W(spot[1] + 4, -1, spot[2] + 2), sr:NextNumber(2, 3), Enum.Material.LeafyGrass)
	end
	local flowerColors = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 130, 255), Color3.fromRGB(255, 150, 70) }
	placed, tries = 0, 0
	while placed < 50 and tries < 2000 do
		tries += 1
		local x, z = sr:NextNumber(-260, 260), sr:NextNumber(-260, 260)
		if not blocked(x, z) or (math.abs(x) > 60 and z > -85 and z < -75) then
			placed += 1
			local color = flowerColors[sr:NextInteger(1, #flowerColors)]
			for _ = 1, 6 do
				local fx, fz = x + sr:NextNumber(-3, 3), z + sr:NextNumber(-3, 3)
				local stem = newPart({ Name = "FlowerStem", Size = Vector3.new(0.12, 0.9, 0.12), Position = W(fx, 0.45, fz), Color = Color3.fromRGB(70, 130, 50), Material = Enum.Material.SmoothPlastic, CanCollide = false }, town)
				stem.CastShadow = false
				stem.CanQuery = false
				local head = newPart({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), Position = W(fx, 1, fz), Color = color, Material = Enum.Material.SmoothPlastic, CanCollide = false }, town)
				head.CastShadow = false
				head.CanQuery = false
			end
		end
	end

	return pad
end

local sellPad = buildWorld()
remoteFolder.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- THE MINE
-- Blocks are created lazily: only blocks touching air exist. Breaking one creates its hidden neighbours.
-- cells[key] = nil (solid, not built yet) | false (air) | true (outside, solid) | Part
--------------------------------------------------------------------------------
local mineFolder = Instance.new("Folder")
mineFolder.Name = "Mine"
mineFolder.Parent = workspace

local cells = {}
local blockInfo = {}
local partCount = 0
local DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
local GEODE_COLOR = Color3.fromRGB(170, 95, 255)

local function cellKey(x, y, z)
	return (x + 1) + (z + 1) * 64 + y * 4096
end

local function cellPos(x, y, z)
	return Vector3.new((x - GRID / 2 + 0.5) * BLOCK, TOP - y * BLOCK - BLOCK / 2, (z - GRID / 2 + 0.5) * BLOCK)
end

local function layerAt(y)
	local found = LAYERS[1]
	for _, L in LAYERS do
		if y >= L.from then
			found = L
		end
	end
	return found
end

local function layerAverage(L)
	local avg = L.value
	for _, o in L.ores do
		avg += o.chance * ORES[o.id].value
	end
	return avg
end

local function rushActive()
	return workspace:GetServerTimeNow() % RUSH_EVERY < RUSH_LENGTH
end

local function rollKind(y, L)
	if y >= GEODE_MIN_DEPTH and rng:NextNumber() < GEODE_CHANCE then
		return "Geode"
	end
	local boost = if rushActive() then RUSH_MULT else 1
	local r = rng:NextNumber()
	local acc = 0
	for _, o in L.ores do
		acc += o.chance * boost
		if r < acc then
			return o.id
		end
	end
	return ""
end

-- Ore and geode blocks are stone with nuggets or crystals growing out of every face.
local FACE_NORMALS = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

local function orePiece(block, color, mat)
	local piece = Instance.new("Part")
	piece.Name = "Nugget"
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.Color = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber() * 0.18)
	piece.Material = mat
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = block
	return piece
end

-- Ore shows as chunky lumps set into the rock (walls and ceilings) and low inlays on floors,
-- so nothing looks like loose litter. Gems also grow crystal clusters from the sides and ceiling.
local function decorate(block, color, mat, crystal, count)
	local center = block.Position
	for _, n in FACE_NORMALS do
		local t1 = if math.abs(n.Y) > 0.5 then Vector3.xAxis else Vector3.yAxis
		local t2 = n:Cross(t1)
		local floorFace = n.Y > 0.5
		for _ = 1, math.max(2, math.floor(count / 3)) do
			local spot = center + n * (BLOCK / 2) + t1 * rng:NextNumber(-1.8, 1.8) + t2 * rng:NextNumber(-1.8, 1.8)
			local lump = orePiece(block, color, mat)
			if floorFace then
				lump.Size = Vector3.new(rng:NextNumber(1, 1.9), rng:NextNumber(0.8, 1.5), 0.1)
				lump.CFrame = CFrame.lookAt(spot + n * 0.03, spot + n, t1) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi))
			else
				local sz = rng:NextNumber(0.9, 1.5)
				lump.Size = Vector3.new(sz, sz * rng:NextNumber(0.7, 1), sz * rng:NextNumber(0.7, 1))
				-- mostly buried: only a corner or edge breaks the surface
				lump.CFrame = CFrame.new(spot + n * (sz * 0.12)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
			end
		end
		if crystal and not floorFace and rng:NextNumber() < 0.7 then
			local base = center + n * (BLOCK / 2) + t1 * rng:NextNumber(-1.2, 1.2) + t2 * rng:NextNumber(-1.2, 1.2)
			for _ = 1, rng:NextInteger(2, 4) do
				local len = rng:NextNumber(1.2, 2.6)
				local spike = orePiece(block, color, mat)
				spike.Size = Vector3.new(0.5, len, 0.5)
				spike.CFrame = CFrame.lookAt(base, base + n, t1) * CFrame.Angles(-math.pi / 2, 0, 0)
					* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5))
					* CFrame.new(0, len * 0.35, 0)
			end
		end
	end
end

local function spawnBlock(x, y, z)
	if y < 0 then
		return
	end
	local k = cellKey(x, y, z)
	if cells[k] ~= nil then
		return
	end
	local outside = x < 0 or x >= GRID or z < 0 or z >= GRID
	if outside and y == 0 then
		cells[k] = true -- the terrain ground already fills this spot
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(BLOCK, BLOCK, BLOCK)
	p.CFrame = CFrame.new(cellPos(x, y, z))
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	-- The look of a block: its own layer, blending into the next layer near a boundary.
	local L = layerAt(math.min(y, MAX_DEPTH - 1))
	local look = L
	local nextLayer = LAYERS[(table.find(LAYERS, L) or #LAYERS) + 1]
	if nextLayer and y >= nextLayer.from - 4 and rng:NextNumber() < (y - (nextLayer.from - 5)) / 6 then
		look = nextLayer
	end
	local useAlt = look.alt and rng:NextNumber() < 0.28
	local fillColor = if useAlt then rgb(look.alt.color) else rgb(look.color)
	local fillMaterial = material(if useAlt then look.alt.material else look.material)
	-- Rock strata: every two rows the rock shifts towards the layer's accent colour, so walls show bands.
	local STRATA = { 0, 0.4, 0.12, 0.55, 0.25, 0.05, 0.45, 0.18 }
	fillColor = fillColor:Lerp(rgb(look.band), STRATA[math.floor(y / 2) % #STRATA + 1])
	if y == 0 then
		fillColor = Color3.fromRGB(128, 94, 62)
		fillMaterial = Enum.Material.Ground
	end
	fillColor = fillColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber() * 0.08)

	if outside or y >= MAX_DEPTH then
		-- Unbreakable walls keep the look of the layer they are in, only darker.
		p.Name = "Bedrock"
		p.Color = if y >= MAX_DEPTH then Color3.fromRGB(18, 16, 22) else fillColor:Lerp(Color3.new(0, 0, 0), 0.35)
		p.Material = if y >= MAX_DEPTH then Enum.Material.Basalt else fillMaterial
		p:SetAttribute("Bedrock", true)
	else
		local kind = rollKind(y, L)
		local info = { x = x, y = y, z = z, kind = kind, pos = p.Position }
		local hp
		if kind == "Geode" then
			p.Name = "Geode"
			p.Color = Color3.fromRGB(58, 44, 72)
			p.Material = Enum.Material.Basalt
			decorate(p, GEODE_COLOR, Enum.Material.Neon, true, 6)
			addLight(p, GEODE_COLOR, 14, 1.6)
			hp = L.hp * 14
			info.value = math.floor(layerAverage(L) * 60)
			info.hitters = {}
			p:SetAttribute("Geode", true)
		elseif kind ~= "" then
			local O = ORES[kind]
			local oreColor = rgb(O.color)
			local crystal = O.material == "Glass" or O.material == "Neon"
			p.Name = O.name
			p.Color = fillColor:Lerp(oreColor, 0.12)
			p.Material = fillMaterial
			decorate(p, oreColor, material(O.material), crystal, rng:NextInteger(6, 9))
			if O.glow then
				addLight(p, oreColor, 11, 1.1)
			end
			hp = L.hp * O.hp
			info.value = O.value
			p:SetAttribute("Ore", kind)
		else
			p.Name = L.name
			p.Color = fillColor
			p.Material = fillMaterial
			hp = L.hp
			info.value = L.value
		end
		hp = math.max(1, math.floor(hp))
		info.hp = hp
		info.maxHp = hp
		info.color = p.Color
		p:SetAttribute("HP", hp)
		p:SetAttribute("MaxHP", hp)
		blockInfo[p] = info
	end
	p.Parent = mineFolder
	cells[k] = p
	partCount += 1
end

-- A wall torch on the block at (x, y, z), on the face that looks at `facing`.
local function placeTorch(x, y, z, facing)
	local block = cells[cellKey(x, y, z)]
	if typeof(block) ~= "Instance" or not block:IsA("BasePart") or block:FindFirstChild("Torch") then
		return
	end
	local base = block.Position + facing * (BLOCK / 2) + Vector3.new(0, 0.6, 0)
	local tilt = CFrame.fromAxisAngle(facing:Cross(Vector3.yAxis), -0.45)
	local stick = Instance.new("Part")
	stick.Name = "Torch"
	stick.Anchored = true
	stick.CanCollide = false
	stick.CanQuery = false
	stick.CanTouch = false
	stick.Size = Vector3.new(0.3, 1.8, 0.3)
	stick.CFrame = CFrame.new(base + facing * 0.35) * tilt
	stick.Color = Color3.fromRGB(96, 66, 40)
	stick.Material = Enum.Material.Wood
	local flame = Instance.new("Part")
	flame.Name = "Flame"
	flame.Anchored = true
	flame.CanCollide = false
	flame.CanQuery = false
	flame.CanTouch = false
	flame.CastShadow = false
	flame.Size = Vector3.new(0.45, 0.45, 0.45)
	flame.CFrame = CFrame.new(base + facing * 0.75 + Vector3.new(0, 0.85, 0))
	flame.Color = Color3.fromRGB(255, 170, 60)
	flame.Material = Enum.Material.Neon
	local fire = Instance.new("Fire")
	fire.Size = 1.6
	fire.Heat = 4
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 168, 90)
	light.Range = 20
	light.Brightness = 1.4
	light.Shadows = true
	light.Parent = flame
	flame.Parent = stick
	stick.Parent = block
end

local function clearCell(x, y, z)
	if y < 0 or y >= MAX_DEPTH or x < 0 or x >= GRID or z < 0 or z >= GRID then
		return
	end
	local k = cellKey(x, y, z)
	local c = cells[k]
	if c == true then
		return
	end
	if typeof(c) == "Instance" then
		blockInfo[c] = nil
		c:Destroy()
		partCount -= 1
	end
	cells[k] = false
	for _, d in DIRS do
		spawnBlock(x + d[1], y + d[2], z + d[3])
	end
end

-- The mine starts as a terraced open-pit quarry: each ring is one block (one jump) lower than the last.
local function quarryDepth(x, z)
	local c = (GRID - 1) / 2
	local d = math.max(math.abs(x - c), math.abs(z - c))
	if d > 9.5 then
		return 0
	elseif d > 7.5 then
		return 1
	elseif d > 5.5 then
		return 2
	elseif d > 3.5 then
		return 3
	end
	return 4
end

local function buildMineTop()
	for x = 0, GRID - 1 do
		for z = 0, GRID - 1 do
			spawnBlock(x, 0, z)
		end
	end
	for x = 0, GRID - 1 do
		for z = 0, GRID - 1 do
			for y = 0, quarryDepth(x, z) - 1 do
				clearCell(x, y, z)
			end
		end
	end
end

buildMineTop()

--------------------------------------------------------------------------------
-- PLAYER DATA
--------------------------------------------------------------------------------
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(DATA_STORE)
end)

local sessions = {}

local function newData()
	return {
		coins = 0, pick = 1, bag = 1, best = 0, mined = 0, asc = 0,
		bagCount = 0, bagValue = 0, treasures = {},
		streak = 0, lastDay = -1, earned = 0, tut = 0,
		pets = {}, equipped = {}, petUid = 0, xp = 0, level = 1,
		potions = {}, codes = {}, spinAt = 0, starter = false, firstJoin = 0, receipts = {},
	}
end

local function loadData(player)
	local d = newData()
	if not store then
		d._noSave = true
		return d
	end
	local tries = if RunService:IsStudio() then 1 else 3
	for attempt = 1, tries do
		local ok, result = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		if ok then
			if type(result) == "table" then
				for k, v in result do
					d[k] = v
				end
			end
			return d
		end
		warn("[DigDeep] Load failed for " .. player.Name .. ": " .. tostring(result))
		if attempt < tries then
			task.wait(attempt * 2)
		end
	end
	-- Never overwrite a save we couldn't read.
	d._noSave = true
	if not RunService:IsStudio() then
		task.delay(3, function()
			if player.Parent then
				Remotes.Notify:FireClient(player, "Couldn't load your save. Progress this session won't be saved.", Color3.fromRGB(255, 120, 100))
			end
		end)
	end
	return d
end

local function saveData(player)
	local d = sessions[player]
	if not d or d._noSave or not store then
		return
	end
	local payload = {}
	for k, v in d do
		if string.sub(k, 1, 1) ~= "_" then
			payload[k] = v
		end
	end
	local ok, err = pcall(function()
		store:SetAsync("u" .. player.UserId, payload)
	end)
	if not ok then
		warn("[DigDeep] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local PASS_BY_KEY, PASS_BY_ID, PRODUCT_BY_KEY, PRODUCT_BY_ID = {}, {}, {}, {}
for _, pass in PASSES do
	PASS_BY_KEY[pass.key] = pass
	if pass.id ~= 0 then
		PASS_BY_ID[pass.id] = pass
	end
end
for _, product in PRODUCTS do
	PRODUCT_BY_KEY[product.key] = product
	if product.id ~= 0 then
		PRODUCT_BY_ID[product.id] = product
	end
end

-- Pass ownership lives in the session (checked with Roblox on join), never in the save.
local function owns(player, key)
	local d = sessions[player]
	return d ~= nil and d._passes ~= nil and d._passes[key] == true
end

local function potionActive(player, name)
	local d = sessions[player]
	return d ~= nil and (d.potions[name] or 0) > os.time()
end

local function petSlots(player)
	return PET_SLOTS + (if owns(player, "MorePets") then 2 else 0)
end

local function petBoost(d)
	local total = 0
	for _, uid in d.equipped do
		for _, pet in d.pets do
			if pet.uid == uid and PETS[pet.id] then
				total += PETS[pet.id].boost
			end
		end
	end
	return total
end

local function capacity(player)
	local d = sessions[player]
	if owns(player, "InfiniteBag") then
		return 1e9
	end
	return BAGS[d.bag].capacity
end

-- Multiplier on the time between swings (lower is faster).
local function swingMult(player)
	local m = 1
	if owns(player, "FastMine") then
		m *= 0.8
	end
	if potionActive(player, "Speed") then
		m *= 0.75
	end
	return m
end

local function luckMult(player)
	local m = 1
	if owns(player, "Lucky") then
		m *= 2
	end
	if potionActive(player, "Luck") then
		m *= 2
	end
	return m
end

local function xpForLevel(level)
	return math.floor(30 * level ^ 1.5)
end

local function uniqueTreasures(d)
	local n = 0
	for _ in d.treasures do
		n += 1
	end
	return n
end

local function valueMult(player)
	local d = sessions[player]
	local m = (1 + uniqueTreasures(d) * TREASURE_BONUS) * (1 + (d.asc or 0) * ASCEND_BONUS)
	m *= 1 + (d.level - 1) * LEVEL_BONUS
	m *= 1 + petBoost(d)
	if player:GetAttribute("FriendBonus") then
		m *= 1 + FRIEND_BONUS
	end
	if owns(player, "VIP") then
		m *= 1.25
	end
	if owns(player, "DoubleCoins") then
		m *= 2
	end
	if potionActive(player, "Coins") then
		m *= 2
	end
	return m
end

local function sync(player)
	local d = sessions[player]
	if not d then
		return
	end
	player:SetAttribute("Coins", d.coins)
	player:SetAttribute("Bag", d.bagCount)
	player:SetAttribute("BagMax", capacity(player))
	player:SetAttribute("BagValue", math.floor(d.bagValue))
	player:SetAttribute("Pick", d.pick)
	player:SetAttribute("Pack", d.bag)
	player:SetAttribute("Best", d.best)
	player:SetAttribute("Mined", d.mined)
	player:SetAttribute("Streak", d.streak)
	player:SetAttribute("LastDay", d.lastDay)
	player:SetAttribute("Tut", d.tut)
	player:SetAttribute("Treasures", HttpService:JSONEncode(d.treasures))
	player:SetAttribute("Mult", valueMult(player))
	player:SetAttribute("Asc", d.asc or 0)
	player:SetAttribute("Level", d.level)
	player:SetAttribute("XP", d.xp)
	player:SetAttribute("XPNeed", xpForLevel(d.level))
	player:SetAttribute("SwingMult", swingMult(player))
	player:SetAttribute("SpinAt", d.spinAt)
	player:SetAttribute("Starter", d.starter)
	player:SetAttribute("FirstJoin", d.firstJoin)
	for name, expiry in d.potions do
		player:SetAttribute("Potion_" .. name, expiry)
	end
	for _, pass in PASSES do
		player:SetAttribute("Pass_" .. pass.key, owns(player, pass.key))
	end
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Depth.Value = d.best
		stats.Coins.Value = d.coins
		stats.Ascensions.Value = d.asc or 0
	end
end

local function notify(player, text, color)
	Remotes.Notify:FireClient(player, text, color or Color3.fromRGB(255, 255, 255))
end

--------------------------------------------------------------------------------
-- CHARACTER: pickaxe tool, backpack on your back, headlamp
--------------------------------------------------------------------------------
local updateNameplate

local function givePick(player)
	local d = sessions[player]
	local char = player.Character
	if not d or not char then
		return
	end
	for _, c in char:GetChildren() do
		if c:IsA("Tool") then
			c:Destroy()
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack:ClearAllChildren()
	end
	local model = buildPick(d.pick)
	local handle = model.PrimaryPart
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = PICKS[d.pick].name
	-- Same grip as the classic sword: handle points up out of the fist, head swings forward.
	tool.Grip = CFrame.new(0, 0, -1.6, 0, 0, 1, 1, 0, 0, 0, 1, 0)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Parent = tool
			if p ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model:Destroy()
	if owns(player, "VIP") then
		local head = tool:FindFirstChild("Head")
		if head then
			local sparkle = Instance.new("Sparkles")
			sparkle.SparkleColor = Color3.fromRGB(255, 214, 90)
			sparkle.Parent = head
		end
	end
	tool.Parent = char -- parenting to the character equips it
end

local function updateBagFill(player)
	local d = sessions[player]
	local char = player.Character
	local bag = char and char:FindFirstChild("DigBag")
	if not d or not bag then
		return
	end
	local fill = bag:FindFirstChild("Fill")
	local weld = fill and fill:FindFirstChild("FillWeld")
	if not fill or not weld then
		return
	end
	local s = bag:GetAttribute("Scale") or 1
	local f = math.clamp(d.bagCount / capacity(player), 0, 1)
	local h = math.max(0.05, f * 1.1 * s)
	fill.Transparency = if f <= 0 then 1 else 0
	fill.Size = Vector3.new(1.7 * s, h, 0.85 * s)
	weld.C0 = CFrame.new(0, 1.3 * s + h / 2, 0)
	fill.Color = if f >= 1 then Color3.fromRGB(255, 80, 70) else Color3.fromRGB(255, 196, 60)
end

local function attachBag(player)
	local d = sessions[player]
	local char = player.Character
	if not d or not char then
		return
	end
	local old = char:FindFirstChild("DigBag")
	if old then
		old:Destroy()
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then
		return
	end
	local s = 0.72 + 0.06 * d.bag
	local model = buildBag(d.bag, s)
	model.Name = "DigBag"
	model:SetAttribute("Scale", s)
	local body = model.PrimaryPart
	model:PivotTo(torso.CFrame * CFrame.new(0, 0.1, torso.Size.Z / 2 + 0.55 * s))
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = p
			weld.Parent = p
		end
	end
	local fill = Instance.new("Part")
	fill.Name = "Fill"
	fill.Anchored = false
	fill.CanCollide = false
	fill.CanQuery = false
	fill.CanTouch = false
	fill.Massless = true
	fill.Material = Enum.Material.Neon
	fill.Transparency = 1
	fill.Size = Vector3.new(1.7 * s, 0.05, 0.85 * s)
	fill.CFrame = body.CFrame
	local weld = Instance.new("Weld")
	weld.Name = "FillWeld"
	weld.Part0 = body
	weld.Part1 = fill
	weld.Parent = fill
	fill.Parent = model
	model.Parent = char
	updateBagFill(player)
end

local function addHeadlamp(char)
	local head = char:FindFirstChild("Head")
	if not head or head:FindFirstChild("DigLamp") then
		return
	end
	local spot = Instance.new("SpotLight")
	spot.Name = "DigLamp"
	spot.Face = Enum.NormalId.Front
	spot.Range = 46
	spot.Angle = 80
	spot.Brightness = 2.4
	spot.Color = Color3.fromRGB(255, 238, 205)
	spot.Shadows = true
	spot.Parent = head
	local glow = Instance.new("PointLight")
	glow.Name = "DigGlow"
	glow.Range = 16
	glow.Brightness = 0.8
	glow.Color = Color3.fromRGB(255, 225, 180)
	glow.Parent = head
end

-- Level / VIP / Ascension tag over the player's head, like every simulator has.
updateNameplate = function(player)
	local d = sessions[player]
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not d or not head then
		return
	end
	local gui = head:FindFirstChild("DigNameplate")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "DigNameplate"
		gui.Size = UDim2.fromOffset(220, 30)
		gui.StudsOffset = Vector3.new(0, 2.7, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 20
		label.RichText = true
		label.TextColor3 = Color3.new(1, 1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(20, 18, 26)
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = head
	end
	local parts = { `<font color="#FFD24A">Lv {d.level}</font>` }
	if owns(player, "VIP") then
		table.insert(parts, `<font color="#FFC83C">👑 VIP</font>`)
	end
	if (d.asc or 0) > 0 then
		table.insert(parts, `<font color="#D7AFFF">⭐{d.asc}</font>`)
	end
	gui.Text.Text = table.concat(parts, "  ")
end

local function teleportTo(player, position)
	local char = player.Character
	if not char then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(position, 3)
	end)
	char:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
end

local function spawnPoint()
	return SPAWN_POS + Vector3.new(rng:NextNumber(-3, 3), 3.5, rng:NextNumber(-3, 3))
end

local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root or not sessions[player] then
		return
	end
	hum.WalkSpeed = 20
	hum.UseJumpPower = false
	hum.JumpHeight = 7.6 -- enough to hop up one block
	task.wait() -- let the rig settle before welding things to it
	if root.Position.Y < TOP - 40 then
		teleportTo(player, spawnPoint())
	end
	givePick(player)
	attachBag(player)
	addHeadlamp(char)
	updateNameplate(player)
end

--------------------------------------------------------------------------------
-- MINING
--------------------------------------------------------------------------------
local lastHit = {}

local function announce(text, color)
	Remotes.Announce:FireAllClients(text, color)
end

local function article(name)
	local first = string.lower(string.sub(name, 1, 1))
	if first == "a" or first == "e" or first == "i" or first == "o" or first == "u" then
		return "an"
	end
	return "a"
end

local TREASURE_ROLL = table.clone(TREASURES)
table.sort(TREASURE_ROLL, function(a, b)
	return a.chance < b.chance -- rarest first
end)

local function awardTreasure(player, T, pos, depth)
	local d = sessions[player]
	local first = d.treasures[T.id] == nil
	d.treasures[T.id] = (d.treasures[T.id] or 0) + 1
	local reward = math.floor(T.reward * valueMult(player))
	d.coins += reward
	d.earned += reward
	Remotes.Treasure:FireClient(player, T.id, pos, reward, first)
	if first or T.reward >= 25000 then
		announce(`🏆 {player.DisplayName} found {article(T.name)} {T.name} at {depth}m!`, rgb(T.color))
	end
end

local function breakBlock(player, part, info)
	local d = sessions[player]
	clearCell(info.x, info.y, info.z)
	-- Now and then a torch appears on a wall of the fresh hole, so tunnels feel lived-in.
	if info.y >= 2 and rng:NextNumber() < 1 / 12 then
		local dir = DIRS[rng:NextInteger(1, 6)]
		if dir[2] == 0 then
			placeTorch(info.x + dir[1], info.y, info.z + dir[3], Vector3.new(-dir[1], 0, -dir[3]))
		end
	end
	d.mined += 1
	local depth = info.y + 1
	if depth > d.best then
		d.best = depth
	end
	if d.tut == 0 and d.mined >= 5 then
		d.tut = 1
	end

	local collected, full = false, false
	if info.kind == "Geode" then
		local count = 0
		for _ in info.hitters do
			count += 1
		end
		for hitter in info.hitters do
			local hd = sessions[hitter]
			if hd and hitter.Parent then
				local amount = math.floor(info.value * valueMult(hitter))
				hd.coins += amount
				hd.earned += amount
				Remotes.Geode:FireClient(hitter, info.pos, amount, count)
				sync(hitter)
			end
		end
	elseif d.bagCount < capacity(player) then
		d.bagCount += 1
		d.bagValue += info.value * valueMult(player)
		collected = true
	else
		full = true
	end

	Remotes.Mined:FireClient(player, info.pos, info.kind, info.color, collected, full)

	if info.kind ~= "" and info.kind ~= "Geode" and ORES[info.kind].announce then
		local O = ORES[info.kind]
		announce(`💎 {player.DisplayName} mined {article(O.name)} {O.name} at {depth}m!`, rgb(O.color))
	end

	for _, T in TREASURE_ROLL do
		if depth >= T.depth and rng:NextNumber() < T.chance * luckMult(player) then
			awardTreasure(player, T, info.pos, depth)
			break
		end
	end

	-- XP: deeper layers are worth more
	d.xp += table.find(LAYERS, layerAt(info.y)) or 1
	while d.xp >= xpForLevel(d.level) do
		d.xp -= xpForLevel(d.level)
		d.level += 1
		local reward = math.floor(INCOME[d.pick] * 2 * (1 + (d.asc or 0) * ASCEND_BONUS))
		d.coins += reward
		Remotes.LevelUp:FireClient(player, d.level, reward)
		updateNameplate(player)
	end

	sync(player)
	updateBagFill(player)
end

Remotes.Hit.OnServerEvent:Connect(function(player, part)
	local d = sessions[player]
	if not d or typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	local info = blockInfo[part]
	if not info then
		return
	end
	local pick = PICKS[d.pick]
	local now = os.clock()
	if now - (lastHit[player] or 0) < pick.speed * swingMult(player) * 0.75 then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	if (root.Position - part.Position).Magnitude > REACH + 6 then
		return
	end
	lastHit[player] = now

	if info.hitters then
		info.hitters[player] = true
	end
	info.hp -= pick.dmg
	if info.hp > 0 then
		part:SetAttribute("HP", info.hp)
		part.Color = info.color:Lerp(Color3.new(0, 0, 0), 0.45 * (1 - info.hp / info.maxHp))
		return
	end
	breakBlock(player, part, info)
end)

--------------------------------------------------------------------------------
-- SELLING, SHOPS, ELEVATOR, DAILY CHEST
--------------------------------------------------------------------------------
local lastSell = {}

local function trySell(player)
	local d = sessions[player]
	if not d or d.bagCount <= 0 then
		return
	end
	if os.clock() - (lastSell[player] or 0) < 0.5 then
		return
	end
	lastSell[player] = os.clock()
	local amount = math.floor(d.bagValue)
	d.coins += amount
	d.earned += amount
	d.bagCount = 0
	d.bagValue = 0
	if d.tut < 2 then
		d.tut = 2
	end
	sync(player)
	updateBagFill(player)
	Remotes.Sold:FireClient(player, amount)
end

sellPad.Touched:Connect(function(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if player then
		trySell(player)
	end
end)

--------------------------------------------------------------------------------
-- SIM FEATURES: pets, eggs, potions, codes, spin wheel, passes and products
--------------------------------------------------------------------------------
local function coinMinutes(player, minutes)
	local d = sessions[player]
	local amount = math.floor(INCOME[d.pick] * minutes * (1 + (d.asc or 0) * ASCEND_BONUS))
	d.coins += amount
	d.earned += amount
	return amount
end

local function addPotion(player, name, minutes)
	local d = sessions[player]
	local now = os.time()
	d.potions[name] = math.min(math.max(now, d.potions[name] or 0) + minutes * 60, now + 3 * 3600)
end

local function syncPets(player)
	local d = sessions[player]
	local list, equippedIds = {}, {}
	for _, pet in d.pets do
		local on = table.find(d.equipped, pet.uid) ~= nil
		table.insert(list, { u = pet.uid, id = pet.id, e = on })
		if on then
			table.insert(equippedIds, pet.id)
		end
	end
	player:SetAttribute("Pets", HttpService:JSONEncode(list))
	player:SetAttribute("PetsEquipped", HttpService:JSONEncode(equippedIds))
	player:SetAttribute("PetSlots", petSlots(player))
end

local function findPet(d, uid)
	for i, pet in d.pets do
		if pet.uid == uid then
			return pet, i
		end
	end
	return nil, nil
end

local function equipBest(player)
	local d = sessions[player]
	local sorted = table.clone(d.pets)
	table.sort(sorted, function(a, b)
		return (PETS[a.id] and PETS[a.id].boost or 0) > (PETS[b.id] and PETS[b.id].boost or 0)
	end)
	d.equipped = {}
	for i = 1, math.min(petSlots(player), #sorted) do
		table.insert(d.equipped, sorted[i].uid)
	end
end

local function givePet(player, id)
	local d = sessions[player]
	d.petUid += 1
	table.insert(d.pets, { uid = d.petUid, id = id })
	-- New players shouldn't have to manage pets: a better pet slots itself in.
	if #d.equipped < petSlots(player) then
		table.insert(d.equipped, d.petUid)
	else
		local weakest, weakestBoost = nil, math.huge
		for i, uid in d.equipped do
			local pet = findPet(d, uid)
			local b = pet and PETS[pet.id] and PETS[pet.id].boost or 0
			if b < weakestBoost then
				weakest, weakestBoost = i, b
			end
		end
		if weakest and PETS[id].boost > weakestBoost then
			d.equipped[weakest] = d.petUid
		end
	end
	return d.petUid
end

local lastHatch = {}
local function hatch(player, index, free)
	local d = sessions[player]
	local egg = EGGS[index]
	if not d or not egg then
		return
	end
	if not free then
		if os.clock() - (lastHatch[player] or 0) < 1.2 then
			return
		end
		if d.best < egg.depth then
			notify(player, `Reach {egg.depth}m to unlock the {egg.name}`, Color3.fromRGB(255, 180, 120))
			return
		end
		if d.coins < egg.price then
			notify(player, `You need 💰 {fmt(egg.price - d.coins)} more`, Color3.fromRGB(255, 130, 110))
			return
		end
	end
	if #d.pets >= MAX_PETS then
		notify(player, "Your pet inventory is full! Delete some pets first.", Color3.fromRGB(255, 130, 110))
		return
	end
	lastHatch[player] = os.clock()
	if not free then
		d.coins -= egg.price
	end
	local luck = luckMult(player)
	local total = 0
	for i, entry in egg.pets do
		total += entry[2] * (if i > 1 then luck else 1)
	end
	local roll = rng:NextNumber() * total
	local chosen = egg.pets[1][1]
	for i, entry in egg.pets do
		roll -= entry[2] * (if i > 1 then luck else 1)
		if roll <= 0 then
			chosen = entry[1]
			break
		end
	end
	givePet(player, chosen)
	syncPets(player)
	sync(player)
	Remotes.Hatched:FireClient(player, chosen, egg.id)
	if PETS[chosen].rarity == "Legendary" then
		announce(`🐾 {player.DisplayName} hatched a LEGENDARY {PETS[chosen].name}!`, rgb(RARITY_COLORS.Legendary))
	end
end

local function pickSpin()
	local total = 0
	for _, seg in SPIN do
		total += seg.weight
	end
	local roll = rng:NextNumber() * total
	for i, seg in SPIN do
		roll -= seg.weight
		if roll <= 0 then
			return i
		end
	end
	return 1
end

local function bestUnlockedEgg(d)
	local best = 1
	for i, egg in EGGS do
		if d.best >= egg.depth then
			best = i
		end
	end
	return best
end

local function spin(player)
	local d = sessions[player]
	if not d then
		return
	end
	if os.time() < d.spinAt then
		notify(player, "The wheel is still recharging", Color3.fromRGB(220, 220, 230))
		return
	end
	d.spinAt = os.time() + SPIN_COOLDOWN
	local index = pickSpin()
	local seg = SPIN[index]
	local text
	if seg.coinMinutes then
		text = "+ 💰 " .. fmt(coinMinutes(player, seg.coinMinutes))
	elseif seg.potion then
		addPotion(player, seg.potion, seg.minutes)
		text = `{seg.label} potion · {seg.minutes} min`
	else
		text = "A free egg!"
	end
	sync(player)
	Remotes.SpinResult:FireClient(player, index, text)
	if seg.egg then
		-- hatch after the wheel animation has had time to land
		task.delay(4.5, function()
			if sessions[player] then
				hatch(player, bestUnlockedEgg(d), true)
			end
		end)
	end
	if seg.label == "JACKPOT" then
		task.delay(4.2, announce, `💎 {player.DisplayName} hit the JACKPOT on the spin wheel!`, Color3.fromRGB(255, 90, 90))
	end
end

local function redeem(player, code)
	local d = sessions[player]
	if not d or type(code) ~= "string" then
		return
	end
	code = string.upper((string.gsub(code, "%s", "")))
	local reward = CODES[code]
	if not reward then
		Remotes.Purchased:FireClient(player, "code", false, "That code doesn't exist")
		return
	end
	if d.codes[code] then
		Remotes.Purchased:FireClient(player, "code", false, "You already used this code")
		return
	end
	d.codes[code] = true
	local text
	if reward.coinMinutes then
		text = "+ 💰 " .. fmt(coinMinutes(player, reward.coinMinutes))
	else
		addPotion(player, reward.potion, reward.minutes)
		text = `{reward.potion} potion · {reward.minutes} min`
	end
	sync(player)
	Remotes.Purchased:FireClient(player, "code", true, text)
end

local function applyPass(player, key)
	local d = sessions[player]
	if not d then
		return
	end
	d._passes = d._passes or {}
	if d._passes[key] then
		return
	end
	d._passes[key] = true
	if key == "VIP" then
		givePick(player)
		updateNameplate(player)
	elseif key == "MorePets" then
		equipBest(player)
		syncPets(player)
	end
	sync(player)
	updateBagFill(player)
end

local function grantProduct(player, key)
	local d = sessions[player]
	local product = PRODUCT_BY_KEY[key]
	if not d or not product then
		return false
	end
	local text
	if product.starter then
		if not d.starter then
			d.starter = true
			givePet(player, "StarterPup")
			syncPets(player)
		end
		for _, potion in { "Coins", "Luck", "Speed" } do
			addPotion(player, potion, 15)
		end
		text = "Starter Pup + potions + 💰 " .. fmt(coinMinutes(player, 30))
	elseif product.coinMinutes then
		text = "+ 💰 " .. fmt(coinMinutes(player, product.coinMinutes))
	elseif product.potion then
		addPotion(player, product.potion, product.minutes)
		text = `{product.name} · {product.minutes} min`
	elseif key == "NextPick" then
		if d.pick < #PICKS then
			d.pick += 1
			givePick(player)
			text = "Equipped the " .. PICKS[d.pick].name .. "!"
		else
			text = "+ 💰 " .. fmt(coinMinutes(player, 120))
		end
	end
	sync(player)
	Remotes.Purchased:FireClient(player, key, true, text or product.name)
	return true
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local d = player and sessions[player]
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(d.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = PRODUCT_BY_ID[receipt.ProductId]
	if not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok = pcall(grantProduct, player, product.key)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(d.receipts, receipt.PurchaseId)
	while #d.receipts > 50 do
		table.remove(d.receipts, 1)
	end
	saveData(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local pass = PASS_BY_ID[passId]
	if purchased and pass then
		applyPass(player, pass.key)
		Remotes.Purchased:FireClient(player, pass.key, true, pass.name .. " unlocked!")
	end
end)

local function loadPasses(player)
	for _, pass in PASSES do
		if pass.id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and has then
				applyPass(player, pass.key)
			end
		end
	end
end

local lastAction = {}
Remotes.Action.OnServerEvent:Connect(function(player, action, arg, arg2)
	local d = sessions[player]
	if not d or type(action) ~= "string" then
		return
	end
	if os.clock() - (lastAction[player] or 0) < 0.15 then
		return
	end
	lastAction[player] = os.clock()
	if action == "Sell" then
		if owns(player, "SellAnywhere") then
			trySell(player)
		end
	elseif action == "Equip" or action == "Unequip" then
		local pet = findPet(d, arg)
		if not pet then
			return
		end
		local at = table.find(d.equipped, pet.uid)
		if action == "Unequip" and at then
			table.remove(d.equipped, at)
		elseif action == "Equip" and not at then
			if #d.equipped >= petSlots(player) then
				Remotes.Notify:FireClient(player, "All pet slots are full. Unequip one first.", Color3.fromRGB(255, 180, 120))
				return
			end
			table.insert(d.equipped, pet.uid)
		end
		syncPets(player)
		sync(player)
	elseif action == "EquipBest" then
		equipBest(player)
		syncPets(player)
		sync(player)
	elseif action == "Delete" then
		local pet, i = findPet(d, arg)
		if pet and i then
			table.remove(d.pets, i)
			local at = table.find(d.equipped, pet.uid)
			if at then
				table.remove(d.equipped, at)
			end
			syncPets(player)
			sync(player)
		end
	elseif action == "Redeem" then
		redeem(player, arg)
	elseif action == "Spin" then
		spin(player)
	elseif action == "DevGrant" then
		-- Studio-only test purchases for items whose id is still 0
		if not RunService:IsStudio() then
			return
		end
		if arg == "Pass" and PASS_BY_KEY[arg2] and PASS_BY_KEY[arg2].id == 0 then
			applyPass(player, arg2)
			Remotes.Purchased:FireClient(player, arg2, true, PASS_BY_KEY[arg2].name .. " unlocked! (Studio test)")
		elseif arg == "Product" and PRODUCT_BY_KEY[arg2] and PRODUCT_BY_KEY[arg2].id == 0 then
			grantProduct(player, arg2)
		end
	end
end)

local lastSurface = {}
Remotes.Surface.OnServerEvent:Connect(function(player)
	if not sessions[player] or os.clock() - (lastSurface[player] or 0) < 1.5 then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 or root.Position.Y > TOP - 1 then
		return
	end
	lastSurface[player] = os.clock()
	teleportTo(player, SELL_POS + Vector3.new(rng:NextNumber(-3, 3), 3.5, rng:NextNumber(-3, 3)))
	task.delay(0.15, trySell, player)
end)

local function buy(player, kind, tier)
	local d = sessions[player]
	local list = if kind == "Pick" then PICKS else BAGS
	local item = list[tier]
	if not d or not item then
		return
	end
	local current = if kind == "Pick" then d.pick else d.bag
	if tier <= current then
		notify(player, "You already own this or better!", Color3.fromRGB(200, 200, 210))
		return
	end
	if d.coins < item.price then
		notify(player, `You need 💰 {fmt(item.price - d.coins)} more`, Color3.fromRGB(255, 130, 110))
		return
	end
	d.coins -= item.price
	if kind == "Pick" then
		d.pick = tier
		if d.tut < 3 then
			d.tut = 3
		end
		givePick(player)
	else
		d.bag = tier
		attachBag(player)
	end
	sync(player)
	Remotes.Bought:FireClient(player, kind, tier)
end

local function ascend(player)
	local d = sessions[player]
	if not d then
		return
	end
	if d.best < MAX_DEPTH then
		notify(player, `Reach bedrock ({MAX_DEPTH}m) to Ascend. Deepest so far: {d.best}m`, Color3.fromRGB(200, 170, 255))
		return
	end
	d.asc = (d.asc or 0) + 1
	d.coins = 0
	d.pick = 1
	d.bag = 1
	d.best = 0
	d.bagCount = 0
	d.bagValue = 0
	teleportTo(player, spawnPoint())
	givePick(player)
	attachBag(player)
	sync(player)
	announce(`⭐ {player.DisplayName} ASCENDED! (Ascension {d.asc}: ore worth x{string.format("%.1f", 1 + d.asc * ASCEND_BONUS)})`, Color3.fromRGB(200, 160, 255))
end

local function descend(player)
	local d = sessions[player]
	local char = player.Character
	if not d or not char then
		return
	end
	local stop = math.min(math.floor(d.best / ELEVATOR_STEP) * ELEVATOR_STEP, MAX_DEPTH - 1)
	if stop < ELEVATOR_STEP then
		notify(player, `Dig to {ELEVATOR_STEP}m to unlock the elevator`, Color3.fromRGB(255, 214, 90))
		return
	end
	local row = stop - 1
	local cx, cz = rng:NextInteger(2, GRID - 3), rng:NextInteger(2, GRID - 3)
	for dx = -1, 1 do
		for dz = -1, 1 do
			clearCell(cx + dx, row, cz + dz)
		end
	end
	clearCell(cx, row - 1, cz)
	placeTorch(cx + 2, row, cz, Vector3.new(-1, 0, 0))
	placeTorch(cx - 2, row, cz, Vector3.new(1, 0, 0))
	local floorY = TOP - (row + 1) * BLOCK
	teleportTo(player, Vector3.new(cellPos(cx, row, cz).X, floorY + 3.5, cellPos(cx, row, cz).Z))
	notify(player, `⬇ {stop}m`, Color3.fromRGB(255, 214, 90))
end

local function claimDaily(player)
	local d = sessions[player]
	if not d then
		return
	end
	local today = math.floor(os.time() / 86400)
	if d.lastDay == today then
		local left = (today + 1) * 86400 - os.time()
		notify(player, `Next chest in {math.floor(left / 3600)}h {math.floor(left % 3600 / 60)}m`, Color3.fromRGB(220, 220, 230))
		return
	end
	if d.lastDay == today - 1 then
		d.streak += 1
	else
		d.streak = 1
	end
	d.lastDay = today
	local day = ((d.streak - 1) % 7) + 1
	local mult = if day == 7 then 3 else 1 + 0.25 * (day - 1)
	local reward = math.floor(DAILY[d.pick] * mult)
	d.coins += reward
	d.earned += reward
	sync(player)
	Remotes.Reward:FireClient(player, reward, day, CHEST_POS + Vector3.new(0, 3, 0))
end

ProximityPromptService.PromptTriggered:Connect(function(p, player)
	local kind = p:GetAttribute("Kind")
	if kind == "Pick" or kind == "Bag" then
		buy(player, kind, p:GetAttribute("Tier"))
	elseif kind == "Elevator" then
		descend(player)
	elseif kind == "Daily" then
		claimDaily(player)
	elseif kind == "Ascend" then
		ascend(player)
	elseif kind == "Egg" then
		hatch(player, p:GetAttribute("Egg"), false)
	end
end)

--------------------------------------------------------------------------------
-- FRIENDS
--------------------------------------------------------------------------------
local function refreshFriends()
	local list = Players:GetPlayers()
	for _, a in list do
		local has = false
		for _, b in list do
			if a ~= b then
				local ok, isFriend = pcall(function()
					return (a :: any):IsFriendsWithAsync(b.UserId)
				end)
				if not ok then
					ok, isFriend = pcall(function()
						return (a :: any):IsFriendsWith(b.UserId)
					end)
				end
				if ok and isFriend then
					has = true
					break
				end
			end
		end
		if a.Parent then
			local had = a:GetAttribute("FriendBonus") == true
			a:SetAttribute("FriendBonus", has)
			if has and not had then
				notify(a, "👥 Friend bonus! +10% ore value", Color3.fromRGB(120, 230, 140))
			end
			sync(a)
		end
	end
end

--------------------------------------------------------------------------------
-- JOIN / LEAVE
--------------------------------------------------------------------------------
local function onJoin(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local depth = Instance.new("IntValue")
	depth.Name = "Depth"
	depth.Parent = stats
	local coins = Instance.new("NumberValue")
	coins.Name = "Coins"
	coins.Parent = stats
	local asc = Instance.new("IntValue")
	asc.Name = "Ascensions"
	asc.Parent = stats
	stats.Parent = player

	local d = loadData(player)
	if not player.Parent then
		return
	end
	sessions[player] = d
	d._passes = {}
	if d.firstJoin == 0 then
		d.firstJoin = os.time()
	end
	sync(player)
	syncPets(player)
	task.spawn(function()
		loadPasses(player)
		sync(player)
		syncPets(player)
	end)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	task.spawn(refreshFriends)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in Players:GetPlayers() do
	task.spawn(onJoin, p)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	sessions[player] = nil
	lastHit[player] = nil
	lastSell[player] = nil
	lastSurface[player] = nil
	lastHatch[player] = nil
	lastAction[player] = nil
	for _, info in blockInfo do
		if info.hitters then
			info.hitters[player] = nil
		end
	end
	task.defer(refreshFriends)
end)

game:BindToClose(function()
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			saveData(player)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_EVERY)
		for player in sessions do
			task.spawn(saveData, player)
		end
	end
end)

--------------------------------------------------------------------------------
-- EVENTS: Gold Rush (global clock) and Earthquakes (mine reset)
--------------------------------------------------------------------------------
local function resetMine()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < TOP - 1 then
			teleportTo(player, spawnPoint())
		end
	end
	mineFolder:ClearAllChildren()
	table.clear(cells)
	table.clear(blockInfo)
	partCount = 0
	buildMineTop()
end

task.spawn(function()
	local nextQuake = os.clock() + QUAKE_EVERY
	local warning = false
	local wasRush = rushActive()
	while true do
		task.wait(1)
		local now = os.clock()
		if not warning then
			if partCount > PART_CAP and nextQuake - now > QUAKE_WARNING then
				nextQuake = now + QUAKE_WARNING
			end
			if nextQuake - now <= QUAKE_WARNING then
				warning = true
				workspace:SetAttribute("QuakeAt", workspace:GetServerTimeNow() + (nextQuake - now))
				announce("⚠ EARTHQUAKE INCOMING! The mine is about to collapse!", Color3.fromRGB(255, 100, 80))
			end
		elseif now >= nextQuake then
			resetMine()
			warning = false
			workspace:SetAttribute("QuakeAt", nil)
			nextQuake = now + QUAKE_EVERY
			announce("🌋 The mine has shifted. Fresh ore everywhere!", Color3.fromRGB(255, 200, 120))
		end

		local rush = rushActive()
		if rush and not wasRush then
			announce(`✨ GOLD RUSH! Ore is {RUSH_MULT}x more common for {RUSH_LENGTH} seconds!`, Color3.fromRGB(255, 214, 70))
		end
		wasRush = rush
	end
end)

print("[DigDeep] Server ready.")
