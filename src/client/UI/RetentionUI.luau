--!strict
-- Retention HUD + windows:
--   top-right: streak flame (always visible), gift timer, leaderboards, Premium gift
--   right:     quest tracker (daily quests at a glance)
--   windows:   Daily streak, Gifts, Quests (daily / weekly / achievements), Leaderboards

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Schedule = require(Shared:WaitForChild("Schedule"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local RetentionUI = {}
local C = Theme.Colors

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function call(remote: string, ...: any): boolean
	local ok, msg = Net.Client.invoke(remote, ...)
	if not ok and msg then
		Effects.toast(tostring(msg), C.Bad, 1.8)
	end
	return ok == true
end

-- Text description of a Reward for previews
function RetentionUI.describe(reward: Types.Reward): string
	local parts = {}
	if reward.chargeMinutes then
		table.insert(parts, `{Theme.Icons.Charge} {reward.chargeMinutes} min of Charge`)
	end
	if reward.charge then
		table.insert(parts, `{Theme.Icons.Charge} {Format.short(reward.charge)}`)
	end
	if reward.potions then
		for id, n in reward.potions do
			local def = Defs.Potion[id]
			table.insert(parts, `{n}x {if def then def.name else id}`)
		end
	end
	if reward.passXP then
		table.insert(parts, `{reward.passXP} Pass XP`)
	end
	if reward.tokens then
		table.insert(parts, `{Theme.Icons.Tokens} {reward.tokens} Tokens`)
	end
	if reward.fusionSkips then
		table.insert(parts, `{reward.fusionSkips} Fusion Skip`)
	end
	if reward.pet then
		table.insert(parts, `{Theme.Icons.Pets} {Defs.Pet[reward.pet].name}`)
	end
	if reward.egg then
		table.insert(parts, `{Theme.Icons.Egg} {Defs.Egg[reward.egg].name}`)
	end
	if reward.decoration then
		table.insert(parts, `{Theme.Icons.Build} {Defs.Decoration[reward.decoration].name}`)
	end
	return table.concat(parts, "\n")
end

local function streakInfo(): (boolean, number)
	local daily = ClientState.get("Daily") or { Streak = 0, LastClaimDay = -1 }
	local today = Schedule.dayIndex(now())
	if daily.LastClaimDay == today then
		return false, daily.Streak
	end
	if daily.LastClaimDay == today - 1 then
		return true, daily.Streak + 1
	end
	return true, 1
end

local function nextGift(): (number?, number)
	local gifts = ClientState.get("Gifts")
	if not gifts then
		return nil, 0
	end
	local claimed = {}
	for _, i in gifts.claimed do
		claimed[i] = true
	end
	local elapsed = now() - gifts.joinUnix
	for i, g in Config.Gifts do
		if not claimed[i] then
			return i, g.minutes * 60 - elapsed
		end
	end
	return nil, 0
end

-------------------------------------------------------------------------------
-- HUD pieces
-------------------------------------------------------------------------------

local function buildCluster(root: Frame)
	local cluster = UIKit.new("Frame", {
		Name = "Cluster",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(330, 70),
		Position = UDim2.new(1, -14, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Parent = root,
	})
	UIKit.list(cluster, 8, true, Enum.HorizontalAlignment.Right)
	local streak = UIKit.button({
		Name = "Streak",
		Text = "",
		Color = C.Warn,
		Size = UDim2.fromOffset(110, 66),
		LayoutOrder = 1,
		Parent = cluster,
		OnClick = function()
			Windows.toggle("Daily")
		end,
	})
	local gift = UIKit.button({
		Name = "Gift",
		Text = "",
		Color = C.Shop,
		Size = UDim2.fromOffset(120, 66),
		LayoutOrder = 2,
		Parent = cluster,
		OnClick = function()
			Windows.toggle("Gifts")
		end,
	})
	UIKit.button({
		Name = "Leaderboards",
		Text = Theme.Icons.Leaderboard,
		Color = C.Travel,
		Size = UDim2.fromOffset(66, 66),
		LayoutOrder = 3,
		Parent = cluster,
		OnClick = function()
			Windows.toggle("Leaderboards")
		end,
	})
	RunService.Heartbeat:Connect(function()
		local canClaim, count = streakInfo()
		local shown = if canClaim then count - 1 else count
		UIKit.setButtonText(streak, `{Theme.Icons.Streak} {math.max(0, shown)}`)
		HUD.highlight(streak, canClaim)
		local index, left = nextGift()
		if index == nil then
			UIKit.setButtonText(gift, `{Theme.Icons.Gift} Done`)
			HUD.highlight(gift, false)
		elseif left <= 0 then
			UIKit.setButtonText(gift, `{Theme.Icons.Gift} OPEN!`)
			HUD.highlight(gift, true)
		else
			UIKit.setButtonText(gift, `{Theme.Icons.Gift} {Format.clock(left)}`)
			HUD.highlight(gift, false)
		end
	end)
end

local function buildTracker(root: Frame)
	local tracker = UIKit.panel({
		Name = "QuestTracker",
		Size = UDim2.fromOffset(270, 170),
		Position = UDim2.new(1, -110, 0, 96),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.PanelDark,
		Parent = root,
	})
	tracker.BackgroundTransparency = 0.15
	local title = UIKit.label({
		Text = `{Theme.Icons.Quests} Daily Quests`,
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 4),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = tracker,
	})
	local open = UIKit.new("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = tracker,
	})
	open.Activated:Connect(function()
		Windows.toggle("Quests")
	end)
	local rows: { TextLabel } = {}
	for i = 1, Config.Quests.DailyCount do
		rows[i] = UIKit.label({
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 36 + (i - 1) * 42),
			XAlign = Enum.TextXAlignment.Left,
			Font = Theme.FontBody,
			MaxTextSize = 18,
			Parent = tracker,
		})
	end
	ClientState.observe("Quests", function(quests)
		local anyClaimable = false
		for i, row in rows do
			local q = quests.Daily[i]
			if q then
				local template = Defs.Quest[q.template]
				local text = string.gsub(template.text, "{n}", Format.short(q.target))
				text = string.gsub(text, "{zone}", if q.zone and Defs.Zone[q.zone] then Defs.Zone[q.zone].name else "")
				local done = q.progress >= q.target
				anyClaimable = anyClaimable or (done and not q.claimed)
				row.Text = if q.claimed
					then `<font color="#58E068">{Theme.Icons.Check}</font> <s>{text}</s>`
					else `{text}  <font color="{if done then "#58E068" else "#9FB0D8"}">{Format.short(q.progress)}/{Format.short(q.target)}</font>`
			else
				row.Text = ""
			end
		end
		for _, q in quests.Weekly do
			if q.progress >= q.target and not q.claimed then
				anyClaimable = true
			end
		end
		title.Text = `{Theme.Icons.Quests} Daily Quests{if anyClaimable then " <font color=\"#58E068\">- claim!</font>" else ""}`
		HUD.badge("Quests", anyClaimable)
	end)
