--!strict
-- Placeholder monster and boss models. Builders draw at a natural size; `build()` then
-- scales the model so its height matches MonsterConfig `height` (bosses tower over
-- Brainrots at 50–66 studs). Feet on Y = 0, facing -Z.

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
local BLACK = rgb(18, 16, 22)

type Builder = ModelKit.Builder
type Look = Types.Look

local builders: { [string]: (Builder, Look) -> () } = {}

local function angryEyes(b: Builder, center: Vector3, spacing: number, size: number, glow: Color3?)
	for _, s in { -1, 1 } do
		local p = center + v(spacing * s, 0, 0)
		if glow then
			b:ball(Vector3.one * size, cf(p), glow, Enum.Material.Neon)
		else
			b:eye(p, size)
		end
		b:block(
			v(size * 1.3, size * 0.28, size * 0.3),
			cf(p + v(0, size * 0.55, -size * 0.2)) * ang(0, 0, rad(22 * s)),
			BLACK
		)
	end
end

local function surfaceCracks(b: Builder, center: Vector3, radii: Vector3, n: number, color: Color3, seed: number)
	local rng = Random.new(seed)
	for _ = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local e = rng:NextNumber(-0.7, 0.9)
		local dir = v(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e))
		local p = center + v(dir.X * radii.X, dir.Y * radii.Y, dir.Z * radii.Z)
		local len = rng:NextNumber(0.2, 0.45) * radii.Y
		b:block(
			v(radii.X * 0.05, len, radii.X * 0.05),
			CFrame.lookAt(p, p + dir) * ang(0, 0, rng:NextNumber(0, 3)),
			color,
			Enum.Material.Neon
		)
	end
end

-- Goober / King Goober ------------------------------------------------------------
builders.Slime = function(b: Builder, look: Look)
	local body = b:ball(v(3.8, 3.0, 3.8), cf(0, 1.5, 0), look.primary, Enum.Material.Glass)
	body.Transparency = 0.2
	b:ball(v(4.1, 0.7, 4.1), cf(0, 0.3, 0), look.primary, Enum.Material.Glass).Transparency = 0.3
	b:ball(Vector3.one * 1.3, cf(0.4, 1.3, 0.4), look.secondary, Enum.Material.Neon).Transparency = 0.2
	angryEyes(b, v(0, 2.1, -1.55), 0.6, 0.7)
	b:block(v(1.2, 0.35, 0.2), cf(0, 1.3, -1.8), BLACK)
	for i = -1, 1 do
		b:wedge(v(0.15, 0.3, 0.2), cf(i * 0.35, 1.38, -1.92) * ang(rad(180), 0, 0), WHITE)
	end
	if (look.scale or 1) > 1 then
		-- royal crown for the King
		for k = 0, 5 do
			local a = rad(k * 60)
			b:wedge(
				v(0.3, 0.9, 0.5),
				cf(math.cos(a) * 0.9, 3.25, math.sin(a) * 0.9) * ang(0, -a + rad(90), 0),
				look.accent,
				Enum.Material.Foil
			)
		end
		b:cyl(0.4, 2.1, cf(0, 2.95, 0), look.accent, Enum.Material.Foil)
		b:ball(Vector3.one * 0.35, cf(0, 3.0, -1.05), rgb(255, 50, 80), Enum.Material.Neon)
	end
end

-- Gremlin Imp ------------------------------------------------------------------
builders.Imp = function(b: Builder, look: Look)
	local skin, dark, glow = look.primary, look.secondary, look.accent
	b:ball(v(1.9, 2.1, 1.6), cf(0, 2.3, 0), skin)
	b:ball(Vector3.one * 2.0, cf(0, 4.0, -0.1), skin)
	angryEyes(b, v(0, 4.15, -0.85), 0.45, 0.45, glow)
	b:block(v(0.9, 0.18, 0.2), cf(0, 3.55, -0.95), BLACK)
	for _, s in { -1, 1 } do
		b:cone(0.9, 0.45, cf(0.6 * s, 4.75, 0) * ang(0, 0, rad(-25 * s)), dark, 3)
		b:wedge(v(0.15, 0.6, 0.8), cf(1.05 * s, 4.1, 0.1) * ang(0, rad(90 * s), rad(-50 * s)), skin)
		b:limb(v(0.5 * s, 1.5, 0), v(0.6 * s, 0.25, -0.1), 0.45, skin)
		b:ball(v(0.6, 0.35, 0.8), cf(0.6 * s, 0.17, -0.25), dark)
		b:limb(v(0.9 * s, 2.9, 0), v(1.25 * s, 1.9, -0.6), 0.35, skin)
	end
	-- spiked club
	b:limb(v(1.25, 1.9, -0.6), v(1.4, 3.3, -1.6), 0.3, rgb(110, 70, 40))
	b:ball(Vector3.one * 0.8, cf(1.45, 3.5, -1.75), rgb(110, 70, 40))
	b:limb(v(0, 1.8, 0.7), v(0, 1.0, 1.7), 0.18, skin) -- tail
	b:wedge(v(0.1, 0.4, 0.4), cf(0, 1.0, 1.85), dark)
