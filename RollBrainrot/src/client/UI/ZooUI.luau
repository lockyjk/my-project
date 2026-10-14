--!strict
-- Zoo management: income per minute and bank (collect), every habitat (unlock, upgrade,
-- residents with a remove button, affinity hints), Fill Zoo, and decorations shop.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))

local Players = game:GetService("Players")

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local ZooUI = {}

local C = Theme.Colors

local incomeLabel: TextLabel
local bankLabel: TextLabel
local list: ScrollingFrame
local decorList: ScrollingFrame

local function habitatRow(def: GameConfig.HabitatDef, order: number)
	local zoo = ClientState.data.zoo
	local h = zoo and zoo.habitats[def.id]
	local unlocked = h ~= nil and h.unlocked
	local row = UIKit.panel({
		Size = UDim2.new(1, -12, 0, 104),
		Color = if unlocked then C.PanelLight else C.PanelDark,
		LayoutOrder = order,
		Parent = list,
	})
	UIKit.label({
		Text = `{def.emoji} {def.name}`,
		Size = UDim2.fromOffset(300, 32),
		Position = UDim2.fromOffset(12, 6),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = row,
	})
	if not unlocked then
		local need = if def.requiresArena then ` · needs {Registry.Arena[def.requiresArena].name} cleared` else ""
		UIKit.label({
			Text = `🔒 Locked{need}`,
			Size = UDim2.fromOffset(460, 26),
			Position = UDim2.fromOffset(12, 40),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
			Color = C.TextDim,
			Parent = row,
		})
		UIKit.button({
			Text = `Unlock ${Format.short(def.cost)}`,
			Color = C.Good,
			Size = UDim2.fromOffset(200, 54),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = 22,
			Parent = row,
			OnClick = function()
				Notifications.call("UnlockHabitat", def.id)
			end,
		})
		return
	end
	local hab = h :: { unlocked: boolean, level: number, slots: { string } }
	local slots = BrainrotMath.habitatSlots(def, hab.level)
	local mult = BrainrotMath.habitatIncomeMult(def, hab.level)
	UIKit.label({
		Text = `Lv {hab.level}/{def.maxLevel} · {#hab.slots}/{slots} slots · ×{string.format("%.1f", mult)} income`,
		Size = UDim2.fromOffset(420, 22),
		Position = UDim2.fromOffset(320, 10),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Color = C.Good,
		Parent = row,
	})
	-- residents
	local residents = UIKit.new(
		"Frame",
		{
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -250, 0, 52),
			Position = UDim2.fromOffset(12, 44),
			Parent = row,
		}
	)
	UIKit.list(residents, 6, true, Enum.HorizontalAlignment.Left)
	for i, uid in hab.slots do
		local inst = ClientState.inventory[uid]
		local bdef = inst and Registry.Brainrot[inst.id]
		if inst and bdef then
			local fav = bdef.habitat == def.id
			UIKit.button({
				Text = `{bdef.emoji}{if fav then "💚" else ""}\n<font size="12">${Format.short(
					BrainrotMath.placedIncome(inst, def, hab.level)
				)}/m ✖</font>`,
				Color = Registry.Rarity[bdef.rarity].color:Lerp(Color3.new(0, 0, 0), 0.35),
				Size = UDim2.fromOffset(84, 50),
				MaxTextSize = 20,
				LayoutOrder = i,
				Parent = residents,
				OnClick = function()
					Notifications.call("RemoveFromZoo", uid)
				end,
			})
		end
	end
	for i = #hab.slots + 1, slots do
		local empty = UIKit.panel({
			Size = UDim2.fromOffset(84, 50),
			Color = C.PanelDark,
			LayoutOrder = i,
			Parent = residents,
			Corner = 12,
			Gradient = false,
		})
		UIKit.label({
			Text = "empty",
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 16,
			Color = C.TextDim,
			Parent = empty,
		})
	end
	local cost = BrainrotMath.habitatUpgradeCost(def, hab.level)
	UIKit.button({
		Text = if cost then `⬆️ Upgrade ${Format.short(cost)}` else "MAX",
		Color = if cost then C.Warn else C.Locked,
		Size = UDim2.fromOffset(220, 50),
		Position = UDim2.new(1, -12, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		MaxTextSize = 20,
		Parent = row,
		OnClick = function()
			if cost then
				Notifications.call("UpgradeHabitat", def.id)
			end
		end,
	})
end

local function decorRow(def: GameConfig.DecorationDef, order: number)
	local owned = ClientState.data.zoo and table.find(ClientState.data.zoo.decorations, def.id) ~= nil
	local row = UIKit.panel({
		Size = UDim2.new(1, -12, 0, 58),
		Color = if owned then C.PanelLight else C.PanelDark,
		LayoutOrder = order,
		Parent = decorList,
	})
	UIKit.label({
		Text = def.name,
		Size = UDim2.new(1, -150, 0, 26),
		Position = UDim2.fromOffset(10, 4),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = row,
	})
	UIKit.label({
		Text = `+{math.floor(def.incomeBonus * 100)}% zoo income{if def.vip then " · VIP" else ""}`,
		Size = UDim2.new(1, -150, 0, 20),
		Position = UDim2.fromOffset(10, 30),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
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
		Size = UDim2.fromOffset(126, 44),
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
	if not list then
		return
	end
	local income = (Players.LocalPlayer:GetAttribute("ZooIncome") :: number?) or 0
	incomeLabel.Text = `💵 {Format.short(income)} coins / minute`
	local bank = ClientState.data.zoo and ClientState.data.zoo.bank or 0
	bankLabel.Text = `Bank: 💰 {Format.short(math.floor(bank))}`
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, def in GameConfig.Habitats do
		habitatRow(def, i)
	end
	for _, c in decorList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, def in GameConfig.Decorations do
		decorRow(def, i)
	end
end

function ZooUI.start()
	Windows.register("Zoo", {
		title = "YOUR BRAINROT ZOO",
		icon = "🏡",
		color = C.Good,
		size = Vector2.new(1160, 620),
		build = function(content: Frame)
			local top =
				UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Parent = content })
			incomeLabel = UIKit.label({
				Text = "",
				Size = UDim2.fromOffset(330, 44),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 28,
				Color = C.Coins,
				Parent = top,
			})
			bankLabel = UIKit.label({
				Text = "",
				Size = UDim2.fromOffset(260, 44),
				Position = UDim2.fromOffset(340, 0),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 26,
				Parent = top,
			})
			local row = UIKit.new(
				"Frame",
				{
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(520, 46),
					Position = UDim2.new(1, 0, 0, 0),
					AnchorPoint = Vector2.new(1, 0),
					Parent = top,
				}
			)
			UIKit.list(row, 8, true, Enum.HorizontalAlignment.Right)
			UIKit.button({
				Text = "💰 Collect",
				Color = C.Coins,
				Size = UDim2.fromOffset(150, 44),
				MaxTextSize = 20,
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					Notifications.call("CollectZoo")
				end,
			})
			UIKit.button({
				Text = "🏡 Fill Zoo",
				Color = C.Secondary,
				Size = UDim2.fromOffset(150, 44),
				MaxTextSize = 20,
				LayoutOrder = 2,
				Parent = row,
				OnClick = function()
					Notifications.call("FillZoo")
				end,
			})
			UIKit.button({
				Text = "🚶 Visit",
				Color = C.Good,
				Size = UDim2.fromOffset(150, 44),
				MaxTextSize = 20,
				LayoutOrder = 3,
				Parent = row,
				OnClick = function()
					Windows.close()
					Notifications.call("TeleportTo", "Zoo")
				end,
			})
			list = UIKit.scroll({
				Size = UDim2.new(0.68, 0, 1, -56),
				Position = UDim2.fromOffset(0, 56),
				Parent = content,
			})
			UIKit.list(list, 8, false, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Top
			UIKit.label({
				Text = "DECORATIONS",
				Size = UDim2.new(0.31, 0, 0, 30),
				Position = UDim2.new(0.69, 0, 0, 56),
				MaxTextSize = 24,
				Color = C.Warn,
				Parent = content,
			})
			decorList = UIKit.scroll({
				Size = UDim2.new(0.31, 0, 1, -92),
				Position = UDim2.new(0.69, 0, 0, 90),
				Parent = content,
			})
			UIKit.list(decorList, 6, false, Enum.HorizontalAlignment.Center).VerticalAlignment =
				Enum.VerticalAlignment.Top
			UIKit.label({
				Text = "💚 = favourite habitat (+25% income)",
				Size = UDim2.new(0.68, 0, 0, 20),
				Position = UDim2.new(0, 0, 1, 2),
				MaxTextSize = 16,
				Color = C.TextDim,
				Parent = content,
			})
			return { refresh = ZooUI.refresh }
		end,
	})
	ClientState.Changed:Connect(function(key)
		if (key == "zoo" or key == "inventory") and Windows.isOpen("Zoo") then
			ZooUI.refresh()
		end
	end)
end

return ZooUI
