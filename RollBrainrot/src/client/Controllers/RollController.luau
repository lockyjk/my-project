--!strict
-- The ROLL BRAINROT machine on the client:
--   * idle life: capsules jiggle in the dome, marquee bulbs chase, gears turn, the topper
--     spins, reward pedestals show every Brainrot with live odds
--   * the roll: camera close-up → machine shakes, lights flash → capsule drops down the
--     chute → names flash past → capsule cracks open → the Brainrot pops out with effects
--     that scale with rarity (Common: simple white … Secret: blackout, star burst, huge
--     pillar, rainbow lights) → reveal card
--   * Skip (after the first roll) and Fast Roll make it short; Auto Roll loops it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Animator = require(Modules:WaitForChild("Models"):WaitForChild("Animator"))
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local BrainrotModels = require(Modules.Models:WaitForChild("BrainrotModels"))
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Net = require(Modules:WaitForChild("Net"))
local Registry = require(Modules:WaitForChild("Registry"))
local RollMath = require(Modules:WaitForChild("RollMath"))

local CameraController = require(script.Parent.CameraController)
local ClientState = require(script.Parent.ClientState)
local Effects = require(script.Parent.Effects)
local Bus = require(script.Parent.Parent.UI.Bus)
local Notifications = require(script.Parent.Parent.UI.Notifications)
local RollUI = require(script.Parent.Parent.UI.RollUI)

local RollController = {}

local W = GameConfig.World
local player = Players.LocalPlayer
local NEAR_DIST = 70

local machine: Model? = nil
local busy = false
local autoOn = false
local capsuleBase: { [BasePart]: CFrame } = {}
local displayModels: { { model: Model, rig: Animator.Rig, base: CFrame, label: TextLabel, id: string } } = {}
local revealModel: Model? = nil
local revealRig: Animator.Rig? = nil
local revealSpin = 0

type Spinner = {
	part: BasePart,
	base: CFrame,
	children: { [BasePart]: CFrame },
	angle: number,
	speed: number,
	axis: (number) -> CFrame,
}
local spinners: { Spinner } = {}

local function collectSpinners(m: Model)
	for _, p in m:GetChildren() do
		local spin = p:GetAttribute("Spin")
		if p:IsA("BasePart") and type(spin) == "number" then
			local children = {}
			for _, c in p:GetChildren() do
				if c:IsA("BasePart") then
					children[c] = p.CFrame:ToObjectSpace(c.CFrame)
				end
			end
			local isGear = p.Name == "Gear"
			table.insert(spinners, {
				part = p,
				base = p.CFrame,
				children = children,
				angle = 0,
				speed = if isGear then 1.5 * spin else 2,
				axis = if isGear
					then function(a: number): CFrame
						return CFrame.Angles(a, 0, 0) -- cylinder axis is the part's X
					end
					else function(a: number): CFrame
						return CFrame.Angles(0, a, 0)
					end,
			})
		end
	end
end

local function rollSpeed(): number
	-- 1 = full animation; smaller = faster
	local d = ClientState.data
	local speed = 1
	if ClientState.hasPass("FastRoll") then
		speed *= GameConfig.Roll.FastAnimSeconds / GameConfig.Roll.AnimSeconds
	end
	local quick = BrainrotMath.upgradeValue(GameConfig.Upgrades.RollSpeed, d.upgrades and d.upgrades.RollSpeed or 0)
	speed *= 1 - quick
	if autoOn then
		speed *= 0.6
	end
	return math.max(0.25, speed)
end

-------------------------------------------------------------------------------
-- Machine parts helpers
-------------------------------------------------------------------------------
local function rarityLights(): { BasePart }
	local out = {}
	if machine then
		for i = 1, #Registry.Rarities do
			local p = machine:FindFirstChild(`RarityLight{i}`)
			if p and p:IsA("BasePart") then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function setLights(color: Color3?)
	for i, p in rarityLights() do
		p.Color = color or Registry.Rarities[i].color
	end
end