end

-- Spitter Shroom ----------------------------------------------------------------
builders.Mushroom = function(b: Builder, look: Look)
	local cap, stem, goo = look.primary, look.secondary, look.accent
	b:cyl(2.6, 1.8, cf(0, 1.6, 0), stem)
	b:ball(v(2.2, 0.8, 2.2), cf(0, 0.35, 0), stem)
	b:ball(v(4.4, 2.3, 4.4), cf(0, 3.4, 0), cap)
	b:cyl(0.3, 3.6, cf(0, 2.55, 0), cap:Lerp(BLACK, 0.4))
	for k = 0, 6 do
		local a = rad(k * 51)
		local e = if k == 6 then 1.0 else 0.4
		local n = v(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e))
		local p = v(n.X * 2.1, 3.4 + n.Y * 1.1, n.Z * 2.1)
		b:ball(v(0.75, 0.75, 0.2), CFrame.lookAt(p, p + n), WHITE)
	end
	angryEyes(b, v(0, 2.0, -0.85), 0.42, 0.45)
	-- "O" mouth that spits goo
	local mouth = b:cyl(0.2, 0.6, cf(0, 1.3, -0.92) * ang(rad(90), 0, 0), goo, Enum.Material.Neon)
	mouth.Name = "Muzzle"
end

-- Rock Brute (elite) --------------------------------------------------------------
builders.Brute = function(b: Builder, look: Look)
	local rock, dark, glow = look.primary, look.secondary, look.accent
	local m = Enum.Material.Slate
	b:ball(v(7.4, 7.0, 5.4), cf(0, 7.6, 0), rock, m)
	b:ball(v(5.6, 3.4, 4.4), cf(0, 4.4, 0.2), dark, m)
	b:ball(v(3.4, 3.0, 3.2), cf(0, 11.6, -1.2), rock, m)
	angryEyes(b, v(0, 12.0, -2.75), 0.75, 0.6, glow)
	b:block(v(2.0, 0.8, 1.0), cf(0, 10.6, -2.6), dark, m) -- jaw
	for _, s in { -1, 1 } do
		b:cone(1.0, 0.45, cf(0.7 * s, 10.9, -3.0), WHITE, 3) -- tusks
		-- shoulders, arms and giant stone fists
		b:ball(Vector3.one * 3.0, cf(3.6 * s, 9.4, 0), rock, m)
		b:limb(v(3.9 * s, 9.0, 0), v(4.6 * s, 5.6, -0.8), 2.2, rock, m)
		b:limb(v(4.6 * s, 5.6, -0.8), v(4.8 * s, 2.8, -1.4), 2.0, rock, m)
		b:ball(Vector3.one * 3.4, cf(4.9 * s, 2.0, -1.6), dark, m)
		-- legs
		b:limb(v(1.8 * s, 4.0, 0.3), v(2.0 * s, 0.8, 0), 2.4, dark, m)
		b:block(v(2.6, 1.0, 3.2), cf(2.0 * s, 0.5, -0.4), rock, m)
	end
	surfaceCracks(b, v(0, 7.6, 0), v(3.7, 3.5, 2.7), 10, glow, 5)
	-- moss / boulders on the back
	b:ball(Vector3.one * 2.0, cf(-1.2, 10.2, 2.0), dark, m)
	b:ball(Vector3.one * 1.6, cf(1.3, 9.6, 2.3), dark, m)
end

