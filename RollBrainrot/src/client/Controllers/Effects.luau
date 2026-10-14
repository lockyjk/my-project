--!strict
-- Client-only juice: camera shake, screen flashes/darkening, confetti, floating numbers,
-- particle bursts, shockwave rings, beams, lobbed projectiles and positional sounds.
-- Everything is pooled or self-cleaning and skipped when far from the camera.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Theme = require(Modules:WaitForChild("Theme"))

local Effects = {}

local player = Players.LocalPlayer
local fxFolder: Folder
local screen: ScreenGui
local flashFrame: Frame
local darkFrame: Frame
local shakeAmp = 0
local shakeUntil = 0
Effects.sfxEnabled = true

local function camera(): Camera
	return Workspace.CurrentCamera :: Camera
end

-- Is a world point close enough to bother drawing effects for?
function Effects.near(pos: Vector3, dist: number?): boolean
	return (camera().CFrame.Position - pos).Magnitude < (dist or 500)
end

-------------------------------------------------------------------------------
-- Camera shake (applied after the default camera each frame)
-------------------------------------------------------------------------------
function Effects.shake(amplitude: number, duration: number)
	shakeAmp = math.max(shakeAmp, amplitude)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

-------------------------------------------------------------------------------
-- Screen effects
-------------------------------------------------------------------------------
function Effects.flash(color: Color3, alpha: number?, duration: number?)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - (alpha or 0.6)
	TweenService:Create(flashFrame, TweenInfo.new(duration or 0.4), { BackgroundTransparency = 1 }):Play()
end

function Effects.darken(alpha: number, duration: number)
	TweenService:Create(darkFrame, TweenInfo.new(duration), { BackgroundTransparency = 1 - alpha }):Play()
end

function Effects.confetti(count: number, colors: { Color3 }?)
	local palette = colors
		or {
			Theme.Colors.Primary,
			Theme.Colors.Secondary,
			Theme.Colors.Coins,
			Theme.Colors.Good,
			Color3.fromRGB(190, 110, 255),
		}
	for _ = 1, count do
		local piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = palette[math.random(1, #palette)]
		local s = math.random(8, 16)
		piece.Size = UDim2.fromOffset(s, s * 0.6)
		piece.Position = UDim2.new(math.random(), 0, -0.05, 0)
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 50
		piece.Parent = screen
		local t = math.random(18, 32) / 10
		TweenService:Create(piece, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.3, 0, 1.1, 0),
			Rotation = piece.Rotation + math.random(-540, 540),
		}):Play()
		Debris:AddItem(piece, t)
	end
end

-------------------------------------------------------------------------------
-- Sounds
-------------------------------------------------------------------------------
local soundCache: { [string]: Sound } = {}

function Effects.sound(name: string, volume: number?, pos: Vector3?, pitch: number?)
	if not Effects.sfxEnabled then
		return
	end
	local id = GameConfig.Sounds[name]
	if not id or id == "" then
		return
	end
	if pos then
		if not Effects.near(pos, 300) then
			return
		end
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Position = pos
		holder.Parent = fxFolder
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.PlaybackSpeed = pitch or 1
		s.RollOffMaxDistance = 300
		s.Parent = holder
		s:Play()
		Debris:AddItem(holder, 4)
		return
	end
	local s = soundCache[name]
	if not s then
		local created = Instance.new("Sound")
		created.SoundId = id
		created.Parent = SoundService
		soundCache[name] = created
		s = created
	end
	local snd = s :: Sound
	snd.Volume = volume or 0.6
	snd.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(snd)
end

-------------------------------------------------------------------------------
-- World effects
-------------------------------------------------------------------------------
local function fxPart(shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = fxFolder
	return p
end
Effects.part = fxPart

-- Expanding flat ring / disc (shockwaves, AoE impacts)
function Effects.ring(pos: Vector3, radius: number, color: Color3, duration: number?, startRadius: number?)
	if not Effects.near(pos, 700) then
		return
	end
	local d = duration or 0.45
	local disc = fxPart(
		Enum.PartType.Cylinder,
		Vector3.new(0.4, (startRadius or 1) * 2, (startRadius or 1) * 2),
		CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	disc.Transparency = 0.25
	TweenService:Create(disc, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(disc, d + 0.05)
end

-- Sphere that blooms and fades (explosions)
function Effects.blast(pos: Vector3, radius: number, color: Color3, duration: number?)
	if not Effects.near(pos, 700) then
		return
	end
	local d = duration or 0.35
	local ball = fxPart(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(pos), color)
	ball.Transparency = 0.1
	TweenService
		:Create(ball, TweenInfo.new(d, Enum.EasingStyle.Quad), { Size = Vector3.one * radius * 2, Transparency = 1 })
		:Play()
	Debris:AddItem(ball, d + 0.05)
end

-- Particle burst at a point (sparkles / smoke / fire textures)
local emitterPart: Part
local emitters: { [string]: ParticleEmitter } = {}

local TEXTURES = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

function Effects.burst(pos: Vector3, color: Color3, count: number, kind: string?, speed: number?, size: number?)
	if not Effects.near(pos, 500) then
		return
	end
	local k = kind or "sparkle"
	local pe = emitters[k]
	if not pe then
		local att = Instance.new("Attachment")
		att.Parent = emitterPart
		local created = Instance.new("ParticleEmitter")
		created.Texture = TEXTURES[k] or TEXTURES.sparkle
		created.Enabled = false
		created.LightEmission = if k == "smoke" then 0 else 1
		created.Lifetime = NumberRange.new(0.5, 1.1)
		created.SpreadAngle = Vector2.new(180, 180)
		created.Drag = 2
		created.Parent = att
		emitters[k] = created
		pe = created
	end
	local e = pe :: ParticleEmitter
	local att = e.Parent :: Attachment
	att.WorldPosition = pos
	e.Color = ColorSequence.new(color)
	e.Speed = NumberRange.new((speed or 20) * 0.5, speed or 20)
	local s = size or 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s), NumberSequenceKeypoint.new(1, 0) })
	e:Emit(count)
