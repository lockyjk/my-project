--!strict
-- Themed scenery for every zone island and the hub, in the "chunky storm-toy" style:
--   * organic cliff edges with grassy overhang lips, hanging stalactites and floating islets
--   * waterfalls pouring off the wetter islands
--   * theme props on the outer ring (mushrooms + puddles in Drizzle Meadows, windmills in
--     Breezy Bluffs, lightning rods in Thunder Peaks, snowmen in Frozen Squall, cacti and a
--     pyramid in Sandstorm Dunes, aurora crystals in Aurora Rift, …)
--   * an ambient particle layer per zone (rain, leaves, snow, sand, sparkles, embers)
--
-- Nothing is placed inside the spirit spawn area (island minus a 12-stud ring), on the
-- west entrance / east exit bridges, or near egg stands, so gameplay is unchanged.
-- Every part is tagged Placeholder with an ArtistNote like the rest of the world.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local ZoneScenery = {}

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local rgb = Color3.fromRGB

local TW = Theme.World
local RING = 12 -- spirits never spawn in the outer 12 studs; scenery lives here
local BRIDGE_HALF = Config.World.ZoneSize * 0.25 / 2 + 6

type Ctx = {
	parent: Instance,
	center: Vector3,
	half: number,
	ground: Color3,
	accent: Color3,
	rng: Random,
	avoid: { Vector3 },
}

local function part(parent: Instance, size: Vector3, frame: CFrame, color: Color3, note: string, material: Enum.Material?, shape: Enum.PartType?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = frame
	p.Color = color
	p.Material = material or TW.Material
	p.CanCollide = collide == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("ArtistNote", note)
	CollectionService:AddTag(p, TW.PlaceholderTag)
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, height: number, diameter: number, base: Vector3, color: Color3, note: string, material: Enum.Material?): Part
	return part(parent, v(height, diameter, diameter), cf(base + v(0, height / 2, 0)) * ang(0, 0, rad(90)), color, note, material, Enum.PartType.Cylinder)
end

local function ball(parent: Instance, d: number, pos: Vector3, color: Color3, note: string, material: Enum.Material?): Part
	return part(parent, Vector3.one * d, cf(pos), color, note, material, Enum.PartType.Ball)
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Random spot on the outer ring of the island top, away from bridges and egg stands
local function ringSpot(ctx: Ctx, margin: number?): Vector3?
	local rng = ctx.rng
	for _ = 1, 20 do
		local edge = rng:NextInteger(1, 4)
		local along = rng:NextNumber(-ctx.half + 6, ctx.half - 6)
		local inset = rng:NextNumber(3, RING - 2)
		local off = if edge == 1
			then v(ctx.half - inset, 0, along)
			elseif edge == 2 then v(-ctx.half + inset, 0, along)
			elseif edge == 3 then v(along, 0, ctx.half - inset)
			else v(along, 0, -ctx.half + inset)
		local onBridgeSide = (edge == 1 or edge == 2) and math.abs(along) < BRIDGE_HALF
		local pos = ctx.center + off
		local blocked = onBridgeSide
		for _, a in ctx.avoid do
			if (v(a.X, 0, a.Z) - v(pos.X, 0, pos.Z)).Magnitude < (margin or 18) then
				blocked = true
			end
		end
		if not blocked then
			return pos
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- Island silhouette
-------------------------------------------------------------------------------
local function cliffs(ctx: Ctx)
	local m = model(ctx.parent, "Cliffs")
	local rock = Theme.darken(ctx.ground, 0.4)
	local lip = Theme.darken(ctx.ground, 0.08)
	local rng = ctx.rng
	local top = ctx.center.Y
	for side = 1, 4 do
		local s = -ctx.half
		while s < ctx.half do
			local w = rng:NextNumber(10, 18)
			local mid = s + w / 2
			s += w * 0.85
			local onBridge = (side == 1 or side == 2) and math.abs(mid) < BRIDGE_HALF
			if not onBridge then
				local out = rng:NextNumber(1, 4)
				local h = rng:NextNumber(14, 34)
				local off = if side == 1
					then v(ctx.half + out / 2, 0, mid)
					elseif side == 2 then v(-ctx.half - out / 2, 0, mid)
					elseif side == 3 then v(mid, 0, ctx.half + out / 2)
					else v(mid, 0, -ctx.half - out / 2)
				local size = if side <= 2 then v(out + 3, h, w) else v(w, h, out + 3)
				local pos = ctx.center + off
				part(m, size, cf(pos.X, top - 1.5 - h / 2, pos.Z), rock:Lerp(Theme.Colors.Ink, rng:NextNumber(0, 0.15)), "Cliff rock (irregular island edge)")
				-- grassy lip hanging over the edge
				if rng:NextNumber() < 0.7 then
					local lipSize = if side <= 2 then v(out + 4, 1.4, w * 0.9) else v(w * 0.9, 1.4, out + 4)
					part(m, lipSize, cf(pos.X, top - 0.9, pos.Z), lip, "Grass overhang lip", TW.GroundMaterial)
				end
			end
		end
	end
	-- stalactites under the island
	for _ = 1, 10 do
		local x = rng:NextNumber(-ctx.half * 0.55, ctx.half * 0.55)
		local z = rng:NextNumber(-ctx.half * 0.55, ctx.half * 0.55)
		local h = rng:NextNumber(18, 40)
		local base = ctx.center + v(x, -TW.IslandThickness * 2.2, z)
		for i = 0, 3 do
			local d = (1 - i / 4) * rng:NextNumber(8, 14)
			part(m, v(d, h / 4, d), cf(base - v(0, h / 8 + i * h / 4, 0)) * ang(0, rng:NextNumber(0, 3), 0), rock:Lerp(Theme.Colors.Ink, 0.1 + i * 0.05), "Hanging stalactite")
		end
	end
