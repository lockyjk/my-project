--!strict
-- A Battle is one fight in one place (the stadium run, or a Giant Invasion in the hub).
-- It owns every unit in that fight and simulates them at GameConfig.Combat.TickRate:
--
--   statuses → player positions → AI (target, move, attack, ability, boss patterns)
--   → separation (spatial hash) → bounds → scheduled actions
--
-- There are no physics or models on the server: units are plain tables with a position.
-- Clients render them from the events/snapshots CombatService sends (see UnitRenderer).
--
-- Damage formula (scale-free, so it works from tier 1 to tier 6):
--   damage = attack² / (attack + defense) × multipliers   (crit: × CritMult)

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local GameConfig = require(Modules.GameConfig)
local Registry = require(Modules.Registry)
local Signal = require(Modules.Signal)
local Types = require(Modules.Types)
local Abilities = require(script.Parent.Abilities)
local BossAttacks = require(script.Parent.BossAttacks)

local Battle = {}
Battle.__index = Battle

local CFG = GameConfig.Combat

export type Status = { untilT: number, value: number?, value2: number?, source: number? }

export type Unit = {
	id: number,
	team: "ally" | "enemy",
	kind: "brainrot" | "monster" | "player",
	defId: string,
	mut: string,
	owner: Player?,
	uid: string?,
	pos: Vector3,
	yaw: number,
	radius: number,
	height: number,
	maxHp: number,
	hp: number,
	atk: number,
	def: number,
	speed: number,
	range: number,
	cooldown: number,
	nextAttack: number,
	ability: Types.AbilityDef?,
	nextAbility: number,
	passive: Types.PassiveDef?,
	projectile: boolean,
	statuses: { [string]: Status },
	target: Unit?,
	alive: boolean,
	respawnAt: number,
	isBoss: boolean,
	invulnerableUntil: number,
	moving: boolean,
	casting: number, -- boss windup ends at this time (0 = not casting)
	boss: { nextAttack: number, cooldowns: { [string]: number }, enraged: boolean }?,
	playerDamageBase: number, -- unscaled attack used against player characters
	monsterDef: Types.MonsterDef?,
	scale: number,
	lastHitBy: number?,
	introTarget: Vector3?, -- bosses walk here (fast, invulnerable) during their entrance
}

export type Participant = {
	player: Player,
	unitIds: { number },
	playerUnit: Unit?,
	charge: number,
	cooldowns: { [string]: number },
	rallyUntil: number,
	iframesUntil: number,
	damage: number,
	totals: { [string]: number },
	drops: { string },
}

export type Event = { [string]: any }

export type BattleT = typeof(setmetatable(
	{} :: {
		id: number,
		kind: string,
		center: Vector3,
		radius: number,
		floorY: number,
		units: { [number]: Unit },
		participants: { [Player]: Participant },
		events: { Event },
		scheduled: { { at: number, fn: () -> () } },
		nextUnitId: number,
		active: boolean,
		now: number,
		statMult: number,
		rewardMult: number,
		auraUnits: { Unit },
		UnitDied: Signal.Signal<Unit, Unit?>,
		spawnFn: ((string, Vector3) -> Unit?)?,
		meta: { [string]: any },
	},
	Battle
))

function Battle.new(id: number, kind: string, center: Vector3, radius: number): BattleT
	local self = setmetatable({
		id = id,
		kind = kind,
		center = center,
		radius = radius,
		floorY = center.Y,
		units = {},
		participants = {},
		events = {},
		scheduled = {},
		nextUnitId = 1,
		active = true,
		now = os.clock(),
		statMult = 1,
		rewardMult = 1,
		auraUnits = {},
		UnitDied = Signal.new(),
		spawnFn = nil,
		meta = {},
	}, Battle)
	return self
end

-------------------------------------------------------------------------------
-- Events (flushed to clients by CombatService every tick)
-------------------------------------------------------------------------------
function Battle.emit(self: BattleT, ev: Event)
	table.insert(self.events, ev)
end

