--!strict
-- Monetization: Game Passes, Developer Products, idempotent ProcessReceipt, PolicyService
-- rules for paid random items and trading, the one-time Starter Pack and VIP perks.
--
-- Receipt safety:
--   * a PurchaseId already recorded in the profile returns PurchaseGranted without granting
--   * otherwise grant -> record the PurchaseId -> force a save; only a successful save returns
--     PurchaseGranted, otherwise NotProcessedYet so Roblox retries (in-session the recorded id
--     prevents a second grant; if the server dies before saving, the grant is lost with it and
--     the retry grants it again on the next server).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Schedule = require(Shared.Schedule)
local Types = require(Shared.Types)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)
local RewardService = require(script.Parent.RewardService)
local StatsService = require(script.Parent.StatsService)
local StormPassService = require(script.Parent.StormPassService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local ShopService = {}

local MAX_RECEIPTS = 200

local function pushPasses(player: Player)
	local session = DataService.session(player)
	if session then
		DataService.pushSession(player, "Passes", session.Passes)
		player:SetAttribute("VIP", session.Passes.VIP == true)
	end
end

local function checkPasses(player: Player)
	local session = DataService.session(player)
	if not session then
		return
	end
	for _, pass in Config.GamePasses do
		if pass.id ~= 0 and not session.Passes[pass.key] then
			for _ = 1, 3 do
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
				end)
				if ok then
					session.Passes[pass.key] = owns == true
					break
				end
				task.wait(1)
			end
		end
	end
	pushPasses(player)
	StatsService.refresh(player)
end

function ShopService.hasPass(player: Player, key: string): boolean
	local session = DataService.session(player)
	return session ~= nil and session.Passes[key] == true
end

-- Studio / admin testing helper
function ShopService.setPass(player: Player, key: string, owned: boolean)
	local session = DataService.session(player)
	if session and Defs.Pass[key] then
		session.Passes[key] = owned
		pushPasses(player)
		StatsService.refresh(player)
	end
end

local function fetchPolicy(player: Player)
	local session = DataService.session(player)
	if not session then
		return
	end
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and info then
		session.Policy = {
			PaidRandomItemsRestricted = info.ArePaidRandomItemsRestricted == true,
			PaidItemTradingAllowed = info.IsPaidItemTradingAllowed == true,
		}
	end
	-- on failure the safe defaults (restricted, no paid-item trading) stay in place
	DataService.pushSession(player, "Policy", session.Policy)
end

-------------------------------------------------------------------------------
-- Prompts (server decides what may be sold)
-------------------------------------------------------------------------------

function ShopService.canBuy(player: Player, product: Types.ProductDef): (boolean, string?)
	local data = DataService.get(player)
	local session = DataService.session(player)
	if not data or not session then
		return false, "Not ready"
	end
	if product.id == 0 then
		return false, "This item isn't on sale yet"
	end
	if product.kind == "Egg" and session.Policy.PaidRandomItemsRestricted then
		return false, "Paid eggs aren't available in your region"
	end
	if product.kind == "StarterPack" and data.Purchases.StarterPack then
		return false, "You already own the Starter Pack"
	end
	if product.kind == "PassPremium" then
		local index = Schedule.passSeason(DateTime.now().UnixTimestamp)
		if index == 0 then
			return false, "The Storm Pass season hasn't started"
		end
		if data.Pass.Premium then
			return false, "You already have Premium this season"
		end
	end
	if product.kind == "PassSkip" and (Schedule.passSeason(DateTime.now().UnixTimestamp)) == 0 then
		return false, "The Storm Pass season hasn't started"
	end
	return true
end

function ShopService.promptProduct(player: Player, key: string): (boolean, string?)
	local product = Defs.Product[key]
	if not product then
		return false, "Unknown item"
	end
	local ok, why = ShopService.canBuy(player, product)
	if not ok then
		return false, why
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
	return true
end

function ShopService.promptPass(player: Player, key: string): (boolean, string?)
	local pass = Defs.Pass[key]
	if not pass then
		return false, "Unknown pass"
	end
	if pass.id == 0 then
		return false, "This pass isn't on sale yet"
	end
	if ShopService.hasPass(player, key) then
		return false, "You already own this pass"
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.id)
	return true
end

