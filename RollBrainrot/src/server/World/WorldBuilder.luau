--!strict
-- Builds the whole world when the server starts: lighting, terrain, hub, roll machine,
-- zoo plots and the stadium. Everything is generated placeholder geometry, so the place
-- file needs no assets. Takes a second or two on boot.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local HubBuilder = require(script.Parent.HubBuilder)
local RollMachineBuilder = require(script.Parent.RollMachineBuilder)
local ZooPlotBuilder = require(script.Parent.ZooPlotBuilder)

local WorldBuilder = {}

local rgb = Color3.fromRGB

local function lighting()
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.6
	Lighting.Ambient = rgb(110, 105, 125)
	Lighting.OutdoorAmbient = rgb(150, 145, 165)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ShadowSoftness = 0.25
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.27
	atmosphere.Offset = 0.15
	atmosphere.Color = rgb(205, 225, 255)
	atmosphere.Decay = rgb(140, 160, 200)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.1
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.StarCount = 3000
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.7
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.07
	rays.Spread = 0.6
	rays.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WorldGrade"
	cc.Saturation = 0.15
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = rgb(255, 255, 255)
	clouds.Parent = Workspace.Terrain
end

function WorldBuilder.build()
	local started = os.clock()
	lighting()
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace
	HubBuilder.build(world)
	RollMachineBuilder.build(world)
	ZooPlotBuilder.buildAll(world)
	ArenaBuilder.build(world)
	-- client-rendered things (creatures, crowd, units) go here, never streamed
	local live = Instance.new("Folder")
	live.Name = "Live"
	live.Parent = Workspace
	print(`[World] built in {math.floor((os.clock() - started) * 1000)} ms`)
end

return WorldBuilder
