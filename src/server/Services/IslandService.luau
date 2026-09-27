--!strict
-- Home sky islands: plot assignment, expansion, decoration shop, grid placement and rendering.
-- Decorations with a `boost` feed StatsService (Charge / Luck / Capacity / Offline hours).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.WorldLayout)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local IslandService = {}

local owners: { [number]: Player } = {}

local function plotModel(index: number): Model?
	local world = Workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	return plots and plots:FindFirstChild(`Plot{index}`) :: Model?
end

local function setSign(index: number, text: string)
	local m = plotModel(index)
	local sign = m and m:FindFirstChild("OwnerSign")
	if sign then
		for _, gui in sign:GetChildren() do
			local tl = gui:FindFirstChild("Text")
			if tl and tl:IsA("TextLabel") then
				tl.Text = text
			end
		end
	end
end

local SHAPES: { [string]: Enum.PartType } = {
	Ball = Enum.PartType.Ball,
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Block,
}

local function decorationPart(parent: Instance, def: Types.DecorationDef, cf: CFrame, w: number, d: number): BasePart
	local cell = Config.Island.CellSize
	local size = Vector3.new(w * cell - 1, def.height, d * cell - 1)
	local p: BasePart
	if def.shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = SHAPES[def.shape]
		p = part
	end
	if def.shape == "Cylinder" then
		-- cylinders extrude along X; stand them up
		p.Size = Vector3.new(def.height, math.min(size.X, size.Z), math.min(size.X, size.Z))
		p.CFrame = cf * CFrame.new(0, def.height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	elseif def.shape == "Ball" then
		local s = math.min(size.X, size.Z, def.height)
		p.Size = Vector3.new(s, s, s)
		p.CFrame = cf * CFrame.new(0, s / 2 + (def.height - s), 0)
		-- trunk under ball props
		local trunk = Instance.new("Part")
		trunk.Anchored = true
		trunk.Size = Vector3.new(2, def.height - s + 1, 2)
		trunk.CFrame = cf * CFrame.new(0, (def.height - s) / 2, 0)
		trunk.Color = Theme.darken(def.color, 0.55)
		trunk.Material = Theme.World.Material
		trunk:SetAttribute("ArtistNote", `{def.name} (trunk)`)
		CollectionService:AddTag(trunk, Theme.World.PlaceholderTag)
		trunk.Parent = parent
	else
		p.Size = size
		p.CFrame = cf * CFrame.new(0, def.height / 2, 0)
	end
	p.Anchored = true
	p.Color = def.color
	p.Material = if def.boost then Theme.World.GlowMaterial else Theme.World.Material
	p:SetAttribute("ArtistNote", `Decoration: {def.name}`)
	CollectionService:AddTag(p, Theme.World.PlaceholderTag)
	p.Parent = parent
	return p
end

function IslandService.render(player: Player)
	local session = DataService.session(player)
	local data = DataService.get(player)
	if not session or not session.Plot or not data then
		return
	end
	local index = session.Plot
	local m = plotModel(index)
	if not m then
		return
	end
	local old = m:FindFirstChild("Build")
	if old then
		old:Destroy()
	end
	local build = Instance.new("Model")
	build.Name = "Build"
	local layout = WorldLayout.Plots[index]
	local cell = Config.Island.CellSize

	-- Unlocked grid area
	local cells = Config.Island.Sizes[data.Island.Size].cells
	local area = Instance.new("Part")
	area.Name = "Grass"
	area.Anchored = true
	area.Size = Vector3.new(cells * cell, 1, cells * cell)
	area.CFrame = layout.cframe * CFrame.new(0, 0.5, 0)
	area.Color = Color3.fromRGB(120, 214, 110)
	area.Material = Theme.World.GroundMaterial
	area:SetAttribute("ArtistNote", "Home island buildable ground")
	CollectionService:AddTag(area, Theme.World.PlaceholderTag)
	area.Parent = build

	for i, placed in data.Island.Placed do
		local def = Defs.Decoration[placed.id]
		if def then
			local w, d = WorldLayout.footprint(def.size, placed.r)
			local a = WorldLayout.cellLocal(placed.x, placed.z)
			local b = WorldLayout.cellLocal(placed.x + w - 1, placed.z + d - 1)
			local localCenter = (a + b) / 2
			local cf = layout.cframe * CFrame.new(localCenter + Vector3.new(0, 1, 0)) * CFrame.Angles(0, placed.r * math.pi / 2, 0)
			local p = decorationPart(build, def, cf, def.size.X, def.size.Y)
			p.Name = `Deco{i}`
		end
	end
	build.Parent = m
end

local function assign(player: Player)
	local session = DataService.session(player)
	if not session then
		return
	end
	for i = 1, #WorldLayout.Plots do
		if not owners[i] then
			owners[i] = player
			session.Plot = i
			DataService.pushSession(player, "Plot", i)
			setSign(i, `{player.DisplayName}'s Island`)
			IslandService.render(player)
			return
		end
	end
	warn("[IslandService] No free plot for", player.Name)
end

local function release(player: Player)
	for i, owner in owners do
		if owner == player then
			owners[i] = nil
			setSign(i, "Empty Island")
			local m = plotModel(i)
			local build = m and m:FindFirstChild("Build")
			if build then
				build:Destroy()
			end
		end
	end
end

local function placedCount(data: Types.ProfileData, decoId: string): number
	local n = 0
	for _, p in data.Island.Placed do
		if p.id == decoId then
			n += 1
		end
	end
	return n
end

function IslandService.buySize(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Not ready"
	end
	local nextLevel = Config.Island.Sizes[data.Island.Size + 1]
	if not nextLevel then
		return false, "Island is max size"
	end
	if not CurrencyService.spend(player, nextLevel.cost, "Island", "Expand") then
		return false, "Not enough Charge"
	end
	data.Island.Size += 1
	DataService.markDirty(player, "Island")
	IslandService.render(player)
	return true
end

function IslandService.buyDecoration(player: Player, decoId: string): (boolean, string?)
	local data = DataService.get(player)
	local def = Defs.Decoration[decoId]
	if not data or not def then
		return false, "Unknown decoration"
	end
	if def.unlockZone then
		local zone = Defs.MainZones[def.unlockZone]
		if zone and not data.UnlockedZones[zone.id] then
			return false, `Unlock {zone.name} first`
		end
	end
	if not CurrencyService.spend(player, def.cost, "Decoration", decoId) then
		return false, "Not enough Charge"
	end
	data.Island.Owned[decoId] = (data.Island.Owned[decoId] or 0) + 1
	DataService.markDirty(player, "Island")
	return true
end

function IslandService.grantDecoration(player: Player, decoId: string)
	local data = DataService.get(player)
	if data and Defs.Decoration[decoId] then
		data.Island.Owned[decoId] = (data.Island.Owned[decoId] or 0) + 1
		DataService.markDirty(player, "Island")
	end
end

function IslandService.place(player: Player, decoId: string, x: number, z: number, r: number): (boolean, string?)
	local data = DataService.get(player)
	if not data or not Defs.Decoration[decoId] then
		return false, "Unknown decoration"
	end
	if #data.Island.Placed >= Config.Island.MaxPlaced then
		return false, "Island is full of decorations"
	end
	if placedCount(data, decoId) >= (data.Island.Owned[decoId] or 0) then
		return false, "Buy this decoration first"
	end
	if not WorldLayout.canPlace(data.Island.Size, data.Island.Placed, decoId, x, z, r) then
		return false, "Can't place there"
	end
	table.insert(data.Island.Placed, { id = decoId, x = x, z = z, r = r })
	data.Stats.DecorationsPlaced += 1
	DataService.markDirty(player, "Island")
	DataService.markDirty(player, "Stats")
	IslandService.render(player)
	StatsService.refresh(player)
	GameEvents.DecorationPlaced:Fire(player, decoId)
	return true
end

function IslandService.remove(player: Player, index: number): (boolean, string?)
	local data = DataService.get(player)
	if not data or not data.Island.Placed[index] then
		return false, "Nothing there"
	end
	table.remove(data.Island.Placed, index)
	DataService.markDirty(player, "Island")
	IslandService.render(player)
	StatsService.refresh(player)
	return true
end

function IslandService.init() end

function IslandService.start()
	DataService.Loaded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	Net.Server.handle("BuyIslandSize", IslandService.buySize)
	Net.Server.handle("BuyDecoration", IslandService.buyDecoration)
	Net.Server.handle("PlaceDecoration", IslandService.place)
	Net.Server.handle("RemoveDecoration", IslandService.remove)
end

return IslandService
