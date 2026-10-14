--!strict
-- Always-on HUD:
--   top-left   avatar, name, level + XP bar, team power
--   top-right  Coins, Gems, Roll Tokens (+ Rot Essence / Boss Tokens)
--   left       menu buttons (Collection, Zoo, Upgrades, Shop, Daily, Events, Arena)
--   bottom     equipped Brainrot slots (hidden in battle; BattleUI shows team HP there)
--   under the currencies: active boosts and the world event timer
--   quick travel: Machine / Zoo / Arena

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Bus = require(script.Parent.Bus)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)
local Viewport = require(script.Parent.Viewport)
local Windows = require(script.Parent.Windows)

local HUD = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local root: Frame
local levelLabel: TextLabel
local xpBar: UIKit.Progress
local powerLabel: TextLabel
local currencyLabels: { [string]: TextLabel } = {}
local slotsRow: Frame
local boostsLabel: TextLabel
local eventPanel: Frame
local eventLabel: TextLabel
local menu: Frame
local travel: Frame
local slotsSignature = ""

local function refreshProfile()
	local d = ClientState.data
	local level = d.level or 1
	levelLabel.Text = `⭐ Level {level}`
	local need = BrainrotMath.xpToNext(level)
	xpBar.set((d.xp or 0) / need, `{Format.short(d.xp or 0)} / {Format.short(need)} XP`)
	powerLabel.Text = `⚔️ Team Power {Format.short(ClientState.teamPower())}`
end

local function refreshCurrencies()
	local d = ClientState.data
	for key, label in currencyLabels do
		label.Text = Format.short(d[key] or 0)
	end
end

local function refreshSlots()
	local d = ClientState.data
	local equipped = d.equipped or {}
	local slots = ClientState.equippedSlots()
	local sig = table.concat(equipped, ",") .. "|" .. slots
	if sig == slotsSignature then
		return
	end
	slotsSignature = sig
	for _, c in slotsRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i = 1, slots do
		local uid = equipped[i]
		local inst = uid and ClientState.inventory[uid]
		local def = inst and Registry.Brainrot[inst.id]
		local slot = UIKit.panel({
			Size = UDim2.fromOffset(74, 74),
			Color = if def then C.PanelLight else C.PanelDark,
			LayoutOrder = i,
			Parent = slotsRow,
			Corner = 14,
			Gradient = def ~= nil,
		})
		if def and inst then
			local stroke = slot:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Registry.Rarity[def.rarity].color
				stroke.Thickness = 3
			end
			Viewport.new({
				id = inst.id,
				mut = inst.mut,
				parent = slot,
				size = UDim2.new(1, -6, 1, -6),
				position = UDim2.fromOffset(3, 3),
				zindex = 3,
			})
			UIKit.label({
				Text = `Lv{inst.lvl}`,
				Size = UDim2.new(1, -4, 0, 16),
				Position = UDim2.new(0, 2, 1, -18),
				MaxTextSize = 14,
				ZIndex = 4,
				Parent = slot,
			})
		else
			UIKit.label({ Text = "+", Size = UDim2.fromScale(1, 1), MaxTextSize = 40, Color = C.TextDim, Parent = slot })
		end
		local click = UIKit.new(
			"TextButton",
			{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = slot }
		)
		click.Activated:Connect(function()
			Bus.ViewBrainrot:Fire(uid)
		end)
	end
end

local function refreshBoosts()
	local parts = {}
	for id, b in GameConfig.Boosts do
		local left = ClientState.boostLeft(id)
		if left > 0 then
			table.insert(parts, `{b.icon} {b.mult}x {Format.clock(left)}`)
		end
	end
	boostsLabel.Text = table.concat(parts, "   ")
	boostsLabel.Visible = #parts > 0
end

