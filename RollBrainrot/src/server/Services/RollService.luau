--!strict
-- Server-authoritative Brainrot rolls: cost, luck, pity, mutation, ownership.
-- The client only plays the reveal for the result the server returns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local RollMath = require(Modules.RollMath)
local Types = require(Modules.Types)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local RollService = {}

local rng = Random.new()

-- Total luck multiplier for a player right now
function RollService.luck(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	local luck = BrainrotMath.upgradeValue(GameConfig.Upgrades.Luck, data.upgrades.Luck or 0)
	if DataService.boostActive(data, "Luck") then
		luck *= GameConfig.Boosts.Luck.mult
	end
	local eventLuck = ReplicatedStorage:GetAttribute("EventLuck")
	if type(eventLuck) == "number" and eventLuck > 0 then
		luck *= eventLuck
	end
	return math.floor(luck * 100 + 0.5) / 100
end

local function refreshLuck(player: Player)
	player:SetAttribute("Luck", RollService.luck(player))
end

export type RollPayload = {
	uid: string?,
	id: string,
	mut: string,
	rarity: string,
	pityHit: boolean,
	autoSold: boolean,
	pity: number,
	luck: number,
	isNew: boolean,
}

local function announce(player: Player, def: Types.BrainrotDef, mut: string)
	local rarity = Registry.Rarity[def.rarity]
	if rarity.order >= Registry.Rarity.Legendary.order or (Registry.Mutation[mut].order >= 4) then
		Net.Server.fireAll(
			"Announce",
			`{player.DisplayName} rolled {Registry.displayName(def.id, mut)} ({def.rarity})!`,
			rarity.color
		)
	end
end

function RollService.roll(player: Player, useToken: boolean): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "Loading…"
	end
	if useToken then
		if data.tokens < GameConfig.Roll.TokenCost then
			return false, "No Roll Tokens left"
		end
	elseif data.coins < GameConfig.Roll.CoinCost then
		return false, `Need ${GameConfig.Roll.CoinCost} to roll`
	end
	if useToken then
		DataService.spend(player, "tokens", GameConfig.Roll.TokenCost)
	else
		DataService.spend(player, "coins", GameConfig.Roll.CoinCost)
	end

	local pityId = GameConfig.Roll.Pity.id
	local luck = RollService.luck(player)
	local result, newPity = RollMath.roll(rng, luck, data.pity[pityId] or 0)
	data.pity[pityId] = newPity
	data.totalRolls += 1
	data.stats.rolls += 1
	local isNew = not data.index[result.brainrot.id]
	local uid = InventoryService.add(player, result.brainrot.id, result.mutation.id)
	DataService.push(player, "pity", "totalRolls", "stats")
	announce(player, result.brainrot, result.mutation.id)

	local payload: RollPayload = {
		uid = uid,
		id = result.brainrot.id,
		mut = result.mutation.id,
		rarity = result.rarity.id,
		pityHit = result.pityHit,
		autoSold = uid == nil,
		pity = newPity,
		luck = luck,
		isNew = isNew,
	}
	return true, payload
end

-- Grant a random Brainrot of a given rarity (daily rewards, boss crates)
function RollService.grantOfRarity(player: Player, rarityId: string, mutationId: string?): (string?, string?)
	local pool = Registry.RollPool[rarityId] or Registry.ByRarity[rarityId]
	if not pool or #pool == 0 then
		return nil, nil
	end
	local def = pool[rng:NextInteger(1, #pool)]
	local mut = mutationId or RollMath.pickMutation(rng, RollService.luck(player)).id
	local uid = InventoryService.add(player, def.id, mut)
	announce(player, def, mut)
	return uid, def.id
end

function RollService.init() end

function RollService.start()
	Net.Server.handle("Roll", function(player: Player, useToken: boolean)
		return RollService.roll(player, useToken)
	end)
	DataService.Loaded:Connect(function(player: Player)
		refreshLuck(player)
	end)
	-- luck can change with boosts expiring and world events, so refresh it periodically
	task.spawn(function()
		while true do
			task.wait(2)
			for _, p in Players:GetPlayers() do
				if DataService.get(p) then
					refreshLuck(p)
				end
			end
		end
	end)
end

return RollService
