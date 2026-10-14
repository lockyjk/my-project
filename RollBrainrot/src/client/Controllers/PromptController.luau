--!strict
-- World ProximityPrompts carry an "Action" attribute (set by the world builders); this maps
-- them to client behaviour: open a stand window, roll, enter the arena, unlock a habitat.

local ProximityPromptService = game:GetService("ProximityPromptService")

local Bus = require(script.Parent.Parent.UI.Bus)
local Notifications = require(script.Parent.Parent.UI.Notifications)
local Windows = require(script.Parent.Parent.UI.Windows)

local PromptController = {}

local WINDOWS: { [string]: string } = {
	OpenShop = "Shop",
	OpenUpgrades = "Upgrades",
	OpenDaily = "Daily",
	OpenEvents = "Events",
}

function PromptController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local action = prompt:GetAttribute("Action")
		if type(action) ~= "string" then
			return
		end
		local window = WINDOWS[action]
		if window then
			Windows.open(window)
		elseif action == "UnlockHabitat" then
			local id = prompt:GetAttribute("HabitatId")
			if type(id) == "string" then
				Notifications.call("UnlockHabitat", id)
			end
		elseif action ~= "CollectZoo" then -- collecting is handled by the server prompt
			Bus.PromptAction:Fire(action, prompt)
		end
	end)
end

return PromptController
