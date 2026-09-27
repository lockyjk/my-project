--!strict
-- Testing commands, only in Studio or for Config.Security.AdminUserIds:
--   /charge <n>   /tokens <n>   /storm <Thunderstorm|Blizzard|Aurora|Tornado|off>
--   /pass <Key>   /unlockall    /pet <PetId> [tier]    /potion <PotionId>

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Net = require(Shared.Net)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)
local RewardService = require(script.Parent.RewardService)
local ShopService = require(script.Parent.ShopService)
local StatsService = require(script.Parent.StatsService)
local WeatherEventService = require(script.Parent.WeatherEventService)

local DevService = {}

local function allowed(player: Player): boolean
	return RunService:IsStudio() or table.find(Config.Security.AdminUserIds, player.UserId) ~= nil
end

local function run(player: Player, message: string)
	local args = string.split(message, " ")
	local cmd = string.lower(args[1])
	local data = DataService.get(player)
	if not data then
		return
	end
	if cmd == "/charge" then
		CurrencyService.addCharge(player, tonumber(args[2]) or 1e6, "Dev")
	elseif cmd == "/tokens" then
		CurrencyService.addTokens(player, tonumber(args[2]) or 10)
	elseif cmd == "/storm" then
		local id = args[2]
		if id == "off" then
			WeatherEventService.forceStorm(nil, 0)
		elseif id and Defs.Storm[id] then
			WeatherEventService.forceStorm(id, Config.Weather.ActiveSeconds)
		end
	elseif cmd == "/pass" and args[2] then
		ShopService.setPass(player, args[2], true)
	elseif cmd == "/unlockall" then
		for _, z in Defs.MainZones do
			data.UnlockedZones[z.id] = true
		end
		DataService.markDirty(player, "UnlockedZones")
		StatsService.refresh(player)
	elseif cmd == "/pet" and args[2] and Defs.Pet[args[2]] then
		PetService.givePet(player, args[2], "Dev", tonumber(args[3]) or 1)
	elseif cmd == "/potion" and args[2] and Defs.Potion[args[2]] then
		RewardService.grant(player, { potions = { [args[2]] = 1 } }, "Dev")
	else
		return
	end
	Net.Server.fire("Notify", player, "Info", `Dev: {message}`)
end

function DevService.init() end

function DevService.start()
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			if allowed(player) and string.sub(message, 1, 1) == "/" then
				run(player, message)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return DevService
