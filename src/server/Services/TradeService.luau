--!strict
-- Scam-safe pet trading between two players in the same server.
--   1. Request -> accept.
--   2. Both build offers (up to Config.Trade.MaxPets). ANY change un-readies both sides and
--      is written to a visible change log.
--   3. Both press Ready -> Confirming. Confirm unlocks after ConfirmDelay seconds.
--   4. Both Confirm -> server re-validates everything and swaps atomically, then saves both.
-- Locked pets, untradeable pets and (per PolicyService) pets from paid eggs can't be offered.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local TradeService = {}

type Side = { player: Player, uids: { string }, ready: boolean, confirmed: boolean }
type Trade = {
	id: number,
	sides: { Side },
	state: "Negotiating" | "Confirming" | "Done" | "Cancelled",
	confirmAt: number,
	log: { string },
}

local trades: { [Player]: Trade } = {}
local requests: { [Player]: { from: Player, at: number } } = {}
local lastRequest: { [Player]: number } = {}
local nextId = 0

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function playMinutes(player: Player): number
	local data = DataService.get(player)
	local session = DataService.session(player)
	if not data or not session then
		return 0
	end
	return (data.Stats.PlaySeconds + (os.clock() - session.JoinClock) - session.PlayCounted) / 60
end

local function sideOf(trade: Trade, player: Player): (Side, Side)
	if trade.sides[1].player == player then
		return trade.sides[1], trade.sides[2]
	end
	return trade.sides[2], trade.sides[1]
end

local function petView(data: Types.ProfileData?, uids: { string }): { any }
	local out = {}
	if not data then
		return out
	end
	for _, uid in uids do
		local pet = data.Pets[uid]
		if pet then
			table.insert(out, { uid = uid, id = pet.id, tier = pet.tier, source = pet.source })
		end
	end
	return out
end

local function push(trade: Trade)
	for _, side in trade.sides do
		local mine, theirs = sideOf(trade, side.player)
		Net.Server.fire("TradeUpdate", side.player, {
			id = trade.id,
			state = trade.state,
			partner = { name = theirs.player.DisplayName, userId = theirs.player.UserId },
			mine = petView(DataService.get(mine.player), mine.uids),
			theirs = petView(DataService.get(theirs.player), theirs.uids),
			myReady = mine.ready,
			theirReady = theirs.ready,
			myConfirmed = mine.confirmed,
			theirConfirmed = theirs.confirmed,
			confirmAt = trade.confirmAt,
			log = trade.log,
		})
	end
end

local function finish(trade: Trade, state: "Done" | "Cancelled", reason: string?)
	trade.state = state
	if reason then
		table.insert(trade.log, reason)
	end
	push(trade)
	for _, side in trade.sides do
		if trades[side.player] == trade then
			trades[side.player] = nil
		end
	end
end

local function canTradePet(player: Player, partner: Player, pet: Types.PetInstance): (boolean, string?)
	local def = Defs.Pet[pet.id]
	if not def or def.tradeable == false then
		return false, `{if def then def.name else pet.id} can't be traded`
	end
	if pet.locked then
		return false, "Unlock a pet before trading it"
	end
	if pet.source == "RobuxEgg" then
		for _, p in { player, partner } do
			local session = DataService.session(p)
			if not session or not session.Policy.PaidItemTradingAllowed then
				return false, "Pets from paid eggs can't be traded here"
			end
		end
	end
	return true
end

function TradeService.request(player: Player, targetUserId: number): (boolean, string?)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return false, "Player not found"
	end
	if trades[player] or trades[target] then
		return false, "Someone is already trading"
	end
	if os.clock() - (lastRequest[player] or 0) < Config.Trade.Cooldown then
		return false, "Wait a moment before sending another request"
	end
	for _, p in { player, target } do
		if not DataService.isLoaded(p) then
			return false, "Not ready"
		end
		if playMinutes(p) < Config.Trade.MinPlayMinutes then
			return false, `Both players need {Config.Trade.MinPlayMinutes} minutes of play time to trade`
		end
	end
	lastRequest[player] = os.clock()
	requests[target] = { from = player, at = now() }
	Net.Server.fire("TradeInvite", target, player.UserId, player.DisplayName)
	return true