end

-- Vertical pillar of light (rarity reveals, boss landing)
function Effects.pillar(pos: Vector3, color: Color3, height: number, width: number, duration: number)
	local p = fxPart(
		Enum.PartType.Cylinder,
		Vector3.new(height, width, width),
		CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	p.Transparency = 0.35
	TweenService:Create(
		p,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1, Size = Vector3.new(height, width * 0.2, width * 0.2) }
	):Play()
	Debris:AddItem(p, duration + 0.05)
end

-- Zig-zag lightning between two points
function Effects.bolt(a: Vector3, b: Vector3, color: Color3, width: number?, duration: number?)
	local segments = math.clamp(math.floor((b - a).Magnitude / 6), 3, 14)
	local prev = a
	for i = 1, segments do
		local t = i / segments
		local nextP = a:Lerp(b, t)
		if i < segments then
			nextP += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 4
		end
		local len = (nextP - prev).Magnitude
		local seg = fxPart(
			Enum.PartType.Block,
			Vector3.new(width or 0.6, width or 0.6, len),
			CFrame.lookAt((prev + nextP) / 2, nextP),
			color
		)
		TweenService:Create(seg, TweenInfo.new(duration or 0.25), { Transparency = 1 }):Play()
		Debris:AddItem(seg, (duration or 0.25) + 0.05)
		prev = nextP
	end
end

-- Lobbed projectile (optionally arcing) — returns after scheduling; calls onHit at impact
function Effects.projectile(
	from: Vector3,
	to: Vector3,
	flight: number,
	color: Color3,
	size: number,
	arc: number?,
	onHit: (() -> ())?,
	shape: Enum.PartType?
)
	if not Effects.near(from, 600) and not Effects.near(to, 600) then
		if onHit then
			task.delay(flight, onHit)
		end
		return
	end
	local ball = fxPart(shape or Enum.PartType.Ball, Vector3.one * size, CFrame.new(from), color)
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, size * 0.3, 0)
	att0.Parent = ball
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -size * 0.3, 0)
	att1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = ball
	local h = arc or 0
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - start) / flight)
		local p = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * h, 0)
		ball.CFrame = CFrame.lookAt(p, p + (to - from)) * CFrame.Angles(0, 0, t * 10)
		if t >= 1 then
			conn:Disconnect()
			ball:Destroy()
			if onHit then
				onHit()
			end
		end
	end)
end

-- Floating text above a world point (damage numbers use UnitRenderer's pool instead)
function Effects.floatText(pos: Vector3, text: string, color: Color3, size: number?, rise: number?)
	if not Effects.near(pos, 250) then
		return
	end
	local anchor = fxPart(Enum.PartType.Block, Vector3.one * 0.2, CFrame.new(pos), color)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size or 6, (size or 6) * 0.4)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Font
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Theme.Colors.Ink
	stroke.Parent = label
	TweenService:Create(
		anchor,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad),
		{ CFrame = CFrame.new(pos + Vector3.new(0, rise or 6, 0)) }
	):Play()
	TweenService
		:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		:Play()
	TweenService
		:Create(stroke, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
		:Play()
	Debris:AddItem(anchor, 1.15)
end

function Effects.folder(): Folder
	return fxFolder
end

function Effects.start()
	local live = Workspace:WaitForChild("Live")
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "Fx"
	fxFolder.Parent = live
	emitterPart = fxPart(Enum.PartType.Block, Vector3.one, CFrame.new(0, -500, 0), Color3.new(1, 1, 1))
	emitterPart.Transparency = 1
	emitterPart.Name = "Emitters"

	screen = Instance.new("ScreenGui")
	screen.Name = "Effects"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Parent = player:WaitForChild("PlayerGui")
	darkFrame = Instance.new("Frame")
	darkFrame.Size = UDim2.fromScale(1, 1)
	darkFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	darkFrame.BackgroundTransparency = 1
	darkFrame.BorderSizePixel = 0
	darkFrame.ZIndex = 1
	darkFrame.Parent = screen
	flashFrame = darkFrame:Clone()
	flashFrame.ZIndex = 40
	flashFrame.Parent = screen

	RunService:BindToRenderStep("RollBrainrotShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now < shakeUntil then
			local left = shakeUntil - now
			local amp = shakeAmp * math.min(1, left * 3)
			local cam = camera()
			cam.CFrame *= CFrame.new((math.random() - 0.5) * amp, (math.random() - 0.5) * amp, 0) * CFrame.Angles(
				0,
				0,
				(math.random() - 0.5) * amp * 0.02
			)
		else
			shakeAmp = 0
		end
	end)
end

return Effects