-- Giant humanoid titan (Forest / Sand / Ice) ------------------------------------
builders.Titan = function(b: Builder, look: Look)
	local bark, moss, glow = look.primary, look.secondary, look.accent
	local mat = look.material or Enum.Material.Wood
	local mossMat = if mat == Enum.Material.Wood then Enum.Material.LeafyGrass else Enum.Material.SmoothPlastic
	-- legs
	for _, s in { -1, 1 } do
		b:limb(v(3.2 * s, 16, 0), v(3.6 * s, 8.5, -0.8), 4.4, bark, mat)
		b:ball(Vector3.one * 4.6, cf(3.6 * s, 8.5, -0.8), moss, mossMat)
		b:limb(v(3.6 * s, 8.5, -0.8), v(3.9 * s, 2.0, 0), 4.0, bark, mat)
		b:block(v(5.0, 2.2, 6.4), cf(3.9 * s, 1.1, -1.0), bark, mat)
		for t = -1, 1 do
			b:ball(Vector3.one * 1.6, cf(3.9 * s + t * 1.5, 0.8, -4.0), bark, mat) -- toes/roots
		end
	end
	b:ball(v(9.5, 5.5, 7), cf(0, 17, 0), bark, mat) -- pelvis
	b:ball(v(12.5, 12.5, 9), cf(0, 24, 0), bark, mat) -- torso
	b:ball(v(9, 6, 2), cf(0, 25, -3.9), bark:Lerp(BLACK, 0.2), mat) -- chest plate
	-- glowing core in the chest
	local core = b:ball(Vector3.one * 3.0, cf(0, 25, -4.6), glow, Enum.Material.Neon)
	core.Name = "Core"
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 40
	light.Brightness = 3
	light.Parent = core
	-- arms with huge fists
	for _, s in { -1, 1 } do
		b:ball(Vector3.one * 6.5, cf(7.4 * s, 28.5, 0), moss, mossMat)
		b:limb(v(7.6 * s, 28, 0), v(9.4 * s, 20.5, -1.5), 4.0, bark, mat)
		b:ball(Vector3.one * 4.2, cf(9.4 * s, 20.5, -1.5), bark, mat)
		b:limb(v(9.4 * s, 20.5, -1.5), v(9.8 * s, 13.0, -3.0), 3.7, bark, mat)
		b:ball(Vector3.one * 6.0, cf(9.9 * s, 11.2, -3.4), bark:Lerp(BLACK, 0.15), mat)
		-- branches growing out of the shoulders
		b:limb(v(7.5 * s, 31, 1), v(10 * s, 37, 3), 1.2, bark, mat)
		b:ball(Vector3.one * 4.0, cf(10 * s, 37.5, 3), moss, mossMat)
	end
	-- head
	b:ball(v(6.5, 7, 6.5), cf(0, 33.5, -0.8), bark, mat)
	angryEyes(b, v(0, 34.2, -4.0), 1.5, 1.2, glow)
	local mouth = b:block(v(3.4, 0.6, 0.6), cf(0, 32.0, -4.0), glow, Enum.Material.Neon)
	mouth.Name = "Mouth"
	-- crown of foliage / crystals
	local rng = Random.new(21)
	for _ = 1, 9 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1, 3.5)
		b:ball(
			Vector3.one * rng:NextNumber(2.5, 4.2),
			cf(math.cos(a) * r, 37 + rng:NextNumber(0, 2.5), math.sin(a) * r + 0.5),
			moss,
			mossMat
		)
	end
	for k = 0, 4 do
		local a = rad(-60 + k * 30)
		b:wedge(
			v(0.8, 4.5, 2.0),
			cf(math.sin(a) * 4.5, 26 + k % 2 * 3, 4.6) * ang(rad(-25), a, 0),
			glow,
			Enum.Material.Neon
		)
	end
end

