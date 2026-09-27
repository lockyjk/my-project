--!strict
-- Game-feel toolkit: number popups, screen shake, particle bursts, toasts, banners, flashes.
-- Everything here is client-side only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local UIKit = require(script.Parent.Parent.UI.UIKit)

local Effects = {}
local C = Theme.Colors

local gui: ScreenGui
local scale: UIScale
local root: Frame
local toastList: Frame

-------------------------------------------------------------------------------
-- Popups
-------------------------------------------------------------------------------

local function toDesign(pixel: Vector2): UDim2
	return UDim2.fromOffset(pixel.X / scale.Scale, pixel.Y / scale.Scale)
end

-- Floating text that rises and fades at a screen position (design pixels)
function Effects.popupAt(position: UDim2, text: string, color: Color3, size: number?)
	local label = UIKit.label({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(260, size or 44),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = size or 44,
		Parent = root,
		ZIndex = 5,
	})
	UIKit.pop(label, 0.4)
	local rise = Theme.UI.PopupRise
	UIKit.tween(label, 0.9, { Position = position - UDim2.fromOffset(0, rise) }, Enum.EasingStyle.Quad)
	task.delay(0.55, function()
		UIKit.tween(label, 0.35, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			UIKit.tween(stroke, 0.35, { Transparency = 1 })
		end
	end)
	task.delay(0.95, function()
		label:Destroy()
	end)
end

function Effects.popupWorld(worldPos: Vector3, text: string, color: Color3, size: number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(worldPos)
	if not onScreen then
		return
	end
	local jitter = Vector2.new(math.random(-20, 20), math.random(-10, 10))
	Effects.popupAt(toDesign(Vector2.new(point.X, point.Y) + jitter), text, color, size)
end

-------------------------------------------------------------------------------
-- Screen shake
-------------------------------------------------------------------------------
local shakeUntil = 0
local shakeStrength = 0

function Effects.shake(intensity: number, duration: number?)
	if intensity <= 0 then
		return
	end
	shakeStrength = math.max(shakeStrength, intensity)
	shakeUntil = math.max(shakeUntil, os.clock() + (duration or 0.35))
end

local function shakeStep()
	local camera = Workspace.CurrentCamera
	local t = os.clock()
	if camera and t < shakeUntil then
		local s = shakeStrength * (shakeUntil - t) * 1.5
		camera.CFrame *= CFrame.Angles(
			math.rad(math.noise(t * 40, 0) * s * 2),
			math.rad(math.noise(0, t * 40) * s * 2),
			0
		)
	elseif t >= shakeUntil then
		shakeStrength = 0
	end
end

-------------------------------------------------------------------------------
-- Particles
-------------------------------------------------------------------------------
function Effects.burst(position: Vector3, color: Color3, count: number?, size: number?)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size or 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = anchor
	anchor.Parent = Workspace
	emitter:Emit(count or 20)
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

-------------------------------------------------------------------------------
-- Toasts / banners / flash
-------------------------------------------------------------------------------
function Effects.toast(text: string, color: Color3?, seconds: number?)
	local frame = UIKit.panel({
		Size = UDim2.fromOffset(520, 52),
		Color = color or C.Panel,
		Parent = toastList,
		ZIndex = 6,
	})
	UIKit.label({
		Text = text,
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		MaxTextSize = 28,
		Parent = frame,
		ZIndex = 7,
	})
	UIKit.pop(frame, 0.7)
	task.delay(seconds or 2.6, function()
		UIKit.tween(frame, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.25)
		frame:Destroy()
	end)
end

function Effects.banner(text: string, color: Color3, seconds: number?)
	local label = UIKit.label({
		Text = text,
		Color = color,
		Size = UDim2.new(0.9, 0, 0, 80),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 64,
		Stroke = 5,
		Parent = root,
		ZIndex = 8,
	})
	UIKit.pop(label, 0.3)
	task.delay(seconds or 3, function()
		UIKit.tween(label, 0.4, { TextTransparency = 1 })
		task.wait(0.4)
		label:Destroy()
	end)
end

function Effects.flash(color: Color3, strength: number?)
	local f = UIKit.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - (strength or 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Parent = root,
	})
	UIKit.tween(f, 0.5, { BackgroundTransparency = 1 })
	task.delay(0.5, function()
		f:Destroy()
	end)
end

function Effects.rarityColor(rarity: string): Color3
	local r = Defs.Rarity[rarity]
	return if r then r.color else C.Text
end

function Effects.root(): Frame
	return root
end

function Effects.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui, scale = UIKit.screen("Effects", 20, playerGui)
	root = UIKit.root(gui, scale)
	toastList = UIKit.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 540, 0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
	})
	local layout = UIKit.list(toastList, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	RunService:BindToRenderStep("StormShake", Enum.RenderPriority.Camera.Value + 1, shakeStep)

	Net.Client.on("Notify", function(kind: string, value: any, color: Color3?)
		if kind == "Sell" then
			Effects.popupAt(UDim2.new(0.5, 0, 1, -190), `+{Format.short(value)} {Theme.Icons.Charge}`, C.Charge, 64)
			Effects.flash(C.Charge, 0.25)
			UIKit.sound("Sell")
		elseif kind == "JarFull" then
			Effects.toast(tostring(value), C.Warn)
		elseif kind == "ZoneUnlocked" then
			Effects.banner(`{value} unlocked!`, C.Charge)
			Effects.shake(0.6)
			UIKit.sound("Upgrade")
		elseif kind == "Error" then
			Effects.toast(tostring(value), C.Bad)
		else
			Effects.toast(tostring(value), color)
		end
	end)
	Net.Client.on("Announce", function(text: string, rarity: string?)
		Effects.toast(text, if rarity then Theme.darken(Effects.rarityColor(rarity), 0.35) else C.Panel, 4)
	end)
end

return Effects
