--!strict
-- Shared "stat sheet" for a Brainrot (used by the roll reveal and the collection details):
-- name in rarity colour, rarity + mutation badges, combat power, zoo income, the stat grid
-- and the ability / passive text.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))
local UIKit = require(script.Parent.UIKit)

local BrainrotInfo = {}

local C = Theme.Colors

local SPEED_WORDS = {
	Slow = "Slow",
	Medium = "Medium",
	Normal = "Normal",
	Fast = "Fast",
	VeryFast = "Very Fast",
	ExtremelyFast = "Extreme",
}

export type Sheet = {
	frame: Frame,
	set: (id: string, mut: string, level: number) -> (),
}

local function badge(parent: Instance, order: number): (Frame, TextLabel)
	local f = UIKit.panel({
		Size = UDim2.fromOffset(120, 30),
		Color = C.PanelLight,
		LayoutOrder = order,
		Parent = parent,
		Corner = 10,
		Gradient = false,
	})
	local l = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -8, 1, -4),
		Position = UDim2.fromOffset(4, 2),
		MaxTextSize = 20,
		Parent = f,
	})
	return f, l
end

function BrainrotInfo.new(parent: Instance, size: UDim2, position: UDim2?): Sheet
	local frame = UIKit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = size, Position = position or UDim2.new(), Parent = parent }
	)
	UIKit.list(frame, 6, false, Enum.HorizontalAlignment.Center)
	local name =
		UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 42), MaxTextSize = 40, LayoutOrder = 1, Parent = frame })
	local badges = UIKit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2, Parent = frame }
	)
	UIKit.list(badges, 8, true, Enum.HorizontalAlignment.Center)
	local rarityBadge, rarityLabel = badge(badges, 1)
	local mutBadge, mutLabel = badge(badges, 2)
	local _, roleLabel = badge(badges, 3)
	local power = UIKit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 28,
		LayoutOrder = 3,
		Color = C.Warn,
		Parent = frame,
	})
	local grid = UIKit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 4, Parent = frame }
	)
	UIKit.grid(grid, Vector2.new(118, 40), 6)
	local cells: { [string]: TextLabel } = {}
	for i, key in { "HP", "ATK", "DEF", "SPD", "RANGE", "INCOME" } do
		local cell = UIKit.panel({
			Size = UDim2.fromOffset(110, 40),
			Color = C.PanelDark,
			LayoutOrder = i,
			Parent = grid,
			Corner = 10,
			Gradient = false,
		})
		UIKit.label({
			Text = key,
			Size = UDim2.new(1, -8, 0.42, 0),
			Position = UDim2.fromOffset(4, 1),
			MaxTextSize = 14,
			Color = C.TextDim,
			Stroke = 1,
			Parent = cell,
		})
		cells[key] = UIKit.label({
			Text = "",
			Size = UDim2.new(1, -8, 0.58, 0),
			Position = UDim2.new(0, 4, 0.42, -2),
			MaxTextSize = 20,
			Parent = cell,
		})
	end
	local ability = UIKit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 52),
		MaxTextSize = 18,
		LayoutOrder = 5,
		Font = Theme.FontBody,
		Stroke = 1,
		Parent = frame,
	})

	local function set(id: string, mut: string, level: number)
		local def = Registry.Brainrot[id]
		if not def then
			return
		end
		local rarity = Registry.Rarity[def.rarity]
		local m = Registry.Mutation[mut] or Registry.Mutation.Normal
		name.Text = `{def.emoji} {Registry.displayName(id, mut)}`
		name.TextColor3 = if m.id ~= "Normal" and m.color then m.color else rarity.color
		rarityLabel.Text = def.rarity:upper()
		rarityBadge.BackgroundColor3 = rarity.color:Lerp(Color3.new(0, 0, 0), 0.35)
		mutBadge.Visible = m.id ~= "Normal"
		mutLabel.Text = `{m.id:upper()} ×{m.statMult}`
		mutBadge.BackgroundColor3 = (m.color or Color3.fromRGB(255, 120, 220)):Lerp(Color3.new(0, 0, 0), 0.35)
		roleLabel.Text = `{def.role} · Lv {level}`
		local s = BrainrotMath.stats(def, mut, level)
		power.Text = `⚔️ Combat Power {Format.commas(BrainrotMath.combatPower(def, mut, level))}`
		cells.HP.Text = Format.short(s.hp)
		cells.ATK.Text = Format.short(s.attack)
		cells.DEF.Text = Format.short(s.defense)
		cells.SPD.Text = SPEED_WORDS[def.speed] or def.speed
		cells.RANGE.Text = def.range
		cells.INCOME.Text = `${Format.short(BrainrotMath.baseIncome(def, mut, level))}/m`
		local ab = Registry.Ability[def.ability]
		local text = if ab then `<b>{ab.name}</b> — {ab.description}` else ""
		if def.passive then
			local pv = Registry.Passive[def.passive]
			if pv then
				text ..= `\n<b>{pv.name}</b> — {pv.description}`
			end
		end
		ability.Text = text
	end

	return { frame = frame, set = set }
end

return BrainrotInfo
