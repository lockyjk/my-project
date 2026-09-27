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
local RunService = game:GetService("RunService")

-- Remove the template's baseplate and spawn first, before any character can land on them.
for _, child in workspace:GetChildren() do
	if child:IsA("SpawnLocation") or child.Name == "Baseplate" then
		child:Destroy()
	end
end

--------------------------------------------------------------------------------
-- TUNING
--------------------------------------------------------------------------------
-- The surface sits high up and the mine digs down from it, so the bottom of the mine
-- stays above Workspace.FallenPartsDestroyHeight (-500 by default).
local TOP = 1850
local BLOCK = 6 -- studs per block
local GRID = 24 -- the mine is GRID x GRID blocks wide
local MAX_DEPTH = 300 -- rows; bedrock below
local REACH = 20 -- studs from your root part to a block's centre
local PART_CAP = 15000 -- an earthquake resets the mine once this many blocks exist
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
	Singularity = { name = "Singularity", value = 1500000, hp = 5, color = { 235, 70, 255 }, material = "Neon", tier = 6, glow = true, announce = true },
}

-- Layers, top to bottom. from = first row. hp = base block health. value = coins for a plain block.
-- tint = colour grading while you are in this layer.
local LAYERS = {
	{ name = "Topsoil", from = 0, hp = 3, value = 1, color = { 118, 84, 56 }, material = "Ground", tint = { 255, 244, 228 },
		ores = { { id = "Coal", chance = 0.06 }, { id = "Copper", chance = 0.03 } } },
	{ name = "Stone", from = 15, hp = 8, value = 2, color = { 125, 125, 130 }, material = "Slate", tint = { 236, 240, 255 },
		ores = { { id = "Coal", chance = 0.04 }, { id = "Copper", chance = 0.04 }, { id = "Iron", chance = 0.04 }, { id = "Silver", chance = 0.015 } } },
	{ name = "Deepstone", from = 40, hp = 16, value = 5, color = { 72, 74, 88 }, material = "Basalt", tint = { 214, 224, 255 },
		ores = { { id = "Iron", chance = 0.04 }, { id = "Silver", chance = 0.03 }, { id = "Gold", chance = 0.025 }, { id = "Ruby", chance = 0.008 }, { id = "Sapphire", chance = 0.008 } } },
	{ name = "Magma Rock", from = 80, hp = 50, value = 12, color = { 70, 40, 34 }, material = "CrackedLava", tint = { 255, 212, 186 },
		ores = { { id = "Gold", chance = 0.03 }, { id = "Obsidian", chance = 0.03 }, { id = "Emerald", chance = 0.015 }, { id = "Firestone", chance = 0.007 } } },
	{ name = "Crystal Caves", from = 130, hp = 160, value = 30, color = { 66, 86, 130 }, material = "Glacier", tint = { 206, 224, 255 },
		ores = { { id = "Amethyst", chance = 0.03 }, { id = "Diamond", chance = 0.01 }, { id = "Moonstone", chance = 0.004 } } },
	{ name = "The Void", from = 200, hp = 520, value = 80, color = { 30, 22, 44 }, material = "Slate", tint = { 222, 196, 255 },
		ores = { { id = "Voidstone", chance = 0.03 }, { id = "Starshard", chance = 0.008 }, { id = "Singularity", chance = 0.0008 } } },
}

local PICKS = {
	{ name = "Rusty Pick", dmg = 1, speed = 0.45, price = 0, color = { 150, 96, 62 }, material = "CorrodedMetal" },
	{ name = "Stone Pick", dmg = 2, speed = 0.42, price = 40, color = { 140, 140, 144 }, material = "Slate" },
	{ name = "Iron Pick", dmg = 4, speed = 0.40, price = 700, color = { 205, 205, 212 }, material = "Metal" },
	{ name = "Golden Pick", dmg = 8, speed = 0.36, price = 8000, color = { 255, 200, 45 }, material = "Foil" },
	{ name = "Diamond Pick", dmg = 16, speed = 0.33, price = 50000, color = { 150, 235, 255 }, material = "Glass", glow = true },
	{ name = "Magma Pick", dmg = 34, speed = 0.30, price = 350000, color = { 255, 105, 25 }, material = "Neon", glow = true },
	{ name = "Crystal Pick", dmg = 75, speed = 0.27, price = 2500000, color = { 175, 95, 255 }, material = "Glass", glow = true },
	{ name = "Void Pick", dmg = 170, speed = 0.24, price = 20000000, color = { 80, 10, 140 }, material = "Neon", glow = true },
	{ name = "Starforged Pick", dmg = 400, speed = 0.20, price = 150000000, color = { 255, 240, 165 }, material = "Neon", glow = true },
}

