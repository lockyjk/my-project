--!strict
-- Personal zoo plots. All plots are built once at server start; ZooService then
-- personalises the one a player is assigned (owner sign, unlocked habitats, decorations).
--
-- Layout per plot (plot-local, -Z = towards the hub road):
--   entrance arch + owner sign at the front, a collector pad, a decoration strip,
--   six themed habitat pens (2 rows × 3) and a long Giant pen along the back.
-- Creatures are NOT built here: clients render them from ReplicatedStorage.ZooState.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local BuildKit = require(script.Parent.BuildKit)
local Props = require(script.Parent.Props)

local ZooPlotBuilder = {}

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rgb = Color3.fromRGB

local W = GameConfig.World
local FLOOR_Y = 0.4

ZooPlotBuilder.FloorY = FLOOR_Y

-- Decoration spots (plot-local ground positions), indexed by GameConfig.Decorations order.
-- Spot 7 runs along the entrance path (the VIP red carpet).
ZooPlotBuilder.DecorSpots = {
	v(-20, 0, -77),
	v(20, 0, -77),
	v(-46, 0, -77),
	v(46, 0, -77),
	v(-72, 0, -77),
	v(72, 0, -77),
	v(0, 0, -74),
}

function ZooPlotBuilder.plotCFrame(index: number): CFrame
	local plot = W.Plots[index]
	return CFrame.lookAt(plot.origin, plot.origin + plot.facing)
end

function ZooPlotBuilder.habitatCFrame(index: number, habitatIndex: number): CFrame
	return ZooPlotBuilder.plotCFrame(index) * cf(W.HabitatOffsets[habitatIndex])
end

