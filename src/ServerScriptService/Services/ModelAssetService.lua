-- ModelAssetService: Open Cloud ile yüklenmiş 3D modelleri (WorldGen/AssetIds) sunucu açılışında BİR KEZ indirir ve
-- oyunun aradığı yerlere koyar. Diğer servislerden önce çalışır (Priority 0; Init içinde biter), böylece dünya,
-- araçlar ve trafik başlarken modeller hazırdır.
--   Cars → ReplicatedStorage.VehicleModels.<Ad> (CarModelConfig.Models; parçalar adlarının önekiyle toplanır)
--   TrafficLights → ReplicatedStorage.TrafficLightModels (TL_<Tip>_* parçaları; istemcideki SignalRenderer kullanır)
--   Pedestrians → ReplicatedStorage.PedestrianModels.Ped_<Id> (deri MeshPart + kemikleri; istemcideki PedMeshRig)
-- Studio'da elle konmuş bir klasör varsa ona dokunulmaz. Numara 0 ya da indirme başarısızsa eski görünüm kalır.
-- Sokak lambalarını WorldGen/StreetLights kendisi yükler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local InsertService = game:GetService("InsertService")

local AssetIds = require(ServerScriptService.WorldGen.AssetIds)
local CarModelConfig = require(ReplicatedStorage.Modules.CarModelConfig)
local PedModelData = require(ReplicatedStorage.Shared.PedModelData)

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

-- Kökteki "<önek>_" parçalarını, istemcilerin hazır olmadan kullanmayacağı bir klasöre koy
local function setupFolder(key: string, folderName: string, prefix: string, label: string)
	if ReplicatedStorage:FindFirstChild(folderName) then
		return -- Studio'da elle konmuş
	end
	local root = ModelAssetService.Load(key)
	if not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder:SetAttribute("Ready", false)
	local model = collect(root, prefix)
	root:Destroy()
	if not model then
		warn("[ModelAssetService] " .. label .. ": dosyada " .. prefix .. "_* parçası yok")
		folder:Destroy()
		return
	end
	model.Parent = folder
	folder.Parent = ReplicatedStorage
	folder:SetAttribute("Ready", true)
	print("[ModelAssetService] " .. label .. " hazır:", #model:GetChildren(), "parça")
end

-- Yayalar: her karakterin parçaları (Ped_<Id>*) ve kemik ağacı kendi Model'ine. Kemikler bir parçanın altında
-- olmalı: karakterin parçalarından birinin altında değilse ilk parçasına taşınır (dünya konumu korunur).
local function setupPeds()
	if ReplicatedStorage:FindFirstChild("PedestrianModels") then
		return -- Studio'da elle konmuş
	end
	local root = ModelAssetService.Load("Pedestrians")
	if not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "PedestrianModels"
	folder:SetAttribute("Ready", false)
	local found = {}
	for _, info in PedModelData.Peds do
		local prefix = "Ped_" .. info.Id
		local parts, mine, topBones = {}, {}, {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == prefix or string.sub(d.Name, 1, #prefix + 1) == prefix .. "_") then
				table.insert(parts, d)
				mine[d] = true
			end
		end
		for _, d in root:GetDescendants() do
			if d:IsA("Bone") and string.sub(d.Name, 1, #prefix + 1) == prefix .. "_" then
				local parent = d.Parent
				local parentIsOwnBone = parent and parent:IsA("Bone") and string.sub(parent.Name, 1, #prefix + 1) == prefix .. "_"
				if not parentIsOwnBone then
					table.insert(topBones, d)
				end
			end
		end
		if #parts > 0 then
			local model = Instance.new("Model")
			model.Name = prefix
			for _, b in topBones do
				local parent = b.Parent
				if not (parent and mine[parent]) then
					local world = if parent and parent:IsA("BasePart") then parent.CFrame * b.CFrame else b.WorldCFrame
					b.Parent = parts[1]
					b.CFrame = parts[1].CFrame:ToObjectSpace(world)
				end
			end
			for _, p in parts do
				p.Anchored = true
				p.Parent = model
			end
			model.PrimaryPart = parts[1]
			model.Parent = folder
			table.insert(found, info.Id)
		end
	end
	root:Destroy()
	if #found == 0 then
		warn("[ModelAssetService] yaya modeli dosyasında Ped_* parçası yok")
		folder:Destroy()
		return
	end
	folder.Parent = ReplicatedStorage
	folder:SetAttribute("Ready", true)
	print("[ModelAssetService] yayalar hazır:", table.concat(found, ", "))
end

function ModelAssetService:Init()
	local jobs = {
		{ "arabalar", setupCars },
		{ "trafik ışıkları", function()
			setupFolder("TrafficLights", "TrafficLightModels", "TL", "trafik ışıkları")
		end },
		{ "yayalar", setupPeds },
	}
	for _, job in jobs do
		local ok, err = pcall(job[2])
		if not ok then
			warn("[ModelAssetService] " .. job[1] .. " kurulamadı:", err)
		end
	end
end

return ModelAssetService
