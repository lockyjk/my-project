--!strict
-- First-time tutorial (catch -> sell -> upgrade, < 60 s) and player settings.
-- Client drives the on-screen steps; the server only records progress, grants the one-time
-- bonus after the first sell, and logs the onboarding funnel.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local TutorialService = {}

-- Steps: 1 catch, 2 go home & sell, 3 buy upgrade, 4 done
TutorialService.Steps = { Catch = 1, Sell = 2, Upgrade = 3, Done = 4 }

local SETTINGS: { [string]: string } = {
	Music = "boolean",
	Sfx = "boolean",
	AutoCatch = "boolean",
	HidePets = "boolean",
}

local function complete(player: Player)
	local data = DataService.get(player)
	if data and not data.Flags.TutorialDone then
		data.Flags.TutorialDone = true
		DataService.markDirty(player, "Flags")
		GameEvents.Tutorial:Fire(player, TutorialService.Steps.Done)
	end
end

function TutorialService.init() end

function TutorialService.start()
	Net.Server.on("TutorialStep", function(player: Player, step: number)
		local data = DataService.get(player)
		if not data or data.Flags.TutorialDone then
			return
		end
		if step >= TutorialService.Steps.Done then
			complete(player)
		else
			GameEvents.Tutorial:Fire(player, step)
		end
	end)

	-- One-time bonus after the very first sell so the first upgrade is affordable immediately
	GameEvents.Sold:Connect(function(player: Player)
		local data = DataService.get(player)
		if data and not data.Flags.TutorialBonus then
			data.Flags.TutorialBonus = true
			DataService.markDirty(player, "Flags")
			CurrencyService.addCharge(player, Config.Tutorial.BonusCharge, "Tutorial")
			Net.Server.fire("Notify", player, "Info", `Tutorial bonus: +{Config.Tutorial.BonusCharge} Charge!`)
		end
	end)
	GameEvents.Upgraded:Connect(function(player: Player)
		local data = DataService.get(player)
		if data and not data.Flags.TutorialDone and data.Flags.TutorialBonus then
			complete(player)
		end
	end)

	Net.Server.handle("SetSetting", function(player: Player, key: string, value: any)
		local data = DataService.get(player)
		local kind = SETTINGS[key]
		if not data or not kind or type(value) ~= kind then
			-- AutoDelete.<Rarity> toggles
			local rarity = string.match(key, "^AutoDelete%.(%a+)$")
			if data and rarity and type(value) == "boolean" and rarity ~= "Legendary" and rarity ~= "Mythic" and rarity ~= "Secret" then
				data.Settings.AutoDelete[rarity] = value
				DataService.markDirty(player, "Settings")
				return true
			end
			return false, "Invalid setting"
		end
		(data.Settings :: any)[key] = value
		DataService.markDirty(player, "Settings")
		return true
	end)
end

return TutorialService
