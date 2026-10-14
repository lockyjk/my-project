--!strict
-- Reusable scenery: trees, rocks, flowers, benches, lamps, fences, signposts, flags,
-- torches, plus zoo decorations (GameConfig.Decorations builders).
-- All props are anchored part assemblies placed with a ground CFrame (Y = ground level).

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotModels = require(Modules.Models.BrainrotModels)
local ModelKit = require(Modules.Models.ModelKit)
local BuildKit = require(script.Parent.BuildKit)

local Props = {}

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local rgb = Color3.fromRGB
local block = BuildKit.block
local ball = BuildKit.ball
local column = BuildKit.column

local LEAF = { rgb(84, 170, 70), rgb(70, 150, 60), rgb(110, 190, 80), rgb(60, 135, 75) }
local BLOSSOM = { rgb(255, 170, 210), rgb(255, 200, 230), rgb(250, 140, 190) }
local FLOWERS = {
	rgb(255, 90, 120),
	rgb(255, 210, 60),
	rgb(160, 110, 255),
	rgb(255, 255, 255),
	rgb(255, 140, 50),
	rgb(90, 180, 255),
}
local WOOD = rgb(120, 82, 52)
local STONE = rgb(150, 150, 158)

local rng = Random.new(2024)

function Props.setSeed(seed: number)
	rng = Random.new(seed)
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- Trees -------------------------------------------------------------------------
function Props.tree(parent: Instance, ground: CFrame, scale: number?, kind: string?): Model
	local s = scale or rng:NextNumber(0.85, 1.35)
	local m = BuildKit.model("Tree", parent)
	local k = kind or pick({ "Oak", "Oak", "Pine", "Blossom", "Round" })
	local trunkH = (if k == "Pine" then 7 else 10) * s
	local trunk = column(m, trunkH, 2.2 * s, ground.Position, WOOD, Enum.Material.Wood, true)
	trunk.Name = "Trunk"
	local top = ground.Position + v(0, trunkH, 0)
	if k == "Pine" then
		for i = 0, 3 do
			local d = (12 - i * 2.6) * s
			BuildKit.part({
				Shape = Enum.PartType.Cylinder,
				Size = v(4 * s, d, d),
				CFrame = cf(top + v(0, i * 3.2 * s, 0)) * ang(0, 0, rad(90)),
				Color = rgb(50, 120, 70),
				Material = Enum.Material.LeafyGrass,
				CanCollide = false,
				Parent = m,
			})
		end
		ball(m, 2.2 * s, top + v(0, 13 * s, 0), rgb(50, 120, 70), Enum.Material.LeafyGrass)
	else
		local colors = if k == "Blossom" then BLOSSOM else LEAF
		local blobs = if k == "Round" then 1 else 5
		if k == "Round" then
			ball(m, 13 * s, top + v(0, 4 * s, 0), pick(colors), Enum.Material.LeafyGrass)
		else
			for _ = 1, blobs do
				local off = v(rng:NextNumber(-4, 4), rng:NextNumber(1, 6), rng:NextNumber(-4, 4)) * s
				ball(m, rng:NextNumber(7, 10) * s, top + off, pick(colors), Enum.Material.LeafyGrass)
			end
			-- a couple of branches
			for _ = 1, 2 do
				local a = rng:NextNumber(0, math.pi * 2)
				local base = ground.Position + v(0, trunkH * 0.7, 0)
				local tip = base + v(math.cos(a) * 4, 3, math.sin(a) * 4) * s
				BuildKit.part({
					Shape = Enum.PartType.Cylinder,
					Size = v((tip - base).Magnitude, 0.9 * s, 0.9 * s),
					CFrame = CFrame.lookAt((base + tip) / 2, tip) * ang(0, rad(90), 0),
					Color = WOOD,
					Material = Enum.Material.Wood,
					CanCollide = false,
					Parent = m,
				})
			end
		end
	end
	-- roots
	for i = 0, 2 do
		local a = i * 2.1 + rng:NextNumber(0, 1)
		block(
			m,
			v(1, 0.8, 3) * s,
			cf(ground.Position + v(math.cos(a) * 1.4, 0.3, math.sin(a) * 1.4) * s) * ang(0, -a, rad(-12)),
			WOOD,
			Enum.Material.Wood
		)
	end
	return m
