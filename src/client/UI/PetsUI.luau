--!strict
-- Stormlings window: inventory grid + detail panel (equip, lock, fuse, delete) and a Fusion
-- tab showing running fusions with real timers, skips and the Instant Fusion product.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local PetPortrait = require(script.Parent.PetPortrait)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local PetsUI = {}
local C = Theme.Colors

local function call(remote: string, ...: any): boolean
	local ok, msg = Net.Client.invoke(remote, ...)
	if not ok and msg then
		Effects.toast(tostring(msg), C.Bad, 1.6)
	end
	return ok == true
end

function PetsUI.start()
	Windows.register("Pets", {
		title = "Stormlings",
		icon = "Pets",
		color = C.Pets,
		size = Vector2.new(860, 540),
		build = function(content: Frame)
			local selected: string? = nil
			local tab = "Pets"
			local confirmDelete = false

			-- Top bar
			local top = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = content })
			local tabPets = UIKit.button({ Text = "Stormlings", Color = C.Pets, Size = UDim2.fromOffset(170, 52), Parent = top })
			local tabFusion = UIKit.button({
				Text = "Fusion",
				Color = C.PanelLight,
				Size = UDim2.fromOffset(150, 52),
				Position = UDim2.fromOffset(180, 0),
				Parent = top,
			})
			local countLabel = UIKit.label({
				Size = UDim2.fromOffset(260, 44),
				Position = UDim2.fromOffset(340, 4),
				XAlign = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = top,
			})
			UIKit.button({
				Text = "Equip Best",
				Color = C.Good,
				Size = UDim2.fromOffset(180, 52),
				Position = UDim2.new(1, 0, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				Parent = top,
				OnClick = function()
					if call("EquipBest") then
						Effects.toast("Equipped your strongest Stormlings!", C.Good, 1.4)
					end
				end,
			})

			-- Pets tab
			local petsPage = UIKit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, -64),
				Position = UDim2.fromOffset(0, 64),
				Parent = content,
			})
			local grid = UIKit.scroll({ Size = UDim2.new(0.64, 0, 1, 0), Parent = petsPage })
			UIKit.grid(grid, Vector2.new(104, 124), 8)
			local detail = UIKit.panel({
				Size = UDim2.new(0.35, 0, 1, 0),
				Position = UDim2.fromScale(0.65, 0),
				Color = C.PanelDark,
				Parent = petsPage,
			})

			-- Fusion tab
			local fusionPage = UIKit.scroll({
				Size = UDim2.new(1, 0, 1, -64),
				Position = UDim2.fromOffset(0, 64),
				Parent = content,
			})
			fusionPage.Visible = false
			UIKit.list(fusionPage, 10)

			local function renderDetail()
				for _, c in detail:GetChildren() do
					if c:IsA("GuiObject") then
						c:Destroy()
					end
				end
				local pets = ClientState.get("Pets") or {}
				local pet = if selected then pets[selected] else nil
				if not pet then
					UIKit.label({
						Text = "Tap a Stormling to see it.\n\nFuse 3 identical Stormlings into a stronger tier!",
						Size = UDim2.new(1, -20, 1, -20),
						Position = UDim2.fromOffset(10, 10),
						Color = C.TextDim,
						MaxTextSize = 24,
						Parent = detail,
					})
					return
				end
				local def = Defs.Pet[pet.id]
				local rarity = Defs.Rarity[def.rarity]
				local art = UIKit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 130),
					Parent = detail,
				})
				PetPortrait.draw(art, pet.id, pet.tier)
				UIKit.label({ Text = def.name, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 130), MaxTextSize = 30, Parent = detail })
				UIKit.label({
					Text = `{rarity.name} · {PetPortrait.tierName(pet.tier)}`,
					Color = rarity.color,
					Size = UDim2.new(1, -16, 0, 26),
					Position = UDim2.fromOffset(8, 164),
					MaxTextSize = 22,
					Parent = detail,
				})
				UIKit.label({
					Text = `{Theme.Icons.Charge} {Format.percentBonus(EconomyMath.petPower(pet.id, pet.tier))} Charge`,
					Color = C.Charge,
					Size = UDim2.new(1, -16, 0, 28),
					Position = UDim2.fromOffset(8, 192),
					MaxTextSize = 24,
					Parent = detail,
				})
				local equipped = table.find(ClientState.get("Equipped") or {}, pet.uid) ~= nil
				local buttons = UIKit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -16, 0, 200),
					Position = UDim2.new(0, 8, 1, -206),
					Parent = detail,
				})
				UIKit.grid(buttons, Vector2.new(128, 58), 8)
				UIKit.button({
					Text = if equipped then "Unequip" else "Equip",
					Color = if equipped then C.PanelLight else C.Good,
					Parent = buttons,
					LayoutOrder = 1,
					OnClick = function()
						call("EquipPet", pet.uid, not equipped)
					end,
				})
				UIKit.button({
					Text = if pet.locked then "Unlock" else `{Theme.Icons.Lock} Lock`,
					Color = C.Travel,
					Parent = buttons,
					LayoutOrder = 2,
					OnClick = function()
						call("LockPet", pet.uid, not pet.locked)
					end,
				})
				-- Fusion availability
				local same = 0
				for _, other in pets do
					if other.id == pet.id and other.tier == pet.tier and not other.locked then
						same += 1
					end
				end
				local canFuse = pet.tier < #Config.Fusion.Tiers
				UIKit.button({
					Text = if canFuse then `Fuse {math.min(same, Config.Fusion.Required)}/{Config.Fusion.Required}` else "Max tier",
					Color = if canFuse and same >= Config.Fusion.Required then C.Pass else C.PanelDark,
					Parent = buttons,
					LayoutOrder = 3,
					OnClick = function()
						if canFuse and call("StartFusion", pet.id, pet.tier) then
							Effects.toast(`Fusing into {PetPortrait.tierName(pet.tier + 1)} {def.name}!`, C.Pass)
							Effects.shake(0.4)
							selected = nil
						end
					end,
				})
				UIKit.button({
					Text = if confirmDelete then "Sure?" else "Delete",
					Color = C.Bad,
					Parent = buttons,
					LayoutOrder = 4,
					OnClick = function()
						if pet.locked then
							Effects.toast("Unlock it first", C.Bad)
						elseif confirmDelete then
							confirmDelete = false
							if call("DeletePets", { pet.uid }) then
								selected = nil
							end
						else
							confirmDelete = true
							renderDetail()
							task.delay(3, function()
								confirmDelete = false
							end)
						end
					end,
				})
			end

			local function renderGrid()
				for _, c in grid:GetChildren() do
					if c:IsA("GuiObject") then
						c:Destroy()
					end
				end
				local pets = ClientState.get("Pets") or {}
				local equippedList = ClientState.get("Equipped") or {}
				local list = {}
				for uid, pet in pets do
					table.insert(list, {
						uid = uid,
						pet = pet,
						power = EconomyMath.petPower(pet.id, pet.tier),
						equipped = table.find(equippedList, uid) ~= nil,
					})
				end
				table.sort(list, function(a, b)
					if a.equipped ~= b.equipped then
						return a.equipped
					end
					return a.power > b.power
				end)
				for i, entry in list do
					local card = PetPortrait.card({
						petId = entry.pet.id,
						tier = entry.pet.tier,
						caption = Format.percentBonus(entry.power),
						order = i,
						parent = grid,
						size = UDim2.fromOffset(104, 124),
						onClick = function()
							selected = entry.uid
							confirmDelete = false
							renderDetail()
						end,
					})
					if entry.equipped then
						UIKit.label({ Text = Theme.Icons.Check, Color = C.Good, Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(4, 2), Parent = card, ZIndex = 10 })
					end
					if entry.pet.locked then
						UIKit.label({ Text = Theme.Icons.Lock, Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -30, 0, 2), Parent = card, ZIndex = 10 })
					end
					if entry.uid == selected then
						UIKit.stroke(card, 5, C.Text)
					end
				end
				local d = ClientState.derived()
				countLabel.Text = `Equipped {#equippedList}/{d.Slots or Config.Economy.BaseEquipSlots} · {#list}/{Config.Economy.MaxPets}`
				renderDetail()
			end

			local function renderFusion()
				for _, c in fusionPage:GetChildren() do
					if c:IsA("GuiObject") then
						c:Destroy()
					end
				end
				local jobs = ClientState.get("Fusions") or {}
				local skips = ClientState.get("FusionSkips") or 0
				UIKit.label({
					Text = `Fusion skips: {skips}   ·   Pick 3 identical Stormlings in the Stormlings tab and tap Fuse.`,
					Size = UDim2.new(1, -10, 0, 34),
					MaxTextSize = 22,
					Color = C.TextDim,
					LayoutOrder = 0,
					Parent = fusionPage,
				})
				if #jobs == 0 then
					UIKit.label({ Text = "No fusions running.", Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1, Parent = fusionPage })
				end
				for i, job in jobs do
					local row = UIKit.panel({ Size = UDim2.new(1, -10, 0, 110), Color = C.PanelLight, LayoutOrder = i, Parent = fusionPage })
					local art = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 100), Position = UDim2.fromOffset(6, 5), Parent = row })
					PetPortrait.draw(art, job.id, job.tier)
					local def = Defs.Pet[job.id]
					UIKit.label({
						Text = `{PetPortrait.tierName(job.tier)} {def.name}`,
						Size = UDim2.new(0.5, -110, 0, 36),
						Position = UDim2.fromOffset(112, 8),
						XAlign = Enum.TextXAlignment.Left,
						MaxTextSize = 28,
						Parent = row,
					})
					local bar = UIKit.progress({ Size = UDim2.new(0.5, -120, 0, 34), Position = UDim2.fromOffset(112, 56), Color = C.Pass, Parent = row })
					local actions = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -10, 1, -20), Position = UDim2.new(0.5, 0, 0, 10), Parent = row })
					UIKit.list(actions, 8, true, Enum.HorizontalAlignment.Right)
					local claim = UIKit.button({
						Text = "Claim",
						Color = C.Good,
						Size = UDim2.fromOffset(120, 60),
						Parent = actions,
						OnClick = function()
							if call("ClaimFusion", job.uid) then
								Effects.banner(`{PetPortrait.tierName(job.tier)} {def.name}!`, Defs.Rarity[def.rarity].color)
								Effects.shake(0.6)
							end
						end,
					})
					local skip = UIKit.button({
						Text = "Use Skip",
						Color = C.Travel,
						Size = UDim2.fromOffset(130, 60),
						Parent = actions,
						OnClick = function()
							call("UseFusionSkip", job.uid)
						end,
					})
					local instant = UIKit.button({
						Text = "Instant",
						Color = C.Robux,
						Size = UDim2.fromOffset(120, 60),
						Parent = actions,
						OnClick = function()
							call("PromptProduct", "InstantFusion")
						end,
					})
					task.spawn(function()
						while row.Parent do
							local now = DateTime.now().UnixTimestamp
							local total = math.max(1, job.endAt - job.startAt)
							local left = job.endAt - now
							bar.set(1 - left / total, if left > 0 then Format.duration(left) else "Ready!")
							claim.Visible = left <= 0
							skip.Visible = left > 0 and skips > 0
							instant.Visible = left > 0
							task.wait(0.5)
						end
					end)
				end
			end

			local function setTab(name: string)
				tab = name
				petsPage.Visible = name == "Pets"
				fusionPage.Visible = name == "Fusion"
				UIKit.setButtonColor(tabPets, if name == "Pets" then C.Pets else C.PanelLight)
				UIKit.setButtonColor(tabFusion, if name == "Fusion" then C.Pass else C.PanelLight)
				if name == "Pets" then
					renderGrid()
				else
					renderFusion()
				end
			end
			tabPets.Activated:Connect(function()
				setTab("Pets")
			end)
			tabFusion.Activated:Connect(function()
				setTab("Fusion")
			end)

			local function refresh()
				setTab(tab)
			end
			for _, key in { "Pets", "Equipped", "Fusions", "FusionSkips" } do
				ClientState.observe(key, function()
					if Windows.isOpen("Pets") then
						refresh()
					end
				end)
			end
			return { refresh = refresh }
		end,
	})
end

return PetsUI
