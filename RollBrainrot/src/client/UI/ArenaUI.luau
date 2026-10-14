--!strict
-- Arena select (opened at the stadium gate or from the menu): every arena difficulty with
-- unlock requirements, recommended power vs your team, best wave and boss, plus JOIN when
-- a battle is already running.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Format = require(Modules:WaitForChild("Format"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))
local Types = require(Modules:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Bus = require(script.Parent.Bus)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)
local Viewport = require(script.Parent.Viewport)
local Windows = require(script.Parent.Windows)

local ArenaUI = {}

local C = Theme.Colors
local list: ScrollingFrame
local runBanner: Frame
local runLabel: TextLabel

local function canEnter(arena: Types.ArenaDef): (boolean, string?)
	local d = ClientState.data
	if (d.level or 1) < arena.requiredLevel then
		return false, `Reach level {arena.requiredLevel}`
	end
	if arena.requiresArena and not (d.arena and d.arena.beaten[arena.requiresArena]) then
		return false, `Beat {Registry.Arena[arena.requiresArena].name}`
	end
	return true
end

local function enter(arenaId: string?)
	local ok = Notifications.call("ArenaEnter", arenaId)
	if ok then
		Windows.close()
	end
end

function ArenaUI.refresh()
	if not list then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local running = ReplicatedStorage:GetAttribute("ArenaRun")
	local state = ReplicatedStorage:GetAttribute("ArenaState")
	if type(running) == "string" and running ~= "" and state ~= "victory" and state ~= "defeat" then
		runBanner.Visible = true
		local a = Registry.Arena[running]
		runLabel.Text = `⚔️ A battle is running in {a and a.name or running} (wave {ReplicatedStorage:GetAttribute(
			"ArenaWave"
		) or 0})!`
	else
		runBanner.Visible = false
	end
	local power = ClientState.teamPower()
	local d = ClientState.data
	for i, arena in Registry.Arenas do
		local ok, why = canEnter(arena)
		local beaten = d.arena and d.arena.beaten[arena.id]
		local row = UIKit.panel({
			Size = UDim2.new(1, -12, 0, 118),
			Color = if ok then C.PanelLight else C.PanelDark,
			LayoutOrder = i,
			Parent = list,
		})
		local swatch = UIKit.new(
			"Frame",
			{
				BackgroundColor3 = arena.floorColor,
				Size = UDim2.fromOffset(14, 94),
				Position = UDim2.fromOffset(10, 12),
				Parent = row,
			}
		)
		UIKit.corner(swatch, 6)
		local bossId = arena.waves[#arena.waves].spawns[1].monster
		local boss = Registry.Monster[bossId]
		local holder = UIKit.panel({
			Size = UDim2.fromOffset(100, 100),
			Position = UDim2.fromOffset(32, 9),
			Color = C.PanelDark,
			Parent = row,
			Gradient = false,
		})
		if ok then
			Viewport.new({
				id = bossId,
				monster = true,
				parent = holder,
				size = UDim2.new(1, -4, 1, -4),
				position = UDim2.fromOffset(2, 2),
				zindex = 3,
			})
		else
			UIKit.label({ Text = "🔒", Size = UDim2.fromScale(1, 1), MaxTextSize = 50, Parent = holder })
		end
		UIKit.label({
			Text = `{i}. {arena.name}{if beaten then "  ✅" else ""}`,
			Size = UDim2.fromOffset(500, 32),
			Position = UDim2.fromOffset(144, 6),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 28,
			Parent = row,
		})
		UIKit.label({
			Text = arena.description,
			Size = UDim2.fromOffset(560, 22),
			Position = UDim2.fromOffset(144, 40),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
			Font = Theme.FontBody,
			Stroke = 1,
			Color = C.TextDim,
			Parent = row,
		})
		local ratio = power / arena.recommendedPower
		local powerColor = if ratio >= 1 then C.Good elseif ratio >= 0.6 then C.Warn else C.Bad
		UIKit.label({
			Text = `Boss: {boss and boss.name or bossId}   ·   Recommended ⚔️ {Format.short(
				arena.recommendedPower
			)} (you: {Format.short(power)})`,
			Size = UDim2.fromOffset(640, 22),
			Position = UDim2.fromOffset(144, 66),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
			Color = powerColor,
			Parent = row,
		})
		UIKit.label({
			Text = `Rewards ×{Format.short(arena.rewardMult)}   ·   Best wave {d.arena and d.arena.bestWave[arena.id] or 0}/{#arena.waves}`,
			Size = UDim2.fromOffset(640, 22),
			Position = UDim2.fromOffset(144, 90),
			XAlign = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
			Color = C.Coins,
			Parent = row,
		})
		UIKit.button({
			Text = if ok then "⚔️ FIGHT!" else `🔒 {why}`,
			Color = if ok then C.Bad else C.Locked,
			Size = UDim2.fromOffset(200, 64),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = if ok then 28 else 16,
			Parent = row,
			OnClick = function()
				if ok then
					enter(arena.id)
				end
			end,
		})
	end
end

function ArenaUI.start()
	Windows.register("Arena", {
		title = "MONSTER ARENA",
		icon = "🏟️",
		color = Color3.fromRGB(220, 50, 60),
		size = Vector2.new(1100, 640),
		build = function(content: Frame)
			runBanner = UIKit.panel({
				Size = UDim2.new(1, 0, 0, 64),
				Color = Color3.fromRGB(120, 30, 40),
				Visible = false,
				Parent = content,
			})
			runLabel = UIKit.label({
				Text = "",
				Size = UDim2.new(1, -240, 1, -10),
				Position = UDim2.fromOffset(12, 5),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = runBanner,
			})
			UIKit.button({
				Text = "JOIN BATTLE",
				Color = C.Good,
				Size = UDim2.fromOffset(210, 52),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				MaxTextSize = 24,
				Parent = runBanner,
				OnClick = function()
					enter(nil)
				end,
			})
			list =
				UIKit.scroll({ Size = UDim2.new(1, 0, 1, -72), Position = UDim2.fromOffset(0, 72), Parent = content })
			UIKit.list(list, 8, false, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Top
			return { refresh = ArenaUI.refresh }
		end,
	})
	Bus.PromptAction:Connect(function(action: string)
		if action == "EnterArena" then
			Windows.open("Arena")
		end
	end)
	for _, attr in { "ArenaRun", "ArenaState", "ArenaWave" } do
		ReplicatedStorage:GetAttributeChangedSignal(attr):Connect(function()
			if Windows.isOpen("Arena") then
				ArenaUI.refresh()
			end
		end)
	end
end

return ArenaUI
