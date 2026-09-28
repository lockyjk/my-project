--[[
	⛏  DIG DEEP  ·  CLIENT
	Paste this into a LocalScript in StarterPlayer > StarterPlayerScripts.
	Needs DigDeepServer (a Script in ServerScriptService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("DigRemotes")
local CFG = HttpService:JSONDecode(Remotes:WaitForChild("DigConfig").Value)
local TreasureModels = ReplicatedStorage:WaitForChild("DigTreasures")
local mineFolder = workspace:WaitForChild("Mine")

-- SOUNDS. Each entry lists ids to try in order: Creator Store sounds first, then Roblox's
-- built-in sounds as a fallback. A sound that fails to load prints a warning in Output.
-- "(SFX)" ids are from Roblox's own licensed sound library; music is APM, licensed by Roblox.
local SOUNDS = {
	Swing = { ids = { "rbxasset://sounds/swordslash.wav" }, volume = 0.18 },
	Hit = { ids = { "rbxassetid://1682469441", "rbxassetid://9118628948", "rbxasset://sounds/action_jump_land.mp3" }, volume = 0.35 }, -- Pickaxe Hit / Rock Impacts 13 (SFX)
	Break = { ids = { "rbxassetid://4796117828", "rbxassetid://4088521402", "rbxasset://sounds/action_jump_land.mp3" }, volume = 0.45 }, -- Block Break / Rock Hit
	Pickup = { ids = { "rbxassetid://9126073011", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.3 }, -- Synth Sparkle Ding (SFX)
	Sell = { ids = { "rbxassetid://7112275565", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.6 }, -- Cash Register (Kaching)
	Treasure = { ids = { "rbxassetid://8807795651", "rbxassetid://3356359494", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.8 }, -- Fairy dust / Magic
	Buy = { ids = { "rbxassetid://4729756264", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.6 }, -- Power Up
	LevelUp = { ids = { "rbxassetid://2686079706", "rbxassetid://4729756264", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.7 }, -- level up
	Click = { ids = { "rbxassetid://6655842594", "rbxassetid://876939830", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.5 }, -- Button / Click
	Pop = { ids = { "rbxassetid://339325394", "rbxassetid://2375539277", "rbxasset://sounds/electronicpingshort.wav" }, volume = 0.5 }, -- Pop
	EggCrack = { ids = { "rbxassetid://9113959332", "rbxassetid://9113959751", "rbxasset://sounds/action_jump_land.mp3" }, volume = 0.8 }, -- Crack Egg Crunchy (SFX)
	Full = { ids = { "rbxasset://sounds/action_jump_land.mp3" }, volume = 0.5 },
}
local MUSIC = {
	"rbxassetid://1843404009", -- Happy Song (APM)
	"rbxassetid://9039520885", -- Breezy Days (APM)
	"rbxassetid://1848354536", -- Relaxed Scene (APM)
}
local AMBIENCE = {
	Surface = { "rbxassetid://105667490483473", "rbxassetid://9125515917" }, -- forest wind / Eastern Wind (SFX)
	Cave = { "rbxassetid://9112775175", "rbxassetid://9125351660" }, -- Eerie Ambience 1 (SFX) / rumbling ambience (SFX)
}

-- Player settings (saved on the server; these are the defaults)
local settings = { music = true, musicVol = 0.5, sfx = true, sfxVol = 0.8, ambience = true, otherPets = true, shake = true }

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 208, 70)
local RED = Color3.fromRGB(255, 90, 80)
local GREEN = Color3.fromRGB(110, 230, 130)
local INK = Color3.fromRGB(22, 20, 26)

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
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

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function create(className, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if children then
		for _, c in children do
			if c:IsA("UIStroke") and inst:IsA("TextButton") then
				c.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = radius or UDim.new(1, 0) })
end

local function stroke(thickness, color, transparency)
	return create("UIStroke", { Thickness = thickness, Color = color or INK, Transparency = transparency or 0 })
end

local function gradient(parent, top, bottom, rotation)
	return create("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90, Parent = parent })
end

local function tween(inst, time, props, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local playSound, applySoundSettings, musicSound, ambienceSounds
do
	local ContentProvider = game:GetService("ContentProvider")
	local function soundGroup(name)
		local g = SoundService:FindFirstChild(name) or Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
		return g
	end
	local sfxGroup, musicGroup, ambienceGroup = soundGroup("DigSFX"), soundGroup("DigMusic"), soundGroup("DigAmbience")

	-- Try each id until one loads. Built-in rbxasset sounds always work, so they come last.
	local function loadInto(sound, ids, label)
		task.spawn(function()
			for i, id in ids do
				sound.SoundId = id
				local ok = true
				pcall(function()
					ContentProvider:PreloadAsync({ sound }, function(_, status)
						if status ~= Enum.AssetFetchStatus.Success then
							ok = false
						end
					end)
				end)
				if ok then
					return
				end
				if i < #ids then
					warn(`[DigDeep] Sound "{label}" couldn't load {id}; trying the next one`)
				else
					warn(`[DigDeep] Sound "{label}" couldn't load any of its ids. Replace them in the SOUNDS table.`)
				end
			end
		end)
	end

	local soundTemplates = {}
	for name, def in SOUNDS do
		local s = Instance.new("Sound")
		s.Name = name
		s.Volume = def.volume
		s.SoundGroup = sfxGroup
		soundTemplates[name] = s
		loadInto(s, def.ids, name)
	end

	playSound = function(name, pitch)
		local template = soundTemplates[name]
		if not template or not settings.sfx or template.SoundId == "" then
			return
		end
		local s = template:Clone()
		s.PlaybackSpeed = pitch or 1
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 6)
	end

	-- Background music: loops through the playlist, quieter underground.
	musicSound = Instance.new("Sound")
	musicSound.Name = "DigMusic"
	musicSound.SoundGroup = musicGroup
	musicSound.Volume = 0.35
	musicSound.Parent = SoundService
	local musicIndex = math.random(1, #MUSIC)
	local function nextTrack()
		musicIndex = musicIndex % #MUSIC + 1
		musicSound.SoundId = MUSIC[musicIndex]
		loadInto(musicSound, { MUSIC[musicIndex] }, "Music " .. musicIndex)
		if settings.music then
			musicSound:Play()
		end
	end
	musicSound.Ended:Connect(nextTrack)

	ambienceSounds = {}
	for key, ids in AMBIENCE do
		local s = Instance.new("Sound")
		s.Name = "Ambience" .. key
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = ambienceGroup
		s.Parent = SoundService
		loadInto(s, ids, "Ambience " .. key)
		ambienceSounds[key] = s
	end

	applySoundSettings = function()
		sfxGroup.Volume = if settings.sfx then settings.sfxVol else 0
		musicGroup.Volume = if settings.music then settings.musicVol else 0
		ambienceGroup.Volume = if settings.ambience then 1 else 0
		if settings.music and not musicSound.IsPlaying then
			if musicSound.SoundId == "" then
				nextTrack()
			else
				musicSound:Resume()
			end
		elseif not settings.music and musicSound.IsPlaying then
			musicSound:Pause()
		end
		for _, s in ambienceSounds do
			if settings.ambience and not s.IsPlaying then
				s:Play()
			elseif not settings.ambience and s.IsPlaying then
				s:Stop()
			end
		end
	end
end

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function layerIndexAt(depth)
	local index = 1
	for i, L in CFG.layers do
		if depth >= L.from then
			index = i
		end
	end
	return index
end

local function currentDepth()
	local root = getRoot()
	if not root then
		return 0
	end
	local feet = root.Position.Y - 3
	return math.max(0, math.floor((CFG.top - feet) / CFG.block + 0.05))
end

local function ownedTreasures()
	local raw = player:GetAttribute("Treasures")
	if type(raw) ~= "string" then
		return {}
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

local function attr(name, default)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

--------------------------------------------------------------------------------
-- HUD (deliberately tiny: coins, bag, depth, one button)
--------------------------------------------------------------------------------
local gui = create("ScreenGui", {
	Name = "DigHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Coins, top centre
local coinRow = create("Frame", {
	Name = "Coins",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 14, 0, 66),
	Size = UDim2.fromOffset(0, 48),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = WHITE,
	Parent = gui,
}, {
	corner(),
	stroke(4, Color3.fromRGB(120, 70, 10)),
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 22) }),
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
gradient(coinRow, Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 160, 30))
local coinScale = create("UIScale", { Parent = coinRow })
local coinIcon = create("Frame", {
	LayoutOrder = 1,
	Size = UDim2.fromOffset(36, 36),
	BackgroundColor3 = GOLD,
	Parent = coinRow,
}, {
	corner(),
	stroke(2.5, Color3.fromRGB(150, 95, 20)),
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		BackgroundColor3 = Color3.fromRGB(255, 232, 140),
	}, { corner() }),
})
local coinLabel = create("TextLabel", {
	LayoutOrder = 2,
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 36,
	TextColor3 = WHITE,
	Text = "0",
	Parent = coinRow,
}, { stroke(3.5, Color3.fromRGB(110, 60, 5)) })

local eventLabel = create("TextLabel", {
	Name = "Event",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 72),
	Size = UDim2.fromOffset(360, 20),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(230, 230, 235),
	TextTransparency = 0.15,
	Text = "",
	Parent = gui,
}, { stroke(2, INK, 0.3) })

-- Bag pill, bottom centre
local bagPill = create("Frame", {
	Name = "Bag",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -22),
	Size = UDim2.fromOffset(310, 42),
	BackgroundColor3 = Color3.fromRGB(58, 40, 96),
	Parent = gui,
}, { corner(), stroke(4, INK) })
local bagScale = create("UIScale", { Parent = bagPill })
local bagFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = WHITE,
	ZIndex = 1,
	Parent = bagPill,
}, { corner() })
local bagGradient = gradient(bagFill, Color3.fromRGB(140, 240, 110), Color3.fromRGB(60, 190, 70))
local bagLabel = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 18,
	TextColor3 = WHITE,
	Text = "🎒 0 / 20",
	ZIndex = 2,
	Parent = bagPill,
}, { stroke(2) })

-- Next goal, just above the bag: always shows what you're working towards
local goalPill = create("Frame", {
	Name = "NextGoal",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -74),
	Size = UDim2.fromOffset(250, 24),
	BackgroundColor3 = Color3.fromRGB(40, 30, 70),
	Parent = gui,
}, { corner(), stroke(3, INK) })
local goalFill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = goalPill }, { corner() })
gradient(goalFill, Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 150, 30))
local goalText = create("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextColor3 = WHITE, Text = "", ZIndex = 2, Parent = goalPill }, { stroke(2) })

-- Depth gauge, right edge (only underground)
local gauge = create("Frame", {
	Name = "Depth",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -34, 0.6, 0),
	Size = UDim2.fromOffset(8, 230),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
for i, L in CFG.layers do
	local nextFrom = if CFG.layers[i + 1] then CFG.layers[i + 1].from else CFG.maxDepth
	create("Frame", {
		Position = UDim2.fromScale(0, L.from / CFG.maxDepth),
		Size = UDim2.fromScale(1, (nextFrom - L.from) / CFG.maxDepth),
		BackgroundColor3 = rgb(L.color):Lerp(WHITE, 0.25),
		BorderSizePixel = 0,
		Parent = gauge,
	})
end
create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = gauge })
local bestTick = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.new(0, 18, 0, 2),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Parent = gauge,
})
local marker = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = WHITE,
	ZIndex = 3,
	Parent = gauge,
}, { corner(), stroke(2.5) })
local depthLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(0, -10, 0.5, -8),
	Size = UDim2.fromOffset(150, 26),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = WHITE,
	Text = "0m",
	Parent = marker,
}, { stroke(2.5) })
local layerLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(0, -10, 0.5, 12),
	Size = UDim2.fromOffset(150, 16),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(215, 215, 225),
	Text = "",
	Parent = marker,
}, { stroke(2) })

-- Surface button, bottom right (only underground)
local surfaceButton = create("TextButton", {
	Name = "Surface",
	AnchorPoint = Vector2.new(1, 1),
	Position = if isTouch then UDim2.new(1, -28, 1, -190) else UDim2.new(1, -28, 1, -24),
	Size = UDim2.fromOffset(84, 84),
	BackgroundColor3 = WHITE,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	Parent = gui,
}, {
	corner(UDim.new(0.3, 0)),
	stroke(4, INK),
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0.6, 0),
		Position = UDim2.fromScale(0, 0.08),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 34,
		TextColor3 = WHITE,
		Text = "⬆",
	}, { stroke(2) }),
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.fromScale(0, 0.6),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 13,
		TextColor3 = WHITE,
		Text = if isTouch then "SURFACE" else "SURFACE [R]",
	}, { stroke(1.5) }),
})

gradient(surfaceButton, Color3.fromRGB(120, 235, 120), Color3.fromRGB(40, 170, 70))

-- Tutorial hint, lower centre
local hintLabel = create("TextLabel", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.74),
	Size = UDim2.fromOffset(600, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 24,
	TextColor3 = WHITE,
	TextTransparency = 1,
	Text = "",
	Parent = gui,
}, { stroke(3, INK, 1) })
local hintStroke = hintLabel:FindFirstChildOfClass("UIStroke")

-- Toast, upper centre
local toastLabel = create("TextLabel", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.25),
	Size = UDim2.fromOffset(600, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 24,
	TextColor3 = WHITE,
	TextTransparency = 1,
	Text = "",
	Parent = gui,
}, { stroke(2.5, INK, 1) })
local toastStroke = toastLabel:FindFirstChildOfClass("UIStroke")

-- Server-wide announcement banner
local banner = create("Frame", {
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -80),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(40, 30, 70),
	Parent = gui,
}, {
	corner(),
	create("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }),
})
gradient(banner, Color3.fromRGB(80, 60, 140), Color3.fromRGB(34, 24, 64))
local bannerStroke = create("UIStroke", { Thickness = 4, Color = GOLD, Parent = banner })
local bannerLabel = create("TextLabel", {
	Size = UDim2.fromScale(0, 1),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 20,
	TextColor3 = WHITE,
	Text = "",
	Parent = banner,
}, { stroke(2) })

-- Treasure reveal text, centre
local reveal = create("Frame", {
	Name = "Reveal",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromOffset(700, 140),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
}, {
	create("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
})
local revealScale = create("UIScale", { Parent = reveal })
local revealTop = create("TextLabel", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Font = FONT, TextSize = 22, TextColor3 = GOLD, Text = "", Parent = reveal }, { stroke(2.5) })
local revealName = create("TextLabel", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Font = FONT, TextSize = 52, TextColor3 = WHITE, Text = "", Parent = reveal }, { stroke(4) })
local revealSub = create("TextLabel", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Font = FONT, TextSize = 24, TextColor3 = GOLD, Text = "", Parent = reveal }, { stroke(2.5) })
local revealNote = create("TextLabel", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = FONT, TextSize = 18, TextColor3 = GREEN, Text = "", Parent = reveal }, { stroke(2) })

--------------------------------------------------------------------------------
-- HUD BEHAVIOUR
--------------------------------------------------------------------------------
local shownCoins = attr("Coins", 0)
local coinValue = Instance.new("NumberValue")
coinValue.Value = shownCoins
coinLabel.Text = fmt(shownCoins)
coinValue.Changed:Connect(function(v)
	coinLabel.Text = fmt(v)
end)

local function pulse(scaleObj, amount)
	scaleObj.Scale = amount
	tween(scaleObj, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function refreshCoins()
	local target = attr("Coins", 0)
	if target > coinValue.Value then
		pulse(coinScale, 1.12)
	end
	tween(coinValue, 0.45, { Value = target })
end
player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)

local lastBag = attr("Bag", 0)
local function refreshBag()
	local count, max = attr("Bag", 0), attr("BagMax", 20)
	local f = math.clamp(count / math.max(1, max), 0, 1)
	local full = count >= max
	tween(bagFill, 0.2, { Size = UDim2.fromScale(f, 1) })
	bagGradient.Color = if full
		then ColorSequence.new(Color3.fromRGB(255, 120, 110), Color3.fromRGB(220, 50, 50))
		elseif f > 0.75 then ColorSequence.new(Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 160, 30))
		else ColorSequence.new(Color3.fromRGB(140, 240, 110), Color3.fromRGB(60, 190, 70))
	local worth = attr("BagValue", 0)
	bagLabel.Text = if full
		then "🎒 FULL · SURFACE TO SELL"
		elseif worth > 0 then `🎒 {fmt(count)} / {fmt(max)}  ·  💰 {fmt(worth)}`
		else `🎒 {fmt(count)} / {fmt(max)}`
	bagLabel.TextSize = if full then 15 else 18
	if count > lastBag then
		pulse(bagScale, 1.06)
	end
	lastBag = count
end
player:GetAttributeChangedSignal("Bag"):Connect(refreshBag)
player:GetAttributeChangedSignal("BagMax"):Connect(refreshBag)
player:GetAttributeChangedSignal("BagValue"):Connect(refreshBag)
refreshBag()

local toastToken = 0
local function toast(text, color)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or WHITE
	toastLabel.TextTransparency = 0
	toastStroke.Transparency = 0
	toastLabel.Position = UDim2.fromScale(0.5, 0.27)
	tween(toastLabel, 0.25, { Position = UDim2.fromScale(0.5, 0.25) }, Enum.EasingStyle.Back)
	task.delay(2.4, function()
		if token == toastToken then
			tween(toastLabel, 0.4, { TextTransparency = 1 })
			tween(toastStroke, 0.4, { Transparency = 1 })
		end
	end)
end

local bannerQueue = {}
local bannerBusy = false
local function showBanner(text, color)
	table.insert(bannerQueue, { text = text, color = color })
	if bannerBusy then
		return
	end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local item = table.remove(bannerQueue, 1)
			bannerLabel.Text = item.text
			bannerStroke.Color = item.color or GOLD
			bannerLabel.TextColor3 = WHITE
			banner.Position = UDim2.new(0.5, 0, 0, -80)
			tween(banner, 0.45, { Position = UDim2.new(0.5, 0, 0, 132) }, Enum.EasingStyle.Back)
			task.wait(if #bannerQueue > 0 then 2.6 else 4)
			tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -80) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.35)
		end
		bannerBusy = false
	end)
