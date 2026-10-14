--!strict
-- Tiny toolkit for building good-looking placeholder creatures out of parts.
--
-- Convention for every creature model:
--   * Model.PrimaryPart = "Root": invisible, anchored, sitting on the ground at the feet,
--     facing -Z (CFrame.lookAt forward).
--   * Every other part is unanchored and welded to Root, so moving Root.CFrame moves the
--     whole creature in one cheap assignment (used by the client renderers).
--   * Attributes: Height (studs, for health bars) and Radius (studs).
--   * Parts tagged with attribute "Orbit" (number = radius) circle the creature; "Spin"
--     parts rotate in place; "Bob" parts float. The client Animator reads these.
--
-- To replace a placeholder with real art, put a Model named after the Brainrot/monster id
-- into ReplicatedStorage.Art.Brainrots / ReplicatedStorage.Art.Monsters. It only needs a
-- PrimaryPart at the feet facing -Z.

local ModelKit = {}

export type Builder = {
	model: Model,
	root: BasePart,
	part: (Builder, Enum.PartType, Vector3, CFrame, Color3, Enum.Material?) -> Part,
	block: (Builder, Vector3, CFrame, Color3, Enum.Material?) -> Part,
	ball: (Builder, Vector3, CFrame, Color3, Enum.Material?) -> Part,
	cyl: (Builder, number, number, CFrame, Color3, Enum.Material?) -> Part,
	wedge: (Builder, Vector3, CFrame, Color3, Enum.Material?) -> WedgePart,
	cone: (Builder, number, number, CFrame, Color3, number?, Enum.Material?) -> { Part },
	eye: (Builder, Vector3, number, Vector3?) -> (),
	limb: (Builder, Vector3, Vector3, number, Color3, Enum.Material?) -> Part,
	finish: (Builder, number?) -> Model,
}

local Builder = {}
Builder.__index = Builder

local function configure(p: BasePart, color: Color3, material: Enum.Material?)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = true
end

function ModelKit.new(name: string): Builder
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	return (setmetatable({ model = model, root = root }, Builder) :: any) :: Builder
end

