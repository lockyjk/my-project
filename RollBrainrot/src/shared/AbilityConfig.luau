--!strict
-- Brainrot abilities and passives. Each ability names a server `handler` (see
-- ServerScriptService.Server.Combat.Abilities) and a client `vfx` (see
-- StarterPlayerScripts.Client.Controllers.CombatFx). New abilities that reuse an existing
-- handler need only a row here; a brand-new mechanic needs one handler function.
--
-- damageMult is a multiple of the caster's current attack stat.
local Types = require(script.Parent.Types)

local abilities: { [string]: Types.AbilityDef } = {
	BananaBonk = {
		id = "BananaBonk",
		name = "Banana Bonk",
		description = "Quickly bonks an enemy 3 times.",
		handler = "MultiHit",
		cooldown = 5,
		vfx = "Bonk",
		color = Color3.fromRGB(255, 230, 80),
		params = { hits = 3, damageMult = 0.9, interval = 0.15 },
	},
	CheeseBurst = {
		id = "CheeseBurst",
		name = "Cheese Burst",
		description = "Throws a pizza that explodes, damaging nearby enemies.",
		handler = "AoEProjectile",
		cooldown = 6,
		vfx = "PizzaBomb",
		color = Color3.fromRGB(255, 190, 60),
		params = { damageMult = 2.2, radius = 14, flightTime = 0.55 },
	},
	ThornShield = {
		id = "ThornShield",
		name = "Thorn Shield",
		description = "Reduces incoming damage by 50% and reflects 30% back for 5s.",
		handler = "SelfShield",
		cooldown = 10,
		vfx = "ThornShield",
		color = Color3.fromRGB(120, 220, 90),
		params = { duration = 5, reduction = 0.5, reflect = 0.3, taunt = true, tauntRadius = 26 },
	},
	StickySplash = {
		id = "StickySplash",
		name = "Sticky Splash",
		description = "Slows enemies in an area and slightly heals nearby Brainrots.",
		handler = "AreaSlowHeal",
		cooldown = 8,
		vfx = "Splash",
		color = Color3.fromRGB(120, 255, 180),
		params = { radius = 20, slow = 0.45, slowDuration = 4, healPct = 0.12, healRadius = 26, damageMult = 0.8 },
	},
	GatorMissile = {
		id = "GatorMissile",
		name = "Gator Missile",
		description = "Fires a massive explosive missile at the strongest nearby enemy.",
		handler = "AoEProjectile",
		cooldown = 7,
		vfx = "Missile",
		color = Color3.fromRGB(255, 120, 40),
		params = { damageMult = 4.5, radius = 16, flightTime = 0.8, target = "strongest", shake = 0.4 },
	},
	SharkRush = {
		id = "SharkRush",
		name = "Shark Rush",
		description = "Charges through multiple enemies, dealing huge damage.",
		handler = "Dash",
		cooldown = 6,
		vfx = "Rush",
		color = Color3.fromRGB(90, 200, 255),
		params = { distance = 42, width = 9, damageMult = 3.5 },
	},
	VolcanoStomp = {
		id = "VolcanoStomp",
		name = "Volcano Stomp",
		description = "Slams the ground, creating a massive lava shockwave that burns.",
		handler = "GroundSlam",
		cooldown = 8,
		vfx = "LavaSlam",
		color = Color3.fromRGB(255, 90, 20),
		params = { radius = 30, damageMult = 3, burnPct = 0.25, burnDuration = 4, shake = 0.8 },
	},
	CosmicCollapse = {
		id = "CosmicCollapse",
		name = "Cosmic Collapse",
		description = "Creates a mini black hole that pulls monsters together, then explodes.",
		handler = "BlackHole",
		cooldown = 10,
		vfx = "BlackHole",
		color = Color3.fromRGB(170, 90, 255),
		params = { radius = 40, pullTime = 1.6, damageMult = 6, shake = 1.2 },
	},

	-- Generic abilities ready for future Brainrots (no Brainrot uses them yet) --------------
	Fireball = {
		id = "Fireball",
		name = "Fireball",
		description = "Launches a fireball that burns the target area.",
		handler = "AoEProjectile",
		cooldown = 5,
		vfx = "Fireball",
		color = Color3.fromRGB(255, 110, 30),
		params = { damageMult = 2.5, radius = 10, flightTime = 0.5, burnPct = 0.2, burnDuration = 3 },
	},
	Freeze = {
		id = "Freeze",
		name = "Freeze",
		description = "Slows all nearby enemies.",
		handler = "AreaSlowHeal",
		cooldown = 8,
		vfx = "Frost",
		color = Color3.fromRGB(150, 220, 255),
		params = { radius = 24, slow = 0.6, slowDuration = 4, healPct = 0, healRadius = 0, damageMult = 1 },
	},
	Taunt = {
		id = "Taunt",
		name = "Taunt",
		description = "Forces nearby enemies to attack this Brainrot.",
		handler = "SelfShield",
		cooldown = 10,
		vfx = "ThornShield",
		color = Color3.fromRGB(255, 80, 80),
		params = { duration = 4, reduction = 0.3, reflect = 0, taunt = true, tauntRadius = 30 },
	},
	ChainLightning = {
		id = "ChainLightning",
		name = "Chain Lightning",
		description = "Lightning jumps between up to 5 enemies.",
		handler = "Chain",
		cooldown = 6,
		vfx = "Lightning",
		color = Color3.fromRGB(140, 200, 255),
		params = { bounces = 5, jumpRange = 22, damageMult = 2, falloff = 0.85 },
	},
	Heal = {
		id = "Heal",
		name = "Heal",
		description = "Restores HP to nearby Brainrots.",
		handler = "AreaSlowHeal",
		cooldown = 7,
		vfx = "Heal",
		color = Color3.fromRGB(120, 255, 140),
		params = { radius = 0, slow = 0, slowDuration = 0, healPct = 0.3, healRadius = 30, damageMult = 0 },
	},
}

local passives: { [string]: Types.PassiveDef } = {
	BurnImmune = {
		id = "BurnImmune",
		name = "Magma Hide",
		description = "Immune to burn.",
		params = { immune = { "Burn" } },
	},
	CosmicAura = {
		id = "CosmicAura",
		name = "Cosmic Aura",
		description = "Nearby Brainrots gain +20% attack speed.",
		params = { radius = 36, attackSpeed = 0.2 },
	},
}

return {
	Abilities = abilities,
	Passives = passives,
}
