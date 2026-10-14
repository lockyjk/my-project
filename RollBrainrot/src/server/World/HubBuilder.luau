--!strict
-- The Brainrot Zoo hub: terrain, roads, central plaza, spawn arch, the four stands
-- (Shop, Upgrades, Daily Rewards, Events), signposts, a pond, forests, hills and flowers.
-- Spacious on purpose: big lawns between landmarks, with the stadium visible to the north.

local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local BuildKit = require(script.Parent.BuildKit)
local Props = require(script.Parent.Props)

local HubBuilder = {}

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local rgb = Color3.fromRGB

local W = GameConfig.World
local PATH = rgb(232, 214, 178)
local PATH_EDGE = rgb(200, 180, 145)
local PINK = rgb(255, 92, 170)
local CYAN = rgb(70, 210, 255)
local YELLOW = rgb(255, 210, 50)
local PURPLE = rgb(150, 100, 255)
local DARK = rgb(44, 40, 78)

-------------------------------------------------------------------------------
-- Terrain
-------------------------------------------------------------------------------
local function terrain()
	local t = Workspace.Terrain
	t:SetMaterialColor(Enum.Material.Grass, rgb(106, 178, 74))
	t:SetMaterialColor(Enum.Material.LeafyGrass, rgb(84, 156, 64))
	t:SetMaterialColor(Enum.Material.Sand, rgb(232, 210, 150))
	t.WaterColor = rgb(60, 160, 210)
	t.WaterTransparency = 0.6
	t.WaterWaveSize = 0.08
	t.Decoration = true -- animated grass blades
	-- one huge flat lawn covering hub + stadium
	t:FillBlock(cf(0, -12, -800), v(2000, 24, 3200), Enum.Material.Grass)
	-- rolling hills enclosing the hub (not in front of the stadium)
	local rng = Random.new(9)
	local function hill(x: number, z: number, r: number)
		t:FillBall(v(x, -r * 0.55, z), r, if rng:NextNumber() < 0.4 then Enum.Material.LeafyGrass else Enum.Material.Grass)
	end
	for x = -760, 760, 90 do
		hill(x + rng:NextNumber(-20, 20), 700 + rng:NextNumber(-30, 30), rng:NextNumber(90, 150))
	end
	for z = -520, 660, 90 do
		hill(-760 + rng:NextNumber(-30, 30), z, rng:NextNumber(90, 150))
		hill(760 + rng:NextNumber(-30, 30), z, rng:NextNumber(90, 150))
	end
	-- mountains framing the stadium far away
	for x = -980, 980, 140 do
		t:FillBall(v(x, -60, -2250 + rng:NextNumber(-60, 60)), rng:NextNumber(260, 380), Enum.Material.Rock)
	end
	for z = -2100, -700, 160 do
		t:FillBall(v(-1000 + rng:NextNumber(-40, 40), -60, z), rng:NextNumber(220, 320), Enum.Material.Rock)
		t:FillBall(v(1000 + rng:NextNumber(-40, 40), -60, z), rng:NextNumber(220, 320), Enum.Material.Rock)
	end
	-- pond (sand rim, water inside)
	local pond = v(185, 0, -330)
	t:FillCylinder(cf(pond + v(0, -2, 0)), 4, 52, Enum.Material.Sand)
	t:FillCylinder(cf(pond + v(0, -3.5, 0)), 7, 44, Enum.Material.Water)
end

-------------------------------------------------------------------------------
-- Roads (thin cobblestone strips laid on the lawn)
-------------------------------------------------------------------------------
local function road(parent: Instance, a: Vector3, b: Vector3, width: number)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local look = CFrame.lookAt(v(mid.X, 0, mid.Z), v(b.X, 0, b.Z))
	BuildKit.block(parent, v(width + 3, 0.5, len + 3), look * cf(0, 0.05, 0), PATH_EDGE, Enum.Material.Cobblestone, true)
	BuildKit.block(parent, v(width, 0.5, len), look * cf(0, 0.12, 0), PATH, Enum.Material.Cobblestone, true)
end

