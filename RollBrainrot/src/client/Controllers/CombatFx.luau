--!strict
-- Battle visual effects driven by server events:
--   * basic attack projectiles and melee sparks
--   * Brainrot abilities (AbilityConfig `vfx`): Bonk, PizzaBomb, Missile, ThornShield,
--     Splash, Rush, LavaSlam, BlackHole, Fireball, Frost, Lightning, Heal
--   * boss telegraphs (red danger zones that fill up before an attack lands)
--   * named impacts (Slam, Shockwave, Charge, Meteor, Summon, Ultimate, strikes, …)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))

local Effects = require(script.Parent.Effects)
local UnitRenderer = require(script.Parent.UnitRenderer)

local CombatFx = {}

local rgb = Color3.fromRGB
local DANGER = rgb(255, 40, 40)

local function cam(): Camera
	return Workspace.CurrentCamera :: Camera
end

-- Shake that fades with distance from the camera
local function shakeAt(pos: Vector3, amount: number, duration: number?)
	local d = (cam().CFrame.Position - pos).Magnitude
	local k = math.clamp(1 - d / 260, 0, 1)
	if k > 0 then
		Effects.shake(amount * k, duration or 0.4)
	end
end

local function ground(battleId: number, x: number, z: number): Vector3
	local c = UnitRenderer.center(battleId)
	return Vector3.new(x, if c then c.Y else 0, z)
end

-------------------------------------------------------------------------------
-- Telegraphs
-------------------------------------------------------------------------------
local function disc(pos: Vector3, radius: number, color: Color3, transparency: number, y: number): Part
	local p = Effects.part(
		Enum.PartType.Cylinder,
		Vector3.new(0.3, radius * 2, radius * 2),
		CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	p.Transparency = transparency
	return p
end

local function circleTelegraph(pos: Vector3, radius: number, dur: number)
	local outline = disc(pos, radius, DANGER, 0.55, 0.25)
	local fill = disc(pos, 0.5, rgb(255, 120, 60), 0.35, 0.3)
	TweenService
		:Create(fill, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = Vector3.new(0.3, radius * 2, radius * 2) })
		:Play()
	-- pulsing outline
	TweenService:Create(
		outline,
		TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.8 }
	):Play()
	Debris:AddItem(outline, dur + 0.05)
	Debris:AddItem(fill, dur + 0.05)
end

local function lineTelegraph(from: Vector3, yaw: number, len: number, width: number, dur: number)
	local dir = CFrame.Angles(0, yaw, 0).LookVector
	local base = CFrame.lookAt(from, from + dir)
	local outline =
		Effects.part(Enum.PartType.Block, Vector3.new(width, 0.3, len), base * CFrame.new(0, 0.25, -len / 2), DANGER)
	outline.Transparency = 0.55
	local fill = Effects.part(
		Enum.PartType.Block,
		Vector3.new(width, 0.32, 0.5),
		base * CFrame.new(0, 0.3, -0.25),
		rgb(255, 120, 60)
	)
	fill.Transparency = 0.35
	TweenService:Create(
		fill,
		TweenInfo.new(dur, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(width, 0.32, len), CFrame = base * CFrame.new(0, 0.3, -len / 2) }
	):Play()
	Debris:AddItem(outline, dur + 0.05)
	Debris:AddItem(fill, dur + 0.05)
end

local function onTelegraph(battleId: number, ev: { [string]: any })
	local boss = UnitRenderer.get(battleId, ev.id)
	if boss then
		Effects.floatText(boss.pos + Vector3.new(0, boss.height + 6, 0), `⚠️ {ev.n}!`, Theme.Colors.Bad, 16, 6)
	end
	local dur = ev.dur or 1
	if ev.shape == "Circle" or ev.shape == "Ring" then
		circleTelegraph(ground(battleId, ev.x, ev.z), ev.r, dur)
	elseif ev.shape == "Line" then
		lineTelegraph(ground(battleId, ev.x, ev.z), ev.yaw or 0, ev.len, ev.w, dur)
	elseif ev.shape == "Multi" and ev.xs then
		for i, x in ev.xs do
			circleTelegraph(ground(battleId, x, ev.zs[i]), ev.r, dur)
		end
	elseif boss then
		Effects.ring(boss.pos, boss.height, rgb(170, 80, 255), dur, 2)
	end
	Effects.sound("Whoosh", 0.5, if boss then boss.pos else nil, 0.7)
end

