--!strict
-- Storm Pass: season name + real time left, tier progress, horizontally scrolling tiers with
-- free (top) and premium (bottom) rewards, Claim All, and the premium / skip-tier products.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local PassRewards = require(Shared:WaitForChild("PassRewards"))
local Schedule = require(Shared:WaitForChild("Schedule"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local RetentionUI = require(script.Parent.RetentionUI)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local PassUI = {}
local C = Theme.Colors

local function call(remote: string, ...: any): boolean
	local ok, msg = Net.Client.invoke(remote, ...)
	if not ok and msg then
		Effects.toast(tostring(msg), C.Bad, 1.8)
	end
	return ok == true
end

local function claimable(pass: any): boolean
	if not pass then
		return false
	end
	local reached = EconomyMath.passTier(pass.XP)
	for t = 1, reached do
		if not pass.ClaimedFree[tostring(t)] or (pass.Premium and not pass.ClaimedPremium[tostring(t)]) then
			return true
		end
	end
	return false
end

function PassUI.start()
	Windows.register("Pass", {
		title = "Storm Pass",
		icon = "Pass",
		color = C.Pass,
		size = Vector2.new(940, 560),
		build = function(content: Frame)
			local top = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 100), Parent = content })
			local season = UIKit.label({ Size = UDim2.new(0.5, 0, 0, 36), XAlign = Enum.TextXAlignment.Left, MaxTextSize = 30, Parent = top })
			local timeLeft = UIKit.label({ Size = UDim2.new(0.5, 0, 0, 26), Position = UDim2.fromOffset(0, 36), XAlign = Enum.TextXAlignment.Left, Color = C.TextDim, MaxTextSize = 20, Parent = top })
			local bar = UIKit.progress({ Size = UDim2.new(0.5, -10, 0, 30), Position = UDim2.fromOffset(0, 66), Color = C.Pass, Parent = top })
			local actions = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Parent = top })
			UIKit.list(actions, 8, true, Enum.HorizontalAlignment.Right)
			local claimAll = UIKit.button({
				Text = "Claim All",
				Color = C.Good,
				Size = UDim2.fromOffset(150, 70),
				LayoutOrder = 1,
				Parent = actions,
				OnClick = function()
					call("ClaimAllPass")
				end,
			})
			UIKit.button({
				Text = "Skip Tier",
				Color = C.Robux,
				Size = UDim2.fromOffset(140, 70),
				LayoutOrder = 2,
				Parent = actions,
				OnClick = function()
					call("PromptProduct", "PassSkip")
				end,
			})
			local premiumBtn = UIKit.button({
				Text = "Get Premium",
				Color = C.Robux,
				Size = UDim2.fromOffset(170, 70),
				LayoutOrder = 3,
				Parent = actions,
				OnClick = function()
					call("PromptProduct", "PassPremium")
				end,
			})

			local labels = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 90, 1, -110), Position = UDim2.fromOffset(0, 110), Parent = content })
			UIKit.label({ Text = "FREE", Size = UDim2.new(1, 0, 0.5, -4), Color = C.Text, MaxTextSize = 24, Parent = labels })
			UIKit.label({ Text = "PREMIUM", Size = UDim2.new(1, 0, 0.5, -4), Position = UDim2.fromScale(0, 0.5), Color = C.Charge, MaxTextSize = 20, Parent = labels })
			local track = UIKit.scroll({ Size = UDim2.new(1, -96, 1, -110), Position = UDim2.fromOffset(96, 110), Horizontal = true, Parent = content })
			UIKit.list(track, 8, true, Enum.HorizontalAlignment.Left)

			local cells: { () -> () } = {}
			for tier = 1, Config.StormPass.Tiers do
				local reward = PassRewards.forTier(tier)
				local col = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 150, 1, -10), LayoutOrder = tier, Parent = track })
				UIKit.label({ Text = `Tier {tier}`, Size = UDim2.new(1, 0, 0, 26), MaxTextSize = 22, Parent = col })
				local function cell(premium: boolean, y: number): (Frame, TextButton)
					local r = if premium then reward.premium else reward.free
					local panel = UIKit.panel({
						Size = UDim2.new(1, 0, 0.5, -20),
						Position = UDim2.new(0, 0, y, if premium then 4 else 28),
						Color = if premium then Theme.darken(C.Pass, 0.2) else C.PanelLight,
						Parent = col,
					})
					UIKit.label({
						Text = RetentionUI.describe(r),
						Size = UDim2.new(1, -8, 1, -56),
						Position = UDim2.fromOffset(4, 4),
						Font = Theme.FontBody,
						MaxTextSize = 16,
						Parent = panel,
					})
					local b = UIKit.button({
						Text = "",
						Size = UDim2.new(1, -12, 0, 44),
						Position = UDim2.new(0, 6, 1, -50),
						Parent = panel,
						OnClick = function()
							call("ClaimPassTier", tier, premium)
						end,
					})
					return panel, b
				end
				local _, freeBtn = cell(false, 0)
				local _, premBtn = cell(true, 0.5)
				table.insert(cells, function()
					local pass = ClientState.get("Pass") or { XP = 0, ClaimedFree = {}, ClaimedPremium = {}, Premium = false }
					local reached = EconomyMath.passTier(pass.XP)
					local function style(b: TextButton, claimedMap: any, locked: boolean)
						if claimedMap[tostring(tier)] then
							UIKit.setButtonText(b, Theme.Icons.Check)
							UIKit.setButtonColor(b, C.PanelDark)
						elseif locked then
							UIKit.setButtonText(b, Theme.Icons.Lock)
							UIKit.setButtonColor(b, C.PanelDark)
						elseif tier <= reached then
							UIKit.setButtonText(b, "Claim")
							UIKit.setButtonColor(b, C.Good)
						else
							UIKit.setButtonText(b, `Tier {tier}`)
							UIKit.setButtonColor(b, C.PanelDark)
						end
					end
					style(freeBtn, pass.ClaimedFree, false)
					style(premBtn, pass.ClaimedPremium, not pass.Premium)
				end)
			end

			local function refresh()
				local pass = ClientState.get("Pass") or { XP = 0, ClaimedFree = {}, ClaimedPremium = {}, Premium = false }
				local index, left = Schedule.passSeason(DateTime.now().UnixTimestamp)
				season.Text = if index > 0 then Schedule.passSeasonName(index) else "Storm Pass starts soon!"
				timeLeft.Text = if index > 0 then `Season ends in {Format.duration(left)}` else ""
				local tier, into, need = EconomyMath.passTier(pass.XP)
				bar.set(if need > 0 then into / need else 1, if need > 0 then `Tier {tier} · {into}/{need} XP` else "MAX TIER!")
				premiumBtn.Visible = not pass.Premium
				claimAll.Visible = claimable(pass)
				for _, c in cells do
					c()
				end
			end
			ClientState.observe("Pass", function()
				if Windows.isOpen("Pass") then
					refresh()
				end
			end)
			return { refresh = refresh }
		end,
	})
	ClientState.observe("Pass", function(pass)
		HUD.badge("Pass", claimable(pass))
	end)
end

return PassUI
