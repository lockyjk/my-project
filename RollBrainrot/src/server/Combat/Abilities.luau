--!strict
-- Brainrot ability handlers. AbilityConfig rows pick a handler by name and pass `params`;
-- a new mechanic is one function here. Each handler returns true if it cast (cooldown
-- starts) and emits an "ab" event so clients can play the matching VFX (CombatFx).
--
-- `battle` and units are typed `any` here to avoid a require cycle with Battle.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Types = require(Modules.Types)

local Abilities = {}

type Handler = (battle: any, caster: any, ability: Types.AbilityDef) -> boolean

local handlers: { [string]: Handler } = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function power(battle: any, caster: any, mult: number): number
	return caster.atk * mult * battle:attackMult(caster)
end

-- Current target if alive and within `range`, else the nearest enemy within range
local function targetInRange(battle: any, caster: any, range: number): any?
	local t = caster.target
	if t and t.alive and flat(t.pos, caster.pos) <= range + t.radius then
		return t
	end
	local enemies = battle:within(battle:enemiesOf(caster), caster.pos, range)
	local best, bestD = nil, math.huge
	for _, e in enemies do
		local d = flat(e.pos, caster.pos)
		if d < bestD then
			best, bestD = e, d
		end
	end
	return best
end

local function strongestInRange(battle: any, caster: any, range: number): any?
	local best = nil
	for _, e in battle:within(battle:enemiesOf(caster), caster.pos, range) do
		if not best or e.hp > best.hp then
			best = e
		end
	end
	return best
end

local function emit(battle: any, caster: any, ability: Types.AbilityDef, extra: { [string]: any }?)
	local ev: { [string]: any } = { t = "ab", id = caster.id, ab = ability.id }
	if extra then
		for k, v in extra do
			ev[k] = v
		end
	end
	battle:emit(ev)
end

-- Banana Bonk: several quick hits on one target
handlers.MultiHit = function(battle, caster, ability)
	local p = ability.params
	local target = targetInRange(battle, caster, caster.range + 3)
	if not target then
		return false
	end
	emit(battle, caster, ability, { tg = target.id, n = p.hits })
	for i = 0, p.hits - 1 do
		battle:schedule(i * p.interval, function()
			if target.alive and caster.alive then
				battle:damage(caster, target, power(battle, caster, p.damageMult))
			end
		end)
	end
	return true
end

-- Cheese Burst / Gator Missile / Fireball: a lobbed projectile that explodes in an area
handlers.AoEProjectile = function(battle, caster, ability)
	local p = ability.params
	local range = math.max(caster.range * 1.6, 30)
	local target = if p.target == "strongest"
		then strongestInRange(battle, caster, range)
		else targetInRange(battle, caster, range)
	if not target then
		return false
	end
	local point = target.pos
	emit(
		battle,
		caster,
		ability,
		{ x = point.X, z = point.Z, r = p.radius, ft = p.flightTime, tg = target.id, sh = p.shake }
	)
	local amount = power(battle, caster, p.damageMult)
	battle:schedule(p.flightTime, function()
		for _, e in battle:within(battle:enemiesOf(caster), point, p.radius) do
			battle:damage(caster, e, amount)
			if p.burnPct and e.alive then
				battle:addStatus(e, "Burn", p.burnDuration, caster.atk * p.burnPct, nil, caster.id)
			end
		end
	end)
	return true
end

-- Thorn Shield / Taunt: damage reduction + reflection, optionally pulling aggro
handlers.SelfShield = function(battle, caster, ability)
	local p = ability.params
	-- only worth casting when enemies are close
	if #battle:within(battle:enemiesOf(caster), caster.pos, (p.tauntRadius or 20) + 6) == 0 then
		return false
	end
	battle:addStatus(caster, "Shield", p.duration, p.reduction, p.reflect)
	if p.taunt then
		battle:addStatus(caster, "Taunt", p.duration, p.tauntRadius)
		for _, e in battle:within(battle:enemiesOf(caster), caster.pos, p.tauntRadius) do
			if not e.isBoss or math.random() < 0.5 then
				e.target = caster
			end
		end
	end
	emit(battle, caster, ability, { r = p.tauntRadius, dur = p.duration })
	return true
end

-- Sticky Splash / Freeze / Heal: slow + damage enemies in an area, heal friends nearby
handlers.AreaSlowHeal = function(battle, caster, ability)
	local p = ability.params
	local center = caster.pos
	if (p.radius or 0) > 0 then
		local target = targetInRange(battle, caster, math.max(caster.range, 12) + 10)
		if target then
			center = target.pos
		elseif (p.healPct or 0) <= 0 then
			return false
		end
	end
	local hurtFriends = false
	if (p.healPct or 0) > 0 then
		for _, a in battle:within(caster.team, caster.pos, p.healRadius) do
			if a.hp < a.maxHp * 0.9 then
				hurtFriends = true
				break
			end
		end
	end
	local enemies = if (p.radius or 0) > 0 then battle:within(battle:enemiesOf(caster), center, p.radius) else {}
	if #enemies == 0 and not hurtFriends then
		return false
	end
	for _, e in enemies do
		if (p.damageMult or 0) > 0 then
			battle:damage(caster, e, power(battle, caster, p.damageMult))
		end
		if (p.slow or 0) > 0 and e.alive then
			battle:addStatus(e, "Slow", p.slowDuration, p.slow)
		end
	end
	if (p.healPct or 0) > 0 then
		for _, a in battle:within(caster.team, caster.pos, p.healRadius) do
			battle:heal(a, a.maxHp * p.healPct)
		end
	end
	emit(battle, caster, ability, { x = center.X, z = center.Z, r = math.max(p.radius or 0, p.healRadius or 0) })
	return true
