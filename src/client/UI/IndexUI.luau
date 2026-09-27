--!strict
-- Stormling Index: collection log per egg. Undiscovered pets show as silhouettes.
-- Completing an egg's page gives a permanent Charge bonus (shown per page).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local PetPortrait = require(script.Parent.PetPortrait)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local IndexUI = {}
local C = Theme.Colors

function IndexUI.start()
	Windows.register("Index", {
		title = "Stormling Index",
		icon = "Index",
		color = C.Index,
		size = Vector2.new(900, 560),
		build = function(content: Frame)
			local eggs = {}
			for _, egg in Config.Eggs do
				table.insert(eggs, egg)
			end
			local selected = eggs[1].id
			local left = UIKit.scroll({ Size = UDim2.new(0, 230, 1, 0), Parent = content })
			UIKit.list(left, 6)
			local right = UIKit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -240, 1, 0),
				Position = UDim2.fromOffset(240, 0),
				Parent = content,
			})
			local header = UIKit.label({ Size = UDim2.new(1, 0, 0, 40), MaxTextSize = 30, Parent = right })
			local sub = UIKit.label({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 40), Color = C.TextDim, MaxTextSize = 20, Parent = right })
			local grid = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 76), Parent = right })
			UIKit.grid(grid, Vector2.new(120, 140), 10)
			local eggButtons: { [string]: TextButton } = {}
			local render: () -> ()

			local function pageCount(eggId: string): (number, number)
				local index = ClientState.get("Index") or {}
				local found, total = 0, 0
				for _, entry in Defs.Egg[eggId].pets do
					total += 1
					if index[entry.pet] then
						found += 1
					end
				end
				return found, total
			end

			render = function()
				local index = ClientState.get("Index") or {}
				local rewards = ClientState.get("IndexRewards") or {}
				local totalFound, totalAll = 0, 0
				for _, egg in eggs do
					local found, total = pageCount(egg.id)
					totalFound += found
					totalAll += total
					local b = eggButtons[egg.id]
					UIKit.setButtonText(b, `{egg.name} {found}/{total}`)
					UIKit.setButtonColor(b, if egg.id == selected then C.Index elseif rewards[egg.id] then C.Quests else C.PanelLight)
				end
				local egg = Defs.Egg[selected]
				local found, total = pageCount(selected)
				header.Text = `{egg.name}  {found}/{total}`
				sub.Text = if egg.currency == "Robux"
					then `Collection: {totalFound}/{totalAll} · Paid egg pages give no bonus`
					elseif rewards[selected] then `Collection: {totalFound}/{totalAll} · Complete! +{math.floor(Config.Index.ChargeBonusPerEgg * 100)}% Charge`
					else `Collection: {totalFound}/{totalAll} · Complete this page for +{math.floor(Config.Index.ChargeBonusPerEgg * 100)}% Charge forever`
				for _, c in grid:GetChildren() do
					if c:IsA("GuiObject") then
						c:Destroy()
					end
				end
				for i, entry in egg.pets do
					local def = Defs.Pet[entry.pet]
					PetPortrait.card({
						petId = entry.pet,
						hidden = not index[entry.pet],
						caption = if index[entry.pet] then def.name else nil,
						order = i,
						parent = grid,
						size = UDim2.fromOffset(120, 140),
					})
				end
			end

			for i, egg in eggs do
				eggButtons[egg.id] = UIKit.button({
					Text = egg.name,
					Color = C.PanelLight,
					Size = UDim2.new(1, -10, 0, 52),
					LayoutOrder = i,
					MaxTextSize = 22,
					Parent = left,
					OnClick = function()
						selected = egg.id
						render()
					end,
				})
			end
			for _, key in { "Index", "IndexRewards" } do
				ClientState.observe(key, function()
					if Windows.isOpen("Index") then
						render()
					end
				end)
			end
			return { refresh = render }
		end,
	})
end

return IndexUI
