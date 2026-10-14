--!strict
-- 7-day login reward cycle. Claim once every CooldownHours; missing a day by more than
-- GraceHours restarts the streak at day 1. Day 7 loops back to day 1.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local Types = require(Modules.Types)
local DataService = require(script.Parent.DataService)
local RollService = require(script.Parent.RollService)

local DailyRewardService = {}

local D = GameConfig.Daily

local function now(): number
	return DateTime.now().UnixTimestamp
end

-- Which day (1..7) the next claim gives, and whether it can be claimed now
function DailyRewardService.status(data: Types.PlayerData): (number, boolean, number)
	local t = now()
	local since = t - data.daily.last
	local day = data.daily.day
	if data.daily.last == 0 or since > D.GraceHours * 3600 then
		day = 0 -- streak lost (or first time)
	end
	local nextDay = day % #D.Rewards + 1
	local ready = data.daily.last == 0 or since >= D.CooldownHours * 3600
	local wait = if ready then 0 else D.CooldownHours * 3600 - since
	return nextDay, ready, wait
end

function DailyRewardService.claim(player: Player): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "Loading…"
	end
	local day, ready = DailyRewardService.status(data)
	if not ready then
		return false, "Come back later!"
	end
	local reward = D.Rewards[day]
	local text = reward.label
	if reward.kind == "coins" then
		DataService.add(player, "coins", reward.amount)
	elseif reward.kind == "gems" then
		DataService.add(player, "gems", reward.amount)
	elseif reward.kind == "tokens" then
		DataService.add(player, "tokens", reward.amount)
	elseif reward.kind == "boost" then
		DataService.addBoost(player, reward.boost, reward.minutes)
	elseif reward.kind == "brainrot" then
		local _, id = RollService.grantOfRarity(player, reward.rarity, reward.mutation)
		if id then
			text = `{reward.label}: {Registry.displayName(id, reward.mutation)}!`
		end
	end
	data.daily.day = day
	data.daily.last = now()
	DataService.push(player, "daily")
	Net.Server.fire("Reward", player, `📅 DAY {day} REWARD`, { text })
	return true, day
end

function DailyRewardService.init() end

function DailyRewardService.start()
	Net.Server.handle("ClaimDaily", function(player: Player)
		return DailyRewardService.claim(player)
	end)
	DataService.Loaded:Connect(function(player: Player, data: Types.PlayerData)
		local _, ready = DailyRewardService.status(data)
		if ready then
			task.delay(6, function()
				if player.Parent then
					Net.Server.fire("Notify", player, "📅 Your daily reward is ready! Visit the Daily Rewards stand.", Color3.fromRGB(90, 180, 255))
				end
			end)
		end
	end)
end

return DailyRewardService
