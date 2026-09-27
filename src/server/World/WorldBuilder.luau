--!strict
-- Builds the placeholder world from Config + WorldLayout + Theme using basic parts.
-- Every part is tagged "Placeholder" and has an "ArtistNote" attribute describing what an
-- artist should replace it with. Swap any piece by putting a model with the same name in
-- ServerStorage/ArtOverrides (see README) - the builder uses it instead of parts.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Format = require(Shared.Format)
local Theme = require(Shared.Theme)
local WorldLayout = require(Shared.WorldLayout)

local WorldBuilder = {}

local TW = Theme.World
local world: Folder

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Note: string,
}

local function part(parent: Instance, props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color
	p.Shape = props.Shape or Enum.PartType.Block
	p.Material = props.Material or TW.Material
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.Transparency == nil or props.Transparency < 0.5
	p:SetAttribute("ArtistNote", props.Note)
	CollectionService:AddTag(p, TW.PlaceholderTag)
	p.Parent = parent
	return p
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Artist override: ServerStorage.ArtOverrides.<name> (Model with PrimaryPart) replaces the placeholder
local function override(name: string, cf: CFrame, parent: Instance): Model?
	local folder = ServerStorage:FindFirstChild("ArtOverrides")
	local source = folder and folder:FindFirstChild(name)
	if source and source:IsA("Model") and source.PrimaryPart then
		local clone = source:Clone()
		clone:PivotTo(cf)
		clone.Parent = parent
		return clone
	end
	return nil
end

local function label(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, textScale: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = parent
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Theme.Font
	tl.TextScaled = true
	tl.Text = text
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0
	tl.TextStrokeColor3 = Theme.Colors.Ink
	tl.Parent = gui
	local pad = Instance.new("UIPadding")
	local p = UDim.new(textScale or 0.08, 0)
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = p, p, p, p
	pad.Parent = tl
end

local function billboard(parent: Instance, text: string, color: Color3, size: UDim2, offset: Vector3): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffsetWorldSpace = offset
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Parent = parent
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Theme.Font
	tl.TextScaled = true
	tl.RichText = true
	tl.Text = text
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0
	tl.TextStrokeColor3 = Theme.Colors.Ink
	tl.Parent = bb
	return bb
end

-- Stepped floating-island underside: layered blocks that shrink as they go down
local function islandBody(parent: Instance, center: Vector3, size: number, top: Color3, zoneNote: string)
	part(parent, {
		Name = "Ground",
		Size = Vector3.new(size, TW.IslandThickness, size),
		CFrame = CFrame.new(center - Vector3.new(0, TW.IslandThickness / 2, 0)),
		Color = top,
		Material = TW.GroundMaterial,
		Note = `{zoneNote} ground: stylised grass/snow/sand top, keep flat walkable area`,
	})
	local rock = Theme.darken(top, 0.45)
	local y = center.Y - TW.IslandThickness
	local s = size
	for layer = 1, 3 do
		s *= 0.72
		local h = TW.IslandThickness * (0.9 - layer * 0.15)
		y -= h / 2
		part(parent, {
			Name = `Underside{layer}`,
			Size = Vector3.new(s, h, s),
			CFrame = CFrame.new(center.X, y, center.Z),
			Color = rock:Lerp(Theme.Colors.Ink, layer * 0.12),
			CanCollide = false,
			Note = "Floating island rock underside (stepped blocks)",
		})
		y -= h / 2
	end
	-- Neon trim around the top edge
	local accentNote = "Glowing edge trim"
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local along = if d.X ~= 0 then Vector3.new(1.2, 1.2, size) else Vector3.new(size, 1.2, 1.2)
		part(parent, {
			Name = "Trim",
			Size = along,
			CFrame = CFrame.new(center + d * (size / 2) + Vector3.new(0, -0.4, 0)),
			Color = Theme.lighten(top, 0.35),
			Material = TW.TrimMaterial,
			CanCollide = false,
			Note = accentNote,
		})
	end
end

local function cloud(parent: Instance, position: Vector3, scale: number, rng: Random)
	local m = model(parent, "Cloud")
	local b = TW.CloudBlock * scale
	for _ = 1, rng:NextInteger(3, 6) do
		local offset = Vector3.new(rng:NextNumber(-1.5, 1.5) * b, rng:NextNumber(-0.3, 0.6) * b, rng:NextNumber(-1, 1) * b)
		part(m, {
			Name = "Puff",
			Size = Vector3.new(b, b * 0.8, b) * rng:NextNumber(0.8, 1.5),
			CFrame = CFrame.new(position + offset),
			Color = TW.CloudColor,
			CanCollide = false,
			Transparency = 0.05,
			Note = "Blocky cloud puff",
		})
	end
end

-- Zone-themed chunky props around the edge of an island
local function prop(parent: Instance, zoneIndex: number, position: Vector3, accent: Color3, ground: Color3, rng: Random)
	local scale = Theme.zoneScale(zoneIndex) * rng:NextNumber(0.8, 1.3)
	local kind = rng:NextInteger(1, 3)
	local m = model(parent, "Prop")
	if kind == 1 then
		-- blocky tree / crystal spire
		local trunkH = 8 * scale
		part(m, {
			Name = "Trunk",
			Size = Vector3.new(2.5, trunkH, 2.5) * Vector3.new(scale, 1, scale),
			CFrame = CFrame.new(position + Vector3.new(0, trunkH / 2, 0)),
			Color = Theme.darken(ground, 0.5),
			Note = "Tree trunk / pillar",
		})
		part(m, {
			Name = "Canopy",
			Size = Vector3.new(9, 7, 9) * scale,
			CFrame = CFrame.new(position + Vector3.new(0, trunkH + 3 * scale, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color = Theme.lighten(accent, 0.1),
			Note = "Blocky canopy / crystal top",
		})
	elseif kind == 2 then
		-- stacked rock
		for i = 1, 3 do
			local s = (7 - i * 1.6) * scale
			part(m, {
				Name = "Rock",
				Size = Vector3.new(s, s * 0.7, s),
				CFrame = CFrame.new(position + Vector3.new(0, (i - 0.5) * s * 0.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = Theme.darken(ground, 0.2 + i * 0.05),
				Note = "Stacked boulder",
			})
		end
	else
		-- glowing storm crystal
		local h = 10 * scale
		part(m, {
			Name = "Crystal",
			Size = Vector3.new(3, h, 3) * Vector3.new(scale, 1, scale),
			CFrame = CFrame.new(position + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-12, 12))),
			Color = accent,
			Material = TW.GlowMaterial,
			Note = "Storm crystal (emissive)",
		})
	end
end

local function bridge(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3, accent: Color3)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt(mid, to)
	part(parent, {
		Name = "Bridge",
		Size = Vector3.new(width, 2, length),
		CFrame = cf * CFrame.new(0, -1, 0),
		Color = color,
		Note = "Cloud/plank sky bridge",
	})
	for _, side in { -1, 1 } do
		part(parent, {
			Name = "Rail",
			Size = Vector3.new(1, 3, length),
			CFrame = cf * CFrame.new(side * (width / 2 - 0.5), 1.5, 0),
			Color = accent,
			Material = TW.TrimMaterial,
			Note = "Glowing bridge rail",
		})
	end
end

local function eggStand(parent: Instance, eggId: string, position: Vector3, scale: number)
	local egg = Defs.Egg[eggId]
	local firstPet = Defs.Pet[egg.pets[#egg.pets].pet]
	local m = model(parent, `EggStand_{eggId}`)
	local cf = CFrame.new(position)
	if not override("EggStand", cf, m) then
		part(m, {
			Name = "Pedestal",
			Size = Vector3.new(4, 12 * scale, 12 * scale),
			CFrame = cf * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Theme.Colors.PanelDark,
			Shape = Enum.PartType.Cylinder,
			Note = "Egg pedestal",
		})
		part(m, {
			Name = "Ring",
			Size = Vector3.new(1, 13 * scale, 13 * scale),
			CFrame = cf * CFrame.new(0, 4.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = firstPet.color,
			Material = TW.GlowMaterial,
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			Note = "Glowing pedestal ring (rarity colour of the egg's best pet)",
		})
	end
	local eggPart = part(m, {
		Name = "Egg",
		Size = Vector3.new(7, 9, 7) * scale,
		CFrame = cf * CFrame.new(0, 4.5 + 4.5 * scale, 0),
		Color = firstPet.color,
		Shape = Enum.PartType.Ball,
		Note = `{egg.name} model (spotted storm egg)`,
	})
	eggPart.Material = if egg.currency == "Robux" then TW.GlowMaterial else TW.Material
	local costText = if egg.currency == "Charge"
		then `<font color="#FFD633">⚡ {Format.short(egg.cost)}</font>`
		elseif egg.currency == "Robux" then `<font color="#00B06F">Robux</font>`
		else "Free"
	local extra = if egg.storm then "\n<font size=\"18\">Storm only</font>" elseif egg.event then "\n<font size=\"18\">Event</font>" else ""
	billboard(eggPart, `{egg.name}\n{costText}{extra}`, Theme.Colors.Text, UDim2.fromOffset(220, 110), Vector3.new(0, 9 * scale, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = egg.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Hatch.StandRadius - 4
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = eggPart
	m:SetAttribute("EggId", eggId)
	CollectionService:AddTag(m, "EggStand")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end

local function gate(parent: Instance, zoneDef: any, cf: CFrame, accent: Color3)
	local scale = Theme.zoneScale(zoneDef.index)
	local h = TW.GateHeight * scale
	local w = TW.GateWidth
	local m = model(parent, `Gate_{zoneDef.id}`)
	for _, side in { -1, 1 } do
		part(m, {
			Name = "Pillar",
			Size = Vector3.new(8, h, 8),
			CFrame = cf * CFrame.new(side * (w / 2 + 4), h / 2, 0),
			Color = Theme.Colors.PanelDark,
			Note = "Gate pillar (storm tower)",
		})
		part(m, {
			Name = "PillarGlow",
			Size = Vector3.new(8.4, 3, 8.4),
			CFrame = cf * CFrame.new(side * (w / 2 + 4), h - 4, 0),
			Color = accent,
			Material = TW.GlowMaterial,
			CanCollide = false,
			Note = "Gate pillar light band",
		})
	end
	part(m, {
		Name = "Lintel",
		Size = Vector3.new(w + 16, 8, 8),
		CFrame = cf * CFrame.new(0, h + 4, 0),
		Color = Theme.Colors.PanelDark,
		Note = "Gate lintel",
	})
	local barrier = part(m, {
		Name = "Barrier",
		Size = Vector3.new(w, h, 2),
		CFrame = cf * CFrame.new(0, h / 2, 0),
		Color = accent,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		Note = "Locked gate energy wall (client hides it once unlocked)",
	})
	local text = if zoneDef.vipOnly
		then `{zoneDef.name}\nVIP ONLY`
		else `{zoneDef.name}\n⚡ {Format.short(zoneDef.gateCost)}`
	label(barrier, Enum.NormalId.Front, text, Theme.Colors.Text)
	label(barrier, Enum.NormalId.Back, text, Theme.Colors.Text)
	m:SetAttribute("ZoneId", zoneDef.id)
	CollectionService:AddTag(m, "ZoneGate")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end

local function buildZone(zoneDef: any)
	local layout = WorldLayout.Zones[zoneDef.id]
	local folder = model(world, zoneDef.id)
	local rng = Random.new(zoneDef.index * 7919 + 17)
	local half = layout.size / 2
	islandBody(folder, layout.center, layout.size, zoneDef.ground, zoneDef.name)

	-- Edge props and floating clouds
	for _ = 1, 16 do
		local edge = rng:NextInteger(1, 4)
		local along = rng:NextNumber(-half + 10, half - 10)
		local inset = rng:NextNumber(4, 10)
		local offset = if edge == 1
			then Vector3.new(half - inset, 0, along)
			elseif edge == 2 then Vector3.new(-half + inset, 0, along)
			elseif edge == 3 then Vector3.new(along, 0, half - inset)
			else Vector3.new(along, 0, -half + inset)
		-- keep the west entrance clear
		if not (edge == 2 and math.abs(along) < 40) then
			prop(folder, math.max(1, zoneDef.index), layout.center + offset, zoneDef.accent, zoneDef.ground, rng)
		end
	end
	for _ = 1, 6 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = half + rng:NextNumber(30, 70)
		cloud(folder, layout.center + Vector3.new(math.cos(angle) * dist, rng:NextNumber(-30, 30), math.sin(angle) * dist), rng:NextNumber(1, 2.2), rng)
	end

	-- Zone name sign near the entrance
	local signCf = layout.spawn * CFrame.new(18, 10, 0)
	local sign = part(folder, {
		Name = "Sign",
		Size = Vector3.new(24, 8, 1),
		CFrame = signCf,
		Color = Theme.Colors.Panel,
		Note = "Zone name sign",
	})
	label(sign, Enum.NormalId.Front, zoneDef.name, zoneDef.accent)
	label(sign, Enum.NormalId.Back, zoneDef.name, zoneDef.accent)

	-- Bridge + gate from the previous zone (or from Drizzle Meadows for side zones)
	if layout.gate then
		local gcf = layout.gate
		local gap = Config.World.ZoneSpacing - Config.World.ZoneSize
		local from = (gcf * CFrame.new(0, 0, gap / 2 + 2)).Position
		local to = (gcf * CFrame.new(0, 0, -gap / 2 - 2)).Position
		bridge(folder, from, to, Config.World.ZoneSize * 0.25, Theme.darken(zoneDef.ground, 0.15), zoneDef.accent)
		gate(folder, zoneDef, gcf, zoneDef.accent)
	end

	if zoneDef.egg and layout.eggStand then
		eggStand(folder, zoneDef.egg, layout.eggStand, Theme.zoneScale(math.max(1, zoneDef.index)))
	end
	for eggId, pos in layout.specials do
		eggStand(folder, eggId, pos, 1.2)
	end

	-- Spirits are client-rendered; this marks the zone bounds for tools/artists
	local bounds = Instance.new("Part")
	bounds.Name = "SpawnArea"
	bounds.Anchored = true
	bounds.CanCollide = false
	bounds.CanQuery = false
	bounds.CanTouch = false
	bounds.Transparency = 1
	bounds.Size = Vector3.new(layout.size - 24, 1, layout.size - 24)
	bounds.CFrame = CFrame.new(layout.center + Vector3.new(0, 0.5, 0))
	bounds.Parent = folder
end

local function buildHub()
	local hub = model(world, "Hub")
	local center = WorldLayout.Hub
	part(hub, {
		Name = "Platform",
		Size = Vector3.new(8, 110, 110),
		CFrame = CFrame.new(center - Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Theme.Colors.PanelLight,
		Shape = Enum.PartType.Cylinder,
		Note = "Hub plaza disc",
	})
	part(hub, {
		Name = "Ring",
		Size = Vector3.new(1, 112, 112),
		CFrame = CFrame.new(center - Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Theme.Colors.Charge,
		Material = TW.GlowMaterial,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
		Note = "Hub glowing ring",
	})
	-- Sky bridge to Drizzle Meadows
	local meadows = WorldLayout.Zones.DrizzleMeadows
	bridge(
		hub,
		center + Vector3.new(0, 0, 54),
		meadows.center + Vector3.new(0, 0, -meadows.size / 2 - 1),
		22,
		Theme.Colors.PanelLight,
		Theme.Colors.Charge
	)
	-- Leaderboards
	for i, board in Config.Leaderboards.Boards do
		local angle = math.rad(-40 + (i - 1) * 40)
		local pos = center + Vector3.new(math.sin(angle) * 40, 14, -math.cos(angle) * 40)
		local b = part(hub, {
			Name = `Leaderboard_{board.id}`,
			Size = Vector3.new(20, 26, 1.5),
			CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)),
			Color = Theme.Colors.PanelDark,
			Note = "Leaderboard frame",
		})
		b:SetAttribute("BoardId", board.id)
		CollectionService:AddTag(b, "LeaderboardBoard")
	end
	-- Group reward pad
	local pad = part(hub, {
		Name = "GroupPad",
		Size = Vector3.new(1, 12, 12),
		CFrame = CFrame.new(center + Vector3.new(-30, 0.5, 20)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Theme.Colors.Good,
		Material = TW.GlowMaterial,
		Shape = Enum.PartType.Cylinder,
		Note = "Group reward pad",
	})
	billboard(pad, "Join the group!\nFree Stormling", Theme.Colors.Text, UDim2.fromOffset(200, 80), Vector3.new(0, 6, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Claim"
	prompt.ObjectText = "Group Reward"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	CollectionService:AddTag(pad, "GroupPad")
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end

-- Static plot geometry (platform + converter dock). IslandService adds the owner's build.
local function buildPlots()
	local plots = model(world, "Plots")
	local half = WorldLayout.plotHalfSize()
	for _, p in WorldLayout.Plots do
		local m = model(plots, `Plot{p.index}`)
		part(m, {
			Name = "Base",
			Size = Vector3.new(half * 2, TW.IslandThickness * 0.6, half * 2),
			CFrame = p.cframe * CFrame.new(0, -TW.IslandThickness * 0.3, 0),
			Color = Theme.Colors.PanelLight,
			Note = "Home island base (under the build grid)",
		})
		local body = model(m, "Body")
		islandBody(body, p.center - Vector3.new(0, TW.IslandThickness * 0.6, 0), half * 1.6, Theme.darken(Theme.Colors.PanelLight, 0.2), "Home island")
		-- Converter dock
		local dockCf = CFrame.new(p.converter) * p.cframe.Rotation
		part(m, {
			Name = "Dock",
			Size = Vector3.new(22, 4, 20),
			CFrame = dockCf * CFrame.new(0, -2, 2),
			Color = Theme.Colors.PanelDark,
			Note = "Converter dock",
		})
		local converter = model(m, "Converter")
		if not override("Converter", dockCf, converter) then
			part(converter, {
				Name = "Pad",
				Size = Vector3.new(1, Config.Security.SellRadius * 2 - 2, Config.Security.SellRadius * 2 - 2),
				CFrame = dockCf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Theme.Colors.Charge,
				Material = TW.GlowMaterial,
				Shape = Enum.PartType.Cylinder,
				CanCollide = false,
				Note = "Storm Converter sell pad (stand here to sell)",
			})
			part(converter, {
				Name = "Coil",
				Size = Vector3.new(4, 16, 4),
				CFrame = dockCf * CFrame.new(-9, 8, 6),
				Color = Theme.Colors.Static,
				Material = TW.GlowMaterial,
				Note = "Converter tesla coil",
			})
			part(converter, {
				Name = "Coil",
				Size = Vector3.new(4, 16, 4),
				CFrame = dockCf * CFrame.new(9, 8, 6),
				Color = Theme.Colors.Static,
				Material = TW.GlowMaterial,
				Note = "Converter tesla coil",
			})
		end
		local sign = part(m, {
			Name = "OwnerSign",
			Size = Vector3.new(26, 7, 1),
			CFrame = dockCf * CFrame.new(0, 16, 8),
			Color = Theme.Colors.Panel,
			CanCollide = false,
			Note = "Owner name sign",
		})
		label(sign, Enum.NormalId.Front, "Empty Island", Theme.Colors.Text)
		label(sign, Enum.NormalId.Back, "Empty Island", Theme.Colors.Text)
		billboard(converter:FindFirstChild("Pad") or sign, "SELL", Theme.Colors.Charge, UDim2.fromOffset(140, 50), Vector3.new(0, 5, 0))
		-- Bridge to the hub
		bridge(plots, p.converter + (p.cframe.LookVector * 8), WorldLayout.Hub + (p.center - WorldLayout.Hub).Unit * 56, 12, TW.CloudColor, Theme.Colors.Static)
		m:SetAttribute("PlotIndex", p.index)
		CollectionService:AddTag(m, "Plot")
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
end

local function buildSpawn()
	local meadows = WorldLayout.Zones.DrizzleMeadows
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "StartSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = meadows.spawn - Vector3.new(0, 3.5, 0)
	spawn.Color = Theme.Colors.Charge
	spawn.Material = TW.GlowMaterial
	spawn.Transparency = 0.3
	spawn:SetAttribute("ArtistNote", "Start spawn pad")
	CollectionService:AddTag(spawn, TW.PlaceholderTag)
	spawn.Parent = world
end

function WorldBuilder.build()
	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace
	for _, z in Config.Zones do
		buildZone(z)
	end
	buildHub()
	buildPlots()
	buildSpawn()
end

return WorldBuilder
