--!strict
-- Placeholder Brainrot models built from parts (see ModelKit for the conventions).
-- Each builder takes the config `look` (colours) so recoloured variants are free.
-- Feet sit on Y = 0, the creature faces -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(script.Parent.ModelKit)
local Registry = require(script.Parent.Parent.Registry)
local Types = require(script.Parent.Parent.Types)

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local rgb = Color3.fromRGB

local WHITE = rgb(255, 255, 255)
local BLACK = rgb(20, 20, 26)
local DARK = rgb(40, 28, 30)

type Builder = ModelKit.Builder
type Look = Types.Look

local builders: { [string]: (Builder, Look) -> () } = {}

-- Shared bits ---------------------------------------------------------------

local function smile(b: Builder, center: Vector3, width: number)
	-- three tilted blocks make a curved grin
	b:block(v(width * 0.45, 0.14, 0.12), cf(center + v(-width * 0.3, 0.06, 0)) * ang(0, 0, rad(-18)), DARK)
	b:block(v(width * 0.4, 0.14, 0.12), cf(center + v(0, -0.04, 0)), DARK)
	b:block(v(width * 0.45, 0.14, 0.12), cf(center + v(width * 0.3, 0.06, 0)) * ang(0, 0, rad(18)), DARK)
end

local function sneaker(b: Builder, pos: Vector3, color: Color3)
	b:block(v(0.75, 0.45, 1.15), cf(pos + v(0, 0.22, -0.15)), color)
	b:block(v(0.8, 0.12, 1.2), cf(pos + v(0, 0.04, -0.15)), WHITE)
end

local function leg(b: Builder, hip: Vector3, foot: Vector3, d: number, color: Color3, shoe: Color3)
	b:limb(hip, foot + v(0, 0.35, 0), d, color)
	sneaker(b, foot, shoe)
end

