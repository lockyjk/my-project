--!strict
-- Monster Arena runs (co-op): pick an unlocked arena at the gate → countdown (others can
-- join) → waves of monsters → elite / mini boss waves → GIANT BOSS with a cinematic
-- entrance through the north gate → victory (unlock the next arena) or defeat when every
-- fighter has died or left. Rewards are paid per kill as you go, so leaving early keeps
-- everything earned so far.
--
-- Run status for everyone is published on ReplicatedStorage attributes:
--   ArenaRun (arena id or ""), ArenaState, ArenaWave, ArenaTheme

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ArenaConfig = require(Modules.ArenaConfig)
local Format = require(Modules.Format)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local Types = require(Modules.Types)
local Battle = require(script.Parent.Parent.Combat.Battle)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MonsterService = require(script.Parent.MonsterService)
local RewardService = require(script.Parent.RewardService)

local ArenaService = {}

local W = GameConfig.World
local A = W.Arena

type State = "countdown" | "fighting" | "intermission" | "bossintro" | "victory" | "defeat"

type Run = {
	battle: Battle.BattleT,
	arena: Types.ArenaDef,
	state: string,
	wave: number,
	queue: { string },
	stateEnds: number,
	nextSpawn: number,
	bossUnitId: number?,
	everJoined: boolean,
}

local run: Run? = nil
local currentFloor = Enum.Material.Grass

local function notify(player: Player, text: string, color: Color3?)
	Net.Server.fire("Notify", player, text, color)
end

local function arenaModel(): Model?
	local world = Workspace:FindFirstChild("World")
	return world and world:FindFirstChild("MonsterArena") :: Model?
end

-------------------------------------------------------------------------------
-- Unlock rules
-------------------------------------------------------------------------------
function ArenaService.canEnter(data: Types.PlayerData, arena: Types.ArenaDef): (boolean, string?)
	if data.level < arena.requiredLevel then
		return false, `Reach level {arena.requiredLevel} to enter {arena.name}`
	end
	if arena.requiresArena and not data.arena.beaten[arena.requiresArena] then
		return false, `Defeat the {Registry.Arena[arena.requiresArena].name} boss first`
	end
	return true
end

-------------------------------------------------------------------------------
-- Stadium dressing: floor theme, boss doors, giant screens
-------------------------------------------------------------------------------
local function setFloor(material: Enum.Material)
	if material == currentFloor then
		return
	end
	local c = A.center
	local r = A.fieldRadius + 2
	local region = Region3.new(c + Vector3.new(-r, -12, -r), c + Vector3.new(r, 4, r)):ExpandToGrid(4)
	Workspace.Terrain:ReplaceMaterial(region, 4, currentFloor, material)
	currentFloor = material
end

local function setDoors(open: boolean)
	local model = arenaModel()
	local gate = model and model:FindFirstChild("BossGate")
	local doors = gate and gate:FindFirstChild("Doors")
	if not doors then
		return
	end
	for _, door in doors:GetChildren() do
		if door:IsA("BasePart") then
			local x = door:GetAttribute(if open then "OpenX" else "ClosedX") :: number
			local goal = CFrame.new(x, door.Position.Y, door.Position.Z)
			-- move the door and its welded-looking trim together
			local offset = goal.Position - door.Position
			TweenService:Create(door, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = goal }):Play()
			for _, trim in door:GetChildren() do
				if trim:IsA("BasePart") then
					TweenService:Create(trim, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
						CFrame = trim.CFrame + offset,
					}):Play()
				end
			end
		end
	end
end

local function setScreens(text: string)
	local model = arenaModel()
	local screens = model and model:FindFirstChild("Screens")
	if not screens then
		return
	end
	for _, d in screens:GetDescendants() do
		if d.Name == "ScreenLabel" and d:IsA("TextLabel") then
			d.Text = text
		end
	end
end

local function publishStatus()
	local r = run
	ReplicatedStorage:SetAttribute("ArenaRun", if r then r.arena.id else "")
	ReplicatedStorage:SetAttribute("ArenaState", if r then r.state else "idle")
	ReplicatedStorage:SetAttribute("ArenaWave", if r then r.wave else 0)
	ReplicatedStorage:SetAttribute("ArenaTheme", if r then r.arena.id else "")
