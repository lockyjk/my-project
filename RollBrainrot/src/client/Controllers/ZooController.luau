--!strict
-- Renders every zoo's Brainrots as living creatures wandering their habitats (client-side,
-- from ReplicatedStorage.ZooState). Nearby zoos animate every frame, distant ones are
-- culled. Also hides other players' zoo prompts (unlock / collect) for this client.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Animator = require(Modules:WaitForChild("Models"):WaitForChild("Animator"))
local BrainrotModels = require(Modules.Models:WaitForChild("BrainrotModels"))
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Net = require(Modules:WaitForChild("Net"))
local Registry = require(Modules:WaitForChild("Registry"))

local ClientState = require(script.Parent.ClientState)
local Effects = require(script.Parent.Effects)
local Notifications = require(script.Parent.Parent.UI.Notifications)

local ZooController = {}

local W = GameConfig.World
local FLOOR_Y = 0.4
local RENDER_DIST = 520
local ANIM_DIST = 260

type Creature = {
	uid: string,
	id: string,
	mut: string,
	habitat: string,
	model: Model,
	rig: Animator.Rig,
	pos: Vector3,
	yaw: number,
	goal: Vector3,
	speed: number,
	waitUntil: number,
	nextQuirk: number,
	bounds: { center: CFrame, half: Vector2 },
	nextCoin: number,
	mine: boolean,
}

type Plot = { index: number, creatures: { [string]: Creature }, rendered: boolean, contents: { any } }

local plots: { [number]: Plot } = {}
local coinPop: (Creature, number) -> ()
local folder: Folder
local player = Players.LocalPlayer

local function plotCFrame(index: number): CFrame
	local p = W.Plots[index]
	return CFrame.lookAt(p.origin, p.origin + p.facing)
end

local function habitatBounds(index: number, habitatId: string): { center: CFrame, half: Vector2 }
	local hi = Registry.HabitatIndex[habitatId] or 1
	local center = plotCFrame(index) * CFrame.new(W.HabitatOffsets[hi])
	local size = if habitatId == "Giant" then W.GiantHabitatSize else W.HabitatSize
	return { center = center, half = Vector2.new(size.X / 2 - 4, size.Y / 2 - 4) }
end

local function randomPoint(bounds: { center: CFrame, half: Vector2 }): Vector3
	local p = bounds.center
		* CFrame.new((math.random() * 2 - 1) * bounds.half.X, 0, (math.random() * 2 - 1) * bounds.half.Y)
	return Vector3.new(p.X, FLOOR_Y, p.Z)
end

local function nameTag(model: Model, id: string, mut: string)
	local def = Registry.Brainrot[id]
	if not def or not model.PrimaryPart then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 4) + 1.6, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Registry.displayName(id, mut)
	label.TextColor3 = Registry.Rarity[def.rarity].color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
end

local function isMine(plotIndex: number): boolean
	return player:GetAttribute("Plot") == plotIndex
end

-- Petting (own zoo only): hearts, a happy hop and a little burst of income into the bank
local function petPrompt(c: Creature)
	local root = c.model.PrimaryPart
	local def = Registry.Brainrot[c.id]
	if not root or not def then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pet ❤"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 20)
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		local ok, result = Net.Client.invoke("PetBrainrot", c.uid)
		local head = c.pos + Vector3.new(0, c.rig.height + 1.5, 0)
		if ok then
			Animator.quirk(c.rig, "Hop")
			Effects.burst(head, Color3.fromRGB(255, 110, 170), 18, "sparkle", 10, 1.2)
			Effects.floatText(head, `❤ +${Format.short(result)}`, Color3.fromRGB(255, 140, 190), 7, 5)
			Effects.sound("Coins", 0.4, c.pos, 1.3)
		elseif type(result) == "number" then
			Notifications.toast(`{def.name} is happy already — pet again in {result}s`, Color3.fromRGB(255, 170, 210))
		end
	end)
end

