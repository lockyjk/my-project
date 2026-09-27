--!strict
-- Daily (3) and weekly (5) quests with deterministic rotation, achievements (auto-granted),
-- and the Stormling index with per-egg completion rewards.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Net = require(Shared.Net)
local QuestGen = require(Shared.QuestGen)
local Schedule = require(Shared.Schedule)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local StatsService = require(script.Parent.StatsService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local QuestService = {}

local achievementDirty: { [Player]: boolean } = {}

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function context(player: Player, data: Types.ProfileData): QuestGen.Context
	local derived = StatsService.get(player)
	local zones = {}
	for _, z in Defs.MainZones do
		if data.UnlockedZones[z.id] then
			table.insert(zones, z.id)
		end
	end
	return {
		userId = player.UserId,
		incomePerSecond = if derived then derived.IncomePerSecond else 1,
		unlockedZones = zones,
	}
end

-- Regenerate quests when a new day/week starts
function QuestService.rollover(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local t = now()
	local day, week = Schedule.dayIndex(t), Schedule.weekIndex(t)
	local changed = false
	if data.Quests.DailyDay ~= day then
		data.Quests.DailyDay = day
		data.Quests.Daily = QuestGen.generate(day, true, context(player, data))
		changed = true
	end
	if data.Quests.WeeklyWeek ~= week then
		data.Quests.WeeklyWeek = week
		data.Quests.Weekly = QuestGen.generate(week, false, context(player, data))
		changed = true
	end
	if changed then
		DataService.markDirty(player, "Quests")
	end
end

local function progress(player: Player, kind: string, amount: number, zone: string?)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	local changed = false
	for _, list in { data.Quests.Daily, data.Quests.Weekly } do
		for _, q in list do
			local template = Defs.Quest[q.template]
			if template and not q.claimed and q.progress < q.target then
				local add = QuestGen.progressFor(template, q, kind, amount, zone)
				if add > 0 then
					q.progress = math.min(q.target, q.progress + add)
					changed = true
				end
			end
		end
	end
	if changed then
		DataService.markDirty(player, "Quests")
	end
end
QuestService.progress = progress

function QuestService.claim(player: Player, which: string, index: number): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	QuestService.rollover(player)
	local list = if which == "Daily" then data.Quests.Daily else data.Quests.Weekly
	local q = list[index]
	if not q then
		return false, "Unknown quest"
	end
	if q.claimed then
		return false, "Already claimed"
	end
	if q.progress < q.target then
		return false, "Not finished yet"
	end
	q.claimed = true
	DataService.markDirty(player, "Quests")
	local template = Defs.Quest[q.template]
	RewardService.grant(player, template.reward, "Quest", "Quest complete!")
	return true
end

-------------------------------------------------------------------------------
-- Achievements
-------------------------------------------------------------------------------

function QuestService.statValue(data: Types.ProfileData, stat: string): number
	if stat == "Ascensions" then
		return data.Ascensions
	elseif stat == "LifetimeCharge" then
		return data.LifetimeCharge
	elseif stat == "ZonesUnlocked" then
		local n = 0
		for _, z in Defs.MainZones do
			if data.UnlockedZones[z.id] then
				n += 1
			end
		end
		return n
	end
	return data.Stats[stat] or 0
end

local function checkAchievements(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, a in Config.Achievements do
		if not data.Achievements[a.id] and QuestService.statValue(data, a.stat) >= a.target then
			data.Achievements[a.id] = true
			DataService.markDirty(player, "Achievements")
			RewardService.grant(player, a.reward, "Achievement", `Achievement: {a.name}`)
		end
	end
end

-------------------------------------------------------------------------------
-- Index
-------------------------------------------------------------------------------

local function checkIndex(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, egg in Config.Eggs do
		if egg.currency ~= "Robux" and not data.IndexRewards[egg.id] then
			local complete = true
			for _, entry in egg.pets do
				if not data.Index[entry.pet] then
					complete = false
					break
				end
			end
			if complete then
				data.IndexRewards[egg.id] = true
				DataService.markDirty(player, "IndexRewards")
				StatsService.refresh(player)
				RewardService.grant(player, Config.Index.CompletionReward, "Index", `{egg.name} collection complete! +{math.floor(Config.Index.ChargeBonusPerEgg * 100)}% Charge forever`)
			end
		end
	end
end

-------------------------------------------------------------------------------

function QuestService.init() end

function QuestService.start()
	Net.Server.handle("ClaimQuest", QuestService.claim)

	DataService.Loaded:Connect(function(player)
		task.defer(function()
			QuestService.rollover(player)
			checkAchievements(player)
			checkIndex(player)
		end)
	end)

	local function mark(player: Player)
		achievementDirty[player] = true
	end

	GameEvents.Caught:Connect(function(player, _spiritId, zoneId, shiny, _amount, isStorm)
		progress(player, "Catch", 1, zoneId)
		if shiny then
			progress(player, "CatchShiny", 1)
		end
		if isStorm then
			progress(player, "CatchStorm", 1)
		end
		mark(player)
	end)
	GameEvents.Hatched:Connect(function(player, _eggId, count)
		progress(player, "Hatch", count)
		mark(player)
		task.defer(checkIndex, player)
	end)
	GameEvents.PetObtained:Connect(function(player)
		task.defer(checkIndex, player)
	end)
	GameEvents.FusionStarted:Connect(function(player)
		progress(player, "Fuse", 1)
		mark(player)
	end)
	GameEvents.ChargeEarned:Connect(function(player, amount, source)
		-- Rewards and purchases don't count toward "Earn" quests (no pay-to-complete)
		if source ~= "Quest" and source ~= "Product" and source ~= "Achievement" and source ~= "Index" then
			progress(player, "Earn", amount)
		end
		mark(player)
	end)
	GameEvents.Sold:Connect(function(player)
		progress(player, "Sell", 1)
	end)
	GameEvents.Upgraded:Connect(function(player)
		progress(player, "Upgrade", 1)
	end)
	GameEvents.Ascended:Connect(mark)
	GameEvents.ZoneUnlocked:Connect(mark)
	GameEvents.Traded:Connect(mark)
	GameEvents.DecorationPlaced:Connect(mark)

	Players.PlayerRemoving:Connect(function(player)
		achievementDirty[player] = nil
	end)

	-- Achievements are checked at most every 2s per player; play-time quests tick each minute
	task.spawn(function()
		local minuteAcc = 0
		while true do
			task.wait(2)
			for player in achievementDirty do
				achievementDirty[player] = nil
				checkAchievements(player)
			end
			minuteAcc += 2
			if minuteAcc >= 60 then
				minuteAcc = 0
				for _, player in Players:GetPlayers() do
					if DataService.isLoaded(player) then
						QuestService.rollover(player)
						progress(player, "PlayMinutes", 1)
					end
				end
			end
		end
	end)
end

return QuestService