function Battle.schedule(self: BattleT, delay: number, fn: () -> ())
	table.insert(self.scheduled, { at = self.now + delay, fn = fn })
end

local function round(n: number): number
	return math.floor(n + 0.5)
end

function Battle.spawnEvent(_self: BattleT, u: Unit): Event
	return {
		t = "spawn",
		id = u.id,
		k = u.kind,
		d = u.defId,
		m = u.mut,
		team = u.team,
		x = u.pos.X,
		z = u.pos.Z,
		hp = round(u.hp),
		mhp = round(u.maxHp),
		o = if u.owner then u.owner.UserId else 0,
		boss = u.isBoss,
		alive = u.alive,
	}
end

-------------------------------------------------------------------------------
-- Units
-------------------------------------------------------------------------------
local function baseUnit(self: BattleT): Unit
	local id = self.nextUnitId
	self.nextUnitId += 1
	return {
		id = id,
		team = "ally",
		kind = "brainrot",
		defId = "",
		mut = "Normal",
		owner = nil,
		uid = nil,
		pos = self.center,
		yaw = 0,
		radius = 2,
		height = 4,
		maxHp = 100,
		hp = 100,
		atk = 10,
		def = 0,
		speed = 14,
		range = 4,
		cooldown = 1,
		nextAttack = 0,
		ability = nil,
		nextAbility = 0,
		passive = nil,
		projectile = false,
		statuses = {},
		target = nil,
		alive = true,
		respawnAt = 0,
		isBoss = false,
		invulnerableUntil = 0,
		moving = false,
		casting = 0,
		boss = nil,
		playerDamageBase = 0,
		monsterDef = nil,
		scale = 1,
		lastHitBy = nil,
		introTarget = nil,
	}
end

function Battle.clampToField(self: BattleT, p: Vector3, margin: number?): Vector3
	local flat = Vector3.new(p.X - self.center.X, 0, p.Z - self.center.Z)
	local maxR = self.radius - (margin or 3)
	if flat.Magnitude > maxR then
		flat = flat.Unit * maxR
	end
	return Vector3.new(self.center.X + flat.X, self.floorY, self.center.Z + flat.Z)
end

-- Where the next monster should appear: 70–120 studs from the fighters (their centroid),
-- mostly on the far side from the entrance tunnel, inside the field. Spawning near the
-- action keeps waves snappy on a 1,000-stud battlefield.
function Battle.spawnPoint(self: BattleT): Vector3
	local sum, n = Vector3.zero, 0
	for _, u in self.units do
		if u.alive and u.team == "ally" then
			sum += u.pos
			n += 1
		end
	end
	local focus = if n > 0 then sum / n else self.center
	local a = math.pi + (math.random() - 0.5) * math.pi * 1.5 -- angle 0 = south (tunnel side)
	local r = 70 + math.random() * 50
	return self:clampToField(focus + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r), 8)
end

function Battle.addBrainrot(
	self: BattleT,
	owner: Player,
	uid: string,
	inst: Types.BrainrotInstance,
	pos: Vector3
): Unit?
	local def = Registry.Brainrot[inst.id]
	if not def then
		return nil
	end
	local stats = BrainrotMath.stats(def, inst.mut, inst.lvl)
	local u = baseUnit(self)
	u.team = "ally"
	u.kind = "brainrot"
	u.defId = inst.id
	u.mut = inst.mut
	u.owner = owner
	u.uid = uid
	u.pos = self:clampToField(pos)
	u.radius = CFG.BrainrotRadius * (if def.rarity == "Mythic" or def.rarity == "Secret" then 1.4 else 1)
	u.maxHp = stats.hp
	u.hp = stats.hp
	u.atk = stats.attack
	u.def = stats.defense
	u.speed = stats.speed
	u.range = stats.range
	u.cooldown = stats.cooldown
	u.ability = Registry.Ability[def.ability]
	u.nextAbility = self.now + 2 + math.random() * 2
	u.passive = if def.passive then Registry.Passive[def.passive] else nil
	u.projectile = stats.range > 10
	self.units[u.id] = u
	self:emit(self:spawnEvent(u))
	return u