end

-------------------------------------------------------------------------------
-- Windows
-------------------------------------------------------------------------------

local function dailyWindow()
	Windows.register("Daily", {
		title = "Daily Streak",
		icon = "Streak",
		color = C.Warn,
		size = Vector2.new(860, 460),
		build = function(content: Frame)
			local row = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 250), Parent = content })
			UIKit.list(row, 8, true)
			local cards: { Frame } = {}
			for i, reward in Config.DailyStreak.Rewards do
				local card = UIKit.panel({
					Size = UDim2.fromOffset(110, 240),
					Color = if i == #Config.DailyStreak.Rewards then C.Pass else C.PanelLight,
					LayoutOrder = i,
					Parent = row,
				})
				UIKit.label({ Text = `Day {i}`, Size = UDim2.new(1, -8, 0, 34), Position = UDim2.fromOffset(4, 4), MaxTextSize = 28, Parent = card })
				UIKit.label({
					Text = RetentionUI.describe(reward),
					Size = UDim2.new(1, -8, 1, -46),
					Position = UDim2.fromOffset(4, 40),
					Font = Theme.FontBody,
					MaxTextSize = 17,
					Parent = card,
				})
				cards[i] = card
			end
			local info = UIKit.label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 262), MaxTextSize = 28, Parent = content })
			local claim = UIKit.button({
				Text = "Claim!",
				Color = C.Good,
				Size = UDim2.fromOffset(300, 76),
				Position = UDim2.new(0.5, 0, 1, -8),
				AnchorPoint = Vector2.new(0.5, 1),
				MaxTextSize = 36,
				Parent = content,
				OnClick = function()
					if call("ClaimDaily") then
						Effects.shake(0.4)
					end
				end,
			})
			local function refresh()
				local canClaim, streak = streakInfo()
				local rewards = #Config.DailyStreak.Rewards
				local current = (streak - 1) % rewards + 1
				for i, card in cards do
					local stroke = card:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = if i == current then C.Charge else C.Ink
						stroke.Thickness = if i == current then 6 else 4
					end
					card.BackgroundTransparency = if i < current or (i == current and not canClaim) then 0.5 else 0
				end
				info.Text = if canClaim
					then `{Theme.Icons.Streak} Day {streak} reward is ready! Come back every day - day 7 is a guaranteed Rare+ egg.`
					else `{Theme.Icons.Streak} {streak}-day streak! Next reward in {Format.duration(Schedule.secondsUntilNextDay(now()))}`
				claim.Visible = canClaim
			end
			ClientState.observe("Daily", function()
				if Windows.isOpen("Daily") then
					refresh()
				end
			end)
			return { refresh = refresh }
		end,
	})
