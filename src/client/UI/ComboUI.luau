--!strict
-- Catch combo meter (client-only feedback; it does not change rewards):
-- every catch within COMBO_WINDOW seconds of the last one grows the combo. From x3 a big
-- stroked counter pops above the jar, changing colour as the streak climbs, with a shrinking
-- timer bar; milestones (x10, x25, x50, x100) flash the screen. Shiny catches count double.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local Effects = require(script.Parent.Parent.Controllers.Effects)
local SpiritController = require(script.Parent.Parent.Controllers.SpiritController)
local UIKit = require(script.Parent.UIKit)

local ComboUI = {}

local COMBO_WINDOW = 1.6
local MILESTONES = { [10] = "NICE!", [25] = "STORMY!", [50] = "UNSTOPPABLE!", [100] = "LEGENDARY CHASER!" }
local TIERS = {
	{ at = 3, color = Color3.fromRGB(120, 220, 255) },
	{ at = 10, color = Color3.fromRGB(120, 255, 140) },
	{ at = 25, color = Color3.fromRGB(255, 220, 60) },
	{ at = 50, color = Color3.fromRGB(255, 120, 60) },
	{ at = 100, color = Color3.fromRGB(255, 80, 200) },
}

local combo = 0
local lastCatch = 0
local best = 0
local holder: Frame
local countLabel: TextLabel
local subLabel: TextLabel
local timerFill: Frame
local scale: UIScale

local function tierColor(n: number): Color3
	local color = TIERS[1].color
	for _, t in TIERS do
		if n >= t.at then
			color = t.color
		end
	end
	return color
end

local function bump(shiny: boolean)
	local now = os.clock()
	if now - lastCatch > COMBO_WINDOW then
		combo = 0
	end
	lastCatch = now
	local before = combo
	combo += if shiny then 2 else 1
	best = math.max(best, combo)
	if combo < 3 then
		return
	end
	local color = tierColor(combo)
	holder.Visible = true
	countLabel.Text = `x{combo} COMBO`
	countLabel.TextColor3 = color
	timerFill.BackgroundColor3 = color
	scale.Scale = 1.25
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	countLabel.Rotation = math.random(-4, 4)
	for at, text in MILESTONES do
		if before < at and combo >= at then
			subLabel.Text = text
			subLabel.TextColor3 = color
			subLabel.Visible = true
			Effects.flash(color, 0.18)
			Effects.shake(0.25, 0.25)
			task.delay(1.4, function()
				if subLabel.Text == text then
					subLabel.Visible = false
				end
			end)
		end
	end
end

function ComboUI.best(): number
	return best
end

function ComboUI.start()
	local gui, uiScale = UIKit.screen("Combo", 3, Players.LocalPlayer:WaitForChild("PlayerGui"))
	local root = UIKit.root(gui, uiScale)
	holder = UIKit.new("Frame", {
		Name = "Combo",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(360, 96),
		Position = UDim2.new(0.5, 0, 1, -150),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = root,
	})
	scale = UIKit.new("UIScale", { Parent = holder })
	countLabel = UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 56), MaxTextSize = 54, Stroke = 4, Parent = holder })
	local bar = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		Size = UDim2.fromOffset(180, 8),
		Position = UDim2.new(0.5, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = holder,
	})
	UIKit.corner(bar, 4)
	timerFill = UIKit.new("Frame", { BackgroundColor3 = Theme.Colors.Static, Size = UDim2.fromScale(1, 1), Parent = bar })
	UIKit.corner(timerFill, 4)
	subLabel = UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 70), MaxTextSize = 28, Parent = holder })
	subLabel.Visible = false

	SpiritController.Caught:Connect(function(_id: number, shiny: boolean)
		bump(shiny)
	end)
	RunService.RenderStepped:Connect(function()
		if not holder.Visible then
			return
		end
		local left = COMBO_WINDOW - (os.clock() - lastCatch)
		if left <= 0 then
			holder.Visible = false
			combo = 0
			return
		end
		timerFill.Size = UDim2.fromScale(left / COMBO_WINDOW, 1)
	end)
end

return ComboUI