local function roads(parent: Instance)
	local f = BuildKit.folder("Roads", parent)
	local plazaR = W.Plaza.radius
	-- plaza
	BuildKit.disc(f, plazaR * 2 + 6, 0.5, v(0, 0.05, 0), PATH_EDGE, Enum.Material.Cobblestone, true)
	BuildKit.disc(f, plazaR * 2, 0.5, v(0, 0.12, 0), PATH, Enum.Material.Cobblestone, true)
	-- decorative rings in the plaza floor
	for i, r in { 70, 58 } do
		local ring = BuildKit.disc(f, r * 2, 0.5, v(0, 0.14 + i * 0.01, 0), if i == 1 then rgb(255, 180, 210) else rgb(170, 230, 255), Enum.Material.Marble, true)
		ring.Name = "PlazaRing"
		BuildKit.disc(f, r * 2 - 4, 0.5, v(0, 0.15 + i * 0.01, 0), PATH, Enum.Material.Cobblestone, true)
	end
	-- north road to the stadium gate
	road(f, v(0, 0, -plazaR + 4), v(0, 0, W.ArenaGate.Z + 4), 30)
	-- south road to the spawn and the invasion meadow
	road(f, v(0, 0, plazaR - 4), v(0, 0, 250), 24)
	-- east/west avenues and the zoo row roads
	for _, s in { -1, 1 } do
		road(f, v(s * (plazaR - 4), 0, 0), v(s * 232, 0, 0), 22)
		road(f, v(s * 232, 0, -290), v(s * 232, 0, 350), 22)
		for _, plot in W.Plots do
			if math.sign(plot.origin.X) == s then
				road(f, v(s * 232, 0, plot.origin.Z), v(s * 246, 0, plot.origin.Z), 14)
			end
		end
	end
	-- diagonal paths to the four stands
	for _, pos in W.Stands do
		local dir = v(pos.X, 0, pos.Z).Unit
		road(f, dir * (plazaR - 4), v(pos.X, 0, pos.Z) - dir * 8, 12)
	end
	-- path round the pond
	road(f, v(0, 0, -330), v(120, 0, -330), 10)
end

-------------------------------------------------------------------------------
-- Spawn + welcome arch
-------------------------------------------------------------------------------
local function spawnArea(parent: Instance)
	local f = BuildKit.folder("Spawn", parent)
	local p = W.Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = v(16, 1, 16)
	spawn.CFrame = cf(p.X, 0.6, p.Z)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = rgb(255, 150, 210)
	spawn.Transparency = 0.2
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = f
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	BuildKit.disc(f, 26, 0.6, v(p.X, 0.35, p.Z), rgb(255, 255, 255), Enum.Material.Marble, true)
	-- big welcome arch facing the spawn (players look north through it at the machine + stadium)
	local archZ = p.Z - 24
	for _, s in { -1, 1 } do
		BuildKit.column(f, 30, 6, v(s * 18, 0, archZ), rgb(255, 255, 255), Enum.Material.Marble, true)
		BuildKit.ball(f, 8, v(s * 18, 32, archZ), if s < 0 then PINK else CYAN, Enum.Material.SmoothPlastic)
		for i = 0, 5 do
			BuildKit.ball(f, 2.6, v(s * 18, 4 + i * 4.6, archZ - 3.2), if i % 2 == 0 then YELLOW else PINK, Enum.Material.SmoothPlastic)
		end
	end
	BuildKit.block(f, v(44, 5, 4), cf(0, 28, archZ), DARK)
	BuildKit.sign(f, cf(0, 28, archZ + 2.1) * ang(0, math.pi, 0), Vector2.new(42, 4.6), "WELCOME TO THE BRAINROT ZOO", DARK, YELLOW)
	BuildKit.sign(f, cf(0, 28, archZ - 2.1), Vector2.new(42, 4.6), "HAVE FUN!", DARK, YELLOW)
	-- welcome flower beds
	for _, s in { -1, 1 } do
		Props.decoration("FlowerBed", f, cf(s * 26, 0, p.Z) * ang(0, rad(90), 0))
	end
end

