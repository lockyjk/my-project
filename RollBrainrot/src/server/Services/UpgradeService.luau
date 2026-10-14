--!strict
-- Permanent upgrades bought at the UPGRADES stand (all data-driven from GameConfig.Upgrades).

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local Format = require(Modules.Format)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Signal = require(Modules.Signal)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local UpgradeService = {}

UpgradeService.Bought = Signal.new() :: Signal.Signal<Player, string, number>

function UpgradeService.buy(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	local def = GameConfig.Upgrades[id]
	if not data or not def then
		return false, "Unknown upgrade"
	end
	local level = data.upgrades[id] or 0
	local cost = BrainrotMath.upgradeCost(def, level)
	if not cost then
		return false, "Maxed out!"
	end
	if not DataService.spend(player, def.currency, cost) then
		return false, `Need {Format.short(cost)} {def.currency}`
	end
	data.upgrades[id] = level + 1
	DataService.push(player, "upgrades")
	UpgradeService.Bought:Fire(player, id, level + 1)
	if id == "EquipSlots" or id == "TrainerPower" then
		InventoryService.publish(player)
	end
	return true
end

function UpgradeService.init() end

function UpgradeService.start()
	Net.Server.handle("BuyUpgrade", function(player: Player, id: string)
		return UpgradeService.buy(player, id)
	end)
end

return UpgradeService