end

local function islets(ctx: Ctx)
	local m = model(ctx.parent, "FloatingIslets")
	local rng = ctx.rng
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		-- keep clear of the east/west bridge line
		if math.abs(math.sin(a)) < 0.35 then
			a += math.pi / 2
		end
		local dist = ctx.half + rng:NextNumber(26, 60)
		local pos = ctx.center + v(math.cos(a) * dist, rng:NextNumber(-25, 20), math.sin(a) * dist)
		local s = rng:NextNumber(10, 22)
		part(m, v(s, 3, s), cf(pos) * ang(0, rng:NextNumber(0, 3), 0), ctx.ground, "Floating islet top", TW.GroundMaterial, nil, true)
		part(m, v(s * 0.75, s * 0.5, s * 0.75), cf(pos - v(0, s * 0.25 + 1.5, 0)), Theme.darken(ctx.ground, 0.45), "Floating islet rock")
		part(m, v(s * 0.4, s * 0.45, s * 0.4), cf(pos - v(0, s * 0.7 + 1.5, 0)), Theme.darken(ctx.ground, 0.55), "Floating islet rock tip")
		if rng:NextNumber() < 0.6 then
			part(m, v(2, 2, 2), cf(pos + v(0, 2.5, 0)) * ang(rng:NextNumber(0, 1), 0, rng:NextNumber(0, 1)), ctx.accent, "Islet crystal", TW.GlowMaterial)
		end
	end
end

local function waterfall(ctx: Ctx, color: Color3)
	local m = model(ctx.parent, "Waterfall")
	-- off the south edge, away from the bridges
	local x = ctx.rng:NextNumber(-ctx.half * 0.4, ctx.half * 0.4)
	local edge = ctx.center + v(x, 0, ctx.half)
	local stream = part(m, v(10, 0.6, RING), cf(edge + v(0, 0.05, -RING / 2)), color, "Waterfall source stream", Enum.Material.Glass)
	stream.Transparency = 0.25
	local fall = part(m, v(10, 120, 2.5), cf(edge + v(0, -60, 1.5)), color, "Waterfall sheet", Enum.Material.Glass)
	fall.Transparency = 0.35
	local mistPart = part(m, v(12, 1, 4), cf(edge + v(0, -118, 2)), color, "Waterfall mist emitter")
	mistPart.Transparency = 1
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(rgb(230, 245, 255))
	mist.Transparency = NumberSequence.new(0.5, 1)
	mist.Size = NumberSequence.new(4, 10)
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Speed = NumberRange.new(2, 5)
	mist.Rate = 8
	mist.Parent = mistPart
	local foam = part(m, v(12, 1.5, 3), cf(edge + v(0, 0.4, -0.5)), rgb(240, 250, 255), "Waterfall foam lip", Enum.Material.SmoothPlastic)
	foam.Transparency = 0.2
end