local function refreshEvent()
	local id = ReplicatedStorage:GetAttribute("WorldEvent")
	local now = ClientState.serverNow()
	if type(id) == "string" and id ~= "" then
		local e = Registry.Event[id]
		local ends = (ReplicatedStorage:GetAttribute("WorldEventEnds") :: number?) or now
		eventLabel.Text = `{e and e.name or id}\n{Format.clock(ends - now)} left`
		eventLabel.TextColor3 = if e then e.color else C.Warn
	else
		local nextAt = (ReplicatedStorage:GetAttribute("WorldEventNext") :: number?) or now
		eventLabel.Text = `Next event\n{Format.clock(nextAt - now)}`
		eventLabel.TextColor3 = C.TextDim
	end
end

local function currency(parent: Instance, key: string, icon: string, color: Color3, order: number)
	local box = UIKit.panel({
		Size = UDim2.fromOffset(172, 46),
		Color = C.PanelDark,
		LayoutOrder = order,
		Parent = parent,
		Corner = 12,
	})
	UIKit.icon({
		Key = key,
		Fallback = icon,
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromOffset(-6, 0),
		MaxTextSize = 30,
		ZIndex = 3,
		Parent = box,
	})
	currencyLabels[key] = UIKit.label({
		Text = "0",
		Size = UDim2.new(1, -54, 1, -8),
		Position = UDim2.fromOffset(46, 4),
		XAlign = Enum.TextXAlignment.Left,
		Color = color,
		MaxTextSize = 30,
		Parent = box,
	})
	return box
end

