--!strict
-- Funnel, economy, progression and retention analytics via Roblox AnalyticsService.
-- Everything is pcall-wrapped: analytics must never break gameplay.
--   Onboarding funnel: Joined -> FirstCatch -> FirstSell -> FirstUpgrade -> TutorialDone
--   Economy: Charge sources/sinks, batched per player per minute (keeps event volume low)
--   Progression: zone unlocks, Ascensions
--   Custom: FirstPurchase, Purchase, SessionLength, RetentionD1, RetentionD7, StormCatch

local Players = game:GetService("Players")
local RobloxAnalytics = game:GetService("AnalyticsService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Defs = require(Shared.Defs)
local Schedule = require(Shared.Schedule)

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local AnalyticsService = {}

local FUNNEL = { "Joined", "FirstCatch", "FirstSell", "FirstUpgrade", "TutorialDone" }

type Bucket = { [string]: number } -- "Source|Sell" -> amount
local pending: { [Player]: Bucket } = {}

local function safe(fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		warn("[Analytics]", err)
	end
end

local function funnel(player: Player, step: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local flag = `Funnel{step}`
	if data.Flags[flag] then
		return
	end
	data.Flags[flag] = true
	DataService.markDirty(player, "Flags")
	safe(function()
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, FUNNEL[step])
	end)
end

local function custom(player: Player, name: string, value: number?)
	safe(function()
		RobloxAnalytics:LogCustomEvent(player, name, value or 1)
	end)
end

local function addEconomy(player: Player, flow: string, source: string, amount: number)
	local bucket = pending[player]
	if not bucket then
		bucket = {}
		pending[player] = bucket
	end
	local key = `{flow}|{source}`
	bucket[key] = (bucket[key] or 0) + amount
end

local TRANSACTION: { [string]: Enum.AnalyticsEconomyTransactionType } = {
	Sell = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Quest = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Achievement = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Offline = Enum.AnalyticsEconomyTransactionType.TimedReward,
	Gift = Enum.AnalyticsEconomyTransactionType.TimedReward,
	Daily = Enum.AnalyticsEconomyTransactionType.TimedReward,
	Tutorial = Enum.AnalyticsEconomyTransactionType.Onboarding,
	Product = Enum.AnalyticsEconomyTransactionType.IAP,
	Upgrade = Enum.AnalyticsEconomyTransactionType.Shop,
	Egg = Enum.AnalyticsEconomyTransactionType.Shop,
	Gate = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Decoration = Enum.AnalyticsEconomyTransactionType.Shop,
	Island = Enum.AnalyticsEconomyTransactionType.Shop,
	Ascension = Enum.AnalyticsEconomyTransactionType.Gameplay,
}

local function flush(player: Player)
	local bucket = pending[player]
	local data = DataService.get(player)
	pending[player] = nil
	if not bucket or not data then
		return
	end
	for key, amount in bucket do
		local flow, source = string.match(key, "^(%a+)|(.+)$")
		if flow and source and amount > 0 then
			safe(function()
				RobloxAnalytics:LogEconomyEvent(
					player,
					if flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
					"Charge",
					math.floor(amount),
					math.floor(data.Charge),
					(TRANSACTION[source] or Enum.AnalyticsEconomyTransactionType.Gameplay).Name,
					source
				)
			end)
		end
	end
end

local function retention(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local today = Schedule.dayIndex(DateTime.now().UnixTimestamp)
	local firstDay = Schedule.dayIndex(data.FirstJoin)
	local daysSince = today - firstDay
	for _, marker in { 1, 7 } do
		local flag = `RetentionD{marker}`
		if daysSince == marker and not data.Flags[flag] then
			data.Flags[flag] = true
			DataService.markDirty(player, "Flags")
			custom(player, flag)
		end
	end
end

function AnalyticsService.init() end

function AnalyticsService.start()
	DataService.Loaded:Connect(function(player)
		funnel(player, 1)
		retention(player)
	end)
	DataService.Removing:Connect(function(player)
		flush(player)
		local session = DataService.session(player)
		if session then
			custom(player, "SessionLength", math.floor(os.clock() - session.JoinClock))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)

	GameEvents.Caught:Connect(function(player, _spirit, _zone, _shiny, _amount, isStorm)
		funnel(player, 2)
		if isStorm then
			local data = DataService.get(player)
			if data and data.Stats.StormCatches == 1 then
				custom(player, "FirstStormCatch")
			end
		end
	end)
	GameEvents.Sold:Connect(function(player)
		funnel(player, 3)
	end)
	GameEvents.Upgraded:Connect(function(player)
		funnel(player, 4)
	end)
	GameEvents.Tutorial:Connect(function(player, step)
		if step >= 4 then
			funnel(player, 5)
		end
	end)
	GameEvents.ChargeEarned:Connect(function(player, amount, source)
		addEconomy(player, "Source", source, amount)
	end)
	GameEvents.ChargeSpent:Connect(function(player, amount, sink)
		addEconomy(player, "Sink", sink, amount)
	end)
	GameEvents.ZoneUnlocked:Connect(function(player, zoneId)
		local zone = Defs.Zone[zoneId]
		safe(function()
			RobloxAnalytics:LogProgressionCompleteEvent(player, "Zones", zone.index, zone.name)
		end)
	end)
	GameEvents.Ascended:Connect(function(player, count)
		safe(function()
			RobloxAnalytics:LogProgressionCompleteEvent(player, "Ascension", count, `Ascension {count}`)
		end)
	end)
	GameEvents.Purchased:Connect(function(player, key, robux)
		local data = DataService.get(player)
		if data and not data.Flags.FirstPurchaseLogged then
			data.Flags.FirstPurchaseLogged = true
			DataService.markDirty(player, "Flags")
			custom(player, "FirstPurchase", robux)
		end
		custom(player, `Purchase_{key}`, robux)
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				flush(player)
			end
		end
	end)
end

return AnalyticsService
