--!strict
-- Lookup tables built once from Config. Use these instead of scanning Config arrays.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Defs = {}

local function index<T>(list: { T }, key: string): { [any]: T }
	local map = {}
	for _, item in list do
		local k = (item :: any)[key]
		assert(map[k] == nil, `Duplicate config id: {tostring(k)}`)
		map[k] = item
	end
	return map
end

Defs.Rarity = index(Config.Rarities, "id") :: { [string]: Types.Rarity }
Defs.Spirit = index(Config.Spirits, "id") :: { [string]: Types.SpiritDef }
Defs.Zone = index(Config.Zones, "id") :: { [string]: Types.ZoneDef }
Defs.Pet = index(Config.Pets, "id") :: { [string]: Types.PetDef }
Defs.Egg = index(Config.Eggs, "id") :: { [string]: Types.EggDef }
Defs.Upgrade = index(Config.Upgrades, "id") :: { [string]: Types.UpgradeDef }
Defs.AscNode = index(Config.AscTree, "id") :: { [string]: Types.AscNode }
Defs.Storm = index(Config.Storms, "id") :: { [string]: Types.StormDef }
Defs.LiveEvent = index(Config.LiveEvents, "id") :: { [string]: Types.LiveEventDef }
Defs.Decoration = index(Config.Decorations, "id") :: { [string]: Types.DecorationDef }
Defs.Potion = index(Config.Potions, "id") :: { [string]: Types.PotionDef }
Defs.Pass = index(Config.GamePasses, "key") :: { [string]: Types.PassDef }
Defs.Product = index(Config.Products, "key") :: { [string]: Types.ProductDef }
Defs.Quest = index(Config.Quests.Templates, "id") :: { [string]: Types.QuestTemplate }
Defs.Achievement = index(Config.Achievements, "id") :: { [string]: Types.AchievementDef }

-- Main progression zones ordered by index (excludes index-0 side zones)
Defs.MainZones = {} :: { Types.ZoneDef }
for _, z in Config.Zones do
	if z.index > 0 then
		table.insert(Defs.MainZones, z)
	end
end
table.sort(Defs.MainZones, function(a, b)
	return a.index < b.index
end)

-- Product lookup by numeric id (for ProcessReceipt). Unconfigured (0) ids are skipped.
Defs.ProductById = {} :: { [number]: Types.ProductDef }
for _, p in Config.Products do
	if p.id ~= 0 then
		Defs.ProductById[p.id] = p
	end
end

-- Egg -> list of pet ids (index / collection log)
Defs.EggPets = {} :: { [string]: { string } }
Defs.PetEgg = {} :: { [string]: string }
for _, egg in Config.Eggs do
	local ids = {}
	for _, entry in egg.pets do
		assert(Defs.Pet[entry.pet], `Egg {egg.id} references unknown pet {entry.pet}`)
		table.insert(ids, entry.pet)
		if Defs.PetEgg[entry.pet] == nil then
			Defs.PetEgg[entry.pet] = egg.id
		end
	end
	Defs.EggPets[egg.id] = ids
end

-- Validate cross references early so config typos fail loudly at startup
for _, z in Config.Zones do
	for _, s in z.spawns do
		assert(Defs.Spirit[s.spirit], `Zone {z.id} references unknown spirit {s.spirit}`)
	end
	if z.egg then
		assert(Defs.Egg[z.egg], `Zone {z.id} references unknown egg {z.egg}`)
	end
end
for _, st in Config.Storms do
	for _, s in st.spirits do
		assert(Defs.Spirit[s.spirit], `Storm {st.id} references unknown spirit {s.spirit}`)
	end
end
for _, ev in Config.LiveEvents do
	if ev.spirits then
		for _, s in ev.spirits do
			assert(Defs.Spirit[s.spirit], `Event {ev.id} references unknown spirit {s.spirit}`)
		end
	end
	if ev.egg then
		assert(Defs.Egg[ev.egg], `Event {ev.id} references unknown egg {ev.egg}`)
	end
end
for _, sp in Config.Spirits do
	if sp.petDrop then
		assert(Defs.Pet[sp.petDrop.pet], `Spirit {sp.id} drops unknown pet {sp.petDrop.pet}`)
	end
end

function Defs.rarityOrder(rarityId: string): number
	local r = Defs.Rarity[rarityId]
	return if r then r.order else 0
end

function Defs.zoneIndex(zoneId: string): number
	local z = Defs.Zone[zoneId]
	return if z then z.index else 0
end

return Defs
