--!strict
-- Zoo management window:
--   header   ★ zoo rating (with progress to the next star and its income bonus), income per
--            minute, the bank, and Collect / Fill Zoo / Visit
--   cards    one card per habitat: banner art (Higgsfield image when uploaded, themed
--            colour + emoji otherwise), level pips, resident portraits with their income
--            (tap to remove), empty slots, unlock / upgrade
--   side     decorations shop

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)
local Viewport = require(script.Parent.Viewport)
local Windows = require(script.Parent.Windows)

local ZooUI = {}

local C = Theme.Colors
local CARD = Vector2.new(372, 236)

local starsRow: Frame
local ratingLabel: TextLabel
local ratingBar: UIKit.Progress
local incomeLabel: TextLabel
local bankLabel: TextLabel
local grid: ScrollingFrame
local decorList: ScrollingFrame

local function ratingData(): any
	return { zoo = ClientState.data.zoo, inventory = ClientState.inventory }
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-------------------------------------------------------------------------------
-- Header
-------------------------------------------------------------------------------
local function refreshHeader()
	local zoo = ClientState.data.zoo
	if not zoo then
		return
	end
	local stars, points, nextAt = BrainrotMath.zooRating(ratingData())
	clear(starsRow)
	for i = 1, #GameConfig.Zoo.Rating.thresholds do
		local icon = UIKit.icon({
			Key = "star",
			Fallback = "⭐",
			Size = UDim2.fromOffset(34, 34),
			LayoutOrder = i,
			MaxTextSize = 30,
			Parent = starsRow,
		})
		if i > stars then
			if icon:IsA("ImageLabel") then
				icon.ImageTransparency = 0.7
				icon.ImageColor3 = Color3.fromRGB(80, 80, 100)
			elseif icon:IsA("TextLabel") then
				icon.TextTransparency = 0.75
			end
		end
	end
	local bonus = math.floor((BrainrotMath.zooRatingMult(stars) - 1) * 100 + 0.5)
	if nextAt then
		local prev = GameConfig.Zoo.Rating.thresholds[stars]
		ratingBar.set((points - prev) / math.max(1, nextAt - prev), `{points} / {nextAt} pts`)
		ratingLabel.Text = `Zoo Rating · +{bonus}% income · next star brings more visitors`
	else
		ratingBar.set(1, `{points} pts · MAX`)
		ratingLabel.Text = `5-star zoo! · +{bonus}% income`
	end
	local income = (Players.LocalPlayer:GetAttribute("ZooIncome") :: number?) or 0
	incomeLabel.Text = `💵 ${Format.short(income)}/min`
	bankLabel.Text = `🏦 ${Format.short(math.floor(zoo.bank or 0))}`
end

