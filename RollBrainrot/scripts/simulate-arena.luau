--!nocheck
-- Balance check: `lune run scripts/simulate-arena [arenaId] [level] [brainrot ids…]`
-- Runs a whole arena (all waves, monsters trickling in like ArenaService) with the given
-- team and prints how long each wave takes and whether the team wipes. The trainer is
-- not simulated, so real runs are a bit faster.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
process.env.LOADER_ONLY = "1"
local loader = require("./run-tests")
local req = loader.require
local shared = loader.shared
local Registry = req(shared.Registry)
local ArenaConfig = req(shared.ArenaConfig)
local BrainrotMath = req(shared.BrainrotMath)
local serverNode = loader.server
local Battle = req(serverNode.Combat.Battle)

local args = process.args
local arena = Registry.Arena[args[1] or "GreenFields"]
local level = tonumber(args[2]) or 1
local ids = {}
for i = 3, #args do
	table.insert(ids, args[i])
end
if #ids == 0 then
	ids = { "BananiniBongo", "PizzarinoMozzarino", "Cactoboom" }
end

local b = Battle.new(1, "Arena", Vector3.new(0, 0, 0), 540)
local owner = { UserId = 1 }
local power = 0
for i, id in ids do
	local inst = { id = id, mut = "Normal", lvl = level, t = 0 }
	power += BrainrotMath.instancePower(inst)
	b:addBrainrot(owner, tostring(i), inst, Vector3.new(i * 4, 0, 200))
end
print(`{arena.name}: team power {power} (recommended {arena.recommendedPower}), level {level}`)
local now = b.now
local total = 0
deaths, dealt = 0, 0
local queue = {}
b.spawnFn = function(id, pos)
	return b:addMonster(id, pos, BrainrotMath.monsterScale(arena.statMult, 1, ArenaConfig.WaveGrowth, 1), 1)
end
for w, wave in arena.waves do
	for _, s in wave.spawns do
		for _ = 1, s.count do
			table.insert(queue, s.monster)
		end
	end
	local scale = BrainrotMath.monsterScale(arena.statMult, if wave.boss then 1 else w, ArenaConfig.WaveGrowth, 1)
	local t, nextSpawn = 0, 0
	deaths, dealt = 0, 0
	taken = {}
	while (#queue > 0 or b:aliveCount("enemy") > 0) and t < 600 do
		if #queue > 0 and b:aliveCount("enemy") < ArenaConfig.MaxAliveMonsters and t >= nextSpawn then
			b:addMonster(table.remove(queue, 1), b:spawnPoint(), scale, 1)
			nextSpawn = t + ArenaConfig.SpawnInterval
		end
		t += 0.1
		now += 0.1
		b:tick(now, 0.1)
		for _, ev in b.events do
			if ev.t == "die" and b.units[ev.id] and b.units[ev.id].team == "ally" then
				deaths += 1
			elseif ev.t == "hit" and b.units[ev.id] and b.units[ev.id].team == "ally" then
				local src = ev.s and b.units[ev.s]
				local k = if src then (if src.isBoss then "boss" else src.defId) else "?"
				taken[k] = (taken[k] or 0) + ev.a
			elseif ev.t == "hit" and b.units[ev.id] and b.units[ev.id].team == "enemy" then
				dealt += ev.a
			end
		end
		table.clear(b.events)
		local alive = 0
		for _, u in b.units do
			if u.team == "ally" and u.alive then
				alive += 1
			end
		end
	end
	total += t
	print(
		string.format(
			"  wave %2d%-12s %6.1fs  team DPS %5.0f  deaths %2d%s",
			w,
			wave.label and (" " .. wave.label) or "",
			t,
			dealt / t,
			deaths,
			if t >= 600 then "  (TIMEOUT — team too weak)" else ""
		)
	)
	if process.env.VERBOSE then
		local parts = {}
		for k, v in taken do
			table.insert(parts, `{k}={math.floor(v)}`)
		end
		print("      damage taken: " .. table.concat(parts, " "))
	end
	if t >= 600 then
		break
	end
	table.clear(queue)
end
print(string.format("total %.1f min", total / 60))
