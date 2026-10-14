--!strict
-- Every balance value and tunable that is not a Brainrot, monster, arena, rarity or
-- mutation row lives here. Numbers are first-pass and meant to be balanced in play-tests.

local rgb = Color3.fromRGB

local GameConfig = {}

-------------------------------------------------------------------------------
-- Economy / start
-------------------------------------------------------------------------------
GameConfig.Start = {
	Coins = 500,
	Gems = 0,
	Tokens = 5, -- first rolls are free
	StarterBrainrot = "BananiniBongo", -- given on first join so the arena is reachable at once
}

GameConfig.Roll = {
	CoinCost = 250,
	TokenCost = 1,
	-- Pity: after `threshold` rolls without a `minRarity`-or-better result, the next roll is
	-- forced to at least that rarity. Rolling one naturally also resets the counter.
	Pity = { id = "Legendary", threshold = 100, minRarity = "Legendary" },
	AnimSeconds = 3.2, -- full reveal
	FastAnimSeconds = 1.2, -- Fast Roll pass / upgrade
	AutoRollDelay = 0.6, -- pause between auto rolls after the reveal
	DisplayCycleNames = 14, -- how many names flash past before the reveal
}

GameConfig.Inventory = {
	BaseStorage = 150,
}

-- Brainrot levels (spend coins + Rot Essence). Stat mult = 1 + StatPerLevel*(lvl-1)
GameConfig.Leveling = {
	MaxLevel = 30,
	StatPerLevel = 0.12,
	IncomePerLevel = 0.1,
	BaseCoinCost = 100, -- × rarity.upgradeCostMult × CostGrowth^(lvl-1)
	CostGrowth = 1.32,
	EssencePerLevel = 1, -- × lvl × rarity order
}

-- Movement & range tiers referenced by BrainrotConfig
GameConfig.SpeedTiers = {
	Slow = 10,
	Medium = 13,
	Normal = 14,
	Fast = 18,
	VeryFast = 21,
	ExtremelyFast = 26,
} :: { [string]: number }

GameConfig.RangeTiers = {
	Melee = 4,
	Medium = 18,
	Long = 34,
} :: { [string]: number }

-------------------------------------------------------------------------------
-- Player progression
-------------------------------------------------------------------------------
GameConfig.Player = {
	XpBase = 100, -- xp to next = floor(XpBase * level^XpExponent)
	XpExponent = 1.5,
	MaxLevel = 100,
	BaseHealth = 100,
	HealthPerLevel = 15,
	BaseAttack = 10,
	AttackPerLevel = 3,
	LevelUpGems = 5,
	AttackRange = 12,
	AttackCooldown = 0.45,
}

-- Player abilities in battle (keyboard / gamepad / on-screen buttons)
GameConfig.PlayerAbilities = {
	Attack = { cooldown = 0.45, icon = "⚔️", label = "Attack" },
	Dodge = { key = Enum.KeyCode.Q, cooldown = 3, icon = "💨", label = "Dodge", iframes = 0.6, dashSpeed = 90 },
	Heal = { key = Enum.KeyCode.E, cooldown = 18, icon = "💚", label = "Heal", healPct = 0.35, revive = true },
	Rally = { key = Enum.KeyCode.R, cooldown = 24, icon = "📣", label = "Rally", attackMult = 1.5, duration = 8 },
	Ultimate = {
		key = Enum.KeyCode.F,
		cooldown = 1,
		icon = "☄️",
		label = "Ultimate",
		chargeNeeded = 100, -- charge gained from team damage (see ChargePerDamage)
		radius = 34,
		damageMult = 10, -- × average attack of the player's team
	},
} :: { [string]: { [string]: any } }
GameConfig.UltimateChargePerHit = 1.2 -- per team hit
GameConfig.UltimateChargePerKill = 3

