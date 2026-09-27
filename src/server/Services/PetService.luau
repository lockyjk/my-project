--!strict
-- Stormlings: eggs, hatching (odds + luck), inventory, equip, lock/delete, fusion jobs,
-- rare catch drops, index discovery and server-wide rare announcements.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local EconomyMath = require(Shared.EconomyMath)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.WorldLayout)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local WeatherEventService = require(script.Parent.WeatherEventService)
local ZoneService = require(script.Parent.ZoneService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local PetService = {}

local rng = Random.new()
local MAX_TIER = #Config.Fusion.Tiers

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function newUid(data: Types.ProfileData): string
	for _ = 1, 10 do
		local uid = string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 12)
		if not data.Pets[uid] then
			return uid
		end
	end
	return HttpService:GenerateGUID(false)
end

function PetService.count(data: Types.ProfileData): number
	local n = 0
	for _ in data.Pets do
		n += 1
	end
	return n
end

-- Replicate equipped pets to every client (for follower rendering) via a player attribute
function PetService.replicateEquipped(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local list: { { any } } = {}
	for _, uid in data.Equipped do
		local pet = data.Pets[uid]
		if pet then
			table.insert(list, { pet.id, pet.tier } :: { any })
		end
	end
	player:SetAttribute("Pets", HttpService:JSONEncode(list))
end

local function discover(player: Player, data: Types.ProfileData, petId: string)
	if not data.Index[petId] then
		data.Index[petId] = true
		data.Stats.IndexCount = (data.Stats.IndexCount or 0) + 1
		DataService.markDirty(player, "Index")
	end
end

-- Adds a pet. Egg hatches respect MaxPets (checked by the caller); rewards and purchases
-- always succeed so nothing paid-for can be lost.
function PetService.givePet(player: Player, petId: string, source: string, tier: number?, robux: boolean?): Types.PetInstance?
	local data = DataService.get(player)
	if not data or not Defs.Pet[petId] then
		return nil
	end
	local pet: Types.PetInstance = {
		uid = newUid(data),
		id = petId,
		tier = math.clamp(tier or 1, 1, MAX_TIER),
		source = if robux then "RobuxEgg" else source,
		obtained = now(),
	}
	data.Pets[pet.uid] = pet
	discover(player, data, petId)
	local score = EconomyMath.petScore(petId, pet.tier)
	if score > (data.Stats.BestPetScore or 0) then
		data.Stats.BestPetScore = score
		data.BestPet = petId
		data.BestPetTier = pet.tier
		DataService.markDirty(player, "BestPet")
	end
	DataService.markDirty(player, "Pets")
	DataService.markDirty(player, "Stats")
	GameEvents.PetObtained:Fire(player, pet, source)

	local def = Defs.Pet[petId]
	local rarity = Defs.Rarity[def.rarity]
	if rarity and rarity.announce then
		local tierName = if pet.tier > 1 then Config.Fusion.Tiers[pet.tier].name .. " " else ""
		Net.Server.fireAll("Announce", `{player.DisplayName} got a {rarity.name} {tierName}{def.name}!`, def.rarity)
	end
	return pet
end

local function eggAvailable(egg: Types.EggDef): (boolean, string?)
	if egg.storm then
		local storm = WeatherEventService.current().storm
		if not storm or (egg.storm ~= "*" and egg.storm ~= storm.id) then
			return false, "This egg only opens during a storm!"
		end
	end
	if egg.event and not WeatherEventService.isEventActive(egg.event) then
		return false, "This event egg isn't available right now"
	end
	return true
end

export type HatchResult = { pet: string, uid: string?, deleted: boolean, rarity: string }

local function roll(player: Player, data: Types.ProfileData, egg: Types.EggDef, count: number, source: string, robux: boolean?): { HatchResult }
	local derived = StatsService.get(player)
	local luck = if derived then derived.EggLuck else 1
	local odds = EconomyMath.eggOdds(egg, luck)
	local results: { HatchResult } = {}
	for _ = 1, count do
		local petId = EconomyMath.pickFromOdds(odds, rng:NextNumber())
		local def = Defs.Pet[petId]
		local autoDelete = data.Settings.AutoDelete[def.rarity] == true and Defs.rarityOrder(def.rarity) <= 4 and not robux
		if autoDelete then
			discover(player, data, petId)
			table.insert(results, { pet = petId, uid = nil, deleted = true, rarity = def.rarity })
		else
			local pet = PetService.givePet(player, petId, source, 1, robux)
			table.insert(results, { pet = petId, uid = if pet then pet.uid else nil, deleted = false, rarity = def.rarity })
		end
	end
	data.Stats.Hatched += count
	DataService.markDirty(player, "Stats")
	GameEvents.Hatched:Fire(player, egg.id, count)
	return results
end

function PetService.hatch(player: Player, eggId: string, count: number): (boolean, any)
	local data = DataService.get(player)
	local egg = Defs.Egg[eggId]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not egg or not hrp then
		return false, "Not ready"
	end
	if egg.currency ~= "Charge" then
		return false, "This egg can't be bought with Charge"
	end
	local ok, why = eggAvailable(egg)
	if not ok then
		return false, why
	end
	if count == 3 and data.Ascensions < Config.Hatch.TripleHatchAscensions then
		return false, "Triple hatch unlocks after your first Ascension"
	end
	local standPos = WorldLayout.eggPosition(eggId)
	if not standPos or (hrp.Position - standPos).Magnitude > Config.Hatch.StandRadius + Config.Security.CatchRangeTolerance then
		return false, "Get closer to the egg"
	end
	if egg.zone and not ZoneService.canAccess(player, egg.zone) then
		return false, "Unlock this zone first"
	end
	if PetService.count(data) + count > Config.Economy.MaxPets then
		return false, "Your pet inventory is full! Delete or fuse some Stormlings."
	end
	local derived = StatsService.get(player)
	local price = EconomyMath.eggCost(egg, if derived then derived.EggDiscount else 0) * count
	if not CurrencyService.spend(player, price, "Egg", eggId) then
		return false, "Not enough Charge"
	end
	return true, roll(player, data, egg, count, "Egg")
end

-- Free hatch from rewards (streak egg) or Robux receipts. No cost / distance / availability checks.
function PetService.hatchFree(player: Player, eggId: string, count: number, source: string, robux: boolean?): { HatchResult }
	local data = DataService.get(player)
	local egg = Defs.Egg[eggId]
	if not data or not egg then
		return {}
	end
	local results = roll(player, data, egg, count, source, robux)
	-- Free hatches play the reveal on the client even when not triggered by a remote call
	Net.Server.fire("Reward", player, "Hatch", { egg = eggId, results = results })
	return results
end

-------------------------------------------------------------------------------
-- Inventory management
-------------------------------------------------------------------------------

function PetService.equip(player: Player, uid: string, equip: boolean): (boolean, string?)
	local data = DataService.get(player)
	local derived = StatsService.get(player)
	if not data or not derived or not data.Pets[uid] then
		return false, "Unknown pet"
	end
	local index = table.find(data.Equipped, uid)
	if equip then
		if index then
			return true
		end
		if #data.Equipped >= derived.Slots then
			return false, `You can equip {derived.Slots} Stormlings`
		end
		table.insert(data.Equipped, uid)
	elseif index then
		table.remove(data.Equipped, index)
	end
	DataService.markDirty(player, "Equipped")
	StatsService.refresh(player)
	PetService.replicateEquipped(player)
	return true
end

function PetService.equipBest(player: Player): boolean
	local data = DataService.get(player)
	local derived = StatsService.get(player)
	if not data or not derived then
		return false
	end
	local list = {}
	for uid, pet in data.Pets do
		table.insert(list, { uid = uid, power = EconomyMath.petPower(pet.id, pet.tier) })
	end
	table.sort(list, function(a, b)
		return a.power > b.power
	end)
	data.Equipped = {}
	for i = 1, math.min(derived.Slots, #list) do
		table.insert(data.Equipped, list[i].uid)
	end
	DataService.markDirty(player, "Equipped")
	StatsService.refresh(player)
	PetService.replicateEquipped(player)
	return true
end

-- Removes pets from inventory (and from equipped). Used by delete, fusion and trades.
function PetService.removePets(player: Player, uids: { string })
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, uid in uids do
		data.Pets[uid] = nil
		local i = table.find(data.Equipped, uid)
		if i then
			table.remove(data.Equipped, i)
		end
	end
	DataService.markDirty(player, "Pets")
	DataService.markDirty(player, "Equipped")
	StatsService.refresh(player)
	PetService.replicateEquipped(player)
end

function PetService.lock(player: Player, uid: string, locked: boolean): boolean
	local data = DataService.get(player)
	local pet = data and data.Pets[uid]
	if not data or not pet then
		return false
	end
	pet.locked = if locked then true else nil
	DataService.markDirty(player, "Pets")
	return true
end

function PetService.delete(player: Player, uids: { string }): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	local valid = {}
	for _, uid in uids do
		local pet = data.Pets[uid]
		if pet and not pet.locked then
			table.insert(valid, uid)
		end
	end
	if #valid == 0 then
		return false, "Nothing to delete (locked pets are safe)"
	end
	PetService.removePets(player, valid)
	return true
end

-------------------------------------------------------------------------------
-- Fusion
-------------------------------------------------------------------------------

function PetService.startFusion(player: Player, petId: string, tier: number): (boolean, string?)
	local data = DataService.get(player)
	local derived = StatsService.get(player)
	if not data or not derived or not Defs.Pet[petId] then
		return false, "Unknown pet"
	end
	if tier >= MAX_TIER then
		return false, "Already at the highest tier"
	end
	if #data.Fusions >= derived.FusionJobs then
		return false, "Your fusion altar is busy"
	end
	-- Prefer unequipped pets; never use locked ones
	local candidates = {}
	for uid, pet in data.Pets do
		if pet.id == petId and pet.tier == tier and not pet.locked then
			table.insert(candidates, { uid = uid, equipped = table.find(data.Equipped, uid) ~= nil, robux = pet.source == "RobuxEgg" })
		end
	end
	if #candidates < Config.Fusion.Required then
		return false, `Need {Config.Fusion.Required} unlocked copies of the same Stormling and tier`
	end
	table.sort(candidates, function(a, b)
		return (if a.equipped then 1 else 0) < (if b.equipped then 1 else 0)
	end)
	local used = {}
	local robux = false
	for i = 1, Config.Fusion.Required do
		table.insert(used, candidates[i].uid)
		robux = robux or candidates[i].robux
	end
	PetService.removePets(player, used)
	local seconds = Config.Fusion.Tiers[tier + 1].seconds
	table.insert(data.Fusions, {
		uid = newUid(data),
		id = petId,
		tier = tier + 1,
		startAt = now(),
		endAt = now() + seconds,
		robuxSourced = if robux then true else nil,
	})
	data.Stats.Fused += 1
	DataService.markDirty(player, "Fusions")
	DataService.markDirty(player, "Stats")
	GameEvents.FusionStarted:Fire(player, petId, tier + 1)
	return true
end

function PetService.claimFusion(player: Player, uid: string): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false
	end
	for i, job in data.Fusions do
		if job.uid == uid then
			if job.endAt > now() then
				return false, "Still fusing"
			end
			table.remove(data.Fusions, i)
			DataService.markDirty(player, "Fusions")
			PetService.givePet(player, job.id, "Fusion", job.tier, job.robuxSourced)
			return true
		end
	end
	return false, "Unknown fusion"
end

function PetService.useFusionSkip(player: Player, uid: string): (boolean, string?)
	local data = DataService.get(player)
	if not data or data.FusionSkips <= 0 then
		return false, "No fusion skips"
	end
	for _, job in data.Fusions do
		if job.uid == uid and job.endAt > now() then
			data.FusionSkips -= 1
			job.endAt = now()
			DataService.markDirty(player, "Fusions")
			DataService.markDirty(player, "FusionSkips")
			return true
		end
	end
	return false, "Nothing to skip"
end

-- Instant Fusion product: finish the oldest running job, or bank a skip if none is running
function PetService.instantFusion(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local oldest: Types.FusionJob? = nil
	for _, job in data.Fusions do
		if job.endAt > now() and (oldest == nil or job.startAt < oldest.startAt) then
			oldest = job
		end
	end
	if oldest then
		oldest.endAt = now()
		DataService.markDirty(player, "Fusions")
	else
		data.FusionSkips += 1
		DataService.markDirty(player, "FusionSkips")
	end
end

-------------------------------------------------------------------------------

function PetService.init() end

function PetService.start()
	ZoneService.onPetDrop = function(player: Player, petId: string)
		local pet = PetService.givePet(player, petId, "Catch")
		if pet then
			Net.Server.fire("PetDrop", player, pet)
		end
	end

	Net.Server.handle("HatchEgg", PetService.hatch)
	Net.Server.handle("EquipPet", PetService.equip)
	Net.Server.handle("EquipBest", PetService.equipBest)
	Net.Server.handle("LockPet", PetService.lock)
	Net.Server.handle("DeletePets", PetService.delete)
	Net.Server.handle("StartFusion", PetService.startFusion)
	Net.Server.handle("ClaimFusion", PetService.claimFusion)
	Net.Server.handle("UseFusionSkip", PetService.useFusionSkip)

	DataService.Loaded:Connect(function(player)
		-- Drop equipped uids that no longer exist (e.g. traded away in a crash window)
		local data = DataService.get(player)
		if data then
			local clean = {}
			for _, uid in data.Equipped do
				if data.Pets[uid] then
					table.insert(clean, uid)
				end
			end
			data.Equipped = clean
		end
		PetService.replicateEquipped(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("Pets", nil)
	end)
end

return PetService
