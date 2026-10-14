--!strict
-- Runs every Battle: fixed-rate ticks, joining/leaving fighters, player abilities, and the
-- network layer (reliable batched events + unreliable position snapshots) for everyone
-- close enough to see the fight.
--
-- Arena runs (ArenaService) and Giant Invasions (EventService) both use this service.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Signal = require(Modules.Signal)
local Battle = require(script.Parent.Parent.Combat.Battle)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local CombatService = {}

type BattleT = Battle.BattleT
type Participant = Battle.Participant

local CFG = GameConfig.Combat
local PA = GameConfig.PlayerAbilities
local VIEW_DISTANCE = 650 -- players this far outside a battle still see it

local battles: { [number]: BattleT } = {}
local battleOfPlayer: { [Player]: BattleT } = {}
local subscribers: { [BattleT]: { [Player]: boolean } } = {}
local nextBattleId = 1

-- (battle, player, reason, participant) — reason: "left" | "died" | "ended"
CombatService.ParticipantRemoved = Signal.new() :: Signal.Signal<BattleT, Player, string, Participant>

function CombatService.battleOf(player: Player): BattleT?
	return battleOfPlayer[player]
end

function CombatService.all(): { [number]: BattleT }
	return battles
end

function CombatService.create(kind: string, center: Vector3, radius: number): BattleT
	local b = Battle.new(nextBattleId, kind, center, radius)
	nextBattleId = nextBattleId % 60000 + 1
	battles[b.id] = b
	subscribers[b] = {}
	return b
end

-------------------------------------------------------------------------------
-- Participants
-------------------------------------------------------------------------------
local function playerAttack(player: Player, b: BattleT): number
	local data = DataService.get(player)
	if not data then
		return 10
	end
	local power = BrainrotMath.upgradeValue(GameConfig.Upgrades.TrainerPower, data.upgrades.TrainerPower or 0)
	local base = BrainrotMath.playerAttack(data.level, power)
	-- the trainer keeps pace with their team so their hits always matter
	local p = b.participants[player]
	local total, n = 0, 0
	if p then
		for _, id in p.unitIds do
			local u = b.units[id]
			if u then
				total += u.atk
				n += 1
			end
		end
	end
	return base + (if n > 0 then 0.3 * total / n else 0)
end

local function teamAverageAttack(b: BattleT, p: Participant): number
	local total, n = 0, 0
	for _, id in p.unitIds do
		local u = b.units[id]
		if u then
			total += u.atk
			n += 1
		end
	end
	return if n > 0 then total / n else 10
end

-- Spawn/despawn brainrot units so they match the player's equipped list
local function syncTeam(b: BattleT, player: Player)
	local p = b.participants[player]
	local data = DataService.get(player)
	if not p or not data then
		return
	end
	local wanted: { [string]: boolean } = {}
	for _, uid in data.equipped do
		wanted[uid] = true
	end
	for i = #p.unitIds, 1, -1 do
		local u = b.units[p.unitIds[i]]
		if not u or not u.uid or not wanted[u.uid] then
			if u then
				b:removeUnit(u)
			end
			table.remove(p.unitIds, i)
		else
			wanted[u.uid] = nil
		end
	end
	local origin = if p.playerUnit then p.playerUnit.pos else b.center
	local k = 0
	for _, uid in data.equipped do
		if wanted[uid] then
			local inst = data.inventory[uid]
			if inst then
				k += 1
				local a = k / 8 * math.pi * 2
				local u = b:addBrainrot(player, uid, inst, origin + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6))
				if u then
					table.insert(p.unitIds, u.id)
				end
			end
		end
	end
end

function CombatService.addParticipant(b: BattleT, player: Player): Participant?
	if battleOfPlayer[player] then
		return nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	local p: Participant = {
		player = player,
		unitIds = {},
		playerUnit = nil,
		charge = 0,
		cooldowns = {},
		rallyUntil = 0,
		iframesUntil = 0,
		damage = 0,
		totals = { coins = 0, xp = 0, essence = 0, tokens = 0, bossTokens = 0, kills = 0 },
		drops = {},
	}
	b.participants[player] = p
	battleOfPlayer[player] = b
	p.playerUnit = b:addPlayerUnit(player, hum.MaxHealth, playerAttack(player, b))
	syncTeam(b, player)
	player:SetAttribute("BattleId", b.id)
	subscribers[b][player] = nil -- force a fresh full sync on the next subscription pass
	return p
end