end

local hintText = ""
local function setHint(text)
	if text == hintText then
		return
	end
	hintText = text
	if text == "" then
		tween(hintLabel, 0.3, { TextTransparency = 1 })
		tween(hintStroke, 0.3, { Transparency = 1 })
	else
		hintLabel.Text = text
		tween(hintLabel, 0.3, { TextTransparency = 0 })
		tween(hintStroke, 0.3, { Transparency = 0 })
	end
end

--------------------------------------------------------------------------------
-- WORLD EFFECTS
--------------------------------------------------------------------------------
local function worldAttachment(pos, life)
	local a = Instance.new("Attachment")
	a.Position = pos
	a.Parent = workspace.Terrain
	Debris:AddItem(a, life)
	return a
end

local function sparkle(pos, color, count, speed)
	local a = worldAttachment(pos, 2)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.6
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -30, 0)
	pe.Drag = 3
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(count)
end

local function dust(pos, color, count)
	local a = worldAttachment(pos, 2)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(color:Lerp(WHITE, 0.25))
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	pe.Lifetime = NumberRange.new(0.5, 0.9)
	pe.Speed = NumberRange.new(3, 7)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(count)
end

local chunkCount = 0
local function chunks(pos, color, material, count)
	for _ = 1, count do
		if chunkCount > 60 then
			return
		end
		chunkCount += 1
		local s = math.random(45, 100) / 100
		local p = Instance.new("Part")
		p.Size = Vector3.new(s, s, s)
		p.Color = color
		p.Material = material
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.5, 0.2)
		p.CFrame = CFrame.new(pos + Vector3.new(math.random(-15, 15) / 10, math.random(-15, 15) / 10, math.random(-15, 15) / 10))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = workspace
		p.AssemblyLinearVelocity = Vector3.new(math.random(-12, 12), math.random(8, 20), math.random(-12, 12))
		p.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		task.delay(0.7, function()
			tween(p, 0.35, { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
		end)
		task.delay(1.1, function()
			chunkCount -= 1
			p:Destroy()
		end)
	end
end

local function popup(pos, text, color, size, rise, duration)
	local a = worldAttachment(pos, duration + 0.2)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = a
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.Size = UDim2.fromOffset(360, size + 12)
	local label = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = size,
		TextColor3 = color,
		Text = text,
		Parent = bb,
	})
	local st = stroke(math.max(2, size / 12), INK)
	st.Parent = label
	local scale = create("UIScale", { Scale = 0.4, Parent = bb })
	bb.Parent = a
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(bb, duration, { StudsOffsetWorldSpace = Vector3.new(0, rise, 0) }, Enum.EasingStyle.Quad)
	task.delay(duration * 0.6, function()
		tween(label, duration * 0.4, { TextTransparency = 1 })
		tween(st, duration * 0.4, { Transparency = 1 })
	end)
end

local shake = 0
local function kick(amount)
	if settings.shake then
		shake = math.max(shake, amount)
	end
end

--------------------------------------------------------------------------------
-- MINING INPUT
--------------------------------------------------------------------------------
local selection = Instance.new("SelectionBox")
selection.LineThickness = 0.04
selection.Color3 = WHITE
selection.SurfaceColor3 = Color3.new(0, 0, 0)
selection.SurfaceTransparency = 1
selection.Transparency = 0.25
selection.Parent = camera

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { mineFolder }

local mouseHeld = false
local autoMine = false -- Auto Mine pass toggle
local activeTouch = nil
local touchPos = nil
local touchStart = nil
local touchDragged = false
local DRAG_PIXELS = 14
local lastSwing = 0
local lastSurfaceRequest = 0

local function requestSurface()
	if os.clock() - lastSurfaceRequest < 1.5 then
		return
	end
	lastSurfaceRequest = os.clock()
	Remotes.Surface:FireServer()
end

surfaceButton.Activated:Connect(requestSurface)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		activeTouch = input
		touchPos = Vector2.new(input.Position.X, input.Position.Y)
		touchStart = touchPos
		touchDragged = false
	elseif input.KeyCode == Enum.KeyCode.R and currentDepth() > 0 then
		requestSurface()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input == activeTouch then
		touchPos = Vector2.new(input.Position.X, input.Position.Y)
		if touchStart and (touchPos - touchStart).Magnitude > DRAG_PIXELS then
			touchDragged = true
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	elseif input == activeTouch then
		activeTouch = nil
		touchPos = nil
		touchStart = nil
		touchDragged = false
	end
end)

local function pointerRay()
	if activeTouch and touchPos then
		return camera:ScreenPointToRay(touchPos.X, touchPos.Y)
	end
	if UserInputService.MouseEnabled then
		local m = UserInputService:GetMouseLocation()
		return camera:ViewportPointToRay(m.X, m.Y)
	end
	return nil
end

local function swingTime()
	local pick = CFG.picks[attr("Pick", 1)] or CFG.picks[1]
	return pick.speed
end

local function playSwing()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool then
		-- The default Animate script plays its slash animation when it sees this value.
		local v = Instance.new("StringValue")
		v.Name = "toolanim"
		v.Value = "Slash"
		v.Parent = tool
	end
end

local function findTarget()
	local ray = pointerRay()
	local root = getRoot()
	if not ray or not root then
		return nil, nil
	end
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, rayParams)
	if not result then
		return nil, nil
	end
	local part = result.Instance
	if part:GetAttribute("Bedrock") then
		return nil, nil
	end
	if (part.Position - root.Position).Magnitude > CFG.reach then
		return nil, nil
	end
	return part, result.Position
end

local function updateMining()
	local hum = getHumanoid()
	local holding = mouseHeld or (activeTouch ~= nil and not touchDragged)
	local target, hitPos = nil, nil
	if hum and hum.Health > 0 and (holding or not isTouch) then
		target, hitPos = findTarget()
	end
	-- Auto Mine pass: keep digging the block under your feet (or whatever you point at)
	if autoMine and hum and hum.Health > 0 and not holding then
		holding = true
		if not target then
			local root = getRoot()
			if root then
				local down = workspace:Raycast(root.Position, Vector3.new(0, -9, 0), rayParams)
				if down and not down.Instance:GetAttribute("Bedrock") then
					target, hitPos = down.Instance, down.Position
				end
			end
		end
	end

	if target then
		selection.Adornee = target
		local hp, maxHp = target:GetAttribute("HP"), target:GetAttribute("MaxHP")
		if hp and maxHp and maxHp > 0 then
			selection.SurfaceTransparency = 1 - 0.55 * (1 - hp / maxHp)
		else
			selection.SurfaceTransparency = 1
		end
		selection.Color3 = if target:GetAttribute("Geode") then Color3.fromRGB(200, 140, 255) else WHITE
	else
		selection.Adornee = nil
	end

	local now = os.clock()
	if holding and target and hitPos and now - lastSwing >= swingTime() then
		lastSwing = now
		local blockColor = target.Color
		Remotes.Hit:FireServer(target)
		playSwing()
		playSound("Swing", 0.9 + math.random() * 0.25)
		playSound("Hit", 0.85 + math.random() * 0.3)
		dust(hitPos, blockColor, 3)
		sparkle(hitPos, blockColor:Lerp(WHITE, 0.4), 4, 10)
		selection.LineThickness = 0.12
		tween(selection, 0.15, { LineThickness = 0.04 })
		kick(0.06)
	end
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------
local lastFullPopup = 0

Remotes.Mined.OnClientEvent:Connect(function(pos, kind, color, collected, full)
	local mat = Enum.Material.Slate
	dust(pos, color, 8)
	chunks(pos, color, mat, 5)
	playSound("Break", 0.85 + math.random() * 0.3)
	kick(0.12)
	if kind ~= "" and kind ~= "Geode" and collected then
		local ore = CFG.ores[kind]
		if ore then
			local tier = ore.tier or 1
			local c = rgb(ore.color)
			popup(pos, "+1 " .. ore.name, c:Lerp(WHITE, 0.15), 20 + tier * 4, 4 + tier, 1.1 + tier * 0.1)
			sparkle(pos, c, 8 + tier * 6, 14 + tier * 3)
			playSound("Pickup", 0.9 + tier * 0.12)
			if tier >= 4 then
				kick(0.35)
			end
		end
	end
	if full and os.clock() - lastFullPopup > 1.5 then
		lastFullPopup = os.clock()
		popup(pos, "BAG FULL", RED, 26, 4, 1)
		playSound("Full", 0.8)
		pulse(bagScale, 1.18)
	end
end)

Remotes.Geode.OnClientEvent:Connect(function(pos, amount, count)
	local purple = Color3.fromRGB(190, 120, 255)
	popup(pos, "💎 GEODE +" .. fmt(amount), purple, 36, 7, 2)
	if count > 1 then
		popup(pos - Vector3.new(0, 1.5, 0), `shared by {count} miners`, WHITE, 18, 5, 2)
	end
	sparkle(pos, purple, 40, 26)
	playSound("Treasure", 1.2)
	kick(0.5)
end)

local function flyCoins(fromGui, count)
	for i = 1, count do
		local startPos = fromGui.AbsolutePosition + fromGui.AbsoluteSize / 2
		local endPos = coinIcon.AbsolutePosition + coinIcon.AbsoluteSize / 2
		local coin = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(startPos.X + math.random(-60, 60), startPos.Y + math.random(-10, 10)),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = GOLD,
			ZIndex = 10,
			Parent = gui,
		}, { corner(), stroke(2, Color3.fromRGB(150, 95, 20)) })
		task.delay(i * 0.035, function()
			local t = tween(coin, 0.55, { Position = UDim2.fromOffset(endPos.X, endPos.Y), Size = UDim2.fromOffset(12, 12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			t.Completed:Connect(function()
				coin:Destroy()
				pulse(coinScale, 1.1)
			end)
		end)
	end
end

Remotes.Sold.OnClientEvent:Connect(function(amount)
	flyCoins(bagPill, math.clamp(math.floor(amount / 5) + 4, 5, 16))
	playSound("Sell", 1.1)
	task.delay(0.12, playSound, "Sell", 1.4)
	toast("+ 💰 " .. fmt(amount), GOLD)
end)

Remotes.Notify.OnClientEvent:Connect(function(text, color)
	toast(text, color)
end)

Remotes.Announce.OnClientEvent:Connect(function(text, color)
	showBanner(text, color)
end)

Remotes.Reward.OnClientEvent:Connect(function(amount, day, pos)
	popup(pos, "+ 💰 " .. fmt(amount), GOLD, 36, 7, 2)
	sparkle(pos, GOLD, 40, 24)
	flyCoins(bagPill, 12)
	playSound("Treasure", 1)
	toast(if day == 7 then `🔥 Day 7 bonus! Triple reward!` else `🔥 Day {day} streak`, GOLD)
end)

Remotes.Bought.OnClientEvent:Connect(function(kind, tier)
	local list = if kind == "Pick" then CFG.picks else CFG.bags
	local item = list[tier]
	local root = getRoot()
	if root then
		sparkle(root.Position, GOLD, 50, 22)
	end
	playSound("Buy", 1)
	toast(`✨ Equipped {item and item.name or "item"}!`, GREEN)
end)

Remotes.Treasure.OnClientEvent:Connect(function(id, pos, reward, first)
	local T = CFG.treasures[id]
	local template = TreasureModels:FindFirstChild(id)
	if not T then
		return
	end
	local color = rgb(T.color)
	if not first and reward < 25000 then
		-- repeat finds of common treasures stay small so fast diggers aren't spammed
		popup(pos, `🏆 {T.name}  + 💰 {fmt(reward)}`, color:Lerp(WHITE, 0.3), 26, 6, 1.6)
		sparkle(pos, color, 25, 20)
		playSound("Pickup", 0.7)
		return
	end
	playSound("Treasure", 0.8)
	task.delay(0.25, playSound, "Treasure", 1.2)
	kick(0.8)
	sparkle(pos, color, 70, 30)
	sparkle(pos, WHITE, 30, 20)

	if template then
		local model = template:Clone()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
			end
		end
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 18
		light.Brightness = 3
		light.Parent = model.PrimaryPart
		model:PivotTo(CFrame.new(pos))
		model.Parent = workspace
		local start = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > 3.2 or not model.Parent then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local rise = math.min(t / 0.8, 1)
			local shrink = if t > 2.7 then 1 - (t - 2.7) / 0.5 else 1
			model:ScaleTo(math.max(0.05, (0.6 + 0.6 * (1 - (1 - rise) ^ 3)) * shrink))
			model:PivotTo(CFrame.new(pos + Vector3.new(0, 1 + 3.5 * (1 - (1 - rise) ^ 3), 0)) * CFrame.Angles(0, t * 3, 0))
		end)
	end

	revealTop.Text = if first then "🏆 NEW TREASURE!" else "🏆 TREASURE!"
	revealName.Text = T.name
	revealName.TextColor3 = color:Lerp(WHITE, 0.3)
	revealSub.Text = "+ 💰 " .. fmt(reward)
	revealNote.Text = if first then `Museum +1 · ore value +{math.floor(CFG.treasureBonus * 100)}% forever` else ""
	reveal.Visible = true
	revealScale.Scale = 0.3
	tween(revealScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.4, function()
		local t = tween(revealScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			reveal.Visible = false
		end)
	end)
end)

--------------------------------------------------------------------------------
-- LIVING WORLD: spinning displays, shop prices, museum, chest, elevator
--------------------------------------------------------------------------------
local spinning, refreshShops, refreshMuseum, refreshStations
do
	spinning = {}
	local function addSpin(model)
		if model:IsA("Model") then
			spinning[model] = { pivot = model:GetPivot(), phase = math.random() * 6 }
		end
	end
	for _, m in CollectionService:GetTagged("Spin") do
		addSpin(m)
	end
	CollectionService:GetInstanceAddedSignal("Spin"):Connect(addSpin)
	CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(m)
		spinning[m] = nil
	end)

	local function refreshShopItem(p)
		if not p:IsA("ProximityPrompt") then
			return
		end
		local kind, tier = p:GetAttribute("Kind"), p:GetAttribute("Tier")
		local list = if kind == "Pick" then CFG.picks else CFG.bags
		local item = list[tier]
		if not item then
			return
		end
		local owned = if kind == "Pick" then attr("Pick", 1) else attr("Pack", 1)
		local coins = attr("Coins", 0)
		local info = p.Parent and p.Parent:FindFirstChild("Info")
		local priceLabel = info and info:FindFirstChild("Price")
		if tier <= owned then
			p.Enabled = false
			if priceLabel then
				priceLabel.Text = if tier == owned then "✔ EQUIPPED" else "OWNED"
				priceLabel.TextColor3 = if tier == owned then GREEN else Color3.fromRGB(170, 170, 180)
			end
		else
			p.Enabled = true
			p.ActionText = "Buy · " .. fmt(item.price)
			if priceLabel then
				priceLabel.Text = "💰 " .. fmt(item.price)
				priceLabel.TextColor3 = if coins >= item.price then GREEN else Color3.fromRGB(255, 140, 120)
			end
		end
	end

	refreshShops = function()
		for _, p in CollectionService:GetTagged("ShopItem") do
			refreshShopItem(p)
		end
	end
	CollectionService:GetInstanceAddedSignal("ShopItem"):Connect(refreshShopItem)

	local originals = {}
	local function setSilhouette(model, hidden)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				if not originals[p] then
					originals[p] = { color = p.Color, material = p.Material }
				end
				local o = originals[p]
				p.Color = if hidden then Color3.fromRGB(14, 14, 20) else o.color
				p.Material = if hidden then Enum.Material.SmoothPlastic else o.material
			elseif p:IsA("Light") then
				p.Enabled = not hidden
			end
		end
	end

	refreshMuseum = function()
		local owned = ownedTreasures()
		local found = 0
		for _, id in CFG.treasureOrder do
			if owned[id] then
				found += 1
			end
		end
		for _, model in CollectionService:GetTagged("MuseumDisplay") do
			local id = model:GetAttribute("Treasure")
			if id then
				setSilhouette(model, owned[id] == nil)
			end
		end
		for _, base in CollectionService:GetTagged("MuseumItem") do
			local id = base:GetAttribute("Treasure")
			local T = id and CFG.treasures[id]
			local info = base:FindFirstChild("Info")
			if T and info then
				local title, sub = info:FindFirstChild("Title"), info:FindFirstChild("Sub")
				if title and sub then
					if owned[id] then
						title.Text = T.name
						title.TextColor3 = rgb(T.color):Lerp(WHITE, 0.3)
						sub.Text = `Found ×{owned[id]}`
						sub.TextColor3 = GREEN
					else
						title.Text = "???"
						title.TextColor3 = WHITE
						sub.Text = T.hint
						sub.TextColor3 = Color3.fromRGB(200, 200, 210)
					end
				end
			end
		end
		for _, sign in CollectionService:GetTagged("MuseumSign") do
			local info = sign:FindFirstChild("Info")
			local title = info and info:FindFirstChild("Title")
			local sub = info and info:FindFirstChild("Sub")
			if title and sub then
				title.Text = `{found} / {#CFG.treasureOrder} treasures found`
				sub.Text = if found > 0
					then `Your bonus: +{math.floor(found * CFG.treasureBonus * 100 + 0.5)}% ore value`
					else `Each new treasure: +{math.floor(CFG.treasureBonus * 100)}% ore value forever`
			end
		end
	end
	for _, tag in { "MuseumDisplay", "MuseumItem", "MuseumSign" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function()
			task.defer(refreshMuseum)
		end)
	end
	player:GetAttributeChangedSignal("Treasures"):Connect(refreshMuseum)

	refreshStations = function()
		local now = workspace:GetServerTimeNow()
		local today = math.floor(now / 86400)
		for _, chest in CollectionService:GetTagged("DailyChest") do
			local info = chest:FindFirstChild("Info")
			local sub = info and info:FindFirstChild("Sub")
			if sub then
				local streak = attr("Streak", 0)
				if attr("LastDay", -1) == today then
					sub.Text = "Next chest in " .. clock((today + 1) * 86400 - now)
					sub.TextColor3 = Color3.fromRGB(220, 220, 230)
				else
					local pulseOn = math.floor(now * 2) % 2 == 0
					sub.Text = if streak > 0 and attr("LastDay", -1) == today - 1 then `READY! 🔥 {streak}-day streak` else "READY!"
					sub.TextColor3 = if pulseOn then GOLD else WHITE
				end
			end
		end
		for _, altar in CollectionService:GetTagged("Shrine") do
			local info = altar:FindFirstChild("Info")
			local sub = info and info:FindFirstChild("Sub")
			if sub then
				local asc = attr("Asc", 0)
				if attr("Best", 0) >= CFG.maxDepth then
					sub.Text = `Ready! Start over with x{string.format("%.1f", 1 + (asc + 1) * 0.5)} ore value`
					sub.TextColor3 = if math.floor(now * 2) % 2 == 0 then Color3.fromRGB(215, 175, 255) else WHITE
				else
					sub.Text = (if asc > 0 then `Ascension {asc} · ` else "") .. `Reach bedrock ({CFG.maxDepth}m) to unlock`
					sub.TextColor3 = Color3.fromRGB(220, 220, 230)
				end
			end
		end
		for _, platform in CollectionService:GetTagged("Elevator") do
			local info = platform:FindFirstChild("Info")
			local sub = info and info:FindFirstChild("Sub")
			if sub then
				local best = attr("Best", 0)
				local stop = math.min(math.floor(best / CFG.elevatorStep) * CFG.elevatorStep, CFG.maxDepth - 1)
				if stop >= CFG.elevatorStep then
					sub.Text = `Takes you down to {stop}m`
					sub.TextColor3 = GREEN
				else
					sub.Text = `Dig to {CFG.elevatorStep}m to unlock ({best}m)`
					sub.TextColor3 = Color3.fromRGB(220, 220, 230)
				end
			end
		end
	end
end

for _, name in { "Coins", "Pick", "Pack" } do
	player:GetAttributeChangedSignal(name):Connect(refreshShops)
end

--------------------------------------------------------------------------------
-- TUTORIAL: hints + a guide beam, no windows
--------------------------------------------------------------------------------
local updateTutorial
do
	local guideBeam = Instance.new("Beam")
	guideBeam.Color = ColorSequence.new(GOLD)
	guideBeam.LightEmission = 1
	guideBeam.FaceCamera = true
	guideBeam.Width0 = 0.8
	guideBeam.Width1 = 0.8
	guideBeam.Segments = 20
	guideBeam.Enabled = false
	guideBeam.Parent = workspace.Terrain
	local guideEnd = Instance.new("Attachment")
	guideEnd.Parent = workspace.Terrain


	updateTutorial = function(depth)
		-- The objective banner and arrow trail do the guiding now; this only keeps the
		-- big "bag full" reminder when you're down in the mine.
		local full = attr("Bag", 0) >= attr("BagMax", 20)
		if full and depth > 5 then
			setHint(if isTouch then "Bag full! Tap ⬆ to sell" else "Bag full! Press R or ⬆ to sell")
		else
			setHint("")
		end
		guideBeam.Enabled = false
	end
end


--------------------------------------------------------------------------------
-- CHARACTER
--------------------------------------------------------------------------------
local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	local backpack = player:WaitForChild("Backpack")
	local function equip()
		local tool = backpack:FindFirstChild("Pickaxe")
		if tool and tool:IsA("Tool") and hum.Health > 0 then
			hum:EquipTool(tool)
		end
	end
	backpack.ChildAdded:Connect(function()
		task.defer(equip)
	end)
	equip()
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

--------------------------------------------------------------------------------
-- ATMOSPHERE: darker and tinted the deeper you go
--------------------------------------------------------------------------------
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "DigGrade"
grade.Parent = Lighting
local baseAmbient = Lighting.Ambient
local baseOutdoor = Lighting.OutdoorAmbient
local DEEP_AMBIENT = Color3.fromRGB(34, 32, 42)
local DEEP_OUTDOOR = Color3.fromRGB(14, 14, 20)
local dark = 0
local skyOpen = true
local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Include
skyParams.FilterDescendantsInstances = { mineFolder }
local function checkSky()
	local root = getRoot()
	if not root then
		skyOpen = true
		return
	end
	local hit = workspace:Raycast(root.Position + Vector3.new(0, 2, 0), Vector3.new(0, 600, 0), skyParams)
	skyOpen = hit == nil
end

--------------------------------------------------------------------------------
-- SIMULATOR UI: button stack, shop, pets, spin wheel, codes, hatching, levels
--------------------------------------------------------------------------------
local windowsGui = create("ScreenGui", { Name = "DigWindows", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player.PlayerGui })
local overlayGui = create("ScreenGui", { Name = "DigOverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player.PlayerGui })
local blur = create("BlurEffect", { Size = 0, Parent = Lighting })

local function label(props)
	local l = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = props.color or WHITE,
		TextSize = props.size or 18,
		Text = props.text or "",
		Size = props.sz or UDim2.fromScale(1, 1),
		Position = props.pos or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		TextXAlignment = props.alignX or Enum.TextXAlignment.Center,
		TextWrapped = props.wrap or false,
		RichText = props.rich or false,
		ZIndex = props.z or 1,
		LayoutOrder = props.order or 0,
		Parent = props.parent,
	})
	if props.outline ~= false then
		stroke(props.outline or math.max(1.5, (props.size or 18) / 9), INK).Parent = l
	end
	return l
end

-- Chunky 3D look: a light top, the main colour, then a darker "lip" along the bottom edge.
local function bevel(top, bottom)
	local lip = bottom:Lerp(Color3.new(0, 0, 0), 0.3)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top:Lerp(WHITE, 0.2)),
		ColorSequenceKeypoint.new(0.45, top),
		ColorSequenceKeypoint.new(0.8, bottom),
		ColorSequenceKeypoint.new(0.815, lip),
		ColorSequenceKeypoint.new(1, lip),
	})
