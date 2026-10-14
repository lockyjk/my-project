--!strict
-- Background music: hub theme, battle theme, boss theme (crossfaded). Uses the ids in
-- GameConfig.Sounds (HubMusic / BattleMusic / BossMusic); empty ids are skipped, so the
-- game is silent-but-working until music is uploaded. Respects the Music setting, and
-- keeps Effects / UIKit sfx in sync with the SFX setting.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local ClientState = require(script.Parent.ClientState)
local Effects = require(script.Parent.Effects)
local Bus = require(script.Parent.Parent.UI.Bus)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MusicController = {}

local player = Players.LocalPlayer
local tracks: { [string]: Sound } = {}
local playing = ""
local bossUntil = 0

local function track(name: string): Sound?
	local id = GameConfig.Sounds[name]
	if not id or id == "" then
		return nil
	end
	local s = tracks[name]
	if not s then
		local created = Instance.new("Sound")
		created.Name = name
		created.SoundId = id
		created.Looped = true
		created.Volume = 0
		created.Parent = SoundService
		tracks[name] = created
		s = created
	end
	return s
end

local function play(name: string)
	local musicOn = not (ClientState.data.settings and ClientState.data.settings.music == false)
	local want = if musicOn then name else ""
	if want == playing then
		return
	end
	local old = tracks[playing]
	if old then
		local o = old
		TweenService:Create(o, TweenInfo.new(1.2), { Volume = 0 }):Play()
		task.delay(1.25, function()
			if playing ~= o.Name then
				o:Stop()
			end
		end)
	end
	playing = want
	local s = if want ~= "" then track(want) else nil
	if s then
		if not s.IsPlaying then
			s:Play()
		end
		TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0.35 }):Play()
	end
end

local function decide()
	if player:GetAttribute("BattleId") ~= nil then
		play(if os.clock() < bossUntil then "BossMusic" else "BattleMusic")
	else
		play("HubMusic")
	end
end

function MusicController.start()
	Bus.BossIntro:Connect(function()
		bossUntil = os.clock() + 600
		decide()
	end)
	player:GetAttributeChangedSignal("BattleId"):Connect(function()
		bossUntil = 0
		decide()
	end)
	ClientState.Changed:Connect(function(key)
		if key == "settings" then
			local sfx = not (ClientState.data.settings and ClientState.data.settings.sfx == false)
			Effects.sfxEnabled = sfx
			UIKit.sfxEnabled = sfx
			playing = "?" -- force re-evaluation
			decide()
		end
	end)
	ClientState.Loaded:Connect(decide)
end

return MusicController