end

local function giftsWindow()
	Windows.register("Gifts", {
		title = "Free Gifts",
		icon = "Gift",
		color = C.Shop,
		size = Vector2.new(820, 400),
		build = function(content: Frame)
			UIKit.label({
				Text = "Gifts unlock the longer you play this session!",
				Size = UDim2.new(1, 0, 0, 32),
				Color = C.TextDim,
				MaxTextSize = 24,
				Parent = content,
			})
			local row = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40), Parent = content })
			UIKit.list(row, 10, true)
			local updaters: { () -> () } = {}
			for i, gift in Config.Gifts do
				local card = UIKit.panel({ Size = UDim2.fromOffset(145, 270), Color = C.PanelLight, LayoutOrder = i, Parent = row })
				UIKit.label({ Text = Theme.Icons.Gift, Size = UDim2.new(1, 0, 0, 60), Parent = card })
				UIKit.label({
					Text = RetentionUI.describe(gift.reward),
					Size = UDim2.new(1, -8, 0, 110),
					Position = UDim2.fromOffset(4, 62),
					Font = Theme.FontBody,
					MaxTextSize = 17,
					Parent = card,
				})
				local b = UIKit.button({
					Size = UDim2.new(1, -16, 0, 60),
					Position = UDim2.new(0, 8, 1, -68),
					Parent = card,
					OnClick = function()
						call("ClaimGift", i)
					end,
				})
				table.insert(updaters, function()
					local gifts = ClientState.get("Gifts")
					if not gifts then
						return
					end
					local claimed = table.find(gifts.claimed, i) ~= nil
					local left = gift.minutes * 60 - (now() - gifts.joinUnix)
					if claimed then
						UIKit.setButtonText(b, Theme.Icons.Check)
						UIKit.setButtonColor(b, C.PanelDark)
					elseif left <= 0 then
						UIKit.setButtonText(b, "OPEN")
						UIKit.setButtonColor(b, C.Good)
					else
						UIKit.setButtonText(b, Format.clock(left))
						UIKit.setButtonColor(b, C.PanelDark)
					end
				end)
			end
			local running = false
			return {
				refresh = function()
					if running then
						return
					end
					running = true
					task.spawn(function()
						while Windows.isOpen("Gifts") do
							for _, u in updaters do
								u()
							end
							task.wait(0.5)
						end
						running = false
					end)
				end,
			}
		end,
	})
end

