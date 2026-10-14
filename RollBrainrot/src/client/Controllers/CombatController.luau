--!strict
-- Player abilities while fighting: Attack (click / R2 / button), Dodge (Q / B), Heal (E),
-- Rally (R), Ultimate (F, needs charge). The server validates every action and its
-- cooldown; the client predicts cooldowns for snappy buttons and applies the dodge dash
-- (the player's own character physics are client-owned).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Net = require(Modules:WaitForChild("Net"))
local Signal = require(Modules:WaitForChild("Signal"))

local Effects = require(script.Parent.Effects)

local CombatController = {}

local PA = GameConfig.PlayerAbilities
local player = Players.LocalPlayer

local cooldownUntil: { [string]: number } = {}
CombatController.charge = 0
CombatController.chargeNeeded = PA.Ultimate.chargeNeeded
CombatController.Used = Signal.new() :: Signal.Signal<string>

CombatController.ORDER = { "Attack", "Dodge", "Heal", "Rally", "Ultimate" }

function CombatController.inBattle(): boolean
	return player:GetAttribute("BattleId") ~= nil
end

function CombatController.cooldownLeft(name: string): number
	return math.max(0, (cooldownUntil[name] or 0) - os.clock())
end

-- Server HUD pushes the authoritative cooldowns/charge; keep predictions in sync
function CombatController.sync(cooldowns: { [string]: number }?, charge: number?)
	if cooldowns then
		for name, left in cooldowns do
			local predicted = CombatController.cooldownLeft(name)
			if math.abs(predicted - left) > 0.3 then
				cooldownUntil[name] = os.clock() + left
			end
		end
	end
	if charge then
		CombatController.charge = charge
	end
end

local function aim(): Vector3
	local look = (Workspace.CurrentCamera :: Camera).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z)
end

local function dash()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local dir = hum.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	root.AssemblyLinearVelocity = dir * PA.Dodge.dashSpeed + Vector3.new(0, 18, 0)
	Effects.burst(root.Position, Color3.fromRGB(200, 230, 255), 16, "smoke", 12, 2)
	Effects.sound("Whoosh", 0.5)
end

function CombatController.use(name: string)
	if not CombatController.inBattle() then
		return
	end
	local def = PA[name]
	if not def or CombatController.cooldownLeft(name) > 0 then
		return
	end
	if name == "Ultimate" and CombatController.charge < CombatController.chargeNeeded then
		Effects.sound("Error", 0.3)
		return
	end
	cooldownUntil[name] = os.clock() + def.cooldown
	if name == "Dodge" then
		dash()
	elseif name == "Ultimate" then
		CombatController.charge = 0
	end
	Net.Client.fire("PlayerAction", name, aim())
	CombatController.Used:Fire(name)
end

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Q] = "Dodge",
	[Enum.KeyCode.E] = "Heal",
	[Enum.KeyCode.R] = "Rally",
	[Enum.KeyCode.F] = "Ultimate",
	[Enum.KeyCode.ButtonR2] = "Attack",
	[Enum.KeyCode.ButtonB] = "Dodge",
	[Enum.KeyCode.ButtonX] = "Heal",
	[Enum.KeyCode.ButtonY] = "Rally",
	[Enum.KeyCode.ButtonL2] = "Ultimate",
}

function CombatController.start()
	local holding = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not CombatController.inBattle() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			CombatController.use("Attack")
		else
			local action = KEYS[input.KeyCode]
			if action then
				CombatController.use(action)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = false
		end
	end)
	-- hold to keep swinging
	task.spawn(function()
		while true do
			task.wait(0.1)
			if holding and CombatController.inBattle() then
				CombatController.use("Attack")
			end
		end
	end)
	player:GetAttributeChangedSignal("BattleId"):Connect(function()
		if not CombatController.inBattle() then
			holding = false
			table.clear(cooldownUntil)
			CombatController.charge = 0
		end
	end)
end

return CombatController
