--!strict
-- All rewards flow through here so multipliers are applied in one place:
-- coins (Coin Boost × VIP), XP (XP Boost) with level-ups, Rot Essence, Roll Tokens,
-- Boss Tokens, rare drops and boss-exclusive Brainrot drops.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local ArenaConfig = require(Modules.ArenaConfig)
local BrainrotMath = require(Modules.BrainrotMath)
local Format = require(Modules.Format)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local Signal = require(Modules.Signal)
local Types = require(Modules.Types)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local RewardService = {}

RewardService.LevelUp = Signal.new() :: Signal.Signal<Player, number>

local rng = Random.new()

export type Totals = { [string]: number }

local function bump(totals: Totals?, key: string, amount: number)
	if totals then
		totals[key] = (totals[key] or 0) + amount
	end
end

function RewardService.coinMult(data: Types.PlayerData): number
	local m = 1
	if DataService.boostActive(data, "Coins") then
		m *= GameConfig.Boosts.Coins.mult
	end
	if data.passes.VIP then
		m *= GameConfig.Vip.CoinMult
	end
	return m
end

function RewardService.coins(player: Player, base: number, totals: Totals?): number
	local data = DataService.get(player)
	if not data or base <= 0 then
		return 0
	end
	local amount = math.floor(base * RewardService.coinMult(data))
	DataService.add(player, "coins", amount)
	bump(totals, "coins", amount)
	return amount
end

function RewardService.xp(player: Player, base: number, totals: Totals?): number
	local data = DataService.get(player)
	if not data or base <= 0 then
		return 0
	end
	local amount = math.floor(base * (if DataService.boostActive(data, "XP") then GameConfig.Boosts.XP.mult else 1))
	local level, xp, ups = BrainrotMath.applyXp(data.level, data.xp, amount)
	data.level, data.xp = level, xp
	bump(totals, "xp", amount)
	if ups > 0 then
		local gems = ups * GameConfig.Player.LevelUpGems
		DataService.add(player, "gems", gems)
		Net.Server.fire("Notify", player, `⭐ LEVEL UP! You are now level {level} (+{gems} 💎)`, Color3.fromRGB(120, 220, 255))
		RewardService.LevelUp:Fire(player, level)
	end
	DataService.push(player, "level", "xp")
	return amount
end

function RewardService.currency(player: Player, currency: DataService.Currency, amount: number, totals: Totals?)
	if amount <= 0 then
		return
	end
	DataService.add(player, currency, amount)
	bump(totals, currency, amount)
end

-- Rewards for one monster kill. `tier` = arena order (1..6), `rewardMult` from the arena
-- and any world event.
function RewardService.kill(player: Player, def: Types.MonsterDef, rewardMult: number, tier: number, totals: Totals?, drops: { string }?)
	local data = DataService.get(player)
	if not data then
		return
	end
	RewardService.coins(player, def.coins * rewardMult, totals)
	RewardService.xp(player, def.xp * math.sqrt(rewardMult), totals)
	if def.essence then
		RewardService.currency(player, "essence", def.essence * tier, totals)
	end
	if def.tokens then
		RewardService.currency(player, "tokens", def.tokens, totals)
	end
	if def.bossTokens then
		RewardService.currency(player, "bossTokens", def.bossTokens, totals)
	end
	data.stats.kills += 1
	bump(totals, "kills", 1)
	-- tiny chance of a bonus from any monster
	local roll = rng:NextNumber()
	if roll < 0.004 then
		RewardService.currency(player, "tokens", 1, totals)
		Net.Server.fire("Notify", player, "🎟️ Rare drop: Roll Token!", Color3.fromRGB(255, 120, 200))
	elseif roll < 0.006 then
		RewardService.currency(player, "gems", 5, totals)
		Net.Server.fire("Notify", player, "💎 Rare drop: 5 Gems!", Color3.fromRGB(90, 220, 255))
	end
	-- boss-exclusive drops
	if def.kind == "Boss" or def.kind == "MiniBoss" then
		data.stats.bossKills += 1
		data.arena.bossKills[def.id] = (data.arena.bossKills[def.id] or 0) + 1
		DataService.push(player, "arena")
		for _, drop in (def.drops or {}) :: { { brainrot: string, chance: number, mutation: string? } } do
			if rng:NextNumber() < drop.chance then
				local mut = drop.mutation or "Normal"
				local uid = InventoryService.add(player, drop.brainrot, mut)
				local name = Registry.displayName(drop.brainrot, mut)
				if drops then
					table.insert(drops, name)
				end
				Net.Server.fire("Notify", player, `👹 BOSS DROP: {name}{if uid then "" else " (auto-sold)"}!`, Registry.rarityOf(drop.brainrot).color)
				Net.Server.fireAll("Announce", `{player.DisplayName} got {name} from {def.name}!`, Registry.rarityOf(drop.brainrot).color)
			end
		end
	end
	DataService.push(player, "stats")
end

function RewardService.waveClear(player: Player, wave: number, rewardMult: number, totals: Totals?)
	local amount = RewardService.coins(player, ArenaConfig.WaveClearCoins * wave * rewardMult, totals)
	RewardService.xp(player, 10 * wave, totals)
	if amount > 0 then
		Net.Server.fire("Notify", player, `Wave {wave} cleared! +${Format.short(amount)}`, Color3.fromRGB(255, 220, 80))
	end
end

function RewardService.init() end
function RewardService.start() end

return RewardService
