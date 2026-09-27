--!strict
-- Modal window manager: one window open at a time, built lazily, never opens by itself
-- (except the one-time starter offer). Backdrop tap or X closes.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Theme = require(Shared:WaitForChild("Theme"))

local UIKit = require(script.Parent.UIKit)

local Windows = {}

export type WindowDef = {
	title: string,
	icon: string?,
	color: Color3,
	size: Vector2?,
	build: (content: Frame, window: Frame) -> WindowHandle?,
}
export type WindowHandle = { refresh: (() -> ())?, onClose: (() -> ())? }

type Entry = { def: WindowDef, frame: Frame?, handle: WindowHandle? }

local entries: { [string]: Entry } = {}
local openName: string? = nil
local gui: ScreenGui
local root: Frame
local backdrop: TextButton

Windows.Opened = Signal.new() :: Signal.Signal<string>
Windows.Closed = Signal.new() :: Signal.Signal<string>

function Windows.register(name: string, def: WindowDef)
	entries[name] = { def = def, frame = nil, handle = nil }
end

local function build(name: string, entry: Entry): Frame
	local def = entry.def
	local size = def.size or Vector2.new(Theme.UI.PanelWidth, Theme.UI.PanelHeight)
	local frame = UIKit.panel({
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Panel,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	local header = UIKit.panel({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		Color = def.color,
		ZIndex = 3,
		Parent = frame,
	})
	UIKit.label({
		Text = (if def.icon then (Theme.Icons[def.icon] or def.icon) .. "  " else "") .. def.title,
		Size = UDim2.new(1, -140, 1, -12),
		Position = UDim2.fromOffset(20, 6),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 40,
		ZIndex = 4,
		Parent = header,
	})
	UIKit.button({
		Name = "Close",
		Text = Theme.Icons.Close,
		Color = Theme.Colors.Bad,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(1, 12, 0, -12),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 5,
		Parent = header,
		OnClick = function()
			Windows.close()
		end,
	})
	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -84),
		Position = UDim2.fromOffset(12, 74),
		ZIndex = 3,
		Parent = frame,
	})
	entry.handle = def.build(content, frame)
	entry.frame = frame
	return frame
end

function Windows.isOpen(name: string): boolean
	return openName == name
end

function Windows.current(): string?
	return openName
end

function Windows.close()
	local name = openName
	if not name then
		return
	end
	local entry = entries[name]
	openName = nil
	backdrop.Visible = false
	if entry and entry.frame then
		entry.frame.Visible = false
		if entry.handle and entry.handle.onClose then
			entry.handle.onClose()
		end
	end
	Windows.Closed:Fire(name)
end

function Windows.open(name: string)
	local entry = entries[name]
	if not entry then
		warn("Unknown window", name)
		return
	end
	if openName == name then
		return
	end
	Windows.close()
	local frame = entry.frame or build(name, entry)
	openName = name
	backdrop.Visible = true
	frame.Visible = true
	UIKit.pop(frame, 0.7)
	if entry.handle and entry.handle.refresh then
		entry.handle.refresh()
	end
	Windows.Opened:Fire(name)
end

function Windows.toggle(name: string)
	if openName == name then
		Windows.close()
	else
		Windows.open(name)
	end
end

function Windows.refresh(name: string)
	local entry = entries[name]
	if entry and entry.frame and openName == name and entry.handle and entry.handle.refresh then
		entry.handle.refresh()
	end
end

function Windows.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local scale
	gui, scale = UIKit.screen("Windows", 10, playerGui)
	root = UIKit.root(gui, scale)
	backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
		Parent = root,
	})
	backdrop.Activated:Connect(Windows.close)
end

return Windows
