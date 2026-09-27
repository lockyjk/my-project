--!strict
-- Always-on HUD. Mobile-first layout (design px, 1100x620 base):
--   top-left      currencies + multiplier          top-centre  storm banner + real countdown
--   top-right     streak, gifts, settings           right       quest tracker
--   left          main menu grid (one tap to every window, shop included)
--   right-bottom  HOME / BACK / TRAVEL + CATCH (touch & console)
--   bottom-centre jar bar + active boosts + gate unlock prompt

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local SpiritController = require(script.Parent.Parent.Controllers.SpiritController)
local WeatherController = require(script.Parent.Parent.Controllers.WeatherController)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local HUD = {}
local C = Theme.Colors

local root: Frame
local buttons: { [string]: TextButton } = {}
local chargeLabel: TextLabel
local tokensPanel: Frame
local tokensLabel: TextLabel
local multLabel: TextLabel
local jar: UIKit.Progress
local boostsRow: Frame
local stormLabel: TextLabel
local eventLabel: TextLabel
local gatePrompt: TextButton
local gateZone: string? = nil

-- Main menu: order = layout order. `window` names are registered by the UI modules.
HUD.Menu = {
	{ name = "Upgrades", icon = "Upgrades", color = C.Upgrades },
	{ name = "Pets", icon = "Pets", color = C.Pets },
	{ name = "Shop", icon = "Shop", color = C.Shop },
	{ name = "Quests", icon = "Quests", color = C.Quests },
	{ name = "Pass", icon = "Pass", color = C.Pass },
	{ name = "Build", icon = "Build", color = C.Build },
	{ name = "Index", icon = "Index", color = C.Index },
	{ name = "Trade", icon = "Trade", color = C.Trade },
	{ name = "Ascend", icon = "Ascend", color = C.Ascend },
	{ name = "Settings", icon = "Settings", color = C.PanelLight },
}

function HUD.button(name: string): TextButton?
	return buttons[name]
end

function HUD.root(): Frame
	return root
end

-- Pulsing highlight used by the tutorial and "something to claim" badges
local pulses: { [GuiObject]: Frame } = {}
function HUD.highlight(target: GuiObject?, on: boolean)
	if not target then
		return
	end
	local existing = pulses[target]
	if on and not existing then
		local ring = UIKit.new("Frame", {
			Name = "Pulse",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 16, 1, 16),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = target.ZIndex + 5,
			Parent = target,
		})
		UIKit.corner(ring, 20)
		local stroke = UIKit.stroke(ring, 5, C.Charge)
		pulses[target] = ring
		task.spawn(function()
			while ring.Parent do
				UIKit.tween(stroke, 0.4, { Transparency = 0.7 })
				task.wait(0.4)
				UIKit.tween(stroke, 0.4, { Transparency = 0 })
				task.wait(0.4)
			end
		end)
	elseif not on and existing then
		existing:Destroy()
		pulses[target] = nil
	end
end

-- Small red "!" badge on a menu button (claimable rewards)
function HUD.badge(name: string, on: boolean)
	local b = buttons[name]
	if not b then
		return
	end
	local badge = b:FindFirstChild("Badge")
	if on and not badge then
		local dot = UIKit.panel({
			Name = "Badge",
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, 4, 0, -4),
			AnchorPoint = Vector2.new(1, 0),
			Color = C.Bad,
			Corner = 13,
			ZIndex = b.ZIndex + 4,
			Parent = b,
		})
		UIKit.label({ Text = "!", Size = UDim2.fromScale(1, 1), Parent = dot, ZIndex = b.ZIndex + 5 })
	elseif not on and badge then
		badge:Destroy()
	end
end

local function currencyPanel(icon: string, color: Color3, y: number, name: string): (Frame, TextLabel)
	local panel = UIKit.panel({
		Name = name,
		Size = UDim2.fromOffset(250, 54),
		Position = UDim2.fromOffset(14, y),
		Color = C.PanelDark,
		Parent = root,
	})
	UIKit.label({ Text = icon, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(4, 4), Parent = panel })
	local value = UIKit.label({
		Text = "0",
		Color = color,
		Size = UDim2.new(1, -60, 1, -8),
		Position = UDim2.fromOffset(54, 4),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 36,
		Parent = panel,
	})
	return panel, value
end

