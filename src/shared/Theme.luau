--!strict
-- Art direction: "chunky storm-toy" look, built to read like a size simulator.
-- Everything is big, blocky and saturated, with thick dark outlines, neon cores and
-- stepped block terrain. The UI and the placeholder world builders both read these values,
-- so one edit restyles the whole game. Artists replacing placeholders should match
-- these proportions (see DESIGN.md "Art direction").

local rgb = Color3.fromRGB

local Theme = {}

-- UI ------------------------------------------------------------------------
Theme.Font = Enum.Font.FredokaOne
Theme.FontBody = Enum.Font.GothamBold

Theme.Colors = {
	Ink = rgb(22, 24, 44), -- outlines and text strokes
	Text = rgb(255, 255, 255),
	TextDim = rgb(200, 210, 235),
	Panel = rgb(44, 52, 96),
	PanelLight = rgb(62, 74, 132),
	PanelDark = rgb(30, 34, 66),
	Backdrop = rgb(10, 12, 24),
	Charge = rgb(255, 214, 51), -- main currency: electric yellow
	Static = rgb(110, 210, 255), -- jar contents: cyan
	Tokens = rgb(190, 120, 255), -- ascension tokens: violet
	Good = rgb(88, 224, 104),
	Bad = rgb(255, 84, 96),
	Warn = rgb(255, 170, 40),
	Robux = rgb(0, 176, 111),
	-- Button palette: each main button has its own colour so kids can navigate by colour
	Shop = rgb(255, 92, 120),
	Pets = rgb(255, 170, 40),
	Upgrades = rgb(64, 180, 255),
	Quests = rgb(88, 224, 104),
	Pass = rgb(190, 120, 255),
	Build = rgb(60, 220, 200),
	Trade = rgb(255, 130, 60),
	Index = rgb(240, 90, 200),
	Travel = rgb(120, 140, 255),
	Ascend = rgb(170, 90, 255),
}

Theme.UI = {
	Corner = 14, -- px corner radius on panels
	ButtonCorner = 16,
	Stroke = 4, -- thick outline on everything
	TextStroke = 3, -- via UIStroke on text labels
	-- Big touch targets: main bar buttons are at least this many px on phones (Apple/Google guidance ~44pt)
	MainButton = 76,
	SmallButton = 52,
	PanelWidth = 720,
	PanelHeight = 520,
	-- Base design resolution; UIScale adapts to the real viewport (mobile first)
	DesignSize = Vector2.new(1280, 720),
	MinScale = 0.55,
	MaxScale = 1.35,
	PopupRise = 90, -- px the "+Charge" number popups float up
	PressScale = 0.9, -- buttons squash on press
	BounceTime = 0.18,
}

-- Button face gradient: top is 18% lighter, bottom 18% darker (the "toy plastic" look)
function Theme.lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

function Theme.darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

-- World ---------------------------------------------------------------------
Theme.World = {
	Material = Enum.Material.SmoothPlastic, -- toy plastic body
	GlowMaterial = Enum.Material.Neon, -- cores, trims, gate frames
	GroundMaterial = Enum.Material.SmoothPlastic,
	TrimMaterial = Enum.Material.Neon,
	BlockSize = 12, -- terrain is built from stepped blocks of this size
	TerraceHeight = 4, -- each island has 2-3 stepped layers
	IslandThickness = 24,
	CloudColor = rgb(245, 248, 255),
	CloudBlock = 10,
	GateHeight = 44, -- gates are huge: players should feel tiny at first
	GateWidth = 60,
	SignTextSize = 80,
	PlaceholderTag = "Placeholder", -- CollectionService tag on every part an artist should replace
}

-- Scale language: later zones use bigger spirits, bigger props and bigger gates so progress
-- is felt visually, in the spirit of size simulators.
function Theme.zoneScale(zoneIndex: number): number
	return 1 + math.max(0, zoneIndex - 1) * 0.12
end

return Theme
