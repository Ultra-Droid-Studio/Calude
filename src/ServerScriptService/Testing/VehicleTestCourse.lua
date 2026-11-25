-- VehicleTestCourse: otomobil fiziği için TEKRARLANABİLİR test pisti (Aşama 2).
-- Dünya üretimine dokunmaz: Dry Creek ovasının çok üstünde (Y = 400) bağımsız bir asfalt platform kurar.
-- Her çalıştırmada birebir aynı yerleşim (rastgelelik yok).
--
-- İstasyonlar (yerel koordinat; +X ileri):
--   1 HIZLANMA + FREN      z = 0 şeridi, x 20 → 2700. 200 stud'da bir mesafe tabelası, x 1900'den sonra fren bölgesi.
--   2 SLALOM               z = 250, 9 koni / 60 stud aralık. Kapılar x 240 → 840.
--   3 KESKİN VİRAJ         x 1150 → 1300 çevresinde 180° firkete (iç yarıçap 15, dış 45). Aynı x=1150 kapısından girip çıkılır.
--   4 SKIDPAD              merkez (2050, 270), koni halkaları R 80 / 100 (sabit yarıçap → sürekli yanal g).
--   5 BOZUK YOL            z = -300, x 300 → 1200: hız tümsekleri, sağ/sol tümsekler, 0.66 stud basamak (gerçek yollardaki
--                          kavşak basamağıyla aynı), pürüzlü yama.
--   6 YÜKSEK HIZ           z = 0 şeridinde x 1450 → 1750 ani şerit değiştirme (14 stud).
-- Kapılar (görünmez, çarpışmasız) istemcideki telemetri kaydedicisi tarafından okunur (attribute: Test, Role).

local VehicleTestCourse = {}

VehicleTestCourse.Origin = Vector3.new(-3600, 400, -200)
VehicleTestCourse.FolderName = "SolaraTestCourse"

local M = Enum.Material
local rgb = Color3.fromRGB
local ASPHALT = rgb(62, 64, 68)
local PAINT = rgb(236, 236, 230)
local CONE = rgb(255, 122, 40)

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, size: Vector3, cf: CFrame)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = ASPHALT
	w.Material = M.Asphalt
	w.CanTouch = false
	w.Parent = parent
	return w
end

-- Boya: çarpışmasız, sorgulanmaz (tekerleri etkilemez)
local function paint(parent: Instance, o: Vector3, x: number, z: number, sx: number, sz: number)
	part(parent, Vector3.new(sx, 0.05, sz), CFrame.new(o + Vector3.new(x, 0.03, z)), PAINT, M.SmoothPlastic,
		{ CanCollide = false, CanQuery = false, CastShadow = false })
end

local function cone(parent: Instance, o: Vector3, x: number, z: number, test: string)
	local c = part(parent, Vector3.new(2, 1.2, 1.2), CFrame.new(o + Vector3.new(x, 1, z)) * CFrame.Angles(0, 0, math.pi / 2),
		CONE, M.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CastShadow = false })
	c.Name = "Cone"
	c:SetAttribute("Test", test)
	return c
end

