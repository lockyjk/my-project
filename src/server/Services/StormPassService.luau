--!strict
-- Storm Pass: 50 tiers per 30-day season (seasons roll automatically), free + premium tracks.
-- XP from catches, hatches, quests and achievements. Premium and tier skips are Developer
-- Products (a season pass can't be a permanent Game Pass).

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local EconomyMath = require(Shared.EconomyMath)
local Net = require(Shared.Net)
local PassRewards = require(Shared.PassRewards)
local Schedule = require(Shared.Schedule)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local StormPassService = {}

local xpRemainder: { [Player]: number } = {}

local function now(): number
	return DateTime.now().UnixTimestamp
end

-- Resets progress when a new season starts. Returns the current season id ("" before S1).
local function ensureSeason(player: Player, data: Types.ProfileData): string
	local index = Schedule.passSeason(now())
	local id = if index > 0 then Schedule.passSeasonId(index) else ""
	if data.Pass.Season ~= id then
		data.Pass.Season = id
		data.Pass.XP = 0
		data.Pass.Premium = false
		data.Pass.ClaimedFree = {}
		data.Pass.ClaimedPremium = {}
		DataService.markDirty(player, "Pass")
	end
	return id
end

function StormPassService.addXP(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	if ensureSeason(player, data) == "" then
		return
	end
	-- fractional XP (catches) accumulates between calls
	local total = amount + (xpRemainder[player] or 0)
	local whole = math.floor(total)
	xpRemainder[player] = total - whole
	if whole > 0 then
		local cap = EconomyMath.passTotalXPForTier(Config.StormPass.Tiers)
		data.Pass.XP = math.min(cap, data.Pass.XP + whole)
		DataService.markDirty(player, "Pass")
	end
end

function StormPassService.claim(player: Player, tier: number, premium: boolean): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	if ensureSeason(player, data) == "" then
		return false, "The Storm Pass season hasn't started"
	end
	local reached = EconomyMath.passTier(data.Pass.XP)
	if tier < 1 or tier > Config.StormPass.Tiers or tier > reached then
		return false, "Tier not reached yet"
	end
	local key = tostring(tier)
	local claimed = if premium then data.Pass.ClaimedPremium else data.Pass.ClaimedFree
	if claimed[key] then
		return false, "Already claimed"
	end
	if premium and not data.Pass.Premium then
		return false, "Premium track is locked"
	end
	claimed[key] = true
	DataService.markDirty(player, "Pass")
	local reward = PassRewards.forTier(tier)
	RewardService.grant(player, if premium then reward.premium else reward.free, "Pass")
	return true
end

function StormPassService.claimAll(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	ensureSeason(player, data)
	local reached = EconomyMath.passTier(data.Pass.XP)
	local lines = {}
	for tier = 1, reached do
		local key = tostring(tier)
		local reward = PassRewards.forTier(tier)
		if not data.Pass.ClaimedFree[key] then
			data.Pass.ClaimedFree[key] = true
			for _, l in RewardService.grant(player, reward.free, "Pass") do
				table.insert(lines, l)
			end
		end
		if data.Pass.Premium and not data.Pass.ClaimedPremium[key] then
			data.Pass.ClaimedPremium[key] = true
			for _, l in RewardService.grant(player, reward.premium, "Pass") do
				table.insert(lines, l)
			end
		end
	end
	if #lines == 0 then
		return false, "Nothing to claim"
	end
	DataService.markDirty(player, "Pass")
	if #lines > 8 then
		local n = #lines
		lines = { table.unpack(lines, 1, 7) }
		table.insert(lines, `...and {n - 7} more`)
	end
	Net.Server.fire("Reward", player, "Popup", { title = "Storm Pass rewards!", lines = lines })
	return true
end

-- Product grants
function StormPassService.grantPremium(player: Player)
	local data = DataService.get(player)
	if data then
		ensureSeason(player, data)
		data.Pass.Premium = true
		DataService.markDirty(player, "Pass")
	end
end

function StormPassService.skipTier(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureSeason(player, data)
	local tier, into, need = EconomyMath.passTier(data.Pass.XP)
	if tier < Config.StormPass.Tiers then
		data.Pass.XP += need - into
		DataService.markDirty(player, "Pass")
	end
end

function StormPassService.init() end

function StormPassService.start()
	Net.Server.handle("ClaimPassTier", StormPassService.claim)
	Net.Server.handle("ClaimAllPass", StormPassService.claimAll)
	DataService.Loaded:Connect(function(player)
		local data = DataService.get(player)
		if data then
			ensureSeason(player, data)
		end
	end)
	GameEvents.PassXP:Connect(StormPassService.addXP)
	GameEvents.Caught:Connect(function(player)
		StormPassService.addXP(player, Config.Economy.PassXPPerCatch)
	end)
	GameEvents.Hatched:Connect(function(player, _egg, count)
		StormPassService.addXP(player, Config.Economy.PassXPPerHatch * count)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		xpRemainder[player] = nil
	end)
end

return StormPassService
