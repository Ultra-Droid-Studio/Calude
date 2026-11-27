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
	-- tüm kemikler ebeveyn önce sırada (ragdoll'da ileri kinematik için) ve parçaların köke göre yeri
	local order = {}
	local function visit(inst: Instance)
		for _, c in inst:GetChildren() do
			if c:IsA("Bone") then
				table.insert(order, c)
				visit(c)
			end
		end
	end
	for _, p in parts do
		visit(p)
	end
	local partOffset = {}
	for _, p in parts do
		partOffset[p] = root.CFrame:ToObjectSpace(p.CFrame)
	end
	local rig = {
		Mesh = true,
		Id = info.Id,
		Scale = legStuds / LEG_UNIT, -- PedAnim ölçeği (kök ofsetleri ve hız bununla)
		RootY = info.PelvisM * studsPerM, -- kalça noktasının yerden yüksekliği
		Parts = parts,
		Drive = drive,
		Fade = 0,
		Root = root,
		Bones = bones,
		Order = order,
		PartOffset = partOffset,
		Rag = nil, -- ragdoll durumu
		GetUp = nil, -- kalkma durumu
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

-- ===================== RAGDOLL =====================
-- Araç çarpınca: her uzva görünmez bir fizik parçası (kutu) konur, uzuvlar eklemlerle (BallSocket, açı sınırlı)
-- bağlanır, parçalar araçtan aldığı hızla savrulur. Kemikler her karede kendi parçasını izler (Bone.Transform);
-- arada kalan kemikler (omurga, köprücük, el, ayak) ebeveynlerini izler. Model (deri mesh) kalça parçasına kaynaklıdır
-- (görünür sınırları ragdoll'la birlikte gider). Durulunca ayağa kalkma: ragdoll pozundan ayakta duruş pozuna
-- yumuşak geçiş (GETUP_TIME), sonra yürüme yeniden başlar (AmbientController).
local SEGMENTS = { -- uzuv parçaları: kemik → uç noktası (bir sonraki kemik ya da uzatma), en/derinlik (stud, ölçek 1)
	{ Name = "Hips", Bone = "Pelvis", To = "Spine1", W = 1.15, D = 0.75 },
	{ Name = "Chest", Bone = "Spine2", To = "Neck", W = 1.3, D = 0.8 },
	{ Name = "Head", Bone = "Head", From = "Neck", Extend = 0.95, W = 0.7, D = 0.8 },
	{ Name = "LUpperArm", Bone = "LUpperArm", To = "LForearm", W = 0.38, D = 0.38 },
	{ Name = "LForearm", Bone = "LForearm", To = "LHand", Extra = 0.45, W = 0.32, D = 0.32 },
	{ Name = "RUpperArm", Bone = "RUpperArm", To = "RForearm", W = 0.38, D = 0.38 },
	{ Name = "RForearm", Bone = "RForearm", To = "RHand", Extra = 0.45, W = 0.32, D = 0.32 },
	{ Name = "LThigh", Bone = "LThigh", To = "LCalf", W = 0.55, D = 0.55 },
	{ Name = "LCalf", Bone = "LCalf", To = "LFoot", Extra = 0.2, W = 0.42, D = 0.42 },
	{ Name = "RThigh", Bone = "RThigh", To = "RCalf", W = 0.55, D = 0.55 },
	{ Name = "RCalf", Bone = "RCalf", To = "RFoot", Extra = 0.2, W = 0.42, D = 0.42 },
}
local JOINTS = { -- { üst parça, alt parça, eklem kemiği, koni açısı, burulma } (derece)
	{ "Hips", "Chest", "Spine2", 35, 20 },
	{ "Chest", "Head", "Head", 45, 40 },
	{ "Chest", "LUpperArm", "LUpperArm", 110, 60 },
	{ "LUpperArm", "LForearm", "LForearm", 85, 15 },
	{ "Chest", "RUpperArm", "RUpperArm", 110, 60 },
	{ "RUpperArm", "RForearm", "RForearm", 85, 15 },
	{ "Hips", "LThigh", "LThigh", 80, 25 },
	{ "LThigh", "LCalf", "LCalf", 80, 10 },
	{ "Hips", "RThigh", "RThigh", 80, 25 },
	{ "RThigh", "RCalf", "RCalf", 80, 10 },
}
local GETUP_TIME = 0.9

-- Kemiklerin şu anki dünya konumları (ileri kinematik: ebeveyn × dinlenme × Transform)
local function poseWorld(rig): { [Instance]: CFrame }
	local world = {}
	for _, b in rig.Order do
		local parent = b.Parent
		local pw = if parent and parent:IsA("Bone") then world[parent] else (parent :: BasePart).CFrame
		world[b] = pw * b.CFrame * b.Transform
	end
	return world
end

function PedMeshRig.IsDown(rig): boolean
	return rig.Rag ~= nil
end

-- Yere düşür. velocity: çarpan aracın verdiği hız (stud/sn), spin: gövde dönüşü (rad/sn)
function PedMeshRig.Ragdoll(rig, model: Model, velocity: Vector3, spin: Vector3?)
	if rig.Rag or rig.GetUp then
		return
	end
	local world = poseWorld(rig)
	local B = rig.Bones
	local k = rig.Scale
	local parts, drive, all = {}, {}, {}
	for _, seg in SEGMENTS do
		local wa = world[B[seg.Bone]]
		local a = wa.Position
		local b
		if seg.To then
			b = world[B[seg.To]].Position
			if seg.Extra then
				b += (b - a).Unit * seg.Extra * k
			end
		else
			b = a + (a - world[B[seg.From]].Position).Unit * seg.Extend * k
		end
		local dir = b - a
		local len = math.max(dir.Magnitude, 0.3)
		local up = if math.abs(dir.Unit:Dot(wa.UpVector)) < 0.9 then wa.UpVector else wa.RightVector
		local cf = CFrame.lookAt((a + b) / 2, b, up)
		local part = Instance.new("Part")
		part.Name = "Ragdoll_" .. seg.Name
		part.Size = Vector3.new(seg.W * k, seg.D * k, len)
		part.CFrame = cf
		part.Transparency = 1
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CustomPhysicalProperties = PhysicalProperties.new(1.1, 0.9, 0.05, 1, 1)
		part.Parent = model
		parts[seg.Name] = part
		table.insert(all, part)
		drive[B[seg.Bone]] = { Part = part, Offset = cf:ToObjectSpace(wa) }
	end
	for _, j in JOINTS do
		local pa, pb = parts[j[1]], parts[j[2]]
		local at = world[B[j[3]]].Position
		local frame = CFrame.fromMatrix(at, pb.CFrame.LookVector, pb.CFrame.UpVector) -- birincil eksen: alt uzvun yönü
		local a0 = Instance.new("Attachment")
		a0.CFrame = pa.CFrame:ToObjectSpace(frame)
		a0.Parent = pa
		local a1 = Instance.new("Attachment")
		a1.CFrame = pb.CFrame:ToObjectSpace(frame)
		a1.Parent = pb
		local c = Instance.new("BallSocketConstraint")
		c.Attachment0 = a0
		c.Attachment1 = a1
		c.LimitsEnabled = true
		c.UpperAngle = j[4]
		c.TwistLimitsEnabled = true
		c.TwistLowerAngle = -j[5]
		c.TwistUpperAngle = j[5]
		c.Parent = pa
	end
	for i = 1, #all do -- uzuvlar birbirine çarpmaz (titreme yok), sadece dünyaya
		for n = i + 1, #all do
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = all[i]
			nc.Part1 = all[n]
			nc.Parent = all[i]
		end
	end
	-- görünür model kalça parçasıyla gider (kökten ayrılır)
	local rootWelds = {}
	for _, p in rig.Parts do
		for _, w in p:GetChildren() do
			if w:IsA("WeldConstraint") and w.Enabled then
				w.Enabled = false
				table.insert(rootWelds, w)
			end
		end
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = parts.Hips
		weld.Part1 = p
		weld.Parent = parts.Hips
	end
	for _, part in all do
		part.AssemblyLinearVelocity = velocity
	end
	parts.Hips.AssemblyAngularVelocity = spin or Vector3.zero
	rig.Rag = { Parts = parts, All = all, Drive = drive, RootWelds = rootWelds, Time = 0, Still = 0 }
end

-- Her kare: kemikler fizik parçalarını izler. Döndürür: durdu mu (yerde, hareketsiz) ve kalça konumu
function PedMeshRig.StepRagdoll(rig, dt: number): (boolean, Vector3)
	local rag = rig.Rag
	if not rag then
		return false, rig.Root.Position
	end
	local world = {}
	for _, b in rig.Order do
		local parent = b.Parent
		local pw = if parent and parent:IsA("Bone") then world[parent] else (parent :: BasePart).CFrame
		local base = pw * b.CFrame
		local d = rag.Drive[b]
		if d then
			local want = d.Part.CFrame * d.Offset
			b.Transform = base:Inverse() * want
			world[b] = want
		else
			world[b] = base * b.Transform
		end
	end
	rag.Time += dt
	local hips = rag.Parts.Hips
	if hips.AssemblyLinearVelocity.Magnitude < 1.2 then
		rag.Still += dt
	else
		rag.Still = 0
	end
	local settled = rag.Time > 6 or (rag.Time > 1.6 and rag.Still > 0.5)
	return settled, hips.Position
end

local function clearRagdoll(rig)
	local rag = rig.Rag
	if not rag then
		return
	end
	for _, part in rag.All do
		part:Destroy() -- eklemler, çarpışmama kuralları ve modele kaynak da birlikte gider
	end
	rig.Rag = nil
	return rag
end

-- Ayağa kalk: kök standing (kalça noktası, yüz yönü) konumuna konur; model ragdoll pozundan ayakta duruşa geçer
function PedMeshRig.StartGetUp(rig, standing: CFrame)
	local rag = clearRagdoll(rig)
	if not rag then
		return
	end
	local fromT, toT, meshFrom, meshTo = {}, {}, {}, {}
	for _, b in rig.Order do
		fromT[b] = b.Transform
		toT[b] = CFrame.identity
	end
	for _, d in rig.Drive do
		toT[d.Bone] = d.M1 * d.M2 -- duruş pozu (kollar yanda)
	end
	rig.Root.Anchored = true
	rig.Root.CFrame = standing
	for _, p in rig.Parts do
		p.Anchored = true
		meshFrom[p] = p.CFrame
		meshTo[p] = standing * rig.PartOffset[p]
	end
	rig.GetUp = { Time = 0, FromT = fromT, ToT = toT, MeshFrom = meshFrom, MeshTo = meshTo, RootWelds = rag.RootWelds }
end

-- Her kare; bitince true (model yeniden köke kaynaklı, yürümeye hazır)
function PedMeshRig.StepGetUp(rig, dt: number): boolean
	local g = rig.GetUp
	if not g then
		return true
	end
	g.Time += dt
	local t = math.clamp(g.Time / GETUP_TIME, 0, 1)
	local e = t * t * (3 - 2 * t)
	for p, from in g.MeshFrom do
		p.CFrame = from:Lerp(g.MeshTo[p], e)
	end
	for b, from in g.FromT do
		b.Transform = from:Lerp(g.ToT[b], e)
	end
	if t < 1 then
		return false
	end
	for _, p in rig.Parts do
		p.Anchored = false
	end
	for _, w in g.RootWelds do
		w.Enabled = true
	end
	rig.GetUp = nil
	return true
end

-- Havuza dönerken: ragdoll / kalkma yarıda kaldıysa temizle, model köke kaynaklı duruş pozunda
function PedMeshRig.Reset(rig)
	local rag = clearRagdoll(rig)
	local welds = (rag and rag.RootWelds) or (rig.GetUp and rig.GetUp.RootWelds)
	rig.GetUp = nil
	if welds then
		rig.Root.Anchored = true
		for _, p in rig.Parts do
			p.Anchored = true
			p.CFrame = rig.Root.CFrame * rig.PartOffset[p]
			p.Anchored = false
		end
		for _, w in welds do
			w.Enabled = true
		end
	end
	for _, b in rig.Order do
		b.Transform = CFrame.identity
	end
	PedMeshRig.Neutral(rig)
end

return PedMeshRig