end

-- Soft floating bubbles drawn behind a panel's content (the "inside" of windows and cards).
local function decorate(parent, count)
	local deco = create("Frame", {
		Name = "Deco",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 0,
		Parent = parent,
	})
	for _ = 1, count do
		local s = math.random(8, 34)
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), math.random()),
			Size = UDim2.fromOffset(s, s),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.8 + math.random() * 0.12,
			ZIndex = 0,
			Parent = deco,
		}, { corner(), create("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.5 }) })
	end
	return deco
end

-- A chunky, bouncy 3D button: bevelled gradient, glossy top, thick outline.
local function cartoonButton(parent, props)
	local radius = props.radius or UDim.new(0.25, 0)
	local b = create("TextButton", {
		Name = props.name or "Button",
		Size = props.sz,
		Position = props.pos or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.order or 0,
		ZIndex = props.z or 1,
		Parent = parent,
	}, { corner(radius), stroke(props.strokeSize or 3.5, INK) })
	local grad = create("UIGradient", { Color = bevel(props.top, props.bottom), Rotation = 90, Parent = b })
	create("Frame", {
		Name = "Gloss",
		Position = UDim2.new(0, 5, 0, 3),
		Size = UDim2.new(1, -10, 0.34, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		ZIndex = props.z or 1,
		Parent = b,
	}, { corner(radius) })
	local sc = create("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		tween(sc, 0.12, { Scale = 1.07 })
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(sc, 0.08, { Scale = 0.9 })
	end)
	b.MouseButton1Up:Connect(function()
		tween(sc, 0.25, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	if props.text then
		label({ parent = b, text = props.text, size = props.textSize or 20, pos = UDim2.fromScale(0, -0.06), z = (props.z or 1) + 1 })
	end
	if props.onClick then
		b.Activated:Connect(function()
			playSound("Click", 1)
			props.onClick()
		end)
	end
	return b, grad
end

-- Windows ---------------------------------------------------------------------
local openWindow = nil
local windows = {}

local function closeWindows()
	if openWindow then
		local w = openWindow
		openWindow = nil
		local sc = w:FindFirstChildOfClass("UIScale")
		local t = tween(sc, 0.15, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			if openWindow ~= w then
				w.Visible = false
			end
		end)
		tween(blur, 0.2, { Size = 0 })
	end
end

local function makeWindow(key, title, top, bottom)
	local w = create("Frame", {
		Name = key,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.new(0.62, 0, 0.68, 0),
		BackgroundColor3 = WHITE,
		Visible = false,
		Parent = windowsGui,
	}, {
		corner(UDim.new(0, 16)),
		stroke(5, INK),
		create("UISizeConstraint", { MaxSize = Vector2.new(800, 560), MinSize = Vector2.new(330, 320) }),
		create("UIScale", {}),
	})
	gradient(w, Color3.fromRGB(84, 158, 250), Color3.fromRGB(42, 86, 196))
	decorate(w, 22)
	-- Big bevelled header bar, a tilted icon and a red square close button (like the top sims)
	local header = create("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(-6, -10),
		Size = UDim2.new(1, 12, 0, 72),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = w,
	}, { corner(UDim.new(0, 12)), stroke(5, INK) })
	create("UIGradient", { Color = bevel(top, bottom), Rotation = 90, Parent = header })
	create("Frame", { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 22), BackgroundColor3 = WHITE, BackgroundTransparency = 0.7, ZIndex = 2, Parent = header }, { corner(UDim.new(0, 8)) })
	local icon, text = string.match(title, "^(%S+)%s+(.+)$")
	local iconLabel = label({ parent = header, text = icon or "", size = 50, outline = false, sz = UDim2.fromOffset(70, 70), pos = UDim2.new(0, 8, 0.5, -6), anchor = Vector2.new(0, 0.5), z = 3 })
	iconLabel.Rotation = -10
	label({ parent = header, text = text or title, size = 40, alignX = Enum.TextXAlignment.Left, sz = UDim2.new(1, -170, 1, -12), pos = UDim2.fromOffset(84, 0), z = 3 })
	cartoonButton(header, {
		name = "Close",
		sz = UDim2.fromOffset(58, 58),
		anchor = Vector2.new(1, 0.5),
		pos = UDim2.new(1, -10, 0.5, -4),
		top = Color3.fromRGB(255, 96, 84),
		bottom = Color3.fromRGB(214, 30, 40),
		radius = UDim.new(0.18, 0),
		text = "X",
		textSize = 38,
		z = 3,
		onClick = closeWindows,
	})
	local body = create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(18, 76),
		Size = UDim2.new(1, -36, 1, -92),
		BackgroundTransparency = 1,
		Parent = w,
	})
	windows[key] = w
	return w, body
end

local function openWindowByKey(key)
	local w = windows[key]
	if not w then
		return
	end
	if openWindow == w then
		closeWindows()
		return
	end
	if openWindow then
		openWindow.Visible = false
	end
	openWindow = w
	w.Visible = true
	local sc = w:FindFirstChildOfClass("UIScale")
	sc.Scale = 0.5
	tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(blur, 0.2, { Size = 14 })
	playSound("Pop", 1.1)
	if w:GetAttribute("OnOpen") then
		task.defer(function()
			local fn = windows[key .. "_open"]
			if fn then
				fn()
			end
		end)
	end
end

-- Purchases -------------------------------------------------------------------
local function buy(kind, item)
	if item.id and item.id ~= 0 then
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.id)
		else
			MarketplaceService:PromptProductPurchase(player, item.id)
		end
	elseif RunService:IsStudio() then
		Remotes.Action:FireServer("DevGrant", kind, item.key)
	else
		toast("Coming soon!", Color3.fromRGB(220, 220, 230))
	end
end

-- Confetti --------------------------------------------------------------------
local function confetti(count)
	local colors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 220, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(200, 120, 255) }
	for _ = 1, count do
		local piece = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.random(), 0, -0.05, 0),
			Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = colors[math.random(1, #colors)],
			ZIndex = 50,
			Parent = overlayGui,
		}, { corner(UDim.new(0, 3)) })
		local t = tween(piece, math.random(18, 30) / 10, { Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.3, 0, 1.1, 0), Rotation = piece.Rotation + math.random(-540, 540) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			piece:Destroy()
		end)
	end
end

-- Left button stack -----------------------------------------------------------
local stack = create("Frame", {
	Name = "Stack",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(160, 380),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIGridLayout", { CellSize = UDim2.fromOffset(72, 72), CellPadding = UDim2.fromOffset(10, 22), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local stackButtons = {}
local function stackButton(order, key, icon, text, top, bottom)
	local b = cartoonButton(stack, { name = key, order = order, top = top, bottom = bottom, onClick = function()
		openWindowByKey(key)
	end })
	label({ parent = b, text = icon, size = 34, outline = false, z = 2 })
	label({ parent = b, text = text, size = 15, pos = UDim2.new(0.5, 0, 1, 2), anchor = Vector2.new(0.5, 0), sz = UDim2.new(1.4, 0, 0, 18), z = 3 })
	local badge = create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.fromRGB(255, 60, 60),
		Visible = false,
		ZIndex = 4,
		Parent = b,
	}, { corner(), stroke(2.5, INK) })
	label({ parent = badge, text = "!", size = 16, z = 5 })
	stackButtons[key] = b
	return b
end
stackButton(1, "Shop", "🛒", "SHOP", Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 150, 30))
stackButton(2, "Pets", "🐾", "PETS", Color3.fromRGB(255, 150, 200), Color3.fromRGB(230, 70, 140))
stackButton(3, "Spin", "🎡", "SPIN", Color3.fromRGB(120, 200, 255), Color3.fromRGB(50, 110, 230))
stackButton(4, "Codes", "🎟️", "CODES", Color3.fromRGB(200, 150, 255), Color3.fromRGB(130, 70, 220))
local offerButton = stackButton(5, "Offer", "🎁", "OFFER!", Color3.fromRGB(255, 130, 110), Color3.fromRGB(230, 40, 80))
stackButton(6, "Quests", "📜", "QUESTS", Color3.fromRGB(255, 190, 120), Color3.fromRGB(220, 110, 40))
stackButton(7, "Settings", "⚙️", "SETTINGS", Color3.fromRGB(220, 224, 235), Color3.fromRGB(140, 146, 165))

-- Level bar under the coins ------------------------------------------------------
local levelRow = create("Frame", {
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 14, 0, 122),
	Size = UDim2.fromOffset(230, 20),
	BackgroundColor3 = Color3.fromRGB(40, 30, 70),
	Parent = gui,
}, { corner(), stroke(3, INK) })
local levelFill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = levelRow }, { corner() })
gradient(levelFill, Color3.fromRGB(130, 220, 255), Color3.fromRGB(60, 140, 255))
local levelText = label({ parent = levelRow, text = "Lv 1", size = 15, z = 2 })

-- Potion timers ----------------------------------------------------------------
local potionRow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.fromOffset(420, 30),
	BackgroundTransparency = 1,
	Parent = gui,
}, { create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }) })
local POTIONS = { { key = "Coins", icon = "🧪", name = "2x Coins", color = Color3.fromRGB(255, 170, 60) }, { key = "Luck", icon = "🍀", name = "Luck", color = Color3.fromRGB(90, 210, 130) }, { key = "Speed", icon = "⚡", name = "Speed", color = Color3.fromRGB(170, 120, 255) } }
local potionPills = {}
for _, pdef in POTIONS do
	local pill = create("Frame", { Size = UDim2.fromOffset(112, 28), BackgroundColor3 = pdef.color, Visible = false, Parent = potionRow }, { corner(), stroke(3, INK) })
	potionPills[pdef.key] = label({ parent = pill, text = "", size = 15, z = 2 })
end

-- Right-side action buttons (Sell Anywhere, Auto Mine) ---------------------------
local sellButton = cartoonButton(gui, {
	name = "SellAnywhere",
	sz = UDim2.fromOffset(84, 60),
	anchor = Vector2.new(1, 1),
	pos = if isTouch then UDim2.new(1, -124, 1, -190) else UDim2.new(1, -124, 1, -24),
	top = Color3.fromRGB(255, 226, 92),
	bottom = Color3.fromRGB(255, 150, 30),
	text = "💰 SELL",
	textSize = 20,
	onClick = function()
		Remotes.Action:FireServer("Sell")
	end,
})
sellButton.Visible = false
local autoButton, autoGrad = cartoonButton(gui, {
	name = "AutoMine",
	sz = UDim2.fromOffset(84, 60),
	anchor = Vector2.new(1, 1),
	pos = if isTouch then UDim2.new(1, -218, 1, -190) else UDim2.new(1, -218, 1, -24),
	top = Color3.fromRGB(200, 200, 210),
	bottom = Color3.fromRGB(130, 130, 145),
	text = "🤖 AUTO",
	textSize = 20,
})
autoButton.Visible = false
autoButton.Activated:Connect(function()
	autoMine = not autoMine
	autoGrad.Color = if autoMine
		then bevel(Color3.fromRGB(120, 235, 120), Color3.fromRGB(40, 170, 70))
		else bevel(Color3.fromRGB(200, 200, 210), Color3.fromRGB(130, 130, 145))
	toast(if autoMine then "🤖 Auto Mine ON" else "Auto Mine OFF", if autoMine then GREEN else WHITE)
end)

