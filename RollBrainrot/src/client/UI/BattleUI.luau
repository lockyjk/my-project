--!strict
-- Battle HUD (arena runs and invasions):
--   top: wave / status panel, giant boss health bar, LEAVE button
--   bottom: your team's HP cards, ability buttons with cooldown sweeps + Ultimate charge
--   centre: WAVE banners, the boss-entrance WARNING cinematic, VICTORY
-- Data comes from the "Battle" push (≈4 Hz) and battle events.

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Net = require(Modules:WaitForChild("Net"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CombatController = require(script.Parent.Parent.Controllers.CombatController)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local UnitRenderer = require(script.Parent.Parent.Controllers.UnitRenderer)
local Bus = require(script.Parent.Bus)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)

local BattleUI = {}

local C = Theme.Colors
local PA = GameConfig.PlayerAbilities
local player = Players.LocalPlayer

local root: Frame
local hud: Frame
local wavePanel: Frame
local waveLabel: TextLabel
local subLabel: TextLabel
local bossPanel: Frame
local bossName: TextLabel
local bossTitle: TextLabel
local bossBar: UIKit.Progress
local teamRow: Frame
local abilityButtons: { [string]: { button: TextButton, shade: Frame, timer: TextLabel } } = {}
local chargeFill: Frame
local banner: TextLabel
local bannerSub: TextLabel
local warning: Frame
local totalsLabel: TextLabel
local state: { [string]: any } = { active = false }
local teamCards: { [string]: { frame: Frame, fill: Frame, label: TextLabel } } = {}

BattleUI.state = state

-------------------------------------------------------------------------------
local function showBanner(text: string, sub: string?, color: Color3?, hold: number?)
	banner.Text = text
	banner.TextColor3 = color or C.Warn
	bannerSub.Text = sub or ""
	banner.Visible = true
	bannerSub.Visible = sub ~= nil
	UIKit.pop(banner, 0.4)
	task.delay(hold or 2.2, function()
		if banner.Text == text then
			banner.Visible = false
			bannerSub.Visible = false
		end
	end)
end
BattleUI.banner = showBanner

local function rebuildTeam(team: { any })
	local seen = {}
	for i, t in team do
		local key = t.uid or tostring(i)
		seen[key] = true
		local card = teamCards[key]
		if not card then
			local def = Registry.Brainrot[t.id]
			local frame = UIKit.panel({
				Size = UDim2.fromOffset(92, 56),
				Color = C.PanelDark,
				LayoutOrder = i,
				Parent = teamRow,
				Corner = 10,
				Gradient = false,
			})
			UIKit.label({
				Text = if def then def.emoji else "?",
				Size = UDim2.new(1, 0, 0, 30),
				MaxTextSize = 26,
				Parent = frame,
			})
			local bar = UIKit.new(
				"Frame",
				{
					BackgroundColor3 = C.Ink,
					Size = UDim2.new(1, -10, 0, 10),
					Position = UDim2.new(0, 5, 1, -16),
					Parent = frame,
				}
			)
			UIKit.corner(bar, 4)
			local fill = UIKit.new("Frame", { BackgroundColor3 = C.Hp, Size = UDim2.fromScale(1, 1), Parent = bar })
			UIKit.corner(fill, 4)
			local label = UIKit.label({
				Text = "",
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 4),
				MaxTextSize = 20,
				Color = C.Bad,
				ZIndex = 3,
				Parent = frame,
			})
			if def then
				local stroke = frame:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = Registry.Rarity[def.rarity].color
				end
			end
			card = { frame = frame, fill = fill, label = label }
			teamCards[key] = card
		end
		local c = card :: { frame: Frame, fill: Frame, label: TextLabel }
		local f = if t.alive then math.clamp(t.hp / math.max(1, t.mhp), 0, 1) else 0
		c.fill.Size = UDim2.fromScale(f, 1)
		c.fill.BackgroundColor3 = if f > 0.5 then C.Hp elseif f > 0.25 then C.Warn else C.Bad
		c.label.Text = if t.alive then "" else `💀 {math.ceil(t.respawn or 0)}s`
		c.frame.BackgroundTransparency = if t.alive then 0 else 0.4
	end
	for key, card in teamCards do
		if not seen[key] then
			card.frame:Destroy()
			teamCards[key] = nil
		end
	end
