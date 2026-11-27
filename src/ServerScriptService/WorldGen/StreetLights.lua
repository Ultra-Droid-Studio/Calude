-- StreetLights: sokak lambalarını 3D modelle kurar (dış model: "Various Low-Poly Street Lights" — KMB3D, CC-BY-4.0).
--
-- Akış: tools/streetlights_convert.py → assets/streetlights/StreetLights.glb → Studio "Import 3D" → içe aktarılan
-- modeli ServerStorage'a taşı ve adını "StreetLightModels" yap (ReplicatedStorage'da da aranır). Model yoksa
-- PropBuilder eski prosedürel lambayı kurar (oyun her durumda çalışır).
--
-- Her lamba tipi iki MeshPart: StreetLight_<Tip>_Pole (direk) ve StreetLight_<Tip>_Lamp (lamba camı). Parçalar adla
-- bulunur (içe aktarmanın klasör yapısı önemli değil). Konum/ölçek StreetLightData'daki ölçülerden: direğin taban
-- merkezi = lambanın kökü, kol yola (−Z) bakar — PropBuilder'ın eski lambasıyla aynı yön.
-- Gece: lamba camı "StreetLamp" etiketini alır → WeatherService eskisi gibi yakar/söndürür (ışık her N lambada bir).

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapDefinitions = require(ReplicatedStorage.Shared.MapDefinitions)
local Config = require(ReplicatedStorage.Shared.Config)
local StreetLightData = require(script.Parent.StreetLightData)

local StreetLights = {}

local FOLDER_NAME = "StreetLightModels"
local STUDS_PER_METRE = 3.5 -- 5 m'lik lamba ≈ 17.5 stud (eski prosedürel lamba 18 stud)
local POLE_COLOR = Color3.fromRGB(52, 54, 58)
local LAMP_OFF = Color3.fromRGB(170, 170, 160) -- WeatherService'in sönük lamba rengiyle aynı

-- Bölge → lamba tipi (şehir kimliği: sahilde küre lambalar, eski mahallede klasik fener, merkezde modern kol ...)
local DISTRICT_STYLE = {
	centro = "Arm",
	costa = "Globe", coral = "Globe", mirador = "Globe",
	riverside = "Classic",
	vista = "Lantern", drycreek = "Lantern", pinebrook = "Lantern",
	palm = "Crook", bayview = "Twin",
	airport = "Double",
	ironside = "Arm",
}
local DEFAULT_STYLE = "Arm"

local templates: { [string]: any }? = nil
local searched = false

local function measure(minV, maxV)
	return Vector3.new(maxV[1] - minV[1], maxV[2] - minV[2], maxV[3] - minV[3]),
		Vector3.new((maxV[1] + minV[1]) / 2, (maxV[2] + minV[2]) / 2, (maxV[3] + minV[3]) / 2)
end

-- İçe aktarılan şablonları bul ve ölç. Eksen uyuşmazlığı varsa o tip kullanılmaz (uyarı + eski lamba).
local function loadTemplates()
	if searched then
		return templates
	end
	searched = true
	local folder = ServerStorage:FindFirstChild(FOLDER_NAME) or ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		return nil
	end
	local found = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("MeshPart") then
			local key, role = string.match(d.Name, "^StreetLight_(%w+)_(%a+)$")
			if key and (role == "Pole" or role == "Lamp") then
				found[key] = found[key] or {}
				found[key][role] = d
			end
		end
	end
	local result = {}
	for key, parts in found do
		local data = StreetLightData[key]
		if data and parts.Pole and parts.Lamp then
			local poleSize, poleCenter = measure(data.PoleMin, data.PoleMax)
			local s = parts.Pole.Size.Y / poleSize.Y -- içe aktarmanın stud/metre oranı
			local expectX, expectZ = poleSize.X * s, poleSize.Z * s
			if math.abs(parts.Pole.Size.X - expectX) > expectX * 0.2 + 0.05 or math.abs(parts.Pole.Size.Z - expectZ) > expectZ * 0.2 + 0.05 then
				warn("[StreetLights] " .. key .. ": şablonun eksenleri beklenenle uyuşmuyor (içe aktarmada döndürülmüş olabilir); eski lamba kullanılacak")
			else
				local base = parts.Pole.CFrame * CFrame.new(-poleCenter * s) -- direğin taban merkezi
				result[key] = {
					Pole = parts.Pole, Lamp = parts.Lamp, Base = base,
					Scale = STUDS_PER_METRE / s,
				}
			end
		end
	end
	if next(result) == nil then
		warn("[StreetLights] " .. FOLDER_NAME .. " bulundu ama kullanılabilir lamba yok; eski lambalar kullanılacak")
		return nil
	end
	templates = result
	local keys = {}
	for k in result do
		table.insert(keys, k)
	end
	table.sort(keys)
	print("[StreetLights] 3D lambalar kullanılıyor:", table.concat(keys, ", "))
	return templates
end

function StreetLights.Available(): boolean
	return loadTemplates() ~= nil
end

-- (x, z) noktasını içeren en küçük bölge
local districtCache = nil
local function districtAt(x: number, z: number): string?
	if not districtCache then
		districtCache = MapDefinitions.GetData().Districts
	end
	local best, bestArea = nil, math.huge
	for _, d in districtCache do
		if x >= d.Min.X and x <= d.Max.X and z >= d.Min.Y and z <= d.Max.Y then
			local area = (d.Max.X - d.Min.X) * (d.Max.Y - d.Min.Y)
			if area < bestArea then
				best, bestArea = d.Id, area
			end
		end
	end
	return best
end

function StreetLights.StyleAt(x: number, z: number): string
	local district = districtAt(x, z)
	return (district and DISTRICT_STYLE[district]) or DEFAULT_STYLE
end

local function place(kit, folder: Instance, template: BasePart, t, cf: CFrame): BasePart
	local part = template:Clone()
	local rel = t.Base:ToObjectSpace(template.CFrame)
	part.Size = template.Size * t.Scale
	part.CFrame = cf * CFrame.new(rel.Position * t.Scale) * rel.Rotation
	part.Anchored = true
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	kit:_tick()
	return part
end

-- Bir lamba kurar. Şablon yoksa false döner (PropBuilder eski lambayı kurar).
-- cf: lambanın tabanı (kaldırım üstü), −Z yola bakar. index: lamba sırası (ışık her N lambada bir).
function StreetLights.Place(kit, folder: Instance, cf: CFrame, p, index: number): boolean
	local all = loadTemplates()
	if not all then
		return false
	end
	local t = all[StreetLights.StyleAt(p.X, p.Z)] or all[DEFAULT_STYLE]
	if not t then
		local _, any = next(all)
		t = any
	end
	local pole = place(kit, folder, t.Pole, t, cf)
	pole.Name = "LampPole"
	pole.Color = POLE_COLOR
	pole.Material = Enum.Material.Metal
	local head = place(kit, folder, t.Lamp, t, cf)
	head.Name = "LampHead"
	head.Color = LAMP_OFF
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	if index % Config.World.LampLightEvery == 0 then
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 36
		light.Angle = 110
		light.Brightness = 2.2
		light.Color = Color3.fromRGB(255, 214, 160)
		light.Shadows = false
		light.Enabled = false
		light.Parent = head
	end
	kit:Tag(head, "StreetLamp") -- ışık eklendikten SONRA etiketle (WeatherService anında açabilsin)
	return true
end

return StreetLights