-- SHOP window -------------------------------------------------------------------
-- Wide, colourful offer cards with a spinning 3D model of each item (like the big sims).
local buildPet, animatePet
-- its own function so its many locals don't count against the script's 200-register limit
;(function()
	local _, body = makeWindow("Shop", "🛒 SHOP", Color3.fromRGB(255, 226, 70), Color3.fromRGB(255, 168, 20))
	local tabs = create("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = body }, {
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	local scroll = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 12) }),
	})

	local function c3(r, g, b)
		return Color3.fromRGB(r, g, b)
	end
	local CARD_COLORS = {
		VIP = { c3(255, 214, 60), c3(232, 112, 20) },
		DoubleCoins = { c3(130, 232, 90), c3(24, 150, 56) },
		AutoMine = { c3(120, 196, 255), c3(40, 86, 214) },
		SellAnywhere = { c3(255, 176, 70), c3(222, 84, 30) },
		Lucky = { c3(150, 240, 110), c3(30, 160, 80) },
		FastMine = { c3(196, 146, 255), c3(108, 56, 214) },
		InfiniteBag = { c3(255, 128, 204), c3(196, 36, 136) },
		MorePets = { c3(255, 156, 184), c3(224, 64, 110) },
		Starter = { c3(255, 96, 90), c3(176, 18, 40) },
		CoinsS = { c3(255, 226, 96), c3(226, 146, 20) },
		CoinsM = { c3(255, 206, 70), c3(214, 110, 16) },
		CoinsL = { c3(255, 186, 60), c3(196, 76, 14) },
		PotionCoins = { c3(255, 186, 76), c3(218, 104, 20) },
		PotionLuck = { c3(130, 232, 110), c3(26, 146, 60) },
		PotionSpeed = { c3(176, 136, 255), c3(96, 48, 206) },
		NextPick = { c3(124, 206, 255), c3(38, 98, 208) },
	}
	local TAGS = { Starter = "ONE TIME!", VIP = "POPULAR", CoinsL = "BEST VALUE", InfiniteBag = "🔥 HOT" }
	local DESC_COLORS = { Starter = c3(255, 236, 90), VIP = c3(255, 255, 255) }

	-- Tiny part-built models for the 3D previews ------------------------------------
	local function part(m, shape, size, cf, color, material)
		local p = Instance.new("Part")
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
	local GOLD, GOLD_HI = c3(255, 200, 40), c3(255, 232, 120)
	local function coin(m, cf, r)
		part(m, CYL, Vector3.new(0.45, r * 2, r * 2), cf, GOLD)
		part(m, CYL, Vector3.new(0.5, r * 1.45, r * 1.45), cf, GOLD_HI)
	end
	local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis pointing up
	local FACE = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis pointing at the camera
	local function pile(m, n)
		for i = 1, n do
			local a = i * 2.4
			local ring = if i == 1 then 0 else 0.9 + (i % 3) * 0.55
			coin(m, CFrame.new(math.cos(a) * ring, -1.3 + math.floor((i - 1) / 4) * 0.42 + (i % 2) * 0.2, math.sin(a) * ring * 0.6) * FLAT, 0.8)
		end
		coin(m, CFrame.new(0, 0.2 + n * 0.04, -0.4) * FACE * CFrame.Angles(math.rad(12), 0, 0), 1.1)
	end
	local function pickaxe(m, head)
		local tilt = CFrame.Angles(0, 0, math.rad(-35))
		part(m, nil, Vector3.new(0.42, 4.6, 0.42), tilt * CFrame.new(0, -0.4, 0), c3(150, 96, 50))
		part(m, nil, Vector3.new(0.5, 0.7, 0.5), tilt * CFrame.new(0, -2.5, 0), c3(90, 56, 30))
		part(m, nil, Vector3.new(3.6, 0.8, 0.7), tilt * CFrame.new(0, 1.8, 0), head)
		part(m, BALL, Vector3.new(0.9, 0.9, 0.9), tilt * CFrame.new(-1.8, 1.6, 0), head:Lerp(WHITE, 0.3))
		part(m, BALL, Vector3.new(0.9, 0.9, 0.9), tilt * CFrame.new(1.8, 1.6, 0), head:Lerp(WHITE, 0.3))
	end
	local function potion(m, color)
		part(m, BALL, Vector3.new(2.8, 2.8, 2.8), CFrame.new(0, -0.6, 0), color)
		part(m, BALL, Vector3.new(0.7, 0.7, 0.7), CFrame.new(-0.6, -0.1, -1.05), WHITE)
		part(m, CYL, Vector3.new(1.1, 0.9, 0.9), CFrame.new(0, 1.1, 0) * FLAT, color:Lerp(WHITE, 0.45))
		part(m, CYL, Vector3.new(0.6, 1.05, 1.05), CFrame.new(0, 1.75, 0) * FLAT, c3(170, 110, 60))
	end
	local function clover(m)
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			part(m, BALL, Vector3.new(1.7, 1.7, 0.7), CFrame.new(math.cos(a) * 0.8, 0.4 + math.sin(a) * 0.8, 0), c3(70, 200, 80))
		end
		part(m, nil, Vector3.new(0.3, 1.8, 0.3), CFrame.new(0.3, -1.2, 0) * CFrame.Angles(0, 0, math.rad(-15)), c3(60, 150, 60))
	end
	local function bolt(m)
		local yellow = c3(255, 226, 60)
		part(m, nil, Vector3.new(0.8, 2.2, 0.6), CFrame.new(0.3, 1, 0) * CFrame.Angles(0, 0, math.rad(-25)), yellow)
		part(m, nil, Vector3.new(1.8, 0.6, 0.6), CFrame.new(0, 0, 0), yellow)
		part(m, nil, Vector3.new(0.8, 2.2, 0.6), CFrame.new(-0.3, -1, 0) * CFrame.Angles(0, 0, math.rad(-25)), yellow)
	end
	local function crown(m)
		part(m, CYL, Vector3.new(1.3, 3.4, 3.4), CFrame.new(0, -0.6, 0) * FLAT, GOLD)
		for i = 0, 4 do
			local a = i * math.pi * 2 / 5
			local pos = Vector3.new(math.cos(a) * 1.35, 0.5, math.sin(a) * 1.35)
			part(m, nil, Vector3.new(0.55, 1.4, 0.55), CFrame.new(pos) * CFrame.Angles(0, -a, 0), GOLD)
			part(m, BALL, Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos + Vector3.new(0, 0.85, 0)), GOLD_HI)
		end
		part(m, BALL, Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, -0.5, -1.65), c3(240, 40, 60))
	end
	local function robot(m)
		local grey = c3(190, 196, 210)
		part(m, nil, Vector3.new(2.8, 2.2, 2.2), CFrame.new(0, 0, 0), grey)
		part(m, nil, Vector3.new(2.2, 1.2, 0.2), CFrame.new(0, 0.1, -1.1), c3(40, 50, 70))
		part(m, BALL, Vector3.new(0.55, 0.55, 0.55), CFrame.new(-0.5, 0.1, -1.2), c3(80, 240, 255), Enum.Material.Neon)
		part(m, BALL, Vector3.new(0.55, 0.55, 0.55), CFrame.new(0.5, 0.1, -1.2), c3(80, 240, 255), Enum.Material.Neon)
		part(m, nil, Vector3.new(0.2, 0.9, 0.2), CFrame.new(0, 1.5, 0), grey)
		part(m, BALL, Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 2.05, 0), c3(255, 70, 70))
		part(m, CYL, Vector3.new(0.3, 0.9, 0.9), CFrame.new(-1.5, 0, 0), c3(255, 170, 40))
		part(m, CYL, Vector3.new(0.3, 0.9, 0.9), CFrame.new(1.5, 0, 0), c3(255, 170, 40))
	end
	local function moneyBag(m)
		local sack = c3(214, 176, 110)
		part(m, BALL, Vector3.new(3, 2.8, 3), CFrame.new(0, -0.6, 0), sack)
		part(m, CYL, Vector3.new(0.6, 1.1, 1.1), CFrame.new(0, 0.9, 0) * FLAT, sack:Lerp(Color3.new(0, 0, 0), 0.15))
		part(m, BALL, Vector3.new(1.3, 0.8, 1.3), CFrame.new(0, 1.35, 0), sack)
		coin(m, CFrame.new(0.2, -0.5, -1.45) * FACE, 0.75)
	end
	local function backpack(m)
		local pink = c3(255, 110, 190)
		part(m, nil, Vector3.new(2.6, 3, 1.6), CFrame.new(0, 0, 0), pink)
		part(m, BALL, Vector3.new(2.6, 1.2, 1.6), CFrame.new(0, 1.5, 0), pink)
		part(m, nil, Vector3.new(1.8, 1.2, 0.5), CFrame.new(0, -0.6, -0.9), pink:Lerp(WHITE, 0.3))
		part(m, nil, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, -0.1, -1.2), GOLD)
		part(m, nil, Vector3.new(0.35, 2.6, 0.2), CFrame.new(-0.8, 0.2, 0.85), pink:Lerp(Color3.new(0, 0, 0), 0.3))
		part(m, nil, Vector3.new(0.35, 2.6, 0.2), CFrame.new(0.8, 0.2, 0.85), pink:Lerp(Color3.new(0, 0, 0), 0.3))
	end
	local function gift(m)
		local red = c3(235, 50, 60)
		part(m, nil, Vector3.new(2.6, 2.2, 2.6), CFrame.new(0, -0.7, 0), red)
		part(m, nil, Vector3.new(2.9, 0.6, 2.9), CFrame.new(0, 0.55, 0), red:Lerp(WHITE, 0.1))
		part(m, nil, Vector3.new(0.6, 2.95, 2.95), CFrame.new(0, -0.3, 0), GOLD)
		part(m, nil, Vector3.new(2.95, 2.95, 0.6), CFrame.new(0, -0.3, 0), GOLD)
		part(m, BALL, Vector3.new(1, 0.8, 1), CFrame.new(-0.45, 1.15, 0), GOLD_HI)
		part(m, BALL, Vector3.new(1, 0.8, 1), CFrame.new(0.45, 1.15, 0), GOLD_HI)
	end
	local function petModel(m, id, offset)
		if not buildPet then
			return
		end
		local pet = buildPet(id)
		pet:PivotTo(CFrame.new(offset) * CFrame.Angles(0, math.rad(200), 0))
		for _, d in pet:GetDescendants() do
			if d:IsA("Light") or d:IsA("Sparkles") then
				d:Destroy()
			end
		end
		pet.Parent = m
	end
	local MODELS = {
		VIP = crown,
		DoubleCoins = function(m)
			pile(m, 8)
		end,
		AutoMine = robot,
		SellAnywhere = moneyBag,
		Lucky = clover,
		FastMine = bolt,
		InfiniteBag = backpack,
		MorePets = function(m)
			petModel(m, "Bunny", Vector3.new(-1.1, 0, 0.3))
			petModel(m, "PebblePup", Vector3.new(1.1, 0, -0.3))
		end,
		Starter = function(m)
			gift(m)
			petModel(m, "StarterPup", Vector3.new(0, 2.1, -0.4))
		end,
		CoinsS = function(m)
			pile(m, 4)
		end,
		CoinsM = function(m)
			pile(m, 9)
		end,
		CoinsL = function(m)
			pile(m, 16)
		end,
		PotionCoins = function(m)
			potion(m, c3(255, 170, 40))
		end,
		PotionLuck = function(m)
			potion(m, c3(80, 210, 90))
		end,
		PotionSpeed = function(m)
			potion(m, c3(160, 110, 255))
		end,
		NextPick = function(m)
			pickaxe(m, c3(90, 220, 255))
		end,
	}
	-- Fits the camera to the model using part positions (rough, but no engine bounds needed)
	local function fillViewport(vp, key)
		local m = Instance.new("Model")
		local builder = MODELS[key]
		if builder then
			builder(m)
		end
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local half = Vector3.one * (math.max(p.Size.X, p.Size.Y, p.Size.Z) / 2)
				lo = lo:Min(p.CFrame.Position - half)
				hi = hi:Max(p.CFrame.Position + half)
			end
		end
		local centre, extent = Vector3.zero, 4
		if lo.X < hi.X then
			centre = (lo + hi) / 2
			extent = (hi - lo).Magnitude
		end
		m.WorldPivot = CFrame.new(centre)
		m.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 38
		cam.CFrame = CFrame.lookAt(centre + Vector3.new(0, extent * 0.3, -extent * 1.35), centre)
		cam.Parent = vp
		vp.CurrentCamera = cam
		return m, centre
	end

	local cards = {}
	local function card(kind, item, order, tab)
		local cols = CARD_COLORS[item.key] or { c3(120, 200, 255), c3(50, 110, 230) }
		local featured = item.starter or item.key == "VIP"
		local c = create("Frame", {
			Name = item.key,
			LayoutOrder = order,
			Size = UDim2.new(1, -6, 0, if featured then 164 else 138),
			BackgroundColor3 = WHITE,
			Parent = scroll,
		}, { corner(UDim.new(0, 14)), stroke(4, INK) })
		gradient(c, cols[1], cols[2], 90)
		decorate(c, 14)
		create("Frame", { Name = "Rim", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, Parent = c }, {
			corner(UDim.new(0, 11)),
			create("UIStroke", { Color = WHITE, Thickness = 2.5, Transparency = 0.35 }),
		})
		local vp = create("ViewportFrame", {
			Name = "Preview",
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(0, 150, 1, -8),
			BackgroundTransparency = 1,
			Ambient = c3(175, 175, 185),
			LightColor = WHITE,
			LightDirection = Vector3.new(-0.6, -1, 0.8),
			ZIndex = 2,
			Parent = c,
		})
		local titleLabel = label({ parent = c, text = item.name, size = if featured then 42 else 34, color = if featured then c3(255, 214, 40) else WHITE, alignX = Enum.TextXAlignment.Right, sz = UDim2.new(1, -180, 0, 46), pos = UDim2.fromOffset(160, 8), z = 3 })
		titleLabel.TextScaled = true
		create("UITextSizeConstraint", { MaxTextSize = if featured then 42 else 34, Parent = titleLabel })
		local desc = label({ parent = c, text = item.desc or "", size = 19, color = DESC_COLORS[item.key] or c3(255, 246, 170), alignX = Enum.TextXAlignment.Right, wrap = true, sz = UDim2.new(1, -180, 0, 44), pos = UDim2.fromOffset(160, 54), z = 3 })
		local btn, bgrad = cartoonButton(c, {
			sz = UDim2.fromOffset(186, 50),
			anchor = Vector2.new(1, 1),
			pos = UDim2.new(1, -14, 1, -12),
			top = c3(140, 244, 90),
			bottom = c3(36, 176, 50),
			radius = UDim.new(0.2, 0),
			z = 3,
			onClick = function()
				buy(kind, item)
			end,
		})
		-- Robux icon: a white rounded "hexagon" with a square hole
		local robux = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 30, 0.44, 0), Size = UDim2.fromOffset(26, 26), Rotation = 45, BackgroundColor3 = WHITE, ZIndex = 4, Parent = btn }, {
			corner(UDim.new(0.3, 0)),
			stroke(2, INK),
		})
		create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = c3(60, 190, 70), ZIndex = 5, Parent = robux }, { corner(UDim.new(0.2, 0)) })
		local priceLabel = label({ parent = btn, text = tostring(item.price), size = 28, sz = UDim2.new(1, -52, 1, -6), pos = UDim2.fromOffset(48, 0), z = 4 })
		if TAGS[item.key] then
			local tag = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(62, 10), Size = UDim2.fromOffset(118, 30), Rotation = -8, BackgroundColor3 = c3(255, 56, 70), ZIndex = 5, Parent = c }, {
				corner(UDim.new(0.3, 0)),
				stroke(3, INK),
			})
			label({ parent = tag, text = TAGS[item.key], size = 17, z = 6 })
		end
		table.insert(cards, { frame = c, kind = kind, item = item, tab = tab, price = priceLabel, button = btn, grad = bgrad, robux = robux, desc = desc, vp = vp })
	end
	for i, pass in CFG.passes do
		card("Pass", pass, if pass.key == "VIP" then 0 else i, "Passes")
	end
	for i, product in CFG.products do
		card("Product", product, i, if product.coinMinutes then "Coins" else "Boosts")
	end

	local current = "Passes"
	local tabButtons = {}
	local spinners = {}
	local function refresh()
		for _, c in cards do
			local show = c.tab == current
			c.frame.Visible = show
			-- models are built the first time their tab is seen, so opening the shop stays fast
			if show and not c.model and windows.Shop.Visible then
				c.model, c.centre = fillViewport(c.vp, c.item.key)
				table.insert(spinners, c)
			end
			local owned = c.kind == "Pass" and attr("Pass_" .. c.item.key, false)
			if owned then
				c.price.Text = "OWNED ✔"
				c.button.Active = false
			else
				c.price.Text = if c.item.id == 0 and not RunService:IsStudio() then "Soon" else tostring(c.item.price)
			end
			c.robux.Visible = not owned and c.price.Text ~= "Soon"
			c.price.Position = UDim2.fromOffset(if c.robux.Visible then 48 else 26, 0)
			c.grad.Color = if owned then bevel(c3(200, 204, 215), c3(140, 146, 165)) else bevel(c3(140, 244, 90), c3(36, 176, 50))
			if c.item.coinMinutes then
				local income = CFG.income[attr("Pick", 1)] or CFG.income[1]
				c.desc.Text = "+ 💰 " .. fmt(income * c.item.coinMinutes * (1 + attr("Asc", 0) * CFG.ascendBonus)) .. " coins"
			elseif c.item.key == "NextPick" then
				local nextPick = CFG.picks[attr("Pick", 1) + 1]
				c.desc.Text = if nextPick then "Get the " .. nextPick.name .. " right now!" else "You have the best pickaxe!"
			elseif c.item.potion then
				c.desc.Text = `{c.item.minutes} minutes. Stacks up to 3 hours`
			end
		end
		for key, b in tabButtons do
			b.grad.Color = if key == current then bevel(c3(130, 240, 80), c3(30, 170, 50)) else bevel(c3(255, 226, 70), c3(255, 168, 20))
			b.button.Size = if key == current then UDim2.fromOffset(156, 48) else UDim2.fromOffset(146, 44)
		end
	end
	for i, t in { { "Passes", "⭐ Passes" }, { "Boosts", "🧪 Boosts" }, { "Coins", "💰 Coins" } } do
		local b, g = cartoonButton(tabs, {
			sz = UDim2.fromOffset(146, 44),
			order = i,
			top = c3(255, 226, 70),
			bottom = c3(255, 168, 20),
			radius = UDim.new(0.16, 0),
			text = t[2],
			textSize = 24,
			onClick = function()
				current = t[1]
				refresh()
			end,
		})
		tabButtons[t[1]] = { button = b, grad = g }
	end
	-- Slowly turn the 3D previews while the shop is open
	RunService.RenderStepped:Connect(function()
		local w = windows.Shop
		if not (w and w.Visible) then
			return
		end
		local t = os.clock()
		for _, c in spinners do
			if c.frame.Visible then
				c.model:PivotTo(CFrame.new(c.centre + Vector3.new(0, math.sin(t * 2) * 0.12, 0)) * CFrame.Angles(0, math.sin(t * 0.9) * 0.6, 0))
			end
		end
	end)
	windows.Shop_open = refresh
	windows.Shop:SetAttribute("OnOpen", true)
	for _, name in { "Pick", "Asc", "Starter" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	for _, pass in CFG.passes do
		player:GetAttributeChangedSignal("Pass_" .. pass.key):Connect(refresh)
	end
	refresh()
	-- the Offer button jumps straight to the starter pack
	stackButtons.Offer.Activated:Connect(function()
		current = "Boosts"
		refresh()
		if openWindow ~= windows.Shop then
			openWindowByKey("Shop")
		end
	end)
end)()
windows.Offer = nil

