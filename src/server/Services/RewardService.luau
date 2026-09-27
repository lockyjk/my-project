--!strict
-- Grants a Config Reward table (quests, gifts, streaks, pass tiers, achievements, products)
-- and owns the potion inventory. Returns human-readable lines for the reward popup.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)
local PetService = require(script.Parent.PetService)
local StatsService = require(script.Parent.StatsService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local RewardService = {}

local function now(): number
	return DateTime.now().UnixTimestamp
end

-- Grants every part of a reward. `title` shows a popup on the client when given.
function RewardService.grant(player: Player, reward: Types.Reward, source: string, title: string?): { string }
	local data = DataService.get(player)
	if not data then
		return {}
	end
	local lines = {}
	local charge = reward.charge or 0
	if reward.chargeMinutes then
		charge += CurrencyService.minutesOfIncome(player, reward.chargeMinutes)
	end
	if charge > 0 then
		CurrencyService.addCharge(player, charge, source)
		table.insert(lines, `+{Format.short(charge)} Charge`)
	end
	if reward.tokens and reward.tokens > 0 then
		CurrencyService.addTokens(player, reward.tokens)
		table.insert(lines, `+{reward.tokens} Ascension Tokens`)
	end
	if reward.passXP and reward.passXP > 0 then
		GameEvents.PassXP:Fire(player, reward.passXP)
		table.insert(lines, `+{reward.passXP} Storm Pass XP`)
	end
	if reward.potions then
		for potionId, count in reward.potions do
			local def = Defs.Potion[potionId]
			if def then
				data.Potions[potionId] = (data.Potions[potionId] or 0) + count
				table.insert(lines, `+{count} {def.name}`)
			end
		end
		DataService.markDirty(player, "Potions")
	end
	if reward.fusionSkips and reward.fusionSkips > 0 then
		data.FusionSkips += reward.fusionSkips
		DataService.markDirty(player, "FusionSkips")
		table.insert(lines, `+{reward.fusionSkips} Fusion Skip`)
	end
	if reward.decoration then
		IslandService.grantDecoration(player, reward.decoration)
		local def = Defs.Decoration[reward.decoration]
		table.insert(lines, `Decoration: {if def then def.name else reward.decoration}`)
	end
	if reward.pet then
		PetService.givePet(player, reward.pet, source)
		local def = Defs.Pet[reward.pet]
		table.insert(lines, `Stormling: {if def then def.name else reward.pet}`)
	end
	if reward.egg then
		PetService.hatchFree(player, reward.egg, 1, source)
		local def = Defs.Egg[reward.egg]
		table.insert(lines, `Free {if def then def.name else reward.egg}!`)
	end
	if title then
		Net.Server.fire("Reward", player, "Popup", { title = title, lines = lines })
	end
	return lines
end

-- Preview "N minutes of income" for UI (Charge packs show exact amounts before purchase)
function RewardService.previewCharge(player: Player, minutes: number): number
	return CurrencyService.minutesOfIncome(player, minutes)
end

function RewardService.usePotion(player: Player, potionId: string): (boolean, string?)
	local data = DataService.get(player)
	local def = Defs.Potion[potionId]
	if not data or not def then
		return false, "Unknown potion"
	end
	if (data.Potions[potionId] or 0) <= 0 then
		return false, "You don't have that potion"
	end
	local t = now()
	local current = math.max(t, data.Boosts[def.stat] or 0)
	if current - t + def.seconds > Config.MaxBoostSeconds then
		return false, "That boost is already maxed out"
	end
	data.Potions[potionId] -= 1
	if data.Potions[potionId] <= 0 then
		data.Potions[potionId] = nil
	end
	data.Boosts[def.stat] = current + def.seconds
	DataService.markDirty(player, "Potions")
	DataService.markDirty(player, "Boosts")
	StatsService.refresh(player)
	return true
end

function RewardService.init() end

function RewardService.start()
	Net.Server.handle("UsePotion", RewardService.usePotion)
end

return RewardService
