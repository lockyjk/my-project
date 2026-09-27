--!strict
-- Island building: decoration shop (with passive boosts), island expansion, and a simple
-- tap-to-place build mode on the player's own sky island grid.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local BuildUI = {}
local C = Theme.Colors

local building = false
local enteredAt = 0
local selectedDeco: string? = nil
local rotation = 0
local removeMode = false
local cursor: { x: number, z: number }? = nil
local gridFolder: Folder? = nil
local ghost: Part? = nil
local bar: Frame
local barLabel: TextLabel

local function call(remote: string, ...: any): boolean
	local ok, msg = Net.Client.invoke(remote, ...)
	if not ok and msg then
		Effects.toast(tostring(msg), C.Bad, 1.8)
	end
	return ok == true
end

local function boostText(def: Types.DecorationDef): string
	if not def.boost then
		return "Decoration"
	end
	local b = def.boost
	local amount = if b.stat == "OfflineHours" then `+{b.amount}h offline cap` else `+{math.floor(b.amount * 100)}% {b.stat}`
	return `{amount} (up to {def.maxBoosting or 1})`
end

local function available(decoId: string): number
	local island = ClientState.get("Island") or { Owned = {}, Placed = {} }
	local placed = 0
	for _, p in island.Placed do
		if p.id == decoId then
			placed += 1
		end
	end
	return (island.Owned[decoId] or 0) - placed
end

local function plotLayout(): WorldLayout.PlotLayout?
	local plot = ClientState.get("Plot")
	return if plot then WorldLayout.Plots[plot] else nil
end

local function updateBar()
	if not building then
		return
	end
	if removeMode then
		barLabel.Text = "Tap a decoration to put it back in your inventory"
	elseif selectedDeco then
		local def = Defs.Decoration[selectedDeco]
		barLabel.Text = `{def.name} (x{available(selectedDeco)}) - tap a tile, then Place`
	else
		barLabel.Text = "Pick a decoration in the Build menu"
	end
end

local function updateGhost()
	local layout = plotLayout()
	if not ghost or not layout then
		return
	end
	if removeMode or not selectedDeco or not cursor then
		ghost.Transparency = 1
		return
	end
	local def = Defs.Decoration[selectedDeco]
	local w, d = WorldLayout.footprint(def.size, rotation)
	local c = cursor :: { x: number, z: number }
	local a = WorldLayout.cellLocal(c.x, c.z)
	local b = WorldLayout.cellLocal(c.x + w - 1, c.z + d - 1)
	local cell = Config.Island.CellSize
	local island = ClientState.get("Island")
	local ok = WorldLayout.canPlace(island.Size, island.Placed, selectedDeco, c.x, c.z, rotation)
	ghost.Size = Vector3.new(w * cell - 0.5, def.height, d * cell - 0.5)
	ghost.CFrame = layout.cframe * CFrame.new((a + b) / 2 + Vector3.new(0, def.height / 2 + 1, 0))
	ghost.Color = if ok then C.Good else C.Bad
	ghost.Transparency = 0.5
end

local function buildGrid()
	if gridFolder then
		gridFolder:Destroy()
	end
	local layout = plotLayout()
	local island = ClientState.get("Island")
	if not layout or not island then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "BuildGrid"
	local lo, hi = WorldLayout.unlockedBounds(island.Size)
	local cell = Config.Island.CellSize
	for x = lo, hi - 1 do
		for z = lo, hi - 1 do
			local p = Instance.new("Part")
			p.Name = `{x}_{z}`
			p.Anchored = true
			p.CanCollide = false
			p.Size = Vector3.new(cell - 0.6, 0.3, cell - 0.6)
			p.CFrame = layout.cframe * CFrame.new(WorldLayout.cellLocal(x, z) + Vector3.new(0, 1.1, 0))
			p.Color = C.Build
			p.Material = Enum.Material.Neon
			p.Transparency = 0.75
			p:SetAttribute("X", x)
			p:SetAttribute("Z", z)
			p.Parent = folder
		end
	end
	folder.Parent = Workspace
	gridFolder = folder
end

function BuildUI.enter()
	if not plotLayout() then
		Effects.toast("Your island isn't ready yet", C.Bad)
		return
	end
	Windows.close()
	-- Teleport may fail on cooldown; that's fine if we're already home
	Net.Client.invoke("Teleport", "Home")
	building = true
	enteredAt = os.clock()
	removeMode = false
	buildGrid()
	local g = Instance.new("Part")
	g.Name = "BuildGhost"
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.Material = Enum.Material.ForceField
	g.Transparency = 1
	g.Parent = Workspace
	ghost = g
	bar.Visible = true
	updateBar()
