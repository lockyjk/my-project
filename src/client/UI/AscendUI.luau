--!strict
-- Ascend window: progress to the next Ascension (multiplier now -> after, tokens you'd earn),
-- a two-tap confirm, and the Ascension Token tree.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local AscendUI = {}
local C = Theme.Colors

function AscendUI.start()
	Windows.register("Ascend", {
		title = "Ascend",
		icon = "Ascend",
		color = C.Ascend,
		size = Vector2.new(860, 540),
		build = function(content: Frame)
			local left = UIKit.panel({ Size = UDim2.new(0.42, 0, 1, 0), Color = C.PanelDark, Parent = content })
			local info = UIKit.label({
				Size = UDim2.new(1, -20, 0, 190),
				Position = UDim2.fromOffset(10, 10),
				MaxTextSize = 26,
				YAlign = Enum.TextYAlignment.Top,
				Parent = left,
			})
			local bar = UIKit.progress({ Size = UDim2.new(1, -20, 0, 38), Position = UDim2.fromOffset(10, 210), Color = C.Ascend, Parent = left })
			UIKit.label({
				Text = "Ascending resets Charge and upgrades.\nYou keep zones, Stormlings, decorations and Tokens.",
				Size = UDim2.new(1, -20, 0, 70),
				Position = UDim2.fromOffset(10, 256),
				Color = C.TextDim,
				Font = Theme.FontBody,
				MaxTextSize = 18,
				Parent = left,
			})
			local confirm = false
			local ascendButton = UIKit.button({
				Text = "ASCEND",
				Color = C.Ascend,
				Size = UDim2.new(1, -20, 0, 80),
				Position = UDim2.new(0, 10, 1, -90),
				MaxTextSize = 40,
				Parent = left,
			})

			local right = UIKit.scroll({ Size = UDim2.new(0.56, 0, 1, 0), Position = UDim2.fromScale(0.44, 0), Parent = content })
			UIKit.list(right, 8)
			local tokensLabel = UIKit.label({ Size = UDim2.new(1, -10, 0, 36), LayoutOrder = 0, Color = C.Tokens, Parent = right })
			local nodeRefreshers: { () -> () } = {}
			for i, node in Config.AscTree do
				local row = UIKit.panel({ Size = UDim2.new(1, -10, 0, 78), Color = C.PanelLight, LayoutOrder = i, Parent = right })
				local title = UIKit.label({
					Size = UDim2.new(1, -170, 0, 34),
					Position = UDim2.fromOffset(12, 6),
					XAlign = Enum.TextXAlignment.Left,
					MaxTextSize = 26,
					Parent = row,
				})
				local desc = UIKit.label({
					Size = UDim2.new(1, -170, 0, 28),
					Position = UDim2.fromOffset(12, 42),
					XAlign = Enum.TextXAlignment.Left,
					Color = C.TextDim,
					Font = Theme.FontBody,
					MaxTextSize = 18,
					Parent = row,
				})
				local buy = UIKit.button({
					Size = UDim2.fromOffset(150, 60),
					Position = UDim2.new(1, -10, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Color = C.Tokens,
					Parent = row,
					OnClick = function()
						local ok, msg = Net.Client.invoke("BuyAscNode", node.id)
						if ok then
							Effects.burst(workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 10, C.Tokens, 16)
						elseif msg then
							Effects.toast(tostring(msg), C.Bad)
						end
					end,
				})
				table.insert(nodeRefreshers, function()
					local tree = ClientState.get("AscTree") or {}
					local tokens = ClientState.get("Tokens") or 0
					local level = tree[node.id] or 0
					title.Text = `{node.name} <font color="#9FB0D8">{level}/{node.maxLevel}</font>`
					local locked = node.requires ~= nil and (tree[node.requires] or 0) < 1
					desc.Text = if locked then `Requires {Defs.AscNode[node.requires :: string].name}` else node.description
					if level >= node.maxLevel then
						UIKit.setButtonText(buy, "MAX")
						UIKit.setButtonColor(buy, C.PanelDark)
					else
						local cost = EconomyMath.ascNodeCost(node, level)
						UIKit.setButtonText(buy, `{Theme.Icons.Tokens} {cost}`)
						UIKit.setButtonColor(buy, if not locked and tokens >= cost then C.Tokens else C.PanelDark)
					end
				end)
			end

			local function refresh()
				local asc = ClientState.get("Ascensions") or 0
				local charge = ClientState.get("Charge") or 0
				local cost = EconomyMath.ascensionCost(asc)
				local now = 1 + EconomyMath.ascensionBonus(asc)
				local after = 1 + EconomyMath.ascensionBonus(asc + 1)
				local tokens = EconomyMath.ascensionTokens(asc, math.max(charge, cost))
				info.Text = `Ascensions: <font color="#BE78FF">{asc}</font>\n`
					.. `Ascension bonus: x{Format.short(now)} → <font color="#58E068">x{Format.short(after)}</font>\n`
					.. `Tokens: +{tokens}{if charge > cost * 2 then " (bonus for extra Charge!)" else ""}\n`
					.. `Cost: {Theme.Icons.Charge} {Format.short(cost)}`
				bar.set(charge / cost, `{Format.short(charge)} / {Format.short(cost)}`)
				UIKit.setButtonColor(ascendButton, if charge >= cost then C.Ascend else C.PanelDark)
				UIKit.setButtonText(ascendButton, if confirm then "TAP AGAIN TO ASCEND" else "ASCEND")
				tokensLabel.Text = `{Theme.Icons.Tokens} {ClientState.get("Tokens") or 0} Tokens`
				for _, r in nodeRefreshers do
					r()
				end
			end

			ascendButton.Activated:Connect(function()
				local asc = ClientState.get("Ascensions") or 0
				if (ClientState.get("Charge") or 0) < EconomyMath.ascensionCost(asc) then
					Effects.toast("Not enough Charge yet", C.Bad)
					return
				end
				if not confirm then
					confirm = true
					refresh()
					task.delay(3, function()
						confirm = false
						if Windows.isOpen("Ascend") then
							refresh()
						end
					end)
					return
				end
				confirm = false
				local ok, result = Net.Client.invoke("Ascend")
				if ok then
					Effects.flash(C.Ascend, 0.8)
					Effects.shake(1.2, 0.8)
					Effects.banner(`ASCENDED! +{result} Tokens`, C.Tokens, 3)
				elseif result then
					Effects.toast(tostring(result), C.Bad)
				end
				refresh()
			end)

			for _, key in { "Charge", "Ascensions", "Tokens", "AscTree" } do
				ClientState.observe(key, function()
					if Windows.isOpen("Ascend") then
						refresh()
					end
				end)
			end
			return { refresh = refresh }
		end,
	})
	-- Badge the menu button when Ascension is affordable
	ClientState.observe("Charge", function(charge: number)
		local asc = ClientState.get("Ascensions") or 0
		HUD.badge("Ascend", charge >= EconomyMath.ascensionCost(asc))
	end)
end

return AscendUI
