--!strict
-- Draws every battle unit the server simulates: Brainrots and monsters as real models,
-- smoothly following unreliable position snapshots, with walk/attack/hit animations,
-- death tumbles, health bars and pooled floating damage numbers.
--
-- Non-unit events (abilities, telegraphs, boss intro, …) are re-fired on `Event` for
-- CombatFx / BattleUI / CrowdController.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Animator = require(Modules:WaitForChild("Models"):WaitForChild("Animator"))
local BrainrotModels = require(Modules.Models:WaitForChild("BrainrotModels"))
local Format = require(Modules:WaitForChild("Format"))
local MonsterModels = require(Modules.Models:WaitForChild("MonsterModels"))
local Net = require(Modules:WaitForChild("Net"))
local Registry = require(Modules:WaitForChild("Registry"))
local Signal = require(Modules:WaitForChild("Signal"))
local Theme = require(Modules:WaitForChild("Theme"))

local Effects = require(script.Parent.Effects)

local UnitRenderer = {}

-- (battleId, event) for everything that isn't a plain unit update
UnitRenderer.Event = Signal.new() :: Signal.Signal<number, { [string]: any }>

export type View = {
	id: number,
	battle: number,
	kind: string,
	defId: string,
	mut: string,
	team: string,
	owner: number,
	isBoss: boolean,
	model: Model,
	rig: Animator.Rig,
	height: number,
	pos: Vector3,
	target: Vector3,
	yaw: number,
	targetYaw: number,
	moving: boolean,
	casting: boolean,
	hp: number,
	mhp: number,
	alive: boolean,
	deadAt: number,
	bar: BillboardGui?,
	barFill: Frame?,
	shownBar: boolean,
	statuses: { [string]: boolean },
	auras: { [string]: Instance },
}

type BattleView = { id: number, center: Vector3, units: { [number]: View } }

local battles: { [number]: BattleView } = {}
local folder: Folder
local myId = Players.LocalPlayer.UserId

-------------------------------------------------------------------------------
-- Lookups for other modules
-------------------------------------------------------------------------------
function UnitRenderer.get(battleId: number, unitId: number): View?
	local b = battles[battleId]
	return b and b.units[unitId]
end

function UnitRenderer.center(battleId: number): Vector3?
	local b = battles[battleId]
	return b and b.center
end

function UnitRenderer.units(battleId: number): { [number]: View }
	local b = battles[battleId]
	return if b then b.units else {}
end

-------------------------------------------------------------------------------
-- Damage numbers (pooled)
-------------------------------------------------------------------------------
local numberPool: { BillboardGui } = {}
local numberAnchor: Part

local function damageNumber(pos: Vector3, text: string, color: Color3, size: number)
	if not Effects.near(pos, 220) then
		return
	end
	local gui = table.remove(numberPool)
	if not gui then
		local g = Instance.new("BillboardGui")
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.Size = UDim2.fromOffset(160, 50)
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Theme.Font
		label.TextScaled = true
		label.Parent = g
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Theme.Colors.Ink
		stroke.Parent = label
		g.Adornee = numberAnchor
		g.Parent = numberAnchor
		gui = g
	end
	local g = gui :: BillboardGui
	local label = g:FindFirstChild("Label") :: TextLabel
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	g.Size = UDim2.fromOffset(110 * size, 36 * size)
	local jitter = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
	g.StudsOffsetWorldSpace = pos - numberAnchor.Position + jitter
	g.Enabled = true
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / 0.9
		if t >= 1 then
			conn:Disconnect()
			g.Enabled = false
			table.insert(numberPool, g)
			return
		end
		g.StudsOffsetWorldSpace = pos - numberAnchor.Position + jitter + Vector3.new(0, t * 5, 0)
		label.TextTransparency = math.max(0, t * 1.6 - 0.6)
	end)
end
UnitRenderer.damageNumber = damageNumber

