--!strict
-- Equipped Brainrots follow their trainer around the hub (for every player, read from the
-- public "Equipped" attribute). Hidden while that player is in a battle — the battle's
-- combat units take over then.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Animator = require(Modules:WaitForChild("Models"):WaitForChild("Animator"))
local BrainrotModels = require(Modules.Models:WaitForChild("BrainrotModels"))
local Registry = require(Modules:WaitForChild("Registry"))

local FollowController = {}

local VIEW_DIST = 260

type Follower = { key: string, model: Model, rig: Animator.Rig, pos: Vector3, yaw: number, slot: number }
type Entry = { player: Player, followers: { Follower }, signature: string }

local entries: { [Player]: Entry } = {}
local folder: Folder

local function clear(entry: Entry)
	for _, f in entry.followers do
		f.model:Destroy()
	end
	table.clear(entry.followers)
end

local function rebuild(entry: Entry, origin: Vector3)
	clear(entry)
	local raw = entry.player:GetAttribute("Equipped")
	if type(raw) ~= "string" or raw == "" then
		return
	end
	local i = 0
	for _, part in string.split(raw, ",") do
		local bits = string.split(part, ":")
		local id, mut = bits[2], bits[3]
		local def = id and Registry.Brainrot[id]
		if def then
			i += 1
			local model = BrainrotModels.build(id, mut)
			model.Parent = folder
			table.insert(entry.followers, {
				key = part,
				model = model,
				rig = Animator.rig(model, def.idleQuirk),
				pos = origin,
				yaw = 0,
				slot = i,
			})
		end
	end
end

-- Formation: two staggered rows fanning out behind the trainer
local function slotOffset(slot: number, count: number): Vector3
	local row = if slot <= 5 then 0 else 1
	local inRow = if row == 0 then math.min(count, 5) else count - 5
	local idx = if row == 0 then slot else slot - 5
	local x = (idx - (inRow + 1) / 2) * 5.5
	return Vector3.new(x, 0, 7 + row * 6 + math.abs(x) * 0.25)
end

function FollowController.start()
	local live = Workspace:WaitForChild("Live")
	folder = Instance.new("Folder")
	folder.Name = "Followers"
	folder.Parent = live

	Players.PlayerRemoving:Connect(function(p)
		local e = entries[p]
		if e then
			clear(e)
			entries[p] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
		for _, p in Players:GetPlayers() do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local entry = entries[p]
			local visible = root ~= nil
				and hum ~= nil
				and hum.Health > 0
				and p:GetAttribute("BattleId") == nil
				and (root.Position - camPos).Magnitude < VIEW_DIST
			if not visible then
				if entry then
					clear(entry)
					entry.signature = ""
				end
				continue
			end
			local r = root :: BasePart
			local h = hum :: Humanoid
			if not entry then
				entry = { player = p, followers = {}, signature = "" }
				entries[p] = entry
			end
			local e = entry :: Entry
			local sig = (p:GetAttribute("Equipped") :: string?) or ""
			local groundY = r.Position.Y - h.HipHeight - r.Size.Y / 2
			if sig ~= e.signature then
				e.signature = sig
				rebuild(e, Vector3.new(r.Position.X, groundY, r.Position.Z))
			end
			local flatCf = CFrame.new(r.Position.X, groundY, r.Position.Z)
				* CFrame.Angles(0, select(2, r.CFrame:ToEulerAnglesYXZ()), 0)
			local count = #e.followers
			for _, f in e.followers do
				local goal = (flatCf * CFrame.new(slotOffset(f.slot, count))).Position
				local delta = Vector3.new(goal.X - f.pos.X, 0, goal.Z - f.pos.Z)
				local d = delta.Magnitude
				local moving = d > 0.8
				if d > 60 then
					f.pos = goal -- teleported trainer: snap
				elseif moving then
					local speed = math.max(16, d * 3)
					f.pos += delta.Unit * math.min(d, speed * dt)
					f.yaw = math.atan2(-delta.X, -delta.Z)
				else
					local _, ry = flatCf:ToEulerAnglesYXZ()
					local diff = (ry - f.yaw + math.pi) % (2 * math.pi) - math.pi
					f.yaw += diff * math.min(1, dt * 4)
				end
				f.pos = Vector3.new(f.pos.X, f.pos.Y + (groundY - f.pos.Y) * math.min(1, dt * 10), f.pos.Z)
				Animator.update(f.rig, CFrame.new(f.pos) * CFrame.Angles(0, f.yaw, 0), now, moving, 1.4)
			end
		end
	end)
end

return FollowController