-------------------------------------------------------------------------------
-- Falling rock from the sky (meteors, ultimate)
-------------------------------------------------------------------------------
local function meteor(target: Vector3, size: number, flight: number, color: Color3, onImpact: () -> ())
	local from = target + Vector3.new(-30, 160, -20)
	Effects.projectile(from, target, flight, color, size, 0, onImpact)
end

-------------------------------------------------------------------------------
-- Abilities
-------------------------------------------------------------------------------
local function onAbility(battleId: number, ev: { [string]: any })
	local ability = Registry.Ability[ev.ab]
	local caster = UnitRenderer.get(battleId, ev.id)
	if not ability or not caster then
		return
	end
	local vfx = ability.vfx
	local color = ability.color
	local origin = caster.pos + Vector3.new(0, caster.height * 0.6, 0)
	local target = if ev.x then ground(battleId, ev.x, ev.z) else nil
	local tgView = if ev.tg then UnitRenderer.get(battleId, ev.tg) else nil
	if not Effects.near(caster.pos, 600) then
		return
	end
	-- ability name pops above the caster
	Effects.floatText(caster.pos + Vector3.new(0, caster.height + 3, 0), ability.name:upper() .. "!", color, 7, 4)
	if vfx == "Bonk" and tgView then
		for i = 0, (ev.n or 3) - 1 do
			task.delay(i * 0.15, function()
				Effects.burst(tgView.pos + Vector3.new(0, tgView.height * 0.6, 0), color, 10, "sparkle", 18, 1)
				Effects.sound("Hit", 0.35, tgView.pos, 1.2 + i * 0.1)
			end)
		end
	elseif (vfx == "PizzaBomb" or vfx == "Missile" or vfx == "Fireball") and target then
		local big = vfx == "Missile"
		Effects.sound("Swing", 0.4, caster.pos)
		Effects.projectile(
			origin,
			target + Vector3.new(0, 1, 0),
			ev.ft or 0.5,
			color,
			if big then 2.6 else 1.6,
			if big then 22 else 10,
			function()
				Effects.blast(target, ev.r or 10, color, 0.4)
				Effects.ring(target, (ev.r or 10) * 1.2, color, 0.5)
				Effects.burst(target + Vector3.new(0, 2, 0), color, 30, "fire", 25, 2)
				Effects.sound("Explosion", 0.5, target)
				if ev.sh then
					shakeAt(target, ev.sh * 2)
				end
			end,
			if big then Enum.PartType.Cylinder else Enum.PartType.Ball
		)
	elseif vfx == "ThornShield" then
		Effects.ring(caster.pos, ev.r or 20, color, 0.5)
		Effects.burst(origin, rgb(240, 255, 200), 24, "sparkle", 20, 0.8)
	elseif (vfx == "Splash" or vfx == "Frost" or vfx == "Heal") and target then
		Effects.ring(target, ev.r or 20, color, 0.6)
		Effects.burst(target + Vector3.new(0, 1, 0), color, 30, "sparkle", 22, 1.6)
		if vfx == "Heal" or vfx == "Splash" then
			Effects.ring(caster.pos, 14, Theme.Colors.Good, 0.5)
		end
	elseif vfx == "Rush" and target then
		local from = ground(battleId, ev.fx, ev.fz) + Vector3.new(0, caster.height * 0.5, 0)
		local to = target + Vector3.new(0, caster.height * 0.5, 0)
		local streak = Effects.part(
			Enum.PartType.Block,
			Vector3.new(4, 2, (to - from).Magnitude),
			CFrame.lookAt((from + to) / 2, to),
			color
		)
		streak.Transparency = 0.3
		TweenService
			:Create(
				streak,
				TweenInfo.new(0.4),
				{ Transparency = 1, Size = Vector3.new(0.5, 0.5, (to - from).Magnitude) }
			)
			:Play()
		Debris:AddItem(streak, 0.45)
		Effects.burst(to, color, 30, "sparkle", 30, 1.5)
		Effects.sound("Whoosh", 0.6, to)
	elseif vfx == "LavaSlam" then
		local p = target or caster.pos
		Effects.ring(p, ev.r or 30, color, 0.6)
		Effects.ring(p, (ev.r or 30) * 0.7, rgb(255, 200, 80), 0.45)
		Effects.burst(p + Vector3.new(0, 2, 0), color, 50, "fire", 35, 3)
		Effects.sound("Explosion", 0.6, p, 0.7)
		shakeAt(p, (ev.sh or 0.8) * 2)
	elseif vfx == "BlackHole" and target then
		local hole =
			Effects.part(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(target + Vector3.new(0, 4, 0)), rgb(20, 0, 40))
		hole.Material = Enum.Material.SmoothPlastic
		local halo = Effects.part(
			Enum.PartType.Cylinder,
			Vector3.new(0.3, 4, 4),
			CFrame.new(target + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color
		)
		halo.Transparency = 0.3
		local ft = ev.ft or 1.6
		TweenService
			:Create(hole, TweenInfo.new(ft, Enum.EasingStyle.Quad), { Size = Vector3.one * (ev.r or 40) * 0.35 })
			:Play()
		TweenService:Create(
			halo,
			TweenInfo.new(ft, Enum.EasingStyle.Quad),
			{ Size = Vector3.new(0.3, (ev.r or 40) * 0.9, (ev.r or 40) * 0.9) }
		):Play()
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < ft and halo.Parent do
				halo.CFrame *= CFrame.Angles(0.15, 0, 0)
				Effects.burst(
					target + Vector3.new(math.random(-20, 20), 3, math.random(-20, 20)),
					color,
					2,
					"sparkle",
					4,
					1.2
				)
				task.wait(0.05)
			end
		end)
		Debris:AddItem(hole, ft + 0.1)
		Debris:AddItem(halo, ft + 0.1)
		Effects.sound("Whoosh", 0.7, target, 0.5)
	elseif vfx == "Lightning" and ev.chain then
		local prev = origin
		for _, id in ev.chain do
			local v = UnitRenderer.get(battleId, id)
			if v then
				local p = v.pos + Vector3.new(0, v.height * 0.5, 0)
				Effects.bolt(prev, p, color, 0.6, 0.3)
				prev = p
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Named impacts
-------------------------------------------------------------------------------
local function onFx(battleId: number, ev: { [string]: any })
	local p = ground(battleId, ev.x or 0, ev.z or 0)
	local r = ev.r or 10
	local n = ev.n
	if not Effects.near(p, 700) then
		return
	end
	if n == "Slam" then
		Effects.blast(p, r * 0.6, rgb(200, 160, 110), 0.35)
		Effects.ring(p, r * 1.3, rgb(255, 200, 140), 0.5)
		Effects.burst(p + Vector3.new(0, 2, 0), rgb(150, 120, 90), 40, "smoke", 30, 4)
		Effects.sound("Explosion", 0.7, p, 0.6)
		shakeAt(p, 2.2, 0.5)
	elseif n == "Shockwave" then
		Effects.ring(p, r, rgb(255, 90, 60), 0.7, 6)
		Effects.ring(p, r * 0.75, rgb(255, 220, 160), 0.55, 6)
		Effects.sound("Explosion", 0.7, p, 0.5)
		shakeAt(p, 2.6, 0.6)
	elseif n == "Charge" then
		local from = ground(battleId, ev.fx, ev.fz)
		for i = 0, 8 do
			Effects.burst(from:Lerp(p, i / 8) + Vector3.new(0, 2, 0), rgb(160, 130, 100), 6, "smoke", 12, 4)
		end
		shakeAt(p, 1.6)
	elseif n == "Meteor" then
		meteor(p, 5, 0.25, rgb(255, 120, 40), function()
			Effects.blast(p, r, rgb(255, 120, 40), 0.35)
			Effects.burst(p + Vector3.new(0, 2, 0), rgb(255, 160, 60), 25, "fire", 25, 3)
			Effects.sound("Explosion", 0.5, p)
			shakeAt(p, 1)
		end)
	elseif n == "MeteorStrike" then
		meteor(p, 7, 0.8, rgb(255, 100, 30), function()
			Effects.blast(p, r * 1.2, rgb(255, 120, 40), 0.4)
			Effects.ring(p, r * 1.5, rgb(255, 180, 80), 0.6)
			Effects.burst(p + Vector3.new(0, 2, 0), rgb(255, 140, 40), 40, "fire", 35, 4)
			Effects.sound("Explosion", 0.8, p, 0.8)
			shakeAt(p, 1.4)
		end)
	elseif n == "Lightning" then
		Effects.bolt(p + Vector3.new(math.random(-20, 20), 180, math.random(-20, 20)), p, rgb(200, 230, 255), 1.4, 0.35)
		Effects.blast(p, r * 0.7, rgb(190, 220, 255), 0.25)
		Effects.flash(rgb(220, 235, 255), 0.25, 0.25)
		Effects.sound("Explosion", 0.6, p, 1.6)
	elseif n == "Summon" then
		Effects.ring(p, r, rgb(170, 80, 255), 0.6)
		Effects.burst(p + Vector3.new(0, 3, 0), rgb(170, 80, 255), 40, "smoke", 20, 4)
	elseif n == "CosmicBoom" then
		Effects.blast(p, r, rgb(190, 110, 255), 0.5)
		Effects.ring(p, r * 1.6, rgb(120, 230, 255), 0.7, 4)
		Effects.burst(p + Vector3.new(0, 4, 0), rgb(255, 255, 255), 80, "sparkle", 50, 3)
		Effects.sound("Explosion", 0.9, p, 0.5)
		shakeAt(p, 2.4, 0.7)
	elseif n == "TrainerHeal" then
		Effects.ring(p, r, Theme.Colors.Good, 0.6)
		Effects.burst(p + Vector3.new(0, 3, 0), Theme.Colors.Good, 40, "sparkle", 20, 1.5)
	elseif n == "Rally" then
		Effects.ring(p, r, Theme.Colors.Warn, 0.6)
		Effects.burst(p + Vector3.new(0, 4, 0), Theme.Colors.Warn, 30, "sparkle", 25, 1.5)
	elseif n == "Ultimate" then
		circleTelegraph(p, r, 0.9)
		meteor(p, 12, 0.9, rgb(255, 110, 200), function()
			Effects.blast(p, r, rgb(255, 120, 220), 0.5)
			Effects.ring(p, r * 1.6, rgb(255, 220, 120), 0.8, 6)
			Effects.burst(p + Vector3.new(0, 4, 0), rgb(255, 200, 255), 100, "sparkle", 60, 4)
			Effects.flash(rgb(255, 200, 240), 0.45, 0.4)
			Effects.sound("Explosion", 1, p, 0.6)
			shakeAt(p, 3, 0.8)
		end)
	end