-------------------------------------------------------------------------------
-- Health bars
-------------------------------------------------------------------------------
local function makeBar(v: View)
	if v.isBoss or not v.model.PrimaryPart then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if v.team == "ally" then 70 else 90, 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, v.height + 1.6, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = v.team == "ally"
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Theme.Colors.Ink
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, -2, 1, -2)
	fill.Position = UDim2.fromOffset(1, 1)
	fill.BorderSizePixel = 0
	local own = v.owner == myId
	fill.BackgroundColor3 = if v.team == "enemy"
		then Theme.Colors.HpEnemy
		elseif own then Theme.Colors.Hp
		else Color3.fromRGB(110, 190, 255)
	fill.Parent = back
	local c2 = corner:Clone()
	c2.Parent = fill
	gui.Parent = v.model.PrimaryPart
	v.bar = gui
	v.barFill = fill
end

local function updateBar(v: View)
	local fill = v.barFill
	if fill then
		local f = math.clamp(v.hp / math.max(1, v.mhp), 0, 1)
		fill.Size = UDim2.new(f, -2, 1, -2)
		if v.bar and v.team == "enemy" and not v.shownBar and f < 1 then
			v.shownBar = true
			v.bar.Enabled = true
		end
	end
end

-------------------------------------------------------------------------------
-- Status visuals (shield bubble, slow, burn, taunt, rally)
-------------------------------------------------------------------------------
local STATUS_LOOK: { [string]: { color: Color3, kind: string } } = {
	Shield = { color = Color3.fromRGB(120, 230, 90), kind = "bubble" },
	Slow = { color = Color3.fromRGB(120, 200, 255), kind = "ring" },
	Burn = { color = Color3.fromRGB(255, 120, 30), kind = "fire" },
	Taunt = { color = Color3.fromRGB(255, 70, 70), kind = "ring" },
	Rally = { color = Color3.fromRGB(255, 210, 60), kind = "ring" },
	Haste = { color = Color3.fromRGB(255, 60, 60), kind = "fire" },
}

local function setStatus(v: View, name: string, on: boolean)
	if on then
		v.statuses[name] = true
	else
		v.statuses[name] = nil
	end
	local existing = v.auras[name]
	if existing then
		existing:Destroy()
		v.auras[name] = nil
	end
	local look = STATUS_LOOK[name]
	local root = v.model.PrimaryPart
	if not on or not look or not root then
		return
	end
	if look.kind == "fire" then
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(0, v.height * 0.5, 0)
		att.Parent = root
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(look.color)
		fire.LightEmission = 1
		fire.Size = NumberSequence.new(math.min(6, v.height * 0.25), 0)
		fire.Lifetime = NumberRange.new(0.3, 0.6)
		fire.Speed = NumberRange.new(2, 5)
		fire.Rate = if v.isBoss then 40 else 14
		fire.Parent = att
		v.auras[name] = att
	else
		local p = Instance.new("Part")
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Material = if look.kind == "bubble" then Enum.Material.ForceField else Enum.Material.Neon
		p.Color = look.color
		if look.kind == "bubble" then
			p.Shape = Enum.PartType.Ball
			local d = math.max(v.height, 4) * 1.4
			p.Size = Vector3.one * d
			p.CFrame = root.CFrame * CFrame.new(0, v.height * 0.5, 0)
		else
			p.Shape = Enum.PartType.Cylinder
			local d = math.max(4, v.height * 0.9)
			p.Size = Vector3.new(0.2, d, d)
			p.Transparency = 0.4
			p.CFrame = root.CFrame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
		end
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		p.Parent = v.model
		v.auras[name] = p
	end
end

