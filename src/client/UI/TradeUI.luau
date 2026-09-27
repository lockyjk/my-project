--!strict
-- Trading UI, built to be scam-safe:
--   * each side's offer is shown with rarity-coloured borders, tier stars and power
--   * anything the partner ADDS is highlighted "NEW" for a while; every change is in the log
--   * any change un-readies both players (server enforced)
--   * Confirm only unlocks a few seconds after both are Ready, with a final summary
--   * warnings when the other side offers nothing

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local PetPortrait = require(script.Parent.PetPortrait)
local UIKit = require(script.Parent.UIKit)
local Windows = require(script.Parent.Windows)

local TradeUI = {}
local C = Theme.Colors

local state: any = nil
local newUntil: { [string]: number } = {} -- partner uids -> highlight expiry
local render: (() -> ())? = nil

local function call(remote: string, ...: any): boolean
	local ok, msg = Net.Client.invoke(remote, ...)
	if not ok and msg then
		Effects.toast(tostring(msg), C.Bad, 2)
	end
	return ok == true
end

local function summary(pets: { any }): string
	if #pets == 0 then
		return "nothing"
	end
	local counts: { [string]: number } = {}
	local power = 0
	for _, p in pets do
		local def = Defs.Pet[p.id]
		if def then
			counts[def.rarity] = (counts[def.rarity] or 0) + 1
			power += EconomyMath.petPower(p.id, p.tier)
		end
	end
	local parts = {}
	for _, r in Config.Rarities do
		if counts[r.id] then
			table.insert(parts, `{counts[r.id]} {r.name}`)
		end
	end
	return `{table.concat(parts, ", ")} ({Format.percentBonus(power)} power)`
end