-------------------------------------------------------------------------------
-- Reward pedestals: live creature + odds label
-------------------------------------------------------------------------------
local function buildDisplays()
	local m = machine
	local pedestals = m and m:FindFirstChild("Pedestals")
	if not pedestals then
		return
	end
	local live = Workspace:WaitForChild("Live")
	for _, ped in pedestals:GetChildren() do
		local id = ped:GetAttribute("BrainrotId")
		local top = ped:GetAttribute("Top")
		if type(id) == "string" and typeof(top) == "Vector3" then
			local def = Registry.Brainrot[id]
			local model = BrainrotModels.build(id, "Normal")
			model.Parent = live
			local base = CFrame.lookAt(top, Vector3.new(W.Machine.X, top.Y, W.Machine.Z + 30))
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(200, 64)
			gui.StudsOffsetWorldSpace = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 4) + 2.5, 0)
			gui.MaxDistance = 120
			gui.LightInfluence = 0
			gui.Parent = model.PrimaryPart
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.RichText = true
			label.TextColor3 = Registry.Rarity[def.rarity].color
			label.Parent = gui
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2.5
			stroke.Parent = label
			table.insert(
				displayModels,
				{ model = model, rig = Animator.rig(model, def.idleQuirk), base = base, label = label, id = id }
			)
		end
	end
end

local function refreshDisplayOdds()
	local odds = RollMath.odds(ClientState.luck())
	local byRarity: { [string]: number } = {}
	for _, row in odds do
		byRarity[row.rarity.id] = row.chance
	end
	for _, d in displayModels do
		local def = Registry.Brainrot[d.id]
		local pool = #Registry.RollPool[def.rarity]
		local chance = (byRarity[def.rarity] or 0) / math.max(1, pool)
		d.label.Text = `{def.emoji} {def.name}\n<font size="18">{def.rarity} · {Format.chance(chance)}</font>`
	end
end

-------------------------------------------------------------------------------
-- The roll sequence
-------------------------------------------------------------------------------
local function makeCapsule(color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "RollCapsule"
	local function half(top: boolean): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 5
		p.Color = if top then color else Color3.fromRGB(250, 250, 255)
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Name = if top then "Top" else "Bottom"
		p.Parent = m
		return p
	end
	half(true)
	half(false)
	local band = Instance.new("Part")
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.6, 5.2, 5.2)
	band.Color = Color3.fromRGB(40, 36, 70)
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.Name = "Band"
	band.Parent = m
	return m
end

local function placeCapsule(capsule: Model, cf: CFrame, open: number)
	local top = capsule:FindFirstChild("Top") :: BasePart
	local bottom = capsule:FindFirstChild("Bottom") :: BasePart
	local band = capsule:FindFirstChild("Band") :: BasePart
	-- halves are full spheres offset apart; when closed they overlap into one capsule
	top.CFrame = cf * CFrame.new(0, 0.6 + open * 5, 0) * CFrame.Angles(0, 0, open * 1.2)
	bottom.CFrame = cf * CFrame.new(0, -0.6 - open * 2, 0)
	band.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	band.Transparency = if open > 0.05 then 1 else 0
end

local function clearReveal()
	if revealModel then
		revealModel:Destroy()
		revealModel = nil
		revealRig = nil
	end
end

