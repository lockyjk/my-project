--!strict
-- Optional monetization: Game Passes, Developer Products (receipts are idempotent and only
-- acknowledged after the grant is saved in the profile), and the free Gem Shop / Boss Crate.
-- Ids of 0 in GameConfig mean "coming soon" and can't be bought.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local Net = require(Modules.Net)
local Types = require(Modules.Types)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local RollService = require(script.Parent.RollService)

local ShopService = {}

local MAX_RECEIPTS = 60

local function grant(player: Player, g: { [string]: any }): string
	if g.boost then
		DataService.addBoost(player, g.boost, g.minutes)
		return `{GameConfig.Boosts[g.boost].name} activated!`
	elseif g.tokens then
		DataService.add(player, "tokens", g.tokens)
		return `+{g.tokens} Roll Tokens`
	elseif g.gems then
		DataService.add(player, "gems", g.gems)
		return `+{g.gems} Gems`
	elseif g.crate then
		local _, id = RollService.grantOfRarity(player, g.crate)
		return if id then `Boss Crate opened!` else "Crate was empty?!"
	end
	return "Purchased!"
end

local function onPassOwned(player: Player, key: string)
	local data = DataService.get(player)
	if not data or data.passes[key] then
		return
	end
	data.passes[key] = true
	DataService.push(player, "passes")
	InventoryService.publish(player)
	Net.Server.fire(
		"Notify",
		player,
		`Thanks! {GameConfig.GamePasses[key].name} unlocked`,
		Color3.fromRGB(255, 220, 80)
	)
end

local function checkPasses(player: Player, data: Types.PlayerData)
	for key, pass in GameConfig.GamePasses do
		if pass.id > 0 and not data.passes[key] then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			if ok and owns then
				onPassOwned(player, key)
			end
		end
	end
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local data = player and DataService.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried next time they join
	end
	local receipt = tostring(info.PurchaseId)
	if table.find(data.receipts, receipt) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = nil
	for _, p in GameConfig.Products do
		if p.id == info.ProductId then
			product = p
		end
	end
	if not product then
		warn(`[Shop] unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local text = grant(player, product.grant)
	table.insert(data.receipts, receipt)
	while #data.receipts > MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end
	Net.Server.fire("Notify", player, `🛒 {text}`, Color3.fromRGB(255, 220, 80))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.gemShopBuy(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Loading…"
	end
	local item = nil
	for _, it in GameConfig.GemShop do
		if it.id == id then
			item = it
		end
	end
	if not item then
		return false, "Unknown item"
	end
	if item.bossTokens then
		if data.bossTokens < item.bossTokens then
			return false, `Need {item.bossTokens} Boss Tokens (beat arena bosses!)`
		end
		DataService.spend(player, "bossTokens", item.bossTokens)
	elseif not DataService.spend(player, "gems", item.cost) then
		return false, `Need {item.cost} Gems`
	end
	return true, grant(player, item.grant)
end

function ShopService.init() end

function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in GameConfig.GamePasses do
			if pass.id == passId then
				onPassOwned(player, key)
			end
		end
	end)
	DataService.Loaded:Connect(function(player: Player, data: Types.PlayerData)
		task.spawn(checkPasses, player, data)
	end)
	Net.Server.handle("PromptPass", function(player: Player, key: string)
		local pass = GameConfig.GamePasses[key]
		if not pass or pass.id == 0 then
			return false, "Coming soon!"
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
		return true
	end)
	Net.Server.handle("PromptProduct", function(player: Player, key: string)
		local product = GameConfig.Products[key]
		if not product or product.id == 0 then
			return false, "Coming soon!"
		end
		MarketplaceService:PromptProductPurchase(player, product.id)
		return true
	end)
	Net.Server.handle("GemShopBuy", function(player: Player, id: string)
		return ShopService.gemShopBuy(player, id)
	end)
end

return ShopService
