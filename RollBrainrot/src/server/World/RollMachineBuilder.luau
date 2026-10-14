--!strict
-- The giant ROLL BRAINROT machine in the middle of the hub.
--
-- Named parts the client animates (RollController):
--   Dome            glass capsule globe       Capsules/*   capsules tumbling inside
--   RarityLight1..7 neon tubes around the dome, flashed in the rolled rarity colour
--   Marquee/*       chasing bulbs around the sign
--   Button          the giant button (ProximityPrompt Action = "Roll")
--   Pedestals/*     reward display pedestals (attribute BrainrotId); client spawns models
-- Attributes on the model: RevealPoint (Vector3) and CameraPoint (Vector3).

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local Registry = require(Modules.Registry)
local BuildKit = require(script.Parent.BuildKit)

local RollMachineBuilder = {}

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local rgb = Color3.fromRGB

local PINK = rgb(255, 92, 170)
local CYAN = rgb(70, 210, 255)
local YELLOW = rgb(255, 210, 50)
local DARK = rgb(44, 38, 78)
local METAL = rgb(190, 195, 210)

function RollMachineBuilder.build(parent: Instance): Model
	local m = BuildKit.model("RollMachine", parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local base = GameConfig.World.Machine
	local function at(x: number, y: number, z: number): Vector3
		return base + v(x, y, z)
	end

	-- Tiered round platform with steps --------------------------------------------
	BuildKit.disc(m, 64, 1.2, at(0, 0.6, 0), rgb(235, 225, 250), Enum.Material.Marble, true)
	BuildKit.disc(m, 56, 1.2, at(0, 1.8, 0), DARK, Enum.Material.SmoothPlastic, true)
	BuildKit.disc(m, 46, 1.2, at(0, 3.0, 0), rgb(235, 225, 250), Enum.Material.Marble, true)
	-- neon inlays on the step edges
	for i, d in { 64.2, 56.2, 46.2 } do
		local ring = BuildKit.disc(
			m,
			d,
			0.25,
			at(0, 1.25 + (i - 1) * 1.2, 0),
			if i % 2 == 1 then PINK else CYAN,
			Enum.Material.Neon
		)
		ring.CastShadow = false
	end

	-- Pedestal column + gear housing ----------------------------------------------
	BuildKit.column(m, 9, 18, at(0, 3.6, 0), DARK, Enum.Material.SmoothPlastic, true)
	BuildKit.column(m, 1.2, 20, at(0, 12.6, 0), YELLOW, Enum.Material.Metal, true)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		BuildKit.block(
			m,
			v(2.2, 1.2, 1.6),
			cf(at(math.sin(a) * 10.4, 13.2, math.cos(a) * 10.4)) * ang(0, a, 0),
			YELLOW,
			Enum.Material.Metal
		)
	end
	-- side gears
	for _, s in { -1, 1 } do
		local gear = BuildKit.part({
			Name = "Gear",
			Shape = Enum.PartType.Cylinder,
			Size = v(1.5, 9, 9),
			CFrame = cf(at(9.6 * s, 8.5, 0)),
			Color = METAL,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = m,
		})
		gear:SetAttribute("Spin", s)
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			BuildKit.block(
				gear,
				v(1.5, 1.6, 1.6),
				cf(at(9.6 * s, 8.5 + math.cos(a) * 4.8, math.sin(a) * 4.8)) * ang(a, 0, 0),
				METAL,
				Enum.Material.Metal
			)
		end
	end

	-- The glass dome full of capsules ---------------------------------------------
	local domeCenter = at(0, 26, 0)
	local dome = BuildKit.part({
		Name = "Dome",
		Shape = Enum.PartType.Ball,
		Size = v(26, 26, 26),
		CFrame = cf(domeCenter),
		Color = rgb(200, 235, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.55,
		Reflectance = 0.2,
		CanCollide = false,
		Parent = m,
	})
	dome.CastShadow = false
	local capsules = BuildKit.folder("Capsules", m)
	local rng = Random.new(5)
	for i = 1, 26 do
		local rarity = Registry.Rarities[((i - 1) % #Registry.Rarities) + 1]
		local p = domeCenter + v(rng:NextNumber(-8, 8), rng:NextNumber(-10, -2), rng:NextNumber(-8, 8))
		local cap = BuildKit.ball(capsules, 3.4, p, rarity.color, Enum.Material.SmoothPlastic)
		cap.Name = "Capsule"
		BuildKit.part({
			Shape = Enum.PartType.Cylinder,
			Size = v(0.4, 3.5, 3.5),
			CFrame = cf(p) * ang(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			Color = rgb(255, 255, 255),
			CanCollide = false,
			Parent = cap,
		})
	end
	-- equator band + crown
	BuildKit.part({
		Name = "Band",
		Shape = Enum.PartType.Cylinder,
		Size = v(2.4, 27.5, 27.5),
		CFrame = cf(domeCenter + v(0, -3, 0)) * ang(0, 0, rad(90)),
		Color = PINK,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = m,
	})
	BuildKit.column(m, 3, 12, domeCenter + v(0, 12, 0), DARK, Enum.Material.SmoothPlastic)
	BuildKit.column(m, 6, 1.2, domeCenter + v(0, 15, 0), METAL, Enum.Material.Metal)
	local star = BuildKit.ball(m, 3.4, domeCenter + v(0, 22, 0), YELLOW, Enum.Material.Neon)
	star.Name = "Topper"
	star:SetAttribute("Spin", 1)
	BuildKit.light(star, YELLOW, 40, 2)

	-- Rarity light tubes around the dome -----------------------------------------
	for i, r in Registry.Rarities do
		local a = (i - 1) / #Registry.Rarities * math.pi * 2
		local p = at(math.sin(a) * 16.5, 14, math.cos(a) * 16.5)
		BuildKit.column(m, 1, 2.4, p, DARK, Enum.Material.Metal)
		local tube = BuildKit.part({
			Name = `RarityLight{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = v(22, 1.4, 1.4),
			CFrame = cf(p + v(0, 12, 0)) * ang(0, 0, rad(90)),
			Color = r.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = m,
		})
		tube.CastShadow = false
		BuildKit.ball(m, 2, p + v(0, 23.4, 0), r.color, Enum.Material.Neon)
	end

	-- Output chute at the front (capsule pops out here) ---------------------------
	BuildKit.block(m, v(10, 7, 6), cf(at(0, 7.5, 10)), DARK, Enum.Material.SmoothPlastic, true)
	BuildKit.block(m, v(7, 4.6, 0.4), cf(at(0, 7.6, 13.05)), rgb(20, 18, 36), Enum.Material.SmoothPlastic)
	BuildKit.block(m, v(10.4, 0.8, 6.4), cf(at(0, 11.3, 10)), PINK, Enum.Material.Neon)
	m:SetAttribute("RevealPoint", at(0, 12, 22))
	m:SetAttribute("CameraPoint", at(0, 17, 54))

	-- Giant ROLL button ------------------------------------------------------------
	local buttonBase = at(0, 3.6, 26)
	BuildKit.column(m, 3.4, 13, buttonBase, YELLOW, Enum.Material.Metal, true)
	BuildKit.column(m, 0.6, 14.2, buttonBase + v(0, 3.4, 0), DARK, Enum.Material.SmoothPlastic, true)
	local button = BuildKit.part({
		Name = "Button",
		Shape = Enum.PartType.Cylinder,
		Size = v(2.2, 10, 10),
		CFrame = cf(buttonBase + v(0, 5, 0)) * ang(0, 0, rad(90)),
		Color = rgb(255, 40, 60),
		Material = Enum.Material.Neon,
		CanCollide = true,
		Parent = m,
	})
	BuildKit.light(button, rgb(255, 60, 80), 18, 1.5)
	local prompt = BuildKit.prompt(button, "ROLL BRAINROT", "Brainrot Machine", "Roll", 22)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	BuildKit.billboard(button, "ROLL BRAINROT", Vector2.new(14, 3), 6, rgb(255, 255, 255), 120)

	-- Marquee sign (visible from the spawn and the roads) --------------------------
	local signCf = cf(at(0, 46, 2)) * ang(0, 0, 0)
	local board = BuildKit.block(m, v(40, 9, 1.6), signCf, DARK, Enum.Material.SmoothPlastic)
	board.Name = "SignBoard"
	-- SurfaceGuis draw on the board's -Z face: rotate the south one to face the spawn
	BuildKit.sign(
		m,
		signCf * cf(0, 0, 0.85) * ang(0, math.pi, 0),
		Vector2.new(38, 8),
		"🎰 ROLL BRAINROT 🎰",
		DARK,
		YELLOW
	)
	BuildKit.sign(m, signCf * cf(0, 0, -0.85), Vector2.new(38, 8), "🎰 ROLL BRAINROT 🎰", DARK, YELLOW)
	local marquee = BuildKit.folder("Marquee", m)
	local idx = 0
	for x = -19, 19, 2.5 do
		for _, y in { -4.6, 4.6 } do
			idx += 1
			local bulb = BuildKit.ball(
				marquee,
				0.9,
				(signCf * cf(x, y, 0)).Position,
				if idx % 2 == 0 then YELLOW else PINK,
				Enum.Material.Neon
			)
			bulb.Name = `Bulb{idx}`
			bulb.CastShadow = false
		end
	end
	BuildKit.column(m, 12, 1.4, at(-14, 34, 2), METAL, Enum.Material.Metal)
	BuildKit.column(m, 12, 1.4, at(14, 34, 2), METAL, Enum.Material.Metal)

	-- Reward pedestals in a ring around the machine --------------------------------
	local pedestals = BuildKit.folder("Pedestals", m)
	local list = Registry.Brainrots
	for i, def in list do
		local a = math.rad(-110 + (i - 1) / math.max(1, #list - 1) * 220) + math.pi
		local p = at(math.sin(a) * 40, 0, math.cos(a) * 40)
		local rarity = Registry.Rarity[def.rarity]
		local ped = BuildKit.column(pedestals, 4, 7, p, rgb(235, 225, 250), Enum.Material.Marble, true)
		ped.Name = `Pedestal{i}`
		ped:SetAttribute("BrainrotId", def.id)
		ped:SetAttribute("Top", p + v(0, 4, 0))
		local ring = BuildKit.disc(pedestals, 7.4, 0.5, p + v(0, 4.1, 0), rarity.color, Enum.Material.Neon)
		ring.CastShadow = false
		BuildKit.disc(pedestals, 9, 0.6, p + v(0, 0.3, 0), DARK, Enum.Material.SmoothPlastic, true)
	end

	-- Big speakers either side
	for _, s in { -1, 1 } do
		local sp = at(22 * s, 3.6, 4)
		BuildKit.block(m, v(6, 12, 6), cf(sp + v(0, 6, 0)), DARK, Enum.Material.SmoothPlastic, true)
		for _, y in { 3.5, 8.5 } do
			BuildKit.part({
				Shape = Enum.PartType.Cylinder,
				Size = v(0.4, 4, 4),
				CFrame = cf(sp + v(0, y, 3.1)) * ang(0, rad(90), 0),
				Color = rgb(30, 30, 36),
				CanCollide = false,
				Parent = m,
			})
		end
		BuildKit.block(m, v(6.2, 0.6, 6.2), cf(sp + v(0, 12.2, 0)), CYAN, Enum.Material.Neon)
	end

	return m
end

return RollMachineBuilder
