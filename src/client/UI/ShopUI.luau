--!strict
-- Shop (one tap from the HUD, never opens by itself). Tabs: Passes, Boosts (potions you own
-- + potions for sale), Charge (packs show the exact amount you'd get), Starter Pack.
-- Prices come live from MarketplaceService. No timers, no "limited stock", no pressure.
-- Also: the one-time Starter Pack offer and the VIP chat tag.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local RetentionUI = require(script.Parent.RetentionUI)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local ShopUI = {}
local C = Theme.Colors

local priceCache: { [string]: number | false } = {}
local requestedTab: string? = nil

-- Real price in Robux, or nil if unknown / not configured
local function price(kind: "Product" | "Pass", id: number): number?
	if id == 0 then
		return nil
	end
	local key = `{kind}{id}`
	local cached = priceCache[key]
	if cached ~= nil then
		return if cached == false then nil else cached :: number
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
	end)
	local value = if ok and info and info.PriceInRobux then info.PriceInRobux else nil
	priceCache[key] = value or false
	return value
end

local function priceText(kind: "Product" | "Pass", id: number): string
	local p = price(kind, id)
	if id == 0 then
		return "Coming soon"
	end
	return if p then `R$ {p}` else "R$ …"
end

local function call(remote: string, ...: any): boolean
	local ok, msg = Net.Client.invoke(remote, ...)
	if not ok and msg then
		Effects.toast(tostring(msg), C.Bad, 2)
	end
	return ok == true
end

-- "Worth R$X if bought separately" from live prices; nil if any price is unknown
local function starterWorth(): number?
	local total = 0
	for _, item in Config.StarterPack.ValueOf do
		local product = Defs.Product[item.key]
		local p = product and price("Product", product.id)
		if not p then
			return nil
		end
		total += p * item.count
	end
	return total
end

local function card(parent: Instance, order: number, color: Color3, title: string, desc: string, buttonText: string, onBuy: () -> ()): (Frame, TextButton)
	local c = UIKit.panel({ Color = color, LayoutOrder = order, Parent = parent })
	UIKit.label({ Text = title, Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 6), MaxTextSize = 28, Parent = c })
	UIKit.label({
		Text = desc,
		Size = UDim2.new(1, -16, 1, -120),
		Position = UDim2.fromOffset(8, 44),
		Font = Theme.FontBody,
		MaxTextSize = 18,
		Parent = c,
	})
	local b = UIKit.button({
		Text = buttonText,
		Color = C.Robux,
		Size = UDim2.new(1, -20, 0, 60),
		Position = UDim2.new(0, 10, 1, -68),
		Parent = c,
		OnClick = function()
			onBuy()
		end,
	})
	return c, b
end

function ShopUI.open(tabName: string?)
	requestedTab = tabName
	Windows.open("Shop")
end

