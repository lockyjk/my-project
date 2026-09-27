--!strict
-- Storm Pass reward table: explicit milestones from Config, generated rewards elsewhere.
-- The same function drives the server (claims) and the UI (preview), so they always match.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local PassRewards = {}

function PassRewards.forTier(tier: number): Types.PassTierReward
	local milestone = Config.StormPass.Milestones[tier]
	if milestone then
		return milestone
	end
	local free: Types.Reward
	if tier % 5 == 0 then
		free = { potions = { LuckPotion = 1 } }
	elseif tier % 3 == 0 then
		free = { potions = { SpeedPotion = 1 } }
	else
		free = { chargeMinutes = 3 + math.floor(tier / 10) }
	end
	local premium: Types.Reward = { chargeMinutes = 6 + math.floor(tier / 5) }
	if tier % 4 == 0 then
		premium.potions = { ChargePotion = 1 }
	end
	if tier % 7 == 0 then
		premium.fusionSkips = 1
	end
	if tier % 12 == 0 then
		premium.tokens = 1
	end
	return { free = free, premium = premium }
end

return PassRewards
