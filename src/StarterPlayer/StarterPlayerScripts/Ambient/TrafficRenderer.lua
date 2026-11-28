-- TrafficRenderer: NPC araçların görselleri ve HAVUZ (Aşama 6). Sadece bu istemcide (yerel parçalar).
--
-- Model: görünmez sabit (Anchored) kök + kaynaklı ~11 parça (gövde, kabin, tavan, 4 teker, farlar, stoplar).
-- Fizik kısıtı yok; kök CFrame'i her karede yazılır (ara değerli). Gövde/kabin çarpışır (oyuncunun aracı çarpar),
-- hiçbiri ışın sorgularına girmez (CanQuery=false: kamera ve araç zemin ışını etkilenmez).
-- Ölçüler ve renkler VehicleDefinitions'tan gelir (aynı otomobil aileleri).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VehicleDefinitions"))
local CarModelKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CarModelKit"))

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

-- Araç çalma (Şehir: NPC aracı çal): sürücü koltuğu (yayanın kalça noktası, araca göre; yüz −Z) ve sürücü kapısının
-- önü (oyuncunun duracağı yer, yolda) köke eklenir; kapı noktasında "Çal" istemi (F). İstemi AmbientController açar.
local function addDriverLayout(root: BasePart, def, width: number, roofTop: number, minSeat: number)
	local driver = def.Seats[1]
	local seatX = math.clamp(driver.X * width / def.Width, -width / 2 + 0.9, 0)
	-- oturan yetişkinin (kalçadan baş üstüne ~3 stud) başı tavanın altında; alçak spor arabada koltuk tabana iner
	-- (sürücü bacaklarını öne uzatır: PedRenderer.SitIn alçak koltukta o pozu seçer)
	local seatY = math.max(math.min(roofTop - 3.2, minSeat + 1.2), 0.75)
	local seat = Instance.new("Attachment")
	seat.Name = "DriverSeat"
	seat.CFrame = CFrame.new(seatX, seatY, driver.Z)
	seat.Parent = root
	local door = Instance.new("Attachment")
	door.Name = "DoorPoint"
	door.CFrame = CFrame.new(-(width / 2 + 1.7), 0, driver.Z)
	door.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HijackPrompt"
	prompt.ActionText = "Çal"
	prompt.ObjectText = "Araç"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = door
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
	addDriverLayout(root, def, W, clearance + lowerH + cabinH, clearance + lowerH * 0.5)
	model:SetAttribute("DefId", defId)
	model:SetAttribute("Painted", true)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Lights", false)
	return model
end

-- Dış 3D model (CarModelConfig; kullanıcının verdiği low-poly arabalar): ReplicatedStorage.VehicleModels'ta varsa kullanılır.
-- Ölçek: tanımın dingil mesafesi; kök yol yüzeyinde, teker merkezleri yerden teker yarıçapı kadar yukarıda.
local meshData: { [Model]: { Name: string, Parts: { BasePart }, Spin: { any }, Radius: number, Angle: number } } = {}

local function buildMesh(defId: string, name: string): Model?
	local info = CarModelKit.Get(name)
	if not info then
		return nil
	end
	local def = VehicleDefinitions.Get(defId)
	local s = def.Wheelbase / info.Wheelbase
	local radius = info.WheelRadius * s
	local model = Instance.new("Model")
	model.Name = "NPC_" .. name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(info.Width * s, 0.2, info.Length * s)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, -500, 0)
	root.Parent = model
	model.PrimaryPart = root
	-- tek kutu çarpışma gövdesi (oyuncunun aracı çarpar; görsel meshler çarpışmaz → ucuz ve kararlı)
	local height = math.max(radius + info.RoofY * s - 0.4, 2)
	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(info.Width * s * 0.95, height, info.Length * s * 0.95)
	hull.CFrame = root.CFrame * CFrame.new(0, 0.4 + height / 2, 0)
	hull.Transparency = 1
	hull.Anchored = false
	hull.CanCollide = true
	hull.CanQuery = false
	hull.CanTouch = false
	hull.Massless = false
	hull.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(def.Mass / (hull.Size.X * hull.Size.Y * hull.Size.Z), 0.05, 10), 0.4, 0.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = hull
	weld.Parent = hull
	hull.Parent = model
	local result = CarModelKit.Build(info, {
		Frame = root.CFrame * CFrame.new(0, radius, 0), Scale = s, Parent = model, Body = root, Shadows = true,
	})
	meshData[model] = { Name = name, Parts = result.Parts, Spin = result.Spin, Radius = radius, Angle = 0 }
	addDriverLayout(root, def, info.Width * s, radius + info.RoofY * s, radius + 0.4)
	model:SetAttribute("DefId", defId)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Lights", false)
	return model
end

