--!strict
-- Collection window: every owned Brainrot in a grid of 3D cards (grouped by Brainrot +
-- mutation with a quantity), rarity filters, sorting (Rarity / Power / Income / Recent),
-- undiscovered "???" index cards, and a detail panel to Equip, send to the Zoo, Level Up,
-- Lock or Sell a specific copy.

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotMath = require(Modules:WaitForChild("BrainrotMath"))
local Format = require(Modules:WaitForChild("Format"))
local Registry = require(Modules:WaitForChild("Registry"))
local Theme = require(Modules:WaitForChild("Theme"))
local Types = require(Modules:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local BrainrotInfo = require(script.Parent.BrainrotInfo)
local Bus = require(script.Parent.Bus)
local Notifications = require(script.Parent.Notifications)
local UIKit = require(script.Parent.UIKit)
local Viewport = require(script.Parent.Viewport)
local Windows = require(script.Parent.Windows)

local CollectionUI = {}

local C = Theme.Colors

type Group = {
	key: string,
	id: string,
	mut: string,
	uids: { string },
	best: string,
	power: number,
	income: number,
	newest: number,
	equipped: number,
	inZoo: number,
}

local filter = "All"
local sortMode = "Rarity"
local selectedKey: string? = nil
local selectedUid: string? = nil
local pendingUid: string? = nil

local grid: ScrollingFrame
local storageLabel: TextLabel
local filterButtons: { [string]: TextButton } = {}
local sortButton: TextButton
local detail: Frame
local detailVp: ViewportFrame? = nil
local detailVpHolder: Frame
local sheet: BrainrotInfo.Sheet
local copiesRow: ScrollingFrame
local actionButtons: { [string]: TextButton } = {}
local emptyDetail: TextLabel
local refreshQueued = false

local SORTS = { "Rarity", "Power", "Income", "Recent" }

local function groups(): { Group }
	local map: { [string]: Group } = {}
	for uid, inst in ClientState.inventory do
		local def = Registry.Brainrot[inst.id]
		if def then
			local key = inst.id .. ":" .. inst.mut
			local g = map[key]
			if not g then
				g = {
					key = key,
					id = inst.id,
					mut = inst.mut,
					uids = {},
					best = uid,
					power = -1,
					income = 0,
					newest = 0,
					equipped = 0,
					inZoo = 0,
				}
				map[key] = g
			end
			local grp = g :: Group
			table.insert(grp.uids, uid)
			local p = BrainrotMath.instancePower(inst)
			if p > grp.power then
				grp.power = p
				grp.best = uid
			end
			grp.income = math.max(grp.income, BrainrotMath.baseIncome(def, inst.mut, inst.lvl))
			grp.newest = math.max(grp.newest, inst.t)
			if ClientState.isEquipped(uid) then
				grp.equipped += 1
			elseif ClientState.zooHabitatOf(uid) then
				grp.inZoo += 1
			end
		end
	end
	local list = {}
	for _, g in map do
		local def = Registry.Brainrot[g.id]
		if filter == "All" or def.rarity == filter then
			table.insert(list, g)
		end
	end
	table.sort(list, function(a, b)
		if sortMode == "Power" then
			return a.power > b.power
		elseif sortMode == "Income" then
			return a.income > b.income
		elseif sortMode == "Recent" then
			return a.newest > b.newest
		end
		local ra = Registry.rarityOf(a.id).order
		local rb = Registry.rarityOf(b.id).order
		if ra ~= rb then
			return ra > rb
		end
		local ma = Registry.Mutation[a.mut].order
		local mb = Registry.Mutation[b.mut].order
		if ma ~= mb then
			return ma > mb
		end
		return a.power > b.power
	end)
	return list
end

local function statusOf(uid: string): string
	if ClientState.isEquipped(uid) then
		return "⚔️ Equipped"
	end
	local h = ClientState.zooHabitatOf(uid)
	if h then
		return `🏡 {Registry.Habitat[h].name}`
	end
	return "💤 Idle"
end

-------------------------------------------------------------------------------
-- Detail panel
-------------------------------------------------------------------------------
local function refreshDetail()
	local inst: Types.BrainrotInstance? = if selectedUid then ClientState.inventory[selectedUid] else nil
	if not inst or not selectedUid then
		emptyDetail.Visible = true
		sheet.frame.Visible = false
		detailVpHolder.Visible = false
		copiesRow.Visible = false
		for _, b in actionButtons do
			b.Visible = false
		end
		return
	end
	local uid = selectedUid :: string
	emptyDetail.Visible = false
	sheet.frame.Visible = true
	detailVpHolder.Visible = true
	copiesRow.Visible = true
	if detailVp then
		Viewport.set(detailVp, inst.id, inst.mut)
	else
		detailVp = Viewport.new({ id = inst.id, mut = inst.mut, spin = true, parent = detailVpHolder, zindex = 4 })
	end
	sheet.set(inst.id, inst.mut, inst.lvl)
	-- copies of this group
	for _, c in copiesRow:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local key = inst.id .. ":" .. inst.mut
	local copies = {}
	for u, other in ClientState.inventory do
		if other.id .. ":" .. other.mut == key then
			table.insert(copies, { uid = u, inst = other })
		end
	end
	table.sort(copies, function(a, b)
		return a.inst.lvl > b.inst.lvl
	end)
	for i, c in copies do
		local selected = c.uid == uid
		UIKit.button({
			Text = `Lv{c.inst.lvl} {if c.inst.locked then "🔒" else ""}\n<font size="12">{statusOf(c.uid)}</font>`,
			Color = if selected then C.Primary else C.PanelLight,
			Size = UDim2.fromOffset(112, 46),
			MaxTextSize = 18,
			LayoutOrder = i,
			Parent = copiesRow,
			OnClick = function()
				selectedUid = c.uid
				refreshDetail()
			end,
		})
	end
	-- actions
	local equipped = ClientState.isEquipped(uid)
	local inZoo = ClientState.zooHabitatOf(uid) ~= nil
	for _, b in actionButtons do
		b.Visible = true
	end
	UIKit.setButtonText(actionButtons.Equip, if equipped then "Unequip" else "⚔️ Equip")
	UIKit.setButtonColor(actionButtons.Equip, if equipped then C.PanelLight else C.Good)
	UIKit.setButtonText(actionButtons.Zoo, if inZoo then "Remove from Zoo" else "🏡 To Zoo")
	local def = Registry.Brainrot[inst.id]
	local coins, essence = BrainrotMath.levelUpCost(def, inst.lvl)
	UIKit.setButtonText(
		actionButtons.Level,
		if coins then `⬆️ Lv Up ${Format.short(coins)} · 🧪{essence}` else "MAX LEVEL"
	)
	UIKit.setButtonText(actionButtons.Lock, if inst.locked then "🔓 Unlock" else "🔒 Lock")
	actionButtons.Sell.Visible = not inst.locked and not equipped
	UIKit.setButtonText(
		actionButtons.Sell,
		`💰 Sell ${Format.short(BrainrotMath.sellValue(def, inst.mut, inst.lvl))}`
	)
end

-------------------------------------------------------------------------------
-- Grid
-------------------------------------------------------------------------------
local function card(g: Group, order: number)
	local def = Registry.Brainrot[g.id]
	local rarity = Registry.Rarity[def.rarity]
	local mut = Registry.Mutation[g.mut]
	local selected = g.key == selectedKey
	local frame = UIKit.panel({
		Size = UDim2.fromOffset(150, 196),
		Color = if selected then C.PanelLight else C.PanelDark,
		LayoutOrder = order,
		Parent = grid,
	})
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.color
		stroke.Thickness = if selected then 5 else 3
	end
	Viewport.new({
		id = g.id,
		mut = g.mut,
		parent = frame,
		size = UDim2.fromOffset(140, 104),
		position = UDim2.fromOffset(5, 4),
		zindex = 3,
	})
	UIKit.label({
		Text = Registry.displayName(g.id, g.mut),
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 108),
		MaxTextSize = 18,
		Color = if mut.color then mut.color else rarity.color,
		Parent = frame,
	})
	UIKit.label({
		Text = def.rarity,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 130),
		MaxTextSize = 14,
		Color = rarity.color,
		Stroke = 1,
		Parent = frame,
	})
	UIKit.label({
		Text = `⚔️ {Format.short(g.power)}   💵 {Format.short(g.income)}/m`,
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(4, 148),
		MaxTextSize = 15,
		Parent = frame,
	})
	local status = {}
	if g.equipped > 0 then
		table.insert(status, `⚔️{g.equipped}`)
	end
	if g.inZoo > 0 then
		table.insert(status, `🏡{g.inZoo}`)
	end
	UIKit.label({
		Text = table.concat(status, " "),
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(4, 170),
		MaxTextSize = 15,
		Color = C.Good,
		Parent = frame,
	})
	UIKit.label({
		Text = `x{#g.uids}`,
		Size = UDim2.fromOffset(50, 26),
		Position = UDim2.new(1, -54, 0, 4),
		XAlign = Enum.TextXAlignment.Right,
		MaxTextSize = 22,
		Color = C.Warn,
		ZIndex = 5,
		Parent = frame,
	})
	local click = UIKit.new(
		"TextButton",
		{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = frame }
	)
	click.Activated:Connect(function()
		UIKit.sound("Click", 0.3)
		selectedKey = g.key
		selectedUid = g.best
		CollectionUI.refresh()
	end)