function CombatService.removeParticipant(b: BattleT, player: Player, reason: string)
	local p = b.participants[player]
	if not p then
		return
	end
	for _, id in p.unitIds do
		local u = b.units[id]
		if u then
			b:removeUnit(u)
		end
	end
	if p.playerUnit then
		b.units[p.playerUnit.id] = nil
	end
	b.participants[player] = nil
	if battleOfPlayer[player] == b then
		battleOfPlayer[player] = nil
	end
	player:SetAttribute("BattleId", nil)
	Net.Server.fire("Battle", player, { active = false })
	CombatService.ParticipantRemoved:Fire(b, player, reason, p)
end

function CombatService.destroy(b: BattleT)
	for player in b.participants do
		CombatService.removeParticipant(b, player, "ended")
	end
	b:destroy()
	for player in (subscribers[b] or {}) :: { [Player]: boolean } do
		Net.Server.fire("CombatEvents", player, b.id, { { t = "clear" } })
	end
	subscribers[b] = nil
	battles[b.id] = nil
end

-------------------------------------------------------------------------------
-- Player abilities
-------------------------------------------------------------------------------
local function ready(p: Participant, id: string, cooldown: number, now: number): boolean
	if now < (p.cooldowns[id] or 0) then
		return false
	end
	p.cooldowns[id] = now + cooldown
	return true
end