end

local function setState(r: Run, state: State, duration: number?)
	r.state = state
	r.stateEnds = os.clock() + (duration or 0)
	publishStatus()
end

local function ctxFor(r: Run): MonsterService.Context
	return { statMult = r.arena.statMult, rewardMult = r.arena.rewardMult, tier = r.arena.order, wave = math.max(1, r.wave) }
end

local function updateHud(r: Run)
	local waveDef = r.arena.waves[r.wave]
	r.battle.meta.hud = {
		arenaId = r.arena.id,
		arenaName = r.arena.name,
		wave = r.wave,
		waves = #r.arena.waves,
		label = if waveDef then waveDef.label else nil,
		status = r.state,
		timer = math.max(0, r.stateEnds - os.clock()),
		queued = #r.queue,
	}
	r.battle.meta.bossUnitId = r.bossUnitId
	-- giant screens
	local boss = r.bossUnitId and r.battle.units[r.bossUnitId]
	if r.state == "countdown" then
		setScreens(`{r.arena.name:upper()}\nBATTLE STARTS IN {math.ceil(math.max(0, r.stateEnds - os.clock()))}`)
	elseif boss and boss.alive then
		setScreens(`{boss.monsterDef and boss.monsterDef.name or "BOSS"}\n{math.ceil(boss.hp / boss.maxHp * 100)}% HP`)
	elseif r.state == "victory" then
		setScreens("🏆 VICTORY! 🏆\nThe crowd goes wild!")
	elseif r.state == "intermission" then
		setScreens(`WAVE {r.wave} CLEARED!\nNext wave incoming…`)
	else
		setScreens(`WAVE {r.wave}/{#r.arena.waves}\n{r.battle:aliveCount("enemy") + #r.queue} MONSTERS LEFT`)
	end
end

-------------------------------------------------------------------------------
-- Joining / leaving
-------------------------------------------------------------------------------
local function teleport(player: Player, pos: Vector3, lookAt: Vector3?)
	local char = player.Character
	if char then
		local target = pos + Vector3.new(math.random(-8, 8), 0, math.random(-4, 4))
		char:PivotTo(CFrame.lookAt(target, if lookAt then Vector3.new(lookAt.X, target.Y, lookAt.Z) else target + Vector3.new(0, 0, -1)))
	end
end

local function join(r: Run, player: Player): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Loading…"
	end
	teleport(player, W.ArenaEntry, A.center)
	local p = CombatService.addParticipant(r.battle, player)
	if not p then
		return false, "You can't join right now"
	end
	r.everJoined = true
	if #data.equipped == 0 then
		notify(player, "You have no Brainrots equipped! Equip some in your Collection.", Color3.fromRGB(255, 120, 80))
	end
	Net.Server.fire("Notify", player, `⚔️ Entered {r.arena.name}!`, Color3.fromRGB(255, 220, 120))
	return true
end

local function summaryLines(totals: { [string]: number }, drops: { string }): { string }
	local lines = {
		`💰 {Format.commas(totals.coins or 0)} coins`,
		`⭐ {Format.commas(totals.xp or 0)} XP`,
		`💀 {totals.kills or 0} monsters defeated`,
	}
	if (totals.essence or 0) > 0 then
		table.insert(lines, `🧪 {totals.essence} Rot Essence`)
	end
	if (totals.tokens or 0) > 0 then
		table.insert(lines, `🎟️ {totals.tokens} Roll Tokens`)
	end
	if (totals.bossTokens or 0) > 0 then
		table.insert(lines, `👹 {totals.bossTokens} Boss Tokens`)
	end
	for _, d in drops do
		table.insert(lines, `🎁 {d}`)
	end
	return lines
end

