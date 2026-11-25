-- PedRenderer: yaya görselleri, HAVUZ ve ucuz yürüme animasyonu (Aşama 6). Sadece bu istemcide.
--
-- Model: görünmez sabit kök (kalça) + gövde, baş, 2 kol, 2 bacak (Motor6D). Humanoid YOK (pahalı):
-- yürüme, Motor6D.Transform ile bacak/kol salınımı; uzaktaki yayalarda animasyon kapalı (LOD).
-- Yayalar çarpışmaz (oyuncunun önünü kesmez; yapay zekâ zaten oyuncudan kaçınır), ışın sorgularına girmez.

local Workspace = game:GetService("Workspace")

local PedRenderer = {}

local SKIN = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 190, 150), Color3.fromRGB(198, 145, 105),
	Color3.fromRGB(160, 110, 75), Color3.fromRGB(110, 72, 48), Color3.fromRGB(80, 52, 36),
}
local SHIRT = {
	Color3.fromRGB(230, 230, 228), Color3.fromRGB(40, 44, 52), Color3.fromRGB(180, 40, 50), Color3.fromRGB(60, 110, 180),
	Color3.fromRGB(240, 200, 70), Color3.fromRGB(90, 150, 90), Color3.fromRGB(255, 122, 69), Color3.fromRGB(150, 90, 170),
	Color3.fromRGB(120, 200, 210),
}
local PANTS = {
	Color3.fromRGB(40, 50, 80), Color3.fromRGB(30, 30, 34), Color3.fromRGB(110, 100, 90), Color3.fromRGB(70, 70, 76),
	Color3.fromRGB(200, 190, 170), Color3.fromRGB(90, 60, 40),
}
local HIP = 2 -- kökün kaldırımdan yüksekliği

local folder: Folder
local pool: { Model } = {}
local rng = Random.new()

function PedRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "SolaraPedestrians"
	folder.Parent = Workspace
end

local function limb(model: Model, name: string, size: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	return m
end

local function build(): (Model, { [string]: Motor6D })
	local model = Instance.new("Model")
	model.Name = "NPC_Pedestrian"
	local root = limb(model, "Root", Vector3.new(2, 2, 1))
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = CFrame.new(0, -500, 0)
	model.PrimaryPart = root
	local torso = limb(model, "Torso", Vector3.new(2, 2, 1))
	local head = limb(model, "Head", Vector3.new(1.2, 1.2, 1.2))
	local armL = limb(model, "ArmL", Vector3.new(0.9, 2, 0.9))
	local armR = limb(model, "ArmR", Vector3.new(0.9, 2, 0.9))
	local legL = limb(model, "LegL", Vector3.new(0.95, 2, 0.95))
	local legR = limb(model, "LegR", Vector3.new(0.95, 2, 0.95))
	joint("Waist", root, torso, CFrame.new(0, 1, 0), CFrame.new())
	joint("Neck", torso, head, CFrame.new(0, 1.6, 0), CFrame.new())
	local motors = {
		ArmL = joint("ShoulderL", torso, armL, CFrame.new(-1.45, 0.8, 0), CFrame.new(0, 0.8, 0)),
		ArmR = joint("ShoulderR", torso, armR, CFrame.new(1.45, 0.8, 0), CFrame.new(0, 0.8, 0)),
		LegL = joint("HipL", root, legL, CFrame.new(-0.5, 0, 0), CFrame.new(0, 1, 0)),
		LegR = joint("HipR", root, legR, CFrame.new(0.5, 0, 0), CFrame.new(0, 1, 0)),
	}
	model:SetAttribute("Ped", true)
	return model, motors
end

local motorsOf: { [Model]: { [string]: Motor6D } } = {}

local function dress(model: Model)
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = SHIRT[rng:NextInteger(1, #SHIRT)]
	local pants = PANTS[rng:NextInteger(1, #PANTS)]
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Head" then
				p.Color = skin
			elseif p.Name == "Torso" then
				p.Color = shirt
			elseif p.Name == "ArmL" or p.Name == "ArmR" then
				p.Color = if rng:NextNumber() < 0.5 then shirt else skin -- kısa / uzun kol
			elseif p.Name == "LegL" or p.Name == "LegR" then
				p.Color = pants
			end
		end
	end
end

function PedRenderer.Acquire(): Model
	local model = table.remove(pool)
	if not model then
		local motors
		model, motors = build()
		motorsOf[model] = motors
	end
	dress(model)
	model.Parent = folder
	return model
end

function PedRenderer.Release(model: Model)
	local root = model.PrimaryPart
	if root then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.new(0, -500, 0)
	end
	PedRenderer.Animate(model, 0, 0)
	model.Parent = nil
	table.insert(pool, model)
end

-- Konum: kaldırım yüksekliğindeki nokta (x, y, z) ve yön (hx, hz)
function PedRenderer.Place(model: Model, position: Vector3, hx: number, hz: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local pos = position + Vector3.new(0, HIP, 0)
	local look = Vector3.new(hx, 0, hz)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	root.CFrame = CFrame.lookAt(pos, pos + look)
end

-- Yürüme salınımı: phase (radyan), amount 0..1 (0 = duruş)
function PedRenderer.Animate(model: Model, phase: number, amount: number)
	local motors = motorsOf[model]
	if not motors then
		return
	end
	local swing = math.sin(phase) * 0.55 * amount
	motors.LegL.Transform = CFrame.Angles(swing, 0, 0)
	motors.LegR.Transform = CFrame.Angles(-swing, 0, 0)
	motors.ArmL.Transform = CFrame.Angles(-swing * 0.7, 0, 0)
	motors.ArmR.Transform = CFrame.Angles(swing * 0.7, 0, 0)
end

-- Araç çarptı: model düşer (bu istemcide fizik), sonra havuza döner
function PedRenderer.MakePhysical(model: Model, velocity: Vector3)
	local root = model.PrimaryPart
	if not root then
		return
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2)
end

function PedRenderer.PoolCount(): number
	return #pool
end

function PedRenderer.Folder(): Folder
	return folder
end

return PedRenderer