-- 🍌 Bananini Bongo ------------------------------------------------------------
builders.Banana = function(b: Builder, look: Look)
	local yellow, brown, red = look.primary, look.secondary, look.accent
	-- curved body: points on an arc that bends backwards
	local pts = {}
	for i = 0, 5 do
		local tt = i / 5
		table.insert(pts, v(0, 1.25 + tt * 4.1, 0.9 * (tt - 0.5) ^ 2 * 4 - 0.75))
	end
	for i = 1, #pts - 1 do
		local tt = (i - 0.5) / (#pts - 1)
		local d = 1.15 + math.sin(tt * math.pi) * 0.75
		b:limb(pts[i], pts[i + 1], d, yellow)
		b:ball(Vector3.one * d, cf(pts[i + 1]), yellow)
	end
	b:ball(Vector3.one * 1.0, cf(pts[1]), yellow)
	b:ball(Vector3.one * 0.55, cf(pts[1] + v(0, -0.35, 0.05)), brown) -- bottom tip
	b:limb(pts[#pts], pts[#pts] + v(0, 0.6, 0.35), 0.4, brown) -- stem
	-- peel flaps opening at the top
	for k = 0, 2 do
		local a = rad(k * 120 + 30)
		local dir = v(math.cos(a), 0, math.sin(a))
		local base = pts[#pts - 1] + dir * 0.55
		b:block(v(0.75, 1.6, 0.18), CFrame.lookAt(base, base + dir) * cf(0, -0.4, -0.2) * ang(rad(-35), 0, 0), yellow)
	end
	-- face
	local face = pts[3] + v(0, 0.45, -0.95)
	b:eye(face + v(-0.38, 0.35, 0), 0.62)
	b:eye(face + v(0.38, 0.35, 0), 0.62)
	smile(b, face + v(0, -0.3, -0.08), 0.9)
	b:block(v(0.42, 0.12, 0.1), cf(face + v(-0.42, 0.78, 0)) * ang(0, 0, rad(12)), brown) -- eyebrows
	b:block(v(0.42, 0.12, 0.1), cf(face + v(0.42, 0.78, 0)) * ang(0, 0, rad(-12)), brown)
	-- boxing arms
	for _, s in { -1, 1 } do
		local shoulder = pts[3] + v(0.75 * s, -0.1, -0.2)
		local hand = shoulder + v(0.9 * s, -0.5, -0.9)
		b:limb(shoulder, hand, 0.28, brown)
		b:cyl(0.35, 0.75, CFrame.lookAt(hand, hand + v(0, 0, -1)) * ang(rad(90), 0, 0), WHITE)
		b:ball(Vector3.one * 1.0, cf(hand + v(0, 0, -0.45)), red)
		b:ball(Vector3.one * 0.38, cf(hand + v(0.3 * s, 0.25, -0.35)), red) -- thumb
	end
	-- legs + red shoes
	for _, s in { -1, 1 } do
		leg(b, pts[1] + v(0.35 * s, 0.1, 0), v(0.5 * s, 0, -0.1), 0.26, brown, red)
	end
end

-- 🍕 Pizzarino Mozzarino --------------------------------------------------------
builders.Pizza = function(b: Builder, look: Look)
	local cheese, crust, pep = look.primary, look.secondary, look.accent
	local h, half, thick, yc = 4.4, 1.9, 0.6, 3.4
	-- two wedges make a downward-pointing triangle
	b:wedge(v(thick, h, half), cf(half / 2, yc, 0) * ang(0, rad(90), 0) * ang(rad(180), 0, 0), cheese)
	b:wedge(v(thick, h, half), cf(-half / 2, yc, 0) * ang(0, rad(-90), 0) * ang(rad(180), 0, 0), cheese)
	-- crust along the top
	b:part(Enum.PartType.Cylinder, v(half * 2 + 0.6, 1.0, 1.0), cf(0, yc + h / 2 + 0.25, 0.05), crust)
	b:ball(Vector3.one * 1.0, cf(-half - 0.3, yc + h / 2 + 0.25, 0.05), crust)
	b:ball(Vector3.one * 1.0, cf(half + 0.3, yc + h / 2 + 0.25, 0.05), crust)
	-- pepperoni + olives on the front face
	local front = -thick / 2 - 0.04
	for _, p in { v(-0.9, 4.6, 0), v(0.7, 4.85, 0), v(0.1, 3.7, 0), v(-0.35, 2.6, 0), v(0.95, 3.4, 0) } do
		b:part(Enum.PartType.Cylinder, v(0.12, 0.75, 0.75), cf(p.X, p.Y, front) * ang(0, rad(90), 0), pep)
	end
	b:part(Enum.PartType.Cylinder, v(0.12, 0.35, 0.35), cf(-0.95, 3.4, front) * ang(0, rad(90), 0), BLACK)
	b:part(Enum.PartType.Cylinder, v(0.12, 0.35, 0.35), cf(0.5, 2.2, front) * ang(0, rad(90), 0), BLACK)
	-- cheese drips on both sides
	for _, d in { v(-1.25, 3.6, 0), v(1.15, 2.8, 0), v(-0.6, 1.9, 0) } do
		b:block(v(0.3, 0.9, 0.35), cf(d.X, d.Y, 0), cheese)
		b:ball(Vector3.one * 0.38, cf(d.X, d.Y - 0.5, 0), cheese)
	end
	-- face
	b:eye(v(-0.5, 4.55, front - 0.12), 0.7)
	b:eye(v(0.5, 4.55, front - 0.12), 0.7)
	smile(b, v(0, 3.95, front - 0.1), 0.9)
	-- stretchy cheese arms
	for _, s in { -1, 1 } do
		local shoulder = v(1.3 * s, 4.1, 0)
		local elbow = v(2.2 * s, 3.4, -0.3)
		local hand = v(2.4 * s, 2.5, -0.7)
		b:limb(shoulder, elbow, 0.28, cheese)
		b:limb(elbow, hand, 0.24, cheese)
		b:ball(Vector3.one * 0.55, cf(hand), crust)
	end
	-- legs
	for _, s in { -1, 1 } do
		leg(b, v(0.32 * s, 1.5, 0), v(0.45 * s, 0, -0.05), 0.26, crust, rgb(60, 140, 60))
	end
end

-- 🌵 Cactoboom ------------------------------------------------------------------
builders.Cactus = function(b: Builder, look: Look)
	local green, hatC, flower = look.primary, look.secondary, look.accent
	local darkGreen = green:Lerp(BLACK, 0.3)
	b:cyl(3.6, 2.5, cf(0, 2.6, 0), green)
	b:ball(Vector3.one * 2.5, cf(0, 4.4, 0), green)
	b:ball(v(2.6, 1.2, 2.6), cf(0, 0.85, 0), green)
	-- ribs
	for k = 0, 5 do
		local a = rad(k * 60 + 30)
		b:block(v(0.18, 3.8, 0.18), cf(math.cos(a) * 1.22, 2.6, math.sin(a) * 1.22), darkGreen)
	end
	-- arms (one up, one down)
	b:cyl(1.0, 0.95, cf(1.55, 2.7, 0) * ang(0, 0, rad(90)), green)
	b:cyl(1.6, 0.95, cf(2.05, 3.45, 0), green)
	b:ball(Vector3.one * 0.95, cf(2.05, 4.25, 0), green)
	b:cyl(1.0, 0.85, cf(-1.55, 2.2, 0) * ang(0, 0, rad(90)), green)
	b:cyl(1.0, 0.85, cf(-2.0, 2.55, 0), green)
	b:ball(Vector3.one * 0.85, cf(-2.0, 3.05, 0), green)
	-- spines
	local rng = Random.new(7)
	for _ = 1, 22 do
		local a = rng:NextNumber(0, math.pi * 2)
		local y = rng:NextNumber(1.2, 4.6)
		local n = v(math.cos(a), 0, math.sin(a))
		local p = n * 1.28 + v(0, y, 0)
		b:block(v(0.08, 0.08, 0.45), CFrame.lookAt(p, p + n) * cf(0, 0, -0.15), rgb(255, 250, 220))
	end
	-- face
	b:eye(v(-0.45, 3.65, -1.15), 0.62)
	b:eye(v(0.45, 3.65, -1.15), 0.62)
	b:block(v(1.1, 0.28, 0.25), cf(0, 3.05, -1.22) * ang(0, 0, 0), DARK) -- mustache
	b:ball(v(0.6, 0.35, 0.3), cf(-0.55, 2.98, -1.2) * ang(0, 0, rad(25)), DARK)
	b:ball(v(0.6, 0.35, 0.3), cf(0.55, 2.98, -1.2) * ang(0, 0, rad(-25)), DARK)
	-- cowboy hat
	local hatCf = cf(0, 5.45, 0) * ang(rad(-8), 0, rad(6))
	b:cyl(0.16, 3.6, hatCf, hatC)
	b:block(v(3.2, 0.12, 0.9), hatCf * cf(0, 0.12, 1.25) * ang(rad(-20), 0, 0), hatC)
	b:block(v(3.2, 0.12, 0.9), hatCf * cf(0, 0.12, -1.25) * ang(rad(20), 0, 0), hatC)
	b:cyl(1.0, 1.9, hatCf * cf(0, 0.55, 0), hatC)
	b:cyl(0.25, 1.95, hatCf * cf(0, 0.25, 0), rgb(200, 40, 40))
	-- flower
	for k = 0, 4 do
		local a = rad(k * 72)
		b:ball(v(0.45, 0.2, 0.45), cf(1.0 + math.cos(a) * 0.3, 4.95, -0.4 + math.sin(a) * 0.3), flower)
	end
	b:ball(Vector3.one * 0.3, cf(1.0, 5.0, -0.4), rgb(255, 230, 60))
	-- stubby feet
	b:ball(v(0.9, 0.6, 1.2), cf(-0.6, 0.3, -0.4), darkGreen)
	b:ball(v(0.9, 0.6, 1.2), cf(0.6, 0.3, -0.4), darkGreen)
end

-- 🐸 Froggolino Gelatino --------------------------------------------------------
builders.Frog = function(b: Builder, look: Look)
	local jelly, core, shine = look.primary, look.secondary, look.accent
	local function jellyPart(p: BasePart)
		p.Material = Enum.Material.Glass
		p.Transparency = 0.25
		p.Reflectance = 0.1
	end
	jellyPart(b:ball(v(4.2, 3.0, 4.4), cf(0, 1.75, 0.2), jelly))
	jellyPart(b:ball(v(3.6, 2.3, 2.8), cf(0, 2.45, -1.2), jelly))
	b:ball(Vector3.one * 1.7, cf(0, 1.9, 0.3), core, Enum.Material.Neon)
	b:ball(Vector3.one * 0.7, cf(0.6, 2.4, 1.0), core:Lerp(WHITE, 0.3), Enum.Material.Neon)
	-- eye domes
	for _, s in { -1, 1 } do
		jellyPart(b:ball(Vector3.one * 1.45, cf(0.95 * s, 3.55, -1.35), jelly))
		b:eye(v(0.95 * s, 3.65, -1.85), 0.85)
	end
	b:block(v(2.6, 0.14, 0.14), cf(0, 2.15, -2.55), DARK) -- wide mouth
	b:ball(v(0.9, 0.35, 0.3), cf(-0.9, 2.3, -2.4), rgb(255, 120, 160)) -- cheeks
	b:ball(v(0.9, 0.35, 0.3), cf(0.9, 2.3, -2.4), rgb(255, 120, 160))
	-- legs
	for _, s in { -1, 1 } do
		jellyPart(b:ball(v(1.5, 1.4, 2.6), cf(1.85 * s, 0.85, 0.9), jelly))
		jellyPart(b:ball(v(1.2, 0.35, 1.7), cf(2.1 * s, 0.18, -0.2), jelly))
		jellyPart(b:limb(v(1.1 * s, 1.2, -1.4), v(1.3 * s, 0.25, -2.0), 0.55, jelly))
		jellyPart(b:ball(v(0.9, 0.3, 0.9), cf(1.35 * s, 0.15, -2.2), jelly))
	end
	-- glossy highlights
	b:ball(v(1.0, 0.3, 0.6), cf(-0.8, 3.15, 0.3), shine, Enum.Material.Neon).Transparency = 0.3
	b:ball(v(0.5, 0.2, 0.4), cf(0.9, 3.0, 0.9), shine, Enum.Material.Neon).Transparency = 0.3
end

-- 🐊 Bombardiro Gatoro ----------------------------------------------------------
builders.Gator = function(b: Builder, look: Look)
	local green, metal, fuse = look.primary, look.secondary, look.accent
	local belly = rgb(220, 210, 150)
	local dark = green:Lerp(BLACK, 0.35)
	b:ball(v(3.2, 2.4, 6.4), cf(0, 1.9, 0.6), green)
	b:ball(v(2.6, 1.4, 5.4), cf(0, 1.35, 0.4), belly)
	b:block(v(2.5, 1.5, 2.4), cf(0, 2.3, -2.9), green)
	b:block(v(2.0, 0.85, 3.2), cf(0, 2.05, -5.3), green)
	b:block(v(1.9, 0.5, 3.0), cf(0, 1.45, -5.1), dark) -- lower jaw
	-- teeth
	for i = 0, 5 do
		for _, s in { -1, 1 } do
			b:wedge(v(0.12, 0.35, 0.25), cf(0.9 * s, 1.75, -4.0 - i * 0.5) * ang(rad(180), 0, 0), WHITE)
		end
	end
	b:ball(Vector3.one * 0.3, cf(-0.45, 2.5, -6.8), BLACK)
	b:ball(Vector3.one * 0.3, cf(0.45, 2.5, -6.8), BLACK)
	-- eyes on bumps + aviator goggles
	for _, s in { -1, 1 } do
		b:ball(Vector3.one * 1.0, cf(0.7 * s, 3.1, -3.3), green)
		b:eye(v(0.7 * s, 3.3, -3.65), 0.7)
		b:cyl(0.2, 0.95, cf(0.7 * s, 3.3, -3.95) * ang(rad(90), 0, 0), rgb(120, 80, 40))
	end
	b:block(v(2.7, 0.22, 0.3), cf(0, 3.3, -3.55), rgb(120, 80, 40))
	-- tail
	for i = 1, 5 do
		local d = 1.9 - i * 0.28
		b:ball(v(d, d * 0.7, 1.6), cf(0, 1.65 - i * 0.18, 3.2 + i * 1.1), green)
		b:wedge(v(0.2, 0.45, 0.6), cf(0, 1.65 - i * 0.18 + d * 0.35 + 0.15, 3.2 + i * 1.1), dark)
	end
	-- back ridges
	for i = 0, 4 do
		b:wedge(v(0.25, 0.5, 0.7), cf(0, 3.15, -1.2 + i * 1.0), dark)
	end
	-- legs
	for _, s in { -1, 1 } do
		for _, z in { -1.6, 2.4 } do
			b:limb(v(1.3 * s, 1.5, z), v(1.8 * s, 0.25, z - 0.2), 0.75, green)
			b:ball(v(0.9, 0.4, 1.2), cf(1.85 * s, 0.2, z - 0.5), dark)
		end
	end
	-- the giant cartoon cannon (strapped to the back, aimed forward and up)
	local cannonCf = cf(0, 4.35, 0.2) * ang(rad(-72), 0, 0)
	b:cyl(5.0, 1.7, cannonCf, metal, Enum.Material.Metal)
	b:cyl(0.5, 2.2, cannonCf * cf(0, 2.45, 0), metal, Enum.Material.Metal)
	b:cyl(0.3, 2.0, cannonCf * cf(0, 0.6, 0), fuse, Enum.Material.Metal)
	b:cyl(0.3, 2.0, cannonCf * cf(0, -1.4, 0), fuse, Enum.Material.Metal)
	b:ball(Vector3.one * 1.8, cannonCf * cf(0, -2.5, 0), metal, Enum.Material.Metal)
	b:cyl(0.6, 1.2, cannonCf * cf(0, 2.75, 0), BLACK) -- muzzle hole
	b:limb(v(0, 4.5, 2.6), v(0.3, 5.4, 3.0), 0.15, rgb(90, 70, 50))
	local spark = b:ball(Vector3.one * 0.45, cf(0.3, 5.55, 3.05), fuse, Enum.Material.Neon)
	spark.Name = "FuseSpark"
	-- straps
	b:block(v(3.4, 0.35, 0.5), cf(0, 2.9, 0.2) * ang(rad(10), 0, 0), rgb(100, 60, 30))
	b:block(v(3.4, 0.35, 0.5), cf(0, 2.95, 1.8) * ang(rad(-10), 0, 0), rgb(100, 60, 30))
end

-- 🦈 Sharkalero Jetto -----------------------------------------------------------
builders.Shark = function(b: Builder, look: Look)
	local blue, belly, flame = look.primary, look.secondary, look.accent
	local metal = rgb(170, 175, 185)
	b:ball(v(3.0, 3.0, 7.4), cf(0, 3.3, 0), blue)
	b:ball(v(2.6, 2.0, 6.4), cf(0, 2.75, -0.3), belly)
	b:ball(v(2.2, 2.0, 2.2), cf(0, 3.4, -3.3), blue) -- rounded snout
	-- mouth with teeth
	b:block(v(1.9, 0.5, 0.5), cf(0, 2.75, -3.75) * ang(rad(-10), 0, 0), DARK)
	for i = -3, 3 do
		b:wedge(v(0.18, 0.3, 0.2), cf(i * 0.26, 2.95, -3.98) * ang(rad(180), 0, 0), WHITE)
	end
	-- eyes + sunglasses
	b:eye(v(-0.95, 3.85, -2.8), 0.6, v(-0.3, 0, -1))
	b:eye(v(0.95, 3.85, -2.8), 0.6, v(0.3, 0, -1))
	b:block(v(2.4, 0.5, 0.15), cf(0, 3.9, -3.12), BLACK, Enum.Material.Glass)
	b:block(v(2.6, 0.12, 0.15), cf(0, 4.12, -3.1), BLACK)
	-- fins
	b:wedge(v(0.35, 2.3, 2.2), cf(0, 5.6, 0.6), blue)
	b:wedge(v(0.3, 2.0, 1.6), cf(0, 4.4, 4.7) * ang(rad(-30), 0, 0), blue)
	b:wedge(v(0.3, 1.6, 1.4), cf(0, 2.5, 4.6) * ang(rad(200), 0, 0), blue)
	for _, s in { -1, 1 } do
		b:wedge(v(0.25, 1.0, 1.6), cf(1.6 * s, 2.6, -0.8) * ang(0, 0, rad(-70 * s)), blue)
	end
	-- jet engines
	for _, s in { -1, 1 } do
		local base = v(1.85 * s, 4.1, 0.9)
		b:cyl(3.2, 1.25, cf(base) * ang(rad(90), 0, 0), metal, Enum.Material.Metal)
		b:cyl(0.4, 1.45, cf(base + v(0, 0, -1.6)) * ang(rad(90), 0, 0), rgb(60, 60, 70), Enum.Material.Metal)
		b:cyl(0.5, 1.1, cf(base + v(0, 0, 1.7)) * ang(rad(90), 0, 0), rgb(50, 50, 55), Enum.Material.Metal)
		local nozzle = b:cyl(0.3, 0.9, cf(base + v(0, 0, 2.0)) * ang(rad(90), 0, 0), flame, Enum.Material.Neon)
		nozzle.Name = "Thruster"
		local att = Instance.new("Attachment")
		att.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 1, 0)) -- emit along cylinder axis
		att.Parent = nozzle
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(flame, rgb(255, 230, 120))
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
		fire.Lifetime = NumberRange.new(0.15, 0.3)
		fire.Speed = NumberRange.new(8, 12)
		fire.Rate = 40
		fire.EmissionDirection = Enum.NormalId.Bottom
		fire.Parent = att
	end
	b:block(v(4.0, 0.3, 0.6), cf(0, 4.4, 0.9), rgb(60, 60, 70)) -- harness
	-- legs + sneakers
	for _, s in { -1, 1 } do
		leg(b, v(0.65 * s, 2.2, 0.6), v(0.75 * s, 0, 0.4), 0.45, blue, rgb(40, 120, 255))
	end
end

-- 🐘 Volcanico Elefanto ---------------------------------------------------------
builders.Elephant = function(b: Builder, look: Look)
	local rock, lava, tusk = look.primary, look.secondary, look.accent
	local mat = Enum.Material.Basalt
	b:ball(v(5.6, 4.8, 7.2), cf(0, 4.4, 0.6), rock, mat)
	b:ball(Vector3.one * 4.2, cf(0, 5.6, -3.0), rock, mat)
	-- trunk (curls forward at the end)
	local trunk = { v(0, 4.9, -4.7), v(0, 3.6, -5.4), v(0, 2.4, -5.6), v(0, 1.5, -5.9), v(0, 1.4, -6.6), v(0, 1.9, -7.0) }
	for i = 1, #trunk - 1 do
		local d = 1.4 - i * 0.16
		b:limb(trunk[i], trunk[i + 1], d, rock, mat)
		b:ball(Vector3.one * d, cf(trunk[i + 1]), rock, mat)
	end
	-- ears
	for _, s in { -1, 1 } do
		b:ball(v(0.5, 3.6, 3.2), cf(2.3 * s, 5.6, -2.3) * ang(0, rad(-25 * s), 0), rock, mat)
		b:ball(v(0.3, 2.6, 2.2), cf(2.45 * s, 5.6, -2.45) * ang(0, rad(-25 * s), 0), lava, Enum.Material.Neon)
	end
	-- tusks
	for _, s in { -1, 1 } do
		b:limb(v(0.85 * s, 4.3, -4.5), v(1.1 * s, 3.2, -5.6), 0.5, tusk)
		b:limb(v(1.1 * s, 3.2, -5.6), v(1.05 * s, 3.4, -6.3), 0.38, tusk)
	end
	-- glowing eyes
	b:ball(Vector3.one * 0.6, cf(-1.25, 6.2, -4.6), lava, Enum.Material.Neon)
	b:ball(Vector3.one * 0.6, cf(1.25, 6.2, -4.6), lava, Enum.Material.Neon)
	b:block(v(0.9, 0.2, 0.2), cf(-1.25, 6.65, -4.6) * ang(0, 0, rad(-15)), BLACK)
	b:block(v(0.9, 0.2, 0.2), cf(1.25, 6.65, -4.6) * ang(0, 0, rad(15)), BLACK)
	-- legs
	for _, s in { -1, 1 } do
		for _, z in { -1.5, 2.6 } do
			b:cyl(2.8, 1.9, cf(1.7 * s, 1.4, z), rock, mat)
			b:cyl(0.4, 2.1, cf(1.7 * s, 0.2, z), lava, Enum.Material.Neon)
		end
	end
	-- lava cracks across the body (points on the ellipsoid surface)
	local rng = Random.new(11)
	for _ = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local e = rng:NextNumber(-0.6, 0.9)
		local n = v(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e))
		local p = v(n.X * 2.8, 4.4 + n.Y * 2.4, 0.6 + n.Z * 3.6)
		b:block(v(0.18, rng:NextNumber(0.6, 1.6), 0.18), CFrame.lookAt(p, p + n) * ang(0, 0, rng:NextNumber(0, 3)), lava, Enum.Material.Neon)
	end
	-- volcano on the back
	local vcf = cf(0, 6.4, 1.2)
	b:cone(2.6, 3.6, vcf, rock, 6, mat)
	local crater = b:cyl(0.4, 1.1, vcf * cf(0, 2.55, 0), lava, Enum.Material.Neon)
	crater.Name = "Crater"
	local att = Instance.new("Attachment")
	att.Parent = crater
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(90, 80, 80))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.Rate = 6
	smoke.Parent = att
	local light = Instance.new("PointLight")
	light.Color = lava
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = crater
	-- tail
	b:limb(v(0, 4.4, 4.1), v(0, 2.8, 4.8), 0.3, rock)
	b:ball(Vector3.one * 0.5, cf(0, 2.7, 4.85), lava, Enum.Material.Neon)
