--!strict
-- Tiny event bus so UI modules can ask each other for things without requiring each other.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Signal = require(Modules:WaitForChild("Signal"))

return {
	-- (uid?) open the collection, optionally selecting a Brainrot
	ViewBrainrot = Signal.new() :: Signal.Signal<string?>,
	-- (window name)
	OpenWindow = Signal.new() :: Signal.Signal<string>,
	-- ("Roll" | "Arena" | …) a world prompt was used
	PromptAction = Signal.new() :: Signal.Signal<string, ProximityPrompt>,
	-- the boss intro cinematic started / ended
	BossIntro = Signal.new() :: Signal.Signal<{ [string]: any }>,
	-- crowd hype events: ("cheer" | "roar" | "celebrate" | "gasp", intensity)
	Crowd = Signal.new() :: Signal.Signal<string, number>,
}
