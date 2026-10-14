--!strict
-- Server bootstrap: validate config → build the world → init() every service (no yielding)
-- → start() them (connect events, spawn loops). Order matters only for init/start.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local WorldBuilder = require(script.World.WorldBuilder)

Registry.assertValid()
Net.Server.init()
WorldBuilder.build()

local Services = script.Services
local order = {
	"DataService",
	"InventoryService",
	"RollService",
	"ZooService",
	"UpgradeService",
	"RewardService",
	"CombatService",
	"MonsterService",
	"ArenaService",
	"PlayerService",
	"DailyRewardService",
	"ShopService",
	"EventService",
	"DevService",
}

local loaded = {}
for _, name in order do
	local module = Services:FindFirstChild(name)
	if module then
		loaded[name] = (require :: any)(module)
	else
		warn(`[Boot] missing service {name}`)
	end
end
for _, name in order do
	if loaded[name] then
		loaded[name].init()
	end
end
for _, name in order do
	if loaded[name] then
		loaded[name].start()
	end
end
print(`[Boot] Roll Brainrot: Monster Arena server ready ({#order} services)`)
