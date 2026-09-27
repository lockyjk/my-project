--!strict
-- Save-data versioning. Each entry migrates data FROM version (n-1) TO version n.
-- Rules:
--   * Never edit a migration that has shipped; add a new one and bump Config.DataVersion.
--   * Migrations must be pure (no services) so they can be unit tested.
--   * After migrating, reconcile() fills any keys added to DataTemplate.
-- The two migrations below are the schema changes made while prototyping; keep them as
-- templates for future changes. Both are covered by tests/Migrations.spec.luau.

local Migrations = {}

type AnyTable = { [any]: any }

Migrations.steps = {
	-- v1 -> v2: Pets changed from an array to a map keyed by uid (O(1) lookups for trades/equips)
	[2] = function(data: AnyTable, _now: number)
		local pets = data.Pets
		if type(pets) == "table" and #pets > 0 then
			local map = {}
			for _, pet in pets do
				if type(pet) == "table" and type(pet.uid) == "string" then
					map[pet.uid] = pet
				end
			end
			data.Pets = map
		end
	end,
	-- v2 -> v3: Boosts changed from "seconds remaining" to absolute expiry unix times
	[3] = function(data: AnyTable, now: number)
		local boosts = data.Boosts
		if type(boosts) == "table" then
			for stat, value in boosts do
				if type(value) == "number" and value < 1e9 then
					boosts[stat] = now + value
				end
			end
		end
	end,
} :: { [number]: (AnyTable, number) -> () }

-- Returns (data, fromVersion). Throws if the save is from a newer game version
-- (the caller should refuse to load rather than overwrite newer data).
function Migrations.migrate(data: AnyTable, targetVersion: number, now: number): (AnyTable, number)
	local from = tonumber(data.DataVersion) or 1
	if from > targetVersion then
		error(`Save data version {from} is newer than this server ({targetVersion})`)
	end
	for v = from + 1, targetVersion do
		local step = Migrations.steps[v]
		if step then
			step(data, now)
		end
		data.DataVersion = v
	end
	return data, from
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- Fill keys missing from `data` using `template`, recursing into tables whose template
-- value is a non-empty dictionary. Never overwrites existing values or removes keys.
function Migrations.reconcile(data: AnyTable, template: AnyTable): AnyTable
	for k, v in template do
		local existing = data[k]
		if existing == nil then
			data[k] = deepCopy(v)
		elseif type(existing) == "table" and type(v) == "table" and next(v) ~= nil and #v == 0 then
			Migrations.reconcile(existing, v)
		end
	end
	return data
end

Migrations.deepCopy = deepCopy

return Migrations