-------------------------------------------------------------------------------
-- Combat
-------------------------------------------------------------------------------
GameConfig.Combat = {
	TickRate = 10, -- server AI ticks per second
	SnapshotRate = 10, -- position snapshots per second
	CritChance = 0.1,
	CritMult = 1.75,
	DefenseScale = 100, -- dmg × 100/(100+def)
	BrainrotRespawnSeconds = 8,
	AggroRange = 400,
	SeparationStrength = 0.6,
	MonsterAttackPlayerMult = 1, -- damage multiplier vs player characters
	PlayerHitboxRadius = 2,
	BrainrotRadius = 2.2,
	InvulnerableIntroSeconds = 5,
	DamageToCrowdHype = 0.02,
}

-------------------------------------------------------------------------------
-- Upgrades (UPGRADES stand). value(level) = base + perLevel*level, capped at max.
-- cost(level) = floor(baseCost * costGrowth^level). currency: "coins" | "gems"
-------------------------------------------------------------------------------
export type UpgradeDef = {
	id: string,
	name: string,
	icon: string,
	description: string,
	currency: "coins" | "gems",
	baseCost: number,
	costGrowth: number,
	maxLevel: number,
	base: number,
	perLevel: number,
	format: "mult" | "count" | "percent",
	order: number,
}

GameConfig.Upgrades = {
	Luck = {
		id = "Luck",
		name = "Roll Luck",
		icon = "🍀",
		description = "Increases your chance of rolling rare Brainrots.",
		currency = "coins",
		baseCost = 1000,
		costGrowth = 1.6,
		maxLevel = 20,
		base = 1,
		perLevel = 0.1,
		format = "mult",
		order = 1,
	},
	EquipSlots = {
		id = "EquipSlots",
		name = "Equip Slots",
		icon = "🎒",
		description = "Take more Brainrots into battle (3 → 8, +2 with the pass).",
		currency = "coins",
		baseCost = 5000,
		costGrowth = 4.5,
		maxLevel = 5,
		base = 3,
		perLevel = 1,
		format = "count",
		order = 2,
	},
	ZooIncome = {
		id = "ZooIncome",
		name = "Zoo Income",
		icon = "💰",
		description = "Multiplies all zoo income.",
		currency = "coins",
		baseCost = 750,
		costGrowth = 1.55,
		maxLevel = 25,
		base = 1,
		perLevel = 0.1,
		format = "mult",
		order = 3,
	},
	Storage = {
		id = "Storage",
		name = "Brainrot Storage",
		icon = "📦",
		description = "Hold more Brainrots in your collection.",
		currency = "coins",
		baseCost = 2000,
		costGrowth = 1.8,
		maxLevel = 10,
		base = 0,
		perLevel = 25,
		format = "count",
		order = 4,
	},
	TrainerPower = {
		id = "TrainerPower",
		name = "Trainer Power",
		icon = "💪",
		description = "Boosts your own attack and health in the arena.",
		currency = "coins",
		baseCost = 800,
		costGrowth = 1.5,
		maxLevel = 30,
		base = 1,
		perLevel = 0.15,
		format = "mult",
		order = 5,
	},
	RollSpeed = {
		id = "RollSpeed",
		name = "Quick Rolls",
		icon = "⚡",
		description = "Shortens the roll animation.",
		currency = "gems",
		baseCost = 40,
		costGrowth = 2,
		maxLevel = 3,
		base = 0,
		perLevel = 0.2,
		format = "percent",
		order = 6,
	},
} :: { [string]: UpgradeDef }

-------------------------------------------------------------------------------
-- Zoo
-------------------------------------------------------------------------------
export type HabitatDef = {
	id: string,
	name: string,
	order: number,
	cost: number, -- coins to unlock
	requiresArena: string?,
	baseSlots: number,
	slotsPerLevel: number,
	maxLevel: number,
	upgradeBaseCost: number,
	upgradeGrowth: number,
	incomePerLevel: number, -- habitat income bonus per level above 1
	ground: Enum.Material,
	groundColor: Color3,
	fence: Color3,
	emoji: string,
}

