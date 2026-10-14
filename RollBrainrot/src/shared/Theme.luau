--!strict
-- Art direction: chunky, colourful, readable. UI uses thick dark outlines, rounded corners,
-- top-lit gradients and a bold stroked font.

local rgb = Color3.fromRGB

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamBold

Theme.Colors = {
	Ink = rgb(24, 20, 38),
	Text = rgb(255, 255, 255),
	TextDim = rgb(200, 205, 225),
	Panel = rgb(44, 40, 78),
	PanelLight = rgb(66, 60, 112),
	PanelDark = rgb(30, 27, 54),
	Primary = rgb(255, 92, 170), -- brainrot pink
	Secondary = rgb(70, 200, 255),
	Good = rgb(90, 220, 90),
	Bad = rgb(255, 70, 70),
	Warn = rgb(255, 190, 40),
	Coins = rgb(255, 210, 50),
	Gems = rgb(90, 220, 255),
	Tokens = rgb(255, 120, 200),
	Essence = rgb(170, 255, 120),
	BossTokens = rgb(255, 90, 60),
	Xp = rgb(120, 220, 255),
	Hp = rgb(90, 230, 90),
	HpEnemy = rgb(255, 70, 70),
	Boss = rgb(230, 40, 60),
	Locked = rgb(110, 110, 130),
}

Theme.Icons = {
	coins = "💰",
	gems = "💎",
	tokens = "🎟️",
	essence = "🧪",
	bossTokens = "👹",
	level = "⭐",
	power = "⚔️",
	income = "💵",
	zoo = "🏡",
	roll = "🎰",
	arena = "🏟️",
	shop = "🛒",
	upgrades = "⬆️",
	daily = "📅",
	events = "🌩️",
	collection = "📖",
}

function Theme.lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

function Theme.darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

Theme.UI = {
	Corner = 14,
	Stroke = 3,
	TextStroke = 2,
	DesignSize = Vector2.new(1280, 720),
}

return Theme
