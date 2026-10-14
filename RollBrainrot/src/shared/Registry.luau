--!strict
-- Validated lookups over every config module. `Registry.validate()` runs on server start
-- and in tests; it checks every cross reference (ability ids, rarities, habitats, monsters in
-- waves, boss drops, …) so a typo in a config row fails loudly instead of silently.

local AbilityConfig = require(script.Parent.AbilityConfig)
local ArenaConfig = require(script.Parent.ArenaConfig)
local BrainrotConfig = require(script.Parent.BrainrotConfig)
local GameConfig = require(script.Parent.GameConfig)
local MonsterConfig = require(script.Parent.MonsterConfig)
local MutationConfig = require(script.Parent.MutationConfig)
local RarityConfig = require(script.Parent.RarityConfig)
local Types = require(script.Parent.Types)

local Registry = {}

Registry.Rarities = RarityConfig.List
Registry.Rarity = RarityConfig.ById
Registry.Mutations = MutationConfig.List
Registry.Mutation = MutationConfig.ById
Registry.Brainrots = BrainrotConfig.List
Registry.Brainrot = BrainrotConfig.ById
Registry.Ability = AbilityConfig.Abilities
Registry.Passive = AbilityConfig.Passives
Registry.Monster = MonsterConfig.Monsters
Registry.BossAttack = MonsterConfig.BossAttacks
Registry.Arenas = ArenaConfig.List
Registry.Arena = ArenaConfig.ById
Registry.Upgrade = GameConfig.Upgrades
Registry.Habitats = GameConfig.Habitats

local habitatById: { [string]: GameConfig.HabitatDef } = {}
local habitatIndex: { [string]: number } = {}
for i, h in GameConfig.Habitats do
	habitatById[h.id] = h
	habitatIndex[h.id] = i
end
Registry.Habitat = habitatById
Registry.HabitatIndex = habitatIndex

local decorationById: { [string]: GameConfig.DecorationDef } = {}
for _, d in GameConfig.Decorations do
	decorationById[d.id] = d
end
Registry.Decoration = decorationById

local eventById: { [string]: GameConfig.WorldEventDef } = {}
for _, e in GameConfig.Events.List do
	eventById[e.id] = e
end
Registry.Event = eventById

-- Brainrots grouped by rarity, in config order (roll pools only include rollable ones)
local byRarity: { [string]: { Types.BrainrotDef } } = {}
local rollPool: { [string]: { Types.BrainrotDef } } = {}
for _, r in RarityConfig.List do
	byRarity[r.id] = {}
	rollPool[r.id] = {}
end
for _, b in BrainrotConfig.List do
	local bucket = byRarity[b.rarity]
	if bucket then
		table.insert(bucket, b)
		if b.rollable then
			table.insert(rollPool[b.rarity], b)
		end
	end
end
Registry.ByRarity = byRarity
Registry.RollPool = rollPool

function Registry.rarityOf(brainrotId: string): Types.RarityDef
	local def = BrainrotConfig.ById[brainrotId]
	return RarityConfig.ById[def and def.rarity or "Common"]
end

-- "Golden Bananini Bongo" / "Bananini Bongo"
function Registry.displayName(brainrotId: string, mutationId: string?): string
	local def = BrainrotConfig.ById[brainrotId]
	local name = if def then def.name else brainrotId
	local mut = mutationId and MutationConfig.ById[mutationId]
	if mut and mut.prefix ~= "" then
		return mut.prefix .. " " .. name
	end
	return name
end