do
	-- PET MODELS (used by the pets that follow players and by the hatch reveal) -------
	local function petPart(model, size, cf, color, mat, shape)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end

	-- Hand-built pet models. Every pet faces -Z, sits on its feet at about y = -1.2 and is
	-- made of glossy ellipsoids (Part + SpecialMesh sphere) so the shapes read as soft and cute.
	-- buildPet returns the model plus a list of animated parts (wings flap, tails wag...).
	local DARK = Color3.fromRGB(26, 22, 34)
	local PINK = Color3.fromRGB(255, 150, 175)

	local function blob(m, size, cf, color, mat, transparency)
		local p = petPart(m, size, cf, color, mat)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		if transparency then
			p.Transparency = transparency
		end
		return p
	end

	local function wedge(m, size, cf, color, mat)
		local p = Instance.new("WedgePart")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Parent = m
		return p
	end

	-- Big glossy chibi eyes, blush and a little "w" mouth, centred on `at` (facing -Z).
	local function face(m, at, scale, blush)
		for _, x in { -1, 1 } do
			local eye = at * CFrame.new(x * 0.36 * scale, 0.08 * scale, 0)
			blob(m, Vector3.new(0.44, 0.58, 0.2) * scale, eye, DARK)
			petPart(m, Vector3.new(0.16, 0.16, 0.1) * scale, eye * CFrame.new(x * -0.06 * scale, 0.13 * scale, -0.08 * scale), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
			petPart(m, Vector3.new(0.08, 0.08, 0.1) * scale, eye * CFrame.new(x * 0.07 * scale, -0.1 * scale, -0.08 * scale), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
			blob(m, Vector3.new(0.32, 0.16, 0.08) * scale, at * CFrame.new(x * 0.62 * scale, -0.24 * scale, 0.05 * scale), blush or PINK, nil, 0.2)
			petPart(m, Vector3.new(0.15, 0.05, 0.05) * scale, at * CFrame.new(x * 0.065 * scale, -0.3 * scale, -0.02) * CFrame.Angles(0, 0, x * 0.55), DARK)
		end
	end

	local function lighter(c, k)
		return c:Lerp(WHITE, k or 0.45)
	end

	local function darker(c, k)
		return c:Lerp(Color3.new(0, 0, 0), k or 0.25)
	end

	local BUILDERS = {}

	-- Chubby four-legged critter: moles, pups
	function BUILDERS.critter(m, P, c, acc, anims)
		local mat = if P.variant == "mole" and P.glow then Enum.Material.Foil else Enum.Material.SmoothPlastic
		blob(m, Vector3.new(2, 1.7, 2.3), CFrame.new(0, -0.35, 0.35), c, mat)
		blob(m, Vector3.new(1.3, 1.1, 0.5), CFrame.new(0, -0.45, -0.72), lighter(c), mat)
		blob(m, Vector3.new(2.1, 1.9, 1.9), CFrame.new(0, 0.55, -0.45), c, mat)
		blob(m, Vector3.new(0.95, 0.62, 0.55), CFrame.new(0, 0.28, -1.33), lighter(c, 0.55), mat)
		blob(m, Vector3.new(0.34, 0.26, 0.22), CFrame.new(0, 0.44, -1.58), if P.variant == "mole" then PINK else DARK)
		face(m, CFrame.new(0, 0.78, -1.33), 0.95)
		for _, x in { -0.62, 0.62 } do
			for _, z in { -0.35, 0.95 } do
				blob(m, Vector3.new(0.58, 0.42, 0.72), CFrame.new(x, -1.12, z), if P.variant == "mole" and z < 0 then PINK else darker(c, 0.15), mat)
			end
		end
		if P.variant == "dog" or P.variant == "starter" then
			for _, x in { -1, 1 } do
				blob(m, Vector3.new(0.5, 1.1, 0.32), CFrame.new(x * 1.0, 0.55, -0.35) * CFrame.Angles(0, 0, x * 0.3), darker(c, 0.2))
			end
			for _, spot in { Vector3.new(0.7, 0.1, 0.9), Vector3.new(-0.6, -0.2, 0.2) } do
				blob(m, Vector3.new(0.6, 0.5, 0.2), CFrame.new(spot) * CFrame.new(0, 0, 0) * CFrame.lookAt(Vector3.zero, spot), darker(c, 0.18))
			end
		else
			for _, x in { -1, 1 } do
				blob(m, Vector3.new(0.72, 0.72, 0.3), CFrame.new(x * 0.78, 1.42, -0.3), c, mat)
				blob(m, Vector3.new(0.42, 0.42, 0.1), CFrame.new(x * 0.78, 1.42, -0.46), acc)
			end
		end
		if P.variant == "starter" then
			wedge(m, Vector3.new(1.9, 0.7, 0.9), CFrame.new(0, -0.3, -0.95) * CFrame.Angles(0, math.pi, math.pi), acc)
			blob(m, Vector3.new(0.45, 0.35, 0.3), CFrame.new(0, -0.35, -1.4), GOLD, Enum.Material.Foil)
		end
		local tail = blob(m, Vector3.new(0.36, 0.36, 0.95), CFrame.new(0, -0.05, 1.55) * CFrame.Angles(-0.7, 0, 0), darker(c, 0.1), mat)
		table.insert(anims, { part = tail, kind = "wag", hinge = Vector3.new(0, -0.3, 1.15) })
	end

	function BUILDERS.bunny(m, P, c, acc, anims)
		blob(m, Vector3.new(1.9, 1.8, 2), CFrame.new(0, -0.4, 0.3), c)
		blob(m, Vector3.new(1.2, 1.1, 0.4), CFrame.new(0, -0.45, -0.65), lighter(c, 0.6))
		blob(m, Vector3.new(1.9, 1.75, 1.75), CFrame.new(0, 0.6, -0.4), c)
		face(m, CFrame.new(0, 0.62, -1.25), 0.95)
		blob(m, Vector3.new(0.28, 0.2, 0.16), CFrame.new(0, 0.42, -1.3), PINK)
		for _, x in { -0.13, 0.13 } do
			petPart(m, Vector3.new(0.2, 0.26, 0.08), CFrame.new(x, 0.18, -1.2), WHITE)
		end
		for _, x in { -1, 1 } do
			local ear = blob(m, Vector3.new(0.52, 1.7, 0.36), CFrame.new(x * 0.45, 1.95, -0.25) * CFrame.Angles(0, 0, x * -0.18), c)
			local inner = blob(m, Vector3.new(0.3, 1.3, 0.1), CFrame.new(x * 0.45, 1.95, -0.42) * CFrame.Angles(0, 0, x * -0.18), acc)
			table.insert(anims, { part = ear, kind = "ear", hinge = Vector3.new(x * 0.4, 1.2, -0.25), side = x })
			table.insert(anims, { part = inner, kind = "ear", hinge = Vector3.new(x * 0.4, 1.2, -0.25), side = x })
			blob(m, Vector3.new(0.6, 0.4, 0.95), CFrame.new(x * 0.6, -1.15, 0.1), lighter(c, 0.3))
		end
		blob(m, Vector3.new(0.75, 0.75, 0.75), CFrame.new(0, -0.3, 1.35), WHITE)
	end

	function BUILDERS.bat(m, P, c, acc, anims)
		blob(m, Vector3.new(1.9, 1.9, 1.8), CFrame.new(0, 0, 0), c)
		blob(m, Vector3.new(1.1, 1, 0.4), CFrame.new(0, -0.35, -0.72), lighter(c, 0.3))
		face(m, CFrame.new(0, 0.25, -0.86), 0.9, acc)
		for _, x in { -1, 1 } do
			wedge(m, Vector3.new(0.2, 0.9, 0.55), CFrame.new(x * 0.55, 1.1, -0.1) * CFrame.Angles(0, 0, x * -0.35), c)
			wedge(m, Vector3.new(0.1, 0.18, 0.1), CFrame.new(x * 0.12, -0.12, -0.9) * CFrame.Angles(math.pi, 0, 0), WHITE)
			-- three-finger membrane wing
			for k = 0, 2 do
				local part = blob(m, Vector3.new(0.1, 1.1 - k * 0.2, 1.6 - k * 0.25), CFrame.new(x * (1.2 + k * 0.32), 0.3 - k * 0.2, 0.1) * CFrame.Angles(0, 0, x * (-0.5 + k * 0.45)), if k == 1 then acc else darker(c, 0.1))
				table.insert(anims, { part = part, kind = "flap", hinge = Vector3.new(x * 0.8, 0.2, 0.1), side = x })
			end
			blob(m, Vector3.new(0.4, 0.3, 0.4), CFrame.new(x * 0.4, -0.95, 0), darker(c, 0.2))
		end
	end

	function BUILDERS.slime(m, P, c, acc, anims)
		local base = blob(m, Vector3.new(2.6, 1.7, 2.4), CFrame.new(0, -0.45, 0), c, Enum.Material.Glass, 0.18)
		base.Reflectance = 0.15
		local top = blob(m, Vector3.new(1.7, 1.4, 1.6), CFrame.new(0, 0.45, 0.05), c, Enum.Material.Glass, 0.18)
		blob(m, Vector3.new(1.2, 0.9, 1.1), CFrame.new(0, -0.3, 0.1), darker(c, 0.35), nil, 0.35)
		petPart(m, Vector3.new(0.4, 0.4, 0.4), CFrame.new(-0.55, 0.85, -0.45), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
		face(m, CFrame.new(0, 0.05, -1.12), 1, acc)
		for _, part in { base, top } do
			table.insert(anims, { part = part, kind = "squash" })
		end
	end

	function BUILDERS.golem(m, P, c, acc, anims)
		local rock = Enum.Material.Rock
		petPart(m, Vector3.new(2.1, 1.8, 1.6), CFrame.new(0, -0.2, 0.2) * CFrame.Angles(0, 0.05, 0.04), c, rock)
		petPart(m, Vector3.new(1.6, 1.2, 1.3), CFrame.new(0, 1.05, -0.05) * CFrame.Angles(0.05, -0.08, 0), lighter(c, 0.1), rock)
		local core = petPart(m, Vector3.new(0.9, 0.9, 0.5), CFrame.new(0, -0.1, -0.62) * CFrame.Angles(0, 0, math.rad(45)), acc, Enum.Material.Neon)
		for _, x in { -1, 1 } do
			petPart(m, Vector3.new(0.34, 0.16, 0.1), CFrame.new(x * 0.34, 1.12, -0.72), acc, Enum.Material.Neon)
			local arm = petPart(m, Vector3.new(0.7, 1.5, 0.8), CFrame.new(x * 1.45, -0.35, 0.1) * CFrame.Angles(0, 0, x * 0.12), darker(c, 0.1), rock)
			table.insert(anims, { part = arm, kind = "swing", hinge = Vector3.new(x * 1.35, 0.35, 0.1), side = x })
			petPart(m, Vector3.new(0.75, 0.6, 0.8), CFrame.new(x * 0.55, -1.3, 0.2), darker(c, 0.2), rock)
			blob(m, Vector3.new(0.7, 0.25, 0.6), CFrame.new(x * 0.35, 1.68, 0.1), Color3.fromRGB(90, 160, 70), Enum.Material.Grass)
		end
		local light = Instance.new("PointLight")
		light.Color = acc
		light.Range = 8
		light.Parent = core
	end

	-- Fox / cat / lava pup: slimmer body, tall ears and a big fluffy tail
	function BUILDERS.fox(m, P, c, acc, anims)
		local mat = Enum.Material.SmoothPlastic
		local crystal = P.variant == nil
		local body = blob(m, Vector3.new(1.8, 1.5, 2.3), CFrame.new(0, -0.45, 0.4), c, if crystal then Enum.Material.Glass else mat)
		blob(m, Vector3.new(1.1, 1, 0.45), CFrame.new(0, -0.5, -0.62), if P.variant == "cat" then lighter(c, 0.15) else WHITE)
		blob(m, Vector3.new(1.95, 1.75, 1.75), CFrame.new(0, 0.55, -0.4), c, if crystal then Enum.Material.Glass else mat)
		blob(m, Vector3.new(0.8, 0.55, 0.7), CFrame.new(0, 0.25, -1.3), if P.variant == "cat" then lighter(c, 0.2) else WHITE)
		blob(m, Vector3.new(0.26, 0.2, 0.18), CFrame.new(0, 0.42, -1.64), if P.variant == "cat" then PINK else DARK)
		face(m, CFrame.new(0, 0.78, -1.26), 0.9, if P.variant == "cat" then acc else nil)
		for _, x in { -1, 1 } do
			wedge(m, Vector3.new(0.25, 1.05, 0.7), CFrame.new(x * 0.62, 1.62, -0.35) * CFrame.Angles(0, 0, x * -0.28), c)
			wedge(m, Vector3.new(0.1, 0.7, 0.45), CFrame.new(x * 0.62, 1.55, -0.45) * CFrame.Angles(0, 0, x * -0.28), acc)
			for _, z in { -0.3, 1.05 } do
				blob(m, Vector3.new(0.45, 0.5, 0.6), CFrame.new(x * 0.55, -1.15, z), darker(c, 0.1))
			end
			if P.variant == "cat" then
				for k = -1, 1 do
					petPart(m, Vector3.new(0.7, 0.04, 0.04), CFrame.new(x * 0.7, 0.28 + k * 0.1, -1.32) * CFrame.Angles(0, 0, x * k * 0.2), WHITE, Enum.Material.Neon)
				end
			end
		end
		-- fluffy tail: a chain of blobs curling up, with a light tip
		local tailColor = if P.variant == "lava" then acc else c
		local segs = { { Vector3.new(0, -0.15, 1.45), 0.85 }, { Vector3.new(0, 0.2, 1.85), 1.05 }, { Vector3.new(0, 0.62, 2.1), 1.15 }, { Vector3.new(0, 1.05, 2.18), 1.05 }, { Vector3.new(0, 1.45, 2.08), 0.8 }, { Vector3.new(0, 1.75, 1.92), 0.55 } }
		for i, seg in segs do
			local part = blob(m, Vector3.one * seg[2], CFrame.new(seg[1]), if i == #segs then (if P.variant == "cat" then acc else WHITE) else tailColor, if crystal then Enum.Material.Glass else mat)
			table.insert(anims, { part = part, kind = "wag", hinge = Vector3.new(0, -0.3, 1.2) })
		end
		if P.variant == "lava" then
			for k = 0, 2 do
				petPart(m, Vector3.new(0.35, 0.8, 0.35), CFrame.new(0, 0.55 - k * 0.3, 0.1 + k * 0.55) * CFrame.Angles(-0.4, math.rad(45), 0), acc, Enum.Material.Neon)
			end
			local fire = Instance.new("Fire")
			fire.Size = 2
			fire.Heat = 3
			fire.Color = Color3.fromRGB(255, 120, 30)
			fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
			fire.Parent = body
		end
		if crystal then
			for k = 0, 2 do
				petPart(m, Vector3.new(0.3, 0.9 - k * 0.15, 0.3), CFrame.new(0, 0.35 - k * 0.25, 0.3 + k * 0.5) * CFrame.Angles(-0.5, 0, (k - 1) * 0.3), acc, Enum.Material.Glass)
			end
		end
	end

	function BUILDERS.owl(m, P, c, acc, anims)
		blob(m, Vector3.new(2, 2.4, 2), CFrame.new(0, -0.1, 0.1), c)
		blob(m, Vector3.new(1.3, 1.5, 0.5), CFrame.new(0, -0.45, -0.72), lighter(c, 0.5))
		for _, x in { -1, 1 } do
			blob(m, Vector3.new(0.85, 0.85, 0.2), CFrame.new(x * 0.42, 0.55, -0.88), lighter(c, 0.65))
			wedge(m, Vector3.new(0.25, 0.6, 0.45), CFrame.new(x * 0.62, 1.25, -0.25) * CFrame.Angles(0, 0, x * -0.35), darker(c, 0.1))
			local wing = blob(m, Vector3.new(0.45, 1.5, 1.3), CFrame.new(x * 1.02, -0.2, 0.2) * CFrame.Angles(0, 0, x * 0.15), darker(c, 0.15))
			table.insert(anims, { part = wing, kind = "flap", hinge = Vector3.new(x * 0.9, 0.5, 0.2), side = x, amount = 0.35 })
			blob(m, Vector3.new(0.4, 0.2, 0.5), CFrame.new(x * 0.4, -1.3, -0.3), acc)
		end
		face(m, CFrame.new(0, 0.55, -1), 1.05)
		wedge(m, Vector3.new(0.3, 0.35, 0.3), CFrame.new(0, 0.28, -1.08) * CFrame.Angles(math.pi, 0, 0), acc)
		blob(m, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 1.2, 0.3), acc, Enum.Material.Glass)
	end

	function BUILDERS.dragon(m, P, c, acc, anims)
		local mat = if P.variant == "diamond" then Enum.Material.Glass else Enum.Material.SmoothPlastic
		local body = blob(m, Vector3.new(2, 1.8, 2.4), CFrame.new(0, -0.4, 0.4), c, mat)
		body.Reflectance = if P.variant == "diamond" then 0.25 else 0
		blob(m, Vector3.new(1.2, 1.2, 0.5), CFrame.new(0, -0.5, -0.65), lighter(acc, 0.4))
		blob(m, Vector3.new(1.8, 1.6, 1.7), CFrame.new(0, 0.6, -0.5), c, mat)
		blob(m, Vector3.new(1.1, 0.8, 1.1), CFrame.new(0, 0.3, -1.35), c, mat)
		for _, x in { -1, 1 } do
			blob(m, Vector3.new(0.12, 0.08, 0.1), CFrame.new(x * 0.2, 0.45, -1.88), DARK)
			petPart(m, Vector3.new(0.22, 0.75, 0.22), CFrame.new(x * 0.5, 1.45, -0.2) * CFrame.Angles(-0.6, 0, x * -0.25), acc, mat)
			petPart(m, Vector3.new(0.16, 0.5, 0.16), CFrame.new(x * 0.58, 1.72, 0.2) * CFrame.Angles(-1.4, 0, x * -0.25), acc, mat)
			for k = 0, 1 do
				local part = blob(m, Vector3.new(0.1, 1.6 - k * 0.4, 1.9 - k * 0.35), CFrame.new(x * (1.3 + k * 0.45), 0.55 - k * 0.15, 0.55) * CFrame.Angles(0, 0, x * (-0.6 + k * 0.5)), if k == 0 then acc else lighter(acc, 0.3), mat, 0.1)
				table.insert(anims, { part = part, kind = "flap", hinge = Vector3.new(x * 0.85, 0.35, 0.55), side = x })
			end
			blob(m, Vector3.new(0.5, 0.45, 0.65), CFrame.new(x * 0.6, -1.2, 0), darker(c, 0.15), mat)
		end
		face(m, CFrame.new(0, 0.85, -1.2), 0.85, acc)
		for k = 0, 2 do
			wedge(m, Vector3.new(0.15, 0.5, 0.5), CFrame.new(0, 0.55 - k * 0.1, 0.35 + k * 0.5), acc, mat)
		end
		local tailSegs = { { Vector3.new(0, -0.55, 1.65), 0.8 }, { Vector3.new(0, -0.45, 2.3), 0.6 }, { Vector3.new(0, -0.2, 2.85), 0.45 } }
		for _, seg in tailSegs do
			local part = blob(m, Vector3.one * seg[2], CFrame.new(seg[1]), c, mat)
			table.insert(anims, { part = part, kind = "wag", hinge = Vector3.new(0, -0.5, 1.3) })
		end
		local spade = wedge(m, Vector3.new(0.12, 0.5, 0.5), CFrame.new(0, 0, 3.2) * CFrame.Angles(0, math.pi, 0), acc, mat)
		table.insert(anims, { part = spade, kind = "wag", hinge = Vector3.new(0, -0.5, 1.3) })
	end

	-- Glowing orb spirit with a flame tail and orbiting sparks
	function BUILDERS.wisp(m, P, c, acc, anims)
		blob(m, Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, 0.1, 0), acc, Enum.Material.Neon, 0.75)
		local core = blob(m, Vector3.new(1.9, 1.9, 1.9), CFrame.new(0, 0.1, 0), c, if P.variant == "spirit" then Enum.Material.SmoothPlastic else Enum.Material.Glass)
		core.Reflectance = 0.2
		face(m, CFrame.new(0, 0.2, -0.92), 0.85, acc)
		for i, seg in { { Vector3.new(0, 0.5, 1.05), 1.2 }, { Vector3.new(0, 0.95, 1.6), 0.9 }, { Vector3.new(0, 1.45, 1.95), 0.6 }, { Vector3.new(0, 1.9, 2.1), 0.35 } } do
			local part = blob(m, Vector3.one * seg[2], CFrame.new(seg[1]), if i % 2 == 0 then acc else c, Enum.Material.Neon, 0.2)
			table.insert(anims, { part = part, kind = "wag", hinge = Vector3.new(0, 0.2, 0.8) })
		end
		for k = 1, 3 do
			local orb = petPart(m, Vector3.new(0.35, 0.35, 0.35), CFrame.new(1.6, 0.2, 0), acc, Enum.Material.Neon, Enum.PartType.Ball)
			table.insert(anims, { part = orb, kind = "orbit", phase = k * 2.09, radius = 1.7 })
		end
		if P.variant == "spirit" then
			petPart(m, Vector3.new(0.12, 1.6, 1.6), CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Neon, Enum.PartType.Cylinder)
			for _, x in { -1, 1 } do
				local wing = blob(m, Vector3.new(0.12, 1.3, 1.9), CFrame.new(x * 1.35, 0.4, 0.4) * CFrame.Angles(0, 0, x * -0.45), WHITE, Enum.Material.Neon, 0.35)
				table.insert(anims, { part = wing, kind = "flap", hinge = Vector3.new(x * 0.9, 0.3, 0.4), side = x })
			end
		end
	end

	-- Cosmic serpent coiled in a spiral, speckled with stars
	function BUILDERS.serpent(m, P, c, acc, anims)
		for i = 0, 7 do
			local ang = i * 0.85
			local r = 1.2 - i * 0.09
			local size = 1.2 - i * 0.08
			blob(m, Vector3.one * size, CFrame.new(math.cos(ang) * r, -1 + i * 0.13, math.sin(ang) * r + 0.3), if i % 2 == 0 then c else darker(c, 0.1))
			if i % 2 == 1 then
				petPart(m, Vector3.new(0.14, 0.14, 0.14), CFrame.new(math.cos(ang) * r, -0.6 + i * 0.13, math.sin(ang) * r + 0.3), acc, Enum.Material.Neon, Enum.PartType.Ball)
			end
		end
		local neck = blob(m, Vector3.new(1, 1.4, 1), CFrame.new(0, 0.15, -0.45) * CFrame.Angles(0.35, 0, 0), c)
		local head = blob(m, Vector3.new(1.7, 1.35, 1.7), CFrame.new(0, 0.95, -0.75), c)
		blob(m, Vector3.new(1, 0.6, 0.8), CFrame.new(0, 0.7, -1.45), lighter(c, 0.2))
		face(m, CFrame.new(0, 1.15, -1.55), 0.8, acc)
		for _, x in { -1, 1 } do
			petPart(m, Vector3.new(0.2, 0.8, 0.2), CFrame.new(x * 0.45, 1.75, -0.6) * CFrame.Angles(-0.5, 0, x * -0.3), acc, Enum.Material.Neon)
			wedge(m, Vector3.new(0.08, 0.6, 0.7), CFrame.new(x * 0.85, 1.0, -0.5) * CFrame.Angles(0, 0, x * -0.8), acc)
		end
		for _, part in { neck, head } do
			table.insert(anims, { part = part, kind = "bob" })
		end
	end

	buildPet = function(id)
		local P = CFG.pets[id]
		local m = Instance.new("Model")
		m.Name = "Pet_" .. id
		local anims = {}
		if not P then
			return m, anims
		end
		local c, acc = rgb(P.color), rgb(P.accent)
		local builder = BUILDERS[P.style or "critter"] or BUILDERS.critter
		builder(m, P, c, acc, anims)
		if P.glow then
			local anchorPart = m:FindFirstChildWhichIsA("BasePart")
			if anchorPart then
				local light = Instance.new("PointLight")
				light.Color = acc
				light.Range = 10
				light.Brightness = 1.5
				light.Parent = anchorPart
				local sp = Instance.new("Sparkles")
				sp.SparkleColor = acc
				sp.Parent = anchorPart
			end
		end
		-- the pivot sits at the model centre; remember every animated part relative to it
		local pivotPart = petPart(m, Vector3.new(0.2, 0.2, 0.2), CFrame.new(), WHITE)
		pivotPart.Name = "Pivot"
		pivotPart.Transparency = 1
		m.PrimaryPart = pivotPart
		for _, a in anims do
			a.base = a.part.CFrame
			a.size = a.part.Size
		end
		return m, anims
	end

	-- Plays each pet's idle animation. `pivot` is the model's current CFrame, `scale` its ScaleTo factor.
	animatePet = function(anims, pivot, t, scale)
		for i, a in anims do
			local hinge = a.hinge and a.hinge * scale or Vector3.zero
			local base = CFrame.new(a.base.Position * scale) * a.base.Rotation
			local rot
			if a.kind == "flap" then
				rot = CFrame.Angles(0, 0, (a.side or 1) * math.sin(t * 9) * (a.amount or 0.6))
			elseif a.kind == "wag" then
				rot = CFrame.Angles(0, math.sin(t * 7) * 0.35, 0)
			elseif a.kind == "ear" then
				rot = CFrame.Angles(0, 0, (a.side or 1) * (math.sin(t * 2.3) * 0.12 + 0.05))
			elseif a.kind == "swing" then
				rot = CFrame.Angles(math.sin(t * 3 + (a.side or 1)) * 0.35, 0, 0)
			elseif a.kind == "bob" then
				rot = CFrame.new(0, math.sin(t * 2.5) * 0.12 * scale, 0)
			elseif a.kind == "orbit" then
				local ang = t * 2 + (a.phase or 0)
				a.part.CFrame = pivot * CFrame.new(math.cos(ang) * a.radius * scale, 0.2 * scale + math.sin(ang * 2) * 0.3 * scale, math.sin(ang) * a.radius * scale)
				continue
			elseif a.kind == "squash" then
				local k = 1 + math.sin(t * 4 + i) * 0.06
				local mesh = a.part:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					mesh.Scale = Vector3.new(1 / math.sqrt(k), k, 1 / math.sqrt(k))
				end
				continue
			end
			if rot then
				a.part.CFrame = pivot * CFrame.new(hinge) * rot * CFrame.new(-hinge) * base
			end
		end
	end
end

-- Pets that follow every player (built locally for smooth movement) ---------------
local rebuildPets, updatePets
do
	local followers = {} -- [Player] = { ids = string, models = { Model } }
	rebuildPets = function(plr)
		local entry = followers[plr]
		if entry then
			for _, m in entry.models do
				m:Destroy()
			end
		end
		local raw = plr:GetAttribute("PetsEquipped")
		local ids = {}
		if type(raw) == "string" then
			local ok, data = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(data) == "table" then
				ids = data
			end
		end
		local models, animSets = {}, {}
		if plr ~= player and not settings.otherPets then
			ids = {}
		end
		for i, id in ids do
			local m, anims = buildPet(id)
			m:ScaleTo(0.8)
			m.Parent = workspace
			models[i] = m
			animSets[i] = anims
		end
		followers[plr] = { models = models, anims = animSets, pos = {} }
	end
	local function watchPlayer(plr)
		plr:GetAttributeChangedSignal("PetsEquipped"):Connect(function()
			rebuildPets(plr)
		end)
		rebuildPets(plr)
	end
	for _, plr in Players:GetPlayers() do
		watchPlayer(plr)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(plr)
		local entry = followers[plr]
		if entry then
			for _, m in entry.models do
				m:Destroy()
			end
		end
		followers[plr] = nil
	end)
	local SLOT_OFFSETS = { Vector3.new(-3.2, 0.8, 3), Vector3.new(3.2, 0.8, 3), Vector3.new(0, 1, 4.6), Vector3.new(-5.4, 0.6, 1), Vector3.new(5.4, 0.6, 1) }
	updatePets = function(dt)
		local t = os.clock()
		for plr, entry in followers do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				for i, m in entry.models do
					local offset = SLOT_OFFSETS[i] or Vector3.new(0, 1, 3 + i)
					local goal = (root.CFrame * CFrame.new(offset)).Position + Vector3.new(0, math.sin(t * 3 + i) * 0.35 - 1.2, 0)
					local cur = entry.pos[i] or goal
					if (cur - goal).Magnitude > 60 then
						cur = goal
					end
					cur = cur:Lerp(goal, 1 - math.exp(-dt * 7))
					entry.pos[i] = cur
					local look = root.CFrame.LookVector
					local flat = Vector3.new(look.X, 0, look.Z)
					if flat.Magnitude < 0.01 then
						flat = Vector3.new(0, 0, -1)
					end
					-- pets face the way their owner is facing (their front is -Z)
					local pivot = CFrame.lookAt(cur, cur + flat.Unit)
					m:PivotTo(pivot)
					if entry.anims and entry.anims[i] then
						animatePet(entry.anims[i], pivot, t + i, 0.8)
					end
				end
			end
		end
	end
end

-- PETS window ---------------------------------------------------------------------
do
	local _, body = makeWindow("Pets", "🐾 PETS", Color3.fromRGB(255, 150, 200), Color3.fromRGB(230, 70, 140))
	local info = label({ parent = body, text = "", size = 18, color = INK, outline = false, sz = UDim2.new(1, -190, 0, 30), alignX = Enum.TextXAlignment.Left })
	cartoonButton(body, {
		sz = UDim2.fromOffset(170, 40),
		pos = UDim2.new(1, 0, 0, -4),
		anchor = Vector2.new(1, 0),
		top = Color3.fromRGB(120, 235, 120),
		bottom = Color3.fromRGB(40, 170, 70),
		text = "⭐ EQUIP BEST",
		textSize = 18,
		onClick = function()
			Remotes.Action:FireServer("EquipBest")
		end,
	})
	local scroll = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		create("UIGridLayout", { CellSize = UDim2.fromOffset(112, 138), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
	})
	local empty = label({ parent = body, text = "No pets yet!\nHatch eggs at the 🥚 Pet Shop next to the museum.", size = 20, color = INK, outline = false, wrap = true, sz = UDim2.new(1, 0, 0, 80), pos = UDim2.fromScale(0, 0.4) })
	local function refresh()
		for _, c in scroll:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local list = {}
		local raw = player:GetAttribute("Pets")
		if type(raw) == "string" then
			local ok, data = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(data) == "table" then
				list = data
			end
		end
		table.sort(list, function(a, b)
			if a.e ~= b.e then
				return a.e
			end
			local pa, pb = CFG.pets[a.id], CFG.pets[b.id]
			return (pa and pa.boost or 0) > (pb and pb.boost or 0)
		end)
		local equipped, total = 0, 0
		for i, pet in list do
			local P = CFG.pets[pet.id]
			if P then
				if pet.e then
					equipped += 1
					total += P.boost
				end
				local rc = rgb(CFG.rarityColors[P.rarity] or { 200, 200, 210 })
				local c = create("Frame", { LayoutOrder = i, BackgroundColor3 = WHITE, Parent = scroll }, { corner(UDim.new(0, 16)), stroke(if pet.e then 4 else 3, if pet.e then Color3.fromRGB(40, 170, 70) else INK) })
				gradient(c, WHITE, rc:Lerp(WHITE, 0.45))
				label({ parent = c, text = P.icon, size = 40, outline = false, sz = UDim2.new(1, 0, 0, 50), pos = UDim2.fromOffset(0, 4) })
				label({ parent = c, text = P.name, size = 14, sz = UDim2.new(1, -6, 0, 18), pos = UDim2.fromOffset(3, 54) })
				label({ parent = c, text = `+{math.floor(P.boost * 100 + 0.5)}%`, size = 16, color = Color3.fromRGB(255, 214, 70), sz = UDim2.new(1, 0, 0, 18), pos = UDim2.fromOffset(0, 72) })
				cartoonButton(c, {
					sz = UDim2.new(0.62, 0, 0, 30),
					pos = UDim2.new(0, 6, 1, -6),
					anchor = Vector2.new(0, 1),
					top = if pet.e then Color3.fromRGB(255, 200, 90) else Color3.fromRGB(120, 235, 120),
					bottom = if pet.e then Color3.fromRGB(230, 140, 30) else Color3.fromRGB(40, 170, 70),
					text = if pet.e then "UNEQUIP" else "EQUIP",
					textSize = 12,
					onClick = function()
						Remotes.Action:FireServer(if pet.e then "Unequip" else "Equip", pet.u)
					end,
				})
				cartoonButton(c, {
					sz = UDim2.new(0.28, 0, 0, 30),
					pos = UDim2.new(1, -6, 1, -6),
					anchor = Vector2.new(1, 1),
					top = Color3.fromRGB(255, 110, 100),
					bottom = Color3.fromRGB(220, 40, 50),
					text = "🗑",
					textSize = 14,
					onClick = function()
						Remotes.Action:FireServer("Delete", pet.u)
					end,
				})
			end
		end
		empty.Visible = #list == 0
		info.Text = `{#list}/{CFG.maxPets} pets · equipped {equipped}/{attr("PetSlots", CFG.petSlots)} · +{math.floor(total * 100 + 0.5)}% · 📖 {attr("PetIndex", 0)}/{CFG.petCount}`
	end
	player:GetAttributeChangedSignal("Pets"):Connect(refresh)
	player:GetAttributeChangedSignal("PetSlots"):Connect(refresh)
	player:GetAttributeChangedSignal("PetIndex"):Connect(refresh)
	refresh()
end

-- SPIN window ------------------------------------------------------------------
local wheelSpinning = false
local spinButton, spinLabel, wheel, spinResult
do
	local _, body = makeWindow("Spin", "🎡 SPIN THE WHEEL", Color3.fromRGB(120, 200, 255), Color3.fromRGB(50, 110, 230))
	-- square wheel sized from the window height, so it always fits
	local holder = create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 1, Parent = body }, {
		create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
	})
	wheel = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 250, 240), Parent = holder }, { corner(), stroke(6, INK) })
	local n = #CFG.spin
	for i, seg in CFG.spin do
		-- Roblox rotates a frame around its own centre, so each slice sits in a full-size
		-- rotor that turns around the wheel's centre.
		local rotor = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = (i - 1) * 360 / n, Parent = wheel })
		local petal = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.03),
			Size = UDim2.fromScale(0.3, 0.47),
			BackgroundColor3 = rgb(seg.color),
			Parent = rotor,
		}, { corner(UDim.new(0.5, 0)), stroke(3, INK) })
		label({ parent = petal, text = seg.icon, size = 26, outline = false, sz = UDim2.new(1, 0, 0, 30), pos = UDim2.fromOffset(0, 8) })
		label({ parent = petal, text = seg.label, size = 12, sz = UDim2.new(1, 0, 0, 16), pos = UDim2.fromOffset(0, 40) })
	end
	create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.16, 0.16), BackgroundColor3 = GOLD, ZIndex = 3, Parent = wheel }, { corner(), stroke(4, INK) })
	label({ parent = holder, text = "▼", size = 44, color = Color3.fromRGB(255, 70, 70), sz = UDim2.fromOffset(60, 50), pos = UDim2.new(0.5, 0, 0, -30), anchor = Vector2.new(0.5, 0), z = 5 })
	spinResult = label({ parent = body, text = "", size = 22, color = INK, outline = false, sz = UDim2.new(1, 0, 0, 28), pos = UDim2.new(0, 0, 0.66, 30) })
	spinButton = cartoonButton(body, {
		sz = UDim2.fromOffset(230, 56),
		pos = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		top = Color3.fromRGB(120, 235, 120),
		bottom = Color3.fromRGB(40, 170, 70),
		onClick = function()
			if wheelSpinning then
				return
			end
			if workspace:GetServerTimeNow() < attr("SpinAt", 0) then
				toast("The wheel is recharging!", WHITE)
				return
			end
			wheelSpinning = true
			spinResult.Text = ""
			Remotes.Action:FireServer("Spin")
			task.delay(8, function()
				wheelSpinning = false
			end)
		end,
	})
	spinLabel = label({ parent = spinButton, text = "SPIN!", size = 26, z = 2 })
