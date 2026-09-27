--!strict
-- Upgrades window: one row per track with current -> next value, cost, Buy x1 / Buy Max.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local UpgradesUI = {}
local C = Theme.Colors

local function fmtValue(def: Types.UpgradeDef, v: number): string
	if def.unit == "s" then
		return string.format("%.2fs", v)
	elseif def.unit == "x" then
		return string.format("x%.1f", v)
	elseif def.unit == "Static" then
		return Format.short(v)
	end
	return tostring(math.floor(v * 10) / 10)
end

UpgradesUI.rows = {} :: { [string]: TextButton }

function UpgradesUI.start()
	Windows.register("Upgrades", {
		title = "Upgrades",
		icon = "Upgrades",
		color = C.Upgrades,
		build = function(content: Frame)
			local scroll = UIKit.scroll({ Parent = content })
			UIKit.list(scroll, 10)
			local refreshers: { () -> () } = {}
			for i, def in Config.Upgrades do
				local row = UIKit.panel({
					Size = UDim2.new(1, -8, 0, 92),
					Color = C.PanelLight,
					LayoutOrder = i,
					Parent = scroll,
				})
				UIKit.label({
					Text = Theme.Icons[def.icon] or "",
					Size = UDim2.fromOffset(70, 70),
					Position = UDim2.fromOffset(10, 11),
					Parent = row,
				})
				local title = UIKit.label({
					Size = UDim2.new(0.5, -90, 0, 38),
					Position = UDim2.fromOffset(88, 8),
					XAlign = Enum.TextXAlignment.Left,
					MaxTextSize = 30,
					Parent = row,
				})
				local desc = UIKit.label({
					Size = UDim2.new(0.55, -90, 0, 36),
					Position = UDim2.fromOffset(88, 48),
					XAlign = Enum.TextXAlignment.Left,
					Color = C.TextDim,
					Font = Theme.FontBody,
					MaxTextSize = 18,
					Parent = row,
				})
				local buy = UIKit.button({
					Size = UDim2.fromOffset(170, 64),
					Position = UDim2.new(1, -196, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Color = C.Good,
					Parent = row,
					OnClick = function()
						local ok, result = Net.Client.invoke("BuyUpgrade", def.id, 1)
						if ok then
							UIKit.sound("Upgrade")
							Effects.burst(workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 10, C.Upgrades, 12)
						elseif result then
							Effects.toast(result, C.Bad, 1.4)
						end
					end,
				})
				UpgradesUI.rows[def.id] = buy
				UIKit.button({
					Text = "MAX",
					Size = UDim2.fromOffset(90, 64),
					Position = UDim2.new(1, -12, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Color = C.Pets,
					Parent = row,
					OnClick = function()
						local ok, result = Net.Client.invoke("BuyUpgrade", def.id, 100)
						if ok then
							UIKit.sound("Upgrade")
							Effects.toast(`+{result} levels`, C.Good, 1.2)
						elseif result then
							Effects.toast(result, C.Bad, 1.4)
						end
					end,
				})
				table.insert(refreshers, function()
					local levels = ClientState.get("Upgrades") or {}
					local level = levels[def.id] or 0
					local charge = ClientState.get("Charge") or 0
					local cur = EconomyMath.upgradeValue(def, level)
					title.Text = `{def.name} <font color="#9FB0D8">Lv {level}</font>`
					if level >= def.maxLevel then
						desc.Text = `{fmtValue(def, cur)} (max)`
						UIKit.setButtonText(buy, "MAXED")
						UIKit.setButtonColor(buy, C.PanelDark)
					else
						local nextV = EconomyMath.upgradeValue(def, level + 1)
						local cost = EconomyMath.upgradeCost(def, level)
						desc.Text = `{def.description}  {fmtValue(def, cur)} → <font color="#58E068">{fmtValue(def, nextV)}</font>`
						UIKit.setButtonText(buy, `{Theme.Icons.Charge} {Format.short(cost)}`)
						UIKit.setButtonColor(buy, if charge >= cost then C.Good else C.PanelDark)
					end
				end)
			end
			local function refresh()
				for _, r in refreshers do
					r()
				end
			end
			ClientState.observe("Upgrades", function()
				if Windows.isOpen("Upgrades") then
					refresh()
				end
			end)
			ClientState.observe("Charge", function()
				if Windows.isOpen("Upgrades") then
					refresh()
				end
			end)
			return { refresh = refresh }
		end,
	})
end

return UpgradesUI
