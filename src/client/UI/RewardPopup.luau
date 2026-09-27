--!strict
-- Reward popups (quests, gifts, streaks, pass tiers, purchases) and "rare catch" reveals.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local Effects = require(script.Parent.Parent.Controllers.Effects)
local PetPortrait = require(script.Parent.PetPortrait)
local UIKit = require(script.Parent.UIKit)

local RewardPopup = {}
local C = Theme.Colors

local root: Frame
local queue: { { title: string, lines: { string }, pet: string? } } = {}
local showing = false

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local item = table.remove(queue, 1) :: { title: string, lines: { string }, pet: string? }
	local panel = UIKit.panel({
		Size = UDim2.fromOffset(460, 150 + #item.lines * 36 + (if item.pet then 150 else 0)),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.Panel,
		ZIndex = 2,
		Parent = root,
	})
	local header = UIKit.panel({ Size = UDim2.new(1, 0, 0, 60), Color = C.Charge, ZIndex = 3, Parent = panel })
	UIKit.label({ Text = item.title, Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), ZIndex = 4, Parent = header })
	local y = 70
	if item.pet then
		local art = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(140, 140),
			Position = UDim2.new(0.5, 0, 0, y),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 3,
			Parent = panel,
		})
		PetPortrait.draw(art, item.pet, 1)
		y += 150
	end
	for i, line in item.lines do
		UIKit.label({
			Text = line,
			Size = UDim2.new(1, -20, 0, 32),
			Position = UDim2.fromOffset(10, y + (i - 1) * 36),
			MaxTextSize = 26,
			ZIndex = 3,
			Parent = panel,
		})
	end
	local ok = UIKit.button({
		Text = "Awesome!",
		Color = C.Good,
		Size = UDim2.fromOffset(200, 56),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Parent = panel,
	})
	UIKit.pop(panel, 0.5)
	Effects.burst(workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 12, C.Charge, 30)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		panel:Destroy()
		showing = false
		showNext()
	end
	ok.Activated:Connect(close)
	task.delay(8, close)
end

function RewardPopup.show(title: string, lines: { string }, pet: string?)
	table.insert(queue, { title = title, lines = lines, pet = pet })
	showNext()
end

function RewardPopup.start()
	local gui, scale = UIKit.screen("Rewards", 12, Players.LocalPlayer:WaitForChild("PlayerGui"))
	root = UIKit.root(gui, scale)
	Net.Client.on("Reward", function(kind: string, payload: any)
		if kind == "Popup" then
			RewardPopup.show(payload.title, payload.lines)
		end
	end)
	Net.Client.on("PetDrop", function(pet: any)
		local def = Defs.Pet[pet.id]
		if def then
			Effects.banner("RARE CATCH!", Defs.Rarity[def.rarity].color, 2.5)
			Effects.shake(1, 0.6)
			RewardPopup.show("Rare catch!", { `{def.name} jumped into your jar!` }, pet.id)
		end
	end)
end

return RewardPopup