end

Remotes.SpinResult.OnClientEvent:Connect(function(index, text)
	local n = #CFG.spin
	-- land segment `index` under the pointer at the top
	local target = 360 * 6 - (index - 1) * 360 / n + math.random(-12, 12)
	wheel.Rotation = wheel.Rotation % 360
	local t = tween(wheel, 4, { Rotation = target }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	for k = 1, 16 do
		task.delay(k * 0.22, playSound, "Swing", 1.6)
	end
	t.Completed:Connect(function()
		wheelSpinning = false
		spinResult.Text = "🎉 " .. text
		playSound("Treasure", 1.2)
		confetti(40)
		toast("🎡 " .. text, GOLD)
	end)
end)

-- CODES window -----------------------------------------------------------------
do
	local _, body = makeWindow("Codes", "🎟️ CODES", Color3.fromRGB(200, 150, 255), Color3.fromRGB(130, 70, 220))
	label({ parent = body, text = "Enter a code for free rewards!", size = 22, color = INK, outline = false, sz = UDim2.new(1, 0, 0, 30), pos = UDim2.fromOffset(0, 10) })
	local boxFrame = create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.new(0.8, 0, 0, 56), BackgroundColor3 = WHITE, Parent = body }, { corner(UDim.new(0, 16)), stroke(4, INK) })
	local box = create("TextBox", {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 26,
		TextColor3 = INK,
		PlaceholderText = "Type code here...",
		PlaceholderColor3 = Color3.fromRGB(160, 160, 170),
		Text = "",
		ClearTextOnFocus = false,
		Parent = boxFrame,
	})
	local result = label({ parent = body, text = "", size = 20, color = INK, outline = false, sz = UDim2.new(1, 0, 0, 28), pos = UDim2.fromOffset(0, 196) })
	cartoonButton(body, {
		sz = UDim2.fromOffset(220, 54),
		pos = UDim2.new(0.5, 0, 0, 132),
		anchor = Vector2.new(0.5, 0),
		top = Color3.fromRGB(120, 235, 120),
		bottom = Color3.fromRGB(40, 170, 70),
		text = "REDEEM",
		textSize = 24,
		onClick = function()
			if box.Text ~= "" then
				Remotes.Action:FireServer("Redeem", box.Text)
			end
		end,
	})
	Remotes.Purchased.OnClientEvent:Connect(function(kind, ok, text)
		if kind == "code" then
			result.Text = (if ok then "✅ " else "❌ ") .. tostring(text)
			result.TextColor3 = if ok then Color3.fromRGB(30, 140, 60) else Color3.fromRGB(200, 40, 40)
			if ok then
				confetti(30)
				playSound("Buy", 1.2)
				box.Text = ""
			end
		elseif ok then
			toast("🎉 " .. tostring(text), GOLD)
			confetti(60)
			playSound("Buy", 1)
		end
	end)
