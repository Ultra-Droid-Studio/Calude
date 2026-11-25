-- WorldService: Workspace.World yaşam döngüsü (Aşama 2).
--   * Dünya "pişirilmişse" (World.Baked = true) olduğu gibi kullanılır.
--   * Değilse sunucu açılışında WorldGen ile kademeli inşa edilir; doğma noktaları ve zemin
--     ilk karede hazır olur, gerisi arka planda tamamlanır.
--   * Aşama 1'in geçici test alanı (Temporary attribute'lu) kaldırılır.
-- Bölüm 30 kuralı: World altında elle eklenen hiçbir şeye dokunulmaz.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Signal = require(Shared.Utilities.Signal)
local Log = require(Shared.Utilities.Log).new("WorldService")

local WorldService = {
	Name = "WorldService",
	Priority = 1,
	WorldReady = Signal.new(),
}

local worldFolder: Folder
local ready = false

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function removePhase1TestZone()
	local districts = worldFolder:FindFirstChild("Districts")
	if districts then
		for _, child in districts:GetChildren() do
			if child:GetAttribute("Temporary") then
				child:Destroy()
				Log.Info("Aşama 1 test alanı kaldırıldı.")
			end
		end
	end
end

local function markReady()
	if ready then
		return
	end
	ready = true
	workspace:SetAttribute("WorldReady", true)
	WorldService.WorldReady:Fire()
end

function WorldService:IsReady(): boolean
	return ready
end

function WorldService:GetWorldFolder(): Folder
	return worldFolder
end

-- Belirli gruptaki doğma noktaları; grup boşsa tüm noktalar
function WorldService:GetSpawnPoints(group: string?): { BasePart }
	local wanted = group or Config.World.DefaultSpawnGroup
	local all, matching = {}, {}
	local folder = worldFolder:FindFirstChild("SpawnPoints")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and not child:IsA("SpawnLocation") then
				table.insert(all, child)
				if child:GetAttribute("SpawnGroup") == wanted then
					table.insert(matching, child)
				end
			end
		end
	end
	return if #matching > 0 then matching else all
end

function WorldService:Init()
	worldFolder = ensureFolder(workspace, "World")
	for _, name in Constants.WorldFolders do
		ensureFolder(worldFolder, name)
	end
	removePhase1TestZone()
	workspace:SetAttribute("WorldReady", false)
end

function WorldService:Start()
	if worldFolder:GetAttribute("Baked") then
		Log.Info("Pişirilmiş dünya bulundu, inşa atlandı.")
		markReady()
		return
	end
	local WorldBuilder = require(ServerScriptService:WaitForChild("WorldGen"):WaitForChild("WorldBuilder"))
	task.spawn(function()
		local ok, result = pcall(WorldBuilder.Build, { Yield = true })
		if not ok then
			Log.Error("Dünya inşası başarısız:", result)
		elseif #result.Errors > 0 then
			Log.Warn("Dünya inşa edildi ama hatalar var:", table.concat(result.Errors, " | "))
		end
		markReady()
	end)
end

return WorldService
