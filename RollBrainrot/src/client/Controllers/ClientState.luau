--!strict
-- The client's read-only copy of its own save data (pushed by DataService) plus a few
-- derived helpers. Everything important is decided by the server; this only drives UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Net = require(Modules:WaitForChild("Net"))
local Signal = require(Modules:WaitForChild("Signal"))
local Types = require(Modules:WaitForChild("Types"))

local ClientState = {}

ClientState.data = {} :: { [string]: any }
ClientState.inventory = {} :: { [string]: Types.BrainrotInstance }
ClientState.loaded = false

-- Changed(key) fires for each top-level key that changed; "inventory" for collection edits
ClientState.Changed = Signal.new() :: Signal.Signal<string>
ClientState.Loaded = Signal.new() :: Signal.Signal<>
-- Inventory(uid, item?) for single edits, ("*") for a full refresh
ClientState.InventoryChanged = Signal.new() :: Signal.Signal<string, Types.BrainrotInstance?>

local player = Players.LocalPlayer

function ClientState.get(key: string): any
	return ClientState.data[key]
end

function ClientState.equippedSlots(): number
	local d = ClientState.data
	local slots = BrainrotMath.upgradeValue(GameConfig.Upgrades.EquipSlots, d.upgrades and d.upgrades.EquipSlots or 0)
	if d.passes and d.passes.ExtraSlots then
		slots += 2
	end
	return slots
end

function ClientState.storageCap(): number
	local d = ClientState.data
	local cap = GameConfig.Inventory.BaseStorage + BrainrotMath.upgradeValue(GameConfig.Upgrades.Storage, d.upgrades and d.upgrades.Storage or 0)
	if d.passes and d.passes.ExtraStorage then
		cap += 300
	end
	return cap
end

function ClientState.inventoryCount(): number
	local n = 0
	for _ in ClientState.inventory do
		n += 1
	end
	return n
end

function ClientState.isEquipped(uid: string): boolean
	local eq = ClientState.data.equipped
	return eq ~= nil and table.find(eq, uid) ~= nil
end

function ClientState.zooHabitatOf(uid: string): string?
	local zoo = ClientState.data.zoo
	if not zoo then
		return nil
	end
	for id, h in zoo.habitats do
		if table.find(h.slots, uid) then
			return id
		end
	end
	return nil
end

function ClientState.boostLeft(id: string): number
	local b = ClientState.data.boosts
	local t = b and b[id]
	if not t then
		return 0
	end
	return math.max(0, t - DateTime.now().UnixTimestamp)
end

function ClientState.luck(): number
	return (player:GetAttribute("Luck") :: number?) or 1
end

function ClientState.hasPass(id: string): boolean
	local p = ClientState.data.passes
	return p ~= nil and p[id] == true
end

function ClientState.teamPower(): number
	local total = 0
	for _, uid in ClientState.data.equipped or {} do
		local inst = ClientState.inventory[uid]
		if inst then
			total += BrainrotMath.instancePower(inst)
		end
	end
	return total
end

function ClientState.serverNow(): number
	return Workspace:GetServerTimeNow()
end

function ClientState.start()
	Net.Client.on("State", function(patch: { [string]: any })
		for k, v in patch do
			ClientState.data[k] = v
		end
		local first = not ClientState.loaded and patch.coins ~= nil
		if first then
			ClientState.loaded = true
		end
		for k in patch do
			ClientState.Changed:Fire(k)
		end
		if first then
			ClientState.Loaded:Fire()
		end
	end)
	Net.Client.on("Inventory", function(op: string, a: any, b: any)
		if op == "full" then
			ClientState.inventory = a or {}
			ClientState.InventoryChanged:Fire("*", nil)
		elseif op == "set" then
			ClientState.inventory[a] = b
			ClientState.InventoryChanged:Fire(a, b)
		end
		ClientState.Changed:Fire("inventory")
	end)
end

-- Yields until the first state push arrived
function ClientState.waitLoaded()
	if not ClientState.loaded then
		ClientState.Loaded:Wait()
	end
end

return ClientState
