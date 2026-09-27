--!strict
-- UI building blocks in the "chunky storm-toy" style (see Theme): thick dark outlines,
-- rounded corners, top-lit gradients, stroked bold text, squash-and-bounce buttons.
-- All sizes are in design pixels; each ScreenGui has a UIScale fitted to the viewport.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))

local UIKit = {}
local C = Theme.Colors

type Props = { [string]: any }

function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(parent: Instance, radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.UI.Corner), Parent = parent })
end

function UIKit.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or Theme.UI.Stroke,
		Color = color or C.Ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UIKit.textStroke(parent: Instance, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or Theme.UI.TextStroke,
		Color = C.Ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

function UIKit.gradient(parent: Instance, color: Color3, amount: number?): UIGradient
	local a = amount or 0.18
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(Theme.lighten(color, a), Theme.darken(color, a)),
		Rotation = 90,
		Parent = parent,
	})
end

function UIKit.padding(parent: Instance, px: number): UIPadding
	local u = UDim.new(0, px)
	return UIKit.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u, Parent = parent })
end

function UIKit.list(parent: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UIKit.grid(parent: Instance, cell: Vector2, padding: number?): UIGridLayout
	return UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = parent,
	})
end

function UIKit.tween(inst: Instance, time: number, goal: Props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tw:Play()
	return tw
end

local sounds: { [string]: Sound } = {}
function UIKit.sound(name: string, volume: number?)
	local id = (Config.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local s: Sound? = sounds[name]
	if not s then
		local created = Instance.new("Sound")
		created.SoundId = id
		created.Parent = SoundService
		sounds[name] = created
		s = created
	end
	local sound = s :: Sound
	sound.Volume = volume or 0.6
	SoundService:PlayLocalSound(sound)
end

-- Big stroked label
function UIKit.label(props: Props): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Font,
		TextColor3 = props.Color or C.Text,
		TextScaled = props.TextSize == nil,
		TextSize = props.TextSize or 24,
		Text = props.Text or "",
		RichText = true,
		Size = props.Size or UDim2.fromOffset(200, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = true,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Name = props.Name or "Label",
		Parent = props.Parent,
	})
	UIKit.textStroke(label, props.Stroke)
	if label.TextScaled then
		UIKit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 48, Parent = label })
	end
	return label
end

-- Plastic panel
function UIKit.panel(props: Props): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = props.Color or C.Panel,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Panel",
		ZIndex = props.ZIndex or 1,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	UIKit.corner(frame, props.Corner)
	UIKit.stroke(frame, props.StrokeThickness)
	if props.Gradient ~= false then
		UIKit.gradient(frame, props.Color or C.Panel, 0.08)
	end
	return frame
end

