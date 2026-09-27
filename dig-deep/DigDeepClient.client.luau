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

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("DigRemotes")
local CFG = HttpService:JSONDecode(Remotes:WaitForChild("DigConfig").Value)
local TreasureModels = ReplicatedStorage:WaitForChild("DigTreasures")
local mineFolder = workspace:WaitForChild("Mine")

-- Swap in your own sound ids here (rbxassetid://123...). A missing sound just stays silent.
local SOUNDS = {
	Swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.18 },
	Break = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.5 },
	Pickup = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25 },
	Sell = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6 },
	Treasure = { id = "rbxasset://sounds/unsheath.wav", volume = 0.8 },
	Buy = { id = "rbxasset://sounds/unsheath.wav", volume = 0.6 },
	Full = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.3 },
}

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

local function playSound(name, pitch)
	local def = SOUNDS[name]
	if not def or def.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = def.volume
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
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
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
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
	Position = UDim2.new(0.5, 0, 0, 88),
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
	shake = math.max(shake, amount)
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
local spinning = {}
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

local function refreshShops()
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

local function refreshMuseum()
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

local function refreshStations()
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

for _, name in { "Coins", "Pick", "Pack" } do
	player:GetAttributeChangedSignal(name):Connect(refreshShops)
end

--------------------------------------------------------------------------------
-- TUTORIAL: hints + a guide beam, no windows
--------------------------------------------------------------------------------
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
local guideStart = nil

local function findPedestal(kind, tier)
	for _, p in CollectionService:GetTagged("ShopItem") do
		if p:GetAttribute("Kind") == kind and p:GetAttribute("Tier") == tier and p.Parent and p.Parent:IsA("BasePart") then
			return p.Parent
		end
	end
	return nil
end

local function updateTutorial(depth)
	local tut = attr("Tut", 0)
	local full = attr("Bag", 0) >= attr("BagMax", 20)
	local nextPick = CFG.picks[attr("Pick", 1) + 1]
	local canAfford = nextPick ~= nil and attr("Coins", 0) >= nextPick.price
	local root = getRoot()
	local target = nil

	if full and depth > 0 then
		setHint(if isTouch then "Bag full! Tap ⬆ to sell" else "Bag full! Press R or ⬆ to sell")
	elseif tut == 0 then
		setHint(if isTouch then "Hold your finger on the ground to dig" else "Hold Left Click on the ground to dig")
	elseif tut == 2 and canAfford and depth == 0 then
		setHint("New pickaxe ready! Follow the light")
		target = findPedestal("Pick", attr("Pick", 1) + 1)
	else
		setHint("")
	end

	if target and root then
		if not guideStart or guideStart.Parent ~= root then
			guideStart = Instance.new("Attachment")
			guideStart.Name = "DigGuide"
			guideStart.Parent = root
		end
		guideEnd.Position = target.Position + Vector3.new(0, 2, 0)
		guideBeam.Attachment0 = guideStart
		guideBeam.Attachment1 = guideEnd
		guideBeam.Enabled = (target.Position - root.Position).Magnitude > 8
	else
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

