--!strict
-- Client bootstrap. Controllers/UI modules expose start(), called in order; start() must not
-- yield for long (spawn any waiting work).

local Controllers = script:WaitForChild("Controllers")
local UI = script:WaitForChild("UI")

local order: { Instance } = {
	Controllers.ClientState,
	UI.Windows,
	Controllers.Effects,
	Controllers.WeatherController,
	Controllers.SpiritController,
	UI.HUD,
	UI.HatchAnimation,
	UI.RewardPopup,
	UI.UpgradesUI,
	UI.TravelUI,
	UI.PetsUI,
	UI.EggUI,
	UI.AscendUI,
	UI.SettingsUI,
	Controllers.PetFollowController,
	Controllers.CharacterVisuals,
	Controllers.GateController,
	Controllers.TutorialController,
}

for _, module in order do
	local ok, err = pcall(function()
		local m = (require :: any)(module)
		if m.start then
			m.start()
		end
	end)
	if not ok then
		warn(`[Client] failed to start {module.Name}: {err}`)
	end
end
