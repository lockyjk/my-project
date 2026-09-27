--!strict
-- Pure world layout: where zones, gates, egg stands, the hub and home plots are.
-- The server builds placeholder geometry from this; server validation (distances) and the
-- client (teleport targets, build grid) read the same numbers.

local Config = require(script.Parent.Config)
local Defs = require(script.Parent.Defs)

local WorldLayout = {}

local W = Config.World

export type ZoneLayout = {
	id: string,
	center: Vector3, -- top surface centre
	size: number,
	spawn: CFrame,
	gate: CFrame?, -- gate barrier centre, facing into the zone
	eggStand: Vector3?,
	specials: { [string]: Vector3 }, -- extra egg stands in this zone (storm altar etc.)
}

export type PlotLayout = {
	index: number,
	center: Vector3,
	cframe: CFrame, -- at centre, LookVector points toward the hub
	converter: Vector3,
	spawn: CFrame,
}

local zones: { [string]: ZoneLayout } = {}

local function mainZoneCenter(index: number): Vector3
	return W.ZoneStart + Vector3.new((index - 1) * W.ZoneSpacing, 0, 0)
end

for _, z in Config.Zones do
	local center: Vector3
	local gate: CFrame?
	local spawn: CFrame
	local half = W.ZoneSize / 2
	if z.index > 0 then
		center = mainZoneCenter(z.index)
		spawn = CFrame.new(center + Vector3.new(-half + 24, 4, 0)) * CFrame.Angles(0, -math.pi / 2, 0)
		if z.index > 1 then
			local gap = W.ZoneSpacing - W.ZoneSize
			gate = CFrame.lookAt(
				center + Vector3.new(-half - gap / 2, 0, 0),
				center + Vector3.new(-half - gap / 2 + 1, 0, 0)
			)
		end
	else
		-- Side zones sit south of Drizzle Meadows
		center = W.ZoneStart + Vector3.new(0, 0, W.ZoneSpacing)
		spawn = CFrame.new(center + Vector3.new(0, 4, -half + 24))
		local gap = W.ZoneSpacing - W.ZoneSize
		gate = CFrame.lookAt(center + Vector3.new(0, 0, -half - gap / 2), center + Vector3.new(0, 0, -half - gap / 2 + 1))
	end
	local layout: ZoneLayout = {
		id = z.id,
		center = center,
		size = W.ZoneSize,
		spawn = spawn,
		gate = gate,
		eggStand = if z.egg then center + Vector3.new(-half + 44, 0, -36) else nil,
		specials = {},
	}
	zones[z.id] = layout
end