local function spawnCreature(plot: Plot, entry: any): Creature?
	local def = Registry.Brainrot[entry.id]
	if not def then
		return nil
	end
	local bounds = habitatBounds(plot.index, entry.h)
	local model = BrainrotModels.build(entry.id, entry.mut)
	model.Parent = folder
	nameTag(model, entry.id, entry.mut)
	local pos = randomPoint(bounds)
	local c: Creature = {
		uid = entry.uid,
		id = entry.id,
		mut = entry.mut,
		habitat = entry.h,
		model = model,
		rig = Animator.rig(model, def.idleQuirk),
		pos = pos,
		yaw = math.random() * math.pi * 2,
		goal = pos,
		speed = (GameConfig.SpeedTiers[def.speed] or 14) * (if def.idleQuirk == "Zoom" then 0.9 else 0.35),
		waitUntil = os.clock() + math.random() * 3,
		nextQuirk = os.clock() + 4 + math.random() * 10,
		bounds = bounds,
		nextCoin = os.clock() + 4 + math.random() * 8,
		mine = isMine(plot.index),
	}
	if c.mine then
		petPrompt(c)
	end
	return c
end

local function clearPlot(plot: Plot)
	for _, c in plot.creatures do
		c.model:Destroy()
	end
	table.clear(plot.creatures)
	plot.rendered = false
end

local function syncPlot(plot: Plot)
	if not plot.rendered then
		return
	end
	local seen: { [string]: boolean } = {}
	for _, entry in plot.contents do
		local key = entry.uid
		seen[key] = true
		local existing = plot.creatures[key]
		if existing and (existing.habitat ~= entry.h or existing.mut ~= entry.mut) then
			existing.model:Destroy()
			plot.creatures[key] = nil
		end
		if not plot.creatures[key] then
			local c = spawnCreature(plot, entry)
			if c then
				plot.creatures[key] = c
			end
		end
	end
	for key, c in plot.creatures do
		if not seen[key] then
			c.model:Destroy()
			plot.creatures[key] = nil
		end
	end
end

local function readContents(plot: Plot, cfg: Configuration)
	local raw = cfg:GetAttribute("Contents")
	local ok, list = pcall(HttpService.JSONDecode, HttpService, if type(raw) == "string" then raw else "[]")
	plot.contents = if ok and type(list) == "table" then list else {}
	syncPlot(plot)
end

local function step(c: Creature, now: number, dt: number)
	if now < c.waitUntil then
		Animator.update(c.rig, CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0), now, false)
		if now >= c.nextQuirk then
			c.nextQuirk = now + 6 + math.random() * 12
			Animator.quirk(c.rig)
		end
		return
	end
	local delta = Vector3.new(c.goal.X - c.pos.X, 0, c.goal.Z - c.pos.Z)
	local d = delta.Magnitude
	if d < 0.6 then
		c.goal = randomPoint(c.bounds)
		c.waitUntil = now + 1 + math.random() * 4
		return
	end
	local stepLen = math.min(d, c.speed * dt)
	c.pos += delta.Unit * stepLen
	local targetYaw = math.atan2(-delta.X, -delta.Z)
	local diff = (targetYaw - c.yaw + math.pi) % (2 * math.pi) - math.pi
	c.yaw += diff * math.min(1, dt * 8)
	Animator.update(c.rig, CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0), now, true, c.speed / 10)
end

-- Your own Brainrots visibly "earn": a little +$ pops above them every ~12 s
coinPop = function(c: Creature, distance: number)
	if distance > 160 then
		return
	end
	local inst = ClientState.inventory[c.uid]
	local habitat = Registry.Habitat[c.habitat]
	local zoo = ClientState.data.zoo
	local h = zoo and zoo.habitats[c.habitat]
	if not inst or not habitat or not h then
		return
	end
	local perMin = BrainrotMath.placedIncome(inst, habitat, h.level)
	local amount = perMin * 12 / 60
	if amount < 0.5 then
		return
	end
	local head = c.pos + Vector3.new(0, c.rig.height + 1, 0)
	Effects.floatText(head, `+${Format.short(math.floor(amount + 0.5))}`, Color3.fromRGB(255, 220, 80), 5, 4)
