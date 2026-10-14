--!strict
-- Server-wide world events, one every GameConfig.Events.Interval seconds:
--   METEOR SHOWER / STORM  strikes rain on monsters in active battles (+ sky visuals)
--   BLOOD MOON             monsters stronger, rewards ×2
--   GOLDEN HOUR            roll luck ×2
--   GIANT MONSTER INVASION a giant boss lands in the hub meadow; walk in to fight it
--
-- State is published on ReplicatedStorage attributes so clients (and RollService /
-- MonsterService) can react: WorldEvent, WorldEventEnds (server time), EventLuck,
-- EventMonsterMult, EventRewardMult.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Format = require(Modules.Format)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local Battle = require(script.Parent.Parent.Combat.Battle)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)

local EventService = {}

local E = GameConfig.Events
local W = GameConfig.World

local current: GameConfig.WorldEventDef? = nil
local endsAt = 0
local nextAt = 0
local invasion: Battle.BattleT? = nil
local forced: string? = nil
local leftInvasion: { [Player]: boolean } = {} -- pressed LEAVE: don't pull them back in until they walk out

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function setBoard(text: string)
	local world = Workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	if not hub then
		return
	end
	for _, d in hub:GetDescendants() do
		if d.Name == "EventBoardLabel" and d:IsA("TextLabel") then
			d.Text = text
		end
	end
end

local function publish()
	local e = current
	ReplicatedStorage:SetAttribute("WorldEvent", if e then e.id else "")
	ReplicatedStorage:SetAttribute("WorldEventEnds", if e then endsAt else 0)
	ReplicatedStorage:SetAttribute("WorldEventNext", nextAt)
	ReplicatedStorage:SetAttribute("EventLuck", if e and e.luckMult then e.luckMult else 1)
	ReplicatedStorage:SetAttribute("EventMonsterMult", if e and e.monsterMult then e.monsterMult else 1)
	ReplicatedStorage:SetAttribute("EventRewardMult", if e and e.rewardMult then e.rewardMult else 1)
end

-------------------------------------------------------------------------------
-- Giant Invasion
-------------------------------------------------------------------------------
local function invasionTier(): number
	local best = 1
	for _, p in Players:GetPlayers() do
		local data = DataService.get(p)
		if data then
			for _, a in Registry.Arenas do
				if data.arena.beaten[a.id] then
					best = math.max(best, a.order)
				end
			end
		end
	end
	return best
end

local function endInvasion(text: string?)
	local b = invasion
	if not b then
		return
	end
	invasion = nil
	if text then
		Net.Server.fireAll("Announce", text, Color3.fromRGB(180, 60, 255))
	end
	CombatService.destroy(b)
	table.clear(leftInvasion)
end