-- Theme props inside a pen -----------------------------------------------------
local function themeProps(parent: Instance, id: string, center: CFrame, size: Vector2, rng: Random)
	local function spot(margin: number): CFrame
		return center
			* cf(
				rng:NextNumber(-size.X / 2 + margin, size.X / 2 - margin),
				FLOOR_Y,
				rng:NextNumber(-size.Y / 2 + margin, size.Y / 2 - margin)
			)
	end
	if id == "Grass" then
		for _ = 1, 4 do
			Props.flowers(parent, spot(4), 4)
		end
		Props.bush(parent, spot(6), 0.9)
		Props.bush(parent, spot(6), 0.8)
	elseif id == "Forest" then
		for _ = 1, 3 do
			Props.tree(parent, spot(7), 0.6, "Pine")
		end
		Props.tree(parent, spot(8), 0.65, "Oak")
		Props.rock(parent, spot(5), 0.8)
	elseif id == "Desert" then
		for _ = 1, 3 do
			local c = spot(6)
			local m = BuildKit.model("DesertCactus", parent)
			BuildKit.column(m, 7, 2, c.Position, rgb(70, 160, 70), Enum.Material.Grass)
			BuildKit.ball(m, 2, c.Position + v(0, 7, 0), rgb(70, 160, 70), Enum.Material.Grass)
			BuildKit.block(m, v(2.4, 1, 1), c * cf(1.6, 4, 0), rgb(70, 160, 70), Enum.Material.Grass)
			BuildKit.column(m, 2.4, 1, (c * cf(2.4, 4, 0)).Position, rgb(70, 160, 70), Enum.Material.Grass)
		end
		Props.rock(parent, spot(5), 1.4, rgb(200, 160, 110))
		Props.rock(parent, spot(5), 1, rgb(210, 170, 120))
	elseif id == "Ice" then
		for _ = 1, 5 do
			local c = spot(4)
			local h = rng:NextNumber(4, 9)
			local spike = BuildKit.block(
				parent,
				v(2, h, 2),
				c * cf(0, h / 2, 0) * ang(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2)),
				rgb(190, 235, 255),
				Enum.Material.Ice
			)
			spike.Transparency = 0.2
		end
		for _ = 1, 3 do
			BuildKit.ball(parent, rng:NextNumber(4, 7), spot(5).Position, rgb(245, 250, 255), Enum.Material.Snow)
		end
	elseif id == "Volcano" then
		local c = center * cf(size.X * 0.22, FLOOR_Y, size.Y * 0.2)
		for i = 0, 4 do
			BuildKit.column(
				parent,
				2.4,
				18 - i * 3.2,
				c.Position + v(0, i * 2.4, 0),
				rgb(70, 55, 55),
				Enum.Material.Basalt
			)
		end
		local lava = BuildKit.disc(parent, 5, 0.4, c.Position + v(0, 12.1, 0), rgb(255, 110, 20), Enum.Material.Neon)
		BuildKit.light(lava, rgb(255, 120, 40), 30, 2)
		local smoke = Instance.new("Smoke")
		smoke.Color = rgb(80, 70, 70)
		smoke.Size = 4
		smoke.RiseVelocity = 6
		smoke.Parent = lava
		for _ = 1, 4 do
			local s = spot(4)
			BuildKit.block(
				parent,
				v(rng:NextNumber(4, 8), 0.2, 1.2),
				s * cf(0, 0.12, 0),
				rgb(255, 100, 20),
				Enum.Material.Neon
			)
		end
	elseif id == "Alien" then
		for _ = 1, 6 do
			local c = spot(4)
			local h = rng:NextNumber(3, 8)
			local crystal = BuildKit.block(
				parent,
				v(1.6, h, 1.6),
				c * cf(0, h / 2, 0) * ang(rng:NextNumber(-0.3, 0.3), 0.7, rng:NextNumber(-0.3, 0.3)),
				if rng:NextNumber() < 0.5 then rgb(80, 255, 200) else rgb(200, 90, 255),
				Enum.Material.Neon
			)
			crystal.Transparency = 0.15
		end
		local ufo = center * cf(-size.X * 0.25, FLOOR_Y + 12, size.Y * 0.2)
		BuildKit.disc(parent, 10, 1.2, ufo.Position, rgb(180, 190, 210), Enum.Material.Metal)
		local glass = BuildKit.ball(parent, 5, ufo.Position + v(0, 1, 0), rgb(120, 255, 200), Enum.Material.Glass)
		glass.Transparency = 0.4
	elseif id == "Giant" then
		for i = -2, 2 do
			Props.palm(parent, center * cf(i * 32 + 8, FLOOR_Y, size.Y * 0.3), 1.1)
		end
		Props.rock(parent, center * cf(-60, FLOOR_Y, 0), 3)
		Props.rock(parent, center * cf(60, FLOOR_Y, 0), 2.6)
	end
end