-------------------------------------------------------------------------------
-- Validation
-------------------------------------------------------------------------------
function Registry.validate(): { string }
	local errors: { string } = {}
	local function check(cond: any, message: string)
		if not cond then
			table.insert(errors, message)
		end
	end

	local seenOrder: { [number]: boolean } = {}
	for i, r in RarityConfig.List do
		check(r.order == i, `rarity {r.id} has order {r.order}, expected {i}`)
		check(not seenOrder[r.order], `duplicate rarity order {r.order}`)
		seenOrder[r.order] = true
		check(r.weight > 0, `rarity {r.id} weight must be > 0`)
	end
	check(MutationConfig.List[1].id == "Normal", "first mutation must be Normal")

	for _, b in BrainrotConfig.List do
		local where = `brainrot {b.id}`
		check(BrainrotConfig.ById[b.id] == b, `{where}: duplicate id`)
		check(RarityConfig.ById[b.rarity], `{where}: unknown rarity {b.rarity}`)
		check(AbilityConfig.Abilities[b.ability], `{where}: unknown ability {b.ability}`)
		check(b.passive == nil or AbilityConfig.Passives[b.passive], `{where}: unknown passive {b.passive}`)
		check(GameConfig.SpeedTiers[b.speed], `{where}: unknown speed tier {b.speed}`)
		check(GameConfig.RangeTiers[b.range], `{where}: unknown range tier {b.range}`)
		check(habitatById[b.habitat], `{where}: unknown habitat {b.habitat}`)
		check(b.hp > 0 and b.attack > 0 and b.cooldown > 0, `{where}: stats must be positive`)
	end
	for _, r in RarityConfig.List do
		-- Every rarity needs at least one rollable Brainrot or rolls of it would have nothing to give
		check(#rollPool[r.id] > 0, `rarity {r.id} has no rollable Brainrots`)
	end

	for id, m in MonsterConfig.Monsters do
		check(m.id == id, `monster key {id} ~= id {m.id}`)
		if m.attacks then
			for _, a in m.attacks do
				check(MonsterConfig.BossAttacks[a], `monster {id}: unknown boss attack {a}`)
			end
		end
		if m.drops then
			for _, d in m.drops do
				check(BrainrotConfig.ById[d.brainrot], `monster {id}: unknown drop {d.brainrot}`)
				check(
					d.mutation == nil or MutationConfig.ById[d.mutation],
					`monster {id}: unknown mutation {d.mutation}`
				)
			end
		end
	end
	for id, a in MonsterConfig.BossAttacks do
		if a.params.monster then
			check(MonsterConfig.Monsters[a.params.monster], `boss attack {id}: unknown monster {a.params.monster}`)
		end
	end

	for _, arena in ArenaConfig.List do
		local where = `arena {arena.id}`
		check(arena.requiresArena == nil or ArenaConfig.ById[arena.requiresArena], `{where}: unknown requiresArena`)
		check(#arena.waves > 0, `{where}: no waves`)
		for w, wave in arena.waves do
			for _, s in wave.spawns do
				check(MonsterConfig.Monsters[s.monster], `{where} wave {w}: unknown monster {s.monster}`)
				check(s.count > 0, `{where} wave {w}: count must be > 0`)
			end
		end
	end

	for _, h in GameConfig.Habitats do
		check(h.requiresArena == nil or ArenaConfig.ById[h.requiresArena], `habitat {h.id}: unknown arena`)
	end
	check(#GameConfig.World.HabitatOffsets >= #GameConfig.Habitats, "not enough HabitatOffsets for every habitat")
	check(BrainrotConfig.ById[GameConfig.Start.StarterBrainrot], "unknown StarterBrainrot")
	check(RarityConfig.ById[GameConfig.Roll.Pity.minRarity], "unknown pity rarity")
	check(MonsterConfig.Monsters[GameConfig.Events.InvasionBoss], "unknown invasion boss")
	for i, reward in GameConfig.Daily.Rewards do
		if reward.kind == "brainrot" then
			check(RarityConfig.ById[reward.rarity], `daily day {i}: unknown rarity`)
		elseif reward.kind == "boost" then
			check(GameConfig.Boosts[reward.boost], `daily day {i}: unknown boost`)
		end
	end
	return errors
end

function Registry.assertValid()
	local errors = Registry.validate()
	if #errors > 0 then
		error("[Registry] invalid config:\n  " .. table.concat(errors, "\n  "), 0)
	end
end

return Registry