end

-- Monster stats are multiplied by `scale` (arena × wave × world event)
function Battle.addMonster(self: BattleT, defId: string, pos: Vector3, scale: number, playerMult: number): Unit?
	local def = Registry.Monster[defId]
	if not def then
		return nil
	end
	local u = baseUnit(self)
	u.team = "enemy"
	u.kind = "monster"
	u.defId = defId
	u.monsterDef = def
	u.pos = self:clampToField(pos, def.radius)
	u.radius = def.radius
	u.height = def.height
	u.maxHp = math.floor(def.hp * scale)
	u.hp = u.maxHp
	u.atk = def.attack * scale
	u.def = def.defense * scale
	u.speed = def.speed
	u.range = def.range
	u.cooldown = def.cooldown
	u.projectile = def.projectile == true
	u.scale = scale
	u.playerDamageBase = def.attack * playerMult
	u.isBoss = def.kind == "Boss" or def.kind == "MiniBoss"
	u.nextAttack = self.now + 0.5 + math.random()
	if def.attacks then
		u.boss = { nextAttack = self.now + 3, cooldowns = {}, enraged = false }
	end
	self.units[u.id] = u
	self:emit(self:spawnEvent(u))
	return u
end

function Battle.addPlayerUnit(self: BattleT, player: Player, maxHp: number, atk: number): Unit
	local u = baseUnit(self)
	u.team = "ally"
	u.kind = "player"
	u.defId = "Player"
	u.owner = player
	u.radius = CFG.PlayerHitboxRadius
	u.maxHp = maxHp
	u.hp = maxHp
	u.atk = atk
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		u.pos = Vector3.new(root.Position.X, self.floorY, root.Position.Z)
	end
	self.units[u.id] = u
	-- not emitted: the client already renders the player's own character
	return u
end

function Battle.removeUnit(self: BattleT, u: Unit)
	if self.units[u.id] then
		self.units[u.id] = nil
		u.alive = false
		if u.kind ~= "player" then
			self:emit({ t = "despawn", id = u.id })
		end
	end
end

function Battle.enemiesOf(_self: BattleT, u: Unit): "ally" | "enemy"
	return if u.team == "ally" then "enemy" else "ally"
end

-- Units of `team` within radius of a point (alive only)
function Battle.within(self: BattleT, team: string, point: Vector3, radius: number): { Unit }
	local out = {}
	for _, u in self.units do
		if u.alive and u.team == team then
			local d = Vector3.new(u.pos.X - point.X, 0, u.pos.Z - point.Z).Magnitude
			if d <= radius + u.radius then
				table.insert(out, u)
			end
		end
	end
	return out
end

function Battle.aliveCount(self: BattleT, team: string): number
	local n = 0
	for _, u in self.units do
		if u.alive and u.team == team then
			n += 1
		end
	end
	return n
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
Battle.flatDist = flatDist

-------------------------------------------------------------------------------
-- Statuses
-------------------------------------------------------------------------------
function Battle.addStatus(
	self: BattleT,
	u: Unit,
	name: string,
	duration: number,
	value: number?,
	value2: number?,
	source: number?
)
	if u.passive and u.passive.params.immune and table.find(u.passive.params.immune, name) then
		return
	end
	local had = u.statuses[name] ~= nil
	u.statuses[name] = { untilT = self.now + duration, value = value, value2 = value2, source = source }
	if not had then
		self:emit({ t = "status", id = u.id, s = name, on = true })
	end
end

local function statusValue(u: Unit, name: string): number?
	local s = u.statuses[name]
	return s and s.value
end

-------------------------------------------------------------------------------
-- Damage / healing / death
-------------------------------------------------------------------------------
export type DamageOpts = { crit: boolean?, noReflect: boolean?, fixed: boolean?, kind: string?, playerBase: number? }

