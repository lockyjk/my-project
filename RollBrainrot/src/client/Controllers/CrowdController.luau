--!strict
-- Thousands of stadium spectators, built client-side only when the camera is near the
-- stadium. Each fan is two anchored, shadowless, non-queryable parts. They react to the
-- fight through "hype" (Bus.Crowd): big hits and kills → some fans bounce, boss entrance →
-- everyone on their feet, boss defeated → a stadium-wide Mexican wave + flags.
-- Only fans whose pose changes are moved (one BulkMoveTo per update), so a calm crowd
-- costs nothing.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local Bus = require(script.Parent.Parent.UI.Bus)

local CrowdController = {}

local A = GameConfig.World.Arena
local CROWD = GameConfig.Crowd
local CENTER = A.center

local SHIRTS = {
	Color3.fromRGB(255, 92, 170),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(110, 210, 110),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 130, 60),
	Color3.fromRGB(245, 245, 250),
	Color3.fromRGB(230, 60, 60),
}
local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(230, 180, 140),
	Color3.fromRGB(170, 120, 85),
	Color3.fromRGB(120, 80, 55),
}

type Fan = {
	body: Part,
	head: Part,
	base: CFrame,
	angle: number,
	threshold: number,
	phase: number,
	speed: number,
	up: boolean,
}

local fans: { Fan } = {}
local folder: Folder? = nil
local hype = 0 -- 0 calm .. 1 everyone jumping
local waveUntil = 0
local waveStart = 0

local function inGap(a: number, r: number): boolean
	local function gap(center: number, half: number): boolean
		local d = math.abs(((a - center + math.pi) % (2 * math.pi)) - math.pi)
		return d * r < half
	end
	return gap(0, A.gateHalfWidth + 10) or gap(math.pi, A.bossGateHalfWidth + 10)
end

local function build()
	local f = Instance.new("Folder")
	f.Name = "Crowd"
	f.Parent = Workspace:WaitForChild("Live")
	folder = f
	local s = CROWD.FanScale
	-- total row length → spacing that hits MaxSpectators
	local rows = {}
	local total = 0
	for t = 0, A.tierCount - 1 do
		local r = A.standsInner + t * A.tierDepth + A.tierDepth * 0.55
		local y = A.wallHeight + (t + 1) * A.tierRise
		table.insert(rows, { r = r, y = y })
		total += 2 * math.pi * r
	end
	local spacing = total / CROWD.MaxSpectators
	local rng = Random.new(31)
	for _, row in rows do
		local count = math.floor(2 * math.pi * row.r / spacing)
		for i = 0, count - 1 do
			local a = (i + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
			if not inGap(a, row.r) then
				local r = row.r + rng:NextNumber(-3, 3)
				local pos = CENTER + Vector3.new(math.sin(a) * r, row.y, math.cos(a) * r)
				local base = CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z))
				local body = Instance.new("Part")
				body.Size = Vector3.new(2.2, 2.6, 1.3) * s
				body.Color = SHIRTS[rng:NextInteger(1, #SHIRTS)]
				body.Material = Enum.Material.SmoothPlastic
				body.Anchored = true
				body.CanCollide = false
				body.CanQuery = false
				body.CanTouch = false
				body.CastShadow = false
				body.CFrame = base * CFrame.new(0, 1.3 * s, 0)
				body.Parent = f
				local head = Instance.new("Part")
				head.Shape = Enum.PartType.Ball
				head.Size = Vector3.one * 1.5 * s
				head.Color = SKIN[rng:NextInteger(1, #SKIN)]
				head.Material = Enum.Material.SmoothPlastic
				head.Anchored = true
				head.CanCollide = false
				head.CanQuery = false
				head.CanTouch = false
				head.CastShadow = false
				head.CFrame = base * CFrame.new(0, 3.3 * s, 0)
				head.Parent = f
				if #fans % 250 == 0 then
					task.wait() -- spread the build over frames (no hitch)
				end
				if folder ~= f then
					return -- destroyed while building
				end
				table.insert(fans, {
					body = body,
					head = head,
					base = base,
					angle = a,
					threshold = rng:NextNumber(0.05, 1),
					phase = rng:NextNumber(0, 6.28),
					speed = rng:NextNumber(7, 11),
					up = false,
				})
			end
		end
	end
end

local function destroy()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(fans)
end

local function react(kind: string, intensity: number)
	if kind == "roar" then
		hype = 1
	elseif kind == "celebrate" then
		hype = 1
		waveStart = os.clock()
		waveUntil = os.clock() + 8
	elseif kind == "gasp" then
		hype = math.max(hype, 0.35 * intensity)
	else
		hype = math.min(1, hype + intensity)
	end
end

function CrowdController.start()
	Bus.Crowd:Connect(react)
	local acc = 0
	local s = CROWD.FanScale
	RunService.Heartbeat:Connect(function(dt: number)
		local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
		local dist = (camPos - CENTER).Magnitude
		if dist < CROWD.BuildDistance and not folder then
			task.spawn(build)
		elseif dist > CROWD.BuildDistance + 250 and folder then
			destroy()
		end
		hype = math.max(0, hype - dt * 0.12) -- calm down over ~8s
		acc += dt
		if not folder or acc < 1 / CROWD.UpdateHz then
			return
		end
		acc = 0
		local now = os.clock()
		local waving = now < waveUntil
		local waveAngle = (now - waveStart) * 1.6
		local parts: { BasePart } = {}
		local cfs: { CFrame } = {}
		for _, fan in fans do
			local jump = 0
			if fan.threshold < hype then
				jump = math.abs(math.sin(now * fan.speed + fan.phase)) * 1.6 * s
			end
			if waving then
				local d = math.abs(((fan.angle - waveAngle + math.pi) % (2 * math.pi)) - math.pi)
				if d < 0.25 then
					jump = math.max(jump, (1 - d / 0.25) * 3 * s)
				end
			end
			if jump > 0.01 or fan.up then
				fan.up = jump > 0.01
				table.insert(parts, fan.body)
				table.insert(cfs, fan.base * CFrame.new(0, 1.3 * s + jump, 0))
				table.insert(parts, fan.head)
				table.insert(cfs, fan.base * CFrame.new(0, 3.3 * s + jump * 1.1, 0))
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return CrowdController