-- Quadruped beast (Volcano Titan, Giant Mutant) ---------------------------------
builders.Beast = function(b: Builder, look: Look)
	local hide, lava, glow = look.primary, look.secondary, look.accent
	local mat = Enum.Material.Basalt
	b:ball(v(14, 11, 22), cf(0, 15, 1), hide, mat)
	b:ball(v(11, 9, 8), cf(0, 17, -9), hide, mat) -- shoulders
	-- head with jaw
	b:ball(v(8.5, 7.5, 9), cf(0, 17, -16), hide, mat)
	b:block(v(7, 2.6, 7), cf(0, 13.4, -17.2) * ang(rad(12), 0, 0), hide:Lerp(BLACK, 0.2), mat)
	for i = -2, 2 do
		b:wedge(v(0.6, 1.4, 0.8), cf(i * 1.3, 14.9, -20.3) * ang(rad(180), 0, 0), WHITE)
	end
	angryEyes(b, v(0, 18.6, -20.2), 2.1, 1.4, glow)
	local maw = b:block(v(5.5, 0.8, 4), cf(0, 14.6, -18.5), lava, Enum.Material.Neon)
	maw.Name = "Mouth"
	for _, s in { -1, 1 } do
		b:cone(6, 2.2, cf(3.2 * s, 20, -15) * ang(rad(-30), 0, rad(-35 * s)), WHITE:Lerp(hide, 0.3), 5) -- horns
		for _, z in { -7, 9 } do
			b:limb(v(5.2 * s, 13, z), v(6.2 * s, 6, z - 1), 4.4, hide, mat)
			b:limb(v(6.2 * s, 6, z - 1), v(6.4 * s, 1.5, z - 0.5), 3.8, hide, mat)
			b:block(v(5, 2.2, 6), cf(6.4 * s, 1.1, z - 1.6), hide:Lerp(BLACK, 0.25), mat)
		end
	end
	-- glowing spikes along the back
	for i = 0, 6 do
		b:cone(
			3.5 - i * 0.25,
			2.4 - i * 0.18,
			cf(0, 20.2 - i * 0.25, -6 + i * 3.4) * ang(rad(-15), 0, 0),
			lava,
			4,
			Enum.Material.Neon
		)
	end
	surfaceCracks(b, v(0, 15, 1), v(7, 5.5, 11), 26, lava, 9)
	-- tail
	for i = 1, 6 do
		local d = 4.2 - i * 0.5
		b:ball(Vector3.one * d, cf(0, 14 - i * 1.2, 11 + i * 2.6), hide, mat)
	end
	b:cone(3, 2, cf(0, 6.6, 27) * ang(rad(-100), 0, 0), lava, 4, Enum.Material.Neon)
end

-- Void Monster (floating eye) ---------------------------------------------------
builders.VoidEye = function(b: Builder, look: Look)
	local shell, glow, iris = look.primary, look.secondary, look.accent
	local cy = 24
	b:ball(Vector3.one * 16, cf(0, cy, 0), shell, Enum.Material.Slate)
	b:ball(Vector3.one * 13.5, cf(0, cy, -1.6), WHITE:Lerp(glow, 0.15))
	local irisPart =
		b:part(Enum.PartType.Cylinder, v(0.6, 8, 8), cf(0, cy, -8.0) * ang(0, rad(90), 0), iris, Enum.Material.Neon)
	irisPart.Name = "Iris"
	b:part(Enum.PartType.Cylinder, v(0.7, 3.6, 3.6), cf(0, cy, -8.15) * ang(0, rad(90), 0), BLACK)
	-- eyelids
	b:ball(v(17, 6, 17), cf(0, cy + 7.2, 0.4), shell, Enum.Material.Slate)
	b:ball(v(17, 5, 17), cf(0, cy - 7.6, 0.4), shell, Enum.Material.Slate)
	-- tentacles reaching to the ground
	for k = 0, 7 do
		local a = rad(k * 45 + 22)
		local dir = v(math.cos(a), 0, math.sin(a))
		local prev = v(0, cy - 6, 0) + dir * 4
		for i = 1, 5 do
			local f = i / 5
			local nextP = v(0, cy - 6 - f * (cy - 7), 0) + dir * (4 + f * 12 + math.sin(f * 3 + k) * 2)
			b:limb(prev, nextP, 2.6 - f * 1.6, if i % 2 == 0 then shell else glow:Lerp(shell, 0.5), Enum.Material.Slate)
			prev = nextP
		end
		b:ball(Vector3.one * 1.4, cf(prev), glow, Enum.Material.Neon)
	end
	-- orbiting void shards
	for i = 1, 6 do
		local p = b:wedge(v(1.2, 3.5, 2), cf(12, cy, 0), glow, Enum.Material.Neon)
		p.Name = "Shard"
		p:SetAttribute("Orbit", 12 + (i % 2) * 3)
		p:SetAttribute("OrbitSpeed", 0.6 + i * 0.07)
		p:SetAttribute("OrbitPhase", i * 1.05)
		p:SetAttribute("OrbitHeight", cy + math.sin(i) * 6)
	end
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 50
	light.Brightness = 2
	light.Parent = irisPart
end