end

-- QUESTS window ------------------------------------------------------------------
do
	local _, body = makeWindow("Quests", "📜 DAILY QUESTS", Color3.fromRGB(255, 190, 120), Color3.fromRGB(220, 110, 40))
	local resetLabel = label({ parent = body, text = "", size = 17, color = INK, outline = false, sz = UDim2.new(1, 0, 0, 22), alignX = Enum.TextXAlignment.Left })
	local rows = {}
	for i = 1, 3 do
		local r = create("Frame", { Position = UDim2.new(0, 0, 0, 30 + (i - 1) * 76), Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = WHITE, Parent = body }, { corner(UDim.new(0, 16)), stroke(3, INK) })
		gradient(r, WHITE, Color3.fromRGB(255, 240, 222))
		local text = label({ parent = r, text = "", size = 19, color = INK, outline = false, sz = UDim2.new(1, -170, 0, 28), pos = UDim2.fromOffset(14, 6), alignX = Enum.TextXAlignment.Left })
		local bar = create("Frame", { Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -170, 0, 18), BackgroundColor3 = Color3.fromRGB(60, 50, 90), Parent = r }, { corner(), stroke(2, INK) })
		local fill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = bar }, { corner() })
		gradient(fill, Color3.fromRGB(140, 240, 110), Color3.fromRGB(60, 190, 70))
		local barText = label({ parent = bar, text = "", size = 13, z = 2 })
		local claim, claimGrad = cartoonButton(r, { sz = UDim2.fromOffset(140, 46), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -12, 0.5, 0), top = WHITE, bottom = WHITE, onClick = function()
			Remotes.Action:FireServer("ClaimQuest", i)
		end })
		local claimText = label({ parent = claim, text = "", size = 18, z = 2 })
		rows[i] = { text = text, fill = fill, barText = barText, claim = claim, claimGrad = claimGrad, claimText = claimText }
	end
	local bonus, bonusGrad = cartoonButton(body, { sz = UDim2.new(0.62, 0, 0, 52), pos = UDim2.new(0, 0, 0, 262), top = WHITE, bottom = WHITE, onClick = function()
		Remotes.Action:FireServer("ClaimQuestBonus")
	end })
	local bonusText = label({ parent = bonus, text = "", size = 18, z = 2 })
	cartoonButton(body, {
		sz = UDim2.new(0.35, 0, 0, 52),
		pos = UDim2.new(1, 0, 0, 262),
		anchor = Vector2.new(1, 0),
		top = Color3.fromRGB(120, 200, 255),
		bottom = Color3.fromRGB(50, 110, 230),
		text = "👥 INVITE FRIENDS",
		textSize = 17,
		onClick = function()
			local ok, can = pcall(function()
				return SocialService:CanSendGameInviteAsync(player)
			end)
			if ok and can then
				pcall(function()
					SocialService:PromptGameInvite(player)
				end)
			else
				toast("Invites aren't available right now", WHITE)
			end
		end,
	})
	label({ parent = body, text = "Playing with a friend gives +10% coins!", size = 15, color = Color3.fromRGB(90, 90, 110), outline = false, sz = UDim2.new(1, 0, 0, 20), pos = UDim2.new(0, 0, 0, 320) })
	local data = { list = {}, bonus = false, resets = 0 }
	local function refresh()
		local raw = player:GetAttribute("Quests")
		if type(raw) == "string" then
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(decoded) == "table" then
				data = decoded
			end
		end
		local claimable, allClaimed = false, #data.list > 0
		for i, row in rows do
			local q = data.list[i]
			row.text.Parent.Visible = q ~= nil
			if q then
				row.text.Text = q.text
				row.fill.Size = UDim2.fromScale(math.clamp(q.progress / math.max(1, q.goal), 0, 1), 1)
				row.barText.Text = `{q.progress} / {q.goal}`
				local done = q.progress >= q.goal
				if q.claimed then
					row.claimText.Text = "✔ DONE"
					row.claimGrad.Color = bevel(Color3.fromRGB(200, 200, 210), Color3.fromRGB(150, 150, 165))
				elseif done then
					row.claimText.Text = "CLAIM!"
					row.claimGrad.Color = bevel(Color3.fromRGB(120, 235, 120), Color3.fromRGB(40, 170, 70))
					claimable = true
				else
					row.claimText.Text = `💰 {CFG.questRewardMinutes} min`
					row.claimGrad.Color = bevel(Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 150, 30))
				end
				allClaimed = allClaimed and q.claimed
			end
		end
		if data.bonus then
			bonusText.Text = "✔ Bonus claimed. New quests tomorrow!"
			bonusGrad.Color = bevel(Color3.fromRGB(200, 200, 210), Color3.fromRGB(150, 150, 165))
		elseif allClaimed then
			bonusText.Text = "🎁 CLAIM BONUS: free egg + Luck potion!"
			bonusGrad.Color = bevel(Color3.fromRGB(255, 150, 200), Color3.fromRGB(230, 70, 140))
			claimable = true
		else
			bonusText.Text = "🎁 Finish all 3 for a free egg!"
			bonusGrad.Color = bevel(Color3.fromRGB(230, 220, 240), Color3.fromRGB(180, 170, 200))
		end
		stackButtons.Quests.Badge.Visible = claimable
	end
	player:GetAttributeChangedSignal("Quests"):Connect(refresh)
	refresh()
	windows.Quests_reset = function()
		if data.resets and data.resets > 0 then
			resetLabel.Text = "New quests in " .. clock(data.resets - workspace:GetServerTimeNow())
		end
	end
end

-- WELCOME BACK popup (offline earnings + daily chest reminder) -----------------------
Remotes.Welcome.OnClientEvent:Connect(function(amount, minutes, dailyReady, streak)
	local panel = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(440, if amount > 0 then 270 else 190),
		BackgroundColor3 = WHITE,
		ZIndex = 30,
		Parent = overlayGui,
	}, { corner(UDim.new(0, 26)), stroke(5, INK) })
	gradient(panel, Color3.fromRGB(255, 252, 244), Color3.fromRGB(236, 226, 210))
	local sc = create("UIScale", { Scale = 0.4, Parent = panel })
	tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	label({ parent = panel, text = "👋 WELCOME BACK!", size = 34, color = Color3.fromRGB(255, 190, 60), sz = UDim2.new(1, 0, 0, 44), pos = UDim2.fromOffset(0, 14), z = 31 })
	local y = 62
	if amount > 0 then
		local hours = math.floor(minutes / 60)
		label({ parent = panel, text = `Your pets kept digging for {if hours > 0 then hours .. "h " else ""}{minutes % 60}m`, size = 18, color = INK, outline = false, sz = UDim2.new(1, 0, 0, 24), pos = UDim2.fromOffset(0, y), z = 31 })
		label({ parent = panel, text = "+ 💰 " .. fmt(amount), size = 40, color = GOLD, sz = UDim2.new(1, 0, 0, 50), pos = UDim2.fromOffset(0, y + 28), z = 31 })
		y += 86
	end
	if dailyReady then
		label({ parent = panel, text = if (streak or 0) > 0 then `🎁 Daily chest ready! Keep your 🔥{streak}-day streak` else "🎁 Your daily chest is ready!", size = 17, color = Color3.fromRGB(200, 90, 40), outline = false, sz = UDim2.new(1, 0, 0, 24), pos = UDim2.fromOffset(0, y), z = 31 })
	end
	local btn = cartoonButton(panel, {
		sz = UDim2.fromOffset(220, 54),
		anchor = Vector2.new(0.5, 1),
		pos = UDim2.new(0.5, 0, 1, -16),
		top = Color3.fromRGB(120, 235, 120),
		bottom = Color3.fromRGB(40, 170, 70),
		text = if amount > 0 then "COLLECT!" else "LET'S DIG!",
		textSize = 24,
		z = 31,
		onClick = function()
			if amount > 0 then
				Remotes.Action:FireServer("CollectOffline")
				confetti(40)
			end
			local t = tween(sc, 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			t.Completed:Connect(function()
				panel:Destroy()
			end)
		end,
	})
	btn.ZIndex = 31
	playSound("Treasure", 1.1)
end)

-- SETTINGS window ---------------------------------------------------------------
do
	local _, body = makeWindow("Settings", "⚙️ SETTINGS", Color3.fromRGB(220, 224, 235), Color3.fromRGB(140, 146, 165))
	local list = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }), create("UIPadding", { PaddingRight = UDim.new(0, 12) }) })
	local saveToken = 0
	local function save()
		saveToken += 1
		local token = saveToken
		task.delay(0.8, function()
			if token == saveToken then
				Remotes.Action:FireServer("Settings", settings)
			end
		end)
	end
	local refreshers = {}
	local function row(order, icon, text, key, volumeKey)
		local r = create("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = WHITE, Parent = list }, { corner(UDim.new(0, 16)), stroke(3, INK) })
		gradient(r, WHITE, Color3.fromRGB(232, 236, 248))
		label({ parent = r, text = icon, size = 30, outline = false, sz = UDim2.fromOffset(50, 62), pos = UDim2.fromOffset(8, 0) })
		label({ parent = r, text = text, size = 21, color = INK, outline = false, sz = UDim2.new(0.4, 0, 1, 0), pos = UDim2.fromOffset(62, 0), alignX = Enum.TextXAlignment.Left })
		local toggle, toggleGrad = cartoonButton(r, { sz = UDim2.fromOffset(92, 42), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -12, 0.5, 0), top = WHITE, bottom = WHITE, textSize = 20 })
		local toggleText = label({ parent = toggle, text = "", size = 20, z = 2 })
		local volText
		if volumeKey then
			local function step(delta)
				settings[volumeKey] = math.clamp(math.floor((settings[volumeKey] + delta) * 10 + 0.5) / 10, 0, 1)
				applySoundSettings()
				save()
				for _, f in refreshers do
					f()
				end
			end
			cartoonButton(r, { sz = UDim2.fromOffset(42, 42), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -250, 0.5, 0), top = Color3.fromRGB(255, 200, 90), bottom = Color3.fromRGB(230, 140, 30), text = "−", textSize = 26, onClick = function()
				step(-0.1)
			end })
			volText = label({ parent = r, text = "", size = 20, color = INK, outline = false, sz = UDim2.fromOffset(70, 42), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -174, 0.5, 0) })
			cartoonButton(r, { sz = UDim2.fromOffset(42, 42), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -124, 0.5, 0), top = Color3.fromRGB(255, 200, 90), bottom = Color3.fromRGB(230, 140, 30), text = "+", textSize = 26, onClick = function()
				step(0.1)
			end })
		end
		local function refresh()
			local on = settings[key]
			toggleText.Text = if on then "ON" else "OFF"
			toggleGrad.Color = if on
				then bevel(Color3.fromRGB(120, 235, 120), Color3.fromRGB(40, 170, 70))
				else bevel(Color3.fromRGB(255, 120, 110), Color3.fromRGB(220, 50, 50))
			if volText then
				volText.Text = `{math.floor(settings[volumeKey] * 100 + 0.5)}%`
			end
		end
		toggle.Activated:Connect(function()
			settings[key] = not settings[key]
			applySoundSettings()
			if key == "otherPets" then
				for _, plr in Players:GetPlayers() do
					rebuildPets(plr)
				end
			end
			refresh()
			save()
			playSound("Click", 1)
		end)
		table.insert(refreshers, refresh)
		refresh()
	end
	row(1, "🎵", "Music", "music", "musicVol")
	row(2, "🔊", "Sound effects", "sfx", "sfxVol")
	row(3, "🌲", "Ambience", "ambience")
	row(4, "🐾", "Other players' pets", "otherPets")
	row(5, "📳", "Screen shake", "shake")
	-- load saved settings from the server
	local function loadSaved()
		local raw = player:GetAttribute("Settings")
		if type(raw) == "string" then
			local ok, data = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(data) == "table" then
				for k, v in data do
					if settings[k] ~= nil and typeof(v) == typeof(settings[k]) then
						settings[k] = v
					end
				end
			end
		end
		applySoundSettings()
		for _, f in refreshers do
			f()
		end
		for _, plr in Players:GetPlayers() do
			if plr ~= player then
				rebuildPets(plr)
			end
		end
	end
	player:GetAttributeChangedSignal("Settings"):Once(loadSaved)
	loadSaved()
end