-------------------------------------------------------------------------------
-- Theme props
-------------------------------------------------------------------------------
type PropFn = (ctx: Ctx, pos: Vector3, rng: Random) -> ()

local function mushroom(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Mushroom")
	local h = rng:NextNumber(3, 6)
	cyl(m, h, 1.6, pos, rgb(245, 235, 215), "Mushroom stem")
	local capColor = if rng:NextNumber() < 0.6 then rgb(230, 70, 70) else rgb(250, 160, 60)
	local cap = part(m, v(5, 2.2, 5), cf(pos + v(0, h + 0.6, 0)), capColor, "Mushroom cap", TW.Material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	for i = 1, 3 do
		local a = i * 2.1
		ball(m, 0.8, pos + v(math.cos(a) * 1.4, h + 1.3, math.sin(a) * 1.4), rgb(255, 255, 255), "Mushroom spot")
	end
end

local function puddle(ctx: Ctx, pos: Vector3, rng: Random)
	local d = rng:NextNumber(6, 12)
	local p = part(ctx.parent, v(0.2, d, d * 0.7), cf(pos + v(0, 0.08, 0)) * ang(0, 0, rad(90)), ctx.accent, "Rain puddle", Enum.Material.Glass, Enum.PartType.Cylinder)
	p.Transparency = 0.3
end

local function roundTree(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Tree")
	local h = rng:NextNumber(7, 11)
	cyl(m, h, 2, pos, rgb(110, 76, 48), "Tree trunk", Enum.Material.Wood)
	ball(m, rng:NextNumber(9, 12), pos + v(0, h + 3, 0), Theme.darken(ctx.ground, 0.15), "Round canopy", TW.GroundMaterial)
	ball(m, rng:NextNumber(5, 7), pos + v(2.5, h + 5.5, 1), Theme.lighten(ctx.ground, 0.05), "Canopy puff", TW.GroundMaterial)
end

local function pine(ctx: Ctx, pos: Vector3, rng: Random, snowy: boolean?)
	local m = model(ctx.parent, "Pine")
	local s = rng:NextNumber(0.9, 1.4)
	cyl(m, 4 * s, 1.6 * s, pos, rgb(100, 70, 45), "Pine trunk", Enum.Material.Wood)
	for i = 0, 2 do
		local d = (9 - i * 2.4) * s
		part(m, v(3.2 * s, d, d), cf(pos + v(0, (4 + i * 3) * s, 0)) * ang(0, 0, rad(90)), rgb(50, 120, 75), "Pine layer", TW.Material, Enum.PartType.Cylinder)
		if snowy then
			part(m, v(0.8 * s, d * 0.85, d * 0.85), cf(pos + v(0, (5.7 + i * 3) * s, 0)) * ang(0, 0, rad(90)), rgb(245, 250, 255), "Snow cap", Enum.Material.Snow, Enum.PartType.Cylinder)
		end
	end
end

local function windmill(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Windmill")
	local h = 16
	cyl(m, h, 5, pos, rgb(240, 236, 225), "Windmill tower")
	part(m, v(6, 4, 6), cf(pos + v(0, h + 1.5, 0)) * ang(0, rng:NextNumber(0, 3), 0), rgb(200, 70, 60), "Windmill roof", TW.Material, Enum.PartType.Block)
	local hub = cf(pos + v(0, h - 1, 3.2))
	ball(m, 1.6, hub.Position, rgb(80, 60, 50), "Windmill hub")
	for i = 0, 3 do
		part(m, v(1.6, 11, 0.4), hub * ang(0, 0, i * math.pi / 2 + rng:NextNumber(0, 1)) * cf(0, 5.5, 0), rgb(250, 250, 250), "Windmill sail")
	end
end

local function boulder(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Boulders")
	for i = 1, rng:NextInteger(2, 3) do
		local s = rng:NextNumber(3, 7)
		part(m, v(s, s * 0.7, s * 0.9), cf(pos + v(rng:NextNumber(-2, 2), s * 0.3, rng:NextNumber(-2, 2))) * ang(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), 0), Theme.darken(ctx.ground, 0.3 + i * 0.05), "Boulder", Enum.Material.Slate, nil, true)
	end
end

local function grassTuft(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Tuft")
	for _ = 1, 5 do
		local h = rng:NextNumber(1.5, 3.5)
		part(m, v(0.3, h, 0.3), cf(pos + v(rng:NextNumber(-1.5, 1.5), h / 2, rng:NextNumber(-1.5, 1.5))) * ang(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), Theme.lighten(ctx.ground, 0.15), "Tall grass blade")
	end
end

local function lightningRod(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "LightningRod")
	local h = rng:NextNumber(14, 22)
	cyl(m, h, 0.8, pos, rgb(150, 150, 165), "Lightning rod pole", Enum.Material.Metal)
	cyl(m, 1, 3, pos, rgb(70, 70, 80), "Rod base", Enum.Material.Metal)
	local orb = ball(m, 2.4, pos + v(0, h + 1, 0), ctx.accent, "Charged orb", TW.GlowMaterial)
	local light = Instance.new("PointLight")
	light.Color = ctx.accent
	light.Range = 16
	light.Brightness = 1.4
	light.Parent = orb
end

local function crystalCluster(ctx: Ctx, pos: Vector3, rng: Random, colors: { Color3 }?)
	local m = model(ctx.parent, "Crystals")
	for i = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(5, 14)
		local color = if colors then colors[(i % #colors) + 1] else ctx.accent
		part(m, v(2.2, h, 2.2), cf(pos + v(rng:NextNumber(-2.5, 2.5), h / 2 - 0.5, rng:NextNumber(-2.5, 2.5))) * ang(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 3), rng:NextNumber(-0.35, 0.35)), color, "Glowing crystal", TW.GlowMaterial)
	end
end

local function iceBoulder(ctx: Ctx, pos: Vector3, rng: Random)
	local s = rng:NextNumber(4, 8)
	local p = part(ctx.parent, v(s, s * 0.8, s), cf(pos + v(0, s * 0.35, 0)) * ang(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), 0), rgb(190, 230, 255), "Hailstone boulder", Enum.Material.Ice, nil, true)
	p.Transparency = 0.15
	part(ctx.parent, v(s * 0.8, 0.8, s * 0.8), cf(pos + v(0, s * 0.75, 0)) * ang(0, rng:NextNumber(0, 3), 0), rgb(250, 252, 255), "Snow cap", Enum.Material.Snow)
end

local function snowman(ctx: Ctx, pos: Vector3, _rng: Random)
	local m = model(ctx.parent, "Snowman")
	ball(m, 5, pos + v(0, 2.3, 0), rgb(250, 252, 255), "Snowman base", Enum.Material.Snow)
	ball(m, 3.6, pos + v(0, 5.8, 0), rgb(250, 252, 255), "Snowman body", Enum.Material.Snow)
	ball(m, 2.6, pos + v(0, 8.5, 0), rgb(250, 252, 255), "Snowman head", Enum.Material.Snow)
	part(m, v(0.4, 0.4, 1.4), cf(pos + v(0, 8.5, -1.6)), rgb(255, 140, 40), "Carrot nose")
	cyl(m, 1.6, 2.2, pos + v(0, 9.5, 0), rgb(30, 30, 36), "Top hat")
	part(m, v(0.25, 3, 0.25), cf(pos + v(2.2, 6.2, 0)) * ang(0, 0, rad(-50)), rgb(100, 70, 45), "Twig arm", Enum.Material.Wood)
	part(m, v(0.25, 3, 0.25), cf(pos + v(-2.2, 6.2, 0)) * ang(0, 0, rad(50)), rgb(100, 70, 45), "Twig arm", Enum.Material.Wood)
end

local function reeds(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Reeds")
	local pond = part(m, v(0.2, 9, 7), cf(pos + v(0, 0.08, 0)) * ang(0, 0, rad(90)), rgb(60, 110, 120), "Murky pond", Enum.Material.Glass, Enum.PartType.Cylinder)
	pond.Transparency = 0.2
	for _ = 1, 7 do
		local p = pos + v(rng:NextNumber(-4, 4), 0, rng:NextNumber(-3, 3))
		local h = rng:NextNumber(3, 6)
		part(m, v(0.3, h, 0.3), cf(p + v(0, h / 2, 0)), rgb(90, 140, 70), "Reed")
		part(m, v(0.6, 1.4, 0.6), cf(p + v(0, h + 0.3, 0)), rgb(120, 80, 50), "Cattail")
	end
end

local function cactus(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Cactus")
	local h = rng:NextNumber(6, 10)
	local green = rgb(80, 160, 80)
	cyl(m, h, 2.4, pos, green, "Cactus trunk", Enum.Material.Grass)
	ball(m, 2.4, pos + v(0, h, 0), green, "Cactus top", Enum.Material.Grass)
	part(m, v(3, 1.4, 1.4), cf(pos + v(1.8, h * 0.5, 0)), green, "Cactus arm", Enum.Material.Grass)
	cyl(m, 3, 1.4, pos + v(3, h * 0.5, 0), green, "Cactus arm up", Enum.Material.Grass)
	if rng:NextNumber() < 0.5 then
		ball(m, 1, pos + v(0, h + 1.1, 0), rgb(255, 120, 190), "Cactus flower")
	end
end

local function dune(ctx: Ctx, pos: Vector3, rng: Random)
	local s = rng:NextNumber(10, 18)
	local d = part(ctx.parent, v(s, s * 0.45, s * 0.8), cf(pos) * ang(0, rng:NextNumber(0, 3), 0), Theme.lighten(ctx.ground, 0.05), "Sand dune", Enum.Material.Sand)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = d
end

local function obelisk(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "Obelisk")
	local h = rng:NextNumber(14, 24)
	part(m, v(3.5, h, 3.5), cf(pos + v(0, h / 2, 0)) * ang(0, rng:NextNumber(0, 1), 0), rgb(30, 22, 44), "Storm obelisk", Enum.Material.Slate, nil, true)
	part(m, v(3.7, 0.8, 3.7), cf(pos + v(0, h * 0.7, 0)), ctx.accent, "Obelisk glow band", TW.GlowMaterial)
	part(m, v(3.7, 0.8, 3.7), cf(pos + v(0, h * 0.4, 0)), ctx.accent, "Obelisk glow band", TW.GlowMaterial)
	ball(m, 2, pos + v(0, h + 1.5, 0), ctx.accent, "Obelisk eye", TW.GlowMaterial)
end

local function rockPillar(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "RockPillar")
	local layers = rng:NextInteger(3, 5)
	local y = 0
	for i = 1, layers do
		local s = rng:NextNumber(5, 8) * (1 - i * 0.08)
		local h = rng:NextNumber(4, 7)
		part(m, v(s, h, s), cf(pos + v(rng:NextNumber(-0.6, 0.6), y + h / 2, rng:NextNumber(-0.6, 0.6))) * ang(0, rng:NextNumber(0, 3), 0), Theme.darken(ctx.ground, 0.1 + (i % 2) * 0.15), "Canyon rock layer", Enum.Material.Sandstone, nil, true)
		y += h
	end
end

local function candyTree(ctx: Ctx, pos: Vector3, rng: Random)
	local m = model(ctx.parent, "CandyTree")
	local h = rng:NextNumber(6, 9)
	cyl(m, h, 1.4, pos, rgb(255, 255, 255), "Candy stick")
	local colors = { rgb(255, 150, 210), rgb(160, 230, 255), rgb(255, 240, 150), rgb(190, 255, 190) }
	ball(m, rng:NextNumber(7, 9), pos + v(0, h + 2.5, 0), colors[rng:NextInteger(1, #colors)], "Cotton candy canopy")
end

-- theme name → list of { prop, weight }
local THEMES: { [string]: { { fn: PropFn, weight: number } } } = {
	DrizzleMeadows = {
		{ fn = roundTree, weight = 3 },
		{ fn = mushroom, weight = 3 },
		{ fn = puddle, weight = 2 },
		{ fn = grassTuft, weight = 3 },
	},
	BreezyBluffs = {
		{ fn = windmill, weight = 1 },
		{ fn = grassTuft, weight = 4 },
		{ fn = boulder, weight = 2 },
		{ fn = roundTree, weight = 1 },
	},
	ThunderPeaks = {
		{ fn = lightningRod, weight = 3 },
		{ fn = crystalCluster, weight = 2 },
		{ fn = boulder, weight = 3 },
	},
	HailstoneHollow = {
		{ fn = iceBoulder, weight = 4 },
		{ fn = function(ctx, pos, rng)
			pine(ctx, pos, rng, true)
		end, weight = 2 },
	},
	FrozenSquall = {
		{ fn = function(ctx, pos, rng)
			pine(ctx, pos, rng, true)
		end, weight = 4 },
		{ fn = snowman, weight = 1 },
		{ fn = iceBoulder, weight = 2 },
	},
	MonsoonMarsh = {
		{ fn = reeds, weight = 3 },
		{ fn = roundTree, weight = 2 },
		{ fn = mushroom, weight = 2 },
	},
	SandstormDunes = {
		{ fn = cactus, weight = 3 },
		{ fn = dune, weight = 3 },
		{ fn = boulder, weight = 1 },
	},
	AuroraRift = {
		{ fn = function(ctx, pos, rng)
			crystalCluster(ctx, pos, rng, { rgb(100, 255, 180), rgb(160, 120, 255), rgb(90, 200, 255) })
		end, weight = 4 },
		{ fn = function(ctx, pos, rng)
			pine(ctx, pos, rng, true)
		end, weight = 1 },
	},
	CycloneCanyon = {
		{ fn = rockPillar, weight = 4 },
		{ fn = boulder, weight = 2 },
	},
	EyeOfTheStorm = {
		{ fn = obelisk, weight = 3 },
		{ fn = crystalCluster, weight = 2 },
	},
	RainbowLagoon = {
		{ fn = candyTree, weight = 3 },
		{ fn = function(ctx, pos, rng)
			crystalCluster(ctx, pos, rng, { rgb(255, 150, 210), rgb(160, 230, 255), rgb(255, 240, 150) })
		end, weight = 1 },
		{ fn = puddle, weight = 1 },
	},
}

local AMBIENT: { [string]: { texture: string, color: Color3, size: number, speed: number, rate: number, glow: boolean } } = {
	DrizzleMeadows = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(170, 210, 255), size = 0.18, speed = 45, rate = 60, glow = false },
	BreezyBluffs = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(150, 220, 120), size = 0.35, speed = 6, rate = 10, glow = false },
	ThunderPeaks = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(255, 235, 120), size = 0.3, speed = 4, rate = 12, glow = true },
	HailstoneHollow = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(230, 245, 255), size = 0.45, speed = 25, rate = 30, glow = false },
	FrozenSquall = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(255, 255, 255), size = 0.4, speed = 9, rate = 50, glow = false },
	MonsoonMarsh = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(150, 190, 240), size = 0.2, speed = 60, rate = 90, glow = false },
	SandstormDunes = { texture = "rbxasset://textures/particles/smoke_main.dds", color = rgb(230, 200, 140), size = 2.5, speed = 18, rate = 14, glow = false },
	AuroraRift = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(120, 255, 200), size = 0.45, speed = 3, rate = 18, glow = true },
	CycloneCanyon = { texture = "rbxasset://textures/particles/smoke_main.dds", color = rgb(180, 160, 140), size = 2, speed = 22, rate = 10, glow = false },
	EyeOfTheStorm = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(255, 80, 140), size = 0.4, speed = 8, rate = 20, glow = true },
	RainbowLagoon = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = rgb(255, 200, 250), size = 0.45, speed = 3, rate = 16, glow = true },
}

local WET = { DrizzleMeadows = rgb(110, 190, 255), MonsoonMarsh = rgb(80, 150, 200), RainbowLagoon = rgb(160, 230, 255) }

local function ambient(ctx: Ctx, zoneId: string)
	local a = AMBIENT[zoneId]
	if not a then
		return
	end
	local emitterPart = part(ctx.parent, v(ctx.half * 2, 1, ctx.half * 2), cf(ctx.center + v(0, 60, 0)), rgb(255, 255, 255), "Ambient weather emitter")
	emitterPart.Name = "AmbientWeather"
	emitterPart.Transparency = 1
	emitterPart.CanQuery = false
	emitterPart.CastShadow = false
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = a.texture
	pe.Color = ColorSequence.new(a.color)
	pe.Size = NumberSequence.new(a.size)
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(60 / math.max(4, a.speed), 80 / math.max(4, a.speed))
	pe.Speed = NumberRange.new(a.speed * 0.8, a.speed)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.SpreadAngle = Vector2.new(15, 15)
	pe.Rate = a.rate
	pe.LightEmission = if a.glow then 1 else 0
	pe.Parent = emitterPart
end

function ZoneScenery.decorate(parent: Instance, zoneDef: any, layout: any, rng: Random)
	local avoid = { layout.spawn.Position }
	if layout.eggStand then
		table.insert(avoid, layout.eggStand)
	end
	for _, pos in layout.specials do
		table.insert(avoid, pos)
	end
	local ctx: Ctx = {
		parent = parent,
		center = layout.center,
		half = layout.size / 2,
		ground = zoneDef.ground,
		accent = zoneDef.accent,
		rng = rng,
		avoid = avoid,
	}
	cliffs(ctx)
	islets(ctx)
	local wet = WET[zoneDef.id]
	if wet then
		waterfall(ctx, wet)
	end
	local theme = THEMES[zoneDef.id]
	if theme then
		local total = 0
		for _, t in theme do
			total += t.weight
		end
		for _ = 1, 26 do
			local pos = ringSpot(ctx)
			if pos then
				local x = rng:NextNumber() * total
				for _, t in theme do
					x -= t.weight
					if x <= 0 then
						t.fn(ctx, pos, rng)
						break
					end
				end
			end
		end
	end
	ambient(ctx, zoneDef.id)
end

-------------------------------------------------------------------------------
-- Hub: a storm-tower centrepiece, lamp ring, benches, flags and clouds
-------------------------------------------------------------------------------
function ZoneScenery.decorateHub(parent: Instance, center: Vector3)
	local m = model(parent, "HubScenery")
	local charge = Theme.Colors.Charge
	local static = Theme.Colors.Static
	-- storm tower
	local base = center
	local plinth = cyl(m, 3, 16, base, Theme.Colors.PanelDark, "Storm tower plinth", nil)
	plinth.CanCollide = true
	local column = cyl(m, 26, 5, base + v(0, 3, 0), Theme.Colors.PanelLight, "Storm tower column")
	column.CanCollide = true
	for i = 0, 2 do
		part(m, v(1, 12 - i * 2.5, 12 - i * 2.5), cf(base + v(0, 10 + i * 7, 0)) * ang(0, 0, rad(90)), if i % 2 == 0 then charge else static, "Floating charge ring", TW.GlowMaterial, Enum.PartType.Cylinder)
	end
	local orb = ball(m, 7, base + v(0, 33, 0), charge, "Storm tower orb", TW.GlowMaterial)
	local light = Instance.new("PointLight")
	light.Color = charge
	light.Range = 50
	light.Brightness = 2
	light.Parent = orb
	-- lamps around the plaza edge, placed between the home-plot sky bridges (which leave
	-- the hub every 25° from 42.5° to 317.5°) and never on the zone bridge to the south
	for k = 0, 12 do
		local a = rad(30 + k * 25)
		local p = center + v(math.sin(a) * 50, 0, math.cos(a) * 50)
		cyl(m, 9, 0.8, p, rgb(60, 60, 70), "Hub lamp post", Enum.Material.Metal)
		local bulb = ball(m, 1.8, p + v(0, 9.5, 0), if k % 2 == 0 then charge else static, "Hub lamp", TW.GlowMaterial)
		local l = Instance.new("PointLight")
		l.Color = bulb.Color
		l.Range = 18
		l.Parent = bulb
	end
	-- benches
	for _, a in { 1.2, 2.0, 4.3, 4.9 } do
		local p = center + v(math.sin(a) * 34, 0, math.cos(a) * 34)
		local face = CFrame.lookAt(p, v(center.X, p.Y, center.Z))
		part(m, v(7, 0.6, 2), face * cf(0, 1.6, 0), rgb(150, 105, 65), "Bench seat", Enum.Material.WoodPlanks, nil, true)
		part(m, v(7, 2, 0.4), face * cf(0, 2.7, 1), rgb(150, 105, 65), "Bench back", Enum.Material.WoodPlanks, nil, true)
		part(m, v(0.6, 1.6, 2), face * cf(-3, 0.8, 0), rgb(60, 60, 70), "Bench leg", Enum.Material.Metal)
		part(m, v(0.6, 1.6, 2), face * cf(3, 0.8, 0), rgb(60, 60, 70), "Bench leg", Enum.Material.Metal)
	end
	-- clouds drifting around the hub
	local rng = Random.new(99)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local p = center + v(math.sin(a) * 95, rng:NextNumber(-20, 25), math.cos(a) * 95)
		for _ = 1, 4 do
			local s = rng:NextNumber(8, 16)
			part(m, v(s, s * 0.7, s), cf(p + v(rng:NextNumber(-10, 10), rng:NextNumber(-3, 4), rng:NextNumber(-6, 6))), TW.CloudColor, "Hub cloud puff")
		end
	end
end

return ZoneScenery