local function gate(parent: Instance, o: Vector3, x: number, z: number, width: number, test: string, role: string, yaw: number?)
	local g = part(parent, Vector3.new(1, 12, width), CFrame.new(o + Vector3.new(x, 6, z)) * CFrame.Angles(0, math.rad(yaw or 0), 0),
		PAINT, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	g.Name = "Gate_" .. test .. "_" .. role
	g:SetAttribute("Test", test)
	g:SetAttribute("Role", role)
	-- yerdeki çizgi
	paint(parent, o, x, z, 1, width)
	return g
end

local function board(parent: Instance, o: Vector3, x: number, z: number, text: string, yaw: number?)
	local b = part(parent, Vector3.new(18, 6, 0.6), CFrame.new(o + Vector3.new(x, 7, z)) * CFrame.Angles(0, math.rad(yaw or 0), 0),
		rgb(24, 26, 34), M.SmoothPlastic, { CanCollide = false, CanQuery = false })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.MaxDistance = 400
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextColor3 = rgb(255, 214, 150)
		label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
		label.Text = text
		label.Parent = gui
		gui.Parent = b
	end
	return b
end

-- Pist kurulur; mevcutsa yeniden kurulur. Döndürür: klasör, araç başlangıç noktaları, oyuncu başlangıcı
function VehicleTestCourse.Build()
	local existing = workspace:FindFirstChild(VehicleTestCourse.FolderName)
	if existing then
		existing:Destroy()
	end
	local o = VehicleTestCourse.Origin
	local folder = Instance.new("Folder")
	folder.Name = VehicleTestCourse.FolderName
	folder:SetAttribute("Origin", o)

	-- Zemin ve kenar bariyerleri
	part(folder, Vector3.new(2900, 4, 1000), CFrame.new(o + Vector3.new(1350, -2, 0)), ASPHALT, M.Asphalt)
	for _, z in { -500, 500 } do
		part(folder, Vector3.new(2900, 3, 2), CFrame.new(o + Vector3.new(1350, 1.5, z)), rgb(200, 200, 196), M.Concrete)
	end
	for _, x in { -100, 2800 } do
		part(folder, Vector3.new(2, 3, 1000), CFrame.new(o + Vector3.new(x, 1.5, 0)), rgb(200, 200, 196), M.Concrete)
	end

	-- 1 HIZLANMA + FREN (+ 6 YÜKSEK HIZ aynı şeritte)
	board(folder, o, 60, -28, "1 · HIZLANMA / FREN")
	for x = 0, 2700, 50 do
		paint(folder, o, x + 12, 15, 12, 0.4)
		paint(folder, o, x + 12, -15, 12, 0.4)
	end
	for d = 200, 2600, 200 do
		board(folder, o, 20 + d, -34, tostring(d))
	end
	gate(folder, o, 20, 0, 30, "Accel", "Start")
	board(folder, o, 1900, 30, "FREN BÖLGESİ")
	-- 6 Şerit değiştirme: x 1500'de z 0 şeridi, x 1620'de z -14 şeridi (koni çiftleri)
	board(folder, o, 1420, -34, "6 · ŞERİT DEĞİŞTİR")
	for _, c in { { 1500, 0 }, { 1520, 0 }, { 1620, -14 }, { 1640, -14 }, { 1700, -14 } } do
		cone(folder, o, c[1], c[2] - 6, "LaneChange")
		cone(folder, o, c[1], c[2] + 6, "LaneChange")
	end
	gate(folder, o, 1450, -5, 40, "LaneChange", "Start")
	gate(folder, o, 1750, -10, 40, "LaneChange", "Finish")

	-- 2 SLALOM
	board(folder, o, 200, 225, "2 · SLALOM")
	for k = 0, 8 do
		cone(folder, o, 300 + 60 * k, 250, "Slalom")
	end
	gate(folder, o, 240, 250, 40, "Slalom", "Start")
	gate(folder, o, 840, 250, 40, "Slalom", "Finish")

	-- 3 KESKİN VİRAJ (180° firkete): x=1150'den +X yönünde gir (z 230..270), etrafından dön, -X yönünde çık (z 150..190)
	board(folder, o, 1100, 300, "3 · KESKİN VİRAJ")
	local pivot = Vector3.new(1300, 0, 210)
	for k = 0, 12 do
		local a = math.rad(-90 + 15 * k) -- yarım çember (sağdan dolaşma)
		local inner = pivot + Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15)
		local outer = pivot + Vector3.new(math.cos(a) * 45, 0, math.sin(a) * 45)
		cone(folder, o, inner.X, inner.Z, "Hairpin")
		cone(folder, o, outer.X, outer.Z, "Hairpin")
	end
	for x = 1160, 1300, 20 do
		cone(folder, o, x, 210, "Hairpin") -- giriş ve çıkış şeritlerini ayıran orta çizgi
	end
	gate(folder, o, 1150, 250, 40, "Hairpin", "Start")
	gate(folder, o, 1150, 170, 40, "Hairpin", "Finish")

	-- 4 SKIDPAD
	board(folder, o, 1930, 150, "4 · SKIDPAD (R 90)")
	local center = Vector3.new(2050, 0, 270)
	for k = 0, 35 do
		local a = math.rad(k * 10)
		cone(folder, o, center.X + math.cos(a) * 80, center.Z + math.sin(a) * 80, "Skidpad")
		cone(folder, o, center.X + math.cos(a) * 100, center.Z + math.sin(a) * 100, "Skidpad")
	end
	local marker = part(folder, Vector3.new(1, 1, 1), CFrame.new(o + center), PAINT, M.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	marker.Name = "SkidpadCenter"
	marker:SetAttribute("Radius", 90)

	-- 5 BOZUK YOL
	board(folder, o, 260, -330, "5 · BOZUK YOL")
	local rz = -300
	local rough = Instance.new("Folder")
	rough.Name = "RoughRoad"
	rough.Parent = folder
	-- a) hız tümsekleri: 0.35 yüksek, 6 stud uzun (rampa + rampa), 15 stud arayla
	for x = 350, 500, 15 do
		wedge(rough, Vector3.new(30, 0.35, 3), CFrame.new(o + Vector3.new(x - 1.5, 0.175, rz)) * CFrame.Angles(0, math.rad(90), 0))
		wedge(rough, Vector3.new(30, 0.35, 3), CFrame.new(o + Vector3.new(x + 1.5, 0.175, rz)) * CFrame.Angles(0, math.rad(-90), 0))
	end
	-- b) sağ/sol dönüşümlü tümsekler (gövde yatışını uyarır)
	for i, x in { 560, 590, 620, 650, 680 } do
		local side = if i % 2 == 0 then 1 else -1
		wedge(rough, Vector3.new(12, 0.5, 3), CFrame.new(o + Vector3.new(x - 1.5, 0.25, rz + side * 7)) * CFrame.Angles(0, math.rad(90), 0))
		wedge(rough, Vector3.new(12, 0.5, 3), CFrame.new(o + Vector3.new(x + 1.5, 0.25, rz + side * 7)) * CFrame.Angles(0, math.rad(-90), 0))
	end
	-- c) 0.66 stud keskin basamak (şehirdeki rampa-kavşak basamağının kopyası) — çık, 150 stud sonra in
	part(rough, Vector3.new(150, 0.66, 30), CFrame.new(o + Vector3.new(825, 0.33, rz)), ASPHALT, M.Asphalt)
	-- d) pürüzlü yama: sabit desenli 0.1–0.3 stud plakalar
	local heights = { 0.12, 0.28, 0.18, 0.3, 0.1, 0.22, 0.26, 0.14 }
	local n = 0
	for x = 960, 1140, 10 do
		for zz = -10, 10, 10 do
			n += 1
			local h = heights[(n % #heights) + 1]
			part(rough, Vector3.new(8, h, 8), CFrame.new(o + Vector3.new(x, h / 2, rz + zz)), ASPHALT, M.Asphalt)
		end
	end
	gate(folder, o, 300, rz, 34, "Rough", "Start")
	gate(folder, o, 1200, rz, 34, "Rough", "Finish")

	folder.Parent = workspace

	-- Başlangıç: araçlar x = -40'ta, +X'e bakarak (araç önü -Z → yaw -90°)
	local carSpots = {}
	for i = 0, 6 do
		table.insert(carSpots, CFrame.new(o + Vector3.new(-40, 0, -180 + 60 * i)) * CFrame.Angles(0, math.rad(-90), 0))
	end
	board(folder, o, -40, -240, "TEST ARAÇLARI · F ile bin")
	return folder, carSpots, CFrame.new(o + Vector3.new(-75, 4, -230)) * CFrame.Angles(0, math.rad(-90), 0)
end

return VehicleTestCourse
