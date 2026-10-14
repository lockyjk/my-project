--!strict
-- 3D Brainrot portraits for UI cards: a ViewportFrame with the real creature model,
-- framed automatically from its Height/Radius attributes. Optional slow spin
-- (one shared RenderStepped loop for all spinning viewports).

local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local BrainrotModels = require(Modules:WaitForChild("Models"):WaitForChild("BrainrotModels"))
local MonsterModels = require(Modules.Models:WaitForChild("MonsterModels"))

local Viewport = {}

type Spinner = { model: Model, vp: ViewportFrame, base: CFrame }
local spinners: { [ViewportFrame]: Spinner } = {}
local looping = false

local function frame(vp: ViewportFrame, model: Model, yaw: number?)
	local h = (model:GetAttribute("Height") :: number?) or 4
	local r = (model:GetAttribute("Radius") :: number?) or 2
	local size = math.max(h, r * 2)
	local cam = vp.CurrentCamera or Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local center = Vector3.new(0, h * 0.5, 0)
	local dist = size / (2 * math.tan(math.rad(15))) * 1.15
	cam.CFrame = CFrame.lookAt(center + Vector3.new(dist * 0.35, h * 0.15, -dist), center)
	model:PivotTo(CFrame.Angles(0, yaw or math.rad(200), 0))
end

local function ensureLoop()
	if looping then
		return
	end
	looping = true
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for vp, s in spinners do
			if not vp.Parent then
				spinners[vp] = nil
			elseif vp.Visible then
				-- no physics inside viewports, so welds don't carry parts: pivot the whole model
				s.model:PivotTo(s.base * CFrame.Angles(0, t * 0.8, 0))
			end
		end
	end)
end

export type Props = {
	id: string,
	mut: string?,
	monster: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	spin: boolean?,
	parent: Instance?,
	zindex: number?,
	ambient: Color3?,
}

function Viewport.new(props: Props): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = props.size or UDim2.fromScale(1, 1)
	vp.Position = props.position or UDim2.new()
	vp.AnchorPoint = props.anchor or Vector2.zero
	vp.ZIndex = props.zindex or 2
	vp.Ambient = props.ambient or Color3.fromRGB(190, 190, 205)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -2, -1)
	local model = if props.monster then MonsterModels.build(props.id) else BrainrotModels.build(props.id, props.mut)
	-- particle emitters don't render in viewports; drop them
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	model.Parent = vp
	frame(vp, model)
	if props.spin then
		spinners[vp] = { model = model, vp = vp, base = model:GetPivot() }
		ensureLoop()
	end
	vp.Parent = props.parent
	return vp
end

-- Swap the creature shown in an existing viewport
function Viewport.set(vp: ViewportFrame, id: string, mut: string?)
	for _, c in vp:GetChildren() do
		if c:IsA("Model") then
			c:Destroy()
		end
	end
	local model = BrainrotModels.build(id, mut)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	model.Parent = vp
	frame(vp, model)
	local s = spinners[vp]
	if s then
		s.model = model
		s.base = model:GetPivot()
	end
end

return Viewport