local function playSequence(payload: { [string]: any }, skip: boolean)
	local m = machine
	local rarity = Registry.Rarity[payload.rarity]
	local tier = rarity.fxTier
	local revealPoint = (m and m:GetAttribute("RevealPoint")) :: Vector3? or (W.Machine + Vector3.new(0, 12, 22))
	local camPoint = (m and m:GetAttribute("CameraPoint")) :: Vector3? or (W.Machine + Vector3.new(0, 17, 54))
	clearReveal()
	if skip then
		Effects.sound(if tier >= 4 then "RevealBig" else "Reveal", 0.6)
		if tier >= 4 then
			Effects.confetti(40 + tier * 10, { rarity.color, rarity.glow })
			Effects.flash(rarity.color, 0.35, 0.4)
		end
		RollUI.showReveal(payload)
		return
	end
	local speed = rollSpeed()
	local function wait(t: number)
		task.wait(t * speed)
	end
	-- 1) camera close-up
	CameraController.focus("Roll", CFrame.lookAt(camPoint, revealPoint + Vector3.new(0, 8, -14)), 0.6 * speed, 55)
	if tier >= 6 then
		Effects.darken(0.75, 0.8 * speed) -- the secret build-up starts dark
	end
	-- 2) machine rumbles, lights strobe through rarity colours
	local capsule = makeCapsule(Color3.fromRGB(255, 255, 255))
	capsule.Parent = Effects.folder()
	local domeTop = W.Machine + Vector3.new(0, 26, 0)
	local shakeEnd = os.clock() + 1.1 * speed
	local lights = rarityLights()
	Effects.sound("RollShake", 0.5)
	while os.clock() < shakeEnd do
		local k = 1 - (shakeEnd - os.clock()) / (1.1 * speed)
		placeCapsule(
			capsule,
			CFrame.new(domeTop + Vector3.new(math.sin(os.clock() * 40) * 1.4, -6 + math.cos(os.clock() * 33), 0))
				* CFrame.Angles(os.clock() * 8, 0, os.clock() * 5),
			0
		)
		for i, p in lights do
			local r = Registry.Rarities[((i + math.floor(os.clock() * 18)) % #Registry.Rarities) + 1]
			p.Color = r.color
		end
		for part, base in capsuleBase do
			part.CFrame = base * CFrame.new((math.random() - 0.5) * 1.2 * k, (math.random() - 0.5) * 1.2 * k, 0)
		end
		Effects.shake(0.15 + k * 0.25, 0.1)
		RunService.RenderStepped:Wait()
	end
	for part, base in capsuleBase do
		part.CFrame = base
	end
	-- 3) capsule drops down the chute and rolls out to the reveal point
	local start = os.clock()
	local dropTime = 0.55 * speed
	local from = domeTop + Vector3.new(0, -8, 0)
	while true do
		local t = math.min(1, (os.clock() - start) / dropTime)
		local p = from:Lerp(revealPoint, t) + Vector3.new(0, math.sin(t * math.pi) * 6, 0)
		placeCapsule(capsule, CFrame.new(p) * CFrame.Angles(t * 9, 0, 0), 0)
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	Effects.sound("Jump", 0.5, revealPoint)
	Effects.burst(revealPoint, Color3.new(1, 1, 1), 12, "smoke", 10, 2)
	-- 4) the names flash past while the capsule wobbles
	local cycleTime = (if tier >= 6 then 2.4 elseif tier >= 4 then 1.8 else 1.3) * speed
	local cycleDone = false
	task.spawn(function()
		RollUI.cycle(cycleTime, payload.id, payload.mut)
		cycleDone = true
	end)
	local wobbleStart = os.clock()
	while not cycleDone do
		local t = os.clock() - wobbleStart
		local amp = math.min(1, t / cycleTime) * (0.25 + tier * 0.05)
		placeCapsule(
			capsule,
			CFrame.new(revealPoint) * CFrame.Angles(math.sin(t * 25) * amp, 0, math.cos(t * 21) * amp),
			0
		)
		RunService.RenderStepped:Wait()
	end
	-- 5) colour reveal: capsule + lights switch to the rarity colour
	local top = capsule:FindFirstChild("Top") :: BasePart
	top.Color = rarity.color
	top.Material = Enum.Material.Neon
	setLights(rarity.color)
	if tier >= 6 then
		Effects.darken(0.92, 0.3)
		wait(0.5)
	end
	-- 6) crack open
	local openStart = os.clock()
	local openTime = 0.35 * speed
	while true do
		local t = math.min(1, (os.clock() - openStart) / openTime)
		placeCapsule(capsule, CFrame.new(revealPoint), t)
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	for _, p in capsule:GetChildren() do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
	end
	task.delay(0.45, function()
		capsule:Destroy()
	end)
	-- 7) the Brainrot pops out + rarity effects
	local model = BrainrotModels.build(payload.id, payload.mut)
	model.Parent = Effects.folder()
	revealModel = model
	revealRig = Animator.rig(model, Registry.Brainrot[payload.id].idleQuirk)
	revealSpin = 0
	local h = (model:GetAttribute("Height") :: number?) or 4
	local scale = math.clamp(7 / h, 1, 2.2)
	model:ScaleTo(scale * 0.05)
	local grow = Instance.new("NumberValue")
	grow.Value = 0.05
	grow.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(scale * math.max(0.05, v))
		end
	end)
	TweenService:Create(grow, TweenInfo.new(0.5 * speed, Enum.EasingStyle.Back), { Value = 1 }):Play()
	Effects.sound(if tier >= 4 then "RevealBig" else "Reveal", 0.7)
	Effects.burst(
		revealPoint + Vector3.new(0, 3, 0),
		rarity.color,
		20 + tier * 15,
		"sparkle",
		20 + tier * 6,
		1 + tier * 0.25
	)
	if tier >= 2 then
		Effects.ring(revealPoint - Vector3.new(0, 8, 0), 20 + tier * 8, rarity.color, 0.6)
	end
	if tier >= 3 then
		Effects.pillar(revealPoint - Vector3.new(0, 10, 0), rarity.color, 80 + tier * 30, 6 + tier, 1.6)
		Effects.confetti(20 + tier * 12, { rarity.color, rarity.glow, Color3.new(1, 1, 1) })
	end
	if tier >= 4 then
		Effects.shake(0.6 + (tier - 4) * 0.5, 0.6 + (tier - 4) * 0.4)
		Effects.flash(rarity.glow, 0.45, 0.6)
	end
	if tier >= 5 then
		Effects.ring(revealPoint - Vector3.new(0, 8, 0), 60, rarity.glow, 0.9, 10)
		Effects.blast(revealPoint, 18, rarity.color, 0.5)
	end
	if tier >= 6 then
		Effects.darken(0, 1.2)
		Effects.flash(Color3.new(1, 1, 1), 0.9, 1.2)
		Effects.shake(2.2, 1.6)
		Effects.burst(revealPoint, Color3.fromRGB(255, 255, 255), 120, "sparkle", 60, 3)
		Effects.pillar(revealPoint - Vector3.new(0, 10, 0), Color3.fromRGB(255, 120, 255), 400, 30, 3)
		task.spawn(function()
			for i = 1, 30 do
				setLights(Color3.fromHSV((i * 0.07) % 1, 0.8, 1))
				Effects.ring(
					revealPoint - Vector3.new(0, 8, 0),
					40 + i * 4,
					Color3.fromHSV((i * 0.07) % 1, 0.7, 1),
					0.8,
					4
				)
				task.wait(0.08)
			end
		end)
		Effects.confetti(220)
	end
	if payload.isNew then
		Effects.floatText(revealPoint + Vector3.new(0, h * scale + 3, 0), "NEW!", Color3.fromRGB(255, 230, 80), 8, 4)
	end
	wait(0.6)
	RollUI.hideCycler()
	RollUI.showReveal(payload)