end

-- A pile of gold on your collector pad that grows with the uncollected bank
local pile: Model? = nil
local pileCount = 0

local function updatePile()
	local index = player:GetAttribute("Plot")
	local zoo = ClientState.data.zoo
	if type(index) ~= "number" or not zoo then
		return
	end
	local bank = zoo.bank or 0
	local want = if bank < 1 then 0 else math.clamp(math.floor(math.log10(bank + 1) * 3), 1, 14)
	if want == pileCount and pile then
		return
	end
	pileCount = want
	if pile then
		pile:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "CoinPile"
	local base = (plotCFrame(index) * CFrame.new(0, 0.6, -66)).Position
	local rng = Random.new(index)
	for i = 1, want do
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.5, 2.2, 2.2)
		coin.Color = Color3.fromRGB(255, 205, 50)
		coin.Material = Enum.Material.Foil
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		local layer = math.floor((i - 1) / 4)
		local a = (i % 4) * math.pi / 2 + layer
		coin.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 1.3, 0.3 + layer * 0.5, math.sin(a) * 1.3))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, math.rad(90) + rng:NextNumber(-0.3, 0.3))
		coin.Parent = m
	end
	m.Parent = folder
	pile = m
end

-- Only the owner of a plot sees its unlock / collect prompts
local function filterPrompts()
	local myPlot = player:GetAttribute("Plot")
	local world = Workspace:FindFirstChild("World")
	local zoos = world and world:FindFirstChild("Zoos")
	if not zoos then
		return
	end
	for _, plotModel in zoos:GetChildren() do
		local mine = plotModel:GetAttribute("PlotIndex") == myPlot
		for _, d in plotModel:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				local action = d:GetAttribute("Action")
				if action == "UnlockHabitat" or action == "CollectZoo" then
					if not mine then
						d.Enabled = false
					end
				end
			end
		end
	end
end

function ZooController.start()
	local live = Workspace:WaitForChild("Live")
	folder = Instance.new("Folder")
	folder.Name = "ZooCreatures"
	folder.Parent = live
	local state = ReplicatedStorage:WaitForChild("ZooState")
	ClientState.Changed:Connect(function(key)
		if key == "zoo" then
			updatePile()
		end
	end)
	player:GetAttributeChangedSignal("Plot"):Connect(function()
		for _, plot in plots do
			clearPlot(plot) -- rebuild so pet prompts land on the right zoo
		end
		updatePile()
	end)
	for i in W.Plots do
		local plot: Plot = { index = i, creatures = {}, rendered = false, contents = {} }
		plots[i] = plot
		task.spawn(function()
			local cfg = state:WaitForChild(`Plot{i}`) :: Configuration
			readContents(plot, cfg)
			cfg:GetAttributeChangedSignal("Contents"):Connect(function()
				readContents(plot, cfg)
			end)
		end)
	end

	-- distance culling (1 Hz) + prompt filter
	task.spawn(function()
		while true do
			local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
			for i, plot in plots do
				local d = (W.Plots[i].origin - camPos).Magnitude
				if d < RENDER_DIST and not plot.rendered then
					plot.rendered = true
					syncPlot(plot)
				elseif d > RENDER_DIST + 60 and plot.rendered then
					clearPlot(plot)
				end
			end
			filterPrompts()
			task.wait(1)
		end
	end)

	local frame = 0
	RunService.Heartbeat:Connect(function(dt: number)
		frame += 1
		local now = os.clock()
		local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
		for i, plot in plots do
			if plot.rendered then
				local d = (W.Plots[i].origin - camPos).Magnitude
				-- far zoos tick at a quarter rate
				if d < ANIM_DIST or frame % 4 == i % 4 then
					local stepDt = if d < ANIM_DIST then dt else dt * 4
					for _, c in plot.creatures do
						step(c, now, stepDt)
						if c.mine and now >= c.nextCoin then
							c.nextCoin = now + 9 + math.random() * 6
							coinPop(c, d)
						end
					end
				end
			end
		end
	end)
end

return ZooController