-- A chunky, bouncy button with a vertical gradient and a thick outline.
local function cartoonButton(parent, props)
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
	}, { corner(props.radius or UDim.new(0.25, 0)), stroke(props.strokeSize or 3.5, INK) })
	local grad = gradient(b, props.top, props.bottom)
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
		label({ parent = b, text = props.text, size = props.textSize or 20, z = (props.z or 1) + 1 })
	end
	if props.onClick then
		b.Activated:Connect(function()
			playSound("Pickup", 1.4)
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
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.62, 0, 0.66, 0),
		BackgroundColor3 = Color3.fromRGB(255, 250, 240),
		Visible = false,
		Parent = windowsGui,
	}, {
		corner(UDim.new(0, 26)),
		stroke(5, INK),
		create("UISizeConstraint", { MaxSize = Vector2.new(780, 520), MinSize = Vector2.new(320, 300) }),
		create("UIScale", {}),
	})
	gradient(w, Color3.fromRGB(255, 252, 244), Color3.fromRGB(236, 226, 210))
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundColor3 = WHITE,
		Parent = w,
	}, { corner(UDim.new(0, 26)), stroke(5, INK) })
	gradient(header, top, bottom)
	label({ parent = header, text = title, size = 34, z = 2 })
	cartoonButton(header, {
		name = "Close",
		sz = UDim2.fromOffset(50, 50),
		anchor = Vector2.new(0.5, 0.5),
		pos = UDim2.new(1, -14, 0, 8),
		top = Color3.fromRGB(255, 110, 100),
		bottom = Color3.fromRGB(220, 40, 50),
		radius = UDim.new(1, 0),
		text = "✖",
		textSize = 26,
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
	Size = UDim2.fromOffset(160, 330),
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

-- Level bar under the coins ------------------------------------------------------
local levelRow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
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
	Position = UDim2.new(0.5, 0, 0, 112),
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
		then ColorSequence.new(Color3.fromRGB(120, 235, 120), Color3.fromRGB(40, 170, 70))
		else ColorSequence.new(Color3.fromRGB(200, 200, 210), Color3.fromRGB(130, 130, 145))
	toast(if autoMine then "🤖 Auto Mine ON" else "Auto Mine OFF", if autoMine then GREEN else WHITE)
end)

-- SHOP window -------------------------------------------------------------------
do
	local _, body = makeWindow("Shop", "🛒 SHOP", Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 150, 30))
	local tabs = create("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = body }, {
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	local scroll = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		create("UIGridLayout", { CellSize = UDim2.fromOffset(172, 200), CellPadding = UDim2.fromOffset(12, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
	})
	local cards = {}
	local function card(kind, item, order, tab)
		local c = create("Frame", { LayoutOrder = order, BackgroundColor3 = WHITE, Parent = scroll }, { corner(UDim.new(0, 18)), stroke(3.5, INK) })
		gradient(c, Color3.fromRGB(255, 255, 255), Color3.fromRGB(226, 234, 255))
		label({ parent = c, text = item.icon, size = 46, outline = false, sz = UDim2.new(1, 0, 0, 58), pos = UDim2.fromOffset(0, 6) })
		label({ parent = c, text = item.name, size = 19, sz = UDim2.new(1, -10, 0, 24), pos = UDim2.fromOffset(5, 64) })
		local desc = label({ parent = c, text = item.desc or "", size = 13, color = Color3.fromRGB(70, 70, 90), outline = false, wrap = true, sz = UDim2.new(1, -16, 0, 58), pos = UDim2.fromOffset(8, 88) })
		local btn = cartoonButton(c, {
			sz = UDim2.new(1, -24, 0, 38),
			pos = UDim2.new(0.5, 0, 1, -10),
			anchor = Vector2.new(0.5, 1),
			top = Color3.fromRGB(120, 235, 120),
			bottom = Color3.fromRGB(40, 170, 70),
			onClick = function()
				buy(kind, item)
			end,
		})
		local priceLabel = label({ parent = btn, text = "R$ " .. item.price, size = 19, z = 2 })
		table.insert(cards, { frame = c, kind = kind, item = item, tab = tab, price = priceLabel, button = btn, desc = desc })
	end
	for i, pass in CFG.passes do
		card("Pass", pass, i, "Passes")
	end
	for i, product in CFG.products do
		card("Product", product, i, if product.coinMinutes then "Coins" else "Boosts")
	end
	local current = "Passes"
	local tabButtons = {}
	local function refresh()
		local pick = CFG.picks[attr("Pick", 1)] or CFG.picks[1]
		for _, c in cards do
			c.frame.Visible = c.tab == current
			if c.kind == "Pass" and attr("Pass_" .. c.item.key, false) then
				c.price.Text = "OWNED ✔"
				c.button.Active = false
			elseif c.item.starter and attr("Starter", false) then
				c.price.Text = "R$ " .. c.item.price
			else
				c.price.Text = if c.item.id == 0 and not RunService:IsStudio() then "Soon" else "R$ " .. c.item.price
			end
			if c.item.coinMinutes then
				local income = CFG.income[attr("Pick", 1)] or CFG.income[1]
				c.desc.Text = "+ 💰 " .. fmt(income * c.item.coinMinutes * (1 + attr("Asc", 0) * CFG.ascendBonus))
			elseif c.item.key == "NextPick" then
				local nextPick = CFG.picks[attr("Pick", 1) + 1]
				c.desc.Text = if nextPick then "Get the " .. nextPick.name .. " right now" else "You have the best pickaxe!"
			elseif c.item.potion then
				c.desc.Text = `{c.item.minutes} minutes. Stacks up to 3 hours`
			end
		end
		for key, b in tabButtons do
			b.BackgroundTransparency = if key == current then 0 else 0.35
		end
		local _ = pick
	end
	for i, t in { { "Passes", "⭐ PASSES" }, { "Boosts", "🧪 BOOSTS" }, { "Coins", "💰 COINS" } } do
		local b = cartoonButton(tabs, {
			sz = UDim2.fromOffset(150, 42),
			order = i,
			top = Color3.fromRGB(120, 200, 255),
			bottom = Color3.fromRGB(50, 110, 230),
			text = t[2],
			textSize = 18,
			onClick = function()
				current = t[1]
				refresh()
			end,
		})
		tabButtons[t[1]] = b
	end
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
end
windows.Offer = nil

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

local function buildPet(id)
	local P = CFG.pets[id]
	local m = Instance.new("Model")
	m.Name = "Pet_" .. id
	if not P then
		return m
	end
	local c, acc = rgb(P.color), rgb(P.accent)
	local ball = Enum.PartType.Ball
	local body = petPart(m, Vector3.new(2.2, 2.2, 2.2), CFrame.new(), c, if P.jelly then Enum.Material.Glass else Enum.Material.SmoothPlastic, ball)
	if P.jelly then
		body.Transparency = 0.2
	end
	for _, x in { -0.42, 0.42 } do
		petPart(m, Vector3.new(0.62, 0.62, 0.62), CFrame.new(x, 0.25, -0.86), WHITE, nil, ball)
		petPart(m, Vector3.new(0.34, 0.34, 0.34), CFrame.new(x, 0.25, -1.08), Color3.fromRGB(20, 20, 26), nil, ball)
		petPart(m, Vector3.new(0.3, 0.2, 0.1), CFrame.new(x * 1.5, -0.15, -0.95), acc, nil, nil).Transparency = 0.3
	end
	if P.ears == "round" then
		for _, x in { -0.7, 0.7 } do
			petPart(m, Vector3.new(0.75, 0.75, 0.75), CFrame.new(x, 0.95, 0), c, nil, ball)
			petPart(m, Vector3.new(0.45, 0.45, 0.45), CFrame.new(x, 0.95, -0.2), acc, nil, ball)
		end
	elseif P.ears == "long" then
		for _, x in { -0.45, 0.45 } do
			petPart(m, Vector3.new(0.4, 1.5, 0.3), CFrame.new(x, 1.5, 0.1) * CFrame.Angles(0, 0, x * -0.3), c)
			petPart(m, Vector3.new(0.22, 1.1, 0.1), CFrame.new(x, 1.5, -0.06) * CFrame.Angles(0, 0, x * -0.3), acc)
		end
	elseif P.ears == "pointy" then
		for _, x in { -0.6, 0.6 } do
			petPart(m, Vector3.new(0.55, 0.9, 0.3), CFrame.new(x, 1.05, 0) * CFrame.Angles(0, 0, x * -0.6), c)
		end
	end
	if P.horns then
		for _, x in { -0.45, 0.45 } do
			petPart(m, Vector3.new(0.26, 0.8, 0.26), CFrame.new(x, 1.15, -0.2) * CFrame.Angles(-0.4, 0, x * -0.5), acc)
		end
	end
	if P.wings then
		for _, x in { -1, 1 } do
			petPart(m, Vector3.new(0.15, 1.2, 1.5), CFrame.new(x * 1.2, 0.35, 0.3) * CFrame.Angles(0, 0, x * -0.5), acc).Transparency = 0.1
		end
	end
	if P.tail then
		petPart(m, Vector3.new(0.45, 0.45, 1.2), CFrame.new(0, -0.3, 1.15) * CFrame.Angles(0.5, 0, 0), c)
	end
	if P.glow then
		local light = Instance.new("PointLight")
		light.Color = acc
		light.Range = 9
		light.Brightness = 1.4
		light.Parent = body
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = acc
		sp.Parent = body
	end
	m.PrimaryPart = body
	return m
end

-- Pets that follow every player (built locally for smooth movement) ---------------
local followers = {} -- [Player] = { ids = string, models = { Model } }
local function rebuildPets(plr)
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
	local models = {}
	for i, id in ids do
		local m = buildPet(id)
		m:ScaleTo(0.8)
		m.Parent = workspace
		models[i] = m
	end
	followers[plr] = { models = models, pos = {} }
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
local function updatePets(dt)
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
				m:PivotTo(CFrame.lookAt(cur, cur - Vector3.new(look.X, 0, look.Z).Unit * -1) * CFrame.Angles(0, math.pi, 0))
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
		info.Text = `{#list}/{CFG.maxPets} pets · equipped {equipped}/{attr("PetSlots", CFG.petSlots)} · +{math.floor(total * 100 + 0.5)}% coins`
	end
	player:GetAttributeChangedSignal("Pets"):Connect(refresh)
	player:GetAttributeChangedSignal("PetSlots"):Connect(refresh)
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
		playSound("Break", 0.8 + k * 0.2)
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
	local model = buildPet(petId)
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
		model:PivotTo(CFrame.Angles(0, (os.clock() - start) * 1.6, 0) * CFrame.new(0, math.sin((os.clock() - start) * 3) * 0.12, 0))
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
	playSound("Buy", 1.5)
	task.delay(2.2, function()
		tween(sc, 0.25, { Scale = 0 })
		tween(sub, 0.25, { TextTransparency = 1 })
		task.wait(0.3)
		big:Destroy()
		sub:Destroy()
	end)
end)

-- Slow HUD refresh (level bar, potions, badges, pass buttons) ----------------------
local function updateSimHUD()
	local now = workspace:GetServerTimeNow()
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

	local depth = currentDepth()
	local now = workspace:GetServerTimeNow()
	local t = os.clock()

	-- Lighting
	local target = if skyOpen then math.clamp((depth - 6) / 30, 0, 0.35) else math.clamp(depth / 8, 0, 1)
	dark += (target - dark) * (1 - math.exp(-dt * 3))
	Lighting.Ambient = baseAmbient:Lerp(DEEP_AMBIENT, dark)
	Lighting.OutdoorAmbient = baseOutdoor:Lerp(DEEP_OUTDOOR, dark)
	local layer = CFG.layers[layerIndexAt(depth)]
	local tint = WHITE:Lerp(rgb(layer.tint), dark)
	local rush = now % CFG.rushEvery < CFG.rushLength
	if rush then
		tint = tint:Lerp(Color3.fromRGB(255, 226, 150), 0.25)
	end
	grade.TintColor = grade.TintColor:Lerp(tint, 1 - math.exp(-dt * 4))
	grade.Contrast = 0.05 + 0.08 * dark
	grade.Saturation = 0.08

	-- Camera shake (swings, finds and earthquakes)
	local hum = getHumanoid()
	local quakeAt = workspace:GetAttribute("QuakeAt")
	local quake = 0
	if type(quakeAt) == "number" and quakeAt > now then
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
		refreshStations()
		updateTutorial(depth)
	end
end)

refreshShops()
refreshMuseum()