local BAGS = {
	{ name = "Pouch", capacity = 20, price = 0, color = { 165, 124, 84 } },
	{ name = "Satchel", capacity = 50, price = 90, color = { 125, 82, 52 } },
	{ name = "Rucksack", capacity = 120, price = 1500, color = { 74, 112, 64 } },
	{ name = "Miner's Pack", capacity = 300, price = 15000, color = { 205, 145, 45 } },
	{ name = "Ore Hauler", capacity = 750, price = 100000, color = { 92, 94, 112 } },
	{ name = "Gem Vault", capacity = 2000, price = 750000, color = { 60, 160, 222 }, trim = { 160, 240, 255 } },
	{ name = "Bottomless Bag", capacity = 6000, price = 5000000, color = { 122, 42, 165 }, trim = { 255, 120, 255 } },
	{ name = "Pocket Dimension", capacity = 20000, price = 40000000, color = { 22, 20, 32 }, trim = { 140, 90, 255 } },
}

-- Treasures, in museum order. chance is per block broken at or below `depth` metres.
local TREASURES = {
	{ id = "OldBoot", name = "Old Boot", depth = 0, chance = 1 / 350, reward = 60, color = { 150, 100, 60 }, hint = "Somewhere near the top" },
	{ id = "AncientCoin", name = "Ancient Coin", depth = 10, chance = 1 / 700, reward = 400, color = { 240, 190, 70 }, hint = "Deeper than 10m" },
	{ id = "FossilSkull", name = "Fossil Skull", depth = 30, chance = 1 / 1400, reward = 3000, color = { 230, 220, 192 }, hint = "Deeper than 30m" },
	{ id = "GoldenIdol", name = "Golden Idol", depth = 60, chance = 1 / 2400, reward = 30000, color = { 255, 200, 50 }, hint = "Deeper than 60m" },
	{ id = "DragonEgg", name = "Dragon Egg", depth = 100, chance = 1 / 4000, reward = 300000, color = { 255, 90, 60 }, hint = "Deeper than 100m" },
	{ id = "Meteorite", name = "Meteorite", depth = 150, chance = 1 / 6500, reward = 2500000, color = { 255, 140, 60 }, hint = "Deeper than 150m" },
	{ id = "CrownOfTheDeep", name = "Crown of the Deep", depth = 220, chance = 1 / 12000, reward = 40000000, color = { 120, 200, 255 }, hint = "Deeper than 220m" },
	{ id = "RubberDuck", name = "Rubber Duck", depth = 0, chance = 1 / 40000, reward = 1000000, color = { 255, 220, 40 }, hint = "Anywhere... if you're lucky" },
}