-- HATCH animation ------------------------------------------------------------------
local hatching = false
Remotes.Hatched.OnClientEvent:Connect(function(petId, eggId)
	local P = CFG.pets[petId]
	local egg
	for _, e in CFG.eggs do
		if e.id == eggId then
			egg = e
		end
	end
	if not P or not egg or hatching then
		if P then
			toast(`🐾 {P.name} hatched!`, GOLD)
		end
		return
	end
	hatching = true
	local rc = rgb(CFG.rarityColors[P.rarity] or { 200, 200, 210 })
	local shade = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 20, Parent = overlayGui })
	tween(shade, 0.25, { BackgroundTransparency = 0.35 })
	local eggFrame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(170, 220),
		BackgroundColor3 = WHITE,
		ZIndex = 21,
		Parent = overlayGui,
	}, { corner(UDim.new(0.5, 0)), stroke(6, INK) })
	gradient(eggFrame, rgb(egg.color):Lerp(WHITE, 0.25), rgb(egg.color))
	for k = 1, 5 do
		create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.2 + (k * 0.37) % 0.7, 0.2 + (k * 0.23) % 0.6), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = rgb(egg.spots), ZIndex = 22, Parent = eggFrame }, { corner() })
	end
	local sc = create("UIScale", { Scale = 0.2, Parent = eggFrame })
	tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.5)
	for k = 1, 3 do
		local amt = 8 + k * 6
		for _ = 1, 3 do
			tween(eggFrame, 0.06, { Rotation = amt })
			task.wait(0.07)
			tween(eggFrame, 0.06, { Rotation = -amt })
			task.wait(0.07)
		end
		eggFrame.Rotation = 0
		playSound("EggCrack", 0.9 + k * 0.1)
		task.wait(0.25)
	end
	local flash = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 30, Parent = overlayGui })
	tween(flash, 0.5, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 0.6)
	eggFrame:Destroy()
	playSound("Treasure", if P.rarity == "Legendary" then 0.7 else 1.1)
	confetti(if P.rarity == "Legendary" then 120 else 50)
	local vp = create("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromOffset(300, 300),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = WHITE,
		Parent = overlayGui,
	})
	local model, revealAnims = buildPet(petId)
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.9, -6.5), Vector3.new(0, 0.3, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	local vsc = create("UIScale", { Scale = 0.2, Parent = vp })
	tween(vsc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	local ribbon = create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.66, 0), Size = UDim2.fromOffset(360, 110), BackgroundColor3 = WHITE, ZIndex = 24, Parent = overlayGui }, { corner(UDim.new(0, 22)), stroke(5, INK) })
	gradient(ribbon, rc:Lerp(WHITE, 0.3), rc:Lerp(Color3.new(0, 0, 0), 0.15))
	label({ parent = ribbon, text = P.name, size = 36, sz = UDim2.new(1, 0, 0, 44), pos = UDim2.fromOffset(0, 6), z = 25 })
	label({ parent = ribbon, text = `{string.upper(P.rarity)} · +{math.floor(P.boost * 100 + 0.5)}% coins`, size = 20, sz = UDim2.new(1, 0, 0, 28), pos = UDim2.fromOffset(0, 54), z = 25 })
	local start = os.clock()
	local revealDone = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if revealDone then
			conn:Disconnect()
			return
		end
		local pivot = CFrame.Angles(0, math.sin((os.clock() - start) * 1.3) * 0.9, 0) * CFrame.new(0, math.sin((os.clock() - start) * 3) * 0.12, 0)
		model:PivotTo(pivot)
		animatePet(revealAnims, pivot, os.clock() - start, 1)
	end)
	task.wait(3)
	revealDone = true
	conn:Disconnect()
	tween(shade, 0.3, { BackgroundTransparency = 1 })
	tween(vsc, 0.25, { Scale = 0 })
	local rsc = create("UIScale", { Parent = ribbon })
	tween(rsc, 0.25, { Scale = 0 })
	task.wait(0.35)
	shade:Destroy()
	vp:Destroy()
	ribbon:Destroy()
	hatching = false
end)

-- LEVEL UP -----------------------------------------------------------------------
Remotes.LevelUp.OnClientEvent:Connect(function(level, reward)
	local big = label({ parent = overlayGui, text = "LEVEL UP!", size = 64, color = Color3.fromRGB(130, 220, 255), sz = UDim2.fromOffset(600, 80), pos = UDim2.fromScale(0.5, 0.3), anchor = Vector2.new(0.5, 0.5), z = 40 })
	local sub = label({ parent = overlayGui, text = `Level {level} · +1% ore value · + 💰 {fmt(reward)}`, size = 26, color = GOLD, sz = UDim2.fromOffset(600, 36), pos = UDim2.fromScale(0.5, 0.37), anchor = Vector2.new(0.5, 0.5), z = 40 })
	local sc = create("UIScale", { Scale = 0.3, Parent = big })
	tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	confetti(45)
	playSound("LevelUp", 1)
	task.delay(2.2, function()
		tween(sc, 0.25, { Scale = 0 })
		tween(sub, 0.25, { TextTransparency = 1 })
		task.wait(0.3)
		big:Destroy()
		sub:Destroy()
	end)
end)

-- Slow HUD refresh (level bar, potions, badges, pass buttons) ----------------------
-- OBJECTIVE BANNER + ARROW TRAIL --------------------------------------------------
-- A big "what to do next" banner at the top and red arrows on the ground leading to it.
-- It walks new players through the first steps, then always shows the next goal.
local updateObjective, updateArrows
do
	local banner2 = create("Frame", {
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Parent = gui,
	}, {
		create("UIPadding", { PaddingLeft = UDim.new(0, 60), PaddingRight = UDim.new(0, 60) }),
		create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.25), NumberSequenceKeypoint.new(0.82, 0.25), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	local bannerScale = create("UIScale", { Parent = banner2 })
	local objText = create("TextLabel", {
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 40,
		TextColor3 = WHITE,
		Text = "",
		Parent = banner2,
	}, { stroke(4, INK) })
	local stepLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(200, 18),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 16,
		TextColor3 = GOLD,
		Text = "",
		Parent = banner2,
	}, { stroke(2.5, INK) })

	local mineCenter = Vector3.new(0, CFG.top - CFG.block * 3, 0)
	local function tagged(tag, pred)
		for _, inst in CollectionService:GetTagged(tag) do
			if not pred or pred(inst) then
				return inst
			end
		end
		return nil
	end
	local function pedestal(kind, tier)
		local p = tagged("ShopItem", function(pr)
			return pr:GetAttribute("Kind") == kind and pr:GetAttribute("Tier") == tier
		end)
		return p and p.Parent
	end
	local function posOf(target)
		if typeof(target) == "Vector3" then
			return target
		elseif typeof(target) == "Instance" and target:IsA("BasePart") then
			return target.Position
		end
		return nil
	end

	local TUTORIAL_STEPS = 7
	local current, currentTarget = "", nil
	-- returns: text, target (part or position), tutorial step number (or nil)
	local function pick(depth)
		local mined, tut, pickTier, pack = attr("Mined", 0), attr("Tut", 0), attr("Pick", 1), attr("Pack", 1)
		local coins, bag, bagMax, best = attr("Coins", 0), attr("Bag", 0), attr("BagMax", 20), attr("Best", 0)
		local have = coins + attr("BagValue", 0)
		local underground = depth > 5
		local full = bag >= bagMax
		local sellPad = tagged("SellPad")
		local function sellStep(step)
			if underground then
				return if isTouch then "⬆ Tap SURFACE to sell!" else "⬆ Press R to go sell!", nil, step
			end
			return "💰 Sell your ores!", sellPad, step
		end
		local function earn(step, goalText, price)
			if full or (bag > 0 and have >= price) then
				return sellStep(step)
			end
			return `⛏ {goalText} ({fmt(have)}/{fmt(price)})`, mineCenter, step
		end
		if mined < 5 then
			return "⛏ Dig into the ground!", mineCenter, 1
		end
		if tut < 2 then
			if bag >= math.min(10, bagMax) then
				return sellStep(2)
			end
			return `🎒 Fill your backpack! ({bag}/{math.min(10, bagMax)})`, mineCenter, 2
		end
		local p2 = CFG.picks[2]
		if pickTier < 2 then
			if coins >= p2.price then
				return `⛏ Buy the {p2.name}!`, pedestal("Pick", 2), 3
			end
			return earn(3, "Dig coins for a " .. p2.name, p2.price)
		end
		local b2 = CFG.bags[2]
		if pack < 2 then
			if coins >= b2.price then
				return `🎒 Buy the {b2.name}!`, pedestal("Bag", 2), 4
			end
			return earn(4, "Dig coins for a " .. b2.name, b2.price)
		end
		local egg = CFG.eggs[1]
		if attr("PetIndex", 0) == 0 then
			if coins >= egg.price then
				return "🥚 Hatch your first pet!", tagged("EggStand", function(e)
					return e:GetAttribute("Egg") == 1
				end), 5
			end
			return earn(5, "Dig coins for a pet egg", egg.price)
		end
		if best < 20 then
			if full then
				return sellStep(6)
			end
			return `⬇ Dig down to 20m! ({best}m)`, mineCenter, 6
		end
		if attr("LastDay", -1) ~= math.floor(workspace:GetServerTimeNow() / 86400) then
			return "🎁 Open your FREE daily chest!", tagged("DailyChest"), 7
		end
		-- after the tutorial: always the next goal
		if full then
			return sellStep(nil)
		end
		local nextPick = CFG.picks[pickTier + 1]
		if nextPick and coins >= nextPick.price then
			return `⛏ Buy the {nextPick.name}!`, pedestal("Pick", pickTier + 1), nil
		end
		local nextBag = CFG.bags[pack + 1]
		if nextBag and coins >= nextBag.price and (not nextPick or nextBag.price <= nextPick.price * 0.5) then
			return `🎒 Buy the {nextBag.name}!`, pedestal("Bag", pack + 1), nil
		end
		if best >= CFG.maxDepth then
			return "⭐ ASCEND at the shrine!", tagged("Shrine"), nil
		end
		for _, L in CFG.layers do
			if L.from > best then
				return `⬇ Reach {L.from}m: {L.name}!`, mineCenter, nil
			end
		end
		return `⬇ Reach {CFG.maxDepth}m to Ascend!`, mineCenter, nil
	end

	updateObjective = function(depth)
		local text, target, step = pick(depth)
		currentTarget = target
		if text ~= current then
			local first = current == ""
			current = text
			objText.Text = text
			stepLabel.Text = if step then `STEP {step} / {TUTORIAL_STEPS}` else ""
			bannerScale.Scale = 0.6
			tween(bannerScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			if not first then
				playSound("Pop", 1.2)
			end
		end
	end

	-- red chevrons that scroll along the ground towards the objective
	local arrowFolder = Instance.new("Folder")
	arrowFolder.Name = "DigArrows"
	arrowFolder.Parent = workspace
	local ARROWS, SPACING = 34, 3.6
	local arrows = {}
	for k = 1, ARROWS do
		local pair = {}
		for side = -1, 1, 2 do
			local bar = Instance.new("Part")
			bar.Anchored = true
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CanTouch = false
			bar.CastShadow = false
			bar.Size = Vector3.new(0.45, 0.2, 1.5)
			bar.Color = Color3.fromRGB(255, 45, 45)
			bar.Material = Enum.Material.SmoothPlastic
			bar.Transparency = 1
			bar.Parent = arrowFolder
			pair[side] = bar
		end
		arrows[k] = pair
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	local function hideFrom(k)
		for i = k, ARROWS do
			arrows[i][-1].Transparency = 1
			arrows[i][1].Transparency = 1
		end
	end
	updateArrows = function(depth)
		local root = getRoot()
		local goal = posOf(currentTarget)
		if not root or not goal then
			hideFrom(1)
			return
		end
		local start = root.Position - Vector3.new(0, 2.8, 0)
		-- underground players get "press surface" instead of arrows through rock
		if depth > 5 and goal.Y > CFG.top - 8 then
			hideFrom(1)
			return
		end
		local flat = Vector3.new(goal.X - start.X, 0, goal.Z - start.Z)
		local dist = flat.Magnitude
		if dist < 6 then
			hideFrom(1)
			return
		end
		local dir = flat.Unit
		groundParams.FilterDescendantsInstances = { arrowFolder, player.Character or arrowFolder }
		local offset = (os.clock() * 5) % SPACING
		local shown = 0
		for k = 1, ARROWS do
			local along = 2.5 + offset + (k - 1) * SPACING
			if along > dist - 3 then
				break
			end
			local p = start + dir * along
			local hit = workspace:Raycast(p + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), groundParams)
			local y = if hit then hit.Position.Y + 0.25 else start.Y + 0.25
			local base = CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z) + dir)
			for side = -1, 1, 2 do
				local bar = arrows[k][side]
				bar.CFrame = base * CFrame.new(side * 0.45, 0, 0.35) * CFrame.Angles(0, side * math.rad(-40), 0)
				bar.Transparency = if k == 1 then 0.5 else 0
			end
			shown = k
		end
		hideFrom(shown + 1)
	end
end

local function updateSimHUD()
	local now = workspace:GetServerTimeNow()
	local nextPick = CFG.picks[attr("Pick", 1) + 1]
	if nextPick then
		local have = attr("Coins", 0) + attr("BagValue", 0)
		goalFill.Size = UDim2.fromScale(math.clamp(have / nextPick.price, 0, 1), 1)
		goalText.Text = `⛏ Next: {nextPick.name} · {math.floor(math.clamp(have / nextPick.price, 0, 1) * 100)}%`
	else
		goalFill.Size = UDim2.fromScale(math.clamp(attr("Best", 0) / CFG.maxDepth, 0, 1), 1)
		goalText.Text = `⭐ Next: reach {CFG.maxDepth}m to Ascend`
	end
	if windows.Quests_reset then
		windows.Quests_reset()
	end
	local lvl, xp, need = attr("Level", 1), attr("XP", 0), attr("XPNeed", 30)
	levelText.Text = `Lv {lvl}  ·  {fmt(xp)} / {fmt(need)} XP`
	levelFill.Size = UDim2.fromScale(math.clamp(xp / math.max(1, need), 0, 1), 1)
	for _, pdef in POTIONS do
		local left = attr("Potion_" .. pdef.key, 0) - now
		local pill = potionPills[pdef.key]
		pill.Parent.Visible = left > 0
		if left > 0 then
			pill.Text = `{pdef.icon} {clock(left)}`
		end
	end
	local spinReady = now >= attr("SpinAt", 0)
	stackButtons.Spin.Badge.Visible = spinReady
	if spinLabel and not wheelSpinning then
		spinLabel.Text = if spinReady then "SPIN!" else "⏳ " .. clock(attr("SpinAt", 0) - now)
	end
	offerButton.Visible = not attr("Starter", false)
	sellButton.Visible = attr("Pass_SellAnywhere", false) and attr("Bag", 0) > 0
	autoButton.Visible = attr("Pass_AutoMine", false)
end

-- Tell the player when their coins plus the ore in their bag can pay for the next pickaxe.
local announcedTier = attr("Pick", 1)
local function checkAfford()
	local owned = attr("Pick", 1)
	if owned > announcedTier then
		announcedTier = owned
	end
	local nextPick = CFG.picks[owned + 1]
	if nextPick and owned + 1 > announcedTier and attr("Coins", 0) + attr("BagValue", 0) >= nextPick.price and attr("Tut", 0) >= 2 then
		announcedTier = owned + 1
		toast(if attr("Coins", 0) >= nextPick.price
			then `⛏ You can buy the {nextPick.name}!`
			else `⛏ Sell your bag to buy the {nextPick.name}!`, GOLD)
		playSound("Buy", 1.3)
	end
end

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------
local slowTimer = 0
local gaugeShown = false

RunService.RenderStepped:Connect(function(dt)
	updateMining()
	updatePets(dt)
	updateArrows(currentDepth())

	local depth = currentDepth()
	local now = workspace:GetServerTimeNow()
	local t = os.clock()

	-- Lighting
	local target = if skyOpen then math.clamp((depth - 6) / 30, 0, 0.35) else math.clamp(depth / 8, 0, 1)
	dark += (target - dark) * (1 - math.exp(-dt * 3))
	Lighting.Ambient = baseAmbient:Lerp(DEEP_AMBIENT, dark)
	if ambienceSounds.Surface then
		ambienceSounds.Surface.Volume = 0.45 * (1 - dark)
		ambienceSounds.Cave.Volume = 0.6 * dark
	end
	musicSound.Volume = 0.35 * (1 - 0.5 * dark)
	Lighting.OutdoorAmbient = baseOutdoor:Lerp(DEEP_OUTDOOR, dark)
	local layer = CFG.layers[layerIndexAt(depth)]
	local tint = WHITE:Lerp(rgb(layer.tint), dark)
	local rush = now % CFG.rushEvery < CFG.rushLength
	if rush then
		tint = tint:Lerp(Color3.fromRGB(255, 226, 150), 0.25)
	end
	grade.TintColor = grade.TintColor:Lerp(tint, 1 - math.exp(-dt * 4))
	grade.Contrast = 0.05 + 0.08 * dark
	grade.Saturation = 0

	-- Camera shake (swings, finds and earthquakes)
	local hum = getHumanoid()
	local quakeAt = workspace:GetAttribute("QuakeAt")
	local quake = 0
	if type(quakeAt) == "number" and quakeAt > now and settings.shake then
		quake = math.clamp(1 - (quakeAt - now) / 20, 0.15, 1) * 0.7
	end
	shake = math.max(0, shake - dt * 2.5)
	local amount = shake + quake
	if hum then
		if amount > 0.001 then
			hum.CameraOffset = Vector3.new(math.random(-100, 100) / 100, math.random(-100, 100) / 100, math.random(-100, 100) / 100) * amount
		elseif hum.CameraOffset ~= Vector3.zero then
			hum.CameraOffset = Vector3.zero
		end
	end

	-- Spinning displays
	for model, s in spinning do
		if model.Parent then
			model:PivotTo(CFrame.new(s.pivot.Position + Vector3.new(0, math.sin(t * 2 + s.phase) * 0.3, 0)) * CFrame.Angles(0, t * 0.9 + s.phase, 0) * s.pivot.Rotation)
		end
	end

	-- Depth gauge + surface button
	local underground = depth > 5 or (depth > 0 and not skyOpen)
	if underground ~= gaugeShown then
		gaugeShown = underground
		gauge.Visible = underground
		surfaceButton.Visible = underground
	end
	if underground then
		marker.Position = UDim2.fromScale(0.5, math.clamp(depth / CFG.maxDepth, 0, 1))
		bestTick.Position = UDim2.fromScale(0.5, math.clamp(attr("Best", 0) / CFG.maxDepth, 0, 1))
		depthLabel.Text = depth .. "m"
		layerLabel.Text = layer.name
	end

	-- Slower updates
	slowTimer += dt
	if slowTimer >= 0.25 then
		slowTimer = 0
		if type(quakeAt) == "number" and quakeAt > now then
			eventLabel.Text = `⚠ EARTHQUAKE IN {math.ceil(quakeAt - now)}s`
			eventLabel.TextColor3 = RED
		elseif rush then
			eventLabel.Text = `✨ GOLD RUSH · {clock(CFG.rushLength - now % CFG.rushEvery)}`
			eventLabel.TextColor3 = if math.floor(t * 3) % 2 == 0 then GOLD else WHITE
		else
			eventLabel.Text = `Gold Rush in {clock(CFG.rushEvery - now % CFG.rushEvery)}`
			eventLabel.TextColor3 = Color3.fromRGB(225, 225, 232)
		end
		checkSky()
		checkAfford()
		updateSimHUD()
		updateObjective(depth)
		refreshStations()
		updateTutorial(depth)
	end
end)

refreshShops()
refreshMuseum()