end

function BuildUI.exit()
	building = false
	cursor = nil
	if gridFolder then
		gridFolder:Destroy()
		gridFolder = nil
	end
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	bar.Visible = false
end

local function onTap(screenPos: Vector2)
	if not building then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	if removeMode then
		local world = Workspace:FindFirstChild("World")
		local plots = world and world:FindFirstChild("Plots")
		local plot = plots and plots:FindFirstChild(`Plot{ClientState.get("Plot")}`)
		local buildModel = plot and plot:FindFirstChild("Build")
		if not buildModel then
			return
		end
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { buildModel }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
		local index = hit and tonumber(string.match(hit.Instance.Name, "^Deco(%d+)$"))
		if index then
			if call("RemoveDecoration", index) then
				Effects.burst(hit.Position, C.Build, 14)
			end
		end
		return
	end
	if not gridFolder then
		return
	end
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { gridFolder }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if hit then
		local x, z = hit.Instance:GetAttribute("X"), hit.Instance:GetAttribute("Z")
		if type(x) == "number" and type(z) == "number" then
			cursor = { x = x, z = z }
			updateGhost()
		end
	end
end

local function buildBar()
	bar = UIKit.panel({
		Name = "BuildBar",
		Size = UDim2.fromOffset(760, 90),
		Position = UDim2.new(0.5, 0, 1, -76),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Build,
		Visible = false,
		ZIndex = 10,
		Parent = HUD.root(),
	})
	barLabel = UIKit.label({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 2), MaxTextSize = 20, ZIndex = 11, Parent = bar })
	local row = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 30), ZIndex = 11, Parent = bar })
	UIKit.list(row, 10, true)
	UIKit.button({
		Text = "Rotate",
		Color = C.Travel,
		Size = UDim2.fromOffset(130, 54),
		ZIndex = 12,
		Parent = row,
		OnClick = function()
			rotation = (rotation + 1) % 4
			updateGhost()
		end,
	})
	UIKit.button({
		Text = "Place",
		Color = C.Good,
		Size = UDim2.fromOffset(150, 54),
		ZIndex = 12,
		Parent = row,
		OnClick = function()
			if selectedDeco and cursor then
				local c = cursor :: { x: number, z: number }
				if call("PlaceDecoration", selectedDeco, c.x, c.z, rotation) then
					Effects.shake(0.2)
					UIKit.sound("Upgrade")
				end
			else
				Effects.toast("Tap a glowing tile first", C.Warn)
			end
		end,
	})
	local removeBtn = UIKit.button({
		Text = "Remove",
		Color = C.Bad,
		Size = UDim2.fromOffset(150, 54),
		ZIndex = 12,
		Parent = row,
	})
	removeBtn.Activated:Connect(function()
		removeMode = not removeMode
		UIKit.setButtonText(removeBtn, if removeMode then "Placing" else "Remove")
		updateBar()
		updateGhost()
	end)
	UIKit.button({
		Text = "Menu",
		Color = C.PanelLight,
		Size = UDim2.fromOffset(120, 54),
		ZIndex = 12,
		Parent = row,
		OnClick = function()
			Windows.open("Build")
		end,
	})
	UIKit.button({
		Text = "Done",
		Color = C.PanelDark,
		Size = UDim2.fromOffset(120, 54),
		ZIndex = 12,
		Parent = row,
		OnClick = BuildUI.exit,
	})
end

