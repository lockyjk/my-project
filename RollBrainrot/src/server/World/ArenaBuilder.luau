--!strict
-- The Monster Arena: a 1,080-stud open battlefield inside a colossal stadium.
--
--   inner wall (with banners + torches)  →  six stepped tiers of stands (crowd sits on
--   these; the client spawns the spectators)  →  tall outer facade with arches, flag ring
--   and eight floodlight towers.
--   South: the fighters' tunnel + gate towers (hub side). North: the boss gate with doors.
--   Two giant screens above the stands show wave / boss info (text set by ArenaService).
--
-- Persistent streaming for the shell so the stadium is always visible from the hub.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local BuildKit = require(script.Parent.BuildKit)
local Props = require(script.Parent.Props)

local ArenaBuilder = {}

local v = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local rgb = Color3.fromRGB

local A = GameConfig.World.Arena
local C = A.center
local CONCRETE = rgb(196, 192, 205)
local CONCRETE_DARK = rgb(120, 116, 140)
local WALL = rgb(70, 64, 104)
local PINK = rgb(255, 92, 170)
local CYAN = rgb(70, 210, 255)
local YELLOW = rgb(255, 210, 50)
local RED = rgb(230, 50, 60)
local SECTOR_COLORS = { rgb(255, 92, 170), rgb(70, 160, 255), rgb(255, 200, 60), rgb(110, 210, 110) }

-- angle 0 = south (+Z, towards the hub), π = north (boss gate)
local function polar(r: number, a: number, y: number): Vector3
	return C + v(math.sin(a) * r, y, math.cos(a) * r)
end

local function inGap(a: number, r: number, halfWidth: number, center: number): boolean
	local d = math.abs(((a - center + math.pi) % (2 * math.pi)) - math.pi)
	return d * r < halfWidth
end

ArenaBuilder.inGap = inGap

function ArenaBuilder.inSouthGap(a: number, r: number): boolean
	return inGap(a, r, A.gateHalfWidth + 4, 0)
end

function ArenaBuilder.inNorthGap(a: number, r: number): boolean
	return inGap(a, r, A.bossGateHalfWidth + 4, math.pi)
end

local function gapAt(a: number, r: number): boolean
	return ArenaBuilder.inSouthGap(a, r) or ArenaBuilder.inNorthGap(a, r)
end

-- Ring of segments around the stadium centre skipping the two gate gaps
local function ringSegments(parent: Instance, r: number, segments: number, height: number, y0: number, depth: number, colorFn: (number) -> Color3, material: Enum.Material, collide: boolean)
	local segLen = 2 * math.pi * r / segments + 0.6
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		if not gapAt(a, r) then
			local pos = polar(r, a, y0 + height / 2)
			local look = CFrame.lookAt(pos, v(C.X, pos.Y, C.Z))
			BuildKit.block(parent, v(segLen, height, depth), look, colorFn(i), material, collide)
		end
	end
end

