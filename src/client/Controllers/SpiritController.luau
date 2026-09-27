--!strict
-- Renders the spirits in the player's current zone from a model pool, and handles catching:
-- tap/click a spirit (or anywhere to vacuum the nearest one), hold to keep catching once the
-- Catch Rod allows it, or automatic catching with the Auto-Catch pass.
-- The server re-validates every catch (range, cooldown, jar, zone access).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.ClientState)
local Effects = require(script.Parent.Effects)
local ModelFactory = require(script.Parent.ModelFactory)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SpiritController = {}

type Spirit = { id: number, def: string, pos: Vector3, model: Model, phase: number, size: number }

local player = Players.LocalPlayer
local folder: Folder
local spirits: { [number]: Spirit } = {}
local recent: { [number]: Vector3 } = {} -- positions of just-removed spirits (for catch popups)
local pools: { [string]: { Model } } = {}
local currentZone = ""
local lastSend = 0
local holding = false
local rangeRing: Part

SpiritController.Caught = Signal.new() :: Signal.Signal<number, boolean>

local function zoneIndex(zoneId: string): number
	local z = Defs.Zone[zoneId]
	return if z then math.max(1, z.index) else 1
end

local function acquire(defId: string): Model
	local pool = pools[defId]
	if pool and #pool > 0 then
		return table.remove(pool) :: Model
	end
	local def = Defs.Spirit[defId]
	local rarityOrder = Defs.rarityOrder(def.rarity)
	return ModelFactory.creature({
		id = defId,
		shape = def.shape,
		size = def.size * Theme.zoneScale(zoneIndex(currentZone)),
		color = def.color,
		glow = def.storm ~= nil or rarityOrder >= 4,
		aura = if rarityOrder >= 3 then Defs.Rarity[def.rarity].color else nil,
	})
end

local function release(s: Spirit)
	s.model.Parent = nil
	local pool = pools[s.def]
	if not pool then
		pool = {}
		pools[s.def] = pool
	end
	if #pool < 30 then
		table.insert(pool, s.model)
	else
		s.model:Destroy()
	end
end

local function add(entry: { any }, pop: boolean)
	local id: number, defId: string = entry[1], entry[2]
	if spirits[id] or not Defs.Spirit[defId] then
		return
	end
	local pos = Vector3.new(entry[3], entry[4], entry[5])
	local model = acquire(defId)
	model:PivotTo(CFrame.new(pos))
	model.Parent = folder
	local ext = model:GetExtentsSize()
	spirits[id] = { id = id, def = defId, pos = pos, model = model, phase = math.random() * math.pi * 2, size = ext.Y }
	-- spawn pop (not for whole-zone snapshots)
	local body = model.PrimaryPart
	if pop and body then
		Effects.burst(pos, (body :: BasePart).Color, 6, 0.6)
	end
end

local function remove(id: number)
	local s = spirits[id]
	if s then
		spirits[id] = nil
		recent[id] = s.pos
		task.delay(3, function()
			recent[id] = nil
		end)
		release(s)
	end
end

local function clear()
	for id in spirits do
		remove(id)
	end
	-- pools were sized for the old zone's scale; drop them
	for _, pool in pools do
		for _, m in pool do
			m:Destroy()
		end
	end
	table.clear(pools)
end

-------------------------------------------------------------------------------
-- Catching
-------------------------------------------------------------------------------

local function rootPart(): BasePart?
	local c = player.Character
	return if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function jarFull(): boolean
	local d = ClientState.derived()
	return d.Capacity ~= nil and (ClientState.get("Static") or 0) >= d.Capacity and not ClientState.hasPass("AutoSell")
end

local function nearest(maxRange: number): Spirit?
	local hrp = rootPart()
	if not hrp then
		return nil
	end
	local best, bestD = nil, maxRange
	for _, s in spirits do
		local d = hrp.Position - s.pos
		local flat = Vector3.new(d.X, 0, d.Z).Magnitude
		if flat <= bestD then
			best, bestD = s, flat
		end
	end
	return best
end

local function beam(target: Vector3, color: Color3)
	local hrp = rootPart()
	if not hrp then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 1)
	a0.Parent = hrp
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.Position = target
	holder.Parent = Workspace
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = ColorSequence.new(Theme.Colors.Static, color)
	b.LightEmission = 1
	b.Width0 = 1.4
	b.Width1 = 0.3
	b.FaceCamera = true
	b.Segments = 6
	b.CurveSize0 = 2
	b.Parent = holder
	task.delay(0.18, function()
		a0:Destroy()
		holder:Destroy()
	end)
end

local function tryCatch(target: Spirit?): boolean
	local d = ClientState.derived()
	if not d.Cooldown or not target then
		return false
	end
	local t = os.clock()
	if t - lastSend < d.Cooldown then
		return false
	end
	if jarFull() then
		Effects.toast("Your Storm Jar is full! Tap HOME to sell.", Theme.Colors.Warn, 1.5)
		lastSend = t + 1
		return false
	end
	local hrp = rootPart()
	if not hrp then
		return false
	end
	local delta = hrp.Position - target.pos
	if Vector3.new(delta.X, 0, delta.Z).Magnitude > d.Range then
		return false
	end
	lastSend = t
	local body = target.model.PrimaryPart
	beam(target.pos, if body then (body :: BasePart).Color else Theme.Colors.Static)
	Net.Client.fire("CatchSpirit", target.id)
	return true