-------------------------------------------------------------------------------
-- Stands (Shop / Upgrades / Daily / Events): striped awning booths with a prompt
-------------------------------------------------------------------------------
local function stand(parent: Instance, name: string, pos: Vector3, color: Color3, title: string, action: string, prompt: string)
	local m = BuildKit.model(name, parent)
	local face = CFrame.lookAt(v(pos.X, 0, pos.Z), v(0, 0, 0)) -- counter faces the plaza
	BuildKit.block(m, v(26, 1, 18), face * cf(0, 0.5, 2), rgb(240, 235, 225), Enum.Material.WoodPlanks, true)
	-- counter
	local counter = BuildKit.block(m, v(20, 4, 3), face * cf(0, 3, -4), color, Enum.Material.SmoothPlastic, true)
	BuildKit.block(m, v(21, 0.6, 3.6), face * cf(0, 5.3, -4), rgb(255, 255, 255), Enum.Material.Marble, true)
	-- back wall + posts
	BuildKit.block(m, v(22, 14, 1.4), face * cf(0, 8, 8), color:Lerp(rgb(255, 255, 255), 0.35), Enum.Material.SmoothPlastic, true)
	for _, x in { -10.5, 10.5 } do
		BuildKit.column(m, 14, 1.2, (face * cf(x, 1, -5.5)).Position, rgb(255, 255, 255), Enum.Material.Wood, true)
	end
	-- striped awning
	for i = 0, 7 do
		local stripe = if i % 2 == 0 then color else rgb(255, 255, 255)
		BuildKit.block(m, v(2.8, 0.5, 16), face * cf(-9.8 + i * 2.8, 15.5, 1) * ang(rad(12), 0, 0), stripe, Enum.Material.Fabric)
	end
	for i = 0, 7 do
		BuildKit.ball(m, 2.8, (face * cf(-9.8 + i * 2.8, 13.8, -7)).Position, if i % 2 == 0 then color else rgb(255, 255, 255), Enum.Material.Fabric)
	end
	-- title sign on the roof (both sides)
	local signCf = face * cf(0, 21, 1)
	BuildKit.block(m, v(20, 5, 1), signCf, DARK)
	BuildKit.sign(m, signCf * cf(0, 0, -0.55), Vector2.new(19, 4.4), title, DARK, rgb(255, 255, 255))
	BuildKit.sign(m, signCf * cf(0, 0, 0.55) * ang(0, math.pi, 0), Vector2.new(19, 4.4), title, DARK, rgb(255, 255, 255))
	BuildKit.prompt(counter, prompt, title, action, 16)
	-- a couple of crates and a lamp
	BuildKit.block(m, v(3, 3, 3), face * cf(11, 2.5, 5) * ang(0, 0.3, 0), rgb(170, 120, 70), Enum.Material.WoodPlanks, true)
	BuildKit.block(m, v(2.4, 2.4, 2.4), face * cf(11.5, 5.2, 5) * ang(0, 0.8, 0), rgb(170, 120, 70), Enum.Material.WoodPlanks, true)
	Props.lamp(m, face * cf(-14, 0, -6), color)
	return m
end

local function stands(parent: Instance)
	local f = BuildKit.folder("Stands", parent)
	local S = W.Stands
	stand(f, "Shop", S.Shop, rgb(255, 170, 40), "🛒 SHOP", "OpenShop", "Open Shop")
	stand(f, "Upgrades", S.Upgrades, rgb(90, 200, 90), "⬆️ UPGRADES", "OpenUpgrades", "Upgrades")
	stand(f, "Daily", S.Daily, rgb(70, 160, 255), "📅 DAILY REWARDS", "OpenDaily", "Daily Rewards")
	local events = stand(f, "Events", S.Events, PURPLE, "🌩️ EVENTS", "OpenEvents", "World Events")
	-- live event board (text updated by EventService)
	local boardCf = CFrame.lookAt(v(S.Events.X, 0, S.Events.Z), v(0, 0, 0)) * cf(0, 9.5, 7.2)
	local board, label = BuildKit.sign(events, boardCf * ang(0, 0, 0), Vector2.new(18, 7), "Next event soon…", rgb(20, 18, 40), rgb(255, 230, 120))
	board.Name = "EventBoard"
	label.Name = "EventBoardLabel"
end

-------------------------------------------------------------------------------
-- Signposts pointing at every landmark
-------------------------------------------------------------------------------
local function angleTo(from: Vector3, to: Vector3): number
	local d = to - from
	return math.atan2(d.X, -d.Z)
end

