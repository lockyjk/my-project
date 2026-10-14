--!strict
-- Toasts (stacked, centre), server-wide announcements (banner), reward summary popups
-- (arena results, daily rewards) and the WELCOME BACK offline-earnings card.
-- `Notifications.call(remote, …)` invokes a server function and toasts its error text.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Format = require(Modules:WaitForChild("Format"))
local Net = require(Modules:WaitForChild("Net"))
local Theme = require(Modules:WaitForChild("Theme"))
local UIKit = require(script.Parent.UIKit)

local Notifications = {}

local C = Theme.Colors
local root: Frame
local toastList: Frame
local banner: Frame
local bannerLabel: TextLabel
local popup: Frame
local popupTitle: TextLabel
local popupBody: Frame
local popupQueue: { { title: string, lines: { string }, big: string? } } = {}
local popupBusy = false
local bannerQueue: { { text: string, color: Color3 } } = {}
local bannerBusy = false
local toastOrder = 0

function Notifications.toast(text: string, color: Color3?)
	if not toastList then
		return
	end
	toastOrder += 1
	local t = UIKit.panel({
		Size = UDim2.fromOffset(560, 44),
		Color = C.PanelDark,
		LayoutOrder = toastOrder,
		Parent = toastList,
		Corner = 12,
		Gradient = false,
	})
	t.BackgroundTransparency = 0.15
	UIKit.label({
		Text = text,
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.fromOffset(8, 3),
		Color = color or C.Text,
		MaxTextSize = 24,
		Parent = t,
	})
	UIKit.pop(t, 0.8)
	-- keep at most 4
	local toasts = {}
	for _, c in toastList:GetChildren() do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	task.delay(3.2, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			for _, d in t:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				end
			end
			task.wait(0.32)
			t:Destroy()
		end
	end)
end

-- Invoke a server function; toast the error message if it fails. Returns the results.
function Notifications.call(name: string, ...: any): (boolean, any)
	local ok, result = Net.Client.invoke(name, ...)
	if not ok and type(result) == "string" then
		Notifications.toast(result, C.Bad)
		UIKit.sound("Error", 0.3)
	end
	return ok, result
end

local function nextBanner()
	if bannerBusy or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local item = table.remove(bannerQueue, 1) :: { text: string, color: Color3 }
	bannerLabel.Text = item.text
	bannerLabel.TextColor3 = item.color
	banner.Position = UDim2.new(0.5, 0, 0, -80)
	banner.Visible = true
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 84) })
		:Play()
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
		task.wait(0.35)
		banner.Visible = false
		bannerBusy = false
		nextBanner()
	end)
end

function Notifications.announce(text: string, color: Color3?)
	table.insert(bannerQueue, { text = text, color = color or C.Warn })
	if #bannerQueue > 5 then
		table.remove(bannerQueue, 1)
	end
	nextBanner()
end

local function showPopup()
	if popupBusy or #popupQueue == 0 then
		return
	end
	popupBusy = true
	local item = table.remove(popupQueue, 1) :: { title: string, lines: { string }, big: string? }
	popupTitle.Text = item.title
	for _, c in popupBody:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if item.big then
		UIKit.label({
			Text = item.big,
			Size = UDim2.new(1, 0, 0, 70),
			MaxTextSize = 64,
			Color = C.Coins,
			LayoutOrder = 0,
			Parent = popupBody,
		})
	end
	for i, line in item.lines do
		UIKit.label({
			Text = line,
			Size = UDim2.new(1, 0, 0, 30),
			MaxTextSize = 24,
			LayoutOrder = i,
			Parent = popupBody,
		})
	end
	popup.Size = UDim2.fromOffset(560, 170 + #item.lines * 34 + (if item.big then 76 else 0))
	popup.Visible = true
	UIKit.pop(popup, 0.6)
	UIKit.sound("Coins", 0.5)
end

function Notifications.popup(title: string, lines: { string }, big: string?)
	table.insert(popupQueue, { title = title, lines = lines, big = big })
	showPopup()
end

function Notifications.start()
	local gui, scale = UIKit.screen("Notifications", 15, Players.LocalPlayer:WaitForChild("PlayerGui"))
	root = UIKit.root(gui, scale)
	toastList = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 220),
		Position = UDim2.new(0.5, 0, 0, 150),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
	})
	local layout = UIKit.list(toastList, 6, false, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	banner = UIKit.panel({
		Size = UDim2.fromOffset(820, 60),
		Position = UDim2.new(0.5, 0, 0, -80),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.PanelDark,
		Visible = false,
		Parent = root,
	})
	bannerLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -24, 1, -8),
		Position = UDim2.fromOffset(12, 4),
		MaxTextSize = 28,
		Parent = banner,
	})
	popup = UIKit.panel({
		Size = UDim2.fromOffset(560, 300),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	popupTitle = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -30, 0, 54),
		Position = UDim2.fromOffset(15, 12),
		MaxTextSize = 40,
		Color = C.Warn,
		Parent = popup,
	})
	popupBody = UIKit.new(
		"Frame",
		{
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -30, 1, -150),
			Position = UDim2.fromOffset(15, 70),
			Parent = popup,
		}
	)
	UIKit.list(popupBody, 4, false, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Top
	UIKit.button({
		Text = "AWESOME!",
		Color = C.Good,
		Size = UDim2.fromOffset(220, 60),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = popup,
		OnClick = function()
			popup.Visible = false
			popupBusy = false
			showPopup()
		end,
	})

	Net.Client.on("Notify", function(text: string, color: Color3?)
		Notifications.toast(text, color)
	end)
	Net.Client.on("Announce", function(text: string, color: Color3?)
		Notifications.announce(text, color)
	end)
	Net.Client.on("Reward", function(title: string, lines: { string })
		Notifications.popup(title, lines)
	end)
	Net.Client.on("WelcomeBack", function(coins: number, seconds: number)
		Notifications.popup(
			"WELCOME BACK!",
			{ `You were away for {Format.duration(seconds)}`, "Your zoo kept earning while you were gone." },
			`Your Zoo earned: ${Format.commas(coins)}`
		)
	end)
end

return Notifications