end

local function onHud(s: { [string]: any })
	local wasActive = state.active
	table.clear(state)
	for k, v in s do
		state[k] = v
	end
	hud.Visible = s.active == true
	if not s.active then
		if wasActive then
			bossPanel.Visible = false
			for _, card in teamCards do
				card.frame:Destroy()
			end
			table.clear(teamCards)
		end
		return
	end
	CombatController.sync(s.cooldowns, s.charge)
	CombatController.chargeNeeded = s.chargeNeeded or CombatController.chargeNeeded
	-- wave panel
	local status = s.status
	if status == "countdown" then
		waveLabel.Text = `{s.arenaName or "ARENA"}`
		subLabel.Text = `Battle starts in {math.ceil(s.timer or 0)}… ({s.fighters or 1} fighter{if (s.fighters or 1)
				== 1
			then ""
			else "s"})`
	elseif status == "intermission" then
		waveLabel.Text = `WAVE {s.wave} CLEARED!`
		subLabel.Text = `Next wave in {math.ceil(s.timer or 0)}s`
	elseif status == "victory" then
		waveLabel.Text = "🏆 VICTORY!"
		subLabel.Text = "Returning to the hub soon…"
	else
		waveLabel.Text = if s.waves and s.waves > 1
			then `WAVE {s.wave}/{s.waves}{if s.label then "  ·  " .. s.label else ""}`
			else (s.label or s.arenaName or "BATTLE")
		subLabel.Text = `👾 {s.enemies + (s.queued or 0)} monsters left  ·  ⚔️ {s.fighters} fighter{if s.fighters
				== 1
			then ""
			else "s"}`
	end
	-- boss bar
	local boss = s.boss
	if boss then
		bossPanel.Visible = true
		bossName.Text = (if boss.enraged then "😡 " else "👹 ") .. boss.name
		bossTitle.Text = boss.title or ""
		bossBar.set(boss.hp / math.max(1, boss.mhp), `{Format.short(boss.hp)} / {Format.short(boss.mhp)}`)
		bossBar.fill.BackgroundColor3 = if boss.enraged then Color3.fromRGB(255, 40, 90) else C.Boss
	else
		bossPanel.Visible = false
	end
	rebuildTeam(s.team or {})
	local t = s.totals or {}
	totalsLabel.Text = `💰 {Format.short(t.coins or 0)}   ⭐ {Format.short(t.xp or 0)}   💀 {t.kills or 0}`
end

