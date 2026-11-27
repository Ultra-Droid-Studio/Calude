-- PedRenderer: NPC yaya görselleri ve HAVUZ (Aşama 6; Yaşayan Şehir: R15 insan modeli). Sadece bu istemcide.
--
-- Model: kodla kurulan R15 iskeleti — HumanoidRootPart (görünmez, sabit kök) + LowerTorso, UpperTorso, Head, kollar
-- (UpperArm/LowerArm/Hand), bacaklar (UpperLeg/LowerLeg/Foot); eklemler standart R15 adlı Motor6D'ler (Root, Waist,
-- Neck, Left/RightShoulder, Elbow, Wrist, Hip, Knee, Ankle). Humanoid ve Animator YOK (80 yayada pahalı):
-- pozlar Shared/Ambient/PedAnim'den gelir (ters kinematik yürüme; basan ayak kaymaz) ve Motor6D.Transform'a yazılır.
-- Dış model/varlık yok: lisans sorunu yok; yüz Roblox'un yerleşik dokusu (rbxasset://textures/face.png).
--
-- Çeşitlilik (her havuzdan alışta yeniden giydirilir): boy (3 ölçek), gövde genişliği, ten rengi, kıyafet tipi
-- (tişört, uzun kol, ceket, takım elbise, elbise/etek, şort), saç (kısa, uzun, topuz, kel) ya da şapka (kep, bere),
-- aksesuar (sırt çantası, omuz çantası, gözlük). Parçalar çarpışmaz, gölge düşürmez, ışın sorgularına girmez.
--
-- Gerçekçi yayalar: kullanıcının verdiği Rocketbox modelleri (yüz, saç, kıyafet dokulu; deri/skinned) sunucuda
-- yüklüyse (ReplicatedStorage.PedestrianModels) yeni yayalar onlardan kurulur (PedMeshRig) ve aynı PedAnim
-- pozlarıyla kemiklerden canlandırılır. Model yoksa yukarıdaki R15 yayalar kullanılır.

local Workspace = game:GetService("Workspace")

local PedMeshRig = require(script.Parent:WaitForChild("PedMeshRig"))

local PedRenderer = {}

local rgb = Color3.fromRGB
local SKIN = { rgb(255, 224, 196), rgb(240, 200, 164), rgb(214, 164, 124), rgb(176, 124, 88), rgb(128, 86, 58), rgb(92, 60, 42) }
local SHIRT = {
	rgb(236, 236, 232), rgb(44, 48, 56), rgb(176, 46, 56), rgb(58, 104, 172), rgb(232, 196, 76), rgb(86, 146, 92),
	rgb(240, 128, 80), rgb(140, 92, 168), rgb(118, 192, 204), rgb(214, 170, 190), rgb(120, 120, 124),
}
local PANTS = { rgb(42, 54, 86), rgb(30, 30, 34), rgb(112, 102, 90), rgb(72, 72, 78), rgb(196, 186, 166), rgb(92, 64, 44), rgb(64, 84, 112) }
local JACKET = { rgb(36, 38, 44), rgb(96, 70, 52), rgb(54, 70, 52), rgb(120, 40, 44), rgb(140, 140, 146), rgb(40, 60, 96) }
local SUIT = { rgb(34, 36, 42), rgb(52, 58, 72), rgb(88, 88, 92) }
local DRESS = { rgb(176, 46, 66), rgb(58, 104, 172), rgb(232, 196, 76), rgb(40, 40, 44), rgb(214, 150, 180), rgb(90, 150, 120) }
local SHOES = { rgb(28, 28, 30), rgb(240, 240, 236), rgb(96, 64, 44), rgb(60, 60, 66) }
local HAIR = { rgb(26, 20, 18), rgb(70, 44, 28), rgb(120, 82, 46), rgb(212, 178, 110), rgb(150, 66, 40), rgb(160, 160, 160) }
local BAG = { rgb(36, 36, 40), rgb(160, 60, 50), rgb(60, 90, 140), rgb(120, 90, 60) }

local SCALES = { 0.88, 0.94, 1.0 } -- boy: ~5.2 / 5.6 / 6.0 stud
local ROOT_Y = 2.95 -- kökün (alt gövde ortası) yerden yüksekliği (ölçek 1)

