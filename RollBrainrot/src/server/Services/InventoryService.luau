--!strict
-- Brainrot ownership: adding, removing, equipping, selling, locking and levelling.
-- A Brainrot instance is either equipped (fights), placed in a zoo habitat (earns), or idle.
-- Owning duplicates is how you do both at once.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local Signal = require(Modules.Signal)
local Types = require(Modules.Types)
local DataService = require(script.Parent.DataService)

local InventoryService = {}

-- Fired whenever equipped or zoo placement may have changed (player)
InventoryService.Changed = Signal.new() :: Signal.Signal<Player>

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function notify(player: Player, text: string, color: Color3?)
	Net.Server.fire("Notify", player, text, color)
end
InventoryService.notify = notify

function InventoryService.count(data: Types.PlayerData): number
	local n = 0
	for _ in data.inventory do
		n += 1
	end
	return n
end

function InventoryService.storageCap(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local cap = GameConfig.Inventory.BaseStorage
		+ BrainrotMath.upgradeValue(GameConfig.Upgrades.Storage, data.upgrades.Storage or 0)
	if data.passes.ExtraStorage then
		cap += 300
	end
	return math.min(cap, GameConfig.Security.MaxStorageHard)
end

function InventoryService.equipSlots(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 3
	end
	local slots = BrainrotMath.upgradeValue(GameConfig.Upgrades.EquipSlots, data.upgrades.EquipSlots or 0)
	if data.passes.ExtraSlots then
		slots += 2
	end
	return slots
end

function InventoryService.hasRoom(player: Player, extra: number?): boolean
	local data = DataService.get(player)
	return data ~= nil and InventoryService.count(data) + (extra or 1) <= InventoryService.storageCap(player)
end

-- Habitat id holding this uid, if any
function InventoryService.zooHabitatOf(data: Types.PlayerData, uid: string): string?
	for id, h in data.zoo.habitats do
		if table.find(h.slots, uid) then
			return id
		end
	end
	return nil
end

function InventoryService.isEquipped(data: Types.PlayerData, uid: string): boolean
	return table.find(data.equipped, uid) ~= nil
end

local function removeFromZoo(data: Types.PlayerData, uid: string): boolean
	for _, h in data.zoo.habitats do
		local i = table.find(h.slots, uid)
		if i then
			table.remove(h.slots, i)
			return true
		end
	end
	return false
end
InventoryService.removeFromZooData = removeFromZoo

-------------------------------------------------------------------------------
-- Team power + public "Equipped" attribute (drives followers on every client)
-------------------------------------------------------------------------------
function InventoryService.teamPower(data: Types.PlayerData): number
	local total = 0
	for _, uid in data.equipped do
		local inst = data.inventory[uid]
		if inst then
			total += BrainrotMath.instancePower(inst)
		end
	end
	return total
end

function InventoryService.publish(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local parts = {}
	for _, uid in data.equipped do
		local inst = data.inventory[uid]
		if inst then
			table.insert(parts, `{uid}:{inst.id}:{inst.mut}`)
		end
	end
	player:SetAttribute("Equipped", table.concat(parts, ","))
	player:SetAttribute("Level", data.level)
	DataService.setPower(player, InventoryService.teamPower(data))
	InventoryService.Changed:Fire(player)
end

-------------------------------------------------------------------------------
-- Adding / removing
-------------------------------------------------------------------------------
-- Adds a Brainrot. If storage is full it is auto-sold instead (returns nil uid).
function InventoryService.add(
	player: Player,
	id: string,
	mutationId: string,
	level: number?
): (string?, Types.BrainrotInstance?)
	local data = DataService.get(player)
	local def = Registry.Brainrot[id]
	if not data or not def then
		return nil, nil
	end
	local mut = if Registry.Mutation[mutationId] then mutationId else "Normal"
	local inst: Types.BrainrotInstance = { id = id, mut = mut, lvl = level or 1, t = now() }
	local firstTime = not data.index[id]
	data.index[id] = true
	data.index[id .. ":" .. mut] = true
	if InventoryService.count(data) >= InventoryService.storageCap(player) then
		local value = BrainrotMath.sellValue(def, mut, inst.lvl)
		DataService.add(player, "coins", value)
		notify(
			player,
			`Storage full! Auto-sold {Registry.displayName(id, mut)} for ${value}`,
			Color3.fromRGB(255, 190, 40)
		)
		DataService.push(player, "index")
		return nil, inst
	end
	local uid = DataService.newUid(data)
	data.inventory[uid] = inst
	DataService.pushInventory(player, uid)
	DataService.push(player, "index", "nextUid")
	if firstTime then
		notify(player, `NEW! {def.emoji} {def.name} added to your Index`, Registry.Rarity[def.rarity].color)
	end
	return uid, inst
end

function InventoryService.remove(player: Player, uid: string)
	local data = DataService.get(player)
	if not data or not data.inventory[uid] then
		return
	end
	data.inventory[uid] = nil
	local i = table.find(data.equipped, uid)
	if i then
		table.remove(data.equipped, i)
	end
	removeFromZoo(data, uid)
	DataService.pushInventory(player, uid)
	DataService.push(player, "equipped", "zoo")
	InventoryService.publish(player)
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
function InventoryService.equip(player: Player, uid: string, on: boolean): (boolean, string?)
	local data = DataService.get(player)
	if not data or not data.inventory[uid] then
		return false, "You don't own that Brainrot"
	end
	local i = table.find(data.equipped, uid)
	if not on then
		if i then
			table.remove(data.equipped, i)
		end
	else
		if i then
			return true
		end
		if #data.equipped >= InventoryService.equipSlots(player) then
			return false, "All equip slots are full! Unequip one or buy more slots."
		end
		if removeFromZoo(data, uid) then
			notify(player, "Moved from your zoo to your team")
		end
		table.insert(data.equipped, uid)
	end
	DataService.push(player, "equipped", "zoo")
	InventoryService.publish(player)
	return true
end

function InventoryService.equipBest(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local all = {}
	for uid, inst in data.inventory do
		table.insert(all, { uid = uid, power = BrainrotMath.instancePower(inst) })
	end
	table.sort(all, function(a, b)
		return a.power > b.power
	end)
	data.equipped = {}
	for i = 1, math.min(#all, InventoryService.equipSlots(player)) do
		removeFromZoo(data, all[i].uid)
		table.insert(data.equipped, all[i].uid)
	end
	DataService.push(player, "equipped", "zoo")
	InventoryService.publish(player)
	return true
end

function InventoryService.lock(player: Player, uid: string, locked: boolean): boolean
	local data = DataService.get(player)
	local inst = data and data.inventory[uid]
	if not inst then
		return false
	end
	inst.locked = if locked then true else nil
	DataService.pushInventory(player, uid)
	return true
end

function InventoryService.sell(player: Player, uids: { string }): (boolean, number)
	local data = DataService.get(player)
	if not data then
		return false, 0
	end
	local total, sold = 0, 0
	for _, uid in uids do
		local inst = data.inventory[uid]
		if inst and not inst.locked and not InventoryService.isEquipped(data, uid) then
			local def = Registry.Brainrot[inst.id]
			if def then
				total += BrainrotMath.sellValue(def, inst.mut, inst.lvl)
			end
			data.inventory[uid] = nil
			removeFromZoo(data, uid)
			Net.Server.fire("Inventory", player, "set", uid, nil)
			sold += 1
		end
	end
	if sold == 0 then
		return false, 0
	end
	DataService.add(player, "coins", total)
	DataService.push(player, "zoo")
	InventoryService.publish(player)
	return true, total
end

function InventoryService.levelUp(player: Player, uid: string): (boolean, string?)
	local data = DataService.get(player)
	local inst = data and data.inventory[uid]
	if not data or not inst then
		return false, "You don't own that Brainrot"
	end
	local def = Registry.Brainrot[inst.id]
	local coins, essence = BrainrotMath.levelUpCost(def, inst.lvl)
	if not coins or not essence then
		return false, "Already max level!"
	end
	if data.coins < coins then
		return false, "Not enough coins"
	end
	if data.essence < essence then
		return false, `Need {essence} Rot Essence (earn it in the arena)`
	end
	DataService.spend(player, "coins", coins)
	DataService.spend(player, "essence", essence)
	inst.lvl += 1
	DataService.pushInventory(player, uid)
	InventoryService.publish(player)
	return true
end

function InventoryService.init() end

function InventoryService.start()
	DataService.Loaded:Connect(function(player: Player, data: Types.PlayerData)
		-- drop references to Brainrots removed from the config, and stale uids
		for uid, inst in data.inventory do
			if not Registry.Brainrot[inst.id] then
				data.inventory[uid] = nil
			end
		end
		for i = #data.equipped, 1, -1 do
			if not data.inventory[data.equipped[i]] then
				table.remove(data.equipped, i)
			end
		end
		for _, h in data.zoo.habitats do
			for i = #h.slots, 1, -1 do
				if not data.inventory[h.slots[i]] then
					table.remove(h.slots, i)
				end
			end
		end
		-- first join: a starter Brainrot, equipped, so the arena is reachable immediately
		if data.totalRolls == 0 and next(data.inventory) == nil then
			local uid = InventoryService.add(player, GameConfig.Start.StarterBrainrot, "Normal")
			if uid then
				table.insert(data.equipped, uid)
				DataService.push(player, "equipped")
			end
		end
		InventoryService.publish(player)
	end)

	Net.Server.handle("Equip", function(player: Player, uid: string, on: boolean)
		return InventoryService.equip(player, uid, on)
	end)
	Net.Server.handle("EquipBest", function(player: Player)
		return InventoryService.equipBest(player)
	end)
	Net.Server.handle("LockBrainrot", function(player: Player, uid: string, locked: boolean)
		return InventoryService.lock(player, uid, locked)
	end)
	Net.Server.handle("SellBrainrots", function(player: Player, uids: { string })
		return InventoryService.sell(player, uids)
	end)
	Net.Server.handle("LevelUpBrainrot", function(player: Player, uid: string)
		return InventoryService.levelUp(player, uid)
	end)
end

return InventoryService
