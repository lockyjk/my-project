--!strict
-- Dramatic egg hatch: dim screen, egg wobbles harder and harder, crack flash, then the
-- Stormling bursts out with spinning rarity rays, a big rarity title and shake scaled by
-- rarity (Common -> Secret). Tap anywhere to skip. Faster Hatch pass shortens it.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local PetPortrait = require(script.Parent.PetPortrait)
local UIKit = require(script.Parent.UIKit)

local HatchAnimation = {}
local C = Theme.Colors

export type Result = { pet: string, uid: string?, deleted: boolean, rarity: string }

local gui: ScreenGui
local root: Frame
local playing = false
local queue: { { egg: string, results: { Result } } } = {}

local function eggColor(eggId: string): Color3
	local egg = Defs.Egg[eggId]
	local best = egg and Defs.Pet[egg.pets[#egg.pets].pet]
	return if best then best.color else C.Charge
end

local function playOne(eggId: string, results: { Result })
	playing = true
	local fast = ClientState.hasPass("FasterHatch")
	local total = if fast then Config.Hatch.FastAnimationSeconds else Config.Hatch.AnimationSeconds
	local skip = false

	local backdrop = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Backdrop,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
	})
	backdrop.Activated:Connect(function()
		skip = true
	end)
	UIKit.tween(backdrop, 0.25, { BackgroundTransparency = 0.3 })

	local n = #results
	local slots: { Frame } = {}
	for i = 1, n do
		local x = 0.5 + (i - (n + 1) / 2) * 0.26
		local slot = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(220, 260),
			Position = UDim2.fromScale(x, 0.48),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
			Parent = root,
		})
		-- Egg: an oval frame with spots
		local egg = UIKit.new("Frame", {
			Name = "Egg",
			BackgroundColor3 = eggColor(eggId),
			Size = UDim2.fromOffset(150, 190),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 3,
			Parent = slot,
		})
		UIKit.corner(egg, 90)
		UIKit.stroke(egg, 5)
		UIKit.gradient(egg, eggColor(eggId), 0.3)
		for s = 1, 3 do
			local spot = UIKit.new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.4,
				Size = UDim2.fromOffset(26 - s * 4, 26 - s * 4),
				Position = UDim2.fromScale(0.25 + s * 0.18, 0.25 + (s % 2) * 0.35),
				ZIndex = 4,
				Parent = egg,
			})
			UIKit.corner(spot, 20)
		end
		slots[i] = slot
	end

	-- Wobble with rising intensity
	local wobbleTime = total * 0.65
	local t0 = os.clock()
	while os.clock() - t0 < wobbleTime and not skip do
		local p = (os.clock() - t0) / wobbleTime
		for _, slot in slots do
			local egg = slot:FindFirstChild("Egg") :: Frame
			egg.Rotation = math.sin(os.clock() * (10 + p * 30)) * (6 + p * 22)
		end
		if p > 0.5 and math.random() < 0.05 then
			UIKit.sound("HatchShake", 0.4)
		end
		task.wait()
	end

	-- Crack
	Effects.flash(Color3.new(1, 1, 1), 0.85)
	local best = 1
	for i, r in results do
		local slot = slots[i]
		local egg = slot:FindFirstChild("Egg")
		if egg then
			egg:Destroy()
		end
		local def = Defs.Pet[r.pet]
		local rarity = Defs.Rarity[def.rarity]
		best = math.max(best, rarity.order)
		-- rotating rays
		local rays = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(300, 300),
			Position = UDim2.fromScale(0.5, 0.45),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
			Parent = slot,
		})
		for k = 1, 6 do
			local ray = UIKit.new("Frame", {
				BackgroundColor3 = rarity.color,
				BackgroundTransparency = 0.55,
				Size = UDim2.new(0, 26, 1, 0),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = k * 30,
				ZIndex = 2,
				Parent = rays,
			})
			UIKit.corner(ray, 13)
		end
		task.spawn(function()
			while rays.Parent do
				rays.Rotation += 1.5
				task.wait()
			end
		end)
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(180, 180),
			Position = UDim2.fromScale(0.5, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 4,
			Parent = slot,
		})
		PetPortrait.draw(art, r.pet, 1)
		UIKit.pop(art, 0.2)
		UIKit.label({
			Text = string.upper(rarity.name) .. (if rarity.order >= 5 then "!" else ""),
			Color = rarity.color,
			Size = UDim2.new(1, 40, 0, 44),
			Position = UDim2.new(0.5, 0, 1, -30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			MaxTextSize = 44,
			Stroke = 4,
			ZIndex = 5,
			Parent = slot,
		})
		UIKit.label({
			Text = def.name .. (if r.deleted then " (auto-deleted)" else ""),
			Size = UDim2.new(1, 40, 0, 32),
			Position = UDim2.new(0.5, 0, 1, 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			MaxTextSize = 30,
			ZIndex = 5,
			Parent = slot,
		})
	end
	local bestRarity = Config.Rarities[best]
	Effects.shake(bestRarity.shake, 0.4 + bestRarity.shake * 0.4)
	UIKit.sound(if best >= 5 then "Legendary" else "HatchReveal")
	if best >= 5 then
		Effects.banner(`{string.upper(bestRarity.name)} STORMLING!`, bestRarity.color, 2.5)
		Effects.flash(bestRarity.color, 0.4)
	end

	local hold = if skip then 0.6 else (if fast then 1.2 else 2.2) + (best >= 5 and 1 or 0)
	local t1 = os.clock()
	skip = false
	while os.clock() - t1 < hold and not skip do
		task.wait()
	end
	for _, slot in slots do
		slot:Destroy()
	end
	UIKit.tween(backdrop, 0.2, { BackgroundTransparency = 1 })
	task.wait(0.2)
	backdrop:Destroy()
	playing = false
end

function HatchAnimation.play(eggId: string, results: { Result })
	table.insert(queue, { egg = eggId, results = results })
	if playing then
		return
	end
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1) :: { egg: string, results: { Result } }
			playOne(item.egg, item.results)
		end
	end)
end

function HatchAnimation.isPlaying(): boolean
	return playing
end

function HatchAnimation.start()
	local scale
	gui, scale = UIKit.screen("Hatch", 15, Players.LocalPlayer:WaitForChild("PlayerGui"))
	root = UIKit.root(gui, scale)
end

return HatchAnimation
