--!strict
-- Builds the chunky placeholder creature models used for spirits and Stormlings.
-- Look: primitive body (ball/block/cylinder/wedge), glowing inner core, two block eyes,
-- accent ears/fins for pets. Every part is tagged Placeholder with an ArtistNote.
-- Artists: put a Model named after the spirit/pet id in ReplicatedStorage.Art.Creatures
-- (with a PrimaryPart) and it will be cloned instead.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local ModelFactory = {}

export type CreatureSpec = {
	id: string,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
	size: number,
	color: Color3,
	accent: Color3?,
	glow: boolean?,
	pet: boolean?,
	aura: Color3?, -- rarity aura particles
	tierGlow: number?, -- 0..1 extra glow for fused tiers
}

local function tag(p: BasePart, note: string)
	p:SetAttribute("ArtistNote", note)
	CollectionService:AddTag(p, Theme.World.PlaceholderTag)
end

local function basePart(className: string, parent: Instance, name: string): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Theme.World.Material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function override(id: string): Model?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local folder = art and art:FindFirstChild("Creatures")
	local source = folder and folder:FindFirstChild(id)
	if source and source:IsA("Model") and source.PrimaryPart then
		return source:Clone()
	end
	return nil
end

function ModelFactory.creature(spec: CreatureSpec): Model
	local custom = override(spec.id)
	if custom then
		custom:ScaleTo(spec.size / 3)
		return custom
	end
	local m = Instance.new("Model")
	m.Name = spec.id
	local s = spec.size
	local kind = if spec.pet then "Stormling" else "Spirit"

	local body: BasePart
	if spec.shape == "Wedge" then
		body = basePart("WedgePart", m, "Body")
		body.Size = Vector3.new(s, s * 0.9, s * 1.1)
	else
		local part = basePart("Part", m, "Body") :: Part
		if spec.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * s
		elseif spec.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(s * 0.9, s, s)
		else
			part.Size = Vector3.new(s, s * 0.9, s)
		end
		body = part
	end
	body.Color = spec.color
	body.Transparency = if spec.glow then 0.25 else 0.1
	tag(body, `{kind} body: {spec.id}`)
	m.PrimaryPart = body

	-- Glowing core visible through the body
	local core = basePart("Part", m, "Core") :: Part
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one * s * 0.5
	core.Material = Theme.World.GlowMaterial
	core.Color = Theme.lighten(spec.accent or spec.color, 0.3)
	core.CFrame = body.CFrame
	tag(core, `{kind} glowing core`)

	-- Eyes on the front face (-Z)
	for _, side in { -1, 1 } do
		local eye = basePart("Part", m, "Eye")
		eye.Size = Vector3.new(s * 0.14, s * 0.24, s * 0.08)
		eye.Color = Theme.Colors.Ink
		eye.CFrame = body.CFrame * CFrame.new(side * s * 0.2, s * 0.12, -s * 0.5)
		tag(eye, `{kind} eye`)
		local shine = basePart("Part", m, "EyeShine")
		shine.Size = Vector3.new(s * 0.05, s * 0.07, s * 0.02)
		shine.Color = Color3.new(1, 1, 1)
		shine.Material = Theme.World.GlowMaterial
		shine.CFrame = eye.CFrame * CFrame.new(s * 0.03, s * 0.06, -s * 0.05)
		tag(shine, `{kind} eye highlight`)
	end

	if spec.pet then
		-- chunky ears / fins in the accent colour
		for _, side in { -1, 1 } do
			local ear = basePart("WedgePart", m, "Ear")
			ear.Size = Vector3.new(s * 0.18, s * 0.4, s * 0.3)
			ear.Color = spec.accent or spec.color
			ear.CFrame = body.CFrame * CFrame.new(side * s * 0.3, s * 0.55, 0) * CFrame.Angles(0, math.rad(90), 0)
			tag(ear, "Stormling ear/fin")
		end
		-- little feet
		for _, side in { -1, 1 } do
			local foot = basePart("Part", m, "Foot")
			foot.Size = Vector3.new(s * 0.22, s * 0.14, s * 0.26)
			foot.Color = Theme.darken(spec.color, 0.25)
			foot.CFrame = body.CFrame * CFrame.new(side * s * 0.22, -s * 0.5, -s * 0.05)
			tag(foot, "Stormling foot")
		end
	end

	if spec.glow then
		local light = Instance.new("PointLight")
		light.Color = spec.color
		light.Range = s * 4
		light.Brightness = 2
		light.Parent = core
	end
	if spec.aura then
		local attach = Instance.new("Attachment")
		attach.Parent = body
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(spec.aura)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.18), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.2)
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Rate = 6 + (spec.tierGlow or 0) * 20
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = attach
	end
	if spec.tierGlow and spec.tierGlow > 0 then
		local halo = basePart("Part", m, "Halo") :: Part
		halo.Shape = Enum.PartType.Cylinder
		halo.Size = Vector3.new(0.3, s * 1.1, s * 1.1)
		halo.Material = Theme.World.GlowMaterial
		halo.Color = spec.aura or Theme.Colors.Charge
		halo.Transparency = 1 - spec.tierGlow * 0.8
		halo.CFrame = body.CFrame * CFrame.new(0, s * 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
		tag(halo, "Fusion tier halo")
	end
	return m
end

return ModelFactory
