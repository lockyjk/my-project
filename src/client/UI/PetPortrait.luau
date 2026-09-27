--!strict
-- Cheap UI-drawn Stormling portrait (no ViewportFrame): a rounded block in the pet colour
-- with block eyes and accent ears, rarity-coloured outline and tier stars. Used by every
-- pet grid (inventory, eggs, index, trades) so hundreds of cards stay fast on phones.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(Shared:WaitForChild("Theme"))

local UIKit = require(script.Parent.UIKit)

local PetPortrait = {}

-- Draws into `parent` (fills it). hidden = silhouette for undiscovered index entries.
function PetPortrait.draw(parent: GuiObject, petId: string, tier: number?, hidden: boolean?)
	local def = Defs.Pet[petId]
	if not def then
		return
	end
	local color = if hidden then Theme.Colors.PanelDark else def.color
	local accent = if hidden then Theme.Colors.PanelDark else def.accent
	local t = math.max(1, tier or 1)
	local bodySize = 0.58 + (t - 1) * 0.06
	local holder = UIKit.new("Frame", {
		Name = "Portrait",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		local ear = UIKit.new("Frame", {
			BackgroundColor3 = accent,
			Size = UDim2.fromScale(0.16, 0.22),
			Position = UDim2.fromScale(0.5 + side * bodySize * 0.3, 0.5 - bodySize * 0.55),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = side * 20,
			ZIndex = holder.ZIndex,
			Parent = holder,
		})
		UIKit.corner(ear, 4)
		UIKit.stroke(ear, 2)
	end
	local body = UIKit.new("Frame", {
		BackgroundColor3 = color,
		Size = UDim2.fromScale(bodySize, bodySize * 0.9),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = holder.ZIndex + 1,
		Parent = holder,
	})
	UIKit.corner(body, if def.shape == "Ball" then 100 elseif def.shape == "Cylinder" then 18 else 10)
	UIKit.stroke(body, 3)
	UIKit.gradient(body, color, 0.2)
	if hidden then
		UIKit.label({ Text = "?", Size = UDim2.fromScale(1, 1), Parent = body, ZIndex = body.ZIndex + 1 })
		return
	end
	for _, side in { -1, 1 } do
		local eye = UIKit.new("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			Size = UDim2.fromScale(0.13, 0.26),
			Position = UDim2.fromScale(0.5 + side * 0.18, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = body.ZIndex + 1,
			Parent = body,
		})
		UIKit.corner(eye, 3)
		local shine = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(0.45, 0.3),
			Position = UDim2.fromScale(0.55, 0.15),
			ZIndex = eye.ZIndex + 1,
			Parent = eye,
		})
		UIKit.corner(shine, 2)
	end
	if t > 1 then
		UIKit.label({
			Text = string.rep("★", t - 1),
			Color = Theme.Colors.Charge,
			Size = UDim2.fromScale(1, 0.24),
			Position = UDim2.fromScale(0, 0.02),
			ZIndex = holder.ZIndex + 3,
			Stroke = 2,
			Parent = holder,
		})
	end
end

-- A full pet card: portrait + name + rarity border. Returns the button.
function PetPortrait.card(props: { [string]: any }): TextButton
	local def = Defs.Pet[props.petId]
	local rarity = Defs.Rarity[def.rarity]
	local hidden = props.hidden == true
	local card = UIKit.new("TextButton", {
		Name = props.name or props.petId,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.PanelLight,
		LayoutOrder = props.order or 0,
		Size = props.size or UDim2.fromOffset(110, 130),
		Parent = props.parent,
	})
	UIKit.corner(card, 12)
	UIKit.stroke(card, 4, if hidden then Theme.Colors.Ink else rarity.color)
	UIKit.gradient(card, Theme.Colors.PanelLight, 0.1)
	local art = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -30),
		ZIndex = card.ZIndex,
		Parent = card,
	})
	PetPortrait.draw(art, props.petId, props.tier, hidden)
	UIKit.label({
		Text = if hidden then "???" else (props.caption or def.name),
		Size = UDim2.new(1, -6, 0, 28),
		Position = UDim2.new(0, 3, 1, -30),
		MaxTextSize = 18,
		Stroke = 2,
		Color = if hidden then Theme.Colors.TextDim else rarity.color,
		ZIndex = card.ZIndex + 3,
		Parent = card,
	})
	if props.onClick then
		local onClick = props.onClick
		card.Activated:Connect(function()
			onClick(card)
		end)
	end
	return card
end

function PetPortrait.tierName(tier: number): string
	local t = Config.Fusion.Tiers[tier]
	return if t then t.name else "Base"
end

return PetPortrait
