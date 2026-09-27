--!strict
-- Renders every player's equipped Stormlings (from the "Pets" player attribute) as
-- client-side models that hop along behind their owner in a fan formation.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Defs"))

local ClientState = require(script.Parent.ClientState)
local ModelFactory = require(script.Parent.ModelFactory)

local PetFollowController = {}

type Follower = { model: Model, id: string, tier: number, cf: CFrame, phase: number, height: number }
local followers: { [Player]: { Follower } } = {}
local folder: Folder

local function petSize(petId: string, tier: number): number
	local def = Defs.Pet[petId]
	local rarityBoost = 1 + Defs.rarityOrder(def.rarity) * 0.06
	return 2.4 * Config.Fusion.Tiers[tier].scale * rarityBoost
end

local function clear(player: Player)
	local list = followers[player]
	if list then
		for _, f in list do
			f.model:Destroy()
		end
	end
	followers[player] = nil
end

local function rebuild(player: Player)
	clear(player)
	local raw = player:GetAttribute("Pets")
	if type(raw) ~= "string" then
		return
	end
	local settings = ClientState.get("Settings")
	if player ~= Players.LocalPlayer and settings and settings.HidePets then
		return
	end
	local ok, list = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	local out: { Follower } = {}
	for _, entry in list do
		local petId, tier = entry[1], entry[2]
		local def = Defs.Pet[petId]
		if def then
			local t = math.clamp(tonumber(tier) or 1, 1, #Config.Fusion.Tiers)
			local rarity = Defs.Rarity[def.rarity]
			local size = petSize(petId, t)
			local model = ModelFactory.creature({
				id = petId,
				shape = def.shape,
				size = size,
				color = def.color,
				accent = def.accent,
				pet = true,
				glow = rarity.order >= 5 or t >= 3,
				aura = if rarity.order >= 4 or t >= 2 then rarity.color else nil,
				tierGlow = (t - 1) / 3,
			})
			model.Parent = folder
			table.insert(out, { model = model, id = petId, tier = t, cf = CFrame.new(), phase = math.random() * 6, height = size })
		end
	end
	followers[player] = out
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

local function step(dt: number)
	local t = os.clock()
	local alpha = 1 - math.exp(-dt * 8)
	for player, list in followers do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local n = #list
			local scale = character and (character :: Model):GetScale() or 1
			for i, f in list do
				local spread = if n > 1 then (i - 1) / (n - 1) - 0.5 else 0
				local row = math.floor((i - 1) / 5)
				local offset = Vector3.new(spread * math.min(n, 5) * 3.2, 0, 5 + row * 4) * scale
				local target = hrp.CFrame * CFrame.new(offset)
				local moving = hrp.AssemblyLinearVelocity.Magnitude > 2
				local hop = if moving then math.abs(math.sin(t * 10 + f.phase)) * 1.2 else math.sin(t * 2 + f.phase) * 0.3
				local groundY = hrp.Position.Y - 3 * scale + f.height / 2
				local goal = CFrame.new(target.Position.X, groundY + hop, target.Position.Z) * hrp.CFrame.Rotation
				if (f.cf.Position - goal.Position).Magnitude > 80 then
					f.cf = goal
				else
					f.cf = f.cf:Lerp(goal, alpha)
				end
				f.model:PivotTo(f.cf)
			end
		end
	end
end

function PetFollowController.start()
	folder = Instance.new("Folder")
	folder.Name = "Stormlings"
	folder.Parent = Workspace
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)
	ClientState.observe("Settings", function()
		for _, p in Players:GetPlayers() do
			rebuild(p)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return PetFollowController
