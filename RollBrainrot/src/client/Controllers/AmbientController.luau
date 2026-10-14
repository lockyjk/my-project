--!strict
-- Life in the hub: blocky NPC visitors stroll between landmarks, stop to cheer at the roll
-- machine, and tour occupied zoos. Purely cosmetic and client-side (cheap BulkMoveTo
-- limb animation, culled by distance). Also waves flags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local AmbientController = {}

local W = GameConfig.World
local HUB_NPCS = 16
local VISITORS_PER_ZOO = 3
local VIEW = 420

local SHIRTS = {
	Color3.fromRGB(255, 92, 170),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(110, 210, 110),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 130, 60),
	Color3.fromRGB(240, 240, 245),
}
local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(230, 180, 140),
	Color3.fromRGB(170, 120, 85),
	Color3.fromRGB(120, 80, 55),
}
local PANTS =
	{ Color3.fromRGB(50, 60, 90), Color3.fromRGB(40, 40, 46), Color3.fromRGB(90, 70, 50), Color3.fromRGB(70, 90, 140) }

type Npc = {
	parts: { BasePart },
	offsets: { CFrame },
	limbs: { [string]: number }, -- name -> index in parts
	pos: Vector3,
	yaw: number,
	goal: Vector3,
	waitUntil: number,
	cheer: boolean,
	route: () -> Vector3,
	phase: number,
	speed: number,
	plot: number?,
	visible: boolean,
}

local npcs: { Npc } = {}
local folder: Folder

local function part(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function makeNpc(route: () -> Vector3, plot: number?): Npc
	local shirt, skin, pants = pick(SHIRTS), pick(SKIN), pick(PANTS)
	local parts, offsets, limbs = {}, {}, {}
	local function add(name: string, p: BasePart, off: CFrame)
		table.insert(parts, p)
		table.insert(offsets, off)
		limbs[name] = #parts
	end
	add("LegL", part(Vector3.new(0.9, 2, 0.9), pants), CFrame.new(-0.5, 1, 0))
	add("LegR", part(Vector3.new(0.9, 2, 0.9), pants), CFrame.new(0.5, 1, 0))
	add("Torso", part(Vector3.new(2, 2, 1), shirt), CFrame.new(0, 3, 0))
	add("ArmL", part(Vector3.new(0.8, 2, 0.8), skin), CFrame.new(-1.4, 3, 0))
	add("ArmR", part(Vector3.new(0.8, 2, 0.8), skin), CFrame.new(1.4, 3, 0))
	add("Head", part(Vector3.new(1.3, 1.3, 1.3), skin, Enum.PartType.Ball), CFrame.new(0, 4.65, 0))
	if math.random() < 0.5 then
		add(
			"Hat",
			part(Vector3.new(1.5, 0.5, 1.5), pick(SHIRTS), Enum.PartType.Cylinder),
			CFrame.new(0, 5.3, 0) * CFrame.Angles(0, 0, math.rad(90))
		)
	end
	if math.random() < 0.3 then
		add("Balloon", part(Vector3.new(1.6, 1.6, 1.6), pick(SHIRTS), Enum.PartType.Ball), CFrame.new(1.6, 8, 0))
		add("String", part(Vector3.new(0.05, 4, 0.05), Color3.new(1, 1, 1)), CFrame.new(1.55, 5.5, 0))
	end
	local start = route()
	return {
		parts = parts,
		offsets = offsets,
		limbs = limbs,
		pos = start,
		yaw = math.random() * 6.28,
		goal = route(),
		waitUntil = 0,
		cheer = false,
		route = route,
		phase = math.random() * 10,
		speed = 6 + math.random() * 3,
		plot = plot,
		visible = true,
	}
end

-- Hub landmarks NPCs wander between
local function hubPoint(): Vector3
	local r = math.random()
	local p: Vector3
	if r < 0.3 then
		local a = math.random() * math.pi * 2
		p = Vector3.new(math.sin(a) * 50, 0, 30 + math.cos(a) * 20) -- in front of the machine
	elseif r < 0.5 then
		local s = pick({ W.Stands.Shop, W.Stands.Upgrades, W.Stands.Daily, W.Stands.Events })
		p = s + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)) * 0.8 - s.Unit * 14
	elseif r < 0.75 then
		p = Vector3.new(pick({ -232, 232 }), 0, math.random(-260, 320))
	elseif r < 0.9 then
		p = W.Spawn + Vector3.new(math.random(-30, 30), 0, math.random(-20, 20))
	else
		p = Vector3.new(math.random(-14, 14), 0, math.random(-450, -120)) -- road to the arena
	end
	return Vector3.new(p.X, 0.6, p.Z)
end

local function visitorRoute(plotIndex: number): () -> Vector3
	return function()
		local plot = W.Plots[plotIndex]
		local cf = CFrame.lookAt(plot.origin, plot.origin + plot.facing)
		local lanes = { -64, -5 }
		local p = cf * CFrame.new(math.random(-80, 80), 0, pick(lanes))
		return Vector3.new(p.X, 0.6, p.Z)
	end
