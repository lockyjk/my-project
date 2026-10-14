--!strict
-- Roll interface:
--   * machine panel (shown near the machine): Luck, PITY x/100, next pity, cost, the big
--     ROLL BRAINROT button, Auto Roll / Skip / Odds toggles
--   * name cycler (rapidly changing possibilities that slow down onto the result)
--   * reveal card: 3D model, name, rarity, mutation, stats, power, EQUIP / SEND TO ZOO /
--     VIEW / ROLL AGAIN
-- RollController drives the timing; this module only draws.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Net = require(Modules:WaitForChild("Net"))
local Registry = require(Modules:WaitForChild("Registry"))
local RollMath = require(Modules:WaitForChild("RollMath"))
local Theme = require(Modules:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local BrainrotInfo = require(script.Parent.BrainrotInfo)
local Bus = require(script.Parent.Bus)
local UIKit = require(script.Parent.UIKit)
local Viewport = require(script.Parent.Viewport)

local RollUI = {}

local C = Theme.Colors

-- callbacks set by RollController
RollUI.onRoll = nil :: (() -> ())?
RollUI.onAutoChanged = nil :: ((boolean) -> ())?

local root: Frame
local panel: Frame
local luckLabel: TextLabel
local pityLabel: TextLabel
local pityBar: UIKit.Progress
local rollButton: TextButton
local costLabel: TextLabel
local autoButton: TextButton
local skipButton: TextButton
local oddsPanel: Frame
local oddsList: Frame
local cycler: Frame
local cyclerName: TextLabel
local cyclerRarity: TextLabel
local reveal: Frame
local revealVp: ViewportFrame?
local revealVpHolder: Frame
local sheet: BrainrotInfo.Sheet
local newTag: TextLabel
local soldLabel: TextLabel
local revealButtons: { [string]: TextButton } = {}
local currentUid: string? = nil
local near = false
local rolling = false
RollUI.auto = false

-------------------------------------------------------------------------------
function RollUI.refresh()
	local d = ClientState.data
	local luck = ClientState.luck()
	luckLabel.Text = `🍀 Luck: {string.format("%.2f", luck)}x`
	local pity = (d.pity and d.pity[GameConfig.Roll.Pity.id]) or 0
	local threshold = GameConfig.Roll.Pity.threshold
	pityLabel.Text = `PITY: {pity}/{threshold}  ·  {GameConfig.Roll.Pity.minRarity}+ in {threshold - pity} rolls`
	pityBar.set(pity / threshold)
	local tokens = d.tokens or 0
	if tokens > 0 then
		costLabel.Text = `🎟️ 1 Token  ({tokens} left)`
	else
		costLabel.Text = `💰 ${Format.commas(GameConfig.Roll.CoinCost)}`
	end
	UIKit.setButtonText(autoButton, if RollUI.auto then "🔁 Auto: ON" else "🔁 Auto: OFF")
	UIKit.setButtonColor(autoButton, if RollUI.auto then C.Good else C.PanelLight)
	local skip = d.settings and d.settings.skipRoll
	skipButton.Visible = d.seenRollAnim == true
	UIKit.setButtonText(skipButton, if skip then "⏩ Skip: ON" else "⏩ Skip: OFF")
	UIKit.setButtonColor(skipButton, if skip then C.Good else C.PanelLight)
	-- odds
	if oddsPanel.Visible then
		for _, c in oddsList:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		for i, row in RollMath.odds(luck) do
			UIKit.label({
				Text = `{row.rarity.id}: <b>{Format.chance(row.chance)}</b>`,
				Color = row.rarity.color,
				Size = UDim2.new(1, 0, 0, 24),
				MaxTextSize = 20,
				LayoutOrder = i,
				Parent = oddsList,
			})
		end
		for i, row in RollMath.mutationOdds(luck) do
			if row.mutation.id ~= "Normal" then
				UIKit.label({
					Text = `{row.mutation.id} (×{row.mutation.statMult}): {Format.chance(row.chance)}`,
					Color = row.mutation.color or Color3.fromRGB(255, 160, 230),
					Size = UDim2.new(1, 0, 0, 20),
					MaxTextSize = 16,
					LayoutOrder = 20 + i,
					Parent = oddsList,
				})
			end
		end
	end
	panel.Visible = near and not rolling and not reveal.Visible
end

function RollUI.setNear(isNear: boolean)
	near = isNear
	if not isNear then
		oddsPanel.Visible = false
	end
	RollUI.refresh()
end

function RollUI.setRolling(isRolling: boolean)
	rolling = isRolling
	RollUI.refresh()
end

-------------------------------------------------------------------------------
-- Name cycler: flashes random Brainrot names, slowing down, ending on the result
-------------------------------------------------------------------------------
function RollUI.cycle(duration: number, finalId: string, finalMut: string)
	cycler.Visible = true
	UIKit.pop(cycler, 0.8)
	local names = GameConfig.Roll.DisplayCycleNames
	for i = 1, names do
		-- ease-out timing: early flips fast, the last few slow
		local f = i / names
		local wait = duration * (f * f - ((i - 1) / names) ^ 2)
		local def = Registry.Brainrots[math.random(1, #Registry.Brainrots)]
		if i == names then
			def = Registry.Brainrot[finalId]
		end
		local rarity = Registry.Rarity[def.rarity]
		cyclerName.Text = `{def.emoji} {if i == names then Registry.displayName(def.id, finalMut) else def.name}`
		cyclerName.TextColor3 = rarity.color
		cyclerRarity.Text = def.rarity:upper()
		cyclerRarity.TextColor3 = rarity.color
		UIKit.sound("RollTick", 0.25 + f * 0.3)
		task.wait(math.max(0.03, wait))
	end
end

function RollUI.hideCycler()
	cycler.Visible = false
end

-------------------------------------------------------------------------------
-- Reveal card
-------------------------------------------------------------------------------
function RollUI.showReveal(payload: { [string]: any })
	currentUid = payload.uid
	if revealVp then
		Viewport.set(revealVp, payload.id, payload.mut)
	else
		revealVp =
			Viewport.new({ id = payload.id, mut = payload.mut, spin = true, parent = revealVpHolder, zindex = 6 })
	end
	sheet.set(payload.id, payload.mut, 1)
	newTag.Visible = payload.isNew == true
	soldLabel.Visible = payload.autoSold == true
	for name, b in revealButtons do
		if name ~= "Again" then
			b.Visible = payload.uid ~= nil
		end
	end
	local rarity = Registry.Rarity[payload.rarity]
	local stroke = reveal:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.color
		stroke.Thickness = 3 + rarity.fxTier
	end
	reveal.Visible = true
	UIKit.pop(reveal, 0.5)
	RollUI.refresh()
end

function RollUI.hideReveal()
	reveal.Visible = false
	RollUI.refresh()
end

function RollUI.isRevealOpen(): boolean
	return reveal.Visible
end

-------------------------------------------------------------------------------
function RollUI.start()
	local gui, scale = UIKit.screen("RollUI", 4, Players.LocalPlayer:WaitForChild("PlayerGui"))
	root = UIKit.root(gui, scale)

	-- machine panel ------------------------------------------------------------
	panel = UIKit.new("Frame", {
		Name = "MachinePanel",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(520, 236),
		Position = UDim2.new(0.5, 0, 1, -118),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = root,
	})
	luckLabel =
		UIKit.label({ Text = "", Size = UDim2.fromOffset(520, 30), Color = C.Good, MaxTextSize = 28, Parent = panel })
	pityLabel = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(520, 24),
		Position = UDim2.fromOffset(0, 30),
		MaxTextSize = 20,
		Color = C.Warn,
		Parent = panel,
	})
	pityBar = UIKit.progress({
		Size = UDim2.fromOffset(360, 14),
		Position = UDim2.fromOffset(80, 58),
		Color = C.Warn,
		Parent = panel,
	})
	rollButton = UIKit.button({
		Text = if UIKit.hasImage("roll") then "      ROLL BRAINROT" else "🎰 ROLL BRAINROT",
		Color = C.Primary,
		Size = UDim2.fromOffset(400, 96),
		Position = UDim2.fromOffset(60, 80),
		MaxTextSize = 44,
		Parent = panel,
		OnClick = function()
			if RollUI.onRoll then
				RollUI.onRoll()
			end
		end,
	})
	if UIKit.hasImage("roll") then
		UIKit.icon({
			Key = "roll",
			Fallback = "",
			Size = UDim2.fromOffset(84, 84),
			Position = UDim2.fromOffset(10, 4),
			ZIndex = rollButton.ZIndex + 2,
			Name = "RollArt",
			Parent = rollButton,
		})
	end
	costLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -24),
		MaxTextSize = 18,
		Parent = rollButton,
	})
	-- gentle "breathing" glow on the button
	local s = rollButton:FindFirstChildOfClass("UIScale") :: UIScale
	task.spawn(function()
		while true do
			if panel.Visible and s.Scale >= 0.99 then
				TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Scale = 1.04 }):Play()
				task.wait(0.6)
				TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			end
			task.wait(0.65)
		end
	end)
	local row = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(520, 46),
		Position = UDim2.fromOffset(0, 186),
		Parent = panel,
	})
	UIKit.list(row, 10, true, Enum.HorizontalAlignment.Center)
	autoButton = UIKit.button({
		Text = "🔁 Auto: OFF",
		Color = C.PanelLight,
		Size = UDim2.fromOffset(150, 42),
		MaxTextSize = 20,
		LayoutOrder = 1,
		Parent = row,
		OnClick = function()
			if not ClientState.hasPass("AutoRoll") then
				local ok = Net.Client.invoke("PromptPass", "AutoRoll")
				if not ok then
					Bus.OpenWindow:Fire("Shop")
				end
				return
			end
			RollUI.auto = not RollUI.auto
			if RollUI.onAutoChanged then
				RollUI.onAutoChanged(RollUI.auto)
			end
			RollUI.refresh()
		end,
	})
	skipButton = UIKit.button({
		Text = "⏩ Skip: OFF",
		Color = C.PanelLight,
		Size = UDim2.fromOffset(150, 42),
		MaxTextSize = 20,
		LayoutOrder = 2,
		Parent = row,
		OnClick = function()
			local cur = ClientState.data.settings and ClientState.data.settings.skipRoll
			Net.Client.invoke("SetSetting", "skipRoll", not cur)
		end,
	})
	UIKit.button({
		Text = "📊 Odds",
		Color = C.PanelLight,
		Size = UDim2.fromOffset(120, 42),
		MaxTextSize = 20,
		LayoutOrder = 3,
		Parent = row,
		OnClick = function()
			oddsPanel.Visible = not oddsPanel.Visible
			RollUI.refresh()
		end,
	})
	oddsPanel = UIKit.panel({
		Size = UDim2.fromOffset(300, 300),
		Position = UDim2.new(0.5, 280, 1, -120),
		AnchorPoint = Vector2.new(0, 1),
		Visible = false,
		Parent = root,
	})
	UIKit.label({
		Text = "ROLL ODDS (with your luck)",
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.fromOffset(8, 6),
		MaxTextSize = 20,
		Parent = oddsPanel,
	})
	oddsList = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, -44),
		Position = UDim2.fromOffset(8, 38),
		Parent = oddsPanel,
	})
	UIKit.list(oddsList, 2, false, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Top

	-- name cycler ------------------------------------------------------------------
	cycler = UIKit.panel({
		Size = UDim2.fromOffset(560, 110),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.PanelDark,
		Visible = false,
		Parent = root,
	})
	cyclerName = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 64),
		Position = UDim2.fromOffset(10, 8),
		MaxTextSize = 52,
		Parent = cycler,
	})
	cyclerRarity = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 72),
		MaxTextSize = 26,
		Parent = cycler,
	})

	-- reveal card --------------------------------------------------------------------
	reveal = UIKit.panel({
		Name = "Reveal",
		Size = UDim2.fromOffset(820, 470),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Parent = root,
	})
	revealVpHolder = UIKit.panel({
		Size = UDim2.fromOffset(330, 330),
		Position = UDim2.fromOffset(20, 20),
		Color = C.PanelDark,
		ZIndex = 5,
		Parent = reveal,
		Gradient = false,
	})
	sheet = BrainrotInfo.new(reveal, UDim2.fromOffset(440, 340), UDim2.fromOffset(365, 14))
	newTag = UIKit.label({
		Text = "✨ NEW! ✨",
		Size = UDim2.fromOffset(160, 40),
		Position = UDim2.fromOffset(30, 26),
		Color = C.Warn,
		MaxTextSize = 30,
		ZIndex = 7,
		Parent = reveal,
	})
	newTag.Rotation = -12
	soldLabel = UIKit.label({
		Text = "Storage full — it was auto-sold!",
		Size = UDim2.fromOffset(330, 30),
		Position = UDim2.fromOffset(20, 352),
		Color = C.Bad,
		MaxTextSize = 20,
		Parent = reveal,
	})
	local buttons = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 80),
		Position = UDim2.new(0, 20, 1, -90),
		Parent = reveal,
	})
	UIKit.list(buttons, 12, true, Enum.HorizontalAlignment.Center)
	local function act(name: string, text: string, color: Color3, order: number, fn: () -> ())
		revealButtons[name] = UIKit.button({
			Text = text,
			Color = color,
			Size = UDim2.fromOffset(180, 70),
			MaxTextSize = 26,
			LayoutOrder = order,
			Parent = buttons,
			OnClick = fn,
		})
	end
	act("Equip", "⚔️ EQUIP", C.Good, 1, function()
		if currentUid then
			local ok = Net.Client.invoke("Equip", currentUid, true)
			if not ok then
				-- slots full: let the player choose who to swap out
				Bus.ViewBrainrot:Fire(currentUid)
			end
		end
		RollUI.hideReveal()
	end)
	act("Zoo", "🏡 SEND TO ZOO", C.Secondary, 2, function()
		if currentUid then
			Net.Client.invoke("SendToZoo", currentUid, nil)
		end
		RollUI.hideReveal()
	end)
	act("View", "📖 VIEW", C.PanelLight, 3, function()
		local uid = currentUid
		RollUI.hideReveal()
		Bus.ViewBrainrot:Fire(uid)
	end)
	act("Again", "🎰 ROLL AGAIN", C.Primary, 4, function()
		RollUI.hideReveal()
		if RollUI.onRoll then
			RollUI.onRoll()
		end
	end)
	UIKit.button({
		Text = Theme.Icons.Close,
		Color = C.Bad,
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(1, 12, 0, -12),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 8,
		Parent = reveal,
		OnClick = function()
			RollUI.hideReveal()
		end,
	})

	ClientState.Changed:Connect(function(key)
		if
			key == "pity"
			or key == "tokens"
			or key == "coins"
			or key == "settings"
			or key == "seenRollAnim"
			or key == "passes"
		then
			RollUI.refresh()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Luck"):Connect(RollUI.refresh)
end

return RollUI
