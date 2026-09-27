--!strict
-- Zones window: every zone as a big tile. Unlocked -> teleport; next locked -> unlock button.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local TravelUI = {}
local C = Theme.Colors

function TravelUI.start()
	Windows.register("Travel", {
		title = "Zones",
		icon = "Travel",
		color = C.Travel,
		build = function(content: Frame)
			local scroll = UIKit.scroll({ Parent = content })
			UIKit.grid(scroll, Vector2.new(214, 150), 12)
			local tiles: { () -> () } = {}
			local order = table.clone(Defs.MainZones)
			for _, z in Config.Zones do
				if z.index == 0 then
					table.insert(order, z)
				end
			end
			for i, z in order do
				local tile = UIKit.panel({ Color = z.ground, LayoutOrder = i, Parent = scroll })
				UIKit.label({
					Text = z.name,
					Size = UDim2.new(1, -12, 0, 44),
					Position = UDim2.fromOffset(6, 6),
					MaxTextSize = 28,
					Parent = tile,
				})
				local info = UIKit.label({
					Size = UDim2.new(1, -12, 0, 26),
					Position = UDim2.fromOffset(6, 48),
					Color = C.Text,
					MaxTextSize = 20,
					Parent = tile,
				})
				local action = UIKit.button({
					Size = UDim2.new(1, -20, 0, 56),
					Position = UDim2.new(0, 10, 1, -64),
					Parent = tile,
					OnClick = function(btn)
						local unlocked = ClientState.get("UnlockedZones") or {}
						local canGo = unlocked[z.id] or (z.vipOnly and ClientState.hasPass("VIP"))
						if canGo then
							local ok, msg = Net.Client.invoke("Teleport", z.id)
							if ok then
								Windows.close()
							elseif msg then
								Effects.toast(msg, C.Bad)
							end
						elseif z.vipOnly then
							Windows.open("Shop")
						else
							local ok, msg = Net.Client.invoke("UnlockZone", z.id)
							if not ok and msg then
								Effects.toast(msg, C.Bad)
							end
						end
						UIKit.pop(btn)
					end,
				})
				table.insert(tiles, function()
					local unlocked = ClientState.get("UnlockedZones") or {}
					local charge = ClientState.get("Charge") or 0
					info.Text = if z.bestZoneScale
						then `x{z.bestZoneScale} your best zone`
						else `Spirits worth x{Format.short(z.valueMult)}`
					if unlocked[z.id] or (z.vipOnly and ClientState.hasPass("VIP")) then
						UIKit.setButtonText(action, "GO")
						UIKit.setButtonColor(action, C.Travel)
					elseif z.vipOnly then
						UIKit.setButtonText(action, "VIP pass")
						UIKit.setButtonColor(action, C.Pass)
					else
						local prev = Defs.MainZones[z.index - 1]
						local ready = prev == nil or unlocked[prev.id]
						UIKit.setButtonText(action, `{Theme.Icons.Lock} {Theme.Icons.Charge}{Format.short(z.gateCost)}`)
						UIKit.setButtonColor(action, if ready and charge >= z.gateCost then C.Good else C.PanelDark)
					end
				end)
			end
			local function refresh()
				for _, t in tiles do
					t()
				end
			end
			ClientState.observe("UnlockedZones", function()
				if Windows.isOpen("Travel") then
					refresh()
				end
			end)
			return { refresh = refresh }
		end,
	})
end

return TravelUI