local function startInvasion()
	local field = W.InvasionField
	local b = CombatService.create("Invasion", field.center, field.radius)
	invasion = b
	local tier = invasionTier()
	local arena = Registry.Arenas[tier]
	local ctx = { statMult = arena.statMult, rewardMult = arena.rewardMult, tier = tier, wave = 1 }
	b.spawnFn = function(id: string, pos: Vector3)
		return MonsterService.spawn(b, id, pos, ctx)
	end
	MonsterService.hookRewards(b, function()
		return ctx
	end)
	local boss = MonsterService.spawn(b, E.InvasionBoss, field.center + Vector3.new(0, 0, -30), ctx)
	if boss then
		-- scale with the number of players around (rough co-op balance)
		boss.maxHp *= math.max(1, #Players:GetPlayers() * 0.6)
		boss.hp = boss.maxHp
		boss.invulnerableUntil = b.now + 4
		b.meta.bossUnitId = boss.id
		b:emit({
			t = "bossintro",
			id = boss.id,
			d = boss.defId,
			name = boss.monsterDef and boss.monsterDef.name or "",
			title = boss.monsterDef and boss.monsterDef.title or "",
			dur = 4,
			landing = true,
		})
		b.UnitDied:Connect(function(u)
			if u == boss then
				for player, p in b.participants do
					Net.Server.fire("Reward", player, "🏆 INVASION REPELLED!", {
						`💰 {Format.commas(p.totals.coins or 0)} coins`,
						`⭐ {Format.commas(p.totals.xp or 0)} XP`,
						`👹 {p.totals.bossTokens or 0} Boss Tokens`,
					})
				end
				task.delay(4, function()
					if invasion == b then
						endInvasion(nil)
					end
				end)
			end
		end)
	end
	b.meta.hud = { arenaName = "Giant Invasion", status = "fighting", wave = 1, waves = 1, label = "GIANT MONSTER" }
end

local function invasionStep()
	local b = invasion
	if not b then
		return
	end
	local field = W.InvasionField
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (
				Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(field.center.X, 0, field.center.Z)
			).Magnitude
			local inThis = b.participants[player] ~= nil
			if leftInvasion[player] and d > field.radius + 10 then
				leftInvasion[player] = nil
			end
			if not inThis and not leftInvasion[player] and d < field.radius and not CombatService.battleOf(player) and DataService.get(player) then
				CombatService.addParticipant(b, player)
				Net.Server.fire(
					"Notify",
					player,
					"⚔️ You joined the fight against the giant!",
					Color3.fromRGB(255, 120, 120)
				)
			elseif inThis and d > field.radius + 40 then
				CombatService.removeParticipant(b, player, "left")
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Strikes (Meteor Shower / Storm)
-------------------------------------------------------------------------------
local function strike(kind: string)
	for _, b in CombatService.all() do
		local enemies = {}
		for _, u in b.units do
			if u.alive and u.team == "enemy" then
				table.insert(enemies, u)
			end
		end
		if #enemies > 0 then
			local target = enemies[math.random(1, #enemies)]
			local point = target.pos + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
			b:emit({
				t = "fx",
				n = if kind == "Storm" then "Lightning" else "MeteorStrike",
				x = point.X,
				z = point.Z,
				r = 12,
			})
			b:schedule(if kind == "Storm" then 0.15 else 0.8, function()
				for _, e in b:within("enemy", point, 12) do
					b:damage(nil, e, e.maxHp * E.StrikeDamageMult, { fixed = true, crit = false })
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------
local function pickEvent(): GameConfig.WorldEventDef
	if forced then
		local f = Registry.Event[forced]
		forced = nil
		if f then
			return f
		end
	end
	local total = 0
	for _, e in E.List do
		total += e.weight
	end
	local x = math.random() * total
	for _, e in E.List do
		x -= e.weight
		if x <= 0 then
			return e
		end
	end
	return E.List[1]
end

function EventService.startEvent(e: GameConfig.WorldEventDef)
	if current then
		EventService.stopEvent()
	end
	current = e
	endsAt = serverNow() + e.duration
	publish()
	Net.Server.fireAll("Announce", `🌍 {e.name}! {e.description}`, e.color)
	if e.id == "GiantInvasion" then
		startInvasion()
	end
end

function EventService.stopEvent()
	local e = current
	if not e then
		return
	end
	current = nil
	if e.id == "GiantInvasion" then
		endInvasion("The giant monster escaped back into the wild…")
	end
	nextAt = serverNow() + E.Interval
	publish()
end

-- Admin helper: force the next event (or start it now)
function EventService.force(id: string, now: boolean?)
	forced = id
	if now then
		EventService.startEvent(pickEvent())
	end
end

function EventService.init()
	nextAt = serverNow() + E.FirstDelay
	publish()
end

function EventService.start()
	CombatService.ParticipantRemoved:Connect(function(b, player: Player, reason: string)
		if b == invasion and reason == "left" then
			leftInvasion[player] = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leftInvasion[player] = nil
	end)
	task.spawn(function()
		local strikeAcc = 0
		while true do
			task.wait(0.5)
			local t = serverNow()
			local e = current
			if e then
				if t >= endsAt then
					EventService.stopEvent()
				elseif e.id == "MeteorShower" or e.id == "Storm" then
					strikeAcc += 0.5
					if strikeAcc >= E.StrikeInterval then
						strikeAcc = 0
						strike(e.id)
					end
				end
				if e.id == "GiantInvasion" then
					invasionStep()
				end
				setBoard(`{e.name}\n{e.description}\nEnds in {Format.clock(endsAt - t)}`)
			else
				if t >= nextAt then
					EventService.startEvent(pickEvent())
				else
					setBoard(`NEXT WORLD EVENT\nin {Format.clock(nextAt - t)}`)
				end
			end
		end
	end)
end

return EventService