end

function Props.palm(parent: Instance, ground: CFrame, scale: number?): Model
	local s = scale or 1
	local m = BuildKit.model("Palm", parent)
	local p = ground.Position
	local lean = rng:NextNumber(-0.25, 0.25)
	for i = 0, 6 do
		ball(
			m,
			(2.4 - i * 0.12) * s,
			p + v(lean * i * i * 0.4, 1 + i * 2.2, 0) * s,
			rgb(140, 100, 60),
			Enum.Material.Wood
		)
	end
	local top = p + v(lean * 36 * 0.4, 15, 0) * s
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		block(
			m,
			v(1.6, 0.3, 9) * s,
			CFrame.lookAt(top, top + v(math.cos(a), 0, math.sin(a))) * cf(0, -1, -4 * s) * ang(rad(-20), 0, 0),
			rgb(70, 170, 70),
			Enum.Material.LeafyGrass
		)
	end
	ball(m, 1.2 * s, top + v(0.8, -1, 0) * s, rgb(120, 80, 40))
	return m
end

-- Rocks / bushes / flowers ------------------------------------------------------
function Props.rock(parent: Instance, ground: CFrame, scale: number?, color: Color3?): Model
	local s = scale or rng:NextNumber(1, 3)
	local m = BuildKit.model("Rock", parent)
	for i = 1, rng:NextInteger(2, 4) do
		local size = v(rng:NextNumber(2, 4), rng:NextNumber(1.5, 3), rng:NextNumber(2, 4)) * s
		local pos = ground.Position + v(rng:NextNumber(-1.5, 1.5) * s, size.Y * 0.35, rng:NextNumber(-1.5, 1.5) * s)
		block(
			m,
			size,
			cf(pos) * ang(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			(color or STONE):Lerp(rgb(110, 110, 120), i * 0.08),
			Enum.Material.Slate,
			i == 1
		)
	end
	return m
end

function Props.bush(parent: Instance, ground: CFrame, scale: number?): Model
	local s = scale or rng:NextNumber(0.8, 1.4)
	local m = BuildKit.model("Bush", parent)
	for _ = 1, 3 do
		ball(
			m,
			rng:NextNumber(3, 4.5) * s,
			ground.Position + v(rng:NextNumber(-1.5, 1.5), 1.4, rng:NextNumber(-1.5, 1.5)) * s,
			pick(LEAF),
			Enum.Material.LeafyGrass
		)
	end
	if rng:NextNumber() < 0.4 then
		for _ = 1, 4 do
			ball(
				m,
				0.6 * s,
				ground.Position + v(rng:NextNumber(-2, 2), rng:NextNumber(1.5, 3), rng:NextNumber(-2, 2)) * s,
				pick(FLOWERS),
				Enum.Material.SmoothPlastic
			)
		end
	end
	return m
end

function Props.flowers(parent: Instance, ground: CFrame, count: number?): Model
	-- each flower is a stem + a bloom (2 parts) so big meadows stay cheap
	local m = BuildKit.model("Flowers", parent)
	local color = pick(FLOWERS)
	for _ = 1, count or 5 do
		local p = ground.Position + v(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		local h = rng:NextNumber(0.8, 1.6)
		BuildKit.part({
			Size = v(0.18, h, 0.18),
			CFrame = cf(p + v(0, h / 2, 0)),
			Color = rgb(70, 150, 60),
			CanCollide = false,
			CastShadow = false,
			Parent = m,
		})
		local bloom = BuildKit.part({
			Size = v(0.9, 0.35, 0.9),
			CFrame = cf(p + v(0, h, 0)) * ang(0, rng:NextNumber(0, 3), 0),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CastShadow = false,
			Parent = m,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = bloom
	end
	return m
end

-- Furniture ---------------------------------------------------------------------
function Props.bench(parent: Instance, ground: CFrame): Model
	local m = BuildKit.model("Bench", parent)
	local base = ground
	for _, x in { -2.6, 2.6 } do
		block(m, v(0.5, 1.6, 2.2), base * cf(x, 0.8, 0), rgb(60, 60, 66), Enum.Material.Metal, true)
	end
	for i = 0, 2 do
		block(m, v(6.4, 0.25, 0.6), base * cf(0, 1.7, -0.7 + i * 0.7), WOOD, Enum.Material.Wood, true)
	end
	for i = 0, 1 do
		block(
			m,
			v(6.4, 0.5, 0.25),
			base * cf(0, 2.5 + i * 0.7, 1.1) * ang(rad(-10), 0, 0),
			WOOD,
			Enum.Material.Wood,
			true
		)
	end
	return m
end

function Props.lamp(parent: Instance, ground: CFrame, color: Color3?): Model
	local m = BuildKit.model("Lamp", parent)
	local p = ground.Position
	column(m, 0.6, 1.6, p, rgb(40, 40, 46), Enum.Material.Metal, true)
	column(m, 11, 0.5, p, rgb(40, 40, 46), Enum.Material.Metal, true)
	block(m, v(2.2, 0.3, 2.2), cf(p + v(0, 11, 0)), rgb(40, 40, 46), Enum.Material.Metal)
	local bulb = ball(m, 1.7, p + v(0, 10.2, 0), color or rgb(255, 230, 170), Enum.Material.Neon)
	BuildKit.light(bulb, color or rgb(255, 220, 160), 26, 1.2, false)
	return m
end

function Props.fence(parent: Instance, a: Vector3, b: Vector3, color: Color3?, height: number?): Model
	local m = BuildKit.model("Fence", parent)
	local h = height or 3.2
	local c = color or rgb(250, 250, 250)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 9))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		block(m, v(0.7, h + 0.4, 0.7), cf(p + v(0, (h + 0.4) / 2, 0)), c, Enum.Material.Wood, true)
		if i == 0 or i == n then
			ball(m, 0.8, p + v(0, h + 0.55, 0), c, Enum.Material.Wood)
		end
	end
	local mid = (a + b) / 2
	local look = CFrame.lookAt(mid, b)
	for _, y in { h * 0.4, h * 0.85 } do
		block(m, v(0.3, 0.45, len), look + v(0, y, 0), c, Enum.Material.Wood, true)
	end
	return m
end

-- Signpost with arrow boards: list of { text, angle (radians, 0 = -Z / north) , color }
function Props.signpost(
	parent: Instance,
	ground: CFrame,
	arrows: { { text: string, angle: number, color: Color3 } }
): Model
	local m = BuildKit.model("Signpost", parent)
	local p = ground.Position
	column(m, 4 + #arrows * 2.6, 0.8, p, WOOD, Enum.Material.Wood, true)
	for i, a in arrows do
		local y = 3 + i * 2.4
		local dir = v(math.sin(a.angle), 0, -math.cos(a.angle))
		local center = p + v(0, y, 0) + dir * 4
		local boardCf = CFrame.lookAt(center, center + dir) * ang(0, rad(90), 0)
		local board, _ = BuildKit.sign(m, boardCf, Vector2.new(7.5, 1.9), a.text, a.color)
		board.Material = Enum.Material.Wood
		-- back side too
		local back = Instance.new("SurfaceGui")
		back.Face = Enum.NormalId.Back
		back.PixelsPerStud = 40
		back.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		back.LightInfluence = 0
		back.Parent = board
		local label = (board:FindFirstChildWhichIsA("SurfaceGui") :: SurfaceGui):FindFirstChild("Label") :: TextLabel
		label:Clone().Parent = back
		-- arrow tip
		BuildKit.part({
			Size = v(0.6, 1.9, 1.6),
			CFrame = CFrame.lookAt(center + dir * 4.5, center + dir * 6) * ang(0, rad(90), 0) * ang(0, 0, 0),
			Color = a.color,
			CanCollide = false,
			Parent = m,
		})
	end
	return m
end

function Props.flag(parent: Instance, ground: CFrame, color: Color3, height: number?): Model
	local m = BuildKit.model("Flag", parent)
	local h = height or 26
	local p = ground.Position
	column(m, h, 0.7, p, rgb(220, 220, 225), Enum.Material.Metal)
	ball(m, 1.4, p + v(0, h + 0.4, 0), rgb(255, 210, 60), Enum.Material.Foil)
	local cloth = block(m, v(0.2, 5, 8), ground * cf(0, h - 3, -4) * ang(0, rad(90), 0), color, Enum.Material.Fabric)
	cloth.Name = "Cloth"
	cloth:SetAttribute("Wave", true)
	return m
end

function Props.torch(parent: Instance, ground: CFrame, height: number?, color: Color3?): Model
	local m = BuildKit.model("Torch", parent)
	local h = height or 10
	local p = ground.Position
	column(m, h, 1.2, p, rgb(70, 60, 55), Enum.Material.Slate, true)
	column(m, 1.6, 2.6, p + v(0, h, 0), rgb(60, 50, 45), Enum.Material.Metal)
	local fireBase = ball(m, 1.8, p + v(0, h + 1.8, 0), color or rgb(255, 140, 40), Enum.Material.Neon)
	fireBase.Transparency = 0.2
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Color = color or rgb(255, 140, 40)
	fire.SecondaryColor = rgb(255, 230, 120)
	fire.Parent = fireBase
	BuildKit.light(fireBase, color or rgb(255, 160, 70), 30, 1.6, false)
	return m
end

-------------------------------------------------------------------------------
-- Zoo decorations (GameConfig.Decorations[].builder)
-------------------------------------------------------------------------------
local Decor: { [string]: (Instance, CFrame) -> Model } = {}

Decor.FlowerBed = function(parent, ground)
	local m = BuildKit.model("FlowerBed", parent)
	block(m, v(10, 1, 5), ground * cf(0, 0.5, 0), rgb(130, 90, 60), Enum.Material.Brick, true)
	block(m, v(9.2, 0.4, 4.2), ground * cf(0, 1.05, 0), rgb(90, 60, 40), Enum.Material.Ground)
	for i = -2, 2 do
		Props.flowers(m, ground * cf(i * 1.8, 1.2, 0), 3)
	end
	return m
end

Decor.LampPair = function(parent, ground)
	local m = BuildKit.model("LampPair", parent)
	Props.lamp(m, ground * cf(-4, 0, 0), rgb(255, 200, 120))
	Props.lamp(m, ground * cf(4, 0, 0), rgb(255, 200, 120))
	return m
end

Decor.Fountain = function(parent, ground)
	local m = BuildKit.model("Fountain", parent)
	local p = ground.Position
	BuildKit.disc(m, 14, 1.6, p + v(0, 0.8, 0), rgb(200, 200, 210), Enum.Material.Marble, true)
	local water = BuildKit.disc(m, 12.4, 0.3, p + v(0, 1.5, 0), rgb(80, 170, 255), Enum.Material.Glass)
	water.Transparency = 0.25
	column(m, 4, 1.6, p + v(0, 1.6, 0), rgb(220, 220, 230), Enum.Material.Marble)
	BuildKit.disc(m, 5, 0.6, p + v(0, 5.6, 0), rgb(220, 220, 230), Enum.Material.Marble)
	local spout = ball(m, 1.2, p + v(0, 6.6, 0), rgb(120, 200, 255), Enum.Material.Glass)
	spout.Transparency = 0.3
	local att = Instance.new("Attachment")
	att.Parent = spout
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(rgb(170, 220, 255))
	pe.Size = NumberSequence.new(0.5, 0.1)
	pe.Lifetime = NumberRange.new(0.8, 1.1)
	pe.Speed = NumberRange.new(10, 12)
	pe.SpreadAngle = Vector2.new(20, 20)
	pe.Acceleration = v(0, -30, 0)
	pe.Rate = 40
	pe.Parent = att
	return m
end

Decor.BalloonArch = function(parent, ground)
	local m = BuildKit.model("BalloonArch", parent)
	local colors = { rgb(255, 80, 120), rgb(255, 210, 60), rgb(90, 180, 255), rgb(140, 220, 90), rgb(190, 110, 255) }
	for i = 0, 16 do
		local a = i / 16 * math.pi
		local p = ground * cf(math.cos(a) * 7, math.sin(a) * 9 + 1, 0)
		ball(m, 2.2, p.Position, colors[i % #colors + 1], Enum.Material.SmoothPlastic).Reflectance = 0.15
	end
	return m
end

Decor.Statue = function(parent, ground)
	local m = BuildKit.model("BrainrotStatue", parent)
	block(m, v(6, 3, 6), ground * cf(0, 1.5, 0), rgb(220, 220, 228), Enum.Material.Marble, true)
	block(m, v(7, 0.5, 7), ground * cf(0, 3.2, 0), rgb(200, 200, 210), Enum.Material.Marble, true)
	local statue = BrainrotModels.build("SharkaleroJetto", "Golden")
	ModelKit.anchorAll(statue)
	for _, d in statue:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Rate = 2
		end
	end
	statue:PivotTo(ground * cf(0, 3.45, 0) * ang(0, math.pi, 0))
	ModelKit.scale(statue, 1.2)
	statue.Parent = m
	return m
end

Decor.Trophy = function(parent, ground)
	local m = BuildKit.model("GoldTrophy", parent)
	local gold = rgb(255, 200, 40)
	block(m, v(4, 2, 4), ground * cf(0, 1, 0), rgb(40, 35, 60), Enum.Material.Marble, true)
	column(m, 2, 1, (ground * cf(0, 2, 0)).Position, gold, Enum.Material.Foil)
	BuildKit.disc(m, 3, 0.4, (ground * cf(0, 4.2, 0)).Position, gold, Enum.Material.Foil)
	ball(m, 4.2, (ground * cf(0, 6.4, 0)).Position, gold, Enum.Material.Foil)
	for _, s in { -1, 1 } do
		BuildKit.part({
			Shape = Enum.PartType.Cylinder,
			Size = v(0.5, 2.6, 2.6),
			CFrame = ground * cf(2.2 * s, 6.6, 0),
			Color = gold,
			Material = Enum.Material.Foil,
			CanCollide = false,
			Parent = m,
		})
	end
	BuildKit.light(m:FindFirstChildWhichIsA("BasePart") :: BasePart, gold, 14, 1)
	return m
end

Decor.VipCarpet = function(parent, ground)
	local m = BuildKit.model("VipCarpet", parent)
	block(m, v(8, 0.2, 26), ground * cf(0, 0.1, 0), rgb(200, 20, 40), Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		for i = 0, 2 do
			local p = ground * cf(5 * s, 0, -10 + i * 10)
			column(m, 3.4, 0.8, p.Position, rgb(255, 200, 40), Enum.Material.Foil, true)
			ball(m, 1.1, p.Position + v(0, 3.7, 0), rgb(255, 200, 40), Enum.Material.Foil)
		end
	end
	return m
end

Props.Decorations = Decor

function Props.decoration(builder: string, parent: Instance, ground: CFrame): Model?
	local fn = Decor[builder]
	if not fn then
		warn(`[Props] unknown decoration builder {builder}`)
		return nil
	end
	return fn(parent, ground)
end

-- Scatter `count` props of a kind inside an annulus/box while avoiding `blocked(pos)`
function Props.scatter(
	parent: Instance,
	count: number,
	sample: () -> Vector3,
	blocked: (Vector3) -> boolean,
	place: (Instance, CFrame) -> ()
)
	local placed, tries = 0, 0
	while placed < count and tries < count * 12 do
		tries += 1
		local p = sample()
		if not blocked(p) then
			place(parent, cf(p) * ang(0, rng:NextNumber(0, math.pi * 2), 0))
			placed += 1
		end
	end
end

function Props.random(): Random
	return rng
end

return Props
