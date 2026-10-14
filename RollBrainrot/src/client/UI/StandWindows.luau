--!strict
-- The hub stand windows: UPGRADES, SHOP (game passes, products, gem shop, boss crate),
-- DAILY REWARDS (7-day track), EVENTS (current + upcoming world events) and SETTINGS.
-- All rows are generated from GameConfig, so new upgrades/products/rewards appear here
-- automatically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local StandWindows = {}

local C = Theme.Colors

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function vlist(parent: ScrollingFrame | Frame, padding: number?)
	UIKit.list(parent, padding or 8, false, Enum.HorizontalAlignment.Center).VerticalAlignment =
		Enum.VerticalAlignment.Top
end

-------------------------------------------------------------------------------
-- Upgrades
-------------------------------------------------------------------------------
local upgradesList: ScrollingFrame

local function formatValue(def: GameConfig.UpgradeDef, v: number): string
	if def.format == "mult" then
		return string.format("%.2fx", v)
	elseif def.format == "percent" then
		return `-{math.floor(v * 100 + 0.5)}%`
	end
	return tostring(math.floor(v))
end

local function refreshUpgrades()
	if not upgradesList then
		return
	end
	clear(upgradesList)
	local defs = {}
	for _, d in GameConfig.Upgrades do
		table.insert(defs, d)
	end
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	local levels = ClientState.data.upgrades or {}
	for i, def in defs do
		local level = levels[def.id] or 0
		local cost = BrainrotMath.upgradeCost(def, level)
		local row = UIKit.panel({
			Size = UDim2.new(1, -12, 0, 84),
			Color = C.PanelLight,
			LayoutOrder = i,
			Parent = upgradesList,
		})
		UIKit.label({
			Text = def.icon,
			Size = UDim2.fromOffset(64, 64),
			Position = UDim2.fromOffset(10, 10),
			MaxTextSize = 46,
			Parent = row,
		})
		UIKit.label({
			Text = `{def.name}  <font size="18">Lv {level}/{def.maxLevel}</font>`,
			Size = UDim2.fromOffset(460, 32),
			Position = UDim2.fromOffset(84, 8),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 26,
			Parent = row,
		})
		UIKit.label({
			Text = def.description,
			Size = UDim2.fromOffset(460, 22),
			Position = UDim2.fromOffset(84, 40),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
			Color = C.TextDim,
			Font = Theme.FontBody,
			Stroke = 1,
			Parent = row,
		})
		local now = BrainrotMath.upgradeValue(def, level)
		local nextV = BrainrotMath.upgradeValue(def, level + 1)
		UIKit.label({
			Text = if cost
				then `{formatValue(def, now)} → <b>{formatValue(def, nextV)}</b>`
				else `{formatValue(def, now)} (MAX)`,
			Size = UDim2.fromOffset(200, 30),
			Position = UDim2.new(1, -440, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			MaxTextSize = 22,
			Color = C.Good,
			Parent = row,
		})
		local icon = if def.currency == "gems" then "💎" else "💰"
		UIKit.button({
			Text = if cost then `{icon} {Format.short(cost)}` else "MAXED",
			Color = if cost then (if def.currency == "gems" then C.Gems else C.Good) else C.Locked,
			Size = UDim2.fromOffset(200, 60),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = 24,
			Parent = row,
			OnClick = function()
				if cost then
					local ok = Notifications.call("BuyUpgrade", def.id)
					if ok then
						UIKit.sound("Coins", 0.5)
						Effects.confetti(25)
					end
				end
			end,
		})
	end
end

-------------------------------------------------------------------------------
-- Shop
-------------------------------------------------------------------------------
local shopList: ScrollingFrame

local function shopSection(title: string, order: number)
	UIKit.label({
		Text = title,
		Size = UDim2.new(1, -12, 0, 34),
		MaxTextSize = 26,
		Color = C.Warn,
		LayoutOrder = order,
		Parent = shopList,
	})
end

local function shopRow(
	order: number,
	icon: string,
	name: string,
	desc: string,
	buttonText: string,
	color: Color3,
	onClick: () -> ()
)
	local row =
		UIKit.panel({ Size = UDim2.new(1, -12, 0, 70), Color = C.PanelLight, LayoutOrder = order, Parent = shopList })
	UIKit.label({
		Text = icon,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.fromOffset(8, 7),
		MaxTextSize = 40,
		Parent = row,
	})
	UIKit.label({
		Text = name,
		Size = UDim2.fromOffset(520, 28),
		Position = UDim2.fromOffset(72, 6),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = row,
	})
	UIKit.label({
		Text = desc,
		Size = UDim2.fromOffset(520, 22),
		Position = UDim2.fromOffset(72, 38),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
		Color = C.TextDim,
		Font = Theme.FontBody,
		Stroke = 1,
		Parent = row,
	})
	UIKit.button({
		Text = buttonText,
		Color = color,
		Size = UDim2.fromOffset(190, 52),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 22,
		Parent = row,
		OnClick = onClick,
	})
end

local function refreshShop()
	if not shopList then
		return
	end
	clear(shopList)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	shopSection("💎 GEM SHOP — free rewards from levelling up and daily rewards", nextOrder())
	for _, item in GameConfig.GemShop do
		local price = if item.bossTokens then `👹 {item.bossTokens}` else `💎 {item.cost}`
		local desc = if item.bossTokens
			then "A random Epic Brainrot — earn Boss Tokens by beating bosses"
			else "Spend your hard-earned gems"
		shopRow(
			nextOrder(),
			item.icon,
			item.name,
			desc,
			price,
			if item.bossTokens then C.BossTokens else C.Gems,
			function()
				local ok, msg = Notifications.call("GemShopBuy", item.id)
				if ok then
					Notifications.toast(tostring(msg), C.Good)
					Effects.confetti(30)
				end
			end
		)
	end
	shopSection("🎟️ BOOSTS & TOKENS", nextOrder())
	local products = {}
	for key, p in GameConfig.Products do
		table.insert(products, { key = key, p = p })
	end
	table.sort(products, function(a, b)
		return a.p.priceHint < b.p.priceHint
	end)
	for _, entry in products do
		local p = entry.p
		shopRow(
			nextOrder(),
			p.icon,
			p.name,
			"Optional — the game is fully playable without it",
			if p.id > 0 then `R$ {p.priceHint}` else "Coming soon",
			if p.id > 0 then C.Good else C.Locked,
			function()
				Notifications.call("PromptProduct", entry.key)
			end
		)
	end
	shopSection("⭐ GAME PASSES", nextOrder())
	for key, pass in GameConfig.GamePasses do
		local owned = ClientState.hasPass(key)
		shopRow(
			nextOrder(),
			pass.icon,
			pass.name,
			pass.description,
			if owned then "Owned ✔" elseif pass.id > 0 then `R$ {pass.priceHint}` else "Coming soon",
			if owned then C.Locked else C.Primary,
			function()
				if not owned then
					Notifications.call("PromptPass", key)
				end
			end
		)
	end
end

-------------------------------------------------------------------------------
-- Daily rewards
-------------------------------------------------------------------------------
local dailyRow: Frame
local dailyStatus: TextLabel
local claimButton: TextButton

local function dailyState(): (number, boolean, number)
	local D = GameConfig.Daily
	local daily = ClientState.data.daily or { day = 0, last = 0 }
	local now = DateTime.now().UnixTimestamp
	local since = now - daily.last
	local day = daily.day
	if daily.last == 0 or since > D.GraceHours * 3600 then
		day = 0
	end
	local nextDay = day % #D.Rewards + 1
	local ready = daily.last == 0 or since >= D.CooldownHours * 3600
	return nextDay, ready, if ready then 0 else D.CooldownHours * 3600 - since
end

local function refreshDaily()
	if not dailyRow then
		return
	end
	clear(dailyRow)
	local nextDay, ready, wait = dailyState()
	for i, r in GameConfig.Daily.Rewards do
		local claimed = i < nextDay
		local today = i == nextDay
		local card = UIKit.panel({
			Size = UDim2.fromOffset(140, 190),
			Color = if today then (if ready then C.Good else C.Secondary) elseif claimed then C.Locked else C.PanelLight,
			LayoutOrder = i,
			Parent = dailyRow,
		})
		UIKit.label({
			Text = `DAY {i}`,
			Size = UDim2.new(1, -8, 0, 30),
			Position = UDim2.fromOffset(4, 6),
			MaxTextSize = 24,
			Parent = card,
		})
		UIKit.label({
			Text = r.icon,
			Size = UDim2.new(1, -8, 0, 70),
			Position = UDim2.fromOffset(4, 38),
			MaxTextSize = 58,
			Parent = card,
		})
		UIKit.label({
			Text = r.label,
			Size = UDim2.new(1, -8, 0, 46),
			Position = UDim2.fromOffset(4, 110),
			MaxTextSize = 18,
			Parent = card,
		})
		UIKit.label({
			Text = if claimed then "✔" elseif today then "TODAY" else "",
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.new(0, 4, 1, -28),
			MaxTextSize = 20,
			Color = C.Warn,
			Parent = card,
		})
	end
	dailyStatus.Text = if ready then "Your reward is ready!" else `Next reward in {Format.duration(wait)}`
	UIKit.setButtonColor(claimButton, if ready then C.Good else C.Locked)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local eventsList: ScrollingFrame
local eventsNow: TextLabel

local function refreshEvents()
	if not eventsList then
		return
	end
	local id = ReplicatedStorage:GetAttribute("WorldEvent")
	local now = ClientState.serverNow()
	if type(id) == "string" and id ~= "" then
		local e = Registry.Event[id]
		local ends = (ReplicatedStorage:GetAttribute("WorldEventEnds") :: number?) or now
		eventsNow.Text = `NOW: {e and e.name or id} — {e and e.description or ""} ({Format.clock(ends - now)} left)`
		eventsNow.TextColor3 = if e then e.color else C.Warn
	else
		local nextAt = (ReplicatedStorage:GetAttribute("WorldEventNext") :: number?) or now
		eventsNow.Text = `No event right now — the next one starts in {Format.clock(nextAt - now)}`
		eventsNow.TextColor3 = C.TextDim
	end
	if #eventsList:GetChildren() > 1 then
		return
	end
	for i, e in GameConfig.Events.List do
		local row =
			UIKit.panel({ Size = UDim2.new(1, -12, 0, 70), Color = C.PanelLight, LayoutOrder = i, Parent = eventsList })
		UIKit.label({
			Text = e.name,
			Size = UDim2.fromOffset(500, 30),
			Position = UDim2.fromOffset(12, 6),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 26,
			Color = e.color,
			Parent = row,
		})
		UIKit.label({
			Text = e.description,
			Size = UDim2.fromOffset(700, 24),
			Position = UDim2.fromOffset(12, 38),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Font = Theme.FontBody,
			Stroke = 1,
			Parent = row,
		})
	end
end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------
local settingsButtons: { [string]: TextButton } = {}

local SETTINGS = {
	{ key = "music", label = "🎵 Music" },
	{ key = "sfx", label = "🔊 Sound effects" },
	{ key = "skipRoll", label = "⏩ Skip roll animation (after your first roll)" },
}

local function refreshSettings()
	local s = ClientState.data.settings or {}
	for _, row in SETTINGS do
		local b = settingsButtons[row.key]
		if b then
			local on = s[row.key] == true
			UIKit.setButtonText(b, if on then "ON" else "OFF")
			UIKit.setButtonColor(b, if on then C.Good else C.PanelLight)
		end
	end
end

-------------------------------------------------------------------------------
function StandWindows.start()
	Windows.register("Upgrades", {
		title = "UPGRADES",
		icon = "⬆️",
		color = Color3.fromRGB(80, 190, 80),
		size = Vector2.new(980, 600),
		build = function(content: Frame)
			upgradesList = UIKit.scroll({ Parent = content })
			vlist(upgradesList)
			return { refresh = refreshUpgrades }
		end,
	})
	Windows.register("Shop", {
		title = "SHOP",
		icon = "🛒",
		color = Color3.fromRGB(255, 160, 40),
		size = Vector2.new(980, 620),
		build = function(content: Frame)
			shopList = UIKit.scroll({ Parent = content })
			vlist(shopList)
			return { refresh = refreshShop }
		end,
	})
	Windows.register("Daily", {
		title = "DAILY REWARDS",
		icon = "📅",
		color = Color3.fromRGB(70, 150, 255),
		size = Vector2.new(1120, 440),
		build = function(content: Frame)
			dailyRow =
				UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Parent = content })
			UIKit.list(dailyRow, 10, true, Enum.HorizontalAlignment.Center)
			dailyStatus = UIKit.label({
				Text = "",
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.fromOffset(0, 210),
				MaxTextSize = 28,
				Parent = content,
			})
			claimButton = UIKit.button({
				Text = "🎁 CLAIM",
				Color = C.Good,
				Size = UDim2.fromOffset(260, 74),
				Position = UDim2.new(0.5, 0, 0, 256),
				AnchorPoint = Vector2.new(0.5, 0),
				MaxTextSize = 34,
				Parent = content,
				OnClick = function()
					local ok = Notifications.call("ClaimDaily")
					if ok then
						Effects.confetti(80)
						UIKit.sound("Coins", 0.6)
					end
				end,
			})
			return { refresh = refreshDaily }
		end,
	})
	Windows.register("Events", {
		title = "WORLD EVENTS",
		icon = "🌩️",
		color = Color3.fromRGB(150, 100, 255),
		size = Vector2.new(900, 520),
		build = function(content: Frame)
			eventsNow = UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 56), MaxTextSize = 24, Parent = content })
			eventsList =
				UIKit.scroll({ Size = UDim2.new(1, 0, 1, -64), Position = UDim2.fromOffset(0, 64), Parent = content })
			vlist(eventsList)
			return { refresh = refreshEvents }
		end,
	})
	Windows.register("Settings", {
		title = "SETTINGS",
		icon = "⚙️",
		color = C.PanelLight,
		size = Vector2.new(720, 360),
		build = function(content: Frame)
			local list =
				UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
			vlist(list :: any, 10)
			for i, row in SETTINGS do
				local r = UIKit.panel({
					Size = UDim2.new(1, -20, 0, 64),
					Color = C.PanelLight,
					LayoutOrder = i,
					Parent = list,
				})
				UIKit.label({
					Text = row.label,
					Size = UDim2.new(1, -170, 1, -10),
					Position = UDim2.fromOffset(12, 5),
					XAlign = Enum.TextXAlignment.Left,
					MaxTextSize = 22,
					Parent = r,
				})
				settingsButtons[row.key] = UIKit.button({
					Text = "",
					Color = C.PanelLight,
					Size = UDim2.fromOffset(130, 48),
					Position = UDim2.new(1, -10, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Parent = r,
					OnClick = function()
						local s = ClientState.data.settings or {}
						Notifications.call("SetSetting", row.key, not (s[row.key] == true))
					end,
				})
			end
			return { refresh = refreshSettings }
		end,
	})

	ClientState.Changed:Connect(function(key)
		if (key == "upgrades" or key == "coins" or key == "gems") and Windows.isOpen("Upgrades") then
			refreshUpgrades()
		elseif key == "passes" and Windows.isOpen("Shop") then
			refreshShop()
		elseif key == "daily" and Windows.isOpen("Daily") then
			refreshDaily()
		elseif key == "settings" then
			refreshSettings()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Events") then
				refreshEvents()
			elseif Windows.isOpen("Daily") then
				local _, ready = dailyState()
				if not ready then
					refreshDaily()
				end
			end
		end
	end)
end

return StandWindows