-------------------------------------------------------------------------------
-- Boss entrance cinematic
-------------------------------------------------------------------------------
local function bossIntro(battleId: number, ev: { [string]: any })
	if player:GetAttribute("BattleId") ~= battleId then
		return
	end
	Bus.BossIntro:Fire(ev)
	Bus.Crowd:Fire("roar", 1)
	warning.Visible = true
	local warnLabel = warning:FindFirstChild("Warn") :: TextLabel
	local sub = warning:FindFirstChild("Sub") :: TextLabel
	local nameLabel = warning:FindFirstChild("BossName") :: TextLabel
	local titleLabel = warning:FindFirstChild("BossTitle") :: TextLabel
	warnLabel.Visible = true
	sub.Visible = true
	nameLabel.Visible = false
	titleLabel.Visible = false
	sub.Text = if ev.landing then "A GIANT MONSTER HAS LANDED IN THE ZOO!" else "A GIANT MONSTER HAS ENTERED THE ARENA"
	Effects.darken(0.45, 0.4)
	Effects.sound("RevealBig", 0.8, nil, 0.6)
	-- flashing WARNING
	task.spawn(function()
		for i = 1, 8 do
			warnLabel.TextTransparency = if i % 2 == 0 then 0.6 else 0
			Effects.flash(Color3.fromRGB(255, 30, 30), 0.18, 0.2)
			task.wait(0.22)
		end
		warnLabel.TextTransparency = 0
	end)
	-- camera: look at the boss from the battlefield, then a low hero shot
	local v = UnitRenderer.get(battleId, ev.id)
	local dur = ev.dur or 5
	if v then
		local bossPos = v.pos
		local height = v.height
		local towards = (UnitRenderer.center(battleId) or bossPos) - bossPos
		local dir = if towards.Magnitude > 1 then Vector3.new(towards.X, 0, towards.Z).Unit else Vector3.new(0, 0, 1)
		local far = bossPos + dir * height * 2.2 + Vector3.new(0, height * 0.35, 0)
		local close = bossPos + dir * height * 0.9 + Vector3.new(0, height * 0.15, 0)
		task.spawn(function()
			CameraController.cinematic("BossIntro", {
				{
					cf = CFrame.lookAt(far, bossPos + Vector3.new(0, height * 0.55, 0)),
					time = 0.8,
					hold = dur * 0.35,
					fov = 60,
				},
				{
					cf = CFrame.lookAt(close, bossPos + Vector3.new(0, height * 0.85, 0)),
					time = dur * 0.25,
					hold = dur * 0.2,
					fov = 50,
				},
			})
		end)
		task.delay(0.6, function()
			Effects.shake(1.6, 1.2)
		end)
	end
	task.wait(dur * 0.45)
	warnLabel.Visible = false
	sub.Visible = false
	local def = Registry.Monster[ev.d]
	nameLabel.Text = ev.name or (def and def.name) or "BOSS"
	titleLabel.Text = ev.title or ""
	nameLabel.Visible = true
	titleLabel.Visible = true
	UIKit.pop(nameLabel, 0.3)
	Effects.shake(1, 0.6)
	task.wait(dur * 0.5)
	warning.Visible = false
	Effects.darken(0, 0.6)
end