local function onAction(player: Player, action: string, aim: Vector3?)
	local b = battleOfPlayer[player]
	local p = b and b.participants[player]
	if not b or not p or not p.playerUnit then
		return
	end
	local pu = p.playerUnit
	if not pu.alive then
		return
	end
	local now = b.now
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	if aim then
		local flatAim = Vector3.new(aim.X, 0, aim.Z)
		if flatAim.Magnitude > 0.1 then
			look = flatAim.Unit
		end
	end
	if action == "Attack" then
		if not ready(p, "Attack", PA.Attack.cooldown * 0.9, now) then
			return
		end
		pu.atk = playerAttack(player, b)
		-- cleave up to three enemies in front of the trainer
		local hits = {}
		for _, u in b.units do
			if u.alive and u.team == "enemy" then
				local rel = Vector3.new(u.pos.X - pu.pos.X, 0, u.pos.Z - pu.pos.Z)
				local d = rel.Magnitude - u.radius
				if d <= GameConfig.Player.AttackRange and (rel.Magnitude < 0.1 or rel.Unit:Dot(look) > 0.2) then
					table.insert(hits, { u = u, d = d })
				end
			end
		end
		table.sort(hits, function(a, c)
			return a.d < c.d
		end)
		for i = 1, math.min(3, #hits) do
			b:damage(pu, hits[i].u, pu.atk * (if i == 1 then 1 else 0.6) * b:attackMult(pu))
		end
		b:emit({ t = "patk", id = pu.id, o = player.UserId })
	elseif action == "Dodge" then
		if ready(p, "Dodge", PA.Dodge.cooldown, now) then
			p.iframesUntil = now + PA.Dodge.iframes
		end
	elseif action == "Heal" then
		if ready(p, "Heal", PA.Heal.cooldown, now) then
			for _, id in p.unitIds do
				local u = b.units[id]
				if u then
					if u.alive then
						b:heal(u, u.maxHp * PA.Heal.healPct)
					elseif PA.Heal.revive then
						b:revive(u, pu.pos + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5)), PA.Heal.healPct)
					end
				end
			end
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.25)
			end
			b:emit({ t = "fx", n = "TrainerHeal", x = pu.pos.X, z = pu.pos.Z, r = 30 })
		end
	elseif action == "Rally" then
		if ready(p, "Rally", PA.Rally.cooldown, now) then
			p.rallyUntil = now + PA.Rally.duration
			for _, id in p.unitIds do
				local u = b.units[id]
				if u and u.alive then
					b:addStatus(u, "Rally", PA.Rally.duration, PA.Rally.attackMult)
				end
			end
			b:emit({ t = "fx", n = "Rally", x = pu.pos.X, z = pu.pos.Z, r = 30 })
		end
	elseif action == "Ultimate" then
		if p.charge < PA.Ultimate.chargeNeeded or not ready(p, "Ultimate", PA.Ultimate.cooldown, now) then
			return
		end
		p.charge = 0
		local point = b:clampToField(pu.pos + look * 26)
		b:emit({ t = "fx", n = "Ultimate", x = point.X, z = point.Z, r = PA.Ultimate.radius })
		local amount = teamAverageAttack(b, p) * PA.Ultimate.damageMult
		b:schedule(0.9, function()
			for _, e in b:within("enemy", point, PA.Ultimate.radius) do
				b:damage(pu, e, amount, { crit = true })
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- HUD status for each fighter (team HP, cooldowns, charge + whatever the battle owner
-- put into b.meta.hud: wave numbers, boss, labels…)
-------------------------------------------------------------------------------
local function hudFor(b: BattleT, p: Participant): { [string]: any }
	local team = {}
	for _, id in p.unitIds do
		local u = b.units[id]
		if u then
			table.insert(team, {
				uid = u.uid,
				id = u.defId,
				hp = math.floor(u.hp),
				mhp = math.floor(u.maxHp),
				alive = u.alive,
				respawn = if u.alive then 0 else math.max(0, u.respawnAt - b.now),
			})
		end
	end
	local cds = {}
	for id, t in p.cooldowns do
		cds[id] = math.max(0, t - b.now)
	end
	local hud: { [string]: any } = {
		active = true,
		battleId = b.id,
		kind = b.kind,
		charge = p.charge,
		chargeNeeded = PA.Ultimate.chargeNeeded,
		team = team,
		cooldowns = cds,
		rally = math.max(0, p.rallyUntil - b.now),
		totals = p.totals,
		fighters = 0,
		enemies = b:aliveCount("enemy"),
	}
	for _ in b.participants do
		hud.fighters += 1
	end
	for k, v in b.meta.hud or {} do
		hud[k] = v
	end
	local bossId = b.meta.bossUnitId
	local boss = bossId and b.units[bossId]
	if boss then
		hud.boss = {
			id = boss.defId,
			name = boss.monsterDef and boss.monsterDef.name or boss.defId,
			title = boss.monsterDef and boss.monsterDef.title or "",
			hp = math.floor(boss.hp),
			mhp = math.floor(boss.maxHp),
			enraged = boss.boss ~= nil and boss.boss.enraged,
			unit = boss.id,
		}
	end
	return hud
end

-------------------------------------------------------------------------------
-- Networking
-------------------------------------------------------------------------------
local function updateSubscribers(b: BattleT)
	local subs = subscribers[b]
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local near = b.participants[player] ~= nil
			or (root ~= nil and (root.Position - b.center).Magnitude < b.radius + VIEW_DISTANCE)
		if near and not subs[player] then
			subs[player] = true
			local list = { { t = "reset", cx = b.center.X, cy = b.center.Y, cz = b.center.Z } }
			for _, u in b.units do
				if u.kind ~= "player" then
					table.insert(list, b:spawnEvent(u))
				end
			end
			Net.Server.fire("CombatEvents", player, b.id, list)
		elseif not near and subs[player] then
			subs[player] = nil
			Net.Server.fire("CombatEvents", player, b.id, { { t = "clear" } })
		end
	end
	for player in subs do
		if not player.Parent then
			subs[player] = nil
		end
	end
end

local function flush(b: BattleT)
	local subs = subscribers[b]
	if not subs then
		return
	end
	if #b.events > 0 then
		local events = b.events
		b.events = {}
		for player in subs do
			Net.Server.fire("CombatEvents", player, b.id, events)
		end
	end
	local packets = b:packSnapshots()
	for player in subs do
		for _, packet in packets do
			Net.Server.fireUnreliable("CombatSnap", player, packet)
		end
	end
end

-------------------------------------------------------------------------------
function CombatService.init() end

function CombatService.start()
	Net.Server.on("PlayerAction", onAction)

	local step = 1 / CFG.TickRate
	local acc = 0
	local hudAcc = 0
	local subAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < step then
			return
		end
		local tickDt = math.min(acc, step * 3)
		acc = 0
		local now = os.clock()
		hudAcc += tickDt
		subAcc += tickDt
		for _, b in battles do
			if b.active then
				local ok, err = pcall(b.tick, b, now, tickDt)
				if not ok then
					warn(`[Combat] battle {b.id} tick error: {err}`)
				end
			end
		end
		if subAcc >= 0.5 then
			subAcc = 0
			for _, b in battles do
				updateSubscribers(b)
			end
		end
		for _, b in battles do
			flush(b)
		end
		if hudAcc >= 0.25 then
			hudAcc = 0
			for _, b in battles do
				for player, p in b.participants do
					Net.Server.fire("Battle", player, hudFor(b, p))
				end
			end
		end
	end)

	-- leaving the game or dying removes you from your battle
	local function hookCharacter(player: Player, char: Model)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				local b = battleOfPlayer[player]
				if b then
					CombatService.removeParticipant(b, player, "died")
				end
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			hookCharacter(player, char)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(char)
			hookCharacter(player, char)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		local b = battleOfPlayer[player]
		if b then
			CombatService.removeParticipant(b, player, "left")
		end
		for _, subs in subscribers do
			subs[player] = nil
		end
	end)
	-- equipping mid-fight swaps the units in
	InventoryService.Changed:Connect(function(player: Player)
		local b = battleOfPlayer[player]
		if b then
			syncTeam(b, player)
		end
	end)
end

return CombatService
