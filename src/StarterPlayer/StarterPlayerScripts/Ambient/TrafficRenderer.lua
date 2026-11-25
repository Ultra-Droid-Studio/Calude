-- TrafficRenderer: NPC araçların görselleri ve HAVUZ (Aşama 6). Sadece bu istemcide (yerel parçalar).
--
-- Model: görünmez sabit (Anchored) kök + kaynaklı ~11 parça (gövde, kabin, tavan, 4 teker, farlar, stoplar).
-- Fizik kısıtı yok; kök CFrame'i her karede yazılır (ara değerli). Gövde/kabin çarpışır (oyuncunun aracı çarpar),
-- hiçbiri ışın sorgularına girmez (CanQuery=false: kamera ve araç zemin ışını etkilenmez).
-- Ölçüler ve renkler VehicleDefinitions'tan gelir (aynı otomobil aileleri).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VehicleDefinitions"))

local TrafficRenderer = {}

local DARK = Color3.fromRGB(28, 30, 34)
local GLASS = Color3.fromRGB(40, 56, 70)
local HEAD_OFF = Color3.fromRGB(220, 220, 210)
local HEAD_ON = Color3.fromRGB(255, 244, 214)
local TAIL_OFF = Color3.fromRGB(110, 18, 22)
local TAIL_ON = Color3.fromRGB(255, 40, 40)

-- Kabin oranı ve konumu (gövde uzunluğuna göre): stil → { uzunluk oranı, merkez kayması }
local CABIN = {
	compact = { 0.55, 0.05 }, sedan = { 0.5, 0.05 }, sports = { 0.4, 0.08 }, suv = { 0.62, 0.08 },
	pickup = { 0.36, -0.12 }, van = { 0.8, 0.06 }, utility = { 0.7, 0.05 },
}

local folder: Folder
local pools: { [string]: { Model } } = {}
local rng = Random.new()

function TrafficRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "SolaraTraffic"
	folder.Parent = Workspace
end

local function part(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, opts: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = opts ~= nil and opts.Collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = not (opts ~= nil and opts.Collide == true) -- gövde/kabin kütleli: kazada gerçekçi savrulma
	p.CastShadow = opts ~= nil and opts.Shadow == true
	if opts and opts.Shape then
		p.Shape = opts.Shape
	end
	if opts and opts.Transparency then
		p.Transparency = opts.Transparency
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function build(defId: string): Model
	local def = VehicleDefinitions.Get(defId)
	local W, L = def.Width, def.Length
	local R = def.WheelRadius
	local clearance = def.Clearance or 1
	local lowerH, cabinH = def.LowerHeight or 2, def.CabinHeight or 2.2
	local model = Instance.new("Model")
	model.Name = "NPC_" .. defId
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(W, 0.2, L)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, -500, 0)
	root.Parent = model
	model.PrimaryPart = root

	part(model, root, "Body", Vector3.new(W, lowerH, L), CFrame.new(0, clearance + lowerH / 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Collide = true, Shadow = true })
	local cab = CABIN[def.Style] or CABIN.sedan
	local cabL = L * cab[1]
	local cabZ = L * cab[2]
	local cw = W - 0.8
	part(model, root, "Cabin", Vector3.new(cw, cabinH, cabL), CFrame.new(0, clearance + lowerH + cabinH / 2, cabZ), GLASS, Enum.Material.Glass, { Collide = true, Transparency = 0.2 })
	part(model, root, "Roof", Vector3.new(cw + 0.1, 0.3, cabL - 0.4), CFrame.new(0, clearance + lowerH + cabinH + 0.15, cabZ), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, root, "Wheel", Vector3.new(def.WheelWidth, R * 2, R * 2), CFrame.new(sx * def.Track / 2, R, sz * def.Wheelbase / 2), DARK, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		end
		part(model, root, "Head", Vector3.new(1.2, 0.5, 0.2), CFrame.new(sx * (W / 2 - 1), clearance + lowerH * 0.65, -L / 2 - 0.05), HEAD_OFF, Enum.Material.SmoothPlastic)
		part(model, root, "Tail", Vector3.new(1.2, 0.5, 0.2), CFrame.new(sx * (W / 2 - 1), clearance + lowerH * 0.65, L / 2 + 0.05), TAIL_OFF, Enum.Material.SmoothPlastic)
	end
	model:SetAttribute("DefId", defId)
	model:SetAttribute("Painted", true)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Lights", false)
	return model
end

local function paint(model: Model)
	local def = VehicleDefinitions.Get(model:GetAttribute("DefId"))
	local color = def.Colors[rng:NextInteger(1, #def.Colors)]
	for _, name in { "Body", "Roof" } do
		local p = model:FindFirstChild(name) :: BasePart?
		if p then
			p.Color = color
		end
	end
end

function TrafficRenderer.SetBrake(model: Model, on: boolean)
	if model:GetAttribute("Brake") == on then
		return
	end
	model:SetAttribute("Brake", on)
	for _, p in model:GetChildren() do
		if p.Name == "Tail" and p:IsA("BasePart") then
			p.Color = if on then TAIL_ON else TAIL_OFF
			p.Material = if on or model:GetAttribute("Lights") then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

function TrafficRenderer.SetLights(model: Model, on: boolean)
	if model:GetAttribute("Lights") == on then
		return
	end
	model:SetAttribute("Lights", on)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and (p.Name == "Head" or p.Name == "Tail") then
			if p.Name == "Head" then
				p.Color = if on then HEAD_ON else HEAD_OFF
			end
			p.Material = if on or (p.Name == "Tail" and model:GetAttribute("Brake")) then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- Havuzdan al (yoksa üret), boya, sahneye koy
function TrafficRenderer.Acquire(defId: string, lightsOn: boolean): Model
	local pool = pools[defId]
	local model = pool and table.remove(pool)
	if not model then
		model = build(defId)
	end
	paint(model)
	TrafficRenderer.SetBrake(model, false)
	TrafficRenderer.SetLights(model, lightsOn)
	model.Parent = folder
	return model
end

-- Havuza geri ver (kaza sonrası fizikseldiyse tekrar sabitle)
function TrafficRenderer.Release(model: Model)
	local root = model.PrimaryPart
	if root then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.new(0, -500, 0)
	end
	model.Parent = nil
	local defId = model:GetAttribute("DefId")
	pools[defId] = pools[defId] or {}
	table.insert(pools[defId], model)
end

-- Kaza: model fizik nesnesine döner (bu istemcide simüle edilir), sonra havuza döner
function TrafficRenderer.MakePhysical(model: Model, velocity: Vector3)
	local root = model.PrimaryPart
	if not root then
		return
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = velocity
end

function TrafficRenderer.PoolCount(): number
	local n = 0
	for _, pool in pools do
		n += #pool
	end
	return n
end

function TrafficRenderer.Folder(): Folder
	return folder
end

return TrafficRenderer