GameConfig.Habitats = {
	{
		id = "Grass",
		name = "Grass Habitat",
		order = 1,
		cost = 0,
		baseSlots = 3,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 400,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.1,
		ground = Enum.Material.Grass,
		groundColor = rgb(110, 200, 80),
		fence = rgb(255, 255, 255),
		emoji = "🌱",
	},
	{
		id = "Forest",
		name = "Forest Habitat",
		order = 2,
		cost = 3000,
		baseSlots = 3,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 2000,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.1,
		ground = Enum.Material.LeafyGrass,
		groundColor = rgb(60, 130, 55),
		fence = rgb(120, 80, 45),
		emoji = "🌲",
	},
	{
		id = "Desert",
		name = "Desert Habitat",
		order = 3,
		cost = 20000,
		baseSlots = 3,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 10000,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.1,
		ground = Enum.Material.Sand,
		groundColor = rgb(235, 205, 140),
		fence = rgb(200, 150, 90),
		emoji = "🏜️",
	},
	{
		id = "Ice",
		name = "Ice Habitat",
		order = 4,
		cost = 100000,
		baseSlots = 3,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 50000,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.1,
		ground = Enum.Material.Ice,
		groundColor = rgb(200, 235, 255),
		fence = rgb(150, 200, 255),
		emoji = "🧊",
	},
	{
		id = "Volcano",
		name = "Volcano Habitat",
		order = 5,
		cost = 600000,
		requiresArena = "DesertColosseum",
		baseSlots = 3,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 300000,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.1,
		ground = Enum.Material.Basalt,
		groundColor = rgb(70, 55, 55),
		fence = rgb(255, 110, 30),
		emoji = "🌋",
	},
	{
		id = "Alien",
		name = "Alien Habitat",
		order = 6,
		cost = 3000000,
		requiresArena = "FrozenWasteland",
		baseSlots = 3,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 1500000,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.1,
		ground = Enum.Material.Neon,
		groundColor = rgb(80, 40, 140),
		fence = rgb(80, 255, 200),
		emoji = "👽",
	},
	{
		id = "Giant",
		name = "Giant Habitat",
		order = 7,
		cost = 15000000,
		requiresArena = "VolcanicArena",
		baseSlots = 4,
		slotsPerLevel = 1,
		maxLevel = 6,
		upgradeBaseCost = 8000000,
		upgradeGrowth = 2.2,
		incomePerLevel = 0.15,
		ground = Enum.Material.Grass,
		groundColor = rgb(150, 220, 90),
		fence = rgb(255, 210, 60),
		emoji = "🦕",
	},
} :: { HabitatDef }

GameConfig.Zoo = {
	AffinityBonus = 0.25, -- +25% income in the Brainrot's preferred habitat
	OfflineRate = 0.5, -- fraction of income earned while offline
	OfflineCapHours = 12,
	OfflineMinSeconds = 120,
	TickSeconds = 5, -- how often the zoo bank accrues
}

export type DecorationDef = {
	id: string,
	name: string,
	cost: number,
	currency: "coins" | "gems",
	incomeBonus: number,
	vip: boolean?,
	builder: string, -- key into World/Props decoration builders
	order: number,
}

GameConfig.Decorations = {
	{ id = "FlowerBed", name = "Flower Bed", cost = 500, currency = "coins", incomeBonus = 0.02, builder = "FlowerBed", order = 1 },
	{ id = "Lamp", name = "Zoo Lamps", cost = 1500, currency = "coins", incomeBonus = 0.03, builder = "LampPair", order = 2 },
	{ id = "Fountain", name = "Fountain", cost = 8000, currency = "coins", incomeBonus = 0.05, builder = "Fountain", order = 3 },
	{ id = "Balloons", name = "Balloon Arch", cost = 25000, currency = "coins", incomeBonus = 0.06, builder = "BalloonArch", order = 4 },
	{ id = "Statue", name = "Brainrot Statue", cost = 120000, currency = "coins", incomeBonus = 0.1, builder = "Statue", order = 5 },
	{ id = "GoldTrophy", name = "Gold Trophy", cost = 150, currency = "gems", incomeBonus = 0.12, builder = "Trophy", order = 6 },
	{ id = "VipCarpet", name = "VIP Red Carpet", cost = 0, currency = "coins", incomeBonus = 0.1, vip = true, builder = "VipCarpet", order = 7 },
} :: { DecorationDef }