-------------------------------------------------------------------------------
-- Spawning / removing views
-------------------------------------------------------------------------------
local function spawnView(b: BattleView, ev: { [string]: any })
	local existing = b.units[ev.id]
	if existing then
		existing.model:Destroy()
	end
	local model = if ev.k == "monster" then MonsterModels.build(ev.d) else BrainrotModels.build(ev.d, ev.m)
	model.Parent = folder
	local pos = Vector3.new(ev.x, b.center.Y, ev.z)
	local quirk = if ev.k == "brainrot" and Registry.Brainrot[ev.d] then Registry.Brainrot[ev.d].idleQuirk else nil
	local v: View = {
		id = ev.id,
		battle = b.id,
		kind = ev.k,
		defId = ev.d,
		mut = ev.m or "Normal",
		team = ev.team,
		owner = ev.o or 0,
		isBoss = ev.boss == true,
		model = model,
		rig = Animator.rig(model, quirk),
		height = (model:GetAttribute("Height") :: number?) or 4,
		pos = pos,
		target = pos,
		yaw = 0,
		targetYaw = 0,
		moving = false,
		casting = false,
		hp = ev.hp,
		mhp = ev.mhp,
		alive = ev.alive ~= false,
		deadAt = 0,
		bar = nil,
		barFill = nil,
		shownBar = false,
		statuses = {},
		auras = {},
	}
	b.units[ev.id] = v
	makeBar(v)
	updateBar(v)
	-- spawn puff
	if ev.k == "monster" and not v.isBoss then
		Effects.burst(pos + Vector3.new(0, 1, 0), Color3.fromRGB(150, 120, 200), 8, "smoke", 8, 2)
	elseif ev.k == "brainrot" then
		Effects.burst(pos + Vector3.new(0, 2, 0), Registry.rarityOf(ev.d).color, 12, "sparkle", 12, 1)
	end
end

local function removeView(b: BattleView, id: number)
	local v = b.units[id]
	if not v then
		return
	end
	b.units[id] = nil
	local model = v.model
	-- fade out instead of popping
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	task.delay(0.4, function()
		model:Destroy()
	end)
end

local function clearBattle(battleId: number)
	local b = battles[battleId]
	if not b then
		return
	end
	for _, v in b.units do
		v.model:Destroy()
	end
	battles[battleId] = nil
end

-------------------------------------------------------------------------------
-- Event handling
-------------------------------------------------------------------------------
local function onEvent(battleId: number, ev: { [string]: any })
	local t = ev.t
	if t == "reset" then
		clearBattle(battleId)
		battles[battleId] = { id = battleId, center = Vector3.new(ev.cx, ev.cy, ev.cz), units = {} }
		return
	elseif t == "clear" then
		clearBattle(battleId)
		UnitRenderer.Event:Fire(battleId, ev)
		return
	end
	local b = battles[battleId]
	if not b then
		return
	end
	if t == "spawn" then
		spawnView(b, ev)
	elseif t == "despawn" then
		removeView(b, ev.id)
	elseif t == "hit" then
		local v = b.units[ev.id]
		if v then
			v.hp = ev.hp
			updateBar(v)
			Animator.hit(v.rig)
			local big = ev.c == true
			local color = if v.team == "ally"
				then Color3.fromRGB(255, 110, 110)
				elseif big then Theme.Colors.Warn
				else Color3.new(1, 1, 1)
			local size = (if big then 1.5 else 1) * (if v.isBoss then 1.4 else 1)
			damageNumber(
				v.pos + Vector3.new(0, v.height + 1, 0),
				(if big then "💥" else "") .. Format.short(ev.a),
				color,
				size
			)
		end
		UnitRenderer.Event:Fire(battleId, ev)
	elseif t == "heal" then
		local v = b.units[ev.id]
		if v then
			v.hp = ev.hp
			updateBar(v)
			damageNumber(v.pos + Vector3.new(0, v.height + 1, 0), "+" .. Format.short(ev.a), Theme.Colors.Good, 0.9)
		end
	elseif t == "atk" then
		local v = b.units[ev.id]
		if v then
			Animator.attack(v.rig)
		end
		UnitRenderer.Event:Fire(battleId, ev)
	elseif t == "die" then
		local v = b.units[ev.id]
		if v then
			v.alive = false
			v.deadAt = os.clock()
			v.hp = 0
			updateBar(v)
			if v.bar then
				v.bar.Enabled = false
			end
			for name in v.statuses do
				setStatus(v, name, false)
			end
			Effects.burst(
				v.pos + Vector3.new(0, v.height * 0.5, 0),
				if v.team == "enemy" then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(200, 200, 220),
				if v.isBoss then 120 else 14,
				"sparkle",
				if v.isBoss then 60 else 16,
				if v.isBoss then 4 else 1.2
			)
		end
		UnitRenderer.Event:Fire(battleId, ev)
	elseif t == "revive" then
		local v = b.units[ev.id]
		if v then
			v.alive = true
			v.hp = ev.hp
			v.pos = Vector3.new(ev.x, b.center.Y, ev.z)
			v.target = v.pos
			updateBar(v)
			if v.bar then
				v.bar.Enabled = true
			end
			Effects.pillar(v.pos, Theme.Colors.Good, 20, 4, 0.6)
		end
	elseif t == "status" then
		local v = b.units[ev.id]
		if v then
			setStatus(v, ev.s, ev.on == true)
		end
	else
		if t == "ab" then
			local v = b.units[ev.id]
			if v then
				Animator.attack(v.rig)
				if ev.x and ev.fx then
					-- dashes: snap the view to the landing point quickly
					v.target = Vector3.new(ev.x, b.center.Y, ev.z)
				end
			end
		end
		UnitRenderer.Event:Fire(battleId, ev)
	end
