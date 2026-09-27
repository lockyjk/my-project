--!strict
-- Server bootstrap: build the world, then init() every service (no yielding, no cross-calls),
-- then start() them (connect events, spawn loops). Order matters only for init.

local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local WorldBuilder = require(script.World.WorldBuilder)

local Services = script.Services
local order = {
	"DataService",
	"WeatherEventService",
	"StatsService",
	"CurrencyService",
	"UpgradeService",
	"ZoneService",
	"IslandService",
	"PetService",
	"RewardService",
	"RebirthService",
	"TutorialService",
}

Net.Server.init()
WorldBuilder.build()

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
print(`[Boot] Storm Chaser Simulator server ready ({#order} services)`)