local function inviteBanner(fromUserId: number, fromName: string)
	local panel = UIKit.panel({
		Size = UDim2.fromOffset(460, 130),
		Position = UDim2.new(0.5, 0, 0, 140),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Trade,
		ZIndex = 20,
		Parent = HUD.root(),
	})
	UIKit.label({ Text = `{fromName} wants to trade!`, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 6), ZIndex = 21, Parent = panel })
	local function respond(accept: boolean)
		panel:Destroy()
		call("TradeRespond", fromUserId, accept)
	end
	UIKit.button({
		Text = "Accept",
		Color = C.Good,
		Size = UDim2.fromOffset(190, 56),
		Position = UDim2.new(0, 16, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 21,
		Parent = panel,
		OnClick = function()
			respond(true)
		end,
	})
	UIKit.button({
		Text = "Decline",
		Color = C.Bad,
		Size = UDim2.fromOffset(190, 56),
		Position = UDim2.new(1, -16, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 21,
		Parent = panel,
		OnClick = function()
			respond(false)
		end,
	})
	UIKit.pop(panel)
	task.delay(Config.Trade.RequestTimeout, function()
		if panel.Parent then
			panel:Destroy()
		end
	end)
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

function TradeUI.start()
	Windows.register("Trade", {
		title = "Trade",
		icon = "Trade",
		color = C.Trade,
		size = Vector2.new(960, 580),
		build = function(content: Frame)
			local body = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })

			local function lobby()
				UIKit.label({
					Text = `Pick a player to trade with. Both of you need {Config.Trade.MinPlayMinutes} minutes of play time.`,
					Size = UDim2.new(1, 0, 0, 34),
					Color = C.TextDim,
					MaxTextSize = 22,
					Parent = body,
				})
				local list = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = body })
				UIKit.list(list, 8)
				local any = false
				for i, p in Players:GetPlayers() do
					if p ~= Players.LocalPlayer then
						any = true
						local row = UIKit.panel({ Size = UDim2.new(1, -10, 0, 64), Color = C.PanelLight, LayoutOrder = i, Parent = list })
						UIKit.label({ Text = p.DisplayName, Size = UDim2.new(1, -220, 1, -10), Position = UDim2.fromOffset(14, 5), XAlign = Enum.TextXAlignment.Left, Parent = row })
						UIKit.button({
							Text = "Request",
							Color = C.Trade,
							Size = UDim2.fromOffset(180, 52),
							Position = UDim2.new(1, -10, 0.5, 0),
							AnchorPoint = Vector2.new(1, 0.5),
							Parent = row,
							OnClick = function()
								if call("TradeRequest", p.UserId) then
									Effects.toast(`Trade request sent to {p.DisplayName}`, C.Trade)
								end
							end,
						})
					end
				end
				if not any then
					UIKit.label({ Text = "Nobody else is here yet. Invite a friend!", Size = UDim2.new(1, 0, 0, 60), Parent = list })
				end
			end

			local function offerGrid(parent: Frame, pets: { any }, highlight: boolean, removable: boolean)
				local grid = UIKit.scroll({ Size = UDim2.new(1, 0, 1, 0), Parent = parent })
				UIKit.grid(grid, Vector2.new(96, 116), 6)
				for i, p in pets do
					local card = PetPortrait.card({
						petId = p.id,
						tier = p.tier,
						caption = Format.percentBonus(EconomyMath.petPower(p.id, p.tier)),
						order = i,
						parent = grid,
						size = UDim2.fromOffset(96, 116),
						onClick = if removable
							then function()
								local uids = {}
								for _, other in state.mine do
									if other.uid ~= p.uid then
										table.insert(uids, other.uid)
									end
								end
								call("TradeSetOffer", uids)
							end
							else nil,
					})
					if highlight and (newUntil[p.uid] or 0) > os.clock() then
						UIKit.stroke(card, 6, C.Charge)
						UIKit.label({ Text = "NEW", Color = C.Charge, Size = UDim2.fromOffset(60, 24), Position = UDim2.fromOffset(2, 2), ZIndex = 12, Parent = card })
					end
					if p.source == "RobuxEgg" then
						UIKit.label({ Text = "R$", Color = C.Robux, Size = UDim2.fromOffset(30, 22), Position = UDim2.new(1, -32, 0, 2), ZIndex = 12, Parent = card })
					end
				end
			end

			local function active()
				local partner = state.partner
				-- Columns
				local mineCol = UIKit.panel({ Size = UDim2.new(0.5, -6, 0, 250), Color = C.PanelDark, Parent = body })
				local theirCol = UIKit.panel({ Size = UDim2.new(0.5, -6, 0, 250), Position = UDim2.new(0.5, 6, 0, 0), Color = C.PanelDark, Parent = body })
				UIKit.label({ Text = `You give{if state.myReady then " " .. Theme.Icons.Check else ""}`, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 2), MaxTextSize = 24, Parent = mineCol })
				UIKit.label({ Text = `{partner.name} gives{if state.theirReady then " " .. Theme.Icons.Check else ""}`, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 2), MaxTextSize = 24, Parent = theirCol })
				local mineGrid = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, -64), Position = UDim2.fromOffset(4, 32), Parent = mineCol })
				local theirGrid = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, -64), Position = UDim2.fromOffset(4, 32), Parent = theirCol })
				offerGrid(mineGrid, state.mine, false, state.state == "Negotiating" or state.state == "Confirming")
				offerGrid(theirGrid, state.theirs, true, false)
				UIKit.label({ Text = summary(state.mine), Size = UDim2.new(1, -10, 0, 28), Position = UDim2.new(0, 5, 1, -30), Color = C.TextDim, Font = Theme.FontBody, MaxTextSize = 17, Parent = mineCol })
				UIKit.label({ Text = summary(state.theirs), Size = UDim2.new(1, -10, 0, 28), Position = UDim2.new(0, 5, 1, -30), Color = C.TextDim, Font = Theme.FontBody, MaxTextSize = 17, Parent = theirCol })

				-- Your inventory picker (tap to add)
				local picker = UIKit.panel({ Size = UDim2.new(0.5, -6, 0, 200), Position = UDim2.fromOffset(0, 258), Color = C.PanelLight, Parent = body })
				UIKit.label({ Text = "Tap your Stormlings to add them", Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 2), MaxTextSize = 20, Parent = picker })
				local pickGrid = UIKit.scroll({ Size = UDim2.new(1, -8, 1, -32), Position = UDim2.fromOffset(4, 30), Parent = picker })
				UIKit.grid(pickGrid, Vector2.new(84, 100), 6)
				local offered = {}
				for _, p in state.mine do
					offered[p.uid] = true
				end
				local myPets = ClientState.get("Pets") or {}
				local order = 0
				for uid, pet in myPets do
					local def = Defs.Pet[pet.id]
					if not offered[uid] and def and def.tradeable ~= false and not pet.locked then
						order += 1
						PetPortrait.card({
							petId = pet.id,
							tier = pet.tier,
							caption = def.name,
							order = order,
							parent = pickGrid,
							size = UDim2.fromOffset(84, 100),
							onClick = function()
								if #state.mine >= Config.Trade.MaxPets then
									Effects.toast(`Up to {Config.Trade.MaxPets} Stormlings per trade`, C.Bad)
									return
								end
								local uids = {}
								for _, p in state.mine do
									table.insert(uids, p.uid)
								end
								table.insert(uids, uid)
								call("TradeSetOffer", uids)
							end,
						})
					end
				end

				-- Change log
				local logPanel = UIKit.panel({ Size = UDim2.new(0.5, -6, 0, 200), Position = UDim2.new(0.5, 6, 0, 258), Color = C.PanelDark, Parent = body })
				local log = UIKit.scroll({ Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), Parent = logPanel })
				UIKit.list(log, 2).HorizontalAlignment = Enum.HorizontalAlignment.Left
				for i, line in state.log do
					UIKit.label({ Text = line, Size = UDim2.new(1, -10, 0, 24), XAlign = Enum.TextXAlignment.Left, Font = Theme.FontBody, MaxTextSize = 16, LayoutOrder = i, Parent = log })
				end
				log.CanvasPosition = Vector2.new(0, 10000)

				-- Actions
				local bar = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0, 0, 1, -80), Parent = body })
				UIKit.list(bar, 12, true)
				local warning = ""
				if #state.theirs == 0 and #state.mine > 0 then
					warning = `{Theme.Icons.Lock} {partner.name} is offering NOTHING`
				end
				if state.state == "Confirming" then
					local left = state.confirmAt - DateTime.now().UnixTimestamp
					UIKit.button({
						Text = if state.myConfirmed then "Waiting..." elseif left > 0 then `Review... {left}` else "CONFIRM TRADE",
						Color = if left > 0 or state.myConfirmed then C.PanelDark else C.Good,
						Size = UDim2.fromOffset(300, 72),
						Parent = bar,
						OnClick = function()
							call("TradeConfirm")
						end,
					})
				else
					UIKit.button({
						Text = if state.myReady then "Not ready" else "Ready",
						Color = if state.myReady then C.PanelLight else C.Good,
						Size = UDim2.fromOffset(240, 72),
						Parent = bar,
						OnClick = function()
							call("TradeReady", not state.myReady)
						end,
					})
				end
				UIKit.button({
					Text = "Cancel",
					Color = C.Bad,
					Size = UDim2.fromOffset(180, 72),
					Parent = bar,
					OnClick = function()
						call("TradeCancel")
					end,
				})
				if warning ~= "" then
					UIKit.label({ Text = warning, Color = C.Warn, Size = UDim2.fromOffset(380, 60), MaxTextSize = 24, Parent = bar })
				end
			end

			render = function()
				clear(body)
				if state and (state.state == "Negotiating" or state.state == "Confirming") then
					active()
				else
					lobby()
				end
			end
			return {
				refresh = function()
					(render :: () -> ())()
				end,
			}
		end,
	})

	Net.Client.on("TradeInvite", inviteBanner)
	Net.Client.on("TradeUpdate", function(newState: any)
		-- Highlight partner additions
		if state and state.id == newState.id then
			local before = {}
			for _, p in state.theirs do
				before[p.uid] = true
			end
			for _, p in newState.theirs do
				if not before[p.uid] then
					newUntil[p.uid] = os.clock() + 10
					Effects.toast(`{newState.partner.name} changed their offer - check it!`, C.Warn, 2)
				end
			end
			if #newState.theirs < #state.theirs then
				Effects.toast(`{newState.partner.name} removed something from their offer!`, C.Warn, 2.5)
			end
		end
		state = newState
		if newState.state == "Done" then
			Effects.banner("Trade complete!", C.Good)
			state = nil
			Windows.close()
			return
		elseif newState.state == "Cancelled" then
			Effects.toast(newState.log[#newState.log] or "Trade cancelled", C.Bad)
			state = nil
			if Windows.isOpen("Trade") and render then
				render()
			end
			return
		end
		if not Windows.isOpen("Trade") then
			Windows.open("Trade")
		elseif render then
			render()
		end
	end)
	-- live countdown on the confirm button
	task.spawn(function()
		while true do
			task.wait(1)
			if state and state.state == "Confirming" and Windows.isOpen("Trade") and render then
				render()
			end
		end
	end)
	-- Closing the window during a trade cancels it (no half-open trades)
	Windows.Closed:Connect(function(name)
		if name == "Trade" and state then
			call("TradeCancel")
		end
	end)
end

return TradeUI
