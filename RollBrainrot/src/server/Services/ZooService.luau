--!strict
-- Personal zoos: plot assignment, habitats (unlock/upgrade/slots), placing Brainrots,
-- passive income into a "bank" you collect at your plot, decorations and offline earnings.
--
-- What each zoo contains is replicated through ReplicatedStorage.ZooState.Plot<i>
-- (attributes, never streamed out) so every client can render every zoo's creatures.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotMath = require(Modules.BrainrotMath)
local Format = require(Modules.Format)
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Registry = require(Modules.Registry)
local Types = require(Modules.Types)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local Props = require(script.Parent.Parent.World.Props)
local ZooPlotBuilder = require(script.Parent.Parent.World.ZooPlotBuilder)

local ZooService = {}

local plotOwner: { [number]: Player } = {}
local playerPlot: { [Player]: number } = {}
local stateFolder: Folder
local incomeCache: { [Player]: number } = {} -- coins per minute (incl. multipliers, excl. coin boost)

local function notify(player: Player, text: string, color: Color3?)
	Net.Server.fire("Notify", player, text, color)
end

local function plotModel(index: number): Model?
	local world = Workspace:FindFirstChild("World")
	local zoos = world and world:FindFirstChild("Zoos")
	return zoos and zoos:FindFirstChild(`Plot{index}`) :: Model?
end

function ZooService.plotOf(player: Player): number?
	return playerPlot[player]
end

-------------------------------------------------------------------------------
-- Income
-------------------------------------------------------------------------------
function ZooService.decorBonus(data: Types.PlayerData): number
	local bonus = 0
	for _, id in data.zoo.decorations do
		local d = Registry.Decoration[id]
		if d then
			bonus += d.incomeBonus
		end
	end
	return bonus
end

-- Coins per minute from the whole zoo (before the temporary Coin Boost)
function ZooService.incomePerMinute(data: Types.PlayerData): number
	local total = 0
	for id, h in data.zoo.habitats do
		local def = Registry.Habitat[id]
		if def and h.unlocked then
			for _, uid in h.slots do
				local inst = data.inventory[uid]
				if inst then
					total += BrainrotMath.placedIncome(inst, def, h.level)
				end
			end
		end
	end
	local upgrade = BrainrotMath.upgradeValue(GameConfig.Upgrades.ZooIncome, data.upgrades.ZooIncome or 0)
	local vip = if data.passes.VIP then GameConfig.Vip.CoinMult else 1
	return total * upgrade * (1 + ZooService.decorBonus(data)) * vip
end

-------------------------------------------------------------------------------
-- Replication + plot visuals
-------------------------------------------------------------------------------
local function publish(player: Player)
	local index = playerPlot[player]
	local data = DataService.get(player)
	if not index or not data then
		return
	end
	local contents = {}
	local habitats = {}
	for id, h in data.zoo.habitats do
		habitats[id] = { u = h.unlocked, l = h.level }
		for _, uid in h.slots do
			local inst = data.inventory[uid]
			if inst then
				table.insert(contents, { h = id, id = inst.id, mut = inst.mut, uid = uid })
			end
		end
	end
	local cfg = stateFolder:FindFirstChild(`Plot{index}`) :: Configuration
	cfg:SetAttribute("Contents", HttpService:JSONEncode(contents))
	cfg:SetAttribute("Habitats", HttpService:JSONEncode(habitats))
	local income = ZooService.incomePerMinute(data)
	incomeCache[player] = income
	cfg:SetAttribute("IncomePerMin", income)
	player:SetAttribute("ZooIncome", income)
	-- locked / unlocked pens
	local model = plotModel(index)
	local folder = model and model:FindFirstChild("Habitats")
	if folder then
		for _, def in GameConfig.Habitats do
			local pen = folder:FindFirstChild(def.id)
			if pen then
				local unlocked = data.zoo.habitats[def.id] and data.zoo.habitats[def.id].unlocked
				local field = pen:FindFirstChild("LockField") :: BasePart?
				local sign = pen:FindFirstChild("LockSign") :: BasePart?
				if field then
					field.Transparency = if unlocked then 1 else 0.2
					field.CanCollide = not unlocked
					local prompt = field:FindFirstChild("UnlockPrompt") :: ProximityPrompt?
					if prompt then
						prompt.Enabled = not unlocked
					end
				end
				if sign then
					local gui = sign:FindFirstChildWhichIsA("BillboardGui")
					if gui then
						gui.Enabled = not unlocked
						local label = gui:FindFirstChild("LockLabel") :: TextLabel?
						if label and not unlocked then
							local need = if def.requiresArena then `\nBeat {Registry.Arena[def.requiresArena].name}` else ""
							label.Text = `🔒 {def.name}\n${Format.short(def.cost)}{need}`
						end
					end
				end
			end
		end
	end
	DataService.push(player, "zoo")