end

local function spiritFromScreen(screenPos: Vector2): Spirit?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		for _, s in spirits do
			if s.model == model then
				return s
			end
		end
	end
	return nil
end

local function onPress(screenPos: Vector2)
	local d = ClientState.derived()
	local clicked = spiritFromScreen(screenPos)
	if clicked then
		tryCatch(clicked)
	else
		tryCatch(nearest(d.Range or 16))
	end
end

-------------------------------------------------------------------------------
-- Per-frame
-------------------------------------------------------------------------------

local function step(dt: number)
	local t = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	for _, s in spirits do
		local toCam = camPos - s.pos
		if toCam.Magnitude < 300 then
			local bob = math.sin(t * 2.2 + s.phase) * 0.6
			local look = Vector3.new(toCam.X, 0, toCam.Z)
			local cf = if look.Magnitude > 0.1
				then CFrame.lookAt(s.pos, s.pos - look) -- face camera (model front is -Z)
				else CFrame.new(s.pos)
			s.model:PivotTo(cf * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.pi + math.sin(t + s.phase) * 0.3, 0))
		end
	end

	-- Hold-to-catch and Auto-Catch
	local d = ClientState.derived()
	local settings = ClientState.get("Settings")
	local auto = ClientState.hasPass("AutoCatch") and (settings == nil or settings.AutoCatch ~= false)
	if (holding and d.HoldToCatch) or auto then
		tryCatch(nearest(d.Range or 16))
	end

	-- Range ring under the player while in a zone
	local hrp = rootPart()
	if hrp and currentZone ~= "" and d.Range then
		rangeRing.Parent = Workspace
		rangeRing.Size = Vector3.new(0.2, d.Range * 2, d.Range * 2)
		rangeRing.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	else
		rangeRing.Parent = nil
	end
end

function SpiritController.nearest(): Spirit?
	return nearest(ClientState.derived().Range or 16)
end

-- On-screen CATCH button (touch/console): press = one catch, hold = keep catching
function SpiritController.setHolding(value: boolean)
	holding = value
	if value then
		tryCatch(nearest(ClientState.derived().Range or 16))
	end
end

function SpiritController.count(): number
	local n = 0
	for _ in spirits do
		n += 1
	end
	return n
end

function SpiritController.start()
	folder = Instance.new("Folder")
	folder.Name = "Spirits"
	folder.Parent = Workspace

	rangeRing = Instance.new("Part")
	rangeRing.Name = "CatchRange"
	rangeRing.Shape = Enum.PartType.Cylinder
	rangeRing.Anchored = true
	rangeRing.CanCollide = false
	rangeRing.CanQuery = false
	rangeRing.CanTouch = false
	rangeRing.Material = Enum.Material.Neon
	rangeRing.Color = Theme.Colors.Static
	rangeRing.Transparency = 0.85
	rangeRing.CastShadow = false

	Net.Client.on("Spirits", function(op: string, zoneId: string, payload: { any })
		if op == "snapshot" then
			if zoneId ~= currentZone then
				clear()
				currentZone = zoneId
			else
				for id in spirits do
					remove(id)
				end
			end
			for _, entry in payload do
				add(entry, false)
			end
		elseif op == "spawn" and zoneId == currentZone then
			for _, entry in payload do
				add(entry, true)
			end
		elseif op == "despawn" and zoneId == currentZone then
			for _, id in payload do
				local s = spirits[id]
				if s then
					local body = s.model.PrimaryPart
					Effects.burst(s.pos, if body then (body :: BasePart).Color else Theme.Colors.Static, 10, 0.8)
				end
				remove(id)
			end
		end
	end)

	Net.Client.on("CatchFx", function(spiritId: number, amount: number, shiny: boolean, rarity: string)
		local pos = recent[spiritId] or (rootPart() and (rootPart() :: BasePart).Position) or Vector3.zero
		local color = if shiny then Theme.Colors.Charge else Theme.Colors.Static
		local text = `+{Format.short(amount)}`
		if shiny then
			text = `✨ SHINY +{Format.short(amount)}`
		end
		Effects.popupWorld(pos + Vector3.new(0, 3, 0), text, color, if shiny then 52 else 38)
		local order = Defs.rarityOrder(rarity)
		if shiny or order >= 4 then
			Effects.shake(if shiny then 0.5 else 0.3)
			Effects.burst(pos, color, 30, 1.4)
			UIKit.sound("CatchRare")
		else
			UIKit.sound("Catch", 0.35)
		end
		SpiritController.Caught:Fire(spiritId, shiny)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = true
			onPress(Vector2.new(input.Position.X, input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding = true
			tryCatch(nearest(ClientState.derived().Range or 16))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonR2
		then
			holding = false
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return SpiritController