end

local function finish()
	CameraController.release("Roll", 0.5)
	RollUI.hideCycler()
	setLights(nil)
	Effects.darken(0, 0.3)
	RollUI.setRolling(false)
	busy = false
end

function RollController.roll()
	if busy then
		return
	end
	if not ClientState.loaded then
		return
	end
	busy = true
	RollUI.setRolling(true)
	RollUI.hideReveal()
	local useToken = (ClientState.data.tokens or 0) > 0
	local ok, result = Net.Client.invoke("Roll", useToken)
	if not ok then
		Notifications.toast(tostring(result or "Can't roll right now"), Color3.fromRGB(255, 90, 90))
		Effects.sound("Error", 0.4)
		autoOn = false
		RollUI.auto = false
		finish()
		return
	end
	local skip = ClientState.data.seenRollAnim == true
		and ClientState.data.settings
		and ClientState.data.settings.skipRoll == true
	local okSeq, err = (pcall :: any)(playSequence, result, skip)
	if not okSeq then
		warn(`[Roll] animation error: {err}`)
		RollUI.showReveal(result)
	end
	if not ClientState.data.seenRollAnim then
		Net.Client.invoke("SetSetting", "seenRollAnim", true)
	end
	finish()
	if autoOn then
		task.delay(GameConfig.Roll.AutoRollDelay + (if skip then 0.4 else 0.9), function()
			if autoOn and not busy then
				RollUI.hideReveal()
				clearReveal()
				RollController.roll()
			end
		end)
	end