-------------------------------------------------------------------------------
-- Habitat cards
-------------------------------------------------------------------------------
local function banner(card: Frame, def: GameConfig.HabitatDef, unlocked: boolean)
	local holder = UIKit.new("Frame", {
		Name = "Banner",
		BackgroundColor3 = def.groundColor,
		Size = UDim2.new(1, -12, 0, 104),
		Position = UDim2.fromOffset(6, 6),
		ClipsDescendants = true,
		Parent = card,
	})
	UIKit.corner(holder, 12)
	local key = "habitat_" .. def.id
	if UIKit.hasImage(key) then
		UIKit.icon({
			Key = key,
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = holder,
		})
	else
		UIKit.gradient(holder, def.groundColor, 0.25)
		UIKit.label({
			Text = def.emoji,
			Size = UDim2.fromOffset(90, 90),
			Position = UDim2.new(1, -96, 0, 6),
			MaxTextSize = 70,
			ZIndex = 2,
			Parent = holder,
		})
	end
	-- dark strip for the name
	local strip = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 1, -34),
		ZIndex = 3,
		Parent = holder,
	})
	UIKit.label({
		Text = `{def.emoji} {def.name}`,
		Size = UDim2.new(1, -16, 1, -4),
		Position = UDim2.fromOffset(8, 2),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		ZIndex = 4,
		Parent = strip,
	})
	if not unlocked then
		local shade = UIKit.new(
			"Frame",
			{
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.35,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 5,
				Parent = holder,
			}
		)
		UIKit.label({
			Text = "🔒",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromScale(0.5, 0.4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			MaxTextSize = 50,
			ZIndex = 6,
			Parent = shade,
		})
	end
	return holder
end

local function levelPips(card: Frame, level: number, max: number)
	local row = UIKit.new(
		"Frame",
		{
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(120, 14),
			Position = UDim2.new(1, -16, 0, 14),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 7,
			Parent = card,
		}
	)
	UIKit.list(row, 3, true, Enum.HorizontalAlignment.Right)
	for i = 1, max do
		local pip = UIKit.new(
			"Frame",
			{
				BackgroundColor3 = if i <= level then C.Warn else C.Ink,
				Size = UDim2.fromOffset(14, 14),
				LayoutOrder = i,
				ZIndex = 7,
				Parent = row,
			}
		)
		UIKit.corner(pip, 7)
		UIKit.stroke(pip, 1.5)
	end
end

local function residentChip(parent: Instance, uid: string, def: GameConfig.HabitatDef, level: number, order: number)
	local inst = ClientState.inventory[uid]
	local bdef = inst and Registry.Brainrot[inst.id]
	if not inst or not bdef then
		return
	end
	local rarity = Registry.Rarity[bdef.rarity]
	local chip = UIKit.panel({
		Size = UDim2.fromOffset(64, 82),
		Color = C.PanelDark,
		LayoutOrder = order,
		Parent = parent,
		Corner = 10,
		Gradient = false,
	})
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.color
	end
	Viewport.new({
		id = inst.id,
		mut = inst.mut,
		parent = chip,
		size = UDim2.fromOffset(58, 54),
		position = UDim2.fromOffset(3, 2),
		zindex = 3,
	})
	local fav = bdef.habitat == def.id
	UIKit.label({
		Text = `${Format.short(BrainrotMath.placedIncome(inst, def, level))}{if fav then "💚" else ""}`,
		Size = UDim2.new(1, -4, 0, 20),
		Position = UDim2.new(0, 2, 1, -23),
		MaxTextSize = 14,
		Color = C.Coins,
		ZIndex = 4,
		Parent = chip,
	})
	local click = UIKit.new(
		"TextButton",
		{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = chip }
	)
	click.Activated:Connect(function()
		UIKit.sound("Click", 0.3)
		Notifications.call("RemoveFromZoo", uid)
	end)
end

local function habitatCard(def: GameConfig.HabitatDef, order: number)
	local zoo = ClientState.data.zoo
	local h = zoo and zoo.habitats[def.id]
	local unlocked = h ~= nil and h.unlocked
	local card = UIKit.panel({
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		Color = if unlocked then C.PanelLight else C.PanelDark,
		LayoutOrder = order,
		Parent = grid,
	})
	banner(card, def, unlocked)
	if not unlocked then
		local need = if def.requiresArena
			then `Needs {Registry.Arena[def.requiresArena].name} cleared`
			else "Unlock to place more Brainrots"
		UIKit.label({
			Text = need,
			Size = UDim2.new(1, -24, 0, 24),
			Position = UDim2.fromOffset(12, 118),
			MaxTextSize = 18,
			Color = C.TextDim,
			Parent = card,
		})
		UIKit.label({
			Text = `Favourite of: {ZooUI.favouritesOf(def.id)}`,
			Size = UDim2.new(1, -24, 0, 22),
			Position = UDim2.fromOffset(12, 142),
			MaxTextSize = 16,
			Color = C.Good,
			Parent = card,
		})
		UIKit.button({
			Text = `🔓 Unlock  ${Format.short(def.cost)}`,
			Color = C.Good,
			Size = UDim2.new(1, -24, 0, 52),
			Position = UDim2.new(0, 12, 1, -62),
			MaxTextSize = 24,
			Parent = card,
			OnClick = function()
				Notifications.call("UnlockHabitat", def.id)
			end,
		})
		return
	end
	local hab = h :: { unlocked: boolean, level: number, slots: { string } }
	levelPips(card, hab.level, def.maxLevel)
	local slots = BrainrotMath.habitatSlots(def, hab.level)
	local row = UIKit.scroll({
		Size = UDim2.new(1, -12, 0, 92),
		Position = UDim2.fromOffset(6, 112),
		Horizontal = true,
		Padding = 4,
		Parent = card,
	})
	UIKit.list(row, 6, true, Enum.HorizontalAlignment.Left)
	for i, uid in hab.slots do
		residentChip(row, uid, def, hab.level, i)
	end
	for i = #hab.slots + 1, slots do
		local empty = UIKit.panel({
			Size = UDim2.fromOffset(64, 82),
			Color = C.PanelDark,
			LayoutOrder = i,
			Parent = row,
			Corner = 10,
			Gradient = false,
		})
		empty.BackgroundTransparency = 0.4
		UIKit.label({ Text = "+", Size = UDim2.fromScale(1, 0.7), MaxTextSize = 40, Color = C.TextDim, Parent = empty })
		UIKit.label({
			Text = "empty",
			Size = UDim2.new(1, 0, 0.3, 0),
			Position = UDim2.fromScale(0, 0.68),
			MaxTextSize = 14,
			Color = C.TextDim,
			Parent = empty,
		})
		local click = UIKit.new(
			"TextButton",
			{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = empty }
		)
		click.Activated:Connect(function()
			Notifications.call("FillZoo")
		end)
	end
	local cost = BrainrotMath.habitatUpgradeCost(def, hab.level)
	UIKit.label({
		Text = `{#hab.slots}/{slots} · ×{string.format("%.1f", BrainrotMath.habitatIncomeMult(def, hab.level))}`,
		Size = UDim2.fromOffset(150, 30),
		Position = UDim2.new(0, 12, 1, -38),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Color = C.Good,
		Parent = card,
	})
	UIKit.button({
		Text = if cost then `⬆️ ${Format.short(cost)}` else "MAX",
		Color = if cost then C.Warn else C.Locked,
		Size = UDim2.fromOffset(180, 40),
		Position = UDim2.new(1, -10, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		MaxTextSize = 20,
		Parent = card,
		OnClick = function()
			if cost then
				Notifications.call("UpgradeHabitat", def.id)
			end
		end,
	})
end

function ZooUI.favouritesOf(habitatId: string): string
	local names = {}
	for _, b in Registry.Brainrots do
		if b.habitat == habitatId then
			table.insert(names, b.emoji)
		end
	end
	return if #names > 0 then table.concat(names, " ") else "giants of the future"
end

local function decorRow(def: GameConfig.DecorationDef, order: number)
	local owned = ClientState.data.zoo and table.find(ClientState.data.zoo.decorations, def.id) ~= nil
	local row = UIKit.panel({
		Size = UDim2.new(1, -12, 0, 62),
		Color = if owned then C.PanelLight else C.PanelDark,
		LayoutOrder = order,
		Parent = decorList,
	})
	UIKit.label({
		Text = def.name,
		Size = UDim2.new(1, -140, 0, 26),
		Position = UDim2.fromOffset(10, 5),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = row,
	})
	UIKit.label({
		Text = `+{math.floor(def.incomeBonus * 100)}% income · +2 rating{if def.vip then " · VIP" else ""}`,
		Size = UDim2.new(1, -140, 0, 20),
		Position = UDim2.fromOffset(10, 33),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		Color = C.Good,
		Parent = row,
	})
	local price = if def.vip
		then "👑 VIP"
		elseif def.currency == "gems" then `💎 {def.cost}`
		else `💰 {Format.short(def.cost)}`
	UIKit.button({
		Text = if owned then "Owned" else price,
		Color = if owned then C.Locked else C.Secondary,
		Size = UDim2.fromOffset(120, 44),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 18,
		Parent = row,
		OnClick = function()
			if not owned then
				Notifications.call("BuyDecoration", def.id)
			end
		end,
	})
end

function ZooUI.refresh()
	if not grid then
		return
	end
	refreshHeader()
	clear(grid)
	for i, def in GameConfig.Habitats do
		habitatCard(def, i)
	end
	clear(decorList)
	for i, def in GameConfig.Decorations do
		decorRow(def, i)
	end
end

function ZooUI.start()
	Windows.register("Zoo", {
		title = "YOUR BRAINROT ZOO",
		icon = "🏡",
		color = C.Good,
		size = Vector2.new(1200, 650),
		build = function(content: Frame)
			-- header ------------------------------------------------------------
			local header = UIKit.panel({ Size = UDim2.new(1, 0, 0, 78), Color = C.PanelDark, Parent = content })
			starsRow = UIKit.new(
				"Frame",
				{
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(190, 36),
					Position = UDim2.fromOffset(12, 6),
					Parent = header,
				}
			)
			UIKit.list(starsRow, 2, true, Enum.HorizontalAlignment.Left)
			ratingBar = UIKit.progress({
				Size = UDim2.fromOffset(190, 22),
				Position = UDim2.fromOffset(12, 46),
				Color = C.Warn,
				Parent = header,
			})
			ratingLabel = UIKit.label({
				Text = "",
				Size = UDim2.fromOffset(300, 40),
				Position = UDim2.fromOffset(212, 6),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 17,
				Color = C.TextDim,
				Parent = header,
			})
			incomeLabel = UIKit.label({
				Text = "",
				Size = UDim2.fromOffset(150, 30),
				Position = UDim2.fromOffset(212, 42),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Color = C.Coins,
				Parent = header,
			})
			bankLabel = UIKit.label({
				Text = "",
				Size = UDim2.fromOffset(150, 30),
				Position = UDim2.fromOffset(370, 42),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = header,
			})
			local buttons = UIKit.new(
				"Frame",
				{
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(470, 60),
					Position = UDim2.new(1, -10, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Parent = header,
				}
			)
			UIKit.list(buttons, 8, true, Enum.HorizontalAlignment.Right)
			UIKit.button({
				Text = "💰 Collect",
				Color = C.Coins,
				Size = UDim2.fromOffset(150, 54),
				MaxTextSize = 22,
				LayoutOrder = 1,
				Parent = buttons,
				OnClick = function()
					Notifications.call("CollectZoo")
				end,
			})
			UIKit.button({
				Text = "🏡 Fill Zoo",
				Color = C.Secondary,
				Size = UDim2.fromOffset(150, 54),
				MaxTextSize = 22,
				LayoutOrder = 2,
				Parent = buttons,
				OnClick = function()
					Notifications.call("FillZoo")
				end,
			})
			UIKit.button({
				Text = "🚶 Visit",
				Color = C.Good,
				Size = UDim2.fromOffset(150, 54),
				MaxTextSize = 22,
				LayoutOrder = 3,
				Parent = buttons,
				OnClick = function()
					Windows.close()
					Notifications.call("TeleportTo", "Zoo")
				end,
			})

			-- habitat cards -----------------------------------------------------------
			grid =
				UIKit.scroll({ Size = UDim2.new(0, 790, 1, -88), Position = UDim2.fromOffset(0, 88), Parent = content })
			UIKit.grid(grid, CARD, 12).HorizontalAlignment = Enum.HorizontalAlignment.Left

			-- decorations --------------------------------------------------------------
			UIKit.label({
				Text = "✨ DECORATIONS",
				Size = UDim2.new(1, -800, 0, 30),
				Position = UDim2.fromOffset(800, 88),
				MaxTextSize = 24,
				Color = C.Warn,
				Parent = content,
			})
			decorList = UIKit.scroll({
				Size = UDim2.new(1, -800, 1, -150),
				Position = UDim2.fromOffset(800, 120),
				Parent = content,
			})
			UIKit.list(decorList, 6, false, Enum.HorizontalAlignment.Center).VerticalAlignment =
				Enum.VerticalAlignment.Top
			UIKit.label({
				Text = "💚 favourite habitat +25% · tap a Brainrot to take it out · pet them in your zoo for bonus coins",
				Size = UDim2.new(1, -800, 0, 30),
				Position = UDim2.new(0, 800, 1, -30),
				MaxTextSize = 14,
				Color = C.TextDim,
				Parent = content,
			})
			return { refresh = ZooUI.refresh }
		end,
	})
	ClientState.Changed:Connect(function(key)
		if not Windows.isOpen("Zoo") then
			return
		end
		if key == "zoo" or key == "inventory" then
			ZooUI.refresh()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("ZooIncome"):Connect(function()
		if Windows.isOpen("Zoo") then
			refreshHeader()
		end
	end)
end

return ZooUI
