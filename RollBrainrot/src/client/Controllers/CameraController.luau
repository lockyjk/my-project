--!strict
-- Scripted camera moments: the roll machine close-up and the boss entrance cinematic.
-- `focus` takes over the camera with a tween; `release` hands it back to the player.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local owner: string? = nil
local savedFov = 70

local function cam(): Camera
	return Workspace.CurrentCamera :: Camera
end

function CameraController.isBusy(): boolean
	return owner ~= nil
end

-- Move the camera to `cf` over `time` seconds. `who` names the owner so overlapping
-- requests don't fight (the last caller wins, release only works for the owner).
function CameraController.focus(who: string, cf: CFrame, time: number, fov: number?)
	local c = cam()
	if not owner then
		savedFov = c.FieldOfView
	end
	owner = who
	c.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(c, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = cf,
		FieldOfView = fov or savedFov,
	}):Play()
end

function CameraController.release(who: string, time: number?)
	if owner ~= who then
		return
	end
	owner = nil
	local c = cam()
	TweenService:Create(c, TweenInfo.new(time or 0.4), { FieldOfView = savedFov }):Play()
	c.CameraType = Enum.CameraType.Custom
end

-- A sequence of shots: { { cf, time, hold } }; yields until done, then releases.
function CameraController.cinematic(who: string, shots: { { cf: CFrame, time: number, hold: number, fov: number? } })
	for _, shot in shots do
		if owner ~= nil and owner ~= who then
			return
		end
		CameraController.focus(who, shot.cf, shot.time, shot.fov)
		task.wait(shot.time + shot.hold)
	end
	CameraController.release(who, 0.6)
end

function CameraController.start() end

return CameraController