local function signposts(parent: Instance)
	local f = BuildKit.folder("Signposts", parent)
	local function post(at: Vector3)
		Props.signpost(f, cf(at), {
			{ text = "🎰 ROLL BRAINROTS", angle = angleTo(at, W.Machine), color = PINK },
			{ text = "🏡 YOUR ZOO", angle = angleTo(at, v(if at.X >= 0 then 330 else -330, 0, at.Z)), color = rgb(90, 200, 90) },
			{ text = "🏟️ MONSTER ARENA", angle = angleTo(at, W.Arena.center), color = rgb(230, 60, 60) },
			{ text = "🛒 SHOP", angle = angleTo(at, W.Stands.Shop), color = rgb(255, 170, 40) },
			{ text = "⬆️ UPGRADES", angle = angleTo(at, W.Stands.Upgrades), color = rgb(90, 180, 90) },
			{ text = "📅 DAILY REWARDS", angle = angleTo(at, W.Stands.Daily), color = rgb(70, 160, 255) },
			{ text = "🌩️ EVENTS", angle = angleTo(at, W.Stands.Events), color = PURPLE },
		})
	end
	post(v(16, 0, 120))
	post(v(-90, 0, -14))
	post(v(90, 0, -14))
	post(v(20, 0, -120))
end

-------------------------------------------------------------------------------
-- Plaza ring decorations: lamps, benches, flower beds, balloons
-------------------------------------------------------------------------------
local function plazaDecor(parent: Instance)
	local f = BuildKit.folder("PlazaDecor", parent)
	local R = W.Plaza.radius
	BuildKit.around(v(0, 0, 0), R - 3, 16, function(ring, i, a)
		-- leave the four road openings clear
		local deg = math.deg(a) % 90
		if deg < 14 or deg > 76 then
			return
		end
		local ground = cf(ring.Position) * ang(0, a + math.pi, 0)
		if i % 2 == 0 then
			Props.lamp(f, ground, if i % 4 == 0 then PINK else CYAN)
		else
			Props.bench(f, ground)
		end
	end)
	BuildKit.around(v(0, 0, 0), R + 10, 8, function(ring, _, a)
		local deg = math.deg(a) % 90
		if deg < 20 or deg > 70 then
			return
		end
		Props.decoration("FlowerBed", f, cf(ring.Position) * ang(0, a + math.pi / 2, 0))
	end, math.pi / 8)
	-- road flags towards the stadium
	for z = -110, W.ArenaGate.Z + 40, -40 do
		Props.flag(f, cf(-22, 0, z), if (z // 40) % 2 == 0 then PINK else CYAN, 24)
		Props.flag(f, cf(22, 0, z), if (z // 40) % 2 == 0 then YELLOW else PURPLE, 24)
	end
	for z = -150, W.ArenaGate.Z + 40, -60 do
		Props.lamp(f, cf(-30, 0, z))
		Props.lamp(f, cf(30, 0, z))
	end
end

-------------------------------------------------------------------------------
-- Pond dock + scattered scenery
-------------------------------------------------------------------------------
local function pondDecor(parent: Instance)
	local f = BuildKit.folder("Pond", parent)
	local pond = v(185, 0, -330)
	-- wooden dock
	for i = 0, 6 do
		BuildKit.block(f, v(8, 0.6, 3), cf(pond + v(-46 + i * 3.2, 0.6, 0)) * ang(0, rad(90), 0), rgb(150, 105, 65), Enum.Material.WoodPlanks, true)
	end
	for _, x in { -46, -28 } do
		for _, z in { -3.5, 3.5 } do
			BuildKit.column(f, 3, 0.8, pond + v(x, -1.5, z), rgb(120, 85, 55), Enum.Material.Wood)
		end
	end
	-- lily pads
	local rng = Random.new(4)
	for _ = 1, 14 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(8, 38)
		local p = pond + v(math.cos(a) * r, 0.05, math.sin(a) * r)
		BuildKit.disc(f, rng:NextNumber(2.5, 4), 0.2, p, rgb(70, 160, 70), Enum.Material.Grass)
		if rng:NextNumber() < 0.35 then
			BuildKit.ball(f, 0.8, p + v(0.4, 0.4, 0), rgb(255, 170, 210))
		end
	end
	-- reeds on the rim
	for _ = 1, 20 do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = pond + v(math.cos(a) * 46, 0, math.sin(a) * 46)
		BuildKit.column(f, rng:NextNumber(3, 5), 0.3, p, rgb(90, 140, 60), Enum.Material.Grass)
	end
	Props.bench(f, cf(pond + v(-30, 0, 30)) * ang(0, rad(220), 0))
	Props.bench(f, cf(pond + v(30, 0, 34)) * ang(0, rad(140), 0))
end

-- Is a ground point reserved for something (roads, plots, plaza, stands, meadow, arena)?
local function reserved(p: Vector3): boolean
	local x, z = p.X, p.Z
	if v(x, 0, z).Magnitude < W.Plaza.radius + 36 then
		return true
	end
	if math.abs(x) < 40 and z > W.ArenaGate.Z - 40 and z < 270 then
		return true -- north/south roads
	end
	if math.abs(z) < 26 and math.abs(x) < 250 then
		return true
	end
	if math.abs(math.abs(x) - 232) < 26 and z > -310 and z < 370 then
		return true
	end
	for _, plot in W.Plots do
		local d = p - plot.origin
		if math.abs(d.X) < W.PlotSize.Y / 2 + 14 and math.abs(d.Z) < W.PlotSize.X / 2 + 14 then
			return true
		end
	end
	for _, s in W.Stands do
		if (p - s).Magnitude < 30 then
			return true
		end
	end
	if (p - W.InvasionField.center).Magnitude < W.InvasionField.radius + 10 then
		return true
	end
	if (p - v(185, 0, -330)).Magnitude < 58 then
		return true
	end
	if (p - W.Spawn).Magnitude < 50 then
		return true
	end
	if z < -560 then
		return true -- stadium grounds
	end
	return false
end
HubBuilder.reserved = reserved

local function scenery(parent: Instance)
	local f = BuildKit.folder("Scenery", parent)
	Props.setSeed(77)
	local rng = Props.random()
	local H = W.Hub
	local function anywhere(): Vector3
		return v(rng:NextNumber(H.minX, H.maxX), 0, rng:NextNumber(H.minZ, H.maxZ))
	end
	local function edge(): Vector3
		-- forest belt along the hub edges
		local side = rng:NextInteger(1, 3)
		if side == 1 then
			return v(rng:NextNumber(H.minX, H.maxX), 0, rng:NextNumber(H.maxZ - 80, H.maxZ + 60))
		elseif side == 2 then
			return v(rng:NextNumber(H.minX - 60, H.minX + 70), 0, rng:NextNumber(H.minZ, H.maxZ))
		end
		return v(rng:NextNumber(H.maxX - 70, H.maxX + 60), 0, rng:NextNumber(H.minZ, H.maxZ))
	end
	Props.scatter(f, 110, edge, reserved, function(par, ground)
		Props.tree(par, ground)
	end)
	Props.scatter(f, 45, anywhere, reserved, function(par, ground)
		Props.tree(par, ground)
	end)
	Props.scatter(f, 50, anywhere, reserved, function(par, ground)
		Props.bush(par, ground)
	end)
	Props.scatter(f, 30, anywhere, reserved, function(par, ground)
		Props.rock(par, ground)
	end)
	Props.scatter(f, 160, anywhere, reserved, function(par, ground)
		Props.flowers(par, ground)
	end)
	-- trees lining the stadium approach (outside the road)
	for z = -160, -520, -45 do
		for _, s in { -1, 1 } do
			local p = v(s * rng:NextNumber(60, 90), 0, z + rng:NextNumber(-10, 10))
			Props.tree(f, cf(p), rng:NextNumber(1, 1.3), "Round")
		end
	end
end

-------------------------------------------------------------------------------
-- Invasion meadow marker (where giant monsters land during the Invasion event)
-------------------------------------------------------------------------------
local function meadow(parent: Instance)
	local f = BuildKit.folder("Meadow", parent)
	local c = W.InvasionField.center
	BuildKit.around(c, W.InvasionField.radius, 20, function(ring)
		BuildKit.column(f, 1.4, 1.6, ring.Position, rgb(240, 240, 240), Enum.Material.Marble)
	end)
	local stone = BuildKit.block(f, v(14, 6, 2), cf(c + v(0, 3, -W.InvasionField.radius - 6)), rgb(160, 160, 170), Enum.Material.Slate, true)
	BuildKit.sign(f, stone.CFrame * cf(0, 0, 1.05) * ang(0, math.pi, 0), Vector2.new(13, 5), "⚠️ MONSTER LANDING ZONE", rgb(160, 160, 170), rgb(255, 230, 120))
end

function HubBuilder.build(parent: Instance)
	terrain()
	local hub = BuildKit.folder("Hub", parent)
	roads(hub)
	spawnArea(hub)
	stands(hub)
	signposts(hub)
	plazaDecor(hub)
	pondDecor(hub)
	meadow(hub)
	scenery(hub)
end

return HubBuilder
