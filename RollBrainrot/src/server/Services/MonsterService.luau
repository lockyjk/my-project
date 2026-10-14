--!strict
-- Monster creation: scaling (arena × wave × world event), spawn points around the
-- battlefield edge, and reward hookup when monsters die. ArenaService drives waves;
-- EventService uses the same calls for the hub Giant Invasion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ArenaConfig = require(Modules.ArenaConfig)
local BrainrotMath = require(Modules.BrainrotMath)
local Registry = require(Modules.Registry)
local Battle = require(script.Parent.Parent.Combat.Battle)
local RewardService = require(script.Parent.RewardService)

local MonsterService = {}

export type Context = {
	statMult: number,
	rewardMult: number,
	tier: number,
	wave: number,
}

local function eventMult(name: string): number
	local v = ReplicatedStorage:GetAttribute(name)
	return if type(v) == "number" and v > 0 then v else 1
end

-- World-event multipliers right now (Blood Moon etc.)
function MonsterService.eventMonsterMult(): number
	return eventMult("EventMonsterMult")
end

function MonsterService.eventRewardMult(): number
	return eventMult("EventRewardMult")
end

-- Where the next monster appears (near the fighters; see Battle.spawnPoint)
function MonsterService.spawnPoint(b: Battle.BattleT): Vector3
	return b:spawnPoint()
end

function MonsterService.spawn(b: Battle.BattleT, monsterId: string, pos: Vector3, ctx: Context): Battle.Unit?
	local def = Registry.Monster[monsterId]
	if not def then
		return nil
	end
	-- giant bosses are tuned as-is per arena (no per-wave growth); everything else ramps
	local wave = if def.kind == "Boss" then 1 else ctx.wave
	local scale =
		BrainrotMath.monsterScale(ctx.statMult, wave, ArenaConfig.WaveGrowth, MonsterService.eventMonsterMult())
	-- damage against player characters grows gently with tier (players don't scale ×4000)
	local playerMult = (1 + 0.5 * (ctx.tier - 1)) * (1 + 0.04 * (ctx.wave - 1))
	return b:addMonster(monsterId, pos, scale, playerMult)
end

-- Grants kill rewards to every fighter in the battle (co-op: everyone gets the full reward)
function MonsterService.hookRewards(b: Battle.BattleT, getCtx: () -> Context)
	b.UnitDied:Connect(function(u: Battle.Unit)
		if u.kind ~= "monster" or not u.monsterDef then
			return
		end
		local ctx = getCtx()
		local mult = ctx.rewardMult * MonsterService.eventRewardMult()
		for player, p in b.participants do
			RewardService.kill(player, u.monsterDef, mult, ctx.tier, p.totals, p.drops)
		end
	end)
end

function MonsterService.init() end
function MonsterService.start() end

return MonsterService