end
ZooService.publish = publish

local function rebuildDecorations(index: number, data: Types.PlayerData?)
	local model = plotModel(index)
	local folder = model and model:FindFirstChild("Decorations")
	if not folder then
		return
	end
	folder:ClearAllChildren()
	if not data then
		return
	end
	local plotCf = ZooPlotBuilder.plotCFrame(index)
	for _, id in data.zoo.decorations do
		local def = Registry.Decoration[id]
		local spot = def and ZooPlotBuilder.DecorSpots[def.order]
		if def and spot then
			Props.decoration(def.builder, folder, plotCf * CFrame.new(spot))
		end
	end
end

local function setOwnerSign(index: number, player: Player?)
	local model = plotModel(index)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d.Name == "OwnerLabel" and d:IsA("TextLabel") then
			d.Text = if player then `{player.DisplayName}'s Zoo` else "EMPTY ZOO"
		end
	end
end

local function resetPlot(index: number)
	local cfg = stateFolder:FindFirstChild(`Plot{index}`) :: Configuration
	cfg:SetAttribute("OwnerId", 0)
	cfg:SetAttribute("OwnerName", "")
	cfg:SetAttribute("Contents", "[]")
	cfg:SetAttribute("Habitats", "{}")
	cfg:SetAttribute("IncomePerMin", 0)
	setOwnerSign(index, nil)
	rebuildDecorations(index, nil)
	local model = plotModel(index)
	local folder = model and model:FindFirstChild("Habitats")
	if folder then
		for _, pen in folder:GetChildren() do
			local field = pen:FindFirstChild("LockField") :: BasePart?
			if field then
				field.Transparency = 0.2
				field.CanCollide = false -- empty plots are walkable
			end
		end
	end
	local bank = model and model:FindFirstChild("BankAnchor")
	local label = bank and bank:FindFirstChild("Billboard") and (bank :: any).Billboard:FindFirstChild("BankLabel")
	if label then
		label.Text = ""
	end
end

local function updateBankLabel(player: Player, data: Types.PlayerData)
	local index = playerPlot[player]
	local model = index and plotModel(index)
	local anchor = model and model:FindFirstChild("BankAnchor")
	local gui = anchor and anchor:FindFirstChild("Billboard")
	local label = gui and gui:FindFirstChild("BankLabel") :: TextLabel?
	if label then
		label.Text = `💰 ${Format.short(math.floor(data.zoo.bank))}\n+${Format.short(incomeCache[player] or 0)}/min`
	end
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
local function freeSlots(data: Types.PlayerData, habitatId: string): number
	local h = data.zoo.habitats[habitatId]
	local def = Registry.Habitat[habitatId]
	if not h or not def or not h.unlocked then
		return 0
	end
	return BrainrotMath.habitatSlots(def, h.level) - #h.slots
end

-- Best habitat for a Brainrot: its favourite if there is room, else the best-paying open one
local function bestHabitatFor(data: Types.PlayerData, inst: Types.BrainrotInstance): string?
	local def = Registry.Brainrot[inst.id]
	if def and freeSlots(data, def.habitat) > 0 then
		return def.habitat
	end
	local best, bestMult = nil, -1
	for _, h in GameConfig.Habitats do
		if freeSlots(data, h.id) > 0 then
			local m = BrainrotMath.habitatIncomeMult(h, data.zoo.habitats[h.id].level)
			if m > bestMult then
				best, bestMult = h.id, m
			end
		end
	end
	return best
end

