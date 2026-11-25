-- RemoteRegistry: TÜM remote'ların tek tanım noktası (Bölüm 25 / 26).
-- Sunucu :Build() ile ReplicatedStorage.Remotes altında oluşturur,
-- istemci :Get(grup, isim) ile bekleyerek alır. Elle remote oluşturmak yasak.
--
-- Yön etiketi sadece dokümantasyon içindir:
--   C2S = istemci → sunucu (sunucu MUTLAKA doğrular)
--   S2C = sunucu → istemci

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

RemoteRegistry.Definitions = {
	PlayerRemotes = {
		ClientReady = { Class = "RemoteEvent", Direction = "C2S" }, -- istemci yüklendi
		SessionInfo = { Class = "RemoteEvent", Direction = "S2C" }, -- mod, sürüm, sunucu saati
		Notify = { Class = "RemoteEvent", Direction = "S2C" }, -- kısa bildirim metni
	},
	-- Aşağıdaki gruplar sonraki aşamalarda doldurulacak; klasörleri şimdiden açılıyor
	VehicleRemotes = {
		RequestExit = { Class = "RemoteEvent", Direction = "C2S" }, -- araçtan in
		DriveState = { Class = "RemoteEvent", Direction = "C2S" }, -- far/sinyal/fren/korna durumu (sadece sürücü)
		RequestFlip = { Class = "RemoteEvent", Direction = "C2S" }, -- ters dönen aracı düzelt
	},
	NPCRemotes = {},
	ShopRemotes = {},
	InventoryRemotes = {},
	TradeRemotes = {},
	MultiplayerRemotes = {},
}

local ROOT_NAME = "Remotes"

function RemoteRegistry.Build()
	assert(RunService:IsServer(), "RemoteRegistry.Build sadece sunucuda çağrılır")
	local root = ReplicatedStorage:FindFirstChild(ROOT_NAME)
	if not root then
		root = Instance.new("Folder")
		root.Name = ROOT_NAME
		root.Parent = ReplicatedStorage
	end
	for groupName, remotes in RemoteRegistry.Definitions do
		local group = root:FindFirstChild(groupName)
		if not group then
			group = Instance.new("Folder")
			group.Name = groupName
			group.Parent = root
		end
		for remoteName, def in remotes do
			local existing = group:FindFirstChild(remoteName)
			if existing and existing.ClassName ~= def.Class then
				existing:Destroy()
				existing = nil
			end
			if not existing then
				local remote = Instance.new(def.Class)
				remote.Name = remoteName
				remote.Parent = group
			end
		end
	end
	return root
end

-- İstemci ve sunucu ikisi de kullanabilir. Tanımda olmayan bir remote istenirse hata verir
-- (yazım hatası sessizce sonsuz beklemeye dönüşmesin).
function RemoteRegistry.Get(groupName: string, remoteName: string, timeout: number?): Instance
	local group = RemoteRegistry.Definitions[groupName]
	assert(group, "Bilinmeyen remote grubu: " .. tostring(groupName))
	assert(group[remoteName], "Bilinmeyen remote: " .. groupName .. "." .. tostring(remoteName))

	local waitTime = timeout or 30
	local root = ReplicatedStorage:WaitForChild(ROOT_NAME, waitTime)
	assert(root, "Remotes klasörü bulunamadı (sunucu Build etmedi mi?)")
	local folder = root:WaitForChild(groupName, waitTime)
	assert(folder, "Remote grubu oluşmadı: " .. groupName)
	local remote = folder:WaitForChild(remoteName, waitTime)
	assert(remote, "Remote oluşmadı: " .. groupName .. "." .. remoteName)
	return remote
end

return RemoteRegistry