-- Ancient Dragon ----------------------------------------------------------------
builders.Dragon = function(b: Builder, look: Look)
	local scales, belly, glow = look.primary, look.secondary, look.accent
	local mat = Enum.Material.Slate
	b:ball(v(11, 10, 21), cf(0, 14, 2), scales, mat)
	b:ball(v(8, 7, 17), cf(0, 12, 1.5), belly, mat)
	-- neck and head
	local neck = { v(0, 17, -7), v(0, 21, -11), v(0, 25, -13.5), v(0, 27.5, -15) }
	for i = 1, #neck - 1 do
		b:limb(neck[i], neck[i + 1], 5.4 - i * 0.6, scales, mat)
		b:ball(Vector3.one * (5.4 - i * 0.6), cf(neck[i + 1]), scales, mat)
	end
	b:block(v(6, 4.5, 7), cf(0, 28.5, -17), scales, mat)
	b:block(v(4.6, 2.8, 6), cf(0, 27.2, -22.5), scales, mat)
	b:block(v(4.2, 1.2, 5.6), cf(0, 25.6, -21.8) * ang(rad(15), 0, 0), belly, mat)
	angryEyes(b, v(0, 30, -20.2), 1.9, 1.1, glow)
	local maw = b:block(v(3.6, 0.6, 4.2), cf(0, 26.3, -22), glow, Enum.Material.Neon)
	maw.Name = "Mouth"
	for _, s in { -1, 1 } do
		b:cone(7, 1.6, cf(2 * s, 30.5, -15) * ang(rad(55), 0, rad(-15 * s)), belly, 5) -- horns
	end
	-- wings
	for _, s in { -1, 1 } do
		local shoulder = v(4.5 * s, 19, -3)
		local elbow = v(14 * s, 30, 0)
		local tip = v(26 * s, 24, 6)
		b:limb(shoulder, elbow, 1.6, scales, mat)
		b:limb(elbow, tip, 1.2, scales, mat)
		for k = 0, 3 do
			local finger = elbow:Lerp(tip, k / 3)
			local anchor = v(finger.X * 0.4, 15, 4 + k * 2)
			local membrane = b:block(
				v(0.4, (finger - anchor).Magnitude, 5.5),
				CFrame.lookAt((finger + anchor) / 2, finger) * ang(rad(90), 0, 0),
				glow:Lerp(scales, 0.55),
				Enum.Material.SmoothPlastic
			)
			membrane.Transparency = 0.15
		end
	end
	-- legs
	for _, s in { -1, 1 } do
		for _, z in { -5, 9 } do
			b:limb(v(4.5 * s, 12, z), v(5.5 * s, 5, z - 1.5), 3.8, scales, mat)
			b:limb(v(5.5 * s, 5, z - 1.5), v(5.6 * s, 1.2, z - 0.5), 3.2, scales, mat)
			for t = -1, 1 do
				b:cone(1.6, 0.8, cf(5.6 * s + t * 1.1, 0.4, z - 2.8) * ang(rad(-80), 0, 0), WHITE, 3)
			end
		end
	end
	-- spines and tail
	for i = 0, 7 do
		b:wedge(v(0.6, 2.6 - i * 0.15, 2.4), cf(0, 19 - i * 0.3, -6 + i * 2.6), glow, Enum.Material.Neon)
	end
	for i = 1, 8 do
		local d = 5 - i * 0.5
		b:ball(Vector3.one * d, cf(math.sin(i * 0.6) * 2, 13 - i * 1.1, 12 + i * 2.6), scales, mat)
	end
	b:wedge(v(0.6, 4, 5), cf(math.sin(9 * 0.6) * 2, 3.6, 34.5), glow, Enum.Material.Neon)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
local MonsterModels = {}
MonsterModels.Builders = builders

function MonsterModels.build(id: string): Model
	local def = Registry.Monster[id]
	local model: Model
	local art = ReplicatedStorage:FindFirstChild("Art")
	local folder = art and art:FindFirstChild("Monsters")
	local custom = folder and folder:FindFirstChild(id)
	if custom and custom:IsA("Model") and custom.PrimaryPart then
		model = custom:Clone()
		local _, size = model:GetBoundingBox()
		model:SetAttribute("Height", size.Y)
		model:SetAttribute("Radius", math.max(size.X, size.Z) / 2)
	else
		local b = ModelKit.new(id)
		local look: Look = if def
			then def.look
			else { builder = "Slime", primary = WHITE, secondary = BLACK, accent = WHITE }
		local fn = builders[look.builder] or builders.Slime
		fn(b, look)
		model = b:finish()
	end
	-- scale so the model is exactly as tall as the config says
	if def then
		local h = (model:GetAttribute("Height") :: number?) or def.height
		if h > 0 and math.abs(h - def.height) > 0.05 then
			ModelKit.scale(model, def.height / h)
		end
	end
	model:SetAttribute("MonsterId", id)
	return model
end

return MonsterModels
