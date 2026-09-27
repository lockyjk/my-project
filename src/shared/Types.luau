--!strict
-- Shared type definitions for config data and saved player data.
-- Keep these in sync with Config.luau and DataTemplate.luau.

export type Rarity = {
	id: string,
	name: string,
	order: number, -- 1 = Common ... 7 = Secret
	color: Color3,
	announce: boolean, -- server-wide chat/toast announcement on hatch
	shake: number, -- screen shake intensity on reveal (0 = none)
}

export type SpiritDef = {
	id: string,
	name: string,
	value: number, -- base Static per catch before zone/player multipliers
	rarity: string,
	color: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
	size: number,
	storm: string?, -- only spawns during this storm type
	petDrop: { pet: string, chance: number }?, -- rare direct pet catch (luck scales chance)
}

export type SpawnEntry = { spirit: string, weight: number }

export type ZoneDef = {
	id: string,
	index: number,
	name: string,
	gateCost: number,
	valueMult: number,
	spawns: { SpawnEntry },
	egg: string?,
	maxSpirits: number,
	spiritsPerPlayer: number,
	respawnSeconds: number,
	ground: Color3,
	accent: Color3,
	vipOnly: boolean?,
	-- VIP-style side zones scale off the player's best unlocked zone instead of a fixed valueMult
	bestZoneScale: number?,
}

export type PetDef = {
	id: string,
	name: string,
	rarity: string,
	power: number, -- additive Charge bonus (0.25 = +25%) at tier 1
	color: Color3,
	accent: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
	tradeable: boolean?,
}

export type EggEntry = { pet: string, weight: number }

export type EggDef = {
	id: string,
	name: string,
	currency: "Charge" | "Robux" | "Free",
	cost: number, -- Charge cost (0 for Robux/Free eggs)
	product: string?, -- ProductKey for Robux eggs
	pets: { EggEntry },
	zone: string?, -- physical stand location
	storm: string?, -- only hatchable during this storm
	event: string?, -- only hatchable during this live event
	hidden: boolean?, -- not shown on a stand (e.g. streak egg)
}

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	icon: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	-- value(level) = mode "linear": base + perLevel*level
	--                mode "exp":    base * perLevel^level
	--                mode "decay":  base * perLevel^level (perLevel < 1)
	mode: "linear" | "exp" | "decay",
	base: number,
	perLevel: number,
	min: number?,
	max: number?,
	unit: string,
}

export type AscNode = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	cost: number, -- tokens per level (flat) ...
	costGrowth: number, -- ... times costGrowth^level
	stat: string,
	perLevel: number,
	requires: string?,
}

export type Reward = {
	charge: number?, -- flat Charge
	chargeMinutes: number?, -- Charge equal to N minutes of estimated income (scales with progress)
	tokens: number?,
	passXP: number?,
	potions: { [string]: number }?,
	pet: string?,
	egg: string?, -- free hatch of this egg
	fusionSkips: number?,
	decoration: string?,
}

export type QuestTemplate = {
	id: string,
	kind: "Catch" | "CatchStorm" | "CatchShiny" | "Hatch" | "Fuse" | "Earn" | "Sell" | "Explore" | "Upgrade" | "PlayMinutes",
	text: string, -- "{n}" is replaced with target
	base: number,
	scale: number, -- target multiplier per zone unlocked beyond the first (for Earn scaled by zone value)
	reward: Reward,
	daily: boolean,
	weekly: boolean,
}

export type AchievementDef = {
	id: string,
	name: string,
	stat: string,
	target: number,
	reward: Reward,
}

export type DecorationDef = {
	id: string,
	name: string,
	cost: number,
	size: Vector2, -- grid cells (x, z)
	height: number,
	color: Color3,
	shape: "Ball" | "Block" | "Cylinder" | "Wedge",
	boost: { stat: string, amount: number }?,
	maxBoosting: number?, -- how many copies count toward the boost
	unlockZone: number?, -- zone index required to buy
}

export type PotionDef = {
	id: string,
	name: string,
	stat: "Luck" | "Speed" | "Charge",
	mult: number,
	seconds: number,
	color: Color3,
}