function Battle.damage(self: BattleT, source: Unit?, target: Unit, amount: number, opts: DamageOpts?)
	if not target.alive or self.now < target.invulnerableUntil then
		return
	end
	local o: DamageOpts = opts or {}
	local dmg = amount
	if not o.fixed then
		dmg = amount * amount / math.max(1e-6, amount + target.def)
	end
	local crit = o.crit
	if crit == nil and source and source.team == "ally" then
		crit = math.random() < CFG.CritChance
	end
	if crit then
		dmg *= CFG.CritMult
	end
	local shield = target.statuses.Shield
	if shield then
		dmg *= 1 - (shield.value or 0)
		if source and not o.noReflect and (shield.value2 or 0) > 0 and source.alive then
			self:damage(target, source, dmg * (shield.value2 or 0), { fixed = true, noReflect = true, crit = false })
		end
	end
	if target.kind == "player" then
		-- players take damage from the monster's unscaled attack (see MonsterConfig notes)
		local participant = target.owner and self.participants[target.owner]
		if participant and self.now < participant.iframesUntil then
			self:emit({ t = "dodge", id = target.id, o = if target.owner then target.owner.UserId else 0 })
			return
		end
		local base = o.playerBase or (if source then source.playerDamageBase else 0)
		dmg = base * CFG.MonsterAttackPlayerMult * (if crit then CFG.CritMult else 1)
		local char = target.owner and target.owner.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum:TakeDamage(dmg)
			target.hp = hum.Health
		end
		return
	end
	dmg = math.max(1, dmg)
	target.hp -= dmg
	target.lastHitBy = if source then source.id else nil
	if source and source.owner and source.team == "ally" then
		local p = self.participants[source.owner]
		if p then
			p.damage += dmg
			p.charge =
				math.min(GameConfig.PlayerAbilities.Ultimate.chargeNeeded, p.charge + GameConfig.UltimateChargePerHit)
		end
	end
	self:emit({
		t = "hit",
		id = target.id,
		a = round(dmg),
		c = crit or nil,
		hp = math.max(0, round(target.hp)),
		s = if source then source.id else nil,
	})
	if target.hp <= 0 then
		self:kill(target, source)
	end
end

function Battle.heal(self: BattleT, target: Unit, amount: number)
	if not target.alive or target.kind == "player" then
		return
	end
	local before = target.hp
	target.hp = math.min(target.maxHp, target.hp + amount)
	local healed = target.hp - before
	if healed > 0 then
		self:emit({ t = "heal", id = target.id, a = round(healed), hp = round(target.hp) })
	end
end

function Battle.kill(self: BattleT, u: Unit, killer: Unit?)
	if not u.alive then
		return
	end
	u.alive = false
	u.hp = 0
	u.target = nil
	u.casting = 0
	table.clear(u.statuses)
	self:emit({ t = "die", id = u.id })
	if u.kind == "brainrot" then
		u.respawnAt = self.now + CFG.BrainrotRespawnSeconds
	elseif u.kind == "monster" then
		if killer and killer.owner then
			local p = self.participants[killer.owner]
			if p then
				p.charge = math.min(
					GameConfig.PlayerAbilities.Ultimate.chargeNeeded,
					p.charge + GameConfig.UltimateChargePerKill
				)
			end
		end
		-- keep the corpse for the death animation, then remove
		self:schedule(1.2, function()
			if self.units[u.id] == u then
				self:removeUnit(u)
			end
		end)
	end
	self.UnitDied:Fire(u, killer)
end

function Battle.revive(self: BattleT, u: Unit, pos: Vector3, hpFrac: number)
	u.alive = true
	u.hp = u.maxHp * hpFrac
	u.pos = self:clampToField(pos)
	u.respawnAt = 0
	u.nextAttack = self.now + 0.5
	self:emit({ t = "revive", id = u.id, hp = round(u.hp), x = u.pos.X, z = u.pos.Z })
end