local function questsWindow()
	Windows.register("Quests", {
		title = "Quests",
		icon = "Quests",
		color = C.Quests,
		size = Vector2.new(820, 540),
		build = function(content: Frame)
			local tab = "Daily"
			local tabs = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = content })
			UIKit.list(tabs, 8, true, Enum.HorizontalAlignment.Left)
			local list = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -64), Position = UDim2.fromOffset(0, 64), Parent = content })
			UIKit.list(list, 8)
			local tabButtons: { [string]: TextButton } = {}
			local render: () -> ()

			local function questRow(q: Types.QuestState, index: number, which: string)
				local template = Defs.Quest[q.template]
				local row = UIKit.panel({ Size = UDim2.new(1, -10, 0, 92), Color = C.PanelLight, LayoutOrder = index, Parent = list })
				local text = string.gsub(template.text, "{n}", Format.short(q.target))
				text = string.gsub(text, "{zone}", if q.zone and Defs.Zone[q.zone] then Defs.Zone[q.zone].name else "")
				UIKit.label({ Text = text, Size = UDim2.new(1, -220, 0, 34), Position = UDim2.fromOffset(12, 6), XAlign = Enum.TextXAlignment.Left, MaxTextSize = 26, Parent = row })
				local bar = UIKit.progress({ Size = UDim2.new(1, -230, 0, 30), Position = UDim2.fromOffset(12, 50), Color = C.Quests, Parent = row })
				bar.set(q.progress / q.target, `{Format.short(q.progress)} / {Format.short(q.target)}`)
				local done = q.progress >= q.target
				UIKit.button({
					Text = if q.claimed then Theme.Icons.Check else if done then "Claim" else "…",
					Color = if done and not q.claimed then C.Good else C.PanelDark,
					Size = UDim2.fromOffset(190, 70),
					Position = UDim2.new(1, -10, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					Parent = row,
					OnClick = function()
						if done and not q.claimed then
							call("ClaimQuest", which, index)
						else
							Effects.toast(RetentionUI.describe(template.reward):gsub("\n", ", "), C.Panel, 2.5)
						end
					end,
				})
			end

			render = function()
				for _, c in list:GetChildren() do
					if c:IsA("GuiObject") then
						c:Destroy()
					end
				end
				for name, b in tabButtons do
					UIKit.setButtonColor(b, if name == tab then C.Quests else C.PanelLight)
				end
				local quests = ClientState.get("Quests") or { Daily = {}, Weekly = {} }
				if tab == "Daily" or tab == "Weekly" then
					local resetIn = if tab == "Daily" then Schedule.secondsUntilNextDay(now()) else Schedule.secondsUntilNextWeek(now())
					UIKit.label({
						Text = `New {string.lower(tab)} quests in {Format.duration(resetIn)}`,
						Size = UDim2.new(1, 0, 0, 30),
						Color = C.TextDim,
						MaxTextSize = 22,
						LayoutOrder = 0,
						Parent = list,
					})
					for i, q in (if tab == "Daily" then quests.Daily else quests.Weekly) do
						questRow(q, i, tab)
					end
				else
					local earned = ClientState.get("Achievements") or {}
					local data = ClientState.data
					for i, a in Config.Achievements do
						local row = UIKit.panel({ Size = UDim2.new(1, -10, 0, 64), Color = if earned[a.id] then C.Quests else C.PanelLight, LayoutOrder = i, Parent = list })
						local value = if a.stat == "Ascensions"
							then data.Ascensions or 0
							elseif a.stat == "LifetimeCharge" then data.LifetimeCharge or 0
							elseif a.stat == "ZonesUnlocked" then (function()
								local n = 0
								for _ in data.UnlockedZones or {} do
									n += 1
								end
								return n
							end)()
							else ((data.Stats or {})[a.stat] or 0)
						UIKit.label({
							Text = `{if earned[a.id] then Theme.Icons.Star .. " " else ""}{a.name}`,
							Size = UDim2.new(0.5, 0, 1, -10),
							Position = UDim2.fromOffset(12, 5),
							XAlign = Enum.TextXAlignment.Left,
							MaxTextSize = 24,
							Parent = row,
						})
						UIKit.label({
							Text = `{Format.short(math.min(value, a.target))} / {Format.short(a.target)}`,
							Size = UDim2.new(0.45, -12, 1, -10),
							Position = UDim2.new(0.55, 0, 0, 5),
							XAlign = Enum.TextXAlignment.Right,
							Color = C.TextDim,
							MaxTextSize = 22,
							Parent = row,
						})
					end
				end
			end
			for i, name in { "Daily", "Weekly", "Achievements" } do
				tabButtons[name] = UIKit.button({
					Text = name,
					Color = C.PanelLight,
					Size = UDim2.fromOffset(200, 52),
					LayoutOrder = i,
					Parent = tabs,
					OnClick = function()
						tab = name
						render()
					end,
				})
			end
			for _, key in { "Quests", "Achievements" } do
				ClientState.observe(key, function()
					if Windows.isOpen("Quests") then
						render()
					end
				end)
			end
			return { refresh = render }
		end,
	})
end