-------------------------------------------------------------------------------
-- Boosts (timed, stacking duration)
-------------------------------------------------------------------------------
GameConfig.Boosts = {
	Luck = { name = "Luck Boost", icon = "🍀", mult = 2 },
	Coins = { name = "Coin Boost", icon = "💰", mult = 2 },
	XP = { name = "XP Boost", icon = "⭐", mult = 2 },
} :: { [string]: { name: string, icon: string, mult: number } }

-------------------------------------------------------------------------------
-- Daily rewards (7-day cycle; missing a day by more than GraceHours resets the streak)
-- kind: coins | gems | tokens | boost | brainrot
-------------------------------------------------------------------------------
GameConfig.Daily = {
	CooldownHours = 20,
	GraceHours = 48,
	Rewards = {
		{ kind = "coins", amount = 1000, label = "1,000 Coins", icon = "💰" },
		{ kind = "tokens", amount = 5, label = "5 Roll Tokens", icon = "🎟️" },
		{ kind = "boost", boost = "XP", minutes = 15, label = "XP Boost 15m", icon = "⭐" },
		{ kind = "boost", boost = "Luck", minutes = 15, label = "Luck Boost 15m", icon = "🍀" },
		{ kind = "brainrot", rarity = "Rare", label = "Rare Brainrot", icon = "🐸" },
		{ kind = "gems", amount = 50, label = "50 Gems", icon = "💎" },
		{ kind = "brainrot", rarity = "Epic", mutation = "Golden", label = "Golden Epic Brainrot", icon = "🐊" },
	} :: { { [string]: any } },
}

-------------------------------------------------------------------------------
-- World events (server-wide). One random event every Interval seconds.
-------------------------------------------------------------------------------
export type WorldEventDef = {
	id: string,
	name: string,
	description: string,
	duration: number,
	weight: number,
	color: Color3,
	luckMult: number?,
	monsterMult: number?,
	rewardMult: number?,
}

GameConfig.Events = {
	Interval = 480,
	FirstDelay = 120,
	List = {
		{
			id = "MeteorShower",
			name = "METEOR SHOWER",
			description = "Meteors are crashing into the arena!",
			duration = 150,
			weight = 3,
			color = rgb(255, 140, 40),
			rewardMult = 1.25,
		},
		{
			id = "Storm",
			name = "STORM",
			description = "Lightning strikes the battlefield!",
			duration = 150,
			weight = 3,
			color = rgb(120, 170, 255),
		},
		{
			id = "BloodMoon",
			name = "BLOOD MOON",
			description = "Monsters are stronger, but drop better rewards.",
			duration = 180,
			weight = 2,
			color = rgb(220, 30, 50),
			monsterMult = 1.5,
			rewardMult = 2,
		},
		{
			id = "GoldenHour",
			name = "GOLDEN HOUR",
			description = "Roll luck is doubled!",
			duration = 180,
			weight = 3,
			color = rgb(255, 210, 60),
			luckMult = 2,
		},
		{
			id = "GiantInvasion",
			name = "GIANT MONSTER INVASION",
			description = "A giant monster is attacking the Brainrot Zoo!",
			duration = 240,
			weight = 2,
			color = rgb(180, 60, 255),
		},
	} :: { WorldEventDef },
	InvasionBoss = "GiantMutant",
	StrikeInterval = 1.5, -- meteor / lightning strikes
	StrikeDamageMult = 0.08, -- fraction of a monster's max HP per strike
}