local folder: Folder
local pool: { Model } = {}
local rng = Random.new()

type Rig = {
	Scale: number, Width: number, Parts: { [string]: BasePart }, Motors: { [string]: Motor6D }, Extras: { Instance },
	Face: Decal, Fade: number,
	Mesh: boolean?, RootY: number?, -- gerçekçi (Rocketbox) yaya: PedMeshRig
}
local rigOf: { [Model]: Rig } = {}

function PedRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "SolaraPedestrians"
	folder.Parent = Workspace
end

local function newPart(model: Model, name: string, size: Vector3, cf: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- R15 eklemi: dünya (dinlenme pozu) noktasında, dönüşsüz C0/C1 (R15 animasyon kuralı)
local function motor(name: string, p0: BasePart, p1: BasePart, at: Vector3): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = p0, p1
	m.C0 = p0.CFrame:Inverse() * CFrame.new(at)
	m.C1 = p1.CFrame:Inverse() * CFrame.new(at)
	m.Parent = p1
	return m
end

-- Dinlenme pozunda (yer y = 0, yüz −Z) R15 iskeletini kur. k: boy ölçeği, w: gövde genişlik çarpanı
local function build(k: number, w: number): (Model, Rig)
	local model = Instance.new("Model")
	model.Name = "NPC_Pedestrian"
	local function at(x, y, z)
		return Vector3.new(x * k, y * k, z * k)
	end
	local function part(name, sx, sy, sz, x, y, z)
		return newPart(model, name, Vector3.new(sx * k, sy * k, sz * k), CFrame.new(at(x, y, z)))
	end
	local tw = 2.0 * w
	local ax = tw / 2 + 0.48
	local P = {}
	P.HumanoidRootPart = part("HumanoidRootPart", 2, 2, 1, 0, ROOT_Y, 0)
	P.HumanoidRootPart.Transparency = 1
	P.HumanoidRootPart.Anchored = true
	P.LowerTorso = part("LowerTorso", 1.9 * w, 0.6, 1.0, 0, 2.95, 0)
	P.UpperTorso = part("UpperTorso", tw, 1.5, 1.0, 0, 4.0, 0)
	P.Head = part("Head", 1.15, 1.2, 1.15, 0, 5.35, 0)
	for _, side in { "Left", "Right" } do
		local sx = (side == "Left") and -1 or 1
		P[side .. "UpperArm"] = part(side .. "UpperArm", 0.95, 1.2, 0.95, sx * ax, 4.15, 0)
		P[side .. "LowerArm"] = part(side .. "LowerArm", 0.9, 1.05, 0.9, sx * ax, 3.0, 0)
		P[side .. "Hand"] = part(side .. "Hand", 0.8, 0.45, 0.8, sx * ax, 2.25, 0)
		P[side .. "UpperLeg"] = part(side .. "UpperLeg", 0.95, 1.2, 0.95, sx * 0.5, 2.1, 0)
		P[side .. "LowerLeg"] = part(side .. "LowerLeg", 0.9, 1.2, 0.9, sx * 0.5, 0.9, 0)
		P[side .. "Foot"] = part(side .. "Foot", 0.9, 0.3, 1.25, sx * 0.5, 0.15, -0.15)
	end
	local head = Instance.new("SpecialMesh")
	head.MeshType = Enum.MeshType.Head
	head.Scale = Vector3.new(1.25, 1.25, 1.25)
	head.Parent = P.Head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = P.Head

	local M = {}
	M.Root = motor("Root", P.HumanoidRootPart, P.LowerTorso, at(0, 2.95, 0))
	M.Waist = motor("Waist", P.LowerTorso, P.UpperTorso, at(0, 3.25, 0))
	M.Neck = motor("Neck", P.UpperTorso, P.Head, at(0, 4.75, 0))
	for _, side in { "Left", "Right" } do
		local sx = (side == "Left") and -1 or 1
		M[side .. "Shoulder"] = motor(side .. "Shoulder", P.UpperTorso, P[side .. "UpperArm"], at(sx * ax, 4.6, 0))
		M[side .. "Elbow"] = motor(side .. "Elbow", P[side .. "UpperArm"], P[side .. "LowerArm"], at(sx * ax, 3.55, 0))
		M[side .. "Wrist"] = motor(side .. "Wrist", P[side .. "LowerArm"], P[side .. "Hand"], at(sx * ax, 2.475, 0))
		M[side .. "Hip"] = motor(side .. "Hip", P.LowerTorso, P[side .. "UpperLeg"], at(sx * 0.5, 2.7, 0))
		M[side .. "Knee"] = motor(side .. "Knee", P[side .. "UpperLeg"], P[side .. "LowerLeg"], at(sx * 0.5, 1.5, 0))
		M[side .. "Ankle"] = motor(side .. "Ankle", P[side .. "LowerLeg"], P[side .. "Foot"], at(sx * 0.5, 0.3, 0))
	end
	model.PrimaryPart = P.HumanoidRootPart
	P.HumanoidRootPart.CFrame = CFrame.new(0, -500, 0)
	model:SetAttribute("Ped", true)
	local rig: Rig = { Scale = k, Width = w, Parts = P, Motors = M, Extras = {}, Face = face, Fade = 0 }
	return model, rig
end

-- Gövde parçasına (dinlenme pozuna göre ofsetle) kaynaklı ek parça: saç, şapka, etek, çanta...
local function extra(rig: Rig, model: Model, base: string, name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?)
	local k = rig.Scale
	local b = rig.Parts[base]
	local p = newPart(model, name, size * k, b.CFrame * CFrame.new(offset.Position * k) * offset.Rotation)
	p.Color = color
	if shape then
		p.Shape = shape
	end
	local wld = Instance.new("Weld")
	wld.Part0 = b
	wld.Part1 = p
	wld.C0 = CFrame.new(offset.Position * k) * offset.Rotation
	wld.Parent = p
	table.insert(rig.Extras, p)
	return p
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- Giydir: renkler + kıyafet tipine göre ek parçalar (havuzdan her alışta yeniden)
local function dress(model: Model, rig: Rig)
	for _, e in rig.Extras do
		e:Destroy()
	end
	rig.Extras = {}
	local P = rig.Parts
	-- ek parçalar dinlenme pozuna göre yerleşsin: eklemleri sıfırla
	for _, m in rig.Motors do
		m.Transform = CFrame.identity
	end
	local skin, shoes = pick(SKIN), pick(SHOES)
	local top, armTop, armLow, low, leg = pick(SHIRT), nil, nil, pick(PANTS), nil
	local outfit = rng:NextNumber()
	local kind
	if outfit < 0.28 then
		kind = "tshirt"
	elseif outfit < 0.46 then
		kind = "longsleeve"
	elseif outfit < 0.62 then
		kind = "jacket"
	elseif outfit < 0.74 then
		kind = "suit"
	elseif outfit < 0.88 then
		kind = "dress"
	else
		kind = "shorts"
	end
	armTop, armLow, leg = top, skin, low
	if kind == "longsleeve" then
		armLow = top
	elseif kind == "jacket" then
		local j = pick(JACKET)
		armTop, armLow = j, j
		extra(rig, model, "UpperTorso", "JacketL", Vector3.new(0.85, 1.5, 1.04), CFrame.new(-0.58, 0, -0.01), j)
		extra(rig, model, "UpperTorso", "JacketR", Vector3.new(0.85, 1.5, 1.04), CFrame.new(0.58, 0, -0.01), j)
	elseif kind == "suit" then
		local s = pick(SUIT)
		top = rgb(240, 240, 236)
		armTop, armLow, low, leg = s, s, s, s
		extra(rig, model, "UpperTorso", "JacketL", Vector3.new(0.8, 1.52, 1.05), CFrame.new(-0.6, 0, -0.01), s)
		extra(rig, model, "UpperTorso", "JacketR", Vector3.new(0.8, 1.52, 1.05), CFrame.new(0.6, 0, -0.01), s)
		extra(rig, model, "UpperTorso", "Tie", Vector3.new(0.22, 0.9, 0.06), CFrame.new(0, 0.15, -0.52), pick({ rgb(150, 30, 40), rgb(30, 50, 110), rgb(40, 40, 44) }))
	elseif kind == "dress" then
		local d = pick(DRESS)
		top, armTop, low = d, d, d
		leg = skin
		extra(rig, model, "LowerTorso", "Skirt", Vector3.new(2.05 * rig.Width, 1.25, 1.2), CFrame.new(0, -0.7, 0), d)
	elseif kind == "shorts" then
		extra(rig, model, "LeftLowerLeg", "SockL", Vector3.new(0.92, 0.3, 0.92), CFrame.new(0, -0.45, 0), rgb(236, 236, 232))
		extra(rig, model, "RightLowerLeg", "SockR", Vector3.new(0.92, 0.3, 0.92), CFrame.new(0, -0.45, 0), rgb(236, 236, 232))
	end
	P.Head.Color = skin
	P.UpperTorso.Color = top
	P.LowerTorso.Color = low
	for _, side in { "Left", "Right" } do
		P[side .. "UpperArm"].Color = armTop
		P[side .. "LowerArm"].Color = armLow
		P[side .. "Hand"].Color = skin
		P[side .. "UpperLeg"].Color = leg
		P[side .. "LowerLeg"].Color = if kind == "shorts" then skin else leg
		P[side .. "Foot"].Color = shoes
	end
	-- saç / şapka
	local hair = pick(HAIR)
	local hr = rng:NextNumber()
	if kind == "suit" and hr < 0.5 then
		hr = 0.1 -- takım elbiseli: çoğunlukla kısa saç
	end
	if hr < 0.34 then
		extra(rig, model, "Head", "Hair", Vector3.new(1.28, 0.42, 1.28), CFrame.new(0, 0.5, 0.04), hair)
		extra(rig, model, "Head", "HairBack", Vector3.new(1.26, 0.7, 0.3), CFrame.new(0, 0.12, 0.52), hair)
	elseif hr < 0.56 then
		extra(rig, model, "Head", "Hair", Vector3.new(1.3, 0.45, 1.3), CFrame.new(0, 0.5, 0.04), hair)
		extra(rig, model, "Head", "HairLong", Vector3.new(1.3, 1.45, 0.34), CFrame.new(0, -0.18, 0.54), hair)
	elseif hr < 0.68 then
		extra(rig, model, "Head", "Hair", Vector3.new(1.28, 0.4, 1.28), CFrame.new(0, 0.5, 0.04), hair)
		extra(rig, model, "Head", "Bun", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 0.55, 0.62), hair, Enum.PartType.Ball)
	elseif hr < 0.8 then
		local cap = pick({ rgb(176, 46, 56), rgb(30, 30, 34), rgb(58, 104, 172), rgb(236, 236, 232) })
		extra(rig, model, "Head", "Cap", Vector3.new(1.32, 0.42, 1.32), CFrame.new(0, 0.55, 0.02), cap)
		extra(rig, model, "Head", "CapBrim", Vector3.new(1.2, 0.08, 0.6), CFrame.new(0, 0.38, -0.85), cap)
	elseif hr < 0.88 then
		extra(rig, model, "Head", "Beanie", Vector3.new(1.32, 0.62, 1.32), CFrame.new(0, 0.5, 0.02), pick(JACKET))
	end -- aksi: kel / çok kısa
	-- aksesuar
	local acc = rng:NextNumber()
	if acc < 0.18 then
		local c = pick(BAG)
		extra(rig, model, "UpperTorso", "Backpack", Vector3.new(1.4, 1.5, 0.6), CFrame.new(0, -0.05, 0.8), c)
	elseif acc < 0.3 then
		local c = pick(BAG)
		extra(rig, model, "UpperTorso", "Strap", Vector3.new(0.16, 1.7, 1.06), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(40)), c)
		extra(rig, model, "LowerTorso", "Bag", Vector3.new(0.5, 0.9, 1.1), CFrame.new(1.25 * rig.Width, -0.2, 0), c)
	end
	if rng:NextNumber() < 0.15 then
		extra(rig, model, "Head", "Glasses", Vector3.new(1.0, 0.16, 0.08), CFrame.new(0, 0.12, -0.6), rgb(20, 20, 22))
	end
	PedRenderer.SetFade(model, 0)
