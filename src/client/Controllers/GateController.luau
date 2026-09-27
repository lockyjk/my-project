--!strict
-- Zone gates: the server keeps every gate solid; the client opens the ones this player
-- has unlocked (client owns its character physics, so this is smooth). The server still
-- checks zone access on every catch and pushes intruders back out.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))

local ClientState = require(script.Parent.ClientState)
local HUD = require(script.Parent.Parent.UI.HUD)

local GateController = {}

local gates: { [Model]: string } = {}

local function canPass(zoneId: string): boolean
	local z = Defs.Zone[zoneId]
	if not z then
		return false
	end
	if z.vipOnly then
		return ClientState.hasPass("VIP")
	end
	local unlocked = ClientState.get("UnlockedZones") or {}
	return unlocked[zoneId] == true
end

local function applyGate(gate: Model, zoneId: string)
	local open = canPass(zoneId)
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Barrier" then
			d.CanCollide = not open
			d.Transparency = if open then 1 else 0.2
			for _, gui in d:GetChildren() do
				if gui:IsA("SurfaceGui") then
					gui.Enabled = not open
				end
			end
		end
	end
end

local function applyAll()
	for gate, zoneId in gates do
		applyGate(gate, zoneId)
	end
end

local function track(inst: Instance)
	if inst:IsA("Model") then
		local zoneId = inst:GetAttribute("ZoneId")
		if type(zoneId) == "string" then
			gates[inst] = zoneId
			applyGate(inst, zoneId)
		end
	end
end

function GateController.start()
	for _, g in CollectionService:GetTagged("ZoneGate") do
		track(g)
	end
	CollectionService:GetInstanceAddedSignal("ZoneGate"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("ZoneGate"):Connect(function(inst)
		gates[inst :: Model] = nil
	end)
	ClientState.observe("UnlockedZones", applyAll)
	ClientState.observe("Passes", applyAll)

	-- Show an unlock button when standing near a locked gate
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = Players.LocalPlayer.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local near: string? = nil
			if hrp then
				for gate, zoneId in gates do
					local z = Defs.Zone[zoneId]
					if z and not z.vipOnly and not canPass(zoneId) then
						local pivot = gate:GetPivot().Position
						if (hrp.Position - pivot).Magnitude < 45 then
							near = zoneId
						end
					end
				end
			end
			HUD.showGatePrompt(near)
		end
	end)
end

return GateController
