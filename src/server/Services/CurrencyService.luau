--!strict
-- The only place Charge, Static and Tokens change. Server authoritative.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local CurrencyService = {}

local function sanitize(amount: number): number
	if amount ~= amount or amount == math.huge or amount < 0 then
		return 0
	end
	return math.floor(amount)
end

function CurrencyService.addCharge(player: Player, amount: number, source: string): number
	local data = DataService.get(player)
	amount = sanitize(amount)
	if not data or amount <= 0 then
		return 0
	end
	data.Charge += amount
	data.LifetimeCharge += amount
	DataService.markDirty(player, "Charge")
	DataService.markDirty(player, "LifetimeCharge")
	GameEvents.ChargeEarned:Fire(player, amount, source)
	return amount
end

function CurrencyService.canAfford(player: Player, amount: number): boolean
	local data = DataService.get(player)
	return data ~= nil and data.Charge >= amount
end

-- Returns true if the Charge was spent
function CurrencyService.spend(player: Player, amount: number, sink: string, item: string): boolean
	local data = DataService.get(player)
	amount = sanitize(amount)
	if not data or data.Charge < amount then
		return false
	end
	data.Charge -= amount
	DataService.markDirty(player, "Charge")
	GameEvents.ChargeSpent:Fire(player, amount, sink, item)
	return true
end

function CurrencyService.addTokens(player: Player, amount: number)
	local data = DataService.get(player)
	amount = sanitize(amount)
	if not data or amount <= 0 then
		return
	end
	data.Tokens += amount
	DataService.markDirty(player, "Tokens")
end

-- Adds Static to the jar, clamped to capacity. Returns the amount actually stored.
function CurrencyService.addStatic(player: Player, amount: number): number
	local data = DataService.get(player)
	local derived = StatsService.get(player)
	if not data or not derived then
		return 0
	end
	local room = math.max(0, derived.Capacity - data.Static)
	local stored = math.min(room, sanitize(amount))
	data.Static += stored
	DataService.markDirty(player, "Static")
	return stored
end

function CurrencyService.jarFull(player: Player): boolean
	local data = DataService.get(player)
	local derived = StatsService.get(player)
	return data ~= nil and derived ~= nil and data.Static >= derived.Capacity
end

-- Converts the jar into Charge
function CurrencyService.sell(player: Player): number
	local data = DataService.get(player)
	if not data or data.Static <= 0 then
		return 0
	end
	local amount = math.floor(data.Static * Config.Economy.SellRate)
	data.Static = 0
	data.Stats.Sold += 1
	DataService.markDirty(player, "Static")
	DataService.markDirty(player, "Stats")
	CurrencyService.addCharge(player, amount, "Sell")
	Net.Server.fire("Notify", player, "Sell", amount)
	GameEvents.Sold:Fire(player, amount)
	return amount
end

-- Charge equal to N minutes of this player's steady income (quests, gifts, packs)
function CurrencyService.minutesOfIncome(player: Player, minutes: number): number
	local derived = StatsService.get(player)
	if not derived then
		return 0
	end
	return math.max(10, math.floor(derived.IncomePerSecond * 60 * minutes))
end

function CurrencyService.init() end
function CurrencyService.start() end

return CurrencyService