end

-- 🌌 Cosmocorno Brainrot --------------------------------------------------------
builders.Unicorn = function(b: Builder, look: Look)
	local space, mane, glow = look.primary, look.secondary, look.accent
	local hover = 1.2 -- it floats
	b:ball(v(3.2, 2.9, 5.2), cf(0, 3.6 + hover, 0.4), space)
	b:ball(v(1.7, 2.6, 1.9), cf(0, 4.9 + hover, -1.8) * ang(rad(-30), 0, 0), space) -- neck
	b:ball(v(2.0, 2.2, 2.8), cf(0, 6.0 + hover, -2.6) * ang(rad(20), 0, 0), space) -- head
	b:ball(v(1.4, 1.3, 1.6), cf(0, 5.45 + hover, -3.8), space:Lerp(WHITE, 0.15)) -- snout
	b:eye(v(-0.75, 6.3 + hover, -3.2), 0.6, v(-0.4, 0, -1))
	b:eye(v(0.75, 6.3 + hover, -3.2), 0.6, v(0.4, 0, -1))
	-- horn
	local horn = b:cone(2.4, 0.7, cf(0, 7.0 + hover, -3.0) * ang(rad(-30), 0, 0), glow, 6, Enum.Material.Neon)
	for _, p in horn do
		p.Name = "Horn"
	end
	-- ears
	b:wedge(v(0.25, 0.8, 0.5), cf(-0.6, 7.2 + hover, -2.3), space)
	b:wedge(v(0.25, 0.8, 0.5), cf(0.6, 7.2 + hover, -2.3), space)
	-- mane + tail (alternating colours)
	for i = 0, 6 do
		local col = if i % 2 == 0 then mane else glow
		b:ball(Vector3.one * (0.9 - i * 0.04), cf(0, 6.8 + hover - i * 0.55, -2.0 + i * 0.55), col, Enum.Material.Neon)
	end
	for i = 0, 4 do
		local col = if i % 2 == 0 then mane else glow
		b:ball(Vector3.one * (0.9 - i * 0.1), cf(0, 4.2 + hover - i * 0.45, 3.1 + i * 0.4), col, Enum.Material.Neon)
	end
	-- legs with glowing hooves
	for _, s in { -1, 1 } do
		for _, z in { -1.2, 2.0 } do
			b:limb(v(1.0 * s, 3.0 + hover, z), v(1.1 * s, 0.6 + hover, z), 0.6, space)
			b:cyl(0.4, 0.75, cf(1.1 * s, 0.45 + hover, z), glow, Enum.Material.Neon)
		end
	end
	-- stars on the body
	local rng = Random.new(3)
	for _ = 1, 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local e = rng:NextNumber(-0.5, 1)
		local n = v(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e))
		b:ball(Vector3.one * 0.18, cf(n.X * 1.6, 3.6 + hover + n.Y * 1.45, 0.4 + n.Z * 2.6), WHITE, Enum.Material.Neon)
	end
	-- orbiting planets (animated by the client Animator)
	local planets = { { size = 0.9, color = mane }, { size = 0.6, color = glow }, { size = 1.2, color = rgb(255, 190, 80) } }
	for i, pl in planets do
		local p = b:ball(Vector3.one * pl.size, cf(4 + i * 0.6, 4.4 + hover, 0), pl.color, Enum.Material.Neon)
		p.Name = "Planet"
		p:SetAttribute("Orbit", 3.6 + i * 0.9)
		p:SetAttribute("OrbitSpeed", 1.6 - i * 0.35)
		p:SetAttribute("OrbitPhase", i * 2.1)
		p:SetAttribute("OrbitHeight", 4.2 + hover + i * 0.4)
	end
	local ring = b:part(Enum.PartType.Cylinder, v(0.1, 2.2, 2.2), cf(7.6, 5.6 + hover, 0) * ang(0, 0, rad(70)), rgb(255, 220, 160), Enum.Material.Neon)
	ring.Transparency = 0.4
	ring.Name = "PlanetRing"
	ring:SetAttribute("Orbit", 6.3)
	ring:SetAttribute("OrbitSpeed", 0.55)
	ring:SetAttribute("OrbitPhase", 6.3)
	ring:SetAttribute("OrbitHeight", 5.4 + hover)
	-- star dust
	local att = Instance.new("Attachment")
	att.Position = v(0, 4, 0)
	att.Parent = b.root
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Color = ColorSequence.new(glow, mane)
	dust.LightEmission = 1
	dust.Rate = 12
	dust.Lifetime = NumberRange.new(1, 2)
	dust.Speed = NumberRange.new(0.5, 2)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	dust.Parent = att
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = b.root
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
local BrainrotModels = {}
BrainrotModels.Builders = builders