local function leaderboardWindow()
	Windows.register("Leaderboards", {
		title = "Leaderboards",
		icon = "Leaderboard",
		color = C.Travel,
		size = Vector2.new(860, 540),
		build = function(content: Frame)
			local tab = "Charge"
			local tabs = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = content })
			UIKit.list(tabs, 8, true, Enum.HorizontalAlignment.Left)
			local list = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -64), Position = UDim2.fromOffset(0, 64), Parent = content })
			UIKit.list(list, 6)
			local snapshot: any = nil
			local buttons: { [string]: TextButton } = {}
			local function render()
				for _, c in list:GetChildren() do
					if c:IsA("GuiObject") then
						c:Destroy()
					end
				end
				for name, b in buttons do
					UIKit.setButtonColor(b, if name == tab then C.Travel else C.PanelLight)
				end
				if not snapshot then
					return
				end
				local rows = {}
				if tab == "Server" then
					local server = table.clone(snapshot.server)
					table.sort(server, function(a: any, b: any)
						return a.charge > b.charge
					end)
					for i, e in server do
						local best = if e.best ~= "" and Defs.Pet[e.best] then Defs.Pet[e.best].name else "-"
						table.insert(rows, { rank = i, name = e.name, text = `{Theme.Icons.Charge}{Format.short(e.charge)}  {Theme.Icons.Ascend}{e.ascensions}  {Theme.Icons.Pets}{best}` })
					end
				else
					for _, e in snapshot.global[tab].entries do
						table.insert(rows, { rank = e.rank, name = e.name, text = e.text })
					end
				end
				if #rows == 0 then
					UIKit.label({ Text = "No entries yet - be the first!", Size = UDim2.new(1, 0, 0, 60), Parent = list })
				end
				for i, r in rows do
					local row = UIKit.panel({
						Size = UDim2.new(1, -10, 0, 52),
						Color = if r.name == Players.LocalPlayer.Name or r.name == Players.LocalPlayer.DisplayName then C.Pass else C.PanelLight,
						LayoutOrder = i,
						Parent = list,
					})
					UIKit.label({ Text = `#{r.rank}  {r.name}`, Size = UDim2.new(0.5, 0, 1, -8), Position = UDim2.fromOffset(12, 4), XAlign = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = row })
					UIKit.label({ Text = r.text, Size = UDim2.new(0.5, -12, 1, -8), Position = UDim2.new(0.5, 0, 0, 4), XAlign = Enum.TextXAlignment.Right, Color = C.Static, MaxTextSize = 22, Parent = row })
				end
			end
			local order = { { "Charge", "Top Charge" }, { "Ascensions", "Ascensions" }, { "Rarest", "Rarest" }, { "Server", "This Server" } }
			for i, t in order do
				buttons[t[1]] = UIKit.button({
					Text = t[2],
					Color = C.PanelLight,
					Size = UDim2.fromOffset(190, 52),
					LayoutOrder = i,
					Parent = tabs,
					OnClick = function()
						tab = t[1]
						render()
					end,
				})
			end
			return {
				refresh = function()
					render()
					task.spawn(function()
						snapshot = Net.Client.invoke("GetLeaderboards")
						render()
					end)
				end,
			}
		end,
	})
end

-- Roblox Premium perks panel (engagement-based payouts): perks only, no pressure.
local function premiumButton(root: Frame)
	local b = UIKit.button({
		Name = "Premium",
		Text = "Premium",
		Color = C.Robux,
		Size = UDim2.fromOffset(130, 44),
		Position = UDim2.new(1, -110, 0, 274),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 22,
		Parent = root,
		OnClick = function()
			if ClientState.get("Premium") then
				if call("ClaimPremiumDaily") then
					Effects.toast("Thanks for being Premium!", C.Robux)
				end
			else
				Effects.toast(`Premium members get +{math.floor(Config.Premium.ChargeBonus * 100)}% Charge and a daily gift.`, C.Robux, 3)
				pcall(function()
					MarketplaceService:PromptPremiumPurchase(Players.LocalPlayer)
				end)
			end
		end,
	})
	ClientState.observe("Premium", function(isPremium)
		UIKit.setButtonText(b, if isPremium then "Premium gift" else "Premium perks")
	end)
end

function RetentionUI.start()
	local root = HUD.root()
	buildCluster(root)
	buildTracker(root)
	premiumButton(root)
	dailyWindow()
	giftsWindow()
	questsWindow()
	leaderboardWindow()
end

return RetentionUI
