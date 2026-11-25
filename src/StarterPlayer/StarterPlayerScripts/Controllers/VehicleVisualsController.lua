-- VehicleVisualsController: dış 3D modelli oyuncu araçlarında görünür tekerlerin dönüşü.
--
-- VehicleFactory görünür tekerleri dönmeyen mafsala Motor6D ("SpinMotor") ile bağlar (fizik tekeri modelinkinden
-- büyük olduğu için görünür teker fizik tekerine kaynaklanırsa merkez kayar ve yalpalardı). Bu kontrolcü, kameraya
-- yakın araçlarda fizik tekerinin mafsala göre açısal hızını okur ve görünür tekeri aynı açıyla döndürür
-- (Motor6D.Transform, sadece bu istemcide; ağ trafiği yok). Fizik etkilenmez.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local VehicleVisualsController = {
	Name = "VehicleVisualsController",
	Priority = 36,
}

local RADIUS = 180 -- stud: bu mesafeden uzaktaki tekerler döndürülmez
local cacheOf: { [Model]: { { Motor: Motor6D, Wheel: BasePart?, Knuckle: BasePart?, Angle: number } } } = {}

local function collect(model: Model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "SpinMotor" then
			local w = d:GetAttribute("Wheel")
			table.insert(list, {
				Motor = d,
				Wheel = model:FindFirstChild("Wheel_" .. tostring(w)) :: BasePart?,
				Knuckle = model:FindFirstChild("Knuckle_" .. tostring(w)) :: BasePart?,
				Angle = 0,
			})
		end
	end
	return list
end

function VehicleVisualsController:Init() end

function VehicleVisualsController:Start()
	CollectionService:GetInstanceRemovedSignal("Vehicle"):Connect(function(model)
		cacheOf[model] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		for _, model in CollectionService:GetTagged("Vehicle") do
			if model:IsA("Model") and model:GetAttribute("BodyModel") then
				local root = model.PrimaryPart
				if root and (root.Position - camPos).Magnitude < RADIUS then
					local list = cacheOf[model]
					if not list or (#list > 0 and (not list[1].Wheel or not list[1].Knuckle)) then
						list = collect(model) -- akış (streaming) parçaları sonradan getirebilir
						cacheOf[model] = list
					end
					for _, s in list do
						local wheel, knuckle = s.Wheel, s.Knuckle
						if wheel and knuckle and wheel.Parent and s.Motor.Parent then
							local omega = (wheel.AssemblyAngularVelocity - knuckle.AssemblyAngularVelocity):Dot(knuckle.CFrame.RightVector)
							s.Angle = (s.Angle + omega * dt) % (math.pi * 2)
							s.Motor.Transform = CFrame.Angles(s.Angle, 0, 0)
						end
					end
				end
			end
		end
	end)
end

return VehicleVisualsController