-- Squash on press, bounce back on release
local function bounce(button: GuiButton)
	local scale = UIKit.new("UIScale", { Parent = button })
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.08, { Scale = Theme.UI.PressScale })
	end)
	local function up()
		UIKit.tween(scale, Theme.UI.BounceTime, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Up:Connect(up)
	button.MouseLeave:Connect(up)
end

-- Chunky coloured button. props.OnClick(button)
function UIKit.button(props: Props): TextButton
	local color: Color3 = props.Color or C.Upgrades
	local button = UIKit.new("TextButton", {
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Size = props.Size or UDim2.fromOffset(160, 56),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Button",
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	UIKit.corner(button, props.Corner or Theme.UI.ButtonCorner)
	UIKit.stroke(button)
	UIKit.gradient(button, color)
	-- glossy highlight strip
	local shine = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		Size = UDim2.new(1, -12, 0.35, 0),
		Position = UDim2.fromOffset(6, 4),
		Name = "Shine",
		ZIndex = button.ZIndex,
		Parent = button,
	})
	UIKit.corner(shine, 10)
	local text = props.Text or ""
	if props.Icon then
		local icon = Theme.Icons[props.Icon] or props.Icon
		if props.Vertical then
			UIKit.label({
				Text = icon,
				Size = UDim2.new(1, 0, 0.62, 0),
				Position = UDim2.fromScale(0, 0.02),
				Parent = button,
				Name = "Icon",
				ZIndex = button.ZIndex + 1,
			})
			UIKit.label({
				Text = text,
				Size = UDim2.new(1, -6, 0.34, 0),
				Position = UDim2.new(0, 3, 0.62, 0),
				Parent = button,
				Name = "Text",
				MaxTextSize = 20,
				Stroke = 2,
				ZIndex = button.ZIndex + 1,
			})
		else
			text = icon .. " " .. text
		end
	end
	if not props.Vertical then
		local label = UIKit.label({
			Text = text,
			Size = UDim2.new(1, -12, 1, -8),
			Position = UDim2.fromOffset(6, 4),
			Parent = button,
			Name = "Text",
			MaxTextSize = props.MaxTextSize or 32,
			ZIndex = button.ZIndex + 1,
		})
		label.RichText = true
	end
	bounce(button)
	if props.OnClick then
		local onClick = props.OnClick
		button.Activated:Connect(function()
			UIKit.sound("Click", 0.4)
			onClick(button)
		end)
	end
	return button
end

function UIKit.setButtonText(button: GuiButton, text: string)
	local label = button:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function UIKit.setButtonColor(button: GuiButton, color: Color3)
	button.BackgroundColor3 = color
	local g = button:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(Theme.lighten(color, 0.18), Theme.darken(color, 0.18))
	end
end

export type Progress = { frame: Frame, fill: Frame, label: TextLabel, set: (number, string?) -> () }

function UIKit.progress(props: Props): Progress
	local frame = UIKit.panel({
		Size = props.Size or UDim2.fromOffset(300, 30),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Color = C.PanelDark,
		Parent = props.Parent,
		Name = props.Name or "Progress",
		Corner = 12,
		Gradient = false,
	})
	local fill = UIKit.new("Frame", {
		BackgroundColor3 = props.Color or C.Static,
		Size = UDim2.fromScale(0, 1),
		Name = "Fill",
		Parent = frame,
	})
	UIKit.corner(fill, 12)
	UIKit.gradient(fill, props.Color or C.Static, 0.25)
	local label = UIKit.label({ Text = "", Size = UDim2.fromScale(1, 1), Parent = frame, ZIndex = 3, MaxTextSize = 26 })
	local p: Progress
	p = {
		frame = frame,
		fill = fill,
		label = label,
		set = function(fraction: number, text: string?)
			fraction = math.clamp(fraction, 0, 1)
			UIKit.tween(fill, 0.15, { Size = UDim2.fromScale(fraction, 1) })
			fill.Visible = fraction > 0.001
			if text then
				label.Text = text
			end
		end,
	}
	return p
end

function UIKit.scroll(props: Props): ScrollingFrame
	local sf = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = props.Horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
		ScrollingDirection = props.Horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.TextDim,
		Name = props.Name or "Scroll",
		Parent = props.Parent,
	})
	UIKit.padding(sf, props.Padding or 8)
	return sf
end

function UIKit.pop(inst: GuiObject, from: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = inst })
	scale.Scale = from or 0.6
	UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- ScreenGui with a UIScale fitted to the viewport (mobile first)
function UIKit.screen(name: string, order: number, parent: Instance): (ScreenGui, UIScale)
	local gui = UIKit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Parent = parent,
	})
	local scale = UIKit.new("UIScale", { Parent = gui })
	local function fit()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		local s = math.min(vp.X / Theme.UI.DesignSize.X, vp.Y / Theme.UI.DesignSize.Y)
		scale.Scale = math.clamp(s, Theme.UI.MinScale, Theme.UI.MaxScale)
	end
	fit()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	return gui, scale
end

-- A full-screen root frame whose size is the viewport divided by the UIScale, so
-- children can anchor to edges in design pixels.
function UIKit.root(gui: ScreenGui, scale: UIScale): Frame
	local root = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Name = "Root",
		Parent = gui,
	})
	local function fit()
		root.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
	end
	fit()
	scale:GetPropertyChangedSignal("Scale"):Connect(fit)
	return root
end

return UIKit
