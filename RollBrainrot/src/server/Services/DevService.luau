--!strict
-- Chat test commands for admins (place owner, Studio, or GameConfig.Security.AdminUserIds):
--   /coins 1e6   /gems 500   /tokens 50   /essence 999   /level 20
--   /give CosmocornoBrainrot Rainbow   /event GiantInvasion   /unlockarenas

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local InventoryService = require(script.Parent.InventoryService)

local DevService = {}

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(GameConfig.Security.AdminUserIds, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

local function run(player: Player, text: string)
	local args = string.split(text, " ")
	local cmd = string.lower(args[1] or "")
	local data = DataService.get(player)
	if not data then
		return
	end
	local n = tonumber(args[2])
	if (cmd == "/coins" or cmd == "/gems" or cmd == "/tokens" or cmd == "/essence") and n then
		DataService.add(player, string.sub(cmd, 2) :: any, n)
	elseif cmd == "/level" and n then
		data.level = math.clamp(math.floor(n), 1, GameConfig.Player.MaxLevel)
		data.xp = 0
		DataService.push(player, "level", "xp")
		InventoryService.publish(player)
	elseif cmd == "/give" and args[2] and Registry.Brainrot[args[2]] then
		InventoryService.add(player, args[2], args[3] or "Normal")
	elseif cmd == "/event" and args[2] then
		EventService.force(args[2], true)
	elseif cmd == "/unlockarenas" then
		for _, a in Registry.Arenas do
			data.arena.beaten[a.id] = true
		end
		data.level = math.max(data.level, 50)
		DataService.push(player, "arena", "level")
	else
		return
	end
	Net.Server.fire("Notify", player, `[dev] {text}`)
end

function DevService.init() end

function DevService.start()
	local function hook(player: Player)
		player.Chatted:Connect(function(msg)
			if string.sub(msg, 1, 1) == "/" and isAdmin(player) then
				run(player, msg)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return DevService