local function paint(model: Model)
	local def = VehicleDefinitions.Get(model:GetAttribute("DefId"))
	local mesh = meshData[model]
	if mesh then
		-- bazen modelin kendi rengi (CarModelConfig.OriginalPaintChance), çoğunlukla aracın renk listesinden
		local color = CarModelKit.RandomPaint(def.Colors, rng)
		CarModelKit.Repaint(mesh.Parts, mesh.Name, color)
		model:SetAttribute("Paint", color) -- nil: modelin kendi rengi (çalınınca aynı renk)
		return
	end
	local color = def.Colors[rng:NextInteger(1, #def.Colors)]
	model:SetAttribute("Paint", color)
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
		if (p.Name == "Tail" or p.Name == "TailLight") and p:IsA("BasePart") then
			p.Color = if on then TAIL_ON else (p:GetAttribute("OffColor") or TAIL_OFF)
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
		if p:IsA("BasePart") then
			local head = p.Name == "Head" or p.Name == "Headlight"
			local tail = p.Name == "Tail" or p.Name == "TailLight"
			if head then
				p.Color = if on then HEAD_ON else (p:GetAttribute("OffColor") or HEAD_OFF)
			end
			if head or tail then
				p.Material = if on or (tail and model:GetAttribute("Brake")) then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end

-- Görünür tekerleri döndür (dış modelli araçlar). speed: stud/sn (ileri +)
function TrafficRenderer.Spin(model: Model, speed: number, dt: number)
	local mesh = meshData[model]
	if not mesh or #mesh.Spin == 0 then
		return
	end
	mesh.Angle = (mesh.Angle - speed / mesh.Radius * dt) % (math.pi * 2)
	local t = CFrame.Angles(mesh.Angle, 0, 0)
	for _, s in mesh.Spin do
		s.Motor.Transform = t
	end
end

-- Havuzdan al (yoksa üret), boya, sahneye koy. taxiScale: bölgeye göre taksi olasılığı çarpanı
function TrafficRenderer.Acquire(defId: string, lightsOn: boolean, taxiScale: number?): Model
	local bodyName = CarModelKit.Pick(defId, rng, true, taxiScale)
	local key = defId .. "|" .. (bodyName or "box")
	local pool = pools[key]
	local model = pool and table.remove(pool)
	if not model then
		model = (bodyName and buildMesh(defId, bodyName)) or build(defId)
		model:SetAttribute("PoolKey", key)
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
	local prompt = TrafficRenderer.HijackPrompt(model)
	if prompt then
		prompt.Enabled = false
	end
	if model:GetAttribute("Ghost") then
		model:SetAttribute("Ghost", nil)
		TrafficRenderer.Ghost(model, false)
	end
	if root then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.new(0, -500, 0)
	end
	model.Parent = nil
	local key = model:GetAttribute("PoolKey") or model:GetAttribute("DefId")
	pools[key] = pools[key] or {}
	table.insert(pools[key], model)
end

-- Kaza: model fizik nesnesine döner (bu istemcide simüle edilir), sonra havuza döner
function TrafficRenderer.MakePhysical(model: Model, velocity: Vector3)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local prompt = TrafficRenderer.HijackPrompt(model)
	if prompt then
		prompt.Enabled = false
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = velocity
end

-- Araç çalma bilgisi: sürücü koltuğu ve kapı önü (köke göre), tanım, model adı (kutu araçta nil), boya (nil: modelin
-- kendi rengi)
function TrafficRenderer.HijackInfo(model: Model): (CFrame?, Vector3?, string?, string?, Color3?)
	local root = model.PrimaryPart
	local seat = root and root:FindFirstChild("DriverSeat")
	local door = root and root:FindFirstChild("DoorPoint")
	if not seat or not door then
		return nil
	end
	local mesh = meshData[model]
	local paint = model:GetAttribute("Paint")
	return (seat :: Attachment).CFrame, (door :: Attachment).Position, model:GetAttribute("DefId"),
		if mesh then mesh.Name else nil, if typeof(paint) == "Color3" then paint else nil
end

-- Hayalet: çalınırken NPC görseli çarpışmaz (sunucudaki gerçek araç aynı yerde belirir). false: eski hâline döner
function TrafficRenderer.Ghost(model: Model, ghost: boolean)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local own = p:GetAttribute("NpcCollide")
			if own == nil then
				own = p.CanCollide
				p:SetAttribute("NpcCollide", own)
			end
			p.CanCollide = (not ghost) and own == true
		end
	end
end

function TrafficRenderer.HijackPrompt(model: Model): ProximityPrompt?
	local root = model.PrimaryPart
	local door = root and root:FindFirstChild("DoorPoint")
	local prompt = door and door:FindFirstChild("HijackPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Kazadaki aracın durumu: hız (stud/sn), dik mi (devrilmemiş), konum, burun yönü (yatay)
function TrafficRenderer.CrashState(model: Model): (number, boolean, Vector3, Vector3)
	local root = model.PrimaryPart
	if not root then
		return 0, false, Vector3.zero, Vector3.new(0, 0, -1)
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	return root.AssemblyLinearVelocity.Magnitude, root.CFrame.UpVector.Y > 0.85, root.Position, flat
end

-- Kazadan toparlan: model yeniden sabit (simülasyon taşır)
function TrafficRenderer.Recover(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
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