export type LiveEventDef = {
	id: string,
	name: string,
	description: string,
	startUnix: number,
	endUnix: number,
	chargeMult: number?,
	luckMult: number?,
	spawnMult: number?,
	spirits: { SpawnEntry }?, -- added to every zone's spawn table (values scale with zone)
	egg: string?,
	color: Color3,
}

export type StormDef = {
	id: string,
	name: string,
	description: string,
	chargeMult: number,
	spawnMult: number,
	spirits: { SpawnEntry },
	egg: string?,
	sky: Color3,
	fog: Color3,
}

export type PassDef = {
	key: string,
	id: number, -- Game Pass asset id (0 = not configured yet)
	name: string,
	description: string,
	priceHint: number, -- Robux, display only; real price comes from MarketplaceService
}

export type ProductDef = {
	key: string,
	id: number, -- Developer Product id (0 = not configured yet)
	name: string,
	description: string,
	priceHint: number,
	kind: "ChargePack" | "Potion" | "Egg" | "PassSkip" | "PassPremium" | "InstantFusion" | "StarterPack",
	minutes: number?, -- ChargePack: minutes of estimated income
	potion: string?,
	count: number?,
	egg: string?,
}

export type PassTierReward = { free: Reward, premium: Reward }

-- Saved data ----------------------------------------------------------------

export type PetInstance = {
	uid: string,
	id: string,
	tier: number, -- 1 Base, 2 Charged, 3 Supercharged, 4 Tempest
	shiny: boolean?,
	locked: boolean?,
	source: string, -- "Egg" | "RobuxEgg" | "Catch" | "Reward" | "Trade" | "Fusion"
	obtained: number,
}

export type FusionJob = {
	uid: string, -- uid the result pet will get
	id: string,
	tier: number, -- resulting tier
	startAt: number,
	endAt: number,
	robuxSourced: boolean?,
}

export type QuestState = {
	template: string,
	target: number,
	progress: number,
	claimed: boolean,
	zone: string?,
}

export type PlacedDecoration = { id: string, x: number, z: number, r: number }

export type ProfileData = {
	DataVersion: number,
	Charge: number,
	Static: number,
	LifetimeCharge: number,
	Upgrades: { [string]: number },
	UnlockedZones: { [string]: boolean },
	LastZone: string,
	Pets: { [string]: PetInstance },
	Equipped: { string },
	Ascensions: number,
	Tokens: number,
	AscTree: { [string]: number },
	Fusions: { FusionJob },
	FusionSkips: number,
	Index: { [string]: boolean },
	IndexRewards: { [string]: boolean },
	Achievements: { [string]: boolean },
	Stats: { [string]: number },
	Daily: { Streak: number, LastClaimDay: number, PremiumDay: number },
	Quests: {
		DailyDay: number,
		Daily: { QuestState },
		WeeklyWeek: number,
		Weekly: { QuestState },
	},
	Pass: { Season: string, XP: number, Premium: boolean, ClaimedFree: { [string]: boolean }, ClaimedPremium: { [string]: boolean } },
	Boosts: { [string]: number }, -- potion stat -> expiry unix time
	Potions: { [string]: number },
	Island: { Size: number, Placed: { PlacedDecoration }, Owned: { [string]: number } },
	Purchases: {
		Receipts: { [string]: number },
		ReceiptOrder: { string },
		StarterPack: boolean,
		FirstPurchaseAt: number,
		RobuxSpent: number,
	},
	Flags: { [string]: boolean },
	Settings: { AutoDelete: { [string]: boolean }, Music: boolean, Sfx: boolean, AutoCatch: boolean, HidePets: boolean },
	FirstJoin: number,
	LastLogin: number,
	LastLogout: number,
	LoginCount: number,
	TradeHistory: { { with: number, at: number, gave: { string }, got: { string } } },
	EventProgress: { [string]: { [string]: number } },
	BestPet: string, -- rarest Stormling ever owned (leaderboard)
	BestPetTier: number,
}

return {}
