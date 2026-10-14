--!strict
-- Procedural animation for part-built creatures (client only). One `update` call per frame
-- per visible creature: bobbing walk, breathing idle, attack lunges, hit shakes, idle
-- quirks (Bananini slips over, Froggolino hops, …), orbiting planets and rainbow hue cycling.
-- Everything is a single Root.CFrame write plus a few orbit parts, so hundreds are cheap.

local Animator = {}

export type Rig = {
	model: Model,
	root: BasePart,
	height: number,
	scale: number,
	quirk: string,
	phase: number,
	orbits: { BasePart },
	rainbow: { BasePart },
	attackAt: number,
	hitAt: number,
	quirkAt: number,
	quirkKind: string?,
	floatHeight: number,
	nextRainbow: number,
}

function Animator.rig(model: Model, quirk: string?): Rig
	local root = model.PrimaryPart :: BasePart
	local orbits, rainbow = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Orbit") then
				table.insert(orbits, d)
			end
			if d:GetAttribute("RainbowOffset") then
				table.insert(rainbow, d)
			end
		end
	end
	return {
		model = model,
		root = root,
		height = (model:GetAttribute("Height") :: number?) or 4,
		scale = model:GetScale(),
		quirk = quirk or "",
		phase = math.random() * 10,
		orbits = orbits,
		rainbow = rainbow,
		attackAt = -10,
		hitAt = -10,
		quirkAt = -10,
		quirkKind = nil,
		floatHeight = if quirk == "Float" then 0.6 else 0,
		nextRainbow = 0,
	}
end

function Animator.attack(rig: Rig)
	rig.attackAt = os.clock()
end

function Animator.hit(rig: Rig)
	rig.hitAt = os.clock()
end

function Animator.quirk(rig: Rig, kind: string?)
	rig.quirkAt = os.clock()
	rig.quirkKind = kind or rig.quirk
end

local QUIRK_LENGTH = {
	Slip = 1.6,
	Hop = 0.7,
	HatTip = 1.0,
	Wobble = 1.2,
	Aim = 1.6,
	Zoom = 0.8,
	Stomp = 1.0,
	Float = 2.0,
	Spin = 0.9,
}

local function quirkOffset(kind: string, k: number, h: number): CFrame
	local s = math.sin(k * math.pi)
	if kind == "Slip" then
		-- feet fly forward, flat on the back, then pop back up
		local tilt = if k < 0.25 then k / 0.25 elseif k < 0.7 then 1 else 1 - (k - 0.7) / 0.3
		return CFrame.new(0, tilt * h * 0.2, 0) * CFrame.Angles(math.rad(80) * tilt, 0, 0)
	elseif kind == "Hop" then
		return CFrame.new(0, s * h * 0.6, 0) * CFrame.Angles(-s * 0.3, 0, 0)
	elseif kind == "HatTip" or kind == "Aim" then
		return CFrame.Angles(s * (if kind == "Aim" then -0.35 else 0.3), 0, 0)
	elseif kind == "Wobble" then
		return CFrame.Angles(0, 0, math.sin(k * math.pi * 6) * 0.25 * (1 - k))
	elseif kind == "Stomp" then
		local up = if k < 0.6 then math.sin(k / 0.6 * math.pi / 2) else 1 - (k - 0.6) / 0.4
		return CFrame.new(0, up * h * 0.12, 0) * CFrame.Angles(-up * 0.25, 0, 0)
	elseif kind == "Spin" or kind == "Zoom" then
		return CFrame.Angles(0, k * math.pi * 2, 0)
	elseif kind == "Float" then
		return CFrame.new(0, s * h * 0.15, 0)
	end
	return CFrame.identity
end

-- baseCF: ground position + facing of the creature this frame
function Animator.update(rig: Rig, baseCF: CFrame, now: number, moving: boolean, speedFactor: number?)
	local h = rig.height
	local t = now + rig.phase
	local off: CFrame
	if moving then
		local f = 9 * (speedFactor or 1)
		local hop = math.abs(math.sin(t * f))
		off = CFrame.new(0, hop * h * 0.08, 0) * CFrame.Angles(-0.06, 0, math.sin(t * f) * 0.09)
	else
		off = CFrame.new(0, math.sin(t * 2.2) * h * 0.015, 0)
			* CFrame.Angles(0, 0, math.sin(t * 1.3) * 0.03)
	end
	if rig.floatHeight > 0 then
		off = CFrame.new(0, rig.floatHeight + math.sin(t * 1.6) * 0.35, 0) * off
	end
	-- attack lunge
	local ak = (now - rig.attackAt) / 0.28
	if ak >= 0 and ak < 1 then
		local s = math.sin(ak * math.pi)
		off = off * CFrame.new(0, s * h * 0.05, -s * math.max(1, h * 0.18)) * CFrame.Angles(-s * 0.25, 0, 0)
	end
	-- hit shake
	local hk = (now - rig.hitAt) / 0.2
	if hk >= 0 and hk < 1 then
		local s = (1 - hk) * 0.25
		off = off * CFrame.new(math.sin(now * 90) * s, 0, s) * CFrame.Angles(0.15 * (1 - hk), 0, 0)
	end
	-- idle quirk
	if rig.quirkKind then
		local len = QUIRK_LENGTH[rig.quirkKind] or 1
		local qk = (now - rig.quirkAt) / len
		if qk >= 1 then
			rig.quirkKind = nil
		else
			off = off * quirkOffset(rig.quirkKind, qk, h)
		end
	end
	local cf = baseCF * off
	rig.root.CFrame = cf
	-- orbiting parts
	if #rig.orbits > 0 then
		for _, p in rig.orbits do
			local r = (p:GetAttribute("Orbit") :: number) * rig.scale
			local a = now * ((p:GetAttribute("OrbitSpeed") :: number?) or 1) + ((p:GetAttribute("OrbitPhase") :: number?) or 0)
			local y = ((p:GetAttribute("OrbitHeight") :: number?) or h * 0.6) * rig.scale
			p.CFrame = cf * CFrame.new(math.cos(a) * r, y, math.sin(a) * r) * CFrame.Angles(0, -a, 0.4)
		end
	end
	-- rainbow mutation: slowly cycle hues (10 Hz is plenty)
	if #rig.rainbow > 0 and now >= rig.nextRainbow then
		rig.nextRainbow = now + 0.1
		for _, p in rig.rainbow do
			local o = p:GetAttribute("RainbowOffset") :: number
			p.Color = Color3.fromHSV((now * 0.25 + o) % 1, 0.7, 1)
		end
	end
end

return Animator