end

local function onSnapshot(packet: buffer)
	if buffer.len(packet) < 4 then
		return
	end
	local battleId = buffer.readu16(packet, 0)
	local b = battles[battleId]
	if not b then
		return
	end
	local n = buffer.readu16(packet, 2)
	if buffer.len(packet) < 4 + n * 8 then
		return
	end
	for k = 0, n - 1 do
		local off = 4 + k * 8
		local id = buffer.readu16(packet, off)
		local v = b.units[id]
		if v then
			local x = buffer.readi16(packet, off + 2) / 10
			local z = buffer.readi16(packet, off + 4) / 10
			local yaw = buffer.readu8(packet, off + 6) / 255 * math.pi * 2
			local flags = buffer.readu8(packet, off + 7)
			v.target = Vector3.new(b.center.X + x, b.center.Y, b.center.Z + z)
			v.targetYaw = yaw
			v.moving = flags % 2 == 1
			v.casting = math.floor(flags / 2) % 2 == 1
		end
	end
end

-------------------------------------------------------------------------------
function UnitRenderer.start()
	local live = Workspace:WaitForChild("Live")
	folder = Instance.new("Folder")
	folder.Name = "BattleUnits"
	folder.Parent = live
	numberAnchor = Effects.part(Enum.PartType.Block, Vector3.one * 0.1, CFrame.new(0, 0, 0), Color3.new(1, 1, 1))
	numberAnchor.Transparency = 1
	numberAnchor.Name = "DamageNumbers"

	Net.Client.on("CombatEvents", function(battleId: number, events: { { [string]: any } })
		for _, ev in events do
			local ok, err = (pcall :: any)(onEvent, battleId, ev)
			if not ok then
				warn(`[UnitRenderer] {ev.t}: {err}`)
			end
		end
	end)
	Net.Client.on("CombatSnap", onSnapshot)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
		local follow = 1 - math.exp(-dt * 12)
		for _, b in battles do
			for _, v in b.units do
				local far = (v.pos - camPos).Magnitude > 700
				v.pos = v.pos:Lerp(v.target, follow)
				local diff = (v.targetYaw - v.yaw + math.pi) % (2 * math.pi) - math.pi
				v.yaw += diff * math.min(1, dt * 10)
				if far then
					continue
				end
				local base = CFrame.new(v.pos) * CFrame.Angles(0, v.yaw, 0)
				if not v.alive then
					-- tumble over and sink
					local k = math.min(1, (now - v.deadAt) / 0.6)
					base *= CFrame.new(0, -k * v.height * 0.15, 0) * CFrame.Angles(0, 0, k * math.rad(85))
					v.rig.root.CFrame = base
				else
					if v.casting then
						-- windup: rear up
						base *= CFrame.new(0, math.sin(now * 6) * 0.04 * v.height, 0) * CFrame.Angles(-0.18, 0, 0)
					end
					Animator.update(v.rig, base, now, v.moving, if v.isBoss then 0.45 else 1.2)
				end
			end
		end
	end)
end

return UnitRenderer