-- Daily chest base reward by pickaxe tier, so it stays useful as you progress.
local DAILY = { 100, 300, 1500, 8000, 40000, 250000, 1600000, 12000000, 80000000 }

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
for _, name in { "Hit", "Surface", "Mined", "Treasure", "Geode", "Sold", "Notify", "Announce", "Bought", "Reward" } do
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
	local grass = Color3.fromRGB(96, 158, 76)
	local wood = Color3.fromRGB(122, 84, 54)
	local darkWood = Color3.fromRGB(84, 58, 40)
	local stone = Color3.fromRGB(150, 150, 156)

	-- Lighting
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(88, 86, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.6
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.28
		atmo.Offset = 0.15
		atmo.Color = Color3.fromRGB(200, 215, 235)
		atmo.Decay = Color3.fromRGB(120, 130, 160)
		atmo.Glare = 0.2
		atmo.Haze = 1.2
		atmo.Parent = Lighting
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 22
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting

	-- Ground: four slabs around the mine. Their thickness is exactly one block,
	-- so row 0 of the mine sits flush with the grass.
	local function slab(cx, cz, sx, sz)
		newPart({ Name = "Ground", Size = Vector3.new(sx, BLOCK, sz), Position = W(cx, -BLOCK / 2, cz), Color = grass, Material = Enum.Material.Grass }, town)
	end
	slab(0, (PIT + EDGE) / 2, EDGE * 2, EDGE - PIT)
	slab(0, -(PIT + EDGE) / 2, EDGE * 2, EDGE - PIT)
	slab(-(PIT + EDGE) / 2, 0, EDGE - PIT, PIT * 2)
	slab((PIT + EDGE) / 2, 0, EDGE - PIT, PIT * 2)

	-- Paths
	local path = Color3.fromRGB(176, 142, 100)
	newPart({ Name = "Path", Size = Vector3.new(12, 0.2, 60), Position = W(0, 0.1, -105), Color = path, Material = Enum.Material.Ground, CanCollide = false }, town)
	newPart({ Name = "Path", Size = Vector3.new(250, 0.2, 10), Position = W(0, 0.1, -95), Color = path, Material = Enum.Material.Ground, CanCollide = false }, town)
	newPart({ Name = "Path", Size = Vector3.new(12, 0.2, 30), Position = W(0, 0.1, -142), Color = path, Material = Enum.Material.Ground, CanCollide = false }, town)

	-- Pit rim: a low wooden frame so you can see where the mine is.
	newPart({ Name = "Rim", Size = Vector3.new(PIT * 2 + 3, 0.6, 1.5), Position = W(0, 0.3, PIT + 0.75), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
	newPart({ Name = "Rim", Size = Vector3.new(PIT * 2 + 3, 0.6, 1.5), Position = W(0, 0.3, -PIT - 0.75), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
	newPart({ Name = "Rim", Size = Vector3.new(1.5, 0.6, PIT * 2), Position = W(PIT + 0.75, 0.3, 0), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
	newPart({ Name = "Rim", Size = Vector3.new(1.5, 0.6, PIT * 2), Position = W(-PIT - 0.75, 0.3, 0), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
	local e = PIT + 2
	for _, c in { { -e, -e }, { e, -e }, { -e, e }, { e, e }, { 0, e }, { -e, 0 }, { e, 0 }, { 30, -e }, { -30, -e } } do
		newPart({ Name = "LanternPost", Size = Vector3.new(0.7, 8, 0.7), Position = W(c[1], 4, c[2]), Color = darkWood, Material = Enum.Material.Wood }, town)
		newPart({ Name = "LanternArm", Size = Vector3.new(0.4, 0.4, 2), Position = W(c[1], 7.8, c[2] + (if c[2] > 0 then -1 else 1)), Color = darkWood, Material = Enum.Material.Wood }, town)
		local lamp = newPart({ Name = "Lantern", Size = Vector3.new(1.1, 1.3, 1.1), Position = W(c[1], 7, c[2] + (if c[2] > 0 then -1.8 else 1.8)), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon, CanCollide = false }, town)
		addLight(lamp, Color3.fromRGB(255, 190, 110), 20, 1.2)
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
	local cartPos = SELL_POS + Vector3.new(12, 0, 0)
	newPart({ Name = "Cart", Size = Vector3.new(6, 2.6, 4), Position = cartPos + Vector3.new(0, 2.2, 0), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
	newPart({ Name = "CartRim", Size = Vector3.new(6.4, 0.4, 4.4), Position = cartPos + Vector3.new(0, 3.6, 0), Color = Color3.fromRGB(80, 80, 88), Material = Enum.Material.Metal }, town)
	for _, wx in { -2, 2 } do
		for _, wz in { -2.1, 2.1 } do
			newPart({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.8, 1.8), CFrame = CFrame.new(cartPos + Vector3.new(wx, 0.9, wz)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal }, town)
		end
	end
	local r = Random.new(3)
	for _ = 1, 9 do
		local o = ORES[({ "Coal", "Copper", "Iron", "Gold", "Ruby", "Emerald" })[r:NextInteger(1, 6)]]
		newPart({ Name = "Ore", Shape = Enum.PartType.Ball, Size = Vector3.one * r:NextNumber(1, 1.6), Position = cartPos + Vector3.new(r:NextNumber(-2, 2), 3.9, r:NextNumber(-1.2, 1.2)), Color = rgb(o.color), Material = material(o.material), CanCollide = false }, town)
	end

	-- Market stalls: pickaxes on the left of the path, backpacks on the right.
	local function stall(centerX, count, roofA, title)
		local length = count * 12 + 4
		newPart({ Name = "StallWall", Size = Vector3.new(length, 9, 1), Position = W(centerX, 4.5, -111), Color = wood, Material = Enum.Material.WoodPlanks }, town)
		for i = 1, count do
			local x = centerX - length / 2 + 2 + (i - 0.5) * 12
			local color = if i % 2 == 0 then roofA else Color3.fromRGB(245, 236, 216)
			newPart({ Name = "Awning", Size = Vector3.new(12, 0.6, 9), CFrame = CFrame.new(W(x, 9.4, -107)) * CFrame.Angles(math.rad(-14), 0, 0), Color = color, Material = Enum.Material.Fabric }, town)
		end
		for _, dx in { -length / 2, length / 2 } do
			newPart({ Name = "StallPost", Size = Vector3.new(0.8, 10, 0.8), Position = W(centerX + dx, 5, -103), Color = darkWood, Material = Enum.Material.Wood }, town)
		end
		local board = newPart({ Name = "StallSign", Size = Vector3.new(26, 5, 0.6), Position = W(centerX, 12.4, -110.5), Color = darkWood, Material = Enum.Material.WoodPlanks }, town)
		signText(board, Enum.NormalId.Back, title, Color3.fromRGB(255, 230, 160))
	end

	local function pedestal(x, z, kind, tier, name, stats, price)
		local base = newPart({ Name = "Pedestal", Size = Vector3.new(6, 3, 6), Position = W(x, 1.5, z), Color = stone, Material = Enum.Material.Slate }, town)
		newPart({ Name = "PedestalTop", Size = Vector3.new(6.6, 0.4, 6.6), Position = W(x, 3.2, z), Color = Color3.fromRGB(110, 110, 118), Material = Enum.Material.Slate }, town)
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
		model:PivotTo(CFrame.new(W(x, 7, -104)) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, math.rad(25), 0))
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
		model:PivotTo(CFrame.new(W(x, 6.3, -104)))
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

	-- Museum
	local mz = -164
	newPart({ Name = "MuseumFloor", Size = Vector3.new(106, 1, 30), Position = W(0, 0.5, mz), Color = Color3.fromRGB(236, 232, 222), Material = Enum.Material.Marble }, town)
	newPart({ Name = "MuseumWall", Size = Vector3.new(106, 15, 1.5), Position = W(0, 8.5, mz - 14.5), Color = Color3.fromRGB(210, 200, 185), Material = Enum.Material.Marble }, town)
	newPart({ Name = "MuseumRoof", Size = Vector3.new(110, 1.4, 34), Position = W(0, 16.6, mz - 1), Color = Color3.fromRGB(150, 60, 50), Material = Enum.Material.ClayRoofTiles }, town)
	for _, x in { -52, -26, 26, 52 } do
		newPart({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(15, 2.2, 2.2), CFrame = CFrame.new(W(x, 8.5, mz + 13)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(240, 236, 228), Material = Enum.Material.Marble }, town)
	end
	local mSign = newPart({ Name = "MuseumSign", Size = Vector3.new(44, 5, 0.6), Position = W(0, 20, mz + 14), Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.WoodPlanks }, town)
	signText(mSign, Enum.NormalId.Back, "🏛 MUSEUM OF THE DEEP", Color3.fromRGB(255, 225, 150))
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

	-- Scenery: a ring of mountains hides the world edge, then trees and rocks.
	local sr = Random.new(42)
	for i = 1, 28 do
		local a = (i / 28) * math.pi * 2 + sr:NextNumber(-0.05, 0.05)
		local dist = sr:NextNumber(275, 295)
		local h = sr:NextNumber(60, 150)
		local w = sr:NextNumber(55, 95)
		newPart({
			Name = "Mountain",
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(W(math.cos(a) * dist, h / 2 - 12, math.sin(a) * dist)) * CFrame.Angles(sr:NextNumber(-0.15, 0.15), sr:NextNumber(0, math.pi), sr:NextNumber(-0.15, 0.15)),
			Color = Color3.fromRGB(110, 118, 110):Lerp(Color3.fromRGB(90, 130, 80), sr:NextNumber()),
			Material = Enum.Material.Rock,
		}, town)
	end
	local function blocked(x, z)
		if math.abs(x) < PIT + 16 and math.abs(z) < PIT + 16 then
			return true
		end
		return x > -140 and x < 140 and z > -190 and z < -70
	end
	local placed = 0
	while placed < 46 do
		local x, z = sr:NextNumber(-255, 255), sr:NextNumber(-255, 255)
		if not blocked(x, z) then
			placed += 1
			local h = sr:NextNumber(7, 13)
			newPart({ Name = "Trunk", Size = Vector3.new(1.6, h, 1.6), Position = W(x, h / 2, z), Color = Color3.fromRGB(105, 74, 50), Material = Enum.Material.Wood }, town)
			for j = 1, 3 do
				local s = sr:NextNumber(5, 8) - j
				newPart({
					Name = "Leaves",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * s,
					Position = W(x + sr:NextNumber(-1.5, 1.5), h + j * 1.8 - 1, z + sr:NextNumber(-1.5, 1.5)),
					Color = Color3.fromRGB(70, 140, 60):Lerp(Color3.fromRGB(120, 175, 70), sr:NextNumber()),
					Material = Enum.Material.Grass,
				}, town)
			end
		end
	end
	placed = 0
	while placed < 30 do
		local x, z = sr:NextNumber(-260, 260), sr:NextNumber(-260, 260)
		if not blocked(x, z) then
			placed += 1
			local s = sr:NextNumber(2, 6)
			newPart({
				Name = "Rock",
				Size = Vector3.new(s * sr:NextNumber(1, 1.6), s, s * sr:NextNumber(1, 1.4)),
				CFrame = CFrame.new(W(x, s * 0.3, z)) * CFrame.Angles(sr:NextNumber(-0.3, 0.3), sr:NextNumber(0, 6), sr:NextNumber(-0.3, 0.3)),
				Color = Color3.fromRGB(128, 128, 134),
				Material = Enum.Material.Rock,
			}, town)
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
local BEDROCK = Color3.fromRGB(26, 26, 30)
local GRASS_TOP = Color3.fromRGB(96, 158, 76)
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
		cells[k] = true -- the grass slab already fills this spot
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(BLOCK, BLOCK, BLOCK)
	p.CFrame = CFrame.new(cellPos(x, y, z))
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if outside or y >= MAX_DEPTH then
		p.Name = "Bedrock"
		p.Color = BEDROCK
		p.Material = Enum.Material.Slate
		p:SetAttribute("Bedrock", true)
	else
		local L = layerAt(y)
		local kind = rollKind(y, L)
		local info = { x = x, y = y, z = z, kind = kind, pos = p.Position }
		local hp
		if kind == "Geode" then
			p.Name = "Geode"
			p.Color = GEODE_COLOR
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.15
			addLight(p, GEODE_COLOR, 12, 1.4)
			hp = L.hp * 14
			info.value = math.floor(layerAverage(L) * 60)
			info.hitters = {}
			p:SetAttribute("Geode", true)
		elseif kind ~= "" then
			local O = ORES[kind]
			p.Name = O.name
			p.Color = rgb(O.color)
			p.Material = material(O.material)
			if O.material == "Glass" then
				p.Reflectance = 0.12
			end
			if O.glow then
				addLight(p, rgb(O.color), 9, 0.9)
			end
			hp = L.hp * O.hp
			info.value = O.value
			p:SetAttribute("Ore", kind)
		else
			p.Name = L.name
			local base = if y == 0 then GRASS_TOP else rgb(L.color)
			p.Color = base:Lerp(Color3.new(0, 0, 0), rng:NextNumber() * 0.09)
			p.Material = if y == 0 then Enum.Material.Grass else material(L.material)
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

local function buildMineTop()
	for x = 0, GRID - 1 do
		for z = 0, GRID - 1 do
			spawnBlock(x, 0, z)
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
		coins = 0, pick = 1, bag = 1, best = 0, mined = 0,
		bagCount = 0, bagValue = 0, treasures = {},
		streak = 0, lastDay = -1, earned = 0, tut = 0,
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

local function uniqueTreasures(d)
	local n = 0
	for _ in d.treasures do
		n += 1
	end
	return n
end

local function valueMult(player)
	local d = sessions[player]
	local m = 1 + uniqueTreasures(d) * TREASURE_BONUS
	if player:GetAttribute("FriendBonus") then
		m *= 1 + FRIEND_BONUS
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
	player:SetAttribute("BagMax", BAGS[d.bag].capacity)
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
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Depth.Value = d.best
		stats.Coins.Value = d.coins
	end
end

local function notify(player, text, color)
	Remotes.Notify:FireClient(player, text, color or Color3.fromRGB(255, 255, 255))
end

--------------------------------------------------------------------------------
-- CHARACTER: pickaxe tool, backpack on your back, headlamp
--------------------------------------------------------------------------------
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
	local f = math.clamp(d.bagCount / BAGS[d.bag].capacity, 0, 1)
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
	announce(`🏆 {player.DisplayName} found {article(T.name)} {T.name} at {depth}m!`, rgb(T.color))
end

local function breakBlock(player, part, info)
	local d = sessions[player]
	clearCell(info.x, info.y, info.z)
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
	elseif d.bagCount < BAGS[d.bag].capacity then
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
		if depth >= T.depth and rng:NextNumber() < T.chance then
			awardTreasure(player, T, info.pos, depth)
			break
		end
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
	if now - (lastHit[player] or 0) < pick.speed * 0.75 then
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
	stats.Parent = player

	local d = loadData(player)
	if not player.Parent then
		return
	end
	sessions[player] = d
	sync(player)
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
