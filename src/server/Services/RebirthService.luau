--!strict
-- Ascension (rebirth): reset Charge + upgrades for a permanent multiplier and Ascension
-- Tokens, spent in the Ascension tree. Also drives the cosmetic "size simulator" growth:
-- avatars grow per Ascension, jars grow with Storm Jar level (Config.SizeFeel).

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Defs = require(Shared.Defs)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local UpgradeService = require(script.Parent.UpgradeService)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local RebirthService = {}

function RebirthService.avatarScale(ascensions: number): number
	if not Config.SizeFeel.Enabled then
		return 1
	end
	return math.min(Config.SizeFeel.AvatarMaxScale, 1 + ascensions * Config.SizeFeel.AvatarScalePerAscension)
end

local function applySize(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	player:SetAttribute("JarLevel", data.Upgrades.JarCapacity or 0)
	player:SetAttribute("Ascensions", data.Ascensions)
	local character = player.Character
	if character and Config.SizeFeel.Enabled then
		local target = RebirthService.avatarScale(data.Ascensions)
		pcall(function()
			if math.abs(character:GetScale() - target) > 0.01 then
				character:ScaleTo(target)
			end
		end)
	end
end

function RebirthService.ascend(player: Player): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "Not ready"
	end
	local cost = EconomyMath.ascensionCost(data.Ascensions)
	if data.Charge < cost then
		return false, `You need {Format.short(cost)} Charge to Ascend`
	end
	local tokens = EconomyMath.ascensionTokens(data.Ascensions, data.Charge)
	local spent = data.Charge
	data.Ascensions += 1
	data.Charge = 0
	data.Static = 0
	UpgradeService.applyHeadStart(player)
	CurrencyService.addTokens(player, tokens)
	GameEvents.ChargeSpent:Fire(player, spent, "Ascension", tostring(data.Ascensions))
	for _, key in { "Ascensions", "Charge", "Static", "Upgrades" } do
		DataService.markDirty(player, key)
	end
	StatsService.refresh(player)
	applySize(player)
	GameEvents.Ascended:Fire(player, data.Ascensions)
	Net.Server.fireAll("Announce", `{player.DisplayName} Ascended! (x{data.Ascensions})`, "Epic")
	DataService.save(player)
	return true, tokens
end

function RebirthService.buyNode(player: Player, nodeId: string): (boolean, string?)
	local data = DataService.get(player)
	local node = Defs.AscNode[nodeId]
	if not data or not node then
		return false, "Unknown upgrade"
	end
	local level = data.AscTree[nodeId] or 0
	if level >= node.maxLevel then
		return false, "Maxed out"
	end
	if node.requires and (data.AscTree[node.requires] or 0) < 1 then
		return false, `Requires {Defs.AscNode[node.requires].name}`
	end
	local cost = EconomyMath.ascNodeCost(node, level)
	if data.Tokens < cost then
		return false, "Not enough Tokens"
	end
	data.Tokens -= cost
	data.AscTree[nodeId] = level + 1
	DataService.markDirty(player, "Tokens")
	DataService.markDirty(player, "AscTree")
	StatsService.refresh(player)
	return true
end

function RebirthService.init() end

function RebirthService.start()
	Net.Server.handle("Ascend", RebirthService.ascend)
	Net.Server.handle("BuyAscNode", RebirthService.buyNode)
	DataService.Loaded:Connect(function(player)
		applySize(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.5)
			applySize(player)
		end)
	end)
	GameEvents.Upgraded:Connect(function(player, upgradeId)
		if upgradeId == "JarCapacity" then
			applySize(player)
		end
	end)
end

return RebirthService