-------------------------------------------------------------------------------
-- Monetization (optional; ids of 0 show "Coming soon" and cannot be bought)
-------------------------------------------------------------------------------
GameConfig.GamePasses = {
	ExtraSlots = { id = 0, name = "+2 Equip Slots", icon = "🎒", description = "Take 2 more Brainrots into battle.", priceHint = 199 },
	AutoRoll = { id = 0, name = "Auto Roll", icon = "🔁", description = "Roll automatically until you stop.", priceHint = 149 },
	FastRoll = { id = 0, name = "Fast Roll", icon = "⚡", description = "Much faster roll animations.", priceHint = 99 },
	ExtraStorage = { id = 0, name = "+300 Storage", icon = "📦", description = "Hold 300 more Brainrots.", priceHint = 99 },
	VIP = { id = 0, name = "VIP", icon = "👑", description = "VIP zoo decorations, +10% coins, gold name.", priceHint = 399 },
} :: { [string]: { id: number, name: string, icon: string, description: string, priceHint: number } }

GameConfig.Products = {
	LuckBoost = { id = 0, name = "2x Luck (15m)", icon = "🍀", grant = { boost = "Luck", minutes = 15 }, priceHint = 49 },
	CoinBoost = { id = 0, name = "2x Coins (15m)", icon = "💰", grant = { boost = "Coins", minutes = 15 }, priceHint = 49 },
	XPBoost = { id = 0, name = "2x XP (15m)", icon = "⭐", grant = { boost = "XP", minutes = 15 }, priceHint = 29 },
	Tokens10 = { id = 0, name = "10 Roll Tokens", icon = "🎟️", grant = { tokens = 10 }, priceHint = 79 },
	Tokens50 = { id = 0, name = "50 Roll Tokens", icon = "🎟️", grant = { tokens = 50 }, priceHint = 329 },
	Gems100 = { id = 0, name = "100 Gems", icon = "💎", grant = { gems = 100 }, priceHint = 99 },
} :: { [string]: { id: number, name: string, icon: string, grant: { [string]: any }, priceHint: number } }

-- Things free players can buy with gems earned by levelling / daily rewards
GameConfig.GemShop = {
	{ id = "GemLuck", name = "2x Luck (10m)", icon = "🍀", cost = 30, grant = { boost = "Luck", minutes = 10 } },
	{ id = "GemCoins", name = "2x Coins (10m)", icon = "💰", cost = 30, grant = { boost = "Coins", minutes = 10 } },
	{ id = "GemTokens", name = "5 Roll Tokens", icon = "🎟️", cost = 25, grant = { tokens = 5 } },
	{ id = "BossCrate", name = "Boss Crate (10 Boss Tokens)", icon = "👹", cost = 0, bossTokens = 10, grant = { crate = "Epic" } },
} :: { { [string]: any } }

GameConfig.Vip = { CoinMult = 1.1 }

-------------------------------------------------------------------------------
-- Audio. rbxasset:// sounds ship with every Roblox client so they never disappear;
-- replace with uploaded ids for final audio. Empty strings are skipped.
-------------------------------------------------------------------------------
GameConfig.Sounds = {
	Click = "rbxasset://sounds/clickfast.wav",
	Open = "rbxasset://sounds/button.wav",
	RollTick = "rbxasset://sounds/clickfast.wav",
	RollShake = "rbxasset://sounds/collide.wav",
	Reveal = "rbxasset://sounds/electronicpingshort.wav",
	RevealBig = "rbxasset://sounds/Launching rocket.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
	Swing = "rbxasset://sounds/swordlunge.wav",
	Explosion = "rbxasset://sounds/Rocket shot.wav",
	Whoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	Coins = "rbxasset://sounds/electronicpingshort.wav",
	Error = "rbxasset://sounds/uuhhh.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	HubMusic = "",
	BattleMusic = "",
	BossMusic = "",
	CrowdCheer = "",
} :: { [string]: string }

