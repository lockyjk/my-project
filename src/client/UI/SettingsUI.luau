--!strict
-- Settings: sound, auto-catch (pass), hide other players' pets, auto-delete by rarity.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local SettingsUI = {}
local C = Theme.Colors

function SettingsUI.start()
	-- Background music (Config.Sounds.Music; skipped when empty)
	local music: Sound? = nil
	if Config.Sounds.Music ~= "" then
		local m = Instance.new("Sound")
		m.Name = "Music"
		m.SoundId = Config.Sounds.Music
		m.Looped = true
		m.Volume = 0.3
		m.Parent = game:GetService("SoundService")
		music = m
	end
	ClientState.observe("Settings", function(settings)
		UIKit.sfxEnabled = settings.Sfx ~= false
		if music then
			if settings.Music ~= false then
				if not music.IsPlaying then
					music:Play()
				end
			else
				music:Stop()
			end
		end
	end)
	Windows.register("Settings", {
		title = "Settings",
		icon = "Settings",
		color = C.PanelLight,
		build = function(content: Frame)
			local scroll = UIKit.scroll({ Parent = content })
			UIKit.list(scroll, 8)
			local refreshers: { () -> () } = {}
			local order = 0
			local function toggle(label: string, key: string, get: () -> boolean)
				order += 1
				local row = UIKit.panel({ Size = UDim2.new(1, -10, 0, 64), Color = C.PanelLight, LayoutOrder = order, Parent = scroll })
				UIKit.label({ Text = label, Size = UDim2.new(1, -170, 1, -10), Position = UDim2.fromOffset(14, 5), XAlign = Enum.TextXAlignment.Left, MaxTextSize = 26, Parent = row })
				local b = UIKit.button({
					Size = UDim2.fromOffset(140, 52),
					Position = UDim2.new(1, -10, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Parent = row,
					OnClick = function()
						Net.Client.invoke("SetSetting", key, not get())
					end,
				})
				table.insert(refreshers, function()
					local on = get()
					UIKit.setButtonText(b, if on then "ON" else "OFF")
					UIKit.setButtonColor(b, if on then C.Good else C.PanelDark)
				end)
			end
			local function settings(): { [string]: any }
				return ClientState.get("Settings") or {}
			end
			toggle("Music", "Music", function()
				return settings().Music ~= false
			end)
			toggle("Sound effects", "Sfx", function()
				return settings().Sfx ~= false
			end)
			toggle("Auto-Catch (pass)", "AutoCatch", function()
				return settings().AutoCatch ~= false
			end)
			toggle("Hide other players' Stormlings", "HidePets", function()
				return settings().HidePets == true
			end)
			for _, rarity in Config.Rarities do
				if rarity.order <= 4 then
					toggle(`Auto-delete {rarity.name} hatches`, `AutoDelete.{rarity.id}`, function()
						local ad = settings().AutoDelete or {}
						return ad[rarity.id] == true
					end)
				end
			end
			local function refresh()
				for _, r in refreshers do
					r()
				end
			end
			ClientState.observe("Settings", function()
				if Windows.isOpen("Settings") then
					refresh()
				end
			end)
			return { refresh = refresh }
		end,
	})
end

return SettingsUI
