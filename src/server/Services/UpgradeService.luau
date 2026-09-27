--!strict
-- Upgrade tracks: Storm Jar, Catch Rod, Storm Boots, Vacuum Nozzle, Lucky Charm.

local Shared = game:GetService("ReplicatedStorage").Shared
local Defs = require(Shared.Defs)
local EconomyMath = require(Shared.EconomyMath)
local Net = require(Shared.Net)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local UpgradeService = {}

-- Buys up to `count` levels of an upgrade. Returns (ok, levelsBought or message).
function UpgradeService.buy(player: Player, upgradeId: string, count: number?): (boolean, any)
	local data = DataService.get(player)
	local def = Defs.Upgrade[upgradeId]
	if not data or not def then
		return false, "Unknown upgrade"
	end
	local bought = 0
	for _ = 1, count or 1 do
		local level = data.Upgrades[upgradeId] or 0
		if level >= def.maxLevel then
			break
		end
		local cost = EconomyMath.upgradeCost(def, level)
		if not CurrencyService.spend(player, cost, "Upgrade", upgradeId) then
			break
		end
		data.Upgrades[upgradeId] = level + 1
		data.Stats.Upgrades += 1
		bought += 1
		GameEvents.Upgraded:Fire(player, upgradeId, level + 1)
	end
	if bought == 0 then
		local level = data.Upgrades[upgradeId] or 0
		return false, if level >= def.maxLevel then "Maxed out!" else "Not enough Charge"
	end
	DataService.markDirty(player, "Upgrades")
	DataService.markDirty(player, "Stats")
	StatsService.refresh(player)
	return true, bought
end

-- Levels granted for free at the start of each Ascension (Head Start node)
function UpgradeService.applyHeadStart(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local levels = math.floor(EconomyMath.ascStat(data.AscTree, "HeadStart"))
	for _, def in Defs.Upgrade do
		data.Upgrades[def.id] = math.min(def.maxLevel, levels)
	end
	DataService.markDirty(player, "Upgrades")
end

function UpgradeService.init() end

function UpgradeService.start()
	Net.Server.handle("BuyUpgrade", function(player: Player, upgradeId: string, count: number?)
		return UpgradeService.buy(player, upgradeId, count)
	end)
end

return UpgradeService