function ZooService.sendToZoo(player: Player, uid: string, habitatId: string?): (boolean, string?)
	local data = DataService.get(player)
	local inst = data and data.inventory[uid]
	if not data or not inst then
		return false, "You don't own that Brainrot"
	end
	if InventoryService.zooHabitatOf(data, uid) then
		return false, "Already in your zoo"
	end
	local target = habitatId or bestHabitatFor(data, inst)
	if not target or not Registry.Habitat[target] then
		return false, "Your zoo is full! Unlock or upgrade a habitat."
	end
	if freeSlots(data, target) <= 0 then
		return false, "That habitat is full"
	end
	local i = table.find(data.equipped, uid)
	if i then
		table.remove(data.equipped, i)
		DataService.push(player, "equipped")
	end
	table.insert(data.zoo.habitats[target].slots, uid)
	InventoryService.publish(player)
	publish(player)
	return true, target
end

function ZooService.removeFromZoo(player: Player, uid: string): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local ok = InventoryService.removeFromZooData(data, uid)
	if ok then
		publish(player)
	end
	return ok
end

function ZooService.fillZoo(player: Player): (boolean, number)
	local data = DataService.get(player)
	if not data then
		return false, 0
	end
	local idle = {}
	for uid, inst in data.inventory do
		if not InventoryService.isEquipped(data, uid) and not InventoryService.zooHabitatOf(data, uid) then
			local def = Registry.Brainrot[inst.id]
			table.insert(idle, { uid = uid, inst = inst, income = BrainrotMath.baseIncome(def, inst.mut, inst.lvl) })
		end
	end
	table.sort(idle, function(a, b)
		return a.income > b.income
	end)
	local placed = 0
	for _, entry in idle do
		local target = bestHabitatFor(data, entry.inst)
		if not target then
			break
		end
		table.insert(data.zoo.habitats[target].slots, entry.uid)
		placed += 1
	end
	-- swap weaker zoo residents out for stronger idle ones is left to the player
	publish(player)
	return true, placed
end

