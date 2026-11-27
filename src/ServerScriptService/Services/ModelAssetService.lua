-- ModelAssetService: Open Cloud ile yüklenmiş 3D modelleri (WorldGen/AssetIds) sunucu açılışında BİR KEZ indirir ve
-- oyunun aradığı yerlere koyar. Diğer servislerden önce çalışır (Priority 0; Init içinde biter), böylece dünya,
-- araçlar ve trafik başlarken modeller hazırdır.
--   Cars → ReplicatedStorage.VehicleModels.<Ad> (CarModelConfig.Models; parçalar adlarının önekiyle toplanır)
-- Studio'da elle konmuş bir klasör varsa ona dokunulmaz. Numara 0 ya da indirme başarısızsa eski görünüm kalır.
-- Sokak lambalarını WorldGen/StreetLights kendisi yükler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local InsertService = game:GetService("InsertService")

local AssetIds = require(ServerScriptService.WorldGen.AssetIds)
local CarModelConfig = require(ReplicatedStorage.Modules.CarModelConfig)

local ModelAssetService = {
	Name = "ModelAssetService",
	Priority = 0,
}

-- Asset'i indir (yoksa / hata → nil, uyarı)
function ModelAssetService.Load(key: string): Instance?
	local id = AssetIds[key] or 0
	if id <= 0 then
		return nil
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if ok and result then
		return result
	end
	warn("[ModelAssetService] " .. key .. " modeli yüklenemedi (asset " .. tostring(id) .. "): " .. tostring(result))
	return nil
end

-- Kökün altındaki, adı "<önek>_" ile başlayan parçaları yeni bir Model'e taşır
local function collect(root: Instance, prefix: string): Model?
	local model = Instance.new("Model")
	model.Name = prefix
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, #prefix + 1) == prefix .. "_" then
			d.Anchored = true
			d.Parent = model
		end
	end
	if #model:GetChildren() == 0 then
		model:Destroy()
		return nil
	end
	return model
end

local function setupCars()
	if ReplicatedStorage:FindFirstChild(CarModelConfig.Folder) then
		return -- Studio'da elle konmuş
	end
	local root = ModelAssetService.Load("Cars")
	if not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = CarModelConfig.Folder
	folder:SetAttribute("Ready", false) -- istemciler tamamı gelene kadar kullanmaz (CarModelKit)
	local found, missing = {}, {}
	for _, name in CarModelConfig.Models do
		local model = collect(root, name)
		if model then
			model.Parent = folder
			table.insert(found, name)
		else
			table.insert(missing, name)
		end
	end
	root:Destroy()
	folder.Parent = ReplicatedStorage
	folder:SetAttribute("Ready", true)
	print("[ModelAssetService] arabalar hazır:", table.concat(found, ", "))
	if #missing > 0 then
		warn("[ModelAssetService] dosyada bulunamayan arabalar:", table.concat(missing, ", "))
	end
end

function ModelAssetService:Init()
	local ok, err = pcall(setupCars)
	if not ok then
		warn("[ModelAssetService] arabalar kurulamadı:", err)
	end
end

return ModelAssetService
