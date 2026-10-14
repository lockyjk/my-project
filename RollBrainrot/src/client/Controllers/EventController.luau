--!strict
-- Makes the world feel alive during world events and inside themed arenas (client-side
-- lighting only): Blood Moon night with a red sky, Golden Hour sunset, Storm rain +
-- lightning, Meteor Shower streaks across the sky, Invasion purple alarm haze, and each
-- arena's fog/sky tint while you fight there.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Registry = require(Modules:WaitForChild("Registry"))

local Effects = require(script.Parent.Effects)

local EventController = {}

local rgb = Color3.fromRGB
local player = Players.LocalPlayer

type Look = { clock: number, tint: Color3, atmosphere: Color3, density: number, brightness: number }

local DEFAULT: Look =
	{ clock = 14.5, tint = rgb(255, 255, 255), atmosphere = rgb(205, 225, 255), density = 0.27, brightness = 2.6 }

local LOOKS: { [string]: Look } = {
	BloodMoon = {
		clock = 0.2,
		tint = rgb(255, 150, 150),
		atmosphere = rgb(150, 30, 40),
		density = 0.4,
		brightness = 1.6,
	},
	GoldenHour = {
		clock = 17.6,
		tint = rgb(255, 225, 170),
		atmosphere = rgb(255, 200, 140),
		density = 0.3,
		brightness = 2.4,
	},
	Storm = { clock = 15, tint = rgb(170, 180, 205), atmosphere = rgb(110, 120, 140), density = 0.45, brightness = 1.4 },
	MeteorShower = {
		clock = 19.2,
		tint = rgb(255, 210, 190),
		atmosphere = rgb(200, 140, 120),
		density = 0.3,
		brightness = 1.8,
	},
	GiantInvasion = {
		clock = 16,
		tint = rgb(220, 190, 255),
		atmosphere = rgb(170, 120, 220),
		density = 0.33,
		brightness = 2,
	},
}

local rain: Part? = nil
local current = ""

local function apply(look: Look, time: number)
	local info = TweenInfo.new(time, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = look.clock, Brightness = look.brightness }):Play()
	local cc = Lighting:FindFirstChild("WorldGrade") :: ColorCorrectionEffect?
	if cc then
		TweenService:Create(cc, info, { TintColor = look.tint }):Play()
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		TweenService:Create(atm, info, { Color = look.atmosphere, Density = look.density }):Play()
	end
end

local function arenaLook(): Look?
	local theme = ReplicatedStorage:GetAttribute("ArenaTheme")
	if player:GetAttribute("BattleId") == nil or type(theme) ~= "string" or theme == "" then
		return nil
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if
		not root
		or (root.Position - GameConfig.World.Arena.center).Magnitude > GameConfig.World.Arena.fieldRadius + 50
	then
		return nil
	end
	local arena = Registry.Arena[theme]
	if not arena or arena.order == 1 then
		return nil
	end
	return {
		clock = DEFAULT.clock,
		tint = arena.skyTint,
		atmosphere = arena.fogColor,
		density = 0.35,
		brightness = DEFAULT.brightness,
	}
end

local function setRain(on: boolean)
	if on and not rain then
		local p = Effects.part(Enum.PartType.Block, Vector3.new(160, 1, 160), CFrame.new(0, 80, 0), rgb(255, 255, 255))
		p.Transparency = 1
		p.Name = "Rain"
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(rgb(190, 210, 255))
		pe.Size = NumberSequence.new(0.18)
		pe.Transparency = NumberSequence.new(0.3)
		pe.Lifetime = NumberRange.new(1, 1.4)
		pe.Speed = NumberRange.new(80, 100)
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.Rate = 600
		pe.LightInfluence = 1
		pe.Parent = p
		rain = p
	elseif not on and rain then
		rain:Destroy()
		rain = nil
	end
end

local function skyMeteor()
	local cam = Workspace.CurrentCamera :: Camera
	local base = cam.CFrame.Position
	local from = base + Vector3.new(math.random(-400, 400), 320, math.random(-500, -200))
	local to = from + Vector3.new(math.random(-250, 250), -260, math.random(-100, 100))
	Effects.projectile(from, to, 1.4, rgb(255, 150, 60), 6, 0)
end

local function lightningFlash()
	Effects.flash(rgb(230, 240, 255), 0.35, 0.25)
	task.delay(0.4 + math.random(), function()
		Effects.sound("Explosion", 0.35, nil, 0.45)
	end)
end

local function refresh()
	local id = ReplicatedStorage:GetAttribute("WorldEvent")
	local eventId = if type(id) == "string" then id else ""
	local look = LOOKS[eventId] or arenaLook() or DEFAULT
	local key = eventId .. "|" .. tostring(look.atmosphere)
	if key ~= current then
		current = key
		apply(look, 3)
	end
	setRain(eventId == "Storm")
end

function EventController.start()
	ReplicatedStorage:GetAttributeChangedSignal("WorldEvent"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("ArenaTheme"):Connect(refresh)
	player:GetAttributeChangedSignal("BattleId"):Connect(function()
		task.delay(0.5, refresh)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
			local id = ReplicatedStorage:GetAttribute("WorldEvent")
			if id == "MeteorShower" and math.random() < 0.6 then
				skyMeteor()
			elseif id == "Storm" and math.random() < 0.15 then
				lightningFlash()
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		local r = rain
		if r then
			local cam = Workspace.CurrentCamera :: Camera
			r.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 70, 0))
		end
	end)
end

return EventController
