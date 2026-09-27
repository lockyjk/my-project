--!strict
-- Server-wide gameplay event bus. Producers fire, listeners (quests, achievements, pass XP,
-- analytics) subscribe. Keeps services decoupled and free of require cycles.

local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

return {
	-- (player, spiritId, zoneId, shiny, staticAmount, isStorm)
	Caught = Signal.new() :: Signal.Signal<Player, string, string, boolean, number, boolean>,
	-- (player, chargeAmount)
	Sold = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, amount, source)
	ChargeEarned = Signal.new() :: Signal.Signal<Player, number, string>,
	-- (player, amount, sink, item)
	ChargeSpent = Signal.new() :: Signal.Signal<Player, number, string, string>,
	-- (player, upgradeId, newLevel)
	Upgraded = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, zoneId)
	ZoneUnlocked = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, zoneId)
	ZoneEntered = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, eggId, count)
	Hatched = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, pet, source)
	PetObtained = Signal.new() :: Signal.Signal<Player, Types.PetInstance, string>,
	-- (player, petId, tier)
	FusionStarted = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, ascensionCount)
	Ascended = Signal.new() :: Signal.Signal<Player, number>,
	-- (player)
	Traded = Signal.new() :: Signal.Signal<Player>,
	-- (player, decorationId)
	DecorationPlaced = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, xp)
	PassXP = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, productKey, robux)
	Purchased = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, step name)
	Tutorial = Signal.new() :: Signal.Signal<Player, number>,
	-- () storm/event state changed
	WeatherChanged = Signal.new() :: Signal.Signal<>,
}