end

function PedRenderer.Acquire(): Model
	local model = table.remove(pool)
	local rig
	if model then
		rig = rigOf[model]
	else
		if PedMeshRig.Available() then
			local ok, m, r = pcall(PedMeshRig.Build, rng)
			if ok and m then
				model, rig = m, r
			elseif not ok then
				warn("[PedRenderer] gerçekçi yaya kurulamadı:", m)
			end
		end
		if not model then
			model, rig = build(SCALES[rng:NextInteger(1, #SCALES)], rng:NextNumber(0.9, 1.08))
		end
		rigOf[model] = rig
	end
	if rig.Mesh then
		PedMeshRig.Neutral(rig)
		PedRenderer.SetFade(model, 0)
	else
		dress(model, rig)
	end
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
	if root then
		root.CanCollide = false
	end
	PedRenderer.SetFade(model, 0)
	model.Parent = nil
	table.insert(pool, model)
end

function PedRenderer.Scale(model: Model): number
	local rig = rigOf[model]
	return rig and rig.Scale or 1
end

-- Konum: zemin noktası (ayak tabanı) ve yön (hx, hz)
function PedRenderer.Place(model: Model, position: Vector3, hx: number, hz: number)
	local root = model.PrimaryPart
	local rig = rigOf[model]
	if not root or not rig then
		return
	end
	local pos = position + Vector3.new(0, if rig.Mesh then rig.RootY else ROOT_Y * rig.Scale, 0)
	local look = Vector3.new(hx, 0, hz)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	root.CFrame = CFrame.lookAt(pos, pos + look)
end

-- PedAnim pozunu eklemlere yaz (açılar radyan; kök ofseti ölçeksiz stud)
local Angles = CFrame.Angles
function PedRenderer.Pose(model: Model, pose)
	local rig = rigOf[model]
	if not rig then
		return
	end
	if rig.Mesh then
		PedMeshRig.Pose(rig, pose)
		return
	end
	local M, k = rig.Motors, rig.Scale
	M.Root.Transform = CFrame.new(pose.RootX * k, pose.RootY * k, 0) * Angles(0, pose.RootYaw, pose.RootRoll)
	M.Waist.Transform = Angles(pose.WaistPitch, pose.WaistYaw, 0)
	M.Neck.Transform = Angles(pose.NeckPitch, pose.NeckYaw, 0)
	M.LeftHip.Transform = Angles(pose.LHip, 0, 0)
	M.LeftKnee.Transform = Angles(-pose.LKnee, 0, 0)
	M.LeftAnkle.Transform = Angles(pose.LAnkle, 0, 0)
	M.RightHip.Transform = Angles(pose.RHip, 0, 0)
	M.RightKnee.Transform = Angles(-pose.RKnee, 0, 0)
	M.RightAnkle.Transform = Angles(pose.RAnkle, 0, 0)
	M.LeftShoulder.Transform = Angles(pose.LShoulder, 0, pose.LShoulderRoll)
	M.RightShoulder.Transform = Angles(pose.RShoulder, 0, pose.RShoulderRoll)
	M.LeftElbow.Transform = Angles(pose.LElbow, 0, 0)
	M.RightElbow.Transform = Angles(pose.RElbow, 0, 0)
end

-- Ayakta, kollar yanda (uzaktaki yaya için tek seferlik)
function PedRenderer.Neutral(model: Model)
	local rig = rigOf[model]
	if rig and rig.Mesh then
		PedMeshRig.Neutral(rig)
	elseif rig then
		for _, m in rig.Motors do
			m.Transform = CFrame.identity
		end
	end
end

-- Kapıda kararma: 0 görünür … 1 görünmez (yerel)
function PedRenderer.SetFade(model: Model, fade: number)
	local rig = rigOf[model]
	if not rig or math.abs((rig.Fade or 0) - fade) < 0.02 then
		return
	end
	rig.Fade = fade
	if rig.Mesh then
		PedMeshRig.SetFade(rig, fade)
		return
	end
	for _, p in rig.Parts do
		if p.Name ~= "HumanoidRootPart" then
			p.LocalTransparencyModifier = fade
		end
	end
	for _, e in rig.Extras do
		if e:IsA("BasePart") then
			e.LocalTransparencyModifier = fade
		end
	end
	rig.Face.Transparency = fade
end

-- Araç çarptı: model düşer (bu istemcide fizik), sonra havuza döner
function PedRenderer.MakePhysical(model: Model, velocity: Vector3)
	local root = model.PrimaryPart
	if not root then
		return
	end
	PedRenderer.Neutral(model)
	root.CanCollide = true -- yere düşsün (zeminin içinden geçmesin)
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