-------------------------------------------------------------------------------
-- AI
-------------------------------------------------------------------------------
local function attackCooldown(self: BattleT, u: Unit): number
	local cd = u.cooldown
	-- Cosmic Aura and similar passives
	if u.team == "ally" then
		for _, aura in self.auraUnits do
			if aura ~= u and aura.alive and aura.passive then
				local r = aura.passive.params.radius or 30
				if flatDist(aura.pos, u.pos) <= r then
					cd /= 1 + (aura.passive.params.attackSpeed or 0)
					break
				end
			end
		end
	end
	local haste = statusValue(u, "Haste")
	if haste then
		cd /= 1 + haste
	end
	return cd
end

function Battle.attackMult(self: BattleT, u: Unit): number
	local m = 1
	if u.owner and u.team == "ally" then
		local p = self.participants[u.owner]
		if p and self.now < p.rallyUntil then
			m *= GameConfig.PlayerAbilities.Rally.attackMult
		end
	end
	return m
end

local function pickTarget(self: BattleT, u: Unit): Unit?
	local enemyTeam = self:enemiesOf(u)
	-- taunt: the nearest taunting enemy within its taunt radius wins
	if u.team == "enemy" then
		for _, other in self.units do
			local taunt = other.statuses.Taunt
			if
				taunt
				and other.alive
				and other.team == enemyTeam
				and flatDist(other.pos, u.pos) <= (taunt.value or 25)
			then
				return other
			end
		end
	end
	local best, bestD = nil, CFG.AggroRange
	for _, other in self.units do
		if other.alive and other.team == enemyTeam then
			local d = flatDist(other.pos, u.pos) - other.radius
			-- monsters prefer brainrots slightly over players so players feel protected
			if u.team == "enemy" and other.kind == "player" then
				d += 6
			end
			if d < bestD then
				best, bestD = other, d
			end
		end
	end
	return best
end

local function moveToward(self: BattleT, u: Unit, goal: Vector3, stopAt: number, dt: number)
	local delta = Vector3.new(goal.X - u.pos.X, 0, goal.Z - u.pos.Z)
	local d = delta.Magnitude
	if d <= stopAt or d < 1e-3 then
		u.moving = false
		return
	end
	local slow = statusValue(u, "Slow") or 0
	local step = math.min(d - stopAt, u.speed * (1 - slow) * dt)
	u.pos += delta.Unit * step
	u.yaw = math.atan2(-delta.X, -delta.Z)
	u.moving = true
end

local function face(u: Unit, p: Vector3)
	local d = Vector3.new(p.X - u.pos.X, 0, p.Z - u.pos.Z)
	if d.Magnitude > 0.01 then
		u.yaw = math.atan2(-d.X, -d.Z)
	end
end

local function basicAttack(self: BattleT, u: Unit, target: Unit)
	u.nextAttack = self.now + attackCooldown(self, u)
	face(u, target.pos)
	self:emit({ t = "atk", id = u.id, tg = target.id, p = u.projectile or nil })
	local amount = u.atk * self:attackMult(u)
	if u.projectile then
		local flight = math.clamp(flatDist(u.pos, target.pos) / 80, 0.15, 0.5)
		self:schedule(flight, function()
			if target.alive and u.alive then
				self:damage(u, target, amount)
			end
		end)
	else
		self:damage(u, target, amount)
	end
end

local function brainrotAI(self: BattleT, u: Unit, dt: number)
	local owner = u.owner
	local participant = owner and self.participants[owner]
	local ownerUnit = participant and participant.playerUnit
	if not u.target or not u.target.alive or flatDist(u.target.pos, u.pos) > 140 then
		u.target = pickTarget(self, u)
		-- don't chase across the whole stadium: stay within leash range of the owner
		if u.target and ownerUnit and flatDist(u.target.pos, ownerUnit.pos) > 150 then
			u.target = nil
		end
	end
	local target = u.target
	if target then
		local reach = u.range + u.radius + target.radius
		local d = flatDist(target.pos, u.pos)
		if d > reach then
			moveToward(self, u, target.pos, reach * 0.9, dt)
		else
			u.moving = false
			face(u, target.pos)
			if self.now >= u.nextAttack then
				basicAttack(self, u, target)
			end
		end
		if u.ability and self.now >= u.nextAbility then
			if Abilities.cast(self, u, u.ability) then
				u.nextAbility = self.now + u.ability.cooldown
			end
		end
	elseif ownerUnit then
		-- follow the trainer in a loose formation
		local slot = (u.id % 8) / 8 * math.pi * 2
		local goal = ownerUnit.pos + Vector3.new(math.cos(slot) * 7, 0, math.sin(slot) * 7)
		moveToward(self, u, goal, 2, dt)
	else
		u.moving = false
	end
