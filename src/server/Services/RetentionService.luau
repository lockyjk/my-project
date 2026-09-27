--!strict
-- Daily login streak, session gifts, offline earnings, Premium daily gift, group reward,
-- friend boost and Premium membership tracking.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Schedule = require(Shared.Schedule)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local StatsService = require(script.Parent.StatsService)

local RetentionService = {}

local friendCache: { [string]: boolean } = {}

local function now(): number
	return DateTime.now().UnixTimestamp
end

-------------------------------------------------------------------------------
-- Daily streak
-------------------------------------------------------------------------------

-- Returns (canClaim, streakIfClaimedToday)
function RetentionService.streakState(lastClaimDay: number, streak: number, today: number): (boolean, number)
	if lastClaimDay == today then
		return false, streak
	end
	if lastClaimDay == today - 1 then
		return true, streak + 1
	end
	return true, 1
end

function RetentionService.claimDaily(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	local today = Schedule.dayIndex(now())
	local can, streak = RetentionService.streakState(data.Daily.LastClaimDay, data.Daily.Streak, today)
	if not can then
		return false, "Come back tomorrow for your next reward!"
	end
	data.Daily.Streak = streak
	data.Daily.LastClaimDay = today
	DataService.markDirty(player, "Daily")
	local rewards = Config.DailyStreak.Rewards
	local dayInCycle = (streak - 1) % #rewards + 1
	RewardService.grant(player, rewards[dayInCycle], "Daily", `Day {streak} streak reward!`)
	return true
end

-------------------------------------------------------------------------------
-- Session gifts
-------------------------------------------------------------------------------

local function pushGifts(player: Player)
	local session = DataService.session(player)
	if session then
		local claimed = {}
		for i in session.GiftsClaimed do
			table.insert(claimed, i)
		end
		DataService.pushSession(player, "Gifts", { joinUnix = session.JoinUnix, claimed = claimed })
	end
end

function RetentionService.claimGift(player: Player, index: number): (boolean, string?)
	local session = DataService.session(player)
	local gift = Config.Gifts[index]
	if not session or not gift then
		return false, "Unknown gift"
	end
	if session.GiftsClaimed[index] then
		return false, "Already opened"
	end
	if os.clock() - session.JoinClock < gift.minutes * 60 then
		return false, "Not ready yet"
	end
	session.GiftsClaimed[index] = true
	pushGifts(player)
	RewardService.grant(player, gift.reward, "Gift", `{gift.minutes}-minute gift!`)
	return true
end

-------------------------------------------------------------------------------
-- Offline earnings / Premium / group
-------------------------------------------------------------------------------

local function offlineEarnings(player: Player)
	local data = DataService.get(player)
	local derived = StatsService.get(player)
	if not data or not derived then
		return
	end
	local t = now()
	if data.LastLogout > 0 then
		local away = t - data.LastLogout
		local amount = EconomyMath.offlineEarnings(away, derived.IncomePerSecond, derived.OfflineHours)
		if amount > 0 then
			CurrencyService.addCharge(player, amount, "Offline")
			local lines = {
				`Your island kept charging for {Format.duration(math.min(away, derived.OfflineHours * 3600))}`,
				`+{Format.short(amount)} Charge`,
			}
			if away > derived.OfflineHours * 3600 then
				table.insert(lines, `(max {derived.OfflineHours}h - Rain Barrels store more!)`)
			end
			Net.Server.fire("Reward", player, "Popup", { title = "While you were away...", lines = lines })
		end
	end
	data.LastLogin = t
end

function RetentionService.claimPremiumDaily(player: Player): (boolean, string?)
	local data = DataService.get(player)
	local session = DataService.session(player)
	if not data or not session then
		return false
	end
	if not session.Premium then
		return false, "This gift is for Roblox Premium members"
	end
	local today = Schedule.dayIndex(now())
	if data.Daily.PremiumDay == today then
		return false, "Already claimed today"
	end
	data.Daily.PremiumDay = today
	DataService.markDirty(player, "Daily")
	RewardService.grant(player, Config.Premium.DailyReward, "Premium", "Premium daily gift!")
	return true
end

function RetentionService.claimGroup(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	if data.Flags.GroupClaimed then
		return false, "Already claimed - thanks for joining!"
	end
	if Config.Group.GroupId == 0 then
		return false, "Group reward isn't set up yet"
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroupAsync(Config.Group.GroupId)
	end)
	if not ok or not inGroup then
		return false, "Join our group, then come back to claim!"
	end
	data.Flags.GroupClaimed = true
	DataService.markDirty(player, "Flags")
	RewardService.grant(player, Config.Group.Reward, "Group", "Thanks for joining the group!")
	return true
end

-------------------------------------------------------------------------------
-- Friend boost
-------------------------------------------------------------------------------

local function areFriends(a: Player, b: Player): boolean
	local key = if a.UserId < b.UserId then `{a.UserId}_{b.UserId}` else `{b.UserId}_{a.UserId}`
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	local value = ok and result == true
	friendCache[key] = value
	return value
end

local function refreshFriends()
	local players = Players:GetPlayers()
	for _, p in players do
		local session = DataService.session(p)
		if session then
			local friends = 0
			for _, other in players do
				if other ~= p and areFriends(p, other) then
					friends += 1
				end
			end
			local boost = math.min(friends, Config.FriendBoost.MaxFriends) * Config.FriendBoost.PerFriend
			if boost ~= session.FriendBoost then
				session.FriendBoost = boost
				StatsService.refresh(p)
			end
			DataService.pushSession(p, "Friends", friends)
		end
	end
end

-------------------------------------------------------------------------------

function RetentionService.init() end

function RetentionService.start()
	Net.Server.handle("ClaimDaily", RetentionService.claimDaily)
	Net.Server.handle("ClaimGift", RetentionService.claimGift)
	Net.Server.handle("ClaimPremiumDaily", RetentionService.claimPremiumDaily)
	Net.Server.handle("ClaimGroupReward", RetentionService.claimGroup)

	DataService.Loaded:Connect(function(player)
		pushGifts(player)
		offlineEarnings(player)
		local session = DataService.session(player)
		if session then
			DataService.pushSession(player, "Premium", session.Premium)
		end
		task.spawn(refreshFriends)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshFriends)
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		local session = DataService.session(player)
		if session then
			session.Premium = player.MembershipType == Enum.MembershipType.Premium
			DataService.pushSession(player, "Premium", session.Premium)
			StatsService.refresh(player)
		end
	end)
end

return RetentionService
