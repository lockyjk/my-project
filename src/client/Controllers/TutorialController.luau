--!strict
-- First-time tutorial: catch -> sell -> upgrade, designed to finish in under 60 seconds.
-- The server grants a small bonus after the first sell so the first upgrade is affordable.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.ClientState)
local Effects = require(script.Parent.Effects)
local SpiritController = require(script.Parent.SpiritController)
local HUD = require(script.Parent.Parent.UI.HUD)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local UpgradesUI = require(script.Parent.Parent.UI.UpgradesUI)
local Windows = require(script.Parent.Parent.UI.Windows)

local TutorialController = {}
local C = Theme.Colors

local panel: Frame
local text: TextLabel
local arrow: BillboardGui?
local step = 0
local caught = 0

local function setText(t: string)
	text.Text = t
	panel.Visible = true
	UIKit.pop(panel, 0.85)
end

local function clearArrow()
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
end

local function pointAtNearestSpirit()
	local s = SpiritController.nearest()
	local target = if s then s.model.PrimaryPart else nil
	if not target then
		-- no spirit in range yet: point at any spirit
		local folder = workspace:FindFirstChild("Spirits")
		local any = folder and folder:FindFirstChildOfClass("Model")
		target = if any then any.PrimaryPart else nil
	end
	if not target then
		clearArrow()
		return
	end
	if not arrow then
		local bb = UIKit.new("BillboardGui", {
			Size = UDim2.fromOffset(80, 80),
			StudsOffset = Vector3.new(0, 5, 0),
			AlwaysOnTop = true,
		})
		UIKit.label({ Text = "⬇", Color = C.Charge, Size = UDim2.fromScale(1, 1), Parent = bb })
		arrow = bb
	end
	(arrow :: BillboardGui).Adornee = target;
	(arrow :: BillboardGui).Parent = target
end

local function advance(n: number)
	step = n
	Net.Client.fire("TutorialStep", n)
	HUD.highlight(HUD.button("Home"), false)
	HUD.highlight(HUD.button("Upgrades"), false)
	if n == 1 then
		setText(`Tap spirits to catch them with your Storm Jar! (0/{Config.Tutorial.CatchesNeeded})`)
	elseif n == 2 then
		clearArrow()
		setText(`Your jar is filling with Static! Tap {Theme.Icons.Home} HOME to sell it for Charge.`)
		HUD.highlight(HUD.button("Home"), true)
	elseif n == 3 then
		setText(`Now spend your Charge! Open {Theme.Icons.Upgrades} Upgrades and buy one.`)
		HUD.highlight(HUD.button("Upgrades"), true)
	elseif n >= 4 then
		clearArrow()
		panel.Visible = false
		Effects.banner("You're a Storm Chaser!", C.Charge, 3)
		Effects.toast("Unlock new zones at the glowing gates. Storms hit every 10 minutes!", C.Panel, 5)
	end
end

function TutorialController.start()
	panel = UIKit.panel({
		Name = "Tutorial",
		Size = UDim2.fromOffset(560, 70),
		Position = UDim2.new(0.5, 0, 0, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Quests,
		Visible = false,
		Parent = HUD.root(),
	})
	text = UIKit.label({ Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxTextSize = 26, Parent = panel })

	task.spawn(TutorialController.run)
end

function TutorialController.run()
	ClientState.waitLoaded()
	local flags = ClientState.get("Flags") or {}
	if flags.TutorialDone then
		return
	end
	advance(1)

	SpiritController.Caught:Connect(function()
		if step ~= 1 then
			return
		end
		caught += 1
		text.Text = `Tap spirits to catch them with your Storm Jar! ({caught}/{Config.Tutorial.CatchesNeeded})`
		if caught >= Config.Tutorial.CatchesNeeded then
			advance(2)
		end
	end)
	ClientState.observe("Static", function(v: number)
		if step == 2 and v == 0 then
			advance(3)
		end
	end)
	ClientState.observe("Upgrades", function(levels)
		if step == 3 then
			local total = 0
			for _, l in levels do
				total += l
			end
			if total > 0 then
				advance(4)
			end
		end
	end)
	Windows.Opened:Connect(function(name)
		if step == 3 and name == "Upgrades" then
			HUD.highlight(UpgradesUI.rows.JarCapacity, true)
		end
	end)
	ClientState.observe("Flags", function(f)
		if f.TutorialDone and step < 4 then
			advance(4)
		end
	end)

	task.spawn(function()
		while step == 1 do
			pointAtNearestSpirit()
			task.wait(0.3)
		end
		clearArrow()
	end)
end

return TutorialController