local function startRun(arena: Types.ArenaDef, starter: Player): (boolean, string?)
	local b = CombatService.create("Arena", A.center, A.fieldRadius)
	local r: Run = {
		battle = b,
		arena = arena,
		state = "countdown",
		wave = 0,
		queue = {},
		stateEnds = os.clock() + ArenaConfig.StartCountdown,
		nextSpawn = 0,
		bossUnitId = nil,
		everJoined = false,
	}
	run = r
	b.statMult = arena.statMult
	b.rewardMult = arena.rewardMult
	b.spawnFn = function(id: string, pos: Vector3)
		return MonsterService.spawn(b, id, pos, ctxFor(r))
	end
	MonsterService.hookRewards(b, function()
		return ctxFor(r)
	end)
	setFloor(arena.floorMaterial)
	setDoors(false)
	publishStatus()
	local ok, err = join(r, starter)
	if not ok then
		CombatService.destroy(b)
		run = nil
		publishStatus()
		return false, err
	end
	Net.Server.fireAll("Announce", `{starter.DisplayName} started a battle in {arena.name}! Join through the arena gate.`, Color3.fromRGB(255, 120, 120))
	return true
end

-------------------------------------------------------------------------------
-- Waves
-------------------------------------------------------------------------------
local function startWave(r: Run, n: number)
	r.wave = n
	local def = r.arena.waves[n]
	r.queue = {}
	for _, s in def.spawns do
		for _ = 1, s.count do
			table.insert(r.queue, s.monster)
		end
	end
	-- shuffle so mixed waves arrive mixed
	for i = #r.queue, 2, -1 do
		local j = math.random(1, i)
		r.queue[i], r.queue[j] = r.queue[j], r.queue[i]
	end
	if def.boss then
		local bossId = table.remove(r.queue, 1) :: string
		local gate = arenaModel() and (arenaModel() :: Model):FindFirstChild("BossGate")
		local spawnAt = (gate and gate:GetAttribute("BossSpawn")) :: Vector3? or (A.center + Vector3.new(0, 0, -A.fieldRadius + 40))
		setDoors(true)
		local boss = MonsterService.spawn(r.battle, bossId, spawnAt, ctxFor(r))
		if boss then
			boss.invulnerableUntil = r.battle.now + GameConfig.Combat.InvulnerableIntroSeconds
			boss.yaw = 0 -- facing south, into the arena
			r.bossUnitId = boss.id
			local def2 = boss.monsterDef :: Types.MonsterDef
			r.battle:emit({ t = "bossintro", id = boss.id, d = bossId, name = def2.name, title = def2.title or "", dur = GameConfig.Combat.InvulnerableIntroSeconds })
		end
		setState(r, "bossintro", GameConfig.Combat.InvulnerableIntroSeconds)
	else
		r.battle:emit({ t = "wave", n = n, total = #r.arena.waves, label = def.label })
		setState(r, "fighting")
	end
end

local function victory(r: Run)
	setState(r, "victory", ArenaConfig.VictoryLingerSeconds)
	r.battle:emit({ t = "victory" })
	for player, p in r.battle.participants do
		local data = DataService.get(player)
		if data then
			local first = not data.arena.beaten[r.arena.id]
			data.arena.beaten[r.arena.id] = true
			data.arena.bestWave[r.arena.id] = math.max(data.arena.bestWave[r.arena.id] or 0, #r.arena.waves)
			DataService.push(player, "arena")
			local lines = summaryLines(p.totals, p.drops)
			if first then
				local nextArena = nil
				for _, a in Registry.Arenas do
					if a.requiresArena == r.arena.id then
						nextArena = a
					end
				end
				if nextArena then
					table.insert(lines, 1, `🔓 {nextArena.name} unlocked! (Level {nextArena.requiredLevel})`)
				end
			end
			Net.Server.fire("Reward", player, `🏆 {r.arena.name:upper()} CLEARED!`, lines)
		end
	end
end

local function finish(r: Run)
	setDoors(false)
	CombatService.destroy(r.battle)
	if run == r then
		run = nil
	end
	setFloor(Enum.Material.Grass)
	setScreens("MONSTER ARENA\nStep through the gate to fight!")
	publishStatus()
end

local function step(r: Run)
	local now = os.clock()
	local b = r.battle
	-- nobody left fighting → defeat
	if r.everJoined and next(b.participants) == nil and r.state ~= "victory" then
		setState(r, "defeat")
		finish(r)
		return
	end
	local state: string = r.state
	if state == "countdown" then
		if now >= r.stateEnds then
			startWave(r, 1)
		end
	elseif state == "bossintro" then
		if now >= r.stateEnds then
			setState(r, "fighting")
		end
	elseif state == "fighting" then
		local alive = b:aliveCount("enemy")
		if #r.queue > 0 and alive < ArenaConfig.MaxAliveMonsters and now >= r.nextSpawn then
			local id = table.remove(r.queue, 1) :: string
			MonsterService.spawn(b, id, MonsterService.edgePoint(b, true), ctxFor(r))
			r.nextSpawn = now + ArenaConfig.SpawnInterval
		elseif #r.queue == 0 and alive == 0 then
			-- wave cleared
			for player, p in b.participants do
				RewardService.waveClear(player, r.wave, r.arena.rewardMult * MonsterService.eventRewardMult(), p.totals)
				local data = DataService.get(player)
				if data then
					data.arena.bestWave[r.arena.id] = math.max(data.arena.bestWave[r.arena.id] or 0, r.wave)
				end
			end
			if r.wave >= #r.arena.waves then
				victory(r)
			else
				b:emit({ t = "waveclear", n = r.wave })
				setState(r, "intermission", ArenaConfig.IntermissionSeconds)
			end
		end
	elseif state == "intermission" then
		if now >= r.stateEnds then
			startWave(r, r.wave + 1)
		end
	elseif state == "victory" then
		if now >= r.stateEnds then
			finish(r)
			return
		end
	end
	updateHud(r)
end

-------------------------------------------------------------------------------
function ArenaService.enter(player: Player, arenaId: string?): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Loading…"
	end
	if CombatService.battleOf(player) then
		return false, "You're already fighting!"
	end
	local r = run
	if r then
		if r.state == "victory" or r.state == "defeat" then
			return false, "The arena is resetting — try again in a moment!"
		end
		local ok, why = ArenaService.canEnter(data, r.arena)
		if not ok then
			return false, `A {r.arena.name} battle is running. {why}`
		end
		return join(r, player)
	end
	local arena = Registry.Arena[arenaId or "GreenFields"]
	if not arena then
		return false, "Unknown arena"
	end
	local ok, why = ArenaService.canEnter(data, arena)
	if not ok then
		return false, why
	end
	return startRun(arena, player)
end

function ArenaService.leave(player: Player): boolean
	local b = CombatService.battleOf(player)
	if not b then
		return false
	end
	CombatService.removeParticipant(b, player, "left")
	return true
end

function ArenaService.init()
	publishStatus()
end

function ArenaService.start()
	Net.Server.handle("ArenaEnter", function(player: Player, arenaId: string?)
		return ArenaService.enter(player, arenaId)
	end)
	Net.Server.handle("ArenaLeave", function(player: Player)
		return ArenaService.leave(player)
	end)
	CombatService.ParticipantRemoved:Connect(function(b, player: Player, reason: string, p: Battle.Participant)
		local r = run
		if not r or r.battle ~= b then
			return
		end
		if reason == "died" then
			local lines = summaryLines(p.totals, p.drops)
			table.insert(lines, 1, `You fell on wave {r.wave} of {r.arena.name}. Rewards kept!`)
			table.insert(lines, "Tip: level up your Brainrots and use Dodge (Q) on red warnings.")
			Net.Server.fire("Reward", player, "💀 KNOCKED OUT", lines)
		elseif reason == "left" then
			Net.Server.fire("Reward", player, `LEFT {r.arena.name:upper()} (WAVE {r.wave})`, summaryLines(p.totals, p.drops))
		end
		if reason ~= "died" and player.Parent then
			teleport(player, W.ArenaGate, W.Machine)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local r = run
			if r then
				local ok, err = (pcall :: any)(step, r)
				if not ok then
					warn(`[Arena] step error: {err}`)
				end
			end
		end
	end)
end

return ArenaService