-------------------------------------------------------------------------------
local function battlefield(parent: Instance)
	local f = BuildKit.folder("Battlefield", parent)
	-- chalk markings (thin, non-colliding)
	local function chalkRing(r: number, w: number)
		BuildKit.around(C, r, math.max(24, math.floor(r / 3)), function(ring)
			local seg = BuildKit.block(f, v(2 * math.pi * r / math.max(24, math.floor(r / 3)) + 0.3, 0.12, w), ring * cf(0, 0.06, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
			seg.CastShadow = false
		end)
	end
	chalkRing(90, 2)
	chalkRing(A.fieldRadius - 30, 2.5)
	local mid = BuildKit.block(f, v(2.5, 0.12, (A.fieldRadius - 30) * 2), cf(C + v(0, 0.06, 0)), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
	mid.CastShadow = false
	-- centre emblem
	local emblem = BuildKit.disc(f, 40, 0.15, C + v(0, 0.08, 0), PINK, Enum.Material.SmoothPlastic)
	emblem.Name = "Emblem"
	BuildKit.disc(f, 30, 0.16, C + v(0, 0.1, 0), rgb(255, 255, 255), Enum.Material.SmoothPlastic)
	BuildKit.disc(f, 18, 0.17, C + v(0, 0.12, 0), CYAN, Enum.Material.SmoothPlastic)
	-- the invisible dome cap: stops players jumping out onto the stands
	BuildKit.ring(f, C, A.fieldRadius, 72, 120, 4, rgb(0, 0, 0), Enum.Material.SmoothPlastic, true, nil)
	for _, d in f:GetChildren() do
		if d:IsA("BasePart") and d.Size.Y >= 119 then
			d.Transparency = 1
			d.CastShadow = false
			d.Name = "Barrier"
		end
	end
end

-------------------------------------------------------------------------------
local function innerWall(parent: Instance)
	local f = BuildKit.folder("InnerWall", parent)
	local r = A.fieldRadius + 4
	ringSegments(f, r, 128, A.wallHeight, 0, 8, function()
		return WALL
	end, Enum.Material.Concrete, true)
	-- padded top rail + neon strip
	ringSegments(f, r - 4.5, 128, 2, A.wallHeight - 2, 2, function(i)
		return if i % 2 == 0 then PINK else CYAN
	end, Enum.Material.Neon, false)
	ringSegments(f, r, 128, 1.5, A.wallHeight, 9, function()
		return CONCRETE
	end, Enum.Material.Concrete, true)
	-- banners + torches on the wall every 15°
	local idx = 0
	for deg = 7.5, 360, 15 do
		local a = rad(deg)
		if not gapAt(a, r) then
			idx += 1
			local pos = polar(r - 4.6, a, A.wallHeight * 0.55)
			local look = CFrame.lookAt(pos, v(C.X, pos.Y, C.Z))
			local color = SECTOR_COLORS[idx % #SECTOR_COLORS + 1]
			local banner = BuildKit.block(f, v(12, 22, 0.4), look, color, Enum.Material.Fabric)
			banner.Name = "Banner"
			BuildKit.sign(f, look * cf(0, 0, -0.25), Vector2.new(11, 6), if idx % 2 == 0 then "BRAINROT\nARENA" else "⚔️", color, rgb(255, 255, 255))
			BuildKit.block(f, v(13, 1, 1), look * cf(0, 11.5, 0), YELLOW, Enum.Material.Foil)
			Props.torch(f, cf(polar(r - 7, a + rad(7.5), 0)), A.wallHeight * 0.4, rgb(255, 150, 60))
		end
	end
end

-------------------------------------------------------------------------------
local function stands(parent: Instance)
	local f = BuildKit.folder("Stands", parent)
	for t = 0, A.tierCount - 1 do
		local r = A.standsInner + t * A.tierDepth + A.tierDepth / 2
		local top = A.wallHeight + (t + 1) * A.tierRise
		local segments = 96
		ringSegments(f, r, segments, top, 0, A.tierDepth + 0.5, function(i)
			local sector = (i // 8) % #SECTOR_COLORS + 1
			local base = SECTOR_COLORS[sector]
			return if t % 2 == 0 then base else base:Lerp(rgb(255, 255, 255), 0.35)
		end, Enum.Material.SmoothPlastic, true)
		-- concrete aisle step at the tier edge
		ringSegments(f, r - A.tierDepth / 2 + 1, segments, 1, top, 2, function()
			return CONCRETE
		end, Enum.Material.Concrete, false)
	end
	-- staircases (aisles) every 30°
	for deg = 15, 360, 30 do
		local a = rad(deg)
		if not gapAt(a, A.standsInner) then
			for t = 0, A.tierCount - 1 do
				local r = A.standsInner + t * A.tierDepth + A.tierDepth / 2
				local top = A.wallHeight + (t + 1) * A.tierRise
				local pos = polar(r, a, top + 0.3)
				BuildKit.block(f, v(5, 0.6, A.tierDepth), CFrame.lookAt(pos, v(C.X, pos.Y, C.Z)), CONCRETE_DARK, Enum.Material.Concrete, false)
			end
		end
	end
end

-------------------------------------------------------------------------------
local function facade(parent: Instance)
	local f = BuildKit.folder("Facade", parent)
	local outer = A.standsInner + A.tierCount * A.tierDepth + 6
	local h = A.facadeHeight
	ringSegments(f, outer, 112, h, 0, 10, function(i)
		return if i % 2 == 0 then CONCRETE else rgb(214, 210, 222)
	end, Enum.Material.Concrete, true)
	-- arches on the outside (dark inset + pillar caps), and an inner back wall above the top tier
	local segs = 56
	for i = 0, segs - 1 do
		local a = (i + 0.5) / segs * math.pi * 2
		if not gapAt(a, outer) then
			local pos = polar(outer + 5.2, a, 0)
			local look = CFrame.lookAt(pos, v(C.X, 0, C.Z)) * ang(0, math.pi, 0) -- faces outward
			for row = 0, 2 do
				local y = 22 + row * 48
				BuildKit.block(f, v(26, 34, 0.6), look * cf(0, y + 17, 0), rgb(60, 56, 96), Enum.Material.SmoothPlastic)
				BuildKit.part({
					Shape = Enum.PartType.Cylinder,
					Size = v(0.7, 26, 26),
					CFrame = look * cf(0, y + 34, 0) * ang(0, rad(90), 0),
					Color = rgb(60, 56, 96),
					CanCollide = false,
					Parent = f,
				})
			end
			BuildKit.block(f, v(4, h, 3), look * cf(15, h / 2, -1), rgb(236, 232, 244), Enum.Material.Concrete, false)
		end
	end
	-- glowing crown band
	ringSegments(f, outer, 112, 4, h, 12, function(i)
		return if i % 2 == 0 then PINK else CYAN
	end, Enum.Material.Neon, false)
	-- flag ring
	local idx = 0
	for deg = 0, 359, 12 do
		local a = rad(deg)
		if not gapAt(a, outer) then
			idx += 1
			Props.flag(f, cf(polar(outer, a, h + 2)) * ang(0, a, 0), SECTOR_COLORS[idx % #SECTOR_COLORS + 1], 30)
		end
	end
end

-------------------------------------------------------------------------------
local function floodlights(parent: Instance)
	local f = BuildKit.folder("Floodlights", parent)
	local r = A.standsInner + A.tierCount * A.tierDepth
	for i = 0, 7 do
		local a = rad(22.5 + i * 45)
		local base = polar(r, a, 0)
		local h = A.facadeHeight + 70
		BuildKit.column(f, h, 6, base, rgb(90, 90, 100), Enum.Material.Metal, true)
		local headPos = base + v(0, h + 6, 0)
		local look = CFrame.lookAt(headPos, v(C.X, 0, C.Z))
		BuildKit.block(f, v(30, 18, 3), look, rgb(50, 50, 60), Enum.Material.Metal)
		for x = -1, 1 do
			for y = -1, 1 do
				local lamp = BuildKit.block(f, v(8, 4.6, 0.6), look * cf(x * 9.4, y * 5.4, -1.6), rgb(255, 250, 225), Enum.Material.Neon)
				lamp.CastShadow = false
				if x == 0 and y == 0 then
					local spot = Instance.new("SpotLight")
					spot.Face = Enum.NormalId.Front
					spot.Angle = 60
					spot.Range = 60
					spot.Brightness = 3
					spot.Color = rgb(255, 245, 220)
					spot.Parent = lamp
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
local function screens(parent: Instance)
	local f = BuildKit.folder("Screens", parent)
	local r = A.standsInner + A.tierCount * A.tierDepth - 6
	for _, a in { rad(90), rad(270) } do -- east + west, facing the field
		local pos = polar(r, a, A.facadeHeight + 34)
		local look = CFrame.lookAt(pos, v(C.X, pos.Y, C.Z))
		BuildKit.block(f, v(120, 62, 4), look * cf(0, 0, 2.5), rgb(30, 30, 38), Enum.Material.Metal)
		BuildKit.column(f, A.facadeHeight + 4, 5, polar(r + 4, a + rad(4), 0), rgb(90, 90, 100), Enum.Material.Metal)
		BuildKit.column(f, A.facadeHeight + 4, 5, polar(r + 4, a - rad(4), 0), rgb(90, 90, 100), Enum.Material.Metal)
		local screen, label = BuildKit.sign(f, look * cf(0, 0, 0.2), Vector2.new(112, 54), "MONSTER ARENA\nStep through the gate to fight!", rgb(10, 12, 30), rgb(255, 255, 255))
		screen.Name = "GiantScreen"
		screen.Material = Enum.Material.Neon
		label.Name = "ScreenLabel"
		local gui = label.Parent :: SurfaceGui
		gui.PixelsPerStud = 12
		gui.Brightness = 2
	end
end

-------------------------------------------------------------------------------
-- South gate: twin towers, arch, tunnel, glowing entry barrier
-------------------------------------------------------------------------------
local function southGate(parent: Instance)
	local f = BuildKit.folder("SouthGate", parent)
	f:SetAttribute("Gate", "South")
	local hw = A.gateHalfWidth
	local outer = A.standsInner + A.tierCount * A.tierDepth + 6
	local zIn = C.Z + A.fieldRadius + 2
	local zOut = C.Z + outer + 8
	-- tunnel walls + ceiling
	for _, s in { -1, 1 } do
		BuildKit.block(f, v(8, 60, zOut - zIn), cf(s * (hw + 4), 30, (zIn + zOut) / 2), WALL, Enum.Material.Concrete, true)
		for z = zIn + 10, zOut - 10, 24 do
			Props.torch(f, cf(s * (hw - 2), 0, z), 14, rgb(255, 150, 60))
		end
	end
	BuildKit.block(f, v(hw * 2 + 16, 8, zOut - zIn), cf(0, 64, (zIn + zOut) / 2), WALL, Enum.Material.Concrete, true)
	BuildKit.block(f, v(hw * 2, 0.6, zOut - zIn + 20), cf(0, 0.2, (zIn + zOut) / 2 + 6), rgb(170, 60, 70), Enum.Material.Fabric, true) -- red carpet
	-- gate towers
	for _, s in { -1, 1 } do
		local tp = v(s * (hw + 26), 0, zOut - 6)
		BuildKit.column(f, A.facadeHeight + 40, 44, tp, rgb(214, 210, 222), Enum.Material.Concrete, true)
		BuildKit.column(f, 6, 48, tp + v(0, A.facadeHeight + 40, 0), WALL, Enum.Material.Concrete, true)
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			BuildKit.block(f, v(6, 8, 4), cf(tp + v(math.sin(a) * 22, A.facadeHeight + 50, math.cos(a) * 22)) * ang(0, a, 0), WALL, Enum.Material.Concrete, true)
		end
		Props.flag(f, cf(tp + v(0, A.facadeHeight + 46, 0)), if s < 0 then PINK else CYAN, 44)
		Props.torch(f, cf(tp + v(-s * 10, 0, 26)), 18, rgb(255, 150, 60))
	end
	-- the great arch + sign
	local archCf = cf(0, 92, zOut + 2)
	BuildKit.block(f, v(hw * 2 + 70, 40, 12), archCf, rgb(214, 210, 222), Enum.Material.Concrete, true)
	BuildKit.block(f, v(hw * 2 + 72, 3, 13), archCf * cf(0, -20, 0), YELLOW, Enum.Material.Foil)
	BuildKit.block(f, v(hw * 2 + 72, 3, 13), archCf * cf(0, 20, 0), YELLOW, Enum.Material.Foil)
	local signCf = archCf * cf(0, 0, 6.2) * ang(0, math.pi, 0)
	BuildKit.sign(f, signCf, Vector2.new(hw * 2 + 60, 30), "⚔️ MONSTER ARENA ⚔️", RED, rgb(255, 255, 255))
	-- raised portcullis
	for x = -hw + 3, hw - 3, 6 do
		BuildKit.block(f, v(1.2, 40, 1.2), cf(x, 52, zOut - 2), rgb(70, 70, 80), Enum.Material.Metal)
	end
	-- glowing entry barrier inside the tunnel; ArenaService watches its prompt
	local barrier = BuildKit.part({
		Name = "EntryBarrier",
		Size = v(hw * 2, 60, 2),
		CFrame = cf(0, 30, zOut - 30),
		Color = rgb(255, 120, 200),
		Material = Enum.Material.ForceField,
		Transparency = 0,
		CanCollide = true,
		Parent = f,
	})
	barrier.CastShadow = false
	local prompt = BuildKit.prompt(barrier, "ENTER ARENA", "Monster Arena", "EnterArena", 30)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Name = "EnterPrompt"
	BuildKit.billboard(barrier, "⚔️ ENTER ARENA ⚔️", Vector2.new(30, 6), 16, rgb(255, 255, 255), 250)
	-- forecourt outside the gate
	BuildKit.disc(f, 120, 0.6, v(0, 0.1, zOut + 34), rgb(214, 196, 160), Enum.Material.Cobblestone, true)
	for _, s in { -1, 1 } do
		Props.decoration("Statue", f, cf(s * 46, 0, zOut + 40) * ang(0, rad(-90 * s), 0))
	end
end

-------------------------------------------------------------------------------
-- North boss gate: huge doors that ArenaService slides open for the boss entrance
-------------------------------------------------------------------------------
local function bossGate(parent: Instance)
	local f = BuildKit.folder("BossGate", parent)
	local hw = A.bossGateHalfWidth
	local outer = A.standsInner + A.tierCount * A.tierDepth + 6
	local zIn = C.Z - A.fieldRadius - 2
	local zOut = C.Z - outer - 8
	for _, s in { -1, 1 } do
		BuildKit.block(f, v(10, 110, zIn - zOut), cf(s * (hw + 5), 55, (zIn + zOut) / 2), rgb(50, 44, 60), Enum.Material.Slate, true)
		-- warning stripes
		for i = 0, 7 do
			BuildKit.block(f, v(0.6, 12, 6), cf(s * hw, 6 + i * 13, zIn - 2) * ang(rad(30), 0, 0), if i % 2 == 0 then YELLOW else rgb(30, 30, 30), Enum.Material.SmoothPlastic)
		end
		-- red warning lamps
		local lamp = BuildKit.ball(f, 5, v(s * (hw + 2), 104, zIn - 2), RED, Enum.Material.Neon)
		lamp.Name = "WarningLamp"
		BuildKit.light(lamp, RED, 60, 2)
	end
	BuildKit.block(f, v(hw * 2 + 20, 14, zIn - zOut), cf(0, 117, (zIn + zOut) / 2), rgb(50, 44, 60), Enum.Material.Slate, true)
	-- giant skull emblem above the gate
	local skull = BuildKit.ball(f, 26, v(0, 140, zIn - 4), rgb(235, 230, 220), Enum.Material.Marble)
	skull.Name = "Skull"
	for _, s in { -1, 1 } do
		BuildKit.ball(f, 7, v(s * 5, 142, zIn + 7), RED, Enum.Material.Neon)
	end
	BuildKit.block(f, v(14, 5, 6), cf(0, 130, zIn + 6), rgb(235, 230, 220), Enum.Material.Marble)
	-- doors (two halves)
	local doors = BuildKit.folder("Doors", f)
	for _, s in { -1, 1 } do
		local door = BuildKit.part({
			Name = if s < 0 then "DoorLeft" else "DoorRight",
			Size = v(hw, 108, 6),
			CFrame = cf(s * hw / 2, 54, zIn - 6),
			Color = rgb(80, 60, 50),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = doors,
		})
		door:SetAttribute("ClosedX", s * hw / 2)
		door:SetAttribute("OpenX", s * (hw * 1.5 + 6))
		for y = 10, 100, 22 do
			BuildKit.block(door, v(hw, 3, 6.6), cf(s * hw / 2, y, zIn - 6), rgb(60, 60, 70), Enum.Material.Metal)
		end
	end
	f:SetAttribute("BossSpawn", v(0, 0, zIn + 30))
	f:SetAttribute("BossOutside", v(0, 0, zOut + 20))
end

function ArenaBuilder.build(parent: Instance): Model
	local m = BuildKit.model("MonsterArena", parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("Center", C)
	battlefield(m)
	innerWall(m)
	stands(m)
	facade(m)
	floodlights(m)
	screens(m)
	southGate(m)
	bossGate(m)
	return m
end

return ArenaBuilder
