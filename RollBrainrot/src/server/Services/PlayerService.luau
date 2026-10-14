--!strict
-- Characters (health from level + Trainer Power), quick-travel teleports and settings.

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local UpgradeService = require(script.Parent.UpgradeService)
local ZooPlotBuilder = require(script.Parent.Parent.World.ZooPlotBuilder)
local ZooService = require(script.Parent.ZooService)

local PlayerService = {}

local W = GameConfig.World

function PlayerService.refreshHealth(player: Player)
	local data = DataService.get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not data or not hum then
		return
	end
	local power = BrainrotMath.upgradeValue(GameConfig.Upgrades.TrainerPower, data.upgrades.TrainerPower or 0)
	local maxHp = BrainrotMath.playerMaxHealth(data.level, power)
	local frac = if hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
	hum.MaxHealth = maxHp
	hum.Health = maxHp * math.clamp(frac, 0, 1)
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	DataService.await(player, 30)
	if player.Character ~= char then
		return
	end
	PlayerService.refreshHealth(player)
	hum.Health = hum.MaxHealth
	-- VIP gold name
	local data = DataService.get(player)
	if data and data.passes.VIP then
		hum.DisplayName = `👑 {player.DisplayName}`
	end
end

-- Quick travel (HUD buttons). Not allowed mid-battle: leave the arena first.
local SETTINGS =
	{ music = "boolean", sfx = "boolean", skipRoll = "boolean", autoRoll = "boolean", seenRollAnim = "boolean" }

function PlayerService.teleport(player: Player, where: string): (boolean, string?)
	if CombatService.battleOf(player) then
		return false, "Leave the battle first!"
	end
	local char = player.Character
	if not char then
		return false, nil
	end
	local target: CFrame
	if where == "Zoo" then
		local index = ZooService.plotOf(player)
		if not index then
			return false, "You don't have a zoo yet"
		end
		local plotCf = ZooPlotBuilder.plotCFrame(index)
		local pos = (plotCf * CFrame.new(0, 4, -W.PlotSize.Y / 2 + 6)).Position
		target = CFrame.lookAt(pos, (plotCf * CFrame.new(0, 4, 0)).Position)
	elseif where == "Arena" then
		target = CFrame.lookAt(W.ArenaGate, Vector3.new(0, W.ArenaGate.Y, W.Arena.center.Z))
	elseif where == "Machine" then
		local p = W.Machine + Vector3.new(0, 4, 48)
		target = CFrame.lookAt(p, W.Machine + Vector3.new(0, 4, 0))
	else
		target = CFrame.lookAt(W.Spawn, W.Machine + Vector3.new(0, W.Spawn.Y, 0))
	end
	char:PivotTo(target)
	return true
end

function PlayerService.init() end

function PlayerService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	RewardService.LevelUp:Connect(function(player: Player)
		PlayerService.refreshHealth(player)
	end)
	UpgradeService.Bought:Connect(function(player: Player, id: string)
		if id == "TrainerPower" then
			PlayerService.refreshHealth(player)
		end
	end)

	Net.Server.handle("TeleportTo", function(player: Player, where: string)
		return PlayerService.teleport(player, where)
	end)
	Net.Server.handle("SetSetting", function(player: Player, key: string, value: any)
		local data = DataService.get(player)
		local kind = SETTINGS[key]
		if not data or not kind or type(value) ~= kind then
			return false
		end
		if key == "seenRollAnim" then
			data.seenRollAnim = value
			DataService.push(player, "seenRollAnim")
			return true
		end
		if key == "autoRoll" and value and not data.passes.AutoRoll then
			return false, "Auto Roll is a Game Pass"
		end
		data.settings[key] = value
		DataService.push(player, "settings")
		return true
	end)
end

return PlayerService