local function buildHabitat(
	parent: Instance,
	plotIndex: number,
	habitatIndex: number,
	def: GameConfig.HabitatDef,
	rng: Random
)
	local isGiant = def.id == "Giant"
	local size = if isGiant then W.GiantHabitatSize else W.HabitatSize
	local center = ZooPlotBuilder.habitatCFrame(plotIndex, habitatIndex)
	local m = BuildKit.model(def.id, parent)
	m:SetAttribute("HabitatId", def.id)
	-- floor
	BuildKit.block(m, v(size.X, 0.8, size.Y), center * cf(0, 0, 0), def.groundColor, def.ground, true).Name = "Floor"
	-- border curb
	BuildKit.block(
		m,
		v(size.X + 2, 0.6, size.Y + 2),
		center * cf(0, -0.05, 0),
		rgb(230, 225, 215),
		Enum.Material.Concrete,
		true
	)
	-- fence with a gap on the front side
	local hx, hz = size.X / 2, size.Y / 2
	local corners = {
		(center * cf(-hx, FLOOR_Y, -hz)).Position,
		(center * cf(hx, FLOOR_Y, -hz)).Position,
		(center * cf(hx, FLOOR_Y, hz)).Position,
		(center * cf(-hx, FLOOR_Y, hz)).Position,
	}
	local gapL = (center * cf(-5, FLOOR_Y, -hz)).Position
	local gapR = (center * cf(5, FLOOR_Y, -hz)).Position
	Props.fence(m, corners[1], gapL, def.fence)
	Props.fence(m, gapR, corners[2], def.fence)
	Props.fence(m, corners[2], corners[3], def.fence)
	Props.fence(m, corners[3], corners[4], def.fence)
	Props.fence(m, corners[4], corners[1], def.fence)
	-- name plaque at the gate
	local plaqueCf = center * cf(-9, 4.2, -hz - 0.6)
	BuildKit.column(m, 3.6, 0.5, (center * cf(-11.5, FLOOR_Y, -hz - 0.6)).Position, rgb(90, 70, 50), Enum.Material.Wood)
	BuildKit.column(m, 3.6, 0.5, (center * cf(-6.5, FLOOR_Y, -hz - 0.6)).Position, rgb(90, 70, 50), Enum.Material.Wood)
	local _, plaque =
		BuildKit.sign(m, plaqueCf, Vector2.new(6, 1.8), `{def.emoji} {def.name}`, def.fence:Lerp(rgb(40, 30, 60), 0.6))
	plaque.Name = "PlaqueLabel"
	-- theme scenery
	local scenery = BuildKit.folder("Scenery", m)
	themeProps(scenery, def.id, center, size, rng)
	-- lock: a translucent force field + floating price sign (hidden once unlocked)
	local field = BuildKit.part({
		Name = "LockField",
		Size = v(size.X, 14, size.Y),
		CFrame = center * cf(0, 7.4, 0),
		Color = rgb(120, 110, 160),
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CanCollide = true,
		Parent = m,
	})
	field.CastShadow = false
	local lockSign = BuildKit.part({
		Name = "LockSign",
		Size = v(1, 1, 1),
		CFrame = center * cf(0, 16, 0),
		Color = rgb(0, 0, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	local priceText = if def.cost > 0 then `🔒 {def.name}\n${def.cost}` else def.name
	local label = BuildKit.billboard(lockSign, priceText, Vector2.new(16, 5), 0, rgb(255, 230, 120), 220)
	label.Name = "LockLabel"
	local prompt = BuildKit.prompt(field, "Unlock", def.name, "UnlockHabitat", 24)
	prompt:SetAttribute("HabitatId", def.id)
	prompt.Name = "UnlockPrompt"
end

function ZooPlotBuilder.build(parent: Instance, index: number): Model
	local plotCf = ZooPlotBuilder.plotCFrame(index)
	local m = BuildKit.model(`Plot{index}`, parent)
	m:SetAttribute("PlotIndex", index)
	local rng = Random.new(100 + index)
	local size = W.PlotSize
	local hx, hz = size.X / 2, size.Y / 2

	-- base lawn + walkway
	BuildKit.block(m, v(size.X, 1, size.Y), plotCf * cf(0, -0.3, 0), rgb(120, 205, 95), Enum.Material.Grass, true).Name =
		"Lawn"
	local path = rgb(225, 205, 170)
	BuildKit.block(m, v(14, 1, 22), plotCf * cf(0, -0.2, -hz + 11), path, Enum.Material.Cobblestone, true) -- entrance
	BuildKit.block(m, v(size.X - 10, 1, 8), plotCf * cf(0, -0.2, -64), path, Enum.Material.Cobblestone, true) -- promenade
	BuildKit.block(m, v(size.X - 10, 1, 7), plotCf * cf(0, -0.22, -5), path, Enum.Material.Cobblestone, true) -- cross lane
	for _, x in { -30, 30 } do
		BuildKit.block(m, v(7, 1, 118), plotCf * cf(x, -0.24, -1), path, Enum.Material.Cobblestone, true)
	end

	-- hedge border with a front entrance
	local function hedge(a: Vector3, b: Vector3)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local h = BuildKit.block(
			m,
			v(3, 4.5, len),
			CFrame.lookAt(mid + v(0, 2.25, 0), b + v(0, 2.25, 0)),
			rgb(60, 140, 60),
			Enum.Material.LeafyGrass,
			true
		)
		h.Name = "Hedge"
	end
	local function p(x: number, z: number): Vector3
		return (plotCf * cf(x, 0, z)).Position
	end
	hedge(p(-hx, -hz), p(-10, -hz))
	hedge(p(10, -hz), p(hx, -hz))
	hedge(p(hx, -hz), p(hx, hz))
	hedge(p(hx, hz), p(-hx, hz))
	hedge(p(-hx, hz), p(-hx, -hz))
	for _, x in { -hx, hx } do
		for _, z in { -hz, hz } do
			Props.lamp(m, plotCf * cf(x, 0, z), rgb(255, 225, 160))
		end
	end

	-- entrance arch + owner sign
	local archCf = plotCf * cf(0, 0, -hz)
	for _, s in { -1, 1 } do
		BuildKit.column(m, 16, 3, (archCf * cf(9 * s, 0, 0)).Position, rgb(255, 255, 255), Enum.Material.Marble, true)
		BuildKit.ball(m, 4, (archCf * cf(9 * s, 16.5, 0)).Position, rgb(255, 92, 170), Enum.Material.SmoothPlastic)
	end
	BuildKit.block(m, v(22, 2, 3), archCf * cf(0, 15, 0), rgb(255, 92, 170), Enum.Material.SmoothPlastic)
	local signCf = archCf * cf(0, 19.5, 0)
	local signBoard = BuildKit.block(m, v(24, 6, 1), signCf, rgb(44, 40, 78))
	signBoard.Name = "OwnerBoard"
	local _, front = BuildKit.sign(
		m,
		signCf * cf(0, 0, -0.55),
		Vector2.new(23, 5.4),
		"EMPTY ZOO",
		rgb(44, 40, 78),
		rgb(255, 230, 120)
	)
	local _, back = BuildKit.sign(
		m,
		signCf * cf(0, 0, 0.55) * ang(0, math.pi, 0),
		Vector2.new(23, 5.4),
		"EMPTY ZOO",
		rgb(44, 40, 78),
		rgb(255, 230, 120)
	)
	front.Name = "OwnerLabel"
	back.Name = "OwnerLabel"

	-- money collector pad
	local collectorPos = (plotCf * cf(0, 0, -66)).Position
	local pad = BuildKit.disc(m, 10, 0.6, collectorPos + v(0, 0.3, 0), rgb(90, 230, 90), Enum.Material.Neon, false)
	pad.Name = "Collector"
	BuildKit.disc(m, 12, 0.5, collectorPos + v(0, 0.15, 0), rgb(255, 255, 255), Enum.Material.Marble, true)
	local bankAnchor = BuildKit.part({
		Name = "BankAnchor",
		Size = v(1, 1, 1),
		CFrame = cf(collectorPos + v(0, 6, 0)),
		Color = rgb(0, 0, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	BuildKit.billboard(bankAnchor, "$0", Vector2.new(10, 3), 0, rgb(120, 255, 120), 150).Name = "BankLabel"
	local prompt = BuildKit.prompt(pad, "Collect", "Zoo Earnings", "CollectZoo", 14)
	prompt.Name = "CollectPrompt"

	-- habitats
	local habitats = BuildKit.folder("Habitats", m)
	for i, def in GameConfig.Habitats do
		buildHabitat(habitats, index, i, def, rng)
	end
	BuildKit.folder("Decorations", m)
	return m
end

function ZooPlotBuilder.buildAll(parent: Instance): { Model }
	local folder = BuildKit.folder("Zoos", parent)
	local plots = {}
	for i in W.Plots do
		plots[i] = ZooPlotBuilder.build(folder, i)
	end
	return plots
end

return ZooPlotBuilder