end

local function pose(n: Npc, now: number, moving: boolean)
	local base = CFrame.new(n.pos) * CFrame.Angles(0, n.yaw, 0)
	local swing = if moving then math.sin((now + n.phase) * 9) * 0.7 else 0
	local bob = if moving then math.abs(math.sin((now + n.phase) * 9)) * 0.15 else 0
	local cheerUp = if n.cheer then math.abs(math.sin((now + n.phase) * 6)) else 0
	local cfs = table.create(#n.parts)
	for i, off in n.offsets do
		local cf = base * CFrame.new(0, bob + cheerUp * 0.8, 0) * off
		if i == n.limbs.LegL then
			cf = base * CFrame.new(-0.5, 2, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
		elseif i == n.limbs.LegR then
			cf = base * CFrame.new(0.5, 2, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1, 0)
		elseif i == n.limbs.ArmL then
			local raise = if n.cheer then math.rad(160) - cheerUp * 0.4 else -swing
			cf = base
				* CFrame.new(0, bob + cheerUp * 0.8, 0)
				* CFrame.new(-1.4, 3.9, 0)
				* CFrame.Angles(raise, 0, 0)
				* CFrame.new(0, -0.9, 0)
		elseif i == n.limbs.ArmR then
			local raise = if n.cheer then math.rad(160) - cheerUp * 0.4 else swing
			cf = base
				* CFrame.new(0, bob + cheerUp * 0.8, 0)
				* CFrame.new(1.4, 3.9, 0)
				* CFrame.Angles(raise, 0, 0)
				* CFrame.new(0, -0.9, 0)
		end
		cfs[i] = cf
	end
	Workspace:BulkMoveTo(n.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function update(n: Npc, now: number, dt: number)
	if now < n.waitUntil then
		pose(n, now, false)
		return
	end
	n.cheer = false
	local delta = Vector3.new(n.goal.X - n.pos.X, 0, n.goal.Z - n.pos.Z)
	local d = delta.Magnitude
	if d < 1 then
		n.goal = n.route()
		n.waitUntil = now + 1.5 + math.random() * 5
		-- people near the machine cheer while they wait
		n.cheer = n.pos.Magnitude < 70 and math.random() < 0.6
		return
	end
	n.pos += delta.Unit * math.min(d, n.speed * dt)
	n.yaw = math.atan2(-delta.X, -delta.Z)
	pose(n, now, true)
end

local function setVisible(n: Npc, visible: boolean)
	if n.visible == visible then
		return
	end
	n.visible = visible
	for _, p in n.parts do
		p.Transparency = if visible then 0 else 1
	end
end

function AmbientController.cheerAll()
	for _, n in npcs do
		if n.pos.Magnitude < 120 then
			n.cheer = true
			n.waitUntil = os.clock() + 3
		end
	end
end

function AmbientController.start()
	local live = Workspace:WaitForChild("Live")
	folder = Instance.new("Folder")
	folder.Name = "Ambient"
	folder.Parent = live
	for _ = 1, HUB_NPCS do
		table.insert(npcs, makeNpc(hubPoint))
	end
	for i in W.Plots do
		for _ = 1, VISITORS_PER_ZOO do
			table.insert(npcs, makeNpc(visitorRoute(i), i))
		end
	end
	local state = ReplicatedStorage:WaitForChild("ZooState")

	-- flags: find cloth parts once (they're anchored world parts)
	local cloths: { BasePart } = {}
	local baseCf: { [BasePart]: CFrame } = {}
	task.spawn(function()
		while true do
			table.clear(cloths)
			local world = Workspace:FindFirstChild("World")
			if world then
				for _, d in world:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("Wave") then
						table.insert(cloths, d)
						if not baseCf[d] then
							baseCf[d] = d.CFrame
						end
					end
				end
			end
			task.wait(10) -- re-scan as parts stream in
		end
	end)

	local frame = 0
	RunService.Heartbeat:Connect(function(dt: number)
		frame += 1
		local now = os.clock()
		local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
		for _, n in npcs do
			local occupied = true
			if n.plot then
				local cfg = state:FindFirstChild(`Plot{n.plot}`)
				occupied = cfg ~= nil and (cfg:GetAttribute("OwnerId") or 0) ~= 0
			end
			local near = occupied and (n.pos - camPos).Magnitude < VIEW
			setVisible(n, near)
			if near then
				update(n, now, dt)
			end
		end
		-- flags wave at 20 Hz
		if frame % 3 == 0 then
			for _, c in cloths do
				local b = baseCf[c]
				if b and (b.Position - camPos).Magnitude < 700 then
					c.CFrame = b * CFrame.Angles(0, math.sin(now * 3 + b.Position.X * 0.1) * 0.12, 0)
				end
			end
		end
	end)
end

return AmbientController
