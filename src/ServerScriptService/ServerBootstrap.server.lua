-- ServerBootstrap: sunucudaki TEK giriş noktası.
-- Her servis bir ModuleScript'tir ve şu sözleşmeye uyar:
--   Service.Name: string
--   Service.Priority: number (küçük olan önce başlar)
--   Service:Init(services)  -- sadece hazırlık, başka servisi ÇAĞIRMAZ
--   Service:Start()         -- diğer servislerle etkileşim burada başlar
-- Bir servis hata verirse diğerleri yine başlar ve hata Output'ta açıkça görünür.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Utilities.Log).new("Bootstrap")
local RemoteRegistry = require(Shared.RemoteRegistry)

-- 1) Remote'lar her şeyden önce oluşur (istemciler bunları bekliyor)
RemoteRegistry.Build()

-- 2) Servisleri topla
local servicesFolder = ServerScriptService:WaitForChild("Services")
local services = {}
local ordered = {}

for _, moduleScript in servicesFolder:GetChildren() do
	if moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" then
			local name = result.Name or moduleScript.Name
			services[name] = result
			table.insert(ordered, result)
		else
			Log.Error("Servis yüklenemedi:", moduleScript.Name, result)
		end
	end
end

table.sort(ordered, function(a, b)
	return (a.Priority or 100) < (b.Priority or 100)
end)

-- 3) Init
for _, service in ordered do
	if type(service.Init) == "function" then
		local ok, err = pcall(service.Init, service, services)
		if not ok then
			Log.Error("Init hatası:", service.Name, err)
			service._failed = true
		end
	end
end

-- 4) Start
for _, service in ordered do
	if not service._failed and type(service.Start) == "function" then
		local ok, err = pcall(service.Start, service)
		if not ok then
			Log.Error("Start hatası:", service.Name, err)
		else
			Log.Info("Başladı:", service.Name)
		end
	end
end

Log.Info("Sunucu hazır. Servis sayısı:", #ordered)
