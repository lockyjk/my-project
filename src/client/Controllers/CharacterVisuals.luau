--!strict
-- The Storm Jar worn on every character's back. It grows with the owner's Storm Jar level
-- (the "size simulator" feel), glows while it fills (local player), and sparks when full.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.ClientState)

local CharacterVisuals = {}

type Jar = { model: Model, fill: Part, glass: Part, height: number }
local jars: { [Player]: Jar } = {}

local function jarScale(player: Player): number
	local level = tonumber(player:GetAttribute("JarLevel")) or 0
	return math.min(Config.SizeFeel.JarMaxScale, Config.SizeFeel.JarScaleBase + level * Config.SizeFeel.JarScalePerLevel)
end

local function part(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p:SetAttribute("ArtistNote", `Storm Jar backpack: {name}`)
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	b.CFrame = a.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function build(player: Player, character: Model)
	local old = jars[player]
	if old then
		old.model:Destroy()
		jars[player] = nil
	end
	local torso = (character:WaitForChild("UpperTorso", 5) or character:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	local s = jarScale(player) * character:GetScale()
	local model = Instance.new("Model")
	model.Name = "StormJar"
	local h = 2.6 * s
	local r = 1.6 * s
	local glass = part(model, "Glass", Vector3.new(h, r, r), Color3.fromRGB(200, 235, 255), Enum.Material.Glass, 0.55)
	local fill = part(model, "Fill", Vector3.new(0.05, r * 0.85, r * 0.85), Theme.Colors.Static, Enum.Material.Neon, 0.1)
	local lid = part(model, "Lid", Vector3.new(0.5 * s, r * 1.08, r * 1.08), Theme.Colors.PanelDark, Enum.Material.SmoothPlastic, 0)
	local nozzle = part(model, "Nozzle", Vector3.new(1.2 * s, 0.4 * s, 0.4 * s), Theme.Colors.Charge, Enum.Material.Neon, 0)
	for _, p in { glass, fill, lid, nozzle } do
		p.Shape = Enum.PartType.Cylinder
	end
	nozzle.Shape = Enum.PartType.Block
	local base = CFrame.new(0, 0.2 * s, torso.Size.Z / 2 + r / 2) * CFrame.Angles(0, 0, math.rad(90))
	model.Parent = character
	weld(torso, glass, base)
	weld(torso, lid, base * CFrame.new(h / 2 + 0.2 * s, 0, 0))
	weld(torso, nozzle, base * CFrame.new(h / 2 + 0.6 * s, 0, -r * 0.3))
	weld(torso, fill, base * CFrame.new(-h / 2 + 0.05, 0, 0))
	jars[player] = { model = model, fill = fill, glass = glass, height = h }
	CharacterVisuals.updateFill()
end

-- Local player's jar fills with glowing Static
function CharacterVisuals.updateFill()
	local jar = jars[Players.LocalPlayer]
	if not jar then
		return
	end
	local d = ClientState.derived()
	local cap = d.Capacity or 1
	local frac = math.clamp((ClientState.get("Static") or 0) / cap, 0, 1)
	local torsoWeld = jar.fill:FindFirstChildOfClass("WeldConstraint")
	local len = math.max(0.05, jar.height * 0.95 * frac)
	-- resize along the jar axis, anchored at the bottom
	if torsoWeld then
		local part0 = torsoWeld.Part0
		torsoWeld.Enabled = false
		local bottom = jar.glass.CFrame * CFrame.new(-jar.height / 2, 0, 0)
		jar.fill.Size = Vector3.new(len, jar.fill.Size.Y, jar.fill.Size.Z)
		jar.fill.CFrame = bottom * CFrame.new(len / 2, 0, 0)
		torsoWeld.Part0 = part0
		torsoWeld.Enabled = true
	end
	jar.fill.Color = if frac >= 1 then Theme.Colors.Warn else Theme.Colors.Static
end

local function watch(player: Player)
	local function onCharacter(character: Model)
		task.defer(build, player, character)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	for _, attr in { "JarLevel", "Ascensions" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if player.Character then
				task.wait(0.3) -- let the server's avatar ScaleTo land first
				build(player, player.Character)
			end
		end)
	end
end

function CharacterVisuals.start()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		jars[p] = nil
	end)
	ClientState.observe("Static", CharacterVisuals.updateFill)
	ClientState.observe("Derived", CharacterVisuals.updateFill)
end

return CharacterVisuals