function Builder.part(self: Builder, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	configure(p, color, material)
	p.Parent = self.model
	return p
end

function Builder.block(self: Builder, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	return self:part(Enum.PartType.Block, size, cf, color, material)
end

function Builder.ball(self: Builder, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	-- Ball parts must be uniform; non-uniform "balls" are cylinders-with-mesh, so use a
	-- SpecialMesh sphere for squashed shapes.
	if size.X == size.Y and size.Y == size.Z then
		return self:part(Enum.PartType.Ball, size, cf, color, material)
	end
	local p = self:part(Enum.PartType.Block, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Cylinder whose axis runs along the CFrame's Y axis (more intuitive than Roblox's X axis)
function Builder.cyl(self: Builder, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	return self:part(
		Enum.PartType.Cylinder,
		Vector3.new(length, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
end

function Builder.wedge(self: Builder, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	configure(p, color, material)
	p.Parent = self.model
	return p
end

-- Stacked cylinders approximating a cone (horns, volcano, hats). Axis along cf's Y.
function Builder.cone(self: Builder, height: number, baseDiameter: number, cf: CFrame, color: Color3, steps: number?, material: Enum.Material?): { Part }
	local n = steps or 5
	local parts = {}
	for i = 0, n - 1 do
		local f = i / n
		local d = baseDiameter * (1 - f) + 0.15
		local h = height / n
		table.insert(parts, self:cyl(h + 0.02, d, cf * CFrame.new(0, h * (i + 0.5), 0), color, material))
	end
	return parts
end

-- Cartoon eye: white ball + black pupil (+ tiny highlight), looking along `look` (default -Z)
function Builder.eye(self: Builder, pos: Vector3, size: number, look: Vector3?)
	local dir = (look or Vector3.new(0, 0, -1)).Unit
	local white = self:ball(Vector3.one * size, CFrame.new(pos), Color3.new(1, 1, 1))
	white.Name = "Eye"
	local pupil = self:ball(Vector3.one * size * 0.55, CFrame.new(pos + dir * size * 0.3), Color3.fromRGB(15, 15, 20))
	pupil.Name = "Pupil"
	local shine = self:ball(Vector3.one * size * 0.18, CFrame.new(pos + dir * size * 0.5 + Vector3.new(size * 0.1, size * 0.12, 0)), Color3.new(1, 1, 1), Enum.Material.Neon)
	shine.Name = "Shine"
end

-- A limb (cylinder) between two points
function Builder.limb(self: Builder, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(math.rad(90), 0, 0)
	return self:cyl(len, diameter, cf, color, material)
end

-- Weld everything to Root, record size attributes and optionally scale the model.
function Builder.finish(self: Builder, scale: number?): Model
	local model = self.model
	local root = self.root
	local top = 0
	local radius = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local p = d :: BasePart
			if p:GetAttribute("Orbit") then
				p.Anchored = true -- moved every frame by the client Animator
			else
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
			top = math.max(top, p.Position.Y + p.Size.Y / 2)
			radius = math.max(radius, Vector2.new(p.Position.X, p.Position.Z).Magnitude + math.min(p.Size.X, p.Size.Z) / 2)
		end
	end
	model:SetAttribute("Height", top)
	model:SetAttribute("Radius", radius)
	if scale and scale ~= 1 then
		ModelKit.scale(model, scale)
	end
	return model
end

function ModelKit.scale(model: Model, factor: number)
	model:ScaleTo(model:GetScale() * factor)
	model:SetAttribute("Height", ((model:GetAttribute("Height") :: number?) or 4) * factor)
	model:SetAttribute("Radius", ((model:GetAttribute("Radius") :: number?) or 2) * factor)
end

-------------------------------------------------------------------------------
-- Mutation look (Golden, Diamond, Rainbow, Shadow, Cosmic, …) — data-driven from
-- MutationConfig, so new mutations need no code.
-------------------------------------------------------------------------------
local SKIP = { Eye = true, Pupil = true, Shine = true, Root = true }

function ModelKit.applyMutation(model: Model, mut: any)
	if not mut or mut.id == "Normal" then
		return
	end
	local i = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not SKIP[d.Name] and d.Transparency < 1 then
			local p = d :: BasePart
			i += 1
			if mut.rainbow then
				p.Color = p.Color:Lerp(Color3.fromHSV((i * 0.13) % 1, 0.75, 1), mut.tintAlpha)
				p:SetAttribute("RainbowOffset", i * 0.13)
			elseif mut.color then
				p.Color = p.Color:Lerp(mut.color, mut.tintAlpha)
			end
			if mut.material and p.Material ~= Enum.Material.Neon then
				p.Material = mut.material
			end
			if mut.reflectance then
				p.Reflectance = mut.reflectance
			end
		end
	end
	if mut.id == "Shadow" then
		for _, d in model:GetDescendants() do
			if d.Name == "Pupil" and d:IsA("BasePart") then
				d.Color = Color3.fromRGB(170, 60, 255)
				d.Material = Enum.Material.Neon
			end
		end
	end
	model:SetAttribute("Rainbow", mut.rainbow == true)
	if mut.sparkle then
		local root = model.PrimaryPart
		if root then
			local att = Instance.new("Attachment")
			att.Name = "SparkleAtt"
			att.Position = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 4) * 0.5, 0)
			att.Parent = root
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "MutationSparkle"
			pe.Color = ColorSequence.new(mut.sparkle)
			pe.LightEmission = 1
			pe.Rate = 6
			pe.Lifetime = NumberRange.new(0.6, 1.2)
			pe.Speed = NumberRange.new(1, 3)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			pe.Parent = att
		end
	end
end

-- Static (server world) use: anchor everything so it never falls
function ModelKit.anchorAll(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

return ModelKit
