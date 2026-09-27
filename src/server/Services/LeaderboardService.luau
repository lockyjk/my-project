--!strict
-- Leaderboards: in-server leaderstats plus global OrderedDataStore boards (Lifetime Charge,
-- Ascensions, Rarest Stormling). Writes are throttled per player; reads are cached and
-- shown on the hub boards and in the Leaderboards window.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local LeaderboardService = {}

export type Entry = { rank: number, userId: number, name: string, value: number, text: string }

local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { Entry } } = {}
local names: { [number]: string } = {}
local lastWrite: { [Player]: number } = {}
local enabled = true

local function statValue(data: Types.ProfileData, stat: string): number
	if stat == "LifetimeCharge" then
		return data.LifetimeCharge
	elseif stat == "Ascensions" then
		return data.Ascensions
	end
	return data.Stats[stat] or 0
end

local function encode(board: any, value: number): number
	if board.log then
		return EconomyMath.encodeLog(value)
	end
	return math.floor(value)
end

local function display(board: any, stored: number): string
	if board.log then
		return Format.short(EconomyMath.decodeLog(stored))
	elseif board.id == "Rarest" then
		local rarity = Config.Rarities[math.floor(stored / 1000)]
		local tier = math.floor(stored % 1000 / 100)
		return (if rarity then rarity.name else "?") .. " " .. string.rep("★", math.max(0, tier - 1))
	end
	return Format.commas(stored)
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and name then name else `Player {userId}`
	return names[userId]
end

-------------------------------------------------------------------------------
-- leaderstats
-------------------------------------------------------------------------------

local function setupLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local charge = Instance.new("StringValue")
	charge.Name = "Charge"
	charge.Parent = folder
	local asc = Instance.new("IntValue")
	asc.Name = "Ascensions"
	asc.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(player: Player)
	local data = DataService.get(player)
	local folder = player:FindFirstChild("leaderstats")
	if not data or not folder then
		return
	end
	local charge = folder:FindFirstChild("Charge") :: StringValue?
	local asc = folder:FindFirstChild("Ascensions") :: IntValue?
	if charge then
		charge.Value = Format.short(data.Charge)
	end
	if asc then
		asc.Value = data.Ascensions
	end
end

-------------------------------------------------------------------------------
-- Global boards
-------------------------------------------------------------------------------

local function write(player: Player)
	local data = DataService.get(player)
	if not data or not enabled then
		return
	end
	for _, board in Config.Leaderboards.Boards do
		local store = stores[board.id]
		local value = encode(board, statValue(data, board.stat))
		if store and value > 0 then
			pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
		end
	end
	lastWrite[player] = os.clock()
end

local function refresh()
	for _, board in Config.Leaderboards.Boards do
		local store = stores[board.id]
		if store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, Config.Leaderboards.Top)
			end)
			if ok and pages then
				local entries: { Entry } = {}
				for i, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key) or 0
					table.insert(entries, {
						rank = i,
						userId = userId,
						name = nameOf(userId),
						value = item.value,
						text = display(board, item.value),
					})
				end
				cache[board.id] = entries
			end
		end
	end
	LeaderboardService.renderBoards()
end

-- Draw the top 10 on the physical hub boards
function LeaderboardService.renderBoards()
	for _, part in CollectionService:GetTagged("LeaderboardBoard") do
		local boardId = part:GetAttribute("BoardId")
		local board = nil
		for _, b in Config.Leaderboards.Boards do
			if b.id == boardId then
				board = b
			end
		end
		if board and part:IsA("BasePart") then
			local gui = part:FindFirstChild("Board") :: SurfaceGui?
			if not gui then
				local g = Instance.new("SurfaceGui")
				g.Name = "Board"
				g.Face = Enum.NormalId.Front
				g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				g.PixelsPerStud = 25
				g.LightInfluence = 0
				g.Parent = part
				local text = Instance.new("TextLabel")
				text.Name = "Text"
				text.BackgroundTransparency = 1
				text.Size = UDim2.fromScale(1, 1)
				text.Font = Theme.Font
				text.TextScaled = true
				text.RichText = true
				text.TextColor3 = Theme.Colors.Text
				text.TextStrokeTransparency = 0
				text.Parent = g
				gui = g
			end
			local lines = { `<font color="#FFD633">{Theme.Icons.Leaderboard} {board.name}</font>` }
			local entries: { Entry } = cache[board.id] or {}
			for i, e in entries do
				if i > 10 then
					break
				end
				table.insert(lines, `{e.rank}. {e.name}  <font color="#6ED2FF">{e.text}</font>`)
			end
			if #lines == 1 then
				table.insert(lines, "Be the first!")
			end
			local label = (gui :: SurfaceGui):FindFirstChild("Text") :: TextLabel
			label.Text = table.concat(lines, "\n")
		end
	end
end

function LeaderboardService.snapshot(): { [string]: any }
	local server = {}
	for _, p in Players:GetPlayers() do
		local data = DataService.get(p)
		if data then
			table.insert(server, {
				name = p.DisplayName,
				userId = p.UserId,
				charge = data.LifetimeCharge,
				ascensions = data.Ascensions,
				best = data.BestPet,
				bestTier = data.BestPetTier,
			})
		end
	end
	local boards = {}
	for _, board in Config.Leaderboards.Boards do
		boards[board.id] = { name = board.name, entries = cache[board.id] or {} }
	end
	return { global = boards, server = server }
end

function LeaderboardService.init()
	local ok = pcall(function()
		for _, board in Config.Leaderboards.Boards do
			stores[board.id] = DataStoreService:GetOrderedDataStore(board.store)
		end
	end)
	enabled = ok and not (RunService:IsStudio() and DataService.IsMock)
end

function LeaderboardService.start()
	Net.Server.handle("GetLeaderboards", function()
		return LeaderboardService.snapshot()
	end)
	DataService.Loaded:Connect(function(player)
		setupLeaderstats(player)
		updateLeaderstats(player)
		lastWrite[player] = os.clock()
	end)
	DataService.Removing:Connect(function(player)
		write(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastWrite[player] = nil
	end)
	GameEvents.ChargeEarned:Connect(updateLeaderstats)
	GameEvents.ChargeSpent:Connect(updateLeaderstats)
	GameEvents.Ascended:Connect(function(player)
		updateLeaderstats(player)
		write(player)
	end)

	task.spawn(function()
		while true do
			refresh()
			task.wait(Config.Leaderboards.RefreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in Players:GetPlayers() do
				if os.clock() - (lastWrite[player] or 0) >= Config.Leaderboards.WriteSeconds then
					write(player)
				end
			end
		end
	end)
end

return LeaderboardService