end

-------------------------------------------------------------------------------
local function onAttack(battleId: number, ev: { [string]: any })
	local a = UnitRenderer.get(battleId, ev.id)
	local t = UnitRenderer.get(battleId, ev.tg)
	if not a or not t or not Effects.near(a.pos, 300) then
		return
	end
	local from = a.pos + Vector3.new(0, a.height * 0.6, 0)
	local to = t.pos + Vector3.new(0, t.height * 0.5, 0)
	if ev.p then
		local color = if a.kind == "monster" then rgb(160, 255, 80) else Registry.rarityOf(a.defId).color
		local flight = math.clamp((to - from).Magnitude / 80, 0.15, 0.5)
		Effects.projectile(from, to, flight, color, 0.9, 3, function()
			Effects.burst(to, color, 6, "sparkle", 10, 0.8)
		end)
	else
		Effects.burst(
			to,
			if a.team == "enemy" then rgb(255, 120, 120) else rgb(255, 255, 200),
			5,
			"sparkle",
			12,
			if t.isBoss then 2 else 0.8
		)
		if math.random() < 0.3 then
			Effects.sound("Hit", 0.25, to, 0.9 + math.random() * 0.4)
		end
	end
end

function CombatFx.start()
	local myId = Players.LocalPlayer.UserId
	UnitRenderer.Event:Connect(function(battleId: number, ev: { [string]: any })
		local t = ev.t
		local ok, err = (pcall :: any)(function()
			if t == "tele" then
				onTelegraph(battleId, ev)
			elseif t == "ab" then
				onAbility(battleId, ev)
			elseif t == "fx" then
				onFx(battleId, ev)
			elseif t == "atk" then
				onAttack(battleId, ev)
			elseif t == "enrage" then
				local v = UnitRenderer.get(battleId, ev.id)
				if v then
					Effects.floatText(v.pos + Vector3.new(0, v.height + 8, 0), "😡 ENRAGED!", Theme.Colors.Bad, 20, 8)
					Effects.flash(rgb(255, 40, 40), 0.3, 0.6)
					shakeAt(v.pos, 1.5)
				end
			elseif t == "patk" then
				if ev.o == myId then
					Effects.sound("Swing", 0.4)
				end
			elseif t == "dodge" and ev.o == myId then
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					Effects.floatText(root.Position + Vector3.new(0, 4, 0), "DODGED!", Theme.Colors.Secondary, 6, 4)
				end
			end
		end)
		if not ok then
			warn(`[CombatFx] {t}: {err}`)
		end
	end)
end

return CombatFx