end

function RollController.start()
	local world = Workspace:WaitForChild("World")
	task.spawn(function()
		machine = world:WaitForChild("RollMachine", 60) :: Model?
		local m = machine
		if not m then
			return
		end
		local capsules = m:WaitForChild("Capsules", 10)
		if capsules then
			for _, c in capsules:GetDescendants() do
				if c:IsA("BasePart") then
					capsuleBase[c] = c.CFrame
				end
			end
		end
		collectSpinners(m)
		buildDisplays()
		refreshDisplayOdds()
	end)

	RollUI.onRoll = function()
		RollController.roll()
	end
	RollUI.onAutoChanged = function(on: boolean)
		autoOn = on
		if on and not busy then
			RollController.roll()
		end
	end
	Bus.PromptAction:Connect(function(action: string)
		if action == "Roll" then
			RollController.roll()
		end
	end)
	player:GetAttributeChangedSignal("Luck"):Connect(refreshDisplayOdds)

	-- idle animation + proximity panel
	local lastNear = false
	local frame = 0
	RunService.Heartbeat:Connect(function(dt: number)
		frame += 1
		local now = os.clock()
		local m = machine
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local isNear = root ~= nil
			and (root.Position - W.Machine).Magnitude < NEAR_DIST
			and player:GetAttribute("BattleId") == nil
		if isNear ~= lastNear then
			lastNear = isNear
			RollUI.setNear(isNear)
		end
		if not m then
			return
		end
		local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
		if (camPos - W.Machine).Magnitude > 400 then
			return
		end
		-- capsules gently tumbling (skip while the roll shakes them)
		if not busy and frame % 2 == 0 then
			for part, base in capsuleBase do
				local o = base.Position.X * 0.37 + base.Position.Z * 0.21
				part.CFrame = base
					* CFrame.new(0, math.sin(now * 2 + o) * 0.25, 0)
					* CFrame.Angles(math.sin(now + o) * 0.2, 0, 0)
			end
		end
		-- marquee chase
		local marquee = m:FindFirstChild("Marquee")
		if marquee and frame % 6 == 0 then
			local step = math.floor(now * 8)
			for _, b in marquee:GetChildren() do
				if b:IsA("BasePart") then
					local n = tonumber(string.match(b.Name, "%d+")) or 0
					b.Transparency = if (n + step) % 4 == 0 then 0.6 else 0
				end
			end
		end
		-- spinning bits (gears carry their teeth around with them)
		for _, sp in spinners do
			sp.angle += dt * sp.speed
			local rot = sp.base * sp.axis(sp.angle)
			sp.part.CFrame = rot
			for child, rel in sp.children do
				child.CFrame = rot * rel
			end
		end
		-- reward displays
		for i, d in displayModels do
			Animator.update(d.rig, d.base, now + i, false)
		end
		-- the freshly revealed Brainrot spins proudly at the reveal point
		local rm, rr = revealModel, revealRig
		if rm and rr and rm.Parent then
			revealSpin += dt * 1.2
			local point = (m:GetAttribute("RevealPoint") :: Vector3?) or W.Machine
			Animator.update(
				rr,
				CFrame.new(point - Vector3.new(0, 1, 0)) * CFrame.Angles(0, revealSpin + math.pi, 0),
				now,
				false
			)
		end
		if rm and not RollUI.isRevealOpen() and not busy then
			clearReveal()
		end
	end)
end

return RollController
