--!strict
-- Client bootstrap. Every controller / UI module exposes start(), called in this order;
-- start() must not yield for long (spawn any waiting work). One failing module never
-- stops the others.

local Controllers = script:WaitForChild("Controllers")
local UI = script:WaitForChild("UI")

local order: { Instance } = {
	Controllers.ClientState,
	UI.Windows,
	Controllers.Effects,
	UI.Notifications,
	Controllers.CameraController,
	Controllers.UnitRenderer,
	Controllers.CombatFx,
	Controllers.CombatController,
	UI.BattleUI,
	UI.RollUI,
	Controllers.RollController,
	UI.HUD,
	UI.CollectionUI,
	UI.ZooUI,
	UI.StandWindows,
	UI.ArenaUI,
	Controllers.ZooController,
	Controllers.FollowController,
	Controllers.AmbientController,
	Controllers.CrowdController,
	Controllers.EventController,
	Controllers.PromptController,
	Controllers.MusicController,
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