end

local function monsterAI(self: BattleT, u: Unit, dt: number)
	if u.casting > 0 then
		u.moving = false
		return
	end
	if u.boss then
		if BossAttacks.update(self, u) then
			return
		end
	end
	if not u.target or not u.target.alive or math.random() < 0.08 then
		u.target = pickTarget(self, u)
	end
	local target = u.target
	if not target then
		moveToward(self, u, self.center, 20, dt)
		return
	end
	local reach = u.range + u.radius + target.radius
	local d = flatDist(target.pos, u.pos)
	if d > reach then
		moveToward(self, u, target.pos, reach * 0.9, dt)
	else
		u.moving = false
		face(u, target.pos)
		if self.now >= u.nextAttack then
			basicAttack(self, u, target)
		end
	end
end

-------------------------------------------------------------------------------
-- Separation (spatial hash, 16-stud cells)
-------------------------------------------------------------------------------
local CELL = 16

local function separate(self: BattleT)
	local grid: { [number]: { Unit } } = {}
	local function key(x: number, z: number): number
		return (x + 4096) * 8192 + (z + 4096)
	end
	for _, u in self.units do
		if u.alive and u.kind ~= "player" then
			local k = key(math.floor(u.pos.X / CELL), math.floor(u.pos.Z / CELL))
			local list = grid[k]
			if not list then
				list = {}
				grid[k] = list
			end
			table.insert(list, u)
		end
	end
	local strength = CFG.SeparationStrength
	for _, u in self.units do
		if u.alive and u.kind ~= "player" and not u.isBoss then
			local cx, cz = math.floor(u.pos.X / CELL), math.floor(u.pos.Z / CELL)
			local push = Vector3.zero
			local reach = 2 -- 5×5 cells: also catches big bosses whose centre is two cells away
			for dx = -reach, reach do
				for dz = -reach, reach do
					local list = grid[key(cx + dx, cz + dz)]
					if list then
						for _, o in list do
							if o ~= u then
								local d = Vector3.new(u.pos.X - o.pos.X, 0, u.pos.Z - o.pos.Z)
								local minD = u.radius + o.radius
								local m = d.Magnitude
								if m < minD then
									local dir = if m > 1e-3
										then d / m
										else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
									-- bosses shove everyone; equals share the push
									local w = if o.isBoss then 1 else 0.5
									push += dir * (minD - m) * w
								end
							end
						end
					end
				end
			end
			if push.Magnitude > 0 then
				u.pos += push * strength
			end
		end
	end
	-- nothing may leave the battlefield
	for _, u in self.units do
		if u.kind ~= "player" then
			u.pos = self:clampToField(u.pos, u.radius)
		end
	end
end