end

function TradeService.respond(player: Player, fromUserId: number, accept: boolean): (boolean, string?)
	local req = requests[player]
	requests[player] = nil
	if not req or req.from.UserId ~= fromUserId or now() - req.at > Config.Trade.RequestTimeout then
		return false, "That request expired"
	end
	local from = req.from
	if not accept then
		Net.Server.fire("Notify", from, "Info", `{player.DisplayName} declined your trade`)
		return true
	end
	if trades[player] or trades[from] or from.Parent ~= Players then
		return false, "Trade unavailable"
	end
	nextId += 1
	local trade: Trade = {
		id = nextId,
		sides = {
			{ player = from, uids = {}, ready = false, confirmed = false },
			{ player = player, uids = {}, ready = false, confirmed = false },
		},
		state = "Negotiating",
		confirmAt = 0,
		log = { "Trade started. Check every Stormling carefully before confirming!" },
	}
	trades[from] = trade
	trades[player] = trade
	push(trade)
	return true
end

local function unready(trade: Trade)
	for _, s in trade.sides do
		s.ready = false
		s.confirmed = false
	end
	trade.state = "Negotiating"
	trade.confirmAt = 0
end

function TradeService.setOffer(player: Player, uids: { string }): (boolean, string?)
	local trade = trades[player]
	local data = DataService.get(player)
	if not trade or not data or trade.state == "Done" or trade.state == "Cancelled" then
		return false, "No active trade"
	end
	local mine, theirs = sideOf(trade, player)
	local seen = {}
	for _, uid in uids do
		local pet = data.Pets[uid]
		if not pet or seen[uid] then
			return false, "Invalid pet"
		end
		seen[uid] = true
		local ok, why = canTradePet(player, theirs.player, pet)
		if not ok then
			return false, why
		end
	end
	-- Describe the change for the log (added / removed)
	local before = {}
	for _, uid in mine.uids do
		before[uid] = true
	end
	local added, removed = 0, 0
	for _, uid in uids do
		if not before[uid] then
			added += 1
		end
	end
	for _, uid in mine.uids do
		if not seen[uid] then
			removed += 1
		end
	end
	mine.uids = table.clone(uids)
	unready(trade)
	if added > 0 or removed > 0 then
		table.insert(trade.log, `{player.DisplayName} changed their offer (+{added} / -{removed}). Ready reset.`)
	end
	push(trade)
	return true
end

function TradeService.setReady(player: Player, ready: boolean): (boolean, string?)
	local trade = trades[player]
	if not trade or trade.state == "Done" or trade.state == "Cancelled" then
		return false, "No active trade"
	end
	local mine, theirs = sideOf(trade, player)
	if #mine.uids == 0 and #theirs.uids == 0 then
		return false, "Add something to the trade first"
	end
	mine.ready = ready
	mine.confirmed = false
	if not ready then
		unready(trade)
	elseif theirs.ready then
		trade.state = "Confirming"
		trade.confirmAt = now() + Config.Trade.ConfirmDelay
		table.insert(trade.log, "Both players are ready. Review the final trade, then confirm.")
	end
	push(trade)
	return true
end

