--!strict
-- Boss special attacks. Every attack is telegraphed: a "tele" event draws the danger zone
-- on the ground for `windup` seconds, then the attack lands on whatever is still inside.
-- Bosses enrage below MonsterDef.enrageAt (faster windups, shorter cooldowns, +attack speed).
--
-- Shapes: Circle (slam on a target), Ring (shockwave around the boss), Line (charge),
-- Multi (barrage of circles), None (summon minions).

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Registry = require(Modules.Registry)

local BossAttacks = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function nearestAlly(battle: any, boss: any): any?
	local best, bestD = nil, math.huge
	for _, u in battle.units do
		if u.alive and u.team == "ally" then
			local d = flat(u.pos, boss.pos)
			if d < bestD then
				best, bestD = u, d
			end
		end
	end
	return best
end

local function randomAllies(battle: any, n: number): { any }
	local list = {}
	for _, u in battle.units do
		if u.alive and u.team == "ally" then
			table.insert(list, u)
		end
	end
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i]
	end
	return out
end

local function hitAllies(battle: any, boss: any, attack: any, filter: (any) -> boolean)
	local amount = boss.atk * attack.damageMult
	for _, u in battle.units do
		if u.alive and u.team == "ally" and filter(u) then
			battle:damage(boss, u, amount, { playerBase = boss.playerDamageBase * attack.damageMult })
		end
	end
end

local function pickAttack(boss: any, now: number): any?
	local def = boss.monsterDef
	local total = 0
	local ready = {}
	for _, id in def.attacks do
		local a = Registry.BossAttack[id]
		if a and now >= (boss.boss.cooldowns[id] or 0) then
			table.insert(ready, a)
			total += a.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local x = math.random() * total
	for _, a in ready do
		x -= a.weight
		if x <= 0 then
			return a
		end
	end
	return ready[#ready]
end

-- Returns true while the boss is busy with a special (normal AI is skipped)
function BossAttacks.update(battle: any, boss: any): boolean
	local now = battle.now
	local state = boss.boss
	local def = boss.monsterDef
	if not state.enraged and def.enrageAt and boss.hp / boss.maxHp <= def.enrageAt then
		state.enraged = true
		battle:addStatus(boss, "Haste", 9999, 0.35)
		battle:emit({ t = "enrage", id = boss.id })
	end
	if now < state.nextAttack then
		return false
	end
	local target = boss.target
	if not target or not target.alive then
		target = nearestAlly(battle, boss)
		boss.target = target
	end
	if not target then
		return false
	end
	local attack = pickAttack(boss, now)
	if not attack then
		state.nextAttack = now + 1
		return false
	end
	local speedUp = if state.enraged then 0.75 else 1
	local windup = attack.windup * speedUp
	local p = attack.params
	boss.casting = now + windup
	state.cooldowns[attack.id] = now + windup + attack.cooldown * (if state.enraged then 0.7 else 1)
	state.nextAttack = now + windup + (if state.enraged then 1.2 else 2)
	local dir = Vector3.new(target.pos.X - boss.pos.X, 0, target.pos.Z - boss.pos.Z)
	if dir.Magnitude > 0.1 then
		boss.yaw = math.atan2(-dir.X, -dir.Z)
	end
	local base = { t = "tele", id = boss.id, n = attack.name, dur = windup, shape = attack.shape }

	local function finish()
		boss.casting = 0
	end

	if attack.shape == "Circle" then
		local point = target.pos
		local ev = table.clone(base)
		ev.x, ev.z, ev.r = point.X, point.Z, p.radius
		battle:emit(ev)
		battle:schedule(windup, function()
			finish()
			if not boss.alive then
				return
			end
			hitAllies(battle, boss, attack, function(u)
				return flat(u.pos, point) <= p.radius + u.radius
			end)
			battle:emit({ t = "fx", n = "Slam", x = point.X, z = point.Z, r = p.radius })
		end)
	elseif attack.shape == "Ring" then
		local ev = table.clone(base)
		ev.x, ev.z, ev.r = boss.pos.X, boss.pos.Z, p.radius
		battle:emit(ev)
		battle:schedule(windup, function()
			finish()
			if not boss.alive then
				return
			end
			local center = boss.pos
			hitAllies(battle, boss, attack, function(u)
				return flat(u.pos, center) <= p.radius + u.radius
			end)
			battle:emit({ t = "fx", n = "Shockwave", x = center.X, z = center.Z, r = p.radius })
		end)
	elseif attack.shape == "Line" then
		local from = boss.pos
		local unit = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, 1)
		local to = battle:clampToField(from + unit * p.length, boss.radius)
		local len = (to - from).Magnitude
		local ev = table.clone(base)
		ev.x, ev.z, ev.len, ev.w, ev.yaw = from.X, from.Z, len, p.width, boss.yaw
		battle:emit(ev)
		battle:schedule(windup, function()
			finish()
			if not boss.alive then
				return
			end
			hitAllies(battle, boss, attack, function(u)
				local rel = u.pos - from
				local along = math.clamp(rel:Dot(unit), 0, len)
				return flat(from + unit * along, u.pos) <= p.width / 2 + u.radius
			end)
			boss.pos = to
			battle:emit({ t = "fx", n = "Charge", x = to.X, z = to.Z, fx = from.X, fz = from.Z })
		end)
	elseif attack.shape == "Multi" then
		local points = {}
		for _, u in randomAllies(battle, p.count) do
			table.insert(points, u.pos + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)))
		end
		while #points < p.count do
			local a = math.random() * math.pi * 2
			local r = math.random() * p.spread
			table.insert(points, battle:clampToField(target.pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)))
		end
		local xs, zs = {}, {}
		for _, pt in points do
			table.insert(xs, math.floor(pt.X * 10) / 10)
			table.insert(zs, math.floor(pt.Z * 10) / 10)
		end
		local ev = table.clone(base)
		ev.xs, ev.zs, ev.r = xs, zs, p.radius
		battle:emit(ev)
		battle:schedule(windup, function()
			finish()
			if not boss.alive then
				return
			end
			for _, pt in points do
				hitAllies(battle, boss, attack, function(u)
					return flat(u.pos, pt) <= p.radius + u.radius
				end)
				battle:emit({ t = "fx", n = "Meteor", x = pt.X, z = pt.Z, r = p.radius })
			end
		end)
	else -- Summon
		battle:emit(base)
		battle:schedule(windup, function()
			finish()
			if not boss.alive or not battle.spawnFn then
				return
			end
			for i = 1, p.count do
				local a = i / p.count * math.pi * 2
				local pos = boss.pos + Vector3.new(math.cos(a), 0, math.sin(a)) * (boss.radius + 8)
				battle.spawnFn(p.monster, pos)
			end
			battle:emit({ t = "fx", n = "Summon", x = boss.pos.X, z = boss.pos.Z, r = boss.radius + 10 })
		end)
	end
	return true
end

return BossAttacks
