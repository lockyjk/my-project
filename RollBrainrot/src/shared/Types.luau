--!strict
-- Shared type definitions for configs, save data and network payloads.

export type RarityDef = {
	id: string,
	order: number, -- 1 = most common
	weight: number, -- base roll weight (relative, normalised at roll time)
	color: Color3,
	glow: Color3,
	luckAffected: boolean, -- luck multiplies this rarity's weight
	fxTier: number, -- 1 simple .. 5 extremely dramatic (drives the roll reveal)
	sellMult: number,
	upgradeCostMult: number,
}

export type MutationDef = {
	id: string,
	order: number,
	chance: number, -- independent of rarity
	statMult: number,
	incomeMult: number,
	color: Color3?, -- tint applied to the model (nil = original colours)
	tintAlpha: number, -- 0 = keep original colour, 1 = full tint
	material: Enum.Material?,
	reflectance: number?,
	rainbow: boolean?,
	sparkle: Color3?, -- sparkle particle colour
	prefix: string, -- shown before the name ("" for Normal)
}

export type Look = {
	builder: string, -- key into BrainrotModels / MonsterModels builders
	primary: Color3,
	secondary: Color3,
	accent: Color3,
	scale: number?,
	material: Enum.Material?,
}

export type BrainrotDef = {
	id: string,
	name: string,
	emoji: string,
	rarity: string,
	role: string,
	description: string,
	personality: string,
	hp: number,
	attack: number,
	defense: number,
	speed: string, -- key into GameConfig.SpeedTiers
	range: string, -- key into GameConfig.RangeTiers
	cooldown: number, -- seconds between basic attacks
	ability: string, -- AbilityConfig id
	passive: string?, -- AbilityConfig passive id
	sellValue: number,
	zooIncome: number, -- coins per minute (before mutation/level/habitat)
	habitat: string, -- preferred habitat id (income bonus)
	rollable: boolean, -- false = only from bosses/events
	idleQuirk: string, -- zoo idle animation flavour
	look: Look,
}

export type AbilityDef = {
	id: string,
	name: string,
	description: string,
	handler: string, -- key into server Combat/Abilities handlers
	cooldown: number,
	vfx: string, -- key into client effects
	color: Color3,
	params: { [string]: any },
}

export type PassiveDef = {
	id: string,
	name: string,
	description: string,
	params: { [string]: any },
}

export type MonsterDef = {
	id: string,
	name: string,
	kind: "Normal" | "Elite" | "MiniBoss" | "Boss",
	hp: number,
	attack: number,
	defense: number,
	speed: number, -- studs per second
	range: number, -- studs (edge to edge)
	cooldown: number,
	radius: number, -- body radius in studs (collision/targeting)
	height: number, -- for health bars
	projectile: boolean?,
	attacks: { string }?, -- boss attack ids (MonsterConfig.BossAttacks)
	enrageAt: number?, -- hp fraction that triggers enrage
	music: string?,
	title: string?, -- boss subtitle
	coins: number,
	xp: number,
	essence: number?,
	tokens: number?,
	bossTokens: number?,
	drops: { { brainrot: string, chance: number, mutation: string? } }?,
	look: Look,
}

export type WaveDef = {
	spawns: { { monster: string, count: number } },
	label: string?,
	boss: boolean?,
}

export type ArenaDef = {
	id: string,
	name: string,
	order: number,
	description: string,
	requiredLevel: number,
	requiresArena: string?, -- boss of this arena must have been beaten
	recommendedPower: number,
	statMult: number,
	rewardMult: number,
	floorMaterial: Enum.Material,
	floorColor: Color3,
	skyTint: Color3,
	fogColor: Color3,
	waves: { WaveDef },
}

-- Save data -----------------------------------------------------------------

export type BrainrotInstance = {
	id: string, -- BrainrotConfig id
	mut: string, -- MutationConfig id
	lvl: number,
	t: number, -- obtained (unix)
	locked: boolean?,
}

export type HabitatState = { unlocked: boolean, level: number, slots: { string } } -- slots = uids

export type PlayerData = {
	version: number,
	coins: number,
	gems: number,
	tokens: number,
	essence: number,
	bossTokens: number,
	level: number,
	xp: number,
	inventory: { [string]: BrainrotInstance },
	nextUid: number,
	equipped: { string },
	zoo: {
		habitats: { [string]: HabitatState },
		decorations: { string },
		bank: number,
	},
	upgrades: { [string]: number },
	pity: { [string]: number },
	totalRolls: number,
	seenRollAnim: boolean,
	index: { [string]: boolean },
	arena: { beaten: { [string]: boolean }, bestWave: { [string]: number }, bossKills: { [string]: number } },
	daily: { day: number, last: number },
	boosts: { [string]: number }, -- boost id -> expiry unix time
	settings: { [string]: any },
	passes: { [string]: boolean },
	receipts: { string },
	stats: { [string]: number },
	lastOnline: number,
	firstJoin: number,
}

return {}