-- Egg stands that are not a zone's main egg live on Drizzle Meadows' "egg plaza"
do
	local meadows = zones.DrizzleMeadows
	local plazaX = -W.ZoneSize / 2 + 44
	local offsets = { Vector3.new(plazaX, 0, 36), Vector3.new(plazaX + 30, 0, 44), Vector3.new(plazaX + 60, 0, 36) }
	local i = 0
	for _, egg in Config.Eggs do
		local isZoneEgg = false
		for _, z in Config.Zones do
			if z.egg == egg.id then
				isZoneEgg = true
			end
		end
		if not isZoneEgg and not egg.hidden and egg.zone then
			i += 1
			local zl = zones[egg.zone]
			if zl then
				local offset = offsets[((i - 1) % #offsets) + 1] + Vector3.new(0, 0, math.floor((i - 1) / #offsets) * 30)
				zl.specials[egg.id] = if zl == meadows then meadows.center + offset else zl.center + offset
			end
		end
	end
end

WorldLayout.Zones = zones

-- Hub (leaderboards, group reward, bridges) north of Drizzle Meadows
WorldLayout.Hub = W.PlotCenter

function WorldLayout.plotHalfSize(): number
	local maxCells = Config.Island.Sizes[#Config.Island.Sizes].cells
	return maxCells * Config.Island.CellSize / 2 + 4
end

local plots: { PlotLayout } = {}
local PLOT_RADIUS = 330
for i = 1, W.PlotCount do
	-- spread plots over 300 degrees, leaving the arc toward the zones free for the sky bridge
	local theta = math.rad(30 + (i - 0.5) / W.PlotCount * 300)
	local center = W.PlotCenter + Vector3.new(math.sin(theta) * PLOT_RADIUS, 0, math.cos(theta) * PLOT_RADIUS)
	local cf = CFrame.lookAt(center, Vector3.new(W.PlotCenter.X, center.Y, W.PlotCenter.Z))
	local converter = (cf * CFrame.new(0, 0, -WorldLayout.plotHalfSize() - 6)).Position
	table.insert(plots, {
		index = i,
		center = center,
		cframe = cf,
		converter = converter,
		spawn = CFrame.lookAt(converter + Vector3.new(0, 4, 0), center + Vector3.new(0, 4, 0)),
	})
end

WorldLayout.Plots = plots

-- Which zone contains a world position (flat check), or nil
function WorldLayout.zoneAt(position: Vector3): string?
	for id, z in zones do
		local half = z.size / 2 + 6
		local d = position - z.center
		if math.abs(d.X) <= half and math.abs(d.Z) <= half and d.Y > -40 and d.Y < 200 then
			return id
		end
	end
	return nil
end

function WorldLayout.plotAt(position: Vector3): number?
	local half = WorldLayout.plotHalfSize() + 4
	for _, p in plots do
		local rel = p.cframe:PointToObjectSpace(position)
		if math.abs(rel.X) <= half and math.abs(rel.Z) <= half + 12 and rel.Y > -30 and rel.Y < 120 then
			return p.index
		end
	end
	return nil
end

-- Where a given egg can be hatched from (main stand or special stand)
function WorldLayout.eggPosition(eggId: string): Vector3?
	for _, z in Config.Zones do
		local zl = zones[z.id]
		if z.egg == eggId and zl.eggStand then
			return zl.eggStand
		end
		if zl.specials[eggId] then
			return zl.specials[eggId]
		end
	end
	return nil
end

-- Build grid helpers ---------------------------------------------------------
function WorldLayout.maxCells(): number
	return Config.Island.Sizes[#Config.Island.Sizes].cells
end

-- Placements use absolute coordinates on the max-size grid (0..maxCells-1) so expanding the
-- island never moves existing decorations. The unlocked square is centred on the plot.
function WorldLayout.unlockedBounds(sizeLevel: number): (number, number)
	local cells = Config.Island.Sizes[sizeLevel].cells
	local lo = math.floor((WorldLayout.maxCells() - cells) / 2)
	return lo, lo + cells -- [lo, hi)
end

-- Cell centre in plot-local space
function WorldLayout.cellLocal(x: number, z: number): Vector3
	local cell = Config.Island.CellSize
	local origin = -WorldLayout.maxCells() * cell / 2
	return Vector3.new(origin + (x + 0.5) * cell, 0, origin + (z + 0.5) * cell)
end

-- Footprint of a decoration after rotation (r = quarter turns)
function WorldLayout.footprint(size: Vector2, r: number): (number, number)
	if r % 2 == 1 then
		return size.Y, size.X
	end
	return size.X, size.Y
end

-- Validate a placement against grid bounds and occupied cells.
-- placed: list of {id, x, z, r}; ignoreIndex skips one entry (for moves)
function WorldLayout.canPlace(
	sizeLevel: number,
	placed: { { id: string, x: number, z: number, r: number } },
	decoId: string,
	x: number,
	z: number,
	r: number,
	ignoreIndex: number?
): boolean
	local def = Defs.Decoration[decoId]
	local level = Config.Island.Sizes[sizeLevel]
	if not def or not level then
		return false
	end
	local w, d = WorldLayout.footprint(def.size, r)
	local lo, hi = WorldLayout.unlockedBounds(sizeLevel)
	if x < lo or z < lo or x + w > hi or z + d > hi then
		return false
	end
	for i, p in placed do
		if i ~= ignoreIndex then
			local pd = Defs.Decoration[p.id]
			if pd then
				local pw, pdd = WorldLayout.footprint(pd.size, p.r)
				local overlapX = x < p.x + pw and p.x < x + w
				local overlapZ = z < p.z + pdd and p.z < z + d
				if overlapX and overlapZ then
					return false
				end
			end
		end
	end
	return true
end

return WorldLayout