local function buildTopLeft()
	local _, charge = currencyPanel(Theme.Icons.Charge, C.Charge, 14, "Charge")
	chargeLabel = charge
	tokensPanel, tokensLabel = currencyPanel(Theme.Icons.Tokens, C.Tokens, 74, "Tokens")
	tokensPanel.Visible = false
	multLabel = UIKit.label({
		Text = "",
		Color = C.TextDim,
		Size = UDim2.fromOffset(250, 26),
		Position = UDim2.fromOffset(18, 132),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = root,
	})
	ClientState.observe("Charge", function(v: number)
		local old = tonumber(chargeLabel:GetAttribute("Value")) or 0
		chargeLabel:SetAttribute("Value", v)
		chargeLabel.Text = Format.short(v)
		if v > old then
			UIKit.pop(chargeLabel, 1.25)
		end
	end)
	local function tokens()
		local t = ClientState.get("Tokens") or 0
		local asc = ClientState.get("Ascensions") or 0
		tokensPanel.Visible = t > 0 or asc > 0
		tokensLabel.Text = Format.short(t)
	end
	ClientState.observe("Tokens", tokens)
	ClientState.observe("Ascensions", tokens)
	ClientState.observe("Derived", function(d)
		multLabel.Text = `{Theme.Icons.Charge} x{Format.short(math.floor(d.ChargeMult * 100) / 100)} Charge`
	end)
end

local function buildMenu()
	local grid = UIKit.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(170, 420),
		Position = UDim2.new(0, 14, 0.5, 30),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = root,
	})
	UIKit.grid(grid, Vector2.new(Theme.UI.MainButton, Theme.UI.MainButton), 10).HorizontalAlignment =
		Enum.HorizontalAlignment.Left
	for i, entry in HUD.Menu do
		buttons[entry.name] = UIKit.button({
			Name = entry.name,
			Text = entry.name,
			Icon = entry.icon,
			Vertical = true,
			Color = entry.color,
			LayoutOrder = i,
			Parent = grid,
			OnClick = function()
				Windows.toggle(entry.name)
			end,
		})
	end
end

local function buildTravel()
	local col = UIKit.new("Frame", {
		Name = "Travel",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.UI.MainButton, 260),
		Position = UDim2.new(1, -14, 0.5, -40),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = root,
	})
	UIKit.list(col, 10)
	local function teleport(target: string)
		local ok, msg = Net.Client.invoke("Teleport", target)
		if not ok and msg then
			Effects.toast(msg, C.Bad, 1.5)
		end
	end
	buttons.Home = UIKit.button({
		Name = "Home",
		Text = "Home",
		Icon = "Home",
		Vertical = true,
		Color = C.Charge,
		Size = UDim2.fromOffset(Theme.UI.MainButton, Theme.UI.MainButton),
		LayoutOrder = 1,
		Parent = col,
		OnClick = function()
			teleport("Home")
		end,
	})
	buttons.Back = UIKit.button({
		Name = "Back",
		Text = "Back",
		Icon = "Back",
		Vertical = true,
		Color = C.Travel,
		Size = UDim2.fromOffset(Theme.UI.MainButton, Theme.UI.MainButton),
		LayoutOrder = 2,
		Parent = col,
		OnClick = function()
			teleport("Back")
		end,
	})
	buttons.Travel = UIKit.button({
		Name = "Travel",
		Text = "Zones",
		Icon = "Travel",
		Vertical = true,
		Color = C.Travel,
		Size = UDim2.fromOffset(Theme.UI.MainButton, Theme.UI.MainButton),
		LayoutOrder = 3,
		Parent = col,
		OnClick = function()
			Windows.toggle("Travel")
		end,
	})

	-- CATCH button for touch and gamepad players (hold works once the Catch Rod allows it)
	local catch = UIKit.button({
		Name = "Catch",
		Text = "CATCH",
		Color = C.Static,
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.new(1, -120, 1, -250),
		AnchorPoint = Vector2.new(1, 1),
		Corner = 55,
		MaxTextSize = 30,
		Parent = root,
	})
	catch.MouseButton1Down:Connect(function()
		SpiritController.setHolding(true)
	end)
	catch.MouseButton1Up:Connect(function()
		SpiritController.setHolding(false)
	end)
	catch.MouseLeave:Connect(function()
		SpiritController.setHolding(false)
	end)
	catch.Visible = UserInputService.TouchEnabled or UserInputService.GamepadEnabled
	buttons.Catch = catch
end