function ShopUI.start()
	Windows.register("Shop", {
		title = "Shop",
		icon = "Shop",
		color = C.Shop,
		size = Vector2.new(940, 580),
		build = function(content: Frame)
			local tab = "Passes"
			local tabs = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = content })
			UIKit.list(tabs, 8, true, Enum.HorizontalAlignment.Left)
			local page = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -64), Position = UDim2.fromOffset(0, 64), Parent = content })
			local tabButtons: { [string]: TextButton } = {}
			local render: () -> ()

			local function clear()
				for _, c in page:GetChildren() do
					if c:IsA("GuiObject") or c:IsA("UIGridLayout") or c:IsA("UIListLayout") then
						c:Destroy()
					end
				end
			end

			local function passes()
				UIKit.grid(page, Vector2.new(282, 230), 10)
				for i, pass in Config.GamePasses do
					local owned = ClientState.hasPass(pass.key)
					local _, b = card(page, i, C.PanelLight, pass.name, pass.description, if owned then "Owned " .. Theme.Icons.Check else priceText("Pass", pass.id), function()
						if not owned then
							call("PromptPass", pass.key)
						end
					end)
					if owned then
						UIKit.setButtonColor(b, C.PanelDark)
					end
				end
			end

			local function boosts()
				UIKit.list(page, 10)
				local owned = ClientState.get("Potions") or {}
				local header = UIKit.label({ Text = "Your potions (free to use, stack up to 4 hours)", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 0, Color = C.TextDim, MaxTextSize = 22, Parent = page })
				header.LayoutOrder = 0
				local row = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 1, Parent = page })
				UIKit.list(row, 10, true)
				for _, potion in Config.Potions do
					local c = UIKit.panel({ Size = UDim2.fromOffset(280, 140), Color = potion.color, Parent = row })
					UIKit.label({ Text = `{potion.name} x{owned[potion.id] or 0}`, Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 6), MaxTextSize = 26, Parent = c })
					UIKit.label({ Text = `{potion.stat} x{potion.mult} for {Format.duration(potion.seconds)}`, Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 46), Font = Theme.FontBody, MaxTextSize = 18, Parent = c })
					UIKit.button({
						Text = "Use",
						Color = C.Good,
						Size = UDim2.new(1, -20, 0, 54),
						Position = UDim2.new(0, 10, 1, -62),
						Parent = c,
						OnClick = function()
							if call("UsePotion", potion.id) then
								Effects.toast(`{potion.name} active!`, potion.color)
							end
						end,
					})
				end
				local grid = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 480), LayoutOrder = 2, Parent = page })
				UIKit.grid(grid, Vector2.new(282, 220), 10)
				local i = 0
				for _, product in Config.Products do
					if product.kind == "Potion" or product.kind == "InstantFusion" then
						i += 1
						card(grid, i, C.PanelLight, product.name, product.description, priceText("Product", product.id), function()
							call("PromptProduct", product.key)
						end)
					end
				end
			end

			local function charge()
				UIKit.grid(page, Vector2.new(282, 230), 10)
				local info = Net.Client.invoke("GetShopInfo") or { chargePacks = {} }
				local i = 0
				for _, product in Config.Products do
					if product.kind == "ChargePack" then
						i += 1
						local amount = info.chargePacks[product.key]
						local desc = `{product.description}\n\nYou get exactly:\n<font color="#FFD633">{Theme.Icons.Charge} {if amount then Format.short(amount) else "…"}</font>`
						card(page, i, C.PanelLight, product.name, desc, priceText("Product", product.id), function()
							call("PromptProduct", product.key)
						end)
					end
				end
				local policy = ClientState.get("Policy") or {}
				for _, product in Config.Products do
					if product.kind == "Egg" and policy.PaidRandomItemsRestricted == false then
						i += 1
						card(page, i, C.Pets, product.name, `{product.description}\nOpen the egg on Drizzle Meadows' plaza to see every pet's exact odds.`, "See odds", function()
							local EggUI = require(script.Parent.EggUI) :: any
							EggUI.open(product.egg)
						end)
					end
				end
			end

			local function starter()
				UIKit.list(page, 10)
				local purchases = ClientState.get("Purchases") or {}
				local product = Defs.Product.StarterPack
				local contents: Types.Reward = Config.StarterPack.Contents
				local panel = UIKit.panel({ Size = UDim2.new(1, -10, 0, 380), Color = C.Pass, Parent = page })
				UIKit.label({ Text = "Starter Pack", Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 8), MaxTextSize = 40, Parent = panel })
				UIKit.label({
					Text = RetentionUI.describe(contents),
					Size = UDim2.new(1, -20, 0, 170),
					Position = UDim2.fromOffset(10, 62),
					Font = Theme.FontBody,
					MaxTextSize = 24,
					Parent = panel,
				})
				local worth = starterWorth()
				local myPrice = price("Product", product.id)
				local worthText = ""
				if worth and myPrice and worth > myPrice then
					worthText = `Worth R$ {worth} if bought separately. One per player.`
				end
				UIKit.label({ Text = worthText, Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 236), Color = C.Charge, MaxTextSize = 24, Parent = panel })
				local b = UIKit.button({
					Text = if purchases.StarterPack then "Owned " .. Theme.Icons.Check else priceText("Product", product.id),
					Color = if purchases.StarterPack then C.PanelDark else C.Robux,
					Size = UDim2.fromOffset(320, 72),
					Position = UDim2.new(0.5, 0, 1, -14),
					AnchorPoint = Vector2.new(0.5, 1),
					Parent = panel,
				})
				b.Activated:Connect(function()
					if not purchases.StarterPack then
						call("PromptProduct", "StarterPack")
					end
				end)
			end

			render = function()
				if requestedTab then
					tab = requestedTab :: string
					requestedTab = nil
				end
				clear()
				for name, b in tabButtons do
					UIKit.setButtonColor(b, if name == tab then C.Shop else C.PanelLight)
				end
				if tab == "Passes" then
					passes()
				elseif tab == "Boosts" then
					boosts()
				elseif tab == "Charge" then
					charge()
				else
					starter()
				end
			end
			for i, name in { "Passes", "Boosts", "Charge", "Starter" } do
				tabButtons[name] = UIKit.button({
					Text = name,
					Color = C.PanelLight,
					Size = UDim2.fromOffset(170, 52),
					LayoutOrder = i,
					Parent = tabs,
					OnClick = function()
						tab = name
						render()
					end,
				})
			end
			for _, key in { "Passes", "Potions", "Purchases" } do
				ClientState.observe(key, function()
					if Windows.isOpen("Shop") then
						render()
					end
				end)
			end
			return {
				refresh = function()
					task.spawn(render) -- prices may yield
				end,
			}
		end,
	})

	-- One-time Starter Pack offer: shown once, a few minutes after the tutorial
	task.spawn(function()
		ClientState.waitLoaded()
		local flags = ClientState.get("Flags") or {}
		local purchases = ClientState.get("Purchases") or {}
		if flags.StarterOffered or purchases.StarterPack or Defs.Product.StarterPack.id == 0 then
			return
		end
		while not (ClientState.get("Flags") or {}).TutorialDone do
			task.wait(2)
		end
		task.wait(Config.StarterPack.OfferAfterSeconds)
		if Windows.current() == nil then
			Net.Client.fire("MarkStarterOffered")
			ShopUI.open("Starter")
		end
	end)

	-- VIP chat tag
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if player and player:GetAttribute("VIP") then
			props.PrefixText = `<font color="#FFD633">[VIP]</font> {message.PrefixText}`
		end
		return props
	end
end

return ShopUI
