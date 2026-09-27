--!strict
-- Egg window, opened from an egg stand's prompt. Shows the EXACT odds for every Stormling
-- (base and with your current luck) before any purchase, as Roblox requires for random
-- items. Robux eggs are hidden for players whose region restricts paid random items.

local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HatchAnimation = require(script.Parent.HatchAnimation)
local PetPortrait = require(script.Parent.PetPortrait)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local EggUI = {}
local C = Theme.Colors

local currentEgg = "DrizzleEgg"
local render: (() -> ())? = nil

function EggUI.open(eggId: string)
	if not Defs.Egg[eggId] then
		return
	end
	currentEgg = eggId
	if Windows.isOpen("Egg") and render then
		render()
	else
		Windows.open("Egg")
	end
end

local function hatch(count: number)
	if HatchAnimation.isPlaying() then
		return
	end
	local ok, result = Net.Client.invoke("HatchEgg", currentEgg, count)
	if ok then
		Windows.close()
		HatchAnimation.play(currentEgg, result)
	elseif result then
		Effects.toast(tostring(result), C.Bad)
	end
end

function EggUI.start()
	Windows.register("Egg", {
		title = "Egg",
		icon = "Egg",
		color = C.Pets,
		size = Vector2.new(820, 540),
		build = function(content: Frame, window: Frame)
			local header = window:FindFirstChild("Header")
			local titleLabel = header and header:FindFirstChildOfClass("TextLabel")
			local body = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })

			render = function()
				for _, c in body:GetChildren() do
					c:Destroy()
				end
				local egg = Defs.Egg[currentEgg]
				if titleLabel then
					titleLabel.Text = `{Theme.Icons.Egg}  {egg.name}`
				end
				local d = ClientState.derived()
				local luck = d.EggLuck or 1
				local odds = EconomyMath.eggOdds(egg, luck)

				UIKit.label({
					Text = "Exact odds for every Stormling in this egg"
						.. (if luck > 1.001 then ` · your luck x{string.format("%.2f", luck)} boosts Rare+` else ""),
					Size = UDim2.new(1, 0, 0, 28),
					Color = C.TextDim,
					MaxTextSize = 22,
					Parent = body,
				})
				local list = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -130), Position = UDim2.fromOffset(0, 32), Parent = body })
				UIKit.grid(list, Vector2.new(146, 184), 8)
				for i, o in odds do
					local def = Defs.Pet[o.pet]
					local rarity = Defs.Rarity[def.rarity]
					local card = PetPortrait.card({
						petId = o.pet,
						parent = list,
						order = i,
						size = UDim2.fromOffset(146, 184),
						caption = def.name,
					})
					local art = card:FindFirstChild("Frame") :: Frame?
					if art then
						art.Size = UDim2.new(1, 0, 1, -84)
					end
					local caption = card:FindFirstChildOfClass("TextLabel")
					if caption then
						caption.Position = UDim2.new(0, 3, 1, -86)
					end
					UIKit.label({
						Text = Format.chance(o.chance),
						Color = rarity.color,
						Size = UDim2.new(1, -6, 0, 30),
						Position = UDim2.new(0, 3, 1, -58),
						MaxTextSize = 28,
						ZIndex = card.ZIndex + 3,
						Parent = card,
					})
					UIKit.label({
						Text = if math.abs(o.chance - o.baseChance) > 1e-9 then `base {Format.chance(o.baseChance)}` else rarity.name,
						Color = C.TextDim,
						Size = UDim2.new(1, -6, 0, 22),
						Position = UDim2.new(0, 3, 1, -28),
						MaxTextSize = 18,
						Stroke = 2,
						ZIndex = card.ZIndex + 3,
						Parent = card,
					})
				end

				local bar = UIKit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 86),
					Position = UDim2.new(0, 0, 1, -86),
					Parent = body,
				})
				UIKit.list(bar, 12, true)
				if egg.currency == "Charge" then
					local discount = d.EggDiscount or 0
					local price = EconomyMath.eggCost(egg, discount)
					UIKit.button({
						Text = `Hatch x1  {Theme.Icons.Charge}{Format.short(price)}`,
						Color = C.Good,
						Size = UDim2.fromOffset(280, 72),
						Parent = bar,
						OnClick = function()
							hatch(1)
						end,
					})
					local ascensions = ClientState.get("Ascensions") or 0
					if ascensions >= Config.Hatch.TripleHatchAscensions then
						UIKit.button({
							Text = `Hatch x3  {Theme.Icons.Charge}{Format.short(price * 3)}`,
							Color = C.Pets,
							Size = UDim2.fromOffset(280, 72),
							Parent = bar,
							OnClick = function()
								hatch(3)
							end,
						})
					end
					UIKit.button({
						Text = "Auto-delete",
						Color = C.PanelLight,
						Size = UDim2.fromOffset(180, 72),
						Parent = bar,
						OnClick = function()
							Windows.open("Settings")
						end,
					})
				elseif egg.currency == "Robux" then
					local policy = ClientState.get("Policy") or {}
					if policy.PaidRandomItemsRestricted ~= false then
						UIKit.label({
							Text = "Paid eggs aren't available in your region.",
							Size = UDim2.fromOffset(600, 60),
							Color = C.TextDim,
							Parent = bar,
						})
					else
						for _, product in Config.Products do
							if product.kind == "Egg" and product.egg == egg.id then
								UIKit.button({
									Text = `{product.name}`,
									Color = C.Robux,
									Size = UDim2.fromOffset(280, 72),
									Parent = bar,
									OnClick = function()
										local ok, msg = Net.Client.invoke("PromptProduct", product.key)
										if not ok and msg then
											Effects.toast(tostring(msg), C.Bad)
										end
									end,
								})
							end
						end
					end
				else
					UIKit.label({ Text = "Earn this egg from your daily streak!", Size = UDim2.fromOffset(600, 60), Parent = bar })
				end
			end
			return { refresh = render }
		end,
	})

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local stand = prompt:FindFirstAncestorOfClass("Model")
		local eggId = stand and stand:GetAttribute("EggId")
		if type(eggId) == "string" then
			EggUI.open(eggId)
		end
	end)

	-- Free hatches (streak egg, purchases) play the same reveal
	Net.Client.on("Reward", function(kind: string, payload: any)
		if kind == "Hatch" then
			HatchAnimation.play(payload.egg, payload.results)
		end
	end)
end

return EggUI