end

local function unknownCard(def: Types.BrainrotDef, order: number)
	local rarity = Registry.Rarity[def.rarity]
	local frame = UIKit.panel({
		Size = UDim2.fromOffset(150, 196),
		Color = Color3.fromRGB(26, 24, 40),
		LayoutOrder = order,
		Parent = grid,
	})
	frame.BackgroundTransparency = 0.2
	UIKit.label({
		Text = "❓",
		Size = UDim2.fromOffset(140, 100),
		Position = UDim2.fromOffset(5, 6),
		MaxTextSize = 70,
		Color = C.Locked,
		Parent = frame,
	})
	UIKit.label({
		Text = "???",
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 110),
		MaxTextSize = 20,
		Color = C.Locked,
		Parent = frame,
	})
	UIKit.label({
		Text = def.rarity,
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(4, 134),
		MaxTextSize = 15,
		Color = rarity.color,
		Stroke = 1,
		Parent = frame,
	})
	UIKit.label({
		Text = "Not discovered",
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(4, 160),
		MaxTextSize = 14,
		Color = C.TextDim,
		Parent = frame,
	})
end

function CollectionUI.refresh()
	if not grid then
		return
	end
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local list = groups()
	if pendingUid and ClientState.inventory[pendingUid] then
		local inst = ClientState.inventory[pendingUid]
		selectedKey = inst.id .. ":" .. inst.mut
		selectedUid = pendingUid
		pendingUid = nil
	end
	if selectedUid and not ClientState.inventory[selectedUid] then
		selectedUid = nil
		selectedKey = nil
	end
	for i, g in list do
		card(g, i)
	end
	-- index: Brainrots never owned
	local index = ClientState.data.index or {}
	local n = #list
	for _, def in Registry.Brainrots do
		if not index[def.id] and (filter == "All" or filter == def.rarity) then
			n += 1
			unknownCard(def, n)
		end
	end
	storageLabel.Text = `📦 {ClientState.inventoryCount()}/{ClientState.storageCap()}`
	for name, b in filterButtons do
		UIKit.setButtonColor(b, if name == filter then C.Primary else C.PanelLight)
	end
	UIKit.setButtonText(sortButton, `Sort: {sortMode}`)
	refreshDetail()
