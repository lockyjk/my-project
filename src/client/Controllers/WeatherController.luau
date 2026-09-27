--!strict
-- Client side of storms and live events: state for the HUD countdown, plus visuals
-- (sky tint, fog, falling rain/snow/sparkles around the camera, lightning flashes).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Theme = require(Shared:WaitForChild("Theme"))

local Effects = require(script.Parent.Effects)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WeatherController = {}

export type State = {
	storm: string?,
	stormEndsAt: number,
	nextStorm: string,
	nextStartsAt: number,
	events: { { id: string, endsAt: number } },
}

WeatherController.state = nil :: State?
WeatherController.Changed = Signal.new() :: Signal.Signal<State>

-- Server time estimate (DateTime is UTC on both sides; this covers clock skew)
local clockOffset = 0
function WeatherController.now(): number
	return DateTime.now().UnixTimestamp + clockOffset
end

local atmosphere: Atmosphere
local fxPart: Part
local emitter: ParticleEmitter
local defaults = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	ClockTime = Lighting.ClockTime,
}

local STORM_FX: { [string]: { color: Color3, rate: number, speed: number, size: number, clock: number } } = {
	Thunderstorm = { color = Color3.fromRGB(170, 200, 255), rate = 400, speed = 90, size = 0.25, clock = 18.5 },
	Blizzard = { color = Color3.fromRGB(255, 255, 255), rate = 300, speed = 25, size = 0.5, clock = 15 },
	Aurora = { color = Color3.fromRGB(120, 255, 200), rate = 60, speed = 4, size = 0.6, clock = 21 },
	Tornado = { color = Color3.fromRGB(200, 190, 170), rate = 250, speed = 60, size = 0.4, clock = 16.5 },
}

local function apply(state: State)
	local storm = if state.storm then Defs.Storm[state.storm] else nil
	if storm then
		local fx = STORM_FX[storm.id]
		UIKit.tween(Lighting, 3, { Ambient = storm.sky, OutdoorAmbient = storm.fog, ClockTime = fx and fx.clock or 16 })
		UIKit.tween(atmosphere, 3, { Density = 0.42, Color = storm.fog, Decay = storm.sky })
		if fx then
			emitter.Color = ColorSequence.new(fx.color)
			emitter.Rate = fx.rate
			emitter.Speed = NumberRange.new(fx.speed * 0.8, fx.speed)
			emitter.Size = NumberSequence.new(fx.size)
			emitter.Enabled = true
		end
		Effects.banner(`{Theme.Icons.Storm} {string.upper(storm.name)}!`, Theme.Colors.Charge, 3.5)
		Effects.shake(0.8, 0.6)
		UIKit.sound("StormStart")
	else
		UIKit.tween(Lighting, 3, defaults)
		UIKit.tween(atmosphere, 3, { Density = 0.28, Color = Color3.fromRGB(199, 220, 255), Decay = Color3.fromRGB(120, 150, 210) })
		emitter.Enabled = false
	end
end

function WeatherController.start()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Color = Color3.fromRGB(199, 220, 255)
	atmosphere.Decay = Color3.fromRGB(120, 150, 210)
	atmosphere.Parent = Lighting

	fxPart = Instance.new("Part")
	fxPart.Name = "WeatherFx"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CanTouch = false
	fxPart.Transparency = 1
	fxPart.Size = Vector3.new(120, 1, 120)
	fxPart.Parent = Workspace
	emitter = Instance.new("ParticleEmitter")
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.LightEmission = 0.6
	emitter.Enabled = false
	emitter.Parent = fxPart

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera then
			fxPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
		end
	end)

	-- Lightning flashes during thunderstorms
	task.spawn(function()
		while true do
			task.wait(math.random(4, 9))
			local s = WeatherController.state
			if s and s.storm == "Thunderstorm" then
				Effects.flash(Color3.new(1, 1, 1), 0.55)
				Effects.shake(0.25, 0.25)
			end
		end
	end)

	Net.Client.on("Weather", function(state: State)
		local previous = WeatherController.state
		WeatherController.state = state
		if not previous or previous.storm ~= state.storm then
			apply(state)
		end
		WeatherController.Changed:Fire(state)
	end)
end

return WeatherController