-------------------------------------------------------------------------------
-- World layout (studs). The builders and the client both read these, so the client
-- can place zoo creatures without waiting for streamed parts.
-------------------------------------------------------------------------------
GameConfig.World = {
	GroundY = 0,
	Spawn = Vector3.new(0, 4, 175),
	Plaza = { center = Vector3.new(0, 0, 0), radius = 78 },
	Machine = Vector3.new(0, 0, -8),
	Hub = { minX = -560, maxX = 560, minZ = -540, maxZ = 520 },
	-- Personal zoo plots (one per player, up to 6 per server). origin = plot centre,
	-- facing = direction from the plot towards the hub road.
	Plots = {
		{ origin = Vector3.new(-330, 0, -170), facing = Vector3.new(1, 0, 0) },
		{ origin = Vector3.new(-330, 0, 40), facing = Vector3.new(1, 0, 0) },
		{ origin = Vector3.new(-330, 0, 250), facing = Vector3.new(1, 0, 0) },
		{ origin = Vector3.new(330, 0, -170), facing = Vector3.new(-1, 0, 0) },
		{ origin = Vector3.new(330, 0, 40), facing = Vector3.new(-1, 0, 0) },
		{ origin = Vector3.new(330, 0, 250), facing = Vector3.new(-1, 0, 0) },
	},
	PlotSize = Vector2.new(190, 170), -- across × deep
	-- Habitat pens inside a plot, in plot-local space where plotCFrame =
	-- CFrame.lookAt(origin, origin + facing): -Z is towards the road (front), X is across.
	-- Order matches GameConfig.Habitats; the 7th (Giant) is a long pen along the back.
	HabitatOffsets = {
		Vector3.new(-60, 0, -34),
		Vector3.new(0, 0, -34),
		Vector3.new(60, 0, -34),
		Vector3.new(-60, 0, 24),
		Vector3.new(0, 0, 24),
		Vector3.new(60, 0, 24),
		Vector3.new(0, 0, 68),
	},
	HabitatSize = Vector2.new(52, 50), -- across × deep
	GiantHabitatSize = Vector2.new(172, 26),
	PlotFrontOffset = -72, -- entrance / sign / collector, plot-local Z
	-- Stadium
	Arena = {
		center = Vector3.new(0, 0, -1320),
		fieldRadius = 540, -- open battlefield (inner wall at 540..548)
		wallHeight = 42,
		standsInner = 548,
		tierCount = 6, -- stepped stands; two crowd rows per tier
		tierDepth = 24,
		tierRise = 18,
		facadeHeight = 175,
		gateHalfWidth = 30, -- south tunnel towards the hub
		bossGateHalfWidth = 46, -- north boss entrance
	},
	ArenaGate = Vector3.new(0, 4, -585), -- forecourt outside the south gate (players return here)
	ArenaEntry = Vector3.new(0, 4, -840), -- where fighters appear inside the battlefield
	InvasionField = { center = Vector3.new(0, 0, 380), radius = 120 },
	Stands = {
		Shop = Vector3.new(-120, 0, 110),
		Upgrades = Vector3.new(120, 0, 110),
		Daily = Vector3.new(-130, 0, -90),
		Events = Vector3.new(130, 0, -90),
	} :: { [string]: Vector3 },
}

GameConfig.Crowd = {
	Rows = 12,
	PerRowDensity = 0.11, -- spectators per stud of row circumference
	MaxSpectators = 1600,
	ActiveDistance = 1400, -- only animate when the camera is this close to the arena
	UpdateHz = 20,
}

GameConfig.Security = {
	AdminUserIds = {} :: { number }, -- plus the place owner / Studio
	MaxStorageHard = 2000,
}

GameConfig.SaveVersion = 1
GameConfig.DataStoreName = "RollBrainrot_v1"
GameConfig.AutoSaveSeconds = 60

return GameConfig
