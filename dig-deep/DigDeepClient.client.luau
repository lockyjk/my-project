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
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.fromOffset(0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local coinScale = create("UIScale", { Parent = coinRow })
local coinIcon = create("Frame", {
	LayoutOrder = 1,
	Size = UDim2.fromOffset(30, 30),
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
}, { stroke(3) })

local eventLabel = create("TextLabel", {
	Name = "Event",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 58),
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
	Size = UDim2.fromOffset(240, 36),
	BackgroundColor3 = Color3.fromRGB(20, 20, 26),
	BackgroundTransparency = 0.3,
	Parent = gui,
}, { corner(), stroke(1.5, WHITE, 0.85) })
local bagScale = create("UIScale", { Parent = bagPill })
local bagFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = GOLD,
	BackgroundTransparency = 0.1,
	ZIndex = 1,
	Parent = bagPill,
}, { corner() })
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
	Position = UDim2.new(1, -34, 0.46, 0),
	Size = UDim2.fromOffset(8, 250),
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
	Size = UDim2.fromOffset(78, 78),
	BackgroundColor3 = Color3.fromRGB(40, 150, 90),
	AutoButtonColor = true,
	Text = "",
	Visible = false,
	Parent = gui,
}, {
	corner(),
	stroke(3, INK, 0.1),
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
	Size = UDim2.fromOffset(600, 30),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 22,
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
	BackgroundColor3 = Color3.fromRGB(18, 16, 24),
	BackgroundTransparency = 0.2,
	Parent = gui,
}, {
	corner(),
	create("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) }),
})
local bannerStroke = create("UIStroke", { Thickness = 2, Color = GOLD, Parent = banner })
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
	bagFill.BackgroundColor3 = if full then RED else GOLD
	bagLabel.Text = if full then "🎒 FULL · SURFACE TO SELL" else `🎒 {fmt(count)} / {fmt(max)}`
	bagLabel.TextSize = if full then 15 else 18
	if count > lastBag then
		pulse(bagScale, 1.06)
	end
	lastBag = count
end
player:GetAttributeChangedSignal("Bag"):Connect(refreshBag)
player:GetAttributeChangedSignal("BagMax"):Connect(refreshBag)
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
			tween(banner, 0.45, { Position = UDim2.new(0.5, 0, 0, 90) }, Enum.EasingStyle.Back)
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
local activeTouch = nil
local touchPos = nil
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
	elseif input.KeyCode == Enum.KeyCode.R and currentDepth() > 0 then
		requestSurface()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input == activeTouch then
		touchPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	elseif input == activeTouch then
		activeTouch = nil
		touchPos = nil
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
	local holding = mouseHeld or activeTouch ~= nil
	local target, hitPos = nil, nil
	if hum and hum.Health > 0 and (holding or not isTouch) then
		target, hitPos = findTarget()
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

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------
local slowTimer = 0
local gaugeShown = false

RunService.RenderStepped:Connect(function(dt)
	updateMining()

	local depth = currentDepth()
	local now = workspace:GetServerTimeNow()
	local t = os.clock()

	-- Lighting
	local target = math.clamp(depth / 8, 0, 1)
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
	local underground = depth > 0
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
		refreshStations()
		updateTutorial(depth)
	end
end)

refreshShops()
refreshMuseum()