end

-- Shark Rush: charge in a line through every enemy on the way
handlers.Dash = function(battle, caster, ability)
	local p = ability.params
	local target = targetInRange(battle, caster, p.distance)
	if not target then
		return false
	end
	local from = caster.pos
	local dir = Vector3.new(target.pos.X - from.X, 0, target.pos.Z - from.Z)
	if dir.Magnitude < 0.1 then
		return false
	end
	dir = dir.Unit
	local to = battle:clampToField(from + dir * p.distance, caster.radius)
	local amount = power(battle, caster, p.damageMult)
	local segment = to - from
	local len = segment.Magnitude
	for _, e in battle:within(battle:enemiesOf(caster), (from + to) / 2, len / 2 + p.width) do
		local rel = e.pos - from
		local along = math.clamp(rel:Dot(dir), 0, len)
		local closest = from + dir * along
		if flat(closest, e.pos) <= p.width / 2 + e.radius then
			battle:damage(caster, e, amount)
		end
	end
	caster.pos = to
	caster.yaw = math.atan2(-dir.X, -dir.Z)
	emit(battle, caster, ability, { x = to.X, z = to.Z, fx = from.X, fz = from.Z })
	return true
end

-- Volcano Stomp: shockwave around the caster (+ burn)
handlers.GroundSlam = function(battle, caster, ability)
	local p = ability.params
	local enemies = battle:within(battle:enemiesOf(caster), caster.pos, p.radius)
	if #enemies == 0 then
		return false
	end
	local amount = power(battle, caster, p.damageMult)
	for _, e in enemies do
		battle:damage(caster, e, amount)
		if p.burnPct and e.alive then
			battle:addStatus(e, "Burn", p.burnDuration, caster.atk * p.burnPct, nil, caster.id)
		end
	end
	emit(battle, caster, ability, { x = caster.pos.X, z = caster.pos.Z, r = p.radius, sh = p.shake })
	return true
end

-- Cosmic Collapse: black hole pulls enemies together, then detonates
handlers.BlackHole = function(battle, caster, ability)
	local p = ability.params
	local target = targetInRange(battle, caster, math.max(caster.range * 1.5, 40))
	if not target then
		return false
	end
	local point = target.pos
	emit(battle, caster, ability, { x = point.X, z = point.Z, r = p.radius, ft = p.pullTime, sh = p.shake })
	local steps = math.max(1, math.floor(p.pullTime / 0.1))
	for i = 1, steps do
		battle:schedule(i * 0.1, function()
			for _, e in battle:within(battle:enemiesOf(caster), point, p.radius) do
				if not e.isBoss then
					local d = Vector3.new(point.X - e.pos.X, 0, point.Z - e.pos.Z)
					if d.Magnitude > 1.5 then
						e.pos += d.Unit * math.min(d.Magnitude - 1, 4)
					end
					battle:addStatus(e, "Pulled", 0.25)
				end
			end
		end)
	end
	local amount = power(battle, caster, p.damageMult)
	battle:schedule(p.pullTime + 0.05, function()
		for _, e in battle:within(battle:enemiesOf(caster), point, p.radius * 0.6) do
			battle:damage(caster, e, amount)
		end
		battle:emit({ t = "fx", n = "CosmicBoom", x = point.X, z = point.Z, r = p.radius * 0.6 })
	end)
	return true
end

-- Chain Lightning: jumps between nearby enemies with damage falloff
handlers.Chain = function(battle, caster, ability)
	local p = ability.params
	local first = targetInRange(battle, caster, math.max(caster.range, 20) + 6)
	if not first then
		return false
	end
	local hit = { [first] = true }
	local chain = { first }
	local current = first
	for _ = 2, p.bounces do
		local nextT, bestD = nil, p.jumpRange
		for _, e in battle:within(battle:enemiesOf(caster), current.pos, p.jumpRange) do
			if not hit[e] then
				local d = flat(e.pos, current.pos)
				if d < bestD then
					nextT, bestD = e, d
				end
			end
		end
		if not nextT then
			break
		end
		hit[nextT] = true
		table.insert(chain, nextT)
		current = nextT
	end
	local ids = {}
	local amount = power(battle, caster, p.damageMult)
	for i, e in chain do
		table.insert(ids, e.id)
		battle:damage(caster, e, amount * p.falloff ^ (i - 1))
	end
	emit(battle, caster, ability, { chain = ids })
	return true
end

Abilities.Handlers = handlers

function Abilities.cast(battle: any, caster: any, ability: Types.AbilityDef): boolean
	local fn = handlers[ability.handler]
	if not fn then
		warn(`[Abilities] no handler {ability.handler} for {ability.id}`)
		return false
	end
	return fn(battle, caster, ability)
end

return Abilities