local function buildJar()
	jar = UIKit.progress({
		Name = "Jar",
		Size = UDim2.fromOffset(440, 44),
		Position = UDim2.new(0.5, 0, 1, -18),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Static,
		Parent = root,
	})
	UIKit.label({
		Text = Theme.Icons.Jar,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(0, -30, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = jar.frame,
		ZIndex = 4,
	})
	local function update()
		local d = ClientState.derived()
		local static = ClientState.get("Static") or 0
		local cap = d.Capacity or 1
		local full = static >= cap
		jar.set(static / cap, if full then "JAR FULL - tap HOME!" else `{Format.short(static)} / {Format.short(cap)}`)
		jar.fill.BackgroundColor3 = if full then C.Warn else C.Static
		HUD.highlight(buttons.Home, full)
	end
	ClientState.observe("Static", update)
	ClientState.observe("Derived", update)

	boostsRow = UIKit.new("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(440, 40),
		Position = UDim2.new(0.5, 0, 1, -68),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UIKit.list(boostsRow, 8, true)

	gatePrompt = UIKit.button({
		Name = "GatePrompt",
		Text = "",
		Color = C.Good,
		Size = UDim2.fromOffset(380, 64),
		Position = UDim2.new(0.5, 0, 1, -120),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
		OnClick = function()
			if gateZone then
				local ok, msg = Net.Client.invoke("UnlockZone", gateZone)
				if not ok and msg then
					Effects.toast(msg, C.Bad)
				end
			end
		end,
	})
	gatePrompt.Visible = false
end

function HUD.showGatePrompt(zoneId: string?)
	gateZone = zoneId
	if not zoneId then
		gatePrompt.Visible = false
		return
	end
	local z = Defs.Zone[zoneId]
	local affordable = (ClientState.get("Charge") or 0) >= z.gateCost
	UIKit.setButtonText(gatePrompt, `{Theme.Icons.Lock} Unlock {z.name}  {Theme.Icons.Charge}{Format.short(z.gateCost)}`)
	UIKit.setButtonColor(gatePrompt, if affordable then C.Good else C.PanelLight)
	if not gatePrompt.Visible then
		gatePrompt.Visible = true
		UIKit.pop(gatePrompt)
	end
end

local function buildBoosts()
	local chips: { [string]: TextLabel } = {}
	RunService.Heartbeat:Connect(function()
		local d = ClientState.derived()
		local boosts = d.Boosts or {}
		local now = DateTime.now().UnixTimestamp
		for _, potion in Config.Potions do
			local expiry = boosts[potion.stat]
			local chip = chips[potion.stat]
			if expiry and expiry > now then
				if not chip then
					local frame = UIKit.panel({ Size = UDim2.fromOffset(140, 36), Color = potion.color, Parent = boostsRow, Corner = 18 })
					chip = UIKit.label({ Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Parent = frame, MaxTextSize = 22 })
					chips[potion.stat] = chip
				end
				(chip :: TextLabel).Text = `{potion.stat} x{potion.mult} {Format.clock(expiry - now)}`
			elseif chip then
				(chip.Parent :: Instance):Destroy()
				chips[potion.stat] = nil
			end
		end
	end)
end

local function buildWeather()
	local panel = UIKit.panel({
		Name = "Weather",
		Size = UDim2.fromOffset(400, 50),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.PanelDark,
		Parent = root,
	})
	stormLabel = UIKit.label({ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Parent = panel, MaxTextSize = 28 })
	eventLabel = UIKit.label({
		Size = UDim2.fromOffset(400, 26),
		Position = UDim2.new(0.5, 0, 0, 68),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Charge,
		MaxTextSize = 22,
		Parent = root,
	})
	RunService.Heartbeat:Connect(function()
		local s = WeatherController.state
		if not s then
			stormLabel.Text = ""
			return
		end
		local now = DateTime.now().UnixTimestamp
		if s.storm then
			local storm = Defs.Storm[s.storm]
			stormLabel.Text = `{Theme.Icons.Storm} {string.upper(storm.name)}  {Format.clock(s.stormEndsAt - now)}`
			stormLabel.TextColor3 = C.Charge
			panel.BackgroundColor3 = storm.sky
		else
			local nextStorm = Defs.Storm[s.nextStorm]
			stormLabel.Text = `Next storm: {nextStorm.name} in {Format.clock(s.nextStartsAt - now)}`
			stormLabel.TextColor3 = C.Text
			panel.BackgroundColor3 = C.PanelDark
		end
		local names = {}
		for _, ev in s.events do
			local def = Defs.LiveEvent[ev.id]
			if def then
				table.insert(names, `{def.name} ends in {Format.duration(ev.endsAt - now)}`)
			end
		end
		eventLabel.Text = table.concat(names, "  |  ")
	end)
end

function HUD.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui, scale = UIKit.screen("HUD", 1, playerGui)
	root = UIKit.root(gui, scale)
	buildTopLeft()
	buildMenu()
	buildTravel()
	buildJar()
	buildBoosts()
	buildWeather()
end

return HUD