-- Exact previews shown before purchase (Charge packs scale with progress)
function ShopService.info(player: Player): { [string]: any }
	local data = DataService.get(player)
	local previews = {}
	for _, p in Config.Products do
		if p.kind == "ChargePack" and p.minutes then
			previews[p.key] = CurrencyService.minutesOfIncome(player, p.minutes)
		end
	end
	return {
		chargePacks = previews,
		starterPackBought = data ~= nil and data.Purchases.StarterPack,
		starterCharge = CurrencyService.minutesOfIncome(player, Config.StarterPack.Contents.chargeMinutes or 0),
	}
end

-------------------------------------------------------------------------------
-- Granting
-------------------------------------------------------------------------------

local function grant(player: Player, data: Types.ProfileData, product: Types.ProductDef): { string }
	local session = DataService.session(player)
	local lines = {}
	if product.kind == "ChargePack" then
		local amount = CurrencyService.minutesOfIncome(player, product.minutes or 0)
		CurrencyService.addCharge(player, amount, "Product")
		table.insert(lines, `+{Format.short(amount)} Charge`)
	elseif product.kind == "Potion" and product.potion then
		lines = RewardService.grant(player, { potions = { [product.potion] = product.count or 1 } }, "Product")
	elseif product.kind == "Egg" and product.egg then
		if session and session.Policy.PaidRandomItemsRestricted then
			-- Should never be prompted, but never lose a purchase: grant a fixed, non-random pet
			for _ = 1, product.count or 1 do
				PetService.givePet(player, Config.RestrictedEggFallbackPet, "Product", 1, true)
			end
			table.insert(lines, `{product.count or 1}x {Defs.Pet[Config.RestrictedEggFallbackPet].name}`)
		else
			PetService.hatchFree(player, product.egg, product.count or 1, "Product", true)
		end
	elseif product.kind == "PassSkip" then
		StormPassService.skipTier(player)
		table.insert(lines, "+1 Storm Pass tier")
	elseif product.kind == "PassPremium" then
		StormPassService.grantPremium(player)
		table.insert(lines, "Premium Storm Pass unlocked!")
	elseif product.kind == "InstantFusion" then
		PetService.instantFusion(player)
		table.insert(lines, "Fusion complete! (or saved as a Fusion Skip)")
	elseif product.kind == "StarterPack" then
		data.Purchases.StarterPack = true
		DataService.markDirty(player, "Purchases")
		lines = RewardService.grant(player, Config.StarterPack.Contents, "Product")
	end
	return lines
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.waitFor(player, 20)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if data.Purchases.Receipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Defs.ProductById[receipt.ProductId]
	if not product then
		warn(`[Shop] Unknown product id {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, lines = pcall(grant, player, data, product)
	if not ok then
		warn(`[Shop] Grant failed for {product.key}: {lines}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Record the receipt (bounded history) and purchase stats
	data.Purchases.Receipts[purchaseId] = DateTime.now().UnixTimestamp
	table.insert(data.Purchases.ReceiptOrder, purchaseId)
	while #data.Purchases.ReceiptOrder > MAX_RECEIPTS do
		local old = table.remove(data.Purchases.ReceiptOrder, 1) :: string
		data.Purchases.Receipts[old] = nil
	end
	local first = data.Purchases.FirstPurchaseAt == 0
	if first then
		data.Purchases.FirstPurchaseAt = DateTime.now().UnixTimestamp
	end
	data.Purchases.RobuxSpent += tonumber(receipt.CurrencySpent) or 0
	DataService.markDirty(player, "Purchases")

	if not DataService.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	GameEvents.Purchased:Fire(player, product.key, tonumber(receipt.CurrencySpent) or 0)
	if #lines > 0 then
		Net.Server.fire("Reward", player, "Popup", { title = `Thanks for buying {product.name}!`, lines = lines })
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.init() end

function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt :: any

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in Config.GamePasses do
			if pass.id == passId then
				ShopService.setPass(player, pass.key, true)
				Net.Server.fire("Reward", player, "Popup", { title = `{pass.name} unlocked!`, lines = { pass.description } })
				GameEvents.Purchased:Fire(player, pass.key, pass.priceHint)
			end
		end
	end)

	Net.Server.handle("PromptProduct", ShopService.promptProduct)
	Net.Server.handle("PromptPass", ShopService.promptPass)
	Net.Server.handle("GetShopInfo", ShopService.info)
	Net.Server.on("MarkStarterOffered", function(player: Player)
		local data = DataService.get(player)
		if data and not data.Flags.StarterOffered then
			data.Flags.StarterOffered = true
			DataService.markDirty(player, "Flags")
		end
	end)

	DataService.Loaded:Connect(function(player)
		fetchPolicy(player)
		checkPasses(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("VIP", nil)
	end)
end

return ShopService
