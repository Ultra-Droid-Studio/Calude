-- PedMeshRig: kullanıcının verdiği gerçekçi yaya modelleri (Microsoft Rocketbox, MIT; tools/peds_convert.py) için
-- kurulum ve poz. Her yaya: tek deri (skinned) MeshPart — yüz, saç, kıyafet dokusu modelin kendisinde — ve 20 kemik
-- (Ped_<Id>_Pelvis, _Spine1, _LThigh ...). Sunucu ReplicatedStorage.PedestrianModels.Ped_<Id> olarak koyar
-- (ModelAssetService).
--
-- Animasyon: PedAnim'in ters kinematikli yürüme / duruş / dönüş / kapı itme pozları (R15 için yazılmış eklem açıları)
-- kemiklere çevrilir. Her eklem açısı karakter eksenlerinde (sağ +X, yukarı +Y, ön −Z; R15 Motor6D kuralıyla aynı)
-- tanımlıdır ve kemiğin kendi dinlenme yönüne göre Bone.Transform'a dönüştürülür:
--   Transform = Rb⁻¹ · Rp · Ap⁻¹ · Δ · Ab
--   (Rb/Rp: kemiğin/ebeveyninin dinlenme yönü, Ab/Ap: "kollar aşağıda" düzeltilmiş dinlenme yönü, Δ: eklem açısı)
-- Kaynak modelin kolları A-pozunda: kollar önce gövdenin yanına indirilir (ARM_OUT açıyla), sonra omuz/dirsek
-- açıları uygulanır; bacaklar dikleştirilir (bazı modellerde dinlenmede birkaç derece eğik). Kalibrasyon kemiklerin kendi konumlarından yapılır (içe aktarmanın ölçeği/dönüşü önemli değil).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PedModelData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PedModelData"))

local PedMeshRig = {}

local FOLDER = "PedestrianModels"
local STUDS_PER_M = 3.15 -- 1.73–1.82 m → 5.4–5.7 stud (oyuncu karakteriyle aynı boy aralığı)
local LEG_UNIT = 2.4 -- PedAnim.L1 + PedAnim.L2 (ölçek 1)
local ARM_OUT = math.rad(7) -- kollar gövdeden bu kadar açık sarkar (kalçaya girmesin)
local Angles = CFrame.Angles
local DRIVEN = { -- PedAnim'in sürdüğü kemikler (diğerleri ebeveyniyle birlikte hareket eder)
	"Pelvis", "Spine1", "Spine2", "Neck", "Head", "LThigh", "LCalf", "LFoot", "RThigh", "RCalf", "RFoot",
	"LUpperArm", "LForearm", "RUpperArm", "RForearm",
}

local templates: { any }? = nil
local warned = false

local function load()
	if templates then
		return templates
	end
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if not folder or folder:GetAttribute("Ready") == false then
		return nil
	end
	local list = {}
	for _, info in PedModelData.Peds do
		local t = folder:FindFirstChild("Ped_" .. info.Id)
		if t then
			table.insert(list, { Info = info, Template = t })
		end
	end
	if #list == 0 then
		return nil
	end
	templates = list
	return list
end

-- Modeller hazır mı (sunucu yüklediyse)
function PedMeshRig.Available(): boolean
	return load() ~= nil
end