function HUD.start()
	local gui, scale = UIKit.screen("HUD", 2, player:WaitForChild("PlayerGui"))
	root = UIKit.root(gui, scale)

	-- game logo (top centre, only once the Higgsfield logo is uploaded) ------------
	local logo: GuiObject? = nil
	if UIKit.hasImage("logo") then
		logo = UIKit.icon({
			Key = "logo",
			Size = UDim2.fromOffset(230, 128),
			Position = UDim2.new(0.5, 0, 0, 4),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = root,
		})
	end

	-- profile (top-left) -----------------------------------------------------------
	local profile = UIKit.panel({
		Size = UDim2.fromOffset(330, 104),
		Position = UDim2.fromOffset(14, 14),
		Color = C.PanelDark,
		Parent = root,
	})
	local avatar = UIKit.new("ImageLabel", {
		BackgroundColor3 = C.PanelLight,
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(10, 10),
		Parent = profile,
	})
	UIKit.corner(avatar, 42)
	task.spawn(function()
		local ok, img = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			player.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		if ok then
			avatar.Image = img
		end
	end)
	UIKit.label({
		Text = player.DisplayName,
		Size = UDim2.fromOffset(220, 28),
		Position = UDim2.fromOffset(102, 8),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = profile,
	})
	levelLabel = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(220, 22),
		Position = UDim2.fromOffset(102, 36),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Color = C.Xp,
		Parent = profile,
	})
	xpBar = UIKit.progress({
		Size = UDim2.fromOffset(218, 18),
		Position = UDim2.fromOffset(102, 60),
		Color = C.Xp,
		Parent = profile,
	})
	powerLabel = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(220, 18),
		Position = UDim2.fromOffset(102, 81),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Color = C.Warn,
		Parent = profile,
	})

	-- currencies (top-right) ----------------------------------------------------------
	local wallet = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 100),
		Position = UDim2.new(1, -14, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Parent = root,
	})
	local grid = UIKit.grid(wallet, Vector2.new(172, 46), 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	currency(wallet, "coins", "💰", C.Coins, 1)
	currency(wallet, "gems", "💎", C.Gems, 2)
	currency(wallet, "tokens", "🎟️", C.Tokens, 3)
	currency(wallet, "essence", "🧪", C.Essence, 4)
	currency(wallet, "bossTokens", "👹", C.BossTokens, 5)
	boostsLabel = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(520, 26),
		Position = UDim2.new(1, -14, 0, 120),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Right,
		MaxTextSize = 22,
		Color = C.Good,
		Parent = root,
	})
	eventPanel = UIKit.panel({
		Size = UDim2.fromOffset(200, 58),
		Position = UDim2.new(1, -14, 0, 148),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.PanelDark,
		Parent = root,
	})
	eventLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		MaxTextSize = 20,
		Parent = eventPanel,
	})
	local eventClick = UIKit.new(
		"TextButton",
		{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), Parent = eventPanel }
	)
	eventClick.Activated:Connect(function()
		Windows.open("Events")
	end)

	-- menu (left) ---------------------------------------------------------------
	menu = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(176, 420),
		Position = UDim2.new(0, 14, 0.5, 30),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = root,
	})
	UIKit.grid(menu, Vector2.new(82, 82), 8).HorizontalAlignment = Enum.HorizontalAlignment.Left
	local items = {
		{ name = "Collection", icon = "📖", text = "Brainrots", color = C.Primary },
		{ name = "Zoo", icon = "🏡", text = "Zoo", color = C.Good },
		{ name = "Upgrades", icon = "⬆️", text = "Upgrades", color = Color3.fromRGB(90, 200, 90) },
		{ name = "Shop", icon = "🛒", text = "Shop", color = Color3.fromRGB(255, 170, 40) },
		{ name = "Daily", icon = "📅", text = "Daily", color = Color3.fromRGB(70, 160, 255) },
		{ name = "Events", icon = "🌩️", text = "Events", color = Color3.fromRGB(150, 100, 255) },
		{ name = "Arena", icon = "🏟️", text = "Arena", color = Color3.fromRGB(230, 60, 60) },
		{ name = "Settings", icon = "⚙️", text = "Settings", color = C.PanelLight },
	}
	for i, it in items do
		UIKit.button({
			Icon = it.icon,
			ImageKey = "menu_" .. it.name,
			Text = it.text,
			Vertical = true,
			Color = it.color,
			Size = UDim2.fromOffset(82, 82),
			LayoutOrder = i,
			Parent = menu,
			OnClick = function()
				Windows.toggle(it.name)
			end,
		})
	end

	-- quick travel (above the slots) --------------------------------------------
	travel = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(470, 44),
		Position = UDim2.new(0.5, 0, 1, -110),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UIKit.list(travel, 8, true, Enum.HorizontalAlignment.Center)
	for i, t in
		{
			{ where = "Machine", text = "🎰 Machine", color = C.Primary },
			{ where = "Zoo", text = "🏡 My Zoo", color = C.Good },
			{ where = "Arena", text = "🏟️ Arena", color = Color3.fromRGB(230, 60, 60) },
		}
	do
		UIKit.button({
			Text = t.text,
			Color = t.color,
			Size = UDim2.fromOffset(146, 40),
			MaxTextSize = 20,
			LayoutOrder = i,
			Parent = travel,
			OnClick = function()
				Notifications.call("TeleportTo", t.where)
			end,
		})
	end

	-- equipped slots (bottom) ----------------------------------------------------
	slotsRow = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(900, 80),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UIKit.list(slotsRow, 8, true, Enum.HorizontalAlignment.Center)

	-- wiring ---------------------------------------------------------------------
	ClientState.Changed:Connect(function(key)
		if key == "level" or key == "xp" or key == "equipped" or key == "inventory" then
			refreshProfile()
		end
		if currencyLabels[key] then
			refreshCurrencies()
		end
		if key == "equipped" or key == "inventory" or key == "upgrades" or key == "passes" then
			slotsSignature = ""
			refreshSlots()
		end
		if key == "boosts" then
			refreshBoosts()
		end
	end)
	ClientState.Loaded:Connect(function()
		refreshProfile()
		refreshCurrencies()
		refreshSlots()
		refreshBoosts()
	end)
	local function battleVisibility()
		local inBattle = player:GetAttribute("BattleId") ~= nil
		slotsRow.Visible = not inBattle
		if logo then
			logo.Visible = not inBattle
		end
		travel.Visible = not inBattle
		menu.Visible = not inBattle
	end
	player:GetAttributeChangedSignal("BattleId"):Connect(battleVisibility)
	Bus.OpenWindow:Connect(function(name: string)
		Windows.open(name)
	end)
	task.spawn(function()
		while true do
			refreshEvent()
			refreshBoosts()
			task.wait(1)
		end
	end)
	if ClientState.loaded then
		refreshProfile()
		refreshCurrencies()
		refreshSlots()
	end
end

return HUD