-------------------------------------------------------------------------------
local function abilityButton(parent: Instance, name: string, size: number, order: number)
	local def = PA[name]
	local key = if def.key then (def.key :: Enum.KeyCode).Name else "Click"
	local b = UIKit.button({
		Text = "",
		Color = if name == "Ultimate" then C.Primary elseif name == "Attack" then C.Bad else C.PanelLight,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = order,
		Corner = size // 2,
		Parent = parent,
		OnClick = function()
			CombatController.use(name)
		end,
	})
	UIKit.label({
		Text = def.icon,
		Size = UDim2.fromScale(0.6, 0.5),
		Position = UDim2.fromScale(0.2, 0.12),
		MaxTextSize = 40,
		ZIndex = 3,
		Parent = b,
	})
	UIKit.label({
		Text = `{def.label} [{key}]`,
		Size = UDim2.new(1.4, 0, 0, 18),
		Position = UDim2.new(-0.2, 0, 1, 2),
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = b,
	})
	local shade = UIKit.new(
		"Frame",
		{
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 0),
			Position = UDim2.fromScale(0, 1),
			AnchorPoint = Vector2.new(0, 1),
			ZIndex = 4,
			Parent = b,
		}
	)
	UIKit.corner(shade, size // 2)
	local timer = UIKit.label({
		Text = "",
		Size = UDim2.fromScale(1, 0.5),
		Position = UDim2.fromScale(0, 0.45),
		MaxTextSize = 26,
		ZIndex = 5,
		Parent = b,
	})
	abilityButtons[name] = { button = b, shade = shade, timer = timer }
	return b
end

function BattleUI.start()
	local gui, scale = UIKit.screen("BattleUI", 3, player:WaitForChild("PlayerGui"))
	root = UIKit.root(gui, scale)
	hud =
		UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })

	wavePanel = UIKit.panel({
		Size = UDim2.fromOffset(520, 70),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.PanelDark,
		Parent = hud,
	})
	waveLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 4),
		MaxTextSize = 32,
		Color = C.Warn,
		Parent = wavePanel,
	})
	subLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 40),
		MaxTextSize = 20,
		Parent = wavePanel,
	})

	bossPanel = UIKit.panel({
		Size = UDim2.fromOffset(760, 92),
		Position = UDim2.new(0.5, 0, 0, 88),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Color3.fromRGB(50, 20, 30),
		Visible = false,
		Parent = hud,
	})
	bossName = UIKit.label({
		Text = "",
		Size = UDim2.new(0.6, 0, 0, 36),
		Position = UDim2.fromOffset(14, 4),
		XAlign = Enum.TextXAlignment.Left,
		MaxTextSize = 34,
		Color = Color3.fromRGB(255, 90, 90),
		Parent = bossPanel,
	})
	bossTitle = UIKit.label({
		Text = "",
		Size = UDim2.new(0.4, -20, 0, 28),
		Position = UDim2.new(0.6, 0, 0, 8),
		XAlign = Enum.TextXAlignment.Right,
		MaxTextSize = 18,
		Color = C.TextDim,
		Parent = bossPanel,
	})
	bossBar = UIKit.progress({
		Size = UDim2.new(1, -28, 0, 34),
		Position = UDim2.fromOffset(14, 46),
		Color = C.Boss,
		Parent = bossPanel,
	})

	-- leave + totals
	UIKit.button({
		Text = "🚪 LEAVE",
		Color = C.Bad,
		Size = UDim2.fromOffset(140, 50),
		Position = UDim2.new(1, -16, 0, 150),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 24,
		Parent = hud,
		OnClick = function()
			Notifications.call("ArenaLeave")
		end,
	})
	totalsLabel = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(320, 30),
		Position = UDim2.new(1, -16, 0, 206),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Right,
		MaxTextSize = 22,
		Color = C.Coins,
		Parent = hud,
	})

	-- team
	teamRow = UIKit.new(
		"Frame",
		{
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(900, 60),
			Position = UDim2.new(0.5, 0, 1, -20),
			AnchorPoint = Vector2.new(0.5, 1),
			Parent = hud,
		}
	)
	UIKit.list(teamRow, 8, true, Enum.HorizontalAlignment.Center)

	-- abilities (bottom right)
	local abilities = UIKit.new(
		"Frame",
		{
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(420, 200),
			Position = UDim2.new(1, -20, 1, -30),
			AnchorPoint = Vector2.new(1, 1),
			Parent = hud,
		}
	)
	local attack = abilityButton(abilities, "Attack", 110, 0)
	attack.Position = UDim2.new(1, -110, 1, -130)
	local small = { "Dodge", "Heal", "Rally" }
	for i, name in small do
		local b = abilityButton(abilities, name, 72, i)
		b.Position = UDim2.new(1, -130 - i * 88, 1, -100)
	end
	local ult = abilityButton(abilities, "Ultimate", 84, 4)
	ult.Position = UDim2.new(1, -96, 1, -230)
	local chargeBack = UIKit.new(
		"Frame",
		{ BackgroundColor3 = C.Ink, Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, 22), Parent = ult }
	)
	UIKit.corner(chargeBack, 5)
	chargeFill = UIKit.new("Frame", { BackgroundColor3 = C.Primary, Size = UDim2.fromScale(0, 1), Parent = chargeBack })
	UIKit.corner(chargeFill, 5)

	-- centre banners
	banner = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(900, 90),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 84,
		Stroke = 4,
		Parent = root,
	})
	banner.Visible = false
	bannerSub = UIKit.label({
		Text = "",
		Size = UDim2.fromOffset(900, 40),
		Position = UDim2.new(0.5, 0, 0.3, 56),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 34,
		Parent = root,
	})
	bannerSub.Visible = false

	warning = UIKit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = root }
	)
	local w = UIKit.label({
		Name = "Warn",
		Text = "⚠️ WARNING ⚠️",
		Size = UDim2.fromOffset(900, 120),
		Position = UDim2.fromScale(0.5, 0.35),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 110,
		Color = Color3.fromRGB(255, 50, 50),
		Stroke = 5,
		ZIndex = 21,
		Parent = warning,
	})
	w.Name = "Warn"
	local sub = UIKit.label({
		Name = "Sub",
		Text = "",
		Size = UDim2.fromOffset(1000, 50),
		Position = UDim2.new(0.5, 0, 0.35, 80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 40,
		ZIndex = 21,
		Parent = warning,
	})
	sub.Name = "Sub"
	local bn = UIKit.label({
		Name = "BossName",
		Text = "",
		Size = UDim2.fromOffset(1000, 130),
		Position = UDim2.fromScale(0.5, 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 120,
		Color = Color3.fromRGB(255, 80, 80),
		Stroke = 6,
		ZIndex = 21,
		Parent = warning,
	})
	bn.Name = "BossName"
	local bt = UIKit.label({
		Name = "BossTitle",
		Text = "",
		Size = UDim2.fromOffset(900, 44),
		Position = UDim2.new(0.5, 0, 0.72, 78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 36,
		Color = Theme.Colors.TextDim,
		ZIndex = 21,
		Parent = warning,
	})
	bt.Name = "BossTitle"

	Net.Client.on("Battle", onHud)
	UnitRenderer.Event:Connect(function(battleId: number, ev: { [string]: any })
		if player:GetAttribute("BattleId") ~= battleId then
			return
		end
		local t = ev.t
		if t == "wave" then
			showBanner(`WAVE {ev.n}`, ev.label, if ev.label then C.Bad else C.Warn)
			Effects.sound("RevealBig", 0.4, nil, 1.3)
			Bus.Crowd:Fire("cheer", 0.6)
		elseif t == "waveclear" then
			showBanner("WAVE CLEARED!", "Get ready…", C.Good, 2)
			Bus.Crowd:Fire("cheer", 0.8)
		elseif t == "bossintro" then
			task.spawn(bossIntro, battleId, ev)
		elseif t == "victory" then
			showBanner("🏆 VICTORY! 🏆", "The giant has fallen!", C.Coins, 5)
			Effects.confetti(200)
			Effects.flash(Color3.fromRGB(255, 240, 180), 0.4, 0.8)
			Bus.Crowd:Fire("celebrate", 1)
		elseif t == "die" then
			local v = UnitRenderer.get(battleId, ev.id)
			if v and v.isBoss then
				Effects.shake(2.5, 1.5)
				Effects.flash(Color3.new(1, 1, 1), 0.6, 0.6)
				Bus.Crowd:Fire("celebrate", 1)
			elseif v and v.team == "enemy" then
				Bus.Crowd:Fire("cheer", 0.08)
			end
		elseif t == "ab" or (t == "hit" and ev.c) then
			Bus.Crowd:Fire("cheer", 0.12)
		elseif t == "tele" then
			Bus.Crowd:Fire("gasp", 0.4)
		end
	end)

	-- cooldown sweeps + charge (render rate)
	game:GetService("RunService").RenderStepped:Connect(function()
		if not hud.Visible then
			return
		end
		for name, b in abilityButtons do
			local left = CombatController.cooldownLeft(name)
			local cd = PA[name].cooldown
			local frac = if cd > 0 then math.clamp(left / cd, 0, 1) else 0
			b.shade.Size = UDim2.fromScale(1, frac)
			b.timer.Text = if left > 0.6 and name ~= "Attack" then tostring(math.ceil(left)) else ""
		end
		local charge = CombatController.charge / math.max(1, CombatController.chargeNeeded)
		chargeFill.Size = UDim2.fromScale(math.clamp(charge, 0, 1), 1)
		local ult = abilityButtons.Ultimate
		if ult then
			ult.shade.Size = UDim2.fromScale(1, if charge >= 1 then 0 else 1 - charge)
			ult.timer.Text = if charge >= 1 then "READY!" else ""
		end
	end)
end

return BattleUI
