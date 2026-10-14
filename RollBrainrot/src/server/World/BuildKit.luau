--!strict
-- Helpers for building anchored world geometry: parts, rings of parts, signs, billboards,
-- prompts and lights. Everything is anchored and (by default) non-colliding decoration
-- unless `collide` is passed.

local BuildKit = {}

export type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
	Parent: Instance?,
}

function BuildKit.part(p: PartProps): Part
	local part = Instance.new("Part")
	part.Name = p.Name or "Part"
	if p.Shape then
		part.Shape = p.Shape
	end
	part.Size = p.Size
	part.CFrame = p.CFrame
	part.Color = p.Color
	part.Material = p.Material or Enum.Material.SmoothPlastic
	part.Transparency = p.Transparency or 0
	part.Reflectance = p.Reflectance or 0
	part.Anchored = true
	part.CanCollide = if p.CanCollide == nil then true else p.CanCollide
	part.CanTouch = false
	part.CastShadow = if p.CastShadow == nil then true else p.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = p.Parent
	return part
end

-- Short form: block(parent, size, cframe, color, material?, collide?)
function BuildKit.block(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return BuildKit.part({
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		CanCollide = collide == true,
		Parent = parent,
	})
end

function BuildKit.ball(parent: Instance, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	return BuildKit.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material,
		CanCollide = false,
		Parent = parent,
	})
end

-- Vertical cylinder standing on `base` (axis along world Y)
function BuildKit.column(parent: Instance, height: number, diameter: number, base: Vector3, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return BuildKit.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		CanCollide = collide == true,
		Parent = parent,
	})
end

-- Flat disc lying on the ground (axis along Y)
function BuildKit.disc(parent: Instance, diameter: number, thickness: number, center: Vector3, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return BuildKit.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		CanCollide = collide == true,
		Parent = parent,
	})
end

-- Calls fn(cframe, index, angle) for `count` evenly spaced points on a circle; the CFrame
-- sits on the circle and looks outward.
function BuildKit.around(center: Vector3, radius: number, count: number, fn: (CFrame, number, number) -> (), startAngle: number?)
	for i = 0, count - 1 do
		local a = (startAngle or 0) + i / count * math.pi * 2
		local pos = center + Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
		local outward = pos + Vector3.new(math.sin(a), 0, math.cos(a))
		fn(CFrame.lookAt(pos, outward), i + 1, a)
	end
end

-- A wall/ring of blocks around a circle (segment length auto-fits the circumference)
function BuildKit.ring(parent: Instance, center: Vector3, radius: number, segments: number, height: number, thickness: number, color: Color3, material: Enum.Material?, collide: boolean?, skip: ((number) -> boolean)?)
	local segLen = 2 * math.pi * radius / segments + 0.4
	BuildKit.around(center + Vector3.new(0, height / 2, 0), radius, segments, function(cf, i)
		if skip and skip(i) then
			return
		end
		BuildKit.block(parent, Vector3.new(segLen, height, thickness), cf, color, material, collide)
	end)
end

-- Sign: a board with a SurfaceGui on its front (-Z face). Returns board + label.
function BuildKit.sign(parent: Instance, cf: CFrame, size: Vector2, text: string, bg: Color3, fg: Color3?): (Part, TextLabel)
	local board = BuildKit.part({
		Name = "Sign",
		Size = Vector3.new(size.X, size.Y, 0.6),
		CFrame = cf,
		Color = bg,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = fg or Color3.new(1, 1, 1)
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 18, 30)
	stroke.Parent = label
	return board, label
end

-- Floating text above a part
function BuildKit.billboard(adornee: BasePart, text: string, size: Vector2, offsetY: number, color: Color3?, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 300
	gui.Parent = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 18, 30)
	stroke.Parent = label
	return label
end

-- ProximityPrompt. `action` is stored as an attribute so the client can open the right UI
-- without the server being involved (PromptController).
function BuildKit.prompt(parent: BasePart, actionText: string, objectText: string, action: string, distance: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = distance or 14
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("Action", action)
	prompt.Parent = parent
	return prompt
end

function BuildKit.light(parent: Instance, color: Color3, range: number, brightness: number?, shadows: boolean?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = shadows == true
	l.Parent = parent
	return l
end

function BuildKit.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function BuildKit.model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

return BuildKit