local function override(id: string): Model?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local folder = art and art:FindFirstChild("Brainrots")
	local m = folder and folder:FindFirstChild(id)
	if m and m:IsA("Model") and m.PrimaryPart then
		local clone = m:Clone()
		local _, size = clone:GetBoundingBox()
		clone:SetAttribute("Height", size.Y)
		clone:SetAttribute("Radius", math.max(size.X, size.Z) / 2)
		return clone
	end
	return nil
end

-- Builds a fresh model for a Brainrot id + mutation id. Never errors: unknown builders fall
-- back to a coloured blob so a config typo is visible instead of fatal.
function BrainrotModels.build(id: string, mutationId: string?): Model
	local def = Registry.Brainrot[id]
	local model = override(id)
	if not model then
		local b = ModelKit.new(id)
		local look: Look = if def then def.look else { builder = "?", primary = WHITE, secondary = BLACK, accent = WHITE }
		local fn = builders[look.builder]
		if fn then
			fn(b, look)
		else
			b:ball(Vector3.one * 3, cf(0, 1.5, 0), look.primary)
			b:eye(v(-0.5, 2, -1.3), 0.6)
			b:eye(v(0.5, 2, -1.3), 0.6)
		end
		model = b:finish(look.scale)
	end
	local m = model :: Model
	m:SetAttribute("BrainrotId", id)
	m:SetAttribute("Mutation", mutationId or "Normal")
	ModelKit.applyMutation(m, Registry.Mutation[mutationId or "Normal"])
	return m
end

return BrainrotModels