function ZooService.unlockHabitat(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	local def = Registry.Habitat[id]
	if not data or not def then
		return false, "Unknown habitat"
	end
	local h = data.zoo.habitats[id]
	if h and h.unlocked then
		return false, "Already unlocked"
	end
	if def.requiresArena and not data.arena.beaten[def.requiresArena] then
		return false, `Defeat the {Registry.Arena[def.requiresArena].name} boss first!`
	end
	if not DataService.spend(player, "coins", def.cost) then
		return false, `Need ${Format.short(def.cost)}`
	end
	data.zoo.habitats[id] = { unlocked = true, level = 1, slots = if h then h.slots else {} }
	publish(player)
	notify(player, `{def.emoji} {def.name} unlocked!`, Color3.fromRGB(120, 255, 120))
	return true
end

function ZooService.upgradeHabitat(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	local def = Registry.Habitat[id]
	local h = data and data.zoo.habitats[id]
	if not data or not def or not h or not h.unlocked then
		return false, "Unlock it first"
	end
	local cost = BrainrotMath.habitatUpgradeCost(def, h.level)
	if not cost then
		return false, "Max level!"
	end
	if not DataService.spend(player, "coins", cost) then
		return false, `Need ${Format.short(cost)}`
	end
	h.level += 1
	publish(player)
	return true
end

function ZooService.collect(player: Player): (boolean, number)
	local data = DataService.get(player)
	if not data then
		return false, 0
	end
	local amount = math.floor(data.zoo.bank)
	if amount <= 0 then
		return false, 0
	end
	data.zoo.bank -= amount
	DataService.add(player, "coins", amount)
	DataService.push(player, "zoo")
	updateBankLabel(player, data)
	Net.Server.fire("Notify", player, `+${Format.short(amount)} collected from your zoo!`, Color3.fromRGB(255, 220, 80))
	return true, amount
end

function ZooService.buyDecoration(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	local def = Registry.Decoration[id]
	if not data or not def then
		return false, "Unknown decoration"
	end
	if table.find(data.zoo.decorations, id) then
		return false, "Already owned"
	end
	if def.vip and not data.passes.VIP then
		return false, "VIP only"
	end
	if def.cost > 0 and not DataService.spend(player, def.currency, def.cost) then
		return false, `Not enough {def.currency}`
	end
	table.insert(data.zoo.decorations, id)
	local index = playerPlot[player]
	if index then
		rebuildDecorations(index, data)
	end
	publish(player)
	return true
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
local function assignPlot(player: Player, data: Types.PlayerData)
	for i in GameConfig.World.Plots do
		if not plotOwner[i] then
			plotOwner[i] = player
			playerPlot[player] = i
			player:SetAttribute("Plot", i)
			local cfg = stateFolder:FindFirstChild(`Plot{i}`) :: Configuration
			cfg:SetAttribute("OwnerId", player.UserId)
			cfg:SetAttribute("OwnerName", player.DisplayName)
			setOwnerSign(i, player)
			rebuildDecorations(i, data)
			return
		end
	end
	warn(`[Zoo] no free plot for {player.Name}`)
end

local function onLoaded(player: Player, data: Types.PlayerData, away: number)
	assignPlot(player, data)
	publish(player)
	-- offline earnings
	local Z = GameConfig.Zoo
	if away >= Z.OfflineMinSeconds then
		local seconds = math.min(away, Z.OfflineCapHours * 3600)
		local earned = math.floor(ZooService.incomePerMinute(data) * seconds / 60 * Z.OfflineRate)
		if earned > 0 then
			DataService.add(player, "coins", earned)
			task.delay(2, function()
				if player.Parent then
					Net.Server.fire("WelcomeBack", player, earned, away)
				end
			end)
		end
	end
end

function ZooService.init()
	stateFolder = Instance.new("Folder")
	stateFolder.Name = "ZooState"
	for i in GameConfig.World.Plots do
		local cfg = Instance.new("Configuration")
		cfg.Name = `Plot{i}`
		cfg.Parent = stateFolder
	end
	stateFolder.Parent = ReplicatedStorage
	for i in GameConfig.World.Plots do
		resetPlot(i)
	end
end

function ZooService.start()
	DataService.Loaded:Connect(onLoaded)
	InventoryService.Changed:Connect(publish)
	Players.PlayerRemoving:Connect(function(player)
		local index = playerPlot[player]
		if index then
			plotOwner[index] = nil
			resetPlot(index)
		end
		playerPlot[player] = nil
		incomeCache[player] = nil
	end)

	-- collector prompts (server side, owner only)
	for i in GameConfig.World.Plots do
		local model = plotModel(i)
		local pad = model and model:FindFirstChild("Collector")
		local prompt = pad and pad:FindFirstChild("CollectPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Triggered:Connect(function(player)
				if plotOwner[i] == player then
					ZooService.collect(player)
				else
					notify(player, "That's not your zoo!")
				end
			end)
		end
	end

	-- income accrual
	task.spawn(function()
		local dt = GameConfig.Zoo.TickSeconds
		while true do
			task.wait(dt)
			for player in playerPlot do
				local data = DataService.get(player)
				if data then
					local perMin = incomeCache[player] or ZooService.incomePerMinute(data)
					local boost = if DataService.boostActive(data, "Coins") then GameConfig.Boosts.Coins.mult else 1
					data.zoo.bank += perMin * dt / 60 * boost
					updateBankLabel(player, data)
				end
			end
		end
	end)
	-- refresh the client's view of the bank now and then (not every tick)
	task.spawn(function()
		while true do
			task.wait(15)
			for player in playerPlot do
				DataService.push(player, "zoo")
			end
		end
	end)

	Net.Server.handle("SendToZoo", function(player: Player, uid: string, habitatId: string?)
		return ZooService.sendToZoo(player, uid, habitatId)
	end)
	Net.Server.handle("RemoveFromZoo", function(player: Player, uid: string)
		return ZooService.removeFromZoo(player, uid)
	end)
	Net.Server.handle("FillZoo", function(player: Player)
		return ZooService.fillZoo(player)
	end)
	Net.Server.handle("UnlockHabitat", function(player: Player, id: string)
		return ZooService.unlockHabitat(player, id)
	end)
	Net.Server.handle("UpgradeHabitat", function(player: Player, id: string)
		return ZooService.upgradeHabitat(player, id)
	end)
	Net.Server.handle("CollectZoo", function(player: Player)
		return ZooService.collect(player)
	end)
	Net.Server.handle("BuyDecoration", function(player: Player, id: string)
		return ZooService.buyDecoration(player, id)
	end)
end

return ZooService