function BuildUI.start()
	buildBar()
	Windows.register("Build", {
		title = "Build Your Island",
		icon = "Build",
		color = C.Build,
		size = Vector2.new(860, 560),
		build = function(content: Frame)
			local top = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), Parent = content })
			local sizeLabel = UIKit.label({ Size = UDim2.new(0.45, 0, 1, 0), XAlign = Enum.TextXAlignment.Left, MaxTextSize = 24, Parent = top })
			local expand = UIKit.button({
				Color = C.Good,
				Size = UDim2.fromOffset(250, 62),
				Position = UDim2.new(0.45, 0, 0, 4),
				Parent = top,
				OnClick = function()
					if call("BuyIslandSize") then
						Effects.banner("Island expanded!", C.Build)
						if building then
							buildGrid()
						end
					end
				end,
			})
			UIKit.button({
				Text = "Build Mode",
				Color = C.Build,
				Size = UDim2.fromOffset(200, 62),
				Position = UDim2.new(1, 0, 0, 4),
				AnchorPoint = Vector2.new(1, 0),
				Parent = top,
				OnClick = BuildUI.enter,
			})
			local list = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -78), Position = UDim2.fromOffset(0, 78), Parent = content })
			UIKit.grid(list, Vector2.new(260, 170), 10)
			local refreshers: { () -> () } = {}
			for i, def in Config.Decorations do
				local card = UIKit.panel({ Color = if def.boost then Theme.darken(C.Build, 0.3) else C.PanelLight, LayoutOrder = i, Parent = list })
				local swatch = UIKit.new("Frame", { BackgroundColor3 = def.color, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 10), Parent = card })
				UIKit.corner(swatch, if def.shape == "Ball" then 22 else 8)
				UIKit.stroke(swatch, 3)
				UIKit.label({ Text = def.name, Size = UDim2.new(1, -70, 0, 30), Position = UDim2.fromOffset(62, 8), XAlign = Enum.TextXAlignment.Left, MaxTextSize = 22, Parent = card })
				UIKit.label({
					Text = boostText(def),
					Size = UDim2.new(1, -70, 0, 22),
					Position = UDim2.fromOffset(62, 38),
					XAlign = Enum.TextXAlignment.Left,
					Color = if def.boost then C.Charge else C.TextDim,
					Font = Theme.FontBody,
					MaxTextSize = 16,
					Parent = card,
				})
				local owned = UIKit.label({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 66), XAlign = Enum.TextXAlignment.Left, Font = Theme.FontBody, MaxTextSize = 16, Parent = card })
				local buy = UIKit.button({
					Size = UDim2.new(0.55, -14, 0, 56),
					Position = UDim2.new(0, 10, 1, -64),
					Color = C.Good,
					Parent = card,
					OnClick = function()
						call("BuyDecoration", def.id)
					end,
				})
				UIKit.button({
					Text = "Place",
					Size = UDim2.new(0.45, -10, 0, 56),
					Position = UDim2.new(0.55, 0, 1, -64),
					Color = C.Build,
					Parent = card,
					OnClick = function()
						if available(def.id) <= 0 then
							Effects.toast("Buy one first", C.Warn)
							return
						end
						selectedDeco = def.id
						removeMode = false
						if building then
							Windows.close()
							updateBar()
							updateGhost()
						else
							BuildUI.enter()
						end
					end,
				})
				table.insert(refreshers, function()
					local unlocked = ClientState.get("UnlockedZones") or {}
					local zone = def.unlockZone and Defs.MainZones[def.unlockZone]
					local locked = zone ~= nil and not unlocked[(zone :: Types.ZoneDef).id]
					owned.Text = `In storage: {math.max(0, available(def.id))}`
					if locked then
						UIKit.setButtonText(buy, `{Theme.Icons.Lock} {(zone :: Types.ZoneDef).name}`)
						UIKit.setButtonColor(buy, C.PanelDark)
					else
						UIKit.setButtonText(buy, `{Theme.Icons.Charge}{Format.short(def.cost)}`)
						UIKit.setButtonColor(buy, if (ClientState.get("Charge") or 0) >= def.cost then C.Good else C.PanelDark)
					end
				end)
			end
			local function refresh()
				local island = ClientState.get("Island") or { Size = 1 }
				local cur = Config.Island.Sizes[island.Size]
				local nextSize = Config.Island.Sizes[island.Size + 1]
				sizeLabel.Text = `Island {cur.cells}x{cur.cells} · {#(island.Placed or {})}/{Config.Island.MaxPlaced} placed`
				if nextSize then
					UIKit.setButtonText(expand, `Expand {nextSize.cells}x{nextSize.cells} {Theme.Icons.Charge}{Format.short(nextSize.cost)}`)
					expand.Visible = true
				else
					expand.Visible = false
				end
				for _, r in refreshers do
					r()
				end
			end
			for _, key in { "Island", "Charge" } do
				ClientState.observe(key, function()
					if Windows.isOpen("Build") then
						refresh()
					end
				end)
			end
			return { refresh = refresh }
		end,
	})

	ClientState.observe("Island", function()
		if building then
			updateBar()
			updateGhost()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not building then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			onTap(Vector2.new(input.Position.X, input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.R then
			rotation = (rotation + 1) % 4
			updateGhost()
		end
	end)
	-- Leaving your island ends build mode
	task.spawn(function()
		while true do
			task.wait(1)
			if building and os.clock() - enteredAt > 4 then
				local character = Players.LocalPlayer.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp and WorldLayout.plotAt(hrp.Position) ~= ClientState.get("Plot") then
					BuildUI.exit()
				end
			end
		end
	end)
end

function BuildUI.isBuilding(): boolean
	return building
end

return BuildUI