-------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------
function Battle.tick(self: BattleT, now: number, dt: number)
	self.now = now
	-- statuses + burn
	for _, u in self.units do
		if u.alive then
			for name, s in u.statuses do
				if now >= s.untilT then
					u.statuses[name] = nil
					self:emit({ t = "status", id = u.id, s = name, on = false })
				elseif name == "Burn" then
					local src = s.source and self.units[s.source]
					self:damage(src, u, (s.value or 0) * dt, { fixed = true, crit = false, noReflect = true })
				end
			end
		end
	end
	-- player positions (their characters move on their own)
	for player, p in self.participants do
		local pu = p.playerUnit
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if pu and root and hum then
			pu.pos = Vector3.new(root.Position.X, self.floorY, root.Position.Z)
			pu.hp = hum.Health
			pu.alive = hum.Health > 0
		end
	end
	-- aura casters
	table.clear(self.auraUnits)
	for _, u in self.units do
		if u.alive and u.passive and u.passive.params.attackSpeed then
			table.insert(self.auraUnits, u)
		end
	end
	-- AI
	for _, u in self.units do
		if u.kind == "brainrot" then
			if u.alive then
				if not u.statuses.Stun and not u.statuses.Pulled then
					brainrotAI(self, u, dt)
				end
			elseif u.respawnAt > 0 and now >= u.respawnAt then
				local p = u.owner and self.participants[u.owner]
				local near = if p and p.playerUnit then p.playerUnit.pos else self.center
				self:revive(u, near + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6)), 1)
			end
		elseif u.kind == "monster" and u.alive then
			if now >= u.invulnerableUntil and not u.statuses.Stun and not u.statuses.Pulled then
				monsterAI(self, u, dt)
			elseif u.introTarget then
				-- boss entrance: stride in from the gate (time it to the intro length)
				local remaining = math.max(0.1, u.invulnerableUntil - now)
				local d = flatDist(u.introTarget, u.pos)
				local speed = math.max(u.speed, d / remaining)
				local saved = u.speed
				u.speed = speed
				moveToward(self, u, u.introTarget, 1, dt)
				u.speed = saved
			else
				u.moving = false
			end
		end
	end
	separate(self)
	-- scheduled actions (projectile impacts, multi-hits, boss attacks landing…)
	if #self.scheduled > 0 then
		local due = {}
		for i = #self.scheduled, 1, -1 do
			local s = self.scheduled[i]
			if now >= s.at then
				table.insert(due, s)
				table.remove(self.scheduled, i)
			end
		end
		for i = #due, 1, -1 do
			local ok, err = (pcall :: any)(due[i].fn)
			if not ok then
				warn(`[Battle] scheduled action failed: {err}`)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Snapshot packing: u16 battle, u16 count, then per unit
--   u16 id | i16 x*10 | i16 z*10 (relative to centre) | u8 yaw | u8 flags
-------------------------------------------------------------------------------
local PER_UNIT = 8
local MAX_PER_PACKET = 100

function Battle.packSnapshots(self: BattleT): { buffer }
	local list = {}
	for _, u in self.units do
		if u.kind ~= "player" then
			table.insert(list, u)
		end
	end
	local packets = {}
	local i = 1
	while i <= #list do
		local n = math.min(MAX_PER_PACKET, #list - i + 1)
		local b = buffer.create(4 + n * PER_UNIT)
		buffer.writeu16(b, 0, self.id)
		buffer.writeu16(b, 2, n)
		for k = 0, n - 1 do
			local u = list[i + k]
			local off = 4 + k * PER_UNIT
			buffer.writeu16(b, off, u.id % 65536)
			buffer.writei16(b, off + 2, math.clamp(round((u.pos.X - self.center.X) * 10), -32768, 32767))
			buffer.writei16(b, off + 4, math.clamp(round((u.pos.Z - self.center.Z) * 10), -32768, 32767))
			buffer.writeu8(b, off + 6, round((u.yaw % (2 * math.pi)) / (2 * math.pi) * 255) % 256)
			local flags = 0
			if u.moving then
				flags += 1
			end
			if u.casting > 0 then
				flags += 2
			end
			if not u.alive then
				flags += 4
			end
			buffer.writeu8(b, off + 7, flags)
		end
		table.insert(packets, b)
		i += n
	end
	return packets
end

function Battle.destroy(self: BattleT)
	self.active = false
	for _, u in self.units do
		if u.kind ~= "player" then
			self:emit({ t = "despawn", id = u.id })
		end
	end
	table.clear(self.units)
	table.clear(self.scheduled)
	self.UnitDied:DisconnectAll()
end

return Battle