end

local function queueRefresh()
	if refreshQueued or not Windows.isOpen("Collection") then
		return
	end
	refreshQueued = true
	task.delay(0.15, function()
		refreshQueued = false
		if Windows.isOpen("Collection") then
			CollectionUI.refresh()
		end
	end)
end

function CollectionUI.start()
	Windows.register("Collection", {
		title = "BRAINROT COLLECTION",
		icon = "📖",
		color = C.Primary,
		size = Vector2.new(1180, 640),
		build = function(content: Frame)
			-- filter bar
			local bar =
				UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 760, 0, 40), Parent = content })
			UIKit.list(bar, 6, true, Enum.HorizontalAlignment.Left)
			local tabs = { "All" }
			for _, r in Registry.Rarities do
				table.insert(tabs, r.id)
			end
			for i, name in tabs do
				local rarity = Registry.Rarity[name]
				filterButtons[name] = UIKit.button({
					Text = name,
					Color = C.PanelLight,
					Size = UDim2.fromOffset(if name == "All" then 60 else 86, 36),
					MaxTextSize = 15,
					LayoutOrder = i,
					Parent = bar,
					OnClick = function()
						filter = name
						CollectionUI.refresh()
					end,
				})
				if rarity then
					local label = filterButtons[name]:FindFirstChild("Text") :: TextLabel?
					if label then
						label.TextColor3 = rarity.color
					end
				end
			end
			-- second row: sort + bulk actions + storage
			local row = UIKit.new(
				"Frame",
				{
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 760, 0, 40),
					Position = UDim2.fromOffset(0, 44),
					Parent = content,
				}
			)
			UIKit.list(row, 8, true, Enum.HorizontalAlignment.Left)
			sortButton = UIKit.button({
				Text = "Sort: Rarity",
				Color = C.Secondary,
				Size = UDim2.fromOffset(170, 36),
				MaxTextSize = 18,
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					local i = table.find(SORTS, sortMode) or 1
					sortMode = SORTS[i % #SORTS + 1]
					CollectionUI.refresh()
				end,
			})
			UIKit.button({
				Text = "⚔️ Equip Best",
				Color = C.Good,
				Size = UDim2.fromOffset(160, 36),
				MaxTextSize = 18,
				LayoutOrder = 2,
				Parent = row,
				OnClick = function()
					Notifications.call("EquipBest")
				end,
			})
			UIKit.button({
				Text = "🏡 Fill Zoo",
				Color = C.Secondary,
				Size = UDim2.fromOffset(140, 36),
				MaxTextSize = 18,
				LayoutOrder = 3,
				Parent = row,
				OnClick = function()
					local ok, placed = Notifications.call("FillZoo")
					if ok then
						Notifications.toast(
							if placed > 0
								then `Placed {placed} Brainrots in your zoo!`
								else "No room — unlock or upgrade habitats",
							C.Good
						)
					end
				end,
			})
			storageLabel = UIKit.label({
				Text = "",
				Size = UDim2.fromOffset(150, 36),
				MaxTextSize = 22,
				LayoutOrder = 4,
				Parent = row,
			})
			grid =
				UIKit.scroll({ Size = UDim2.new(0, 770, 1, -92), Position = UDim2.fromOffset(0, 90), Parent = content })
			local g = UIKit.grid(grid, Vector2.new(150, 196), 10)
			g.HorizontalAlignment = Enum.HorizontalAlignment.Left

			-- detail panel
			detail = UIKit.panel({
				Size = UDim2.new(1, -785, 1, 0),
				Position = UDim2.fromOffset(785, 0),
				Color = C.PanelDark,
				Parent = content,
			})
			emptyDetail = UIKit.label({
				Text = "Select a Brainrot to see its stats",
				Size = UDim2.new(1, -20, 0, 60),
				Position = UDim2.new(0, 10, 0.4, 0),
				MaxTextSize = 22,
				Color = C.TextDim,
				Parent = detail,
			})
			detailVpHolder = UIKit.new(
				"Frame",
				{
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(150, 120),
					Position = UDim2.new(0.5, -75, 0, 4),
					Parent = detail,
				}
			)
			sheet = BrainrotInfo.new(detail, UDim2.new(1, -16, 0, 300), UDim2.fromOffset(8, 118))
			copiesRow = UIKit.scroll({
				Size = UDim2.new(1, -12, 0, 62),
				Position = UDim2.new(0, 6, 1, -176),
				Horizontal = true,
				Padding = 4,
				Parent = detail,
			})
			UIKit.list(copiesRow, 6, true, Enum.HorizontalAlignment.Left)
			local actions = UIKit.new(
				"Frame",
				{
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -12, 0, 104),
					Position = UDim2.new(0, 6, 1, -110),
					Parent = detail,
				}
			)
			UIKit.grid(actions, Vector2.new(184, 46), 6)
			local function action(name: string, color: Color3, order: number, fn: (string) -> ())
				actionButtons[name] = UIKit.button({
					Text = name,
					Color = color,
					Size = UDim2.fromOffset(184, 46),
					MaxTextSize = 18,
					LayoutOrder = order,
					Parent = actions,
					OnClick = function()
						if selectedUid then
							fn(selectedUid)
						end
					end,
				})
			end
			action("Equip", C.Good, 1, function(uid)
				Notifications.call("Equip", uid, not ClientState.isEquipped(uid))
			end)
			action("Zoo", C.Secondary, 2, function(uid)
				if ClientState.zooHabitatOf(uid) then
					Notifications.call("RemoveFromZoo", uid)
				else
					local ok, habitat = Notifications.call("SendToZoo", uid, nil)
					if ok and type(habitat) == "string" then
						Notifications.toast(`Sent to the {Registry.Habitat[habitat].name}!`, C.Good)
					end
				end
			end)
			action("Level", C.Warn, 3, function(uid)
				local ok = Notifications.call("LevelUpBrainrot", uid)
				if ok then
					UIKit.sound("Coins", 0.5)
				end
			end)
			action("Lock", C.PanelLight, 4, function(uid)
				local inst = ClientState.inventory[uid]
				if inst then
					Notifications.call("LockBrainrot", uid, not inst.locked)
				end
			end)
			action("Sell", C.Bad, 5, function(uid)
				local ok, total = Notifications.call("SellBrainrots", { uid })
				if ok then
					Notifications.toast(`Sold for ${Format.short(total)}`, C.Coins)
				end
			end)
			return {
				refresh = CollectionUI.refresh,
			}
		end,
	})
	ClientState.InventoryChanged:Connect(queueRefresh)
	ClientState.Changed:Connect(function(key)
		if key == "equipped" or key == "zoo" or key == "index" then
			queueRefresh()
		end
	end)
	Bus.ViewBrainrot:Connect(function(uid: string?)
		pendingUid = uid
		if Windows.isOpen("Collection") then
			CollectionUI.refresh()
		else
			Windows.open("Collection")
		end
	end)
end

return CollectionUI