local function bonesOf(model: Instance, id: string): { [string]: Bone }
	local prefix = "Ped_" .. id .. "_"
	local bones = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") and string.sub(d.Name, 1, #prefix) == prefix then
			bones[string.sub(d.Name, #prefix + 1)] = d
		end
	end
	return bones
end

-- u yönünü t yönüne çeviren dönüş
local function rotateTo(u: Vector3, t: Vector3): CFrame
	local axis = u:Cross(t)
	local angle = math.acos(math.clamp(u:Dot(t), -1, 1))
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, angle)
end

-- Yeni yaya kur. Döndürür: model, rig (nil: model eksik)
function PedMeshRig.Build(rng: Random): (Model?, any)
	local list = load()
	if not list then
		return nil, nil
	end
	local pick = list[rng:NextInteger(1, #list)]
	local info = pick.Info
	local model = pick.Template:Clone()
	model.Name = "Ped"
	local bones = bonesOf(model, info.Id)
	for _, name in PedModelData.Bones do
		if not bones[name] then
			if not warned then
				warned = true
				warn("[PedMeshRig] Ped_" .. info.Id .. " modelinde " .. name .. " kemiği yok; eski yaya kullanılacak")
			end
			model:Destroy()
			return nil, nil
		end
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	-- ölçek: bacak boyu (uyluk + baldır) hedef boya
	local function wp(n: string): Vector3
		return bones[n].WorldPosition
	end
	local legNow = (wp("LThigh") - wp("LCalf")).Magnitude + (wp("LCalf") - wp("LFoot")).Magnitude
	local variety = rng:NextNumber(0.96, 1.04)
	local studsPerM = STUDS_PER_M * variety
	local legStuds = info.LegM * studsPerM
	model:ScaleTo(model:GetScale() * legStuds / legNow)

	-- karakter çerçevesi: kalça noktasında, sağ = sol uyluk → sağ uyluk, yukarı = kalça → baş, ön = −Z
	local pelvis = wp("Pelvis")
	local up = (wp("Head") - pelvis).Unit
	local right = wp("RThigh") - wp("LThigh")
	right = (right - up * right:Dot(up)).Unit
	local char = CFrame.fromMatrix(pelvis, right, up)

	-- kök: kalça noktasında görünmez, sabit parça (PedRenderer.Place onu taşır); model parçaları köke kaynaklı
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(1.6, 2.6, 1)
	root.CFrame = char
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	for _, p in parts do
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end

	-- dinlenme yönleri (karakter ekseninde) ve kol indirme dönüşleri
	local rest: { [Instance]: CFrame } = {}
	for _, b in bones do
		rest[b] = char:ToObjectSpace(b.WorldCFrame).Rotation
	end
	local function charPos(n: string): Vector3
		return char:PointToObjectSpace(wp(n))
	end
	local down = {
		L = rotateTo((charPos("LForearm") - charPos("LUpperArm")).Unit, Vector3.new(-math.sin(ARM_OUT), -math.cos(ARM_OUT), 0)),
		R = rotateTo((charPos("RForearm") - charPos("RUpperArm")).Unit, Vector3.new(math.sin(ARM_OUT), -math.cos(ARM_OUT), 0)),
	}
	-- "düz duruş" düzeltmeleri (karakter ekseninde, dinlenme yönünün önüne): kollar gövdenin yanına iner (el ve önkol
	-- kolla birlikte), uyluk ve baldır tam dikey olur (PedAnim'in bacak IK'sı dik bacak varsayar; ayak tabanı kendi
	-- dinlenme yönünde, yere paralel kalır)
	local adjust: { [Instance]: CFrame } = {}
	local vertical = Vector3.new(0, -1, 0)
	for _, side in { "L", "R" } do
		for _, n in { "UpperArm", "Forearm", "Hand" } do
			adjust[bones[side .. n]] = down[side]
		end
		adjust[bones[side .. "Thigh"]] = rotateTo((charPos(side .. "Calf") - charPos(side .. "Thigh")).Unit, vertical)
		adjust[bones[side .. "Calf"]] = rotateTo((charPos(side .. "Foot") - charPos(side .. "Calf")).Unit, vertical)
	end
	local function adjusted(b: Instance): CFrame
		local a = adjust[b]
		return if a then a * rest[b] else rest[b]
	end
	-- sürülen kemikler: Transform = M1 · Δ · M2
	local drive = {}
	for _, n in DRIVEN do
		local b = bones[n]
		local parent = b.Parent
		local m1
		if parent and parent:IsA("Bone") and rest[parent] then
			m1 = rest[b]:Inverse() * rest[parent] * adjusted(parent):Inverse()
		else
			m1 = rest[b]:Inverse()
		end
		drive[n] = { Bone = b, M1 = m1, M2 = adjusted(b) }
	end
	local rig = {
		Mesh = true,
		Id = info.Id,
		Scale = legStuds / LEG_UNIT, -- PedAnim ölçeği (kök ofsetleri ve hız bununla)
		RootY = info.PelvisM * studsPerM, -- kalça noktasının yerden yüksekliği
		Parts = parts,
		Drive = drive,
		Fade = 0,
	}
	PedMeshRig.Neutral(rig)
	return model, rig
end

local function set(rig, name: string, delta: CFrame)
	local d = rig.Drive[name]
	d.Bone.Transform = d.M1 * delta * d.M2
end

-- PedAnim pozu (açılar radyan; kök ofseti ölçeksiz stud) → kemikler
function PedMeshRig.Pose(rig, pose)
	local k = rig.Scale
	set(rig, "Pelvis", CFrame.new(pose.RootX * k, pose.RootY * k, 0) * Angles(0, pose.RootYaw, pose.RootRoll))
	local waist = Angles(pose.WaistPitch * 0.5, pose.WaistYaw * 0.5, 0)
	set(rig, "Spine1", waist)
	set(rig, "Spine2", waist)
	local neck = Angles(pose.NeckPitch * 0.5, pose.NeckYaw * 0.5, 0)
	set(rig, "Neck", neck)
	set(rig, "Head", neck)
	set(rig, "LThigh", Angles(pose.LHip, 0, 0))
	set(rig, "LCalf", Angles(-pose.LKnee, 0, 0))
	set(rig, "LFoot", Angles(pose.LAnkle, 0, 0))
	set(rig, "RThigh", Angles(pose.RHip, 0, 0))
	set(rig, "RCalf", Angles(-pose.RKnee, 0, 0))
	set(rig, "RFoot", Angles(pose.RAnkle, 0, 0))
	set(rig, "LUpperArm", Angles(pose.LShoulder, 0, pose.LShoulderRoll))
	set(rig, "RUpperArm", Angles(pose.RShoulder, 0, pose.RShoulderRoll))
	set(rig, "LForearm", Angles(pose.LElbow, 0, 0))
	set(rig, "RForearm", Angles(pose.RElbow, 0, 0))
end

local ZERO = {
	RootX = 0, RootY = 0, RootYaw = 0, RootRoll = 0, WaistPitch = 0, WaistYaw = 0, NeckPitch = 0, NeckYaw = 0,
	LHip = 0, LKnee = 0, LAnkle = 0, RHip = 0, RKnee = 0, RAnkle = 0,
	LShoulder = 0, LShoulderRoll = 0, RShoulder = 0, RShoulderRoll = 0, LElbow = 0, RElbow = 0,
}

-- Ayakta, kollar yanda
function PedMeshRig.Neutral(rig)
	PedMeshRig.Pose(rig, ZERO)
end

-- 0 görünür … 1 görünmez (yerel)
function PedMeshRig.SetFade(rig, fade: number)
	for _, p in rig.Parts do
		p.LocalTransparencyModifier = fade
	end
end

return PedMeshRig