local function execute(trade: Trade): (boolean, string?)
	local a, b = trade.sides[1], trade.sides[2]
	local dataA, dataB = DataService.get(a.player), DataService.get(b.player)
	if not dataA or not dataB then
		return false, "A player left"
	end
	-- Re-validate ownership and rules at the moment of the swap
	local function validate(side: Side, other: Side, data: Types.ProfileData): (boolean, string?)
		for _, uid in side.uids do
			local pet = data.Pets[uid]
			if not pet then
				return false, "An offered pet is no longer available"
			end
			local ok, why = canTradePet(side.player, other.player, pet)
			if not ok then
				return false, why
			end
		end
		return true
	end
	local okA, whyA = validate(a, b, dataA)
	if not okA then
		return false, whyA
	end
	local okB, whyB = validate(b, a, dataB)
	if not okB then
		return false, whyB
	end
	local countA, countB = PetService.count(dataA), PetService.count(dataB)
	if countA - #a.uids + #b.uids > Config.Economy.MaxPets or countB - #b.uids + #a.uids > Config.Economy.MaxPets then
		return false, "Someone's pet inventory would be too full"
	end
	-- Snapshot, remove, then give (receivers get fresh uids)
	local fromA, fromB = {}, {}
	for _, uid in a.uids do
		table.insert(fromA, table.clone(dataA.Pets[uid]))
	end
	for _, uid in b.uids do
		table.insert(fromB, table.clone(dataB.Pets[uid]))
	end
	PetService.removePets(a.player, a.uids)
	PetService.removePets(b.player, b.uids)
	local function receive(player: Player, pets: { Types.PetInstance })
		for _, pet in pets do
			PetService.givePet(player, pet.id, "Trade", pet.tier, pet.source == "RobuxEgg")
		end
	end
	receive(b.player, fromA)
	receive(a.player, fromB)
	local t = now()
	local function record(side: Side, other: Side, data: Types.ProfileData, gavePets: { Types.PetInstance }, gotPets: { Types.PetInstance })
		local gave, got = {}, {}
		for _, p in gavePets do
			table.insert(gave, p.id)
		end
		for _, p in gotPets do
			table.insert(got, p.id)
		end
		table.insert(data.TradeHistory, 1, { with = other.player.UserId, at = t, gave = gave, got = got })
		while #data.TradeHistory > Config.Trade.HistoryLength do
			table.remove(data.TradeHistory)
		end
		data.Stats.Trades += 1
		DataService.markDirty(side.player, "TradeHistory")
		DataService.markDirty(side.player, "Stats")
		GameEvents.Traded:Fire(side.player)
	end
	record(a, b, dataA, fromA, fromB)
	record(b, a, dataB, fromB, fromA)
	-- Persist both sides immediately to minimise any crash window
	task.spawn(DataService.save, a.player)
	task.spawn(DataService.save, b.player)
	return true
end

function TradeService.confirm(player: Player): (boolean, string?)
	local trade = trades[player]
	if not trade or trade.state ~= "Confirming" then
		return false, "Both players must be ready first"
	end
	if now() < trade.confirmAt then
		return false, "Take a moment to review the trade"
	end
	local mine, theirs = sideOf(trade, player)
	mine.confirmed = true
	if theirs.confirmed then
		local ok, why = execute(trade)
		if ok then
			finish(trade, "Done", "Trade complete!")
		else
			unready(trade)
			table.insert(trade.log, `Trade failed: {why}`)
			push(trade)
			return false, why
		end
	else
		push(trade)
	end
	return true
end

function TradeService.cancel(player: Player): boolean
	local trade = trades[player]
	if trade then
		finish(trade, "Cancelled", `{player.DisplayName} cancelled the trade.`)
	end
	return true
end

function TradeService.init() end

function TradeService.start()
	Net.Server.handle("TradeRequest", TradeService.request)
	Net.Server.handle("TradeRespond", TradeService.respond)
	Net.Server.handle("TradeSetOffer", TradeService.setOffer)
	Net.Server.handle("TradeReady", TradeService.setReady)
	Net.Server.handle("TradeConfirm", TradeService.confirm)
	Net.Server.handle("TradeCancel", TradeService.cancel)
	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			finish(trade, "Cancelled", `{player.DisplayName} left the game.`)
		end
		requests[player] = nil
		lastRequest[player] = nil
	end)
end

return TradeService
