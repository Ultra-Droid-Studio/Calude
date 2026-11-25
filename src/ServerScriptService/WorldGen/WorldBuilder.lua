-- WorldBuilder: SOLARA County'yi MapDefinitions verisinden inşa eder.
--
-- İki kullanım:
--   1) Çalışma anında (WorldService otomatik çağırır): kademeli inşa, sunucu donmaz.
--   2) Studio'da "pişirme" (bake) — Command Bar'a:
--        require(game.ServerScriptService.WorldGen.WorldBuilder).Bake()
--      Dünya Workspace'e kalıcı olarak yazılır, Studio'da görünür/düzenlenebilir olur ve
--      sunucu açılışında tekrar üretilmez (World.Baked = true).
--      Silmek için: require(...).Clear()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapDefinitions = require(ReplicatedStorage.Shared.MapDefinitions)
local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Kit)
local LandBuilder = require(script.Parent.LandBuilder)
local RoadBuilder = require(script.Parent.RoadBuilder)
local BuildingBuilder = require(script.Parent.BuildingBuilder)
local PropBuilder = require(script.Parent.PropBuilder)

local WorldBuilder = {}

-- Bu klasörler inşacıya aittir; Clear() sadece bunları siler (elle eklediklerine dokunmaz)
local GENERATED = { "Ground", "Blocks", "Coast", "Boundary", "Roads", "Sidewalks", "Buildings", "Props" }

local SHOP_TYPES = MapDefinitions.ShopTypes

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Doğma noktaları (her şeyden önce: oyuncular boşluğa düşmesin)
function WorldBuilder.BuildSpawns(kit, world: Instance)
	local folder = ensureFolder(world, "SpawnPoints")
	for _, child in folder:GetChildren() do
		if child:GetAttribute("Generated") then
			child:Destroy()
		end
	end
	local first = nil
	for index, s in MapDefinitions.GetSpawns() do
		local part = kit:Box(folder, Vector3.new(4, 1, 4), CFrame.new(s.Position.X, 0.5, s.Position.Z) * CFrame.Angles(0, math.rad(s.Yaw), 0),
			Color3.fromRGB(255, 122, 69), Enum.Material.SmoothPlastic,
			{ Transparency = 1, CanCollide = false, CanQuery = false, Name = "SpawnPoint" .. index })
		part:SetAttribute("SpawnGroup", s.Group)
		part:SetAttribute("Generated", true)
		if not first and s.Group == Config.World.DefaultSpawnGroup then
			first = s
		end
	end
	if first then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "FallbackSpawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(first.Position.X, 0.8, first.Position.Z)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn:SetAttribute("Generated", true)
		spawn.Parent = folder
	end
end

-- Dükkân girişleri ve etkileşim noktaları (Aşama 5/7 bu parçaları kullanır)
function WorldBuilder.BuildInteractionPoints(kit, world: Instance)
	local shops = ensureFolder(world, "Shops")
	local interactive = ensureFolder(world, "InteractiveLocations")
	for _, folder in { shops, interactive } do
		for _, child in folder:GetChildren() do
			if child:GetAttribute("Generated") then
				child:Destroy()
			end
		end
	end
	for _, poi in MapDefinitions.GetPOIs() do
		local parent = if SHOP_TYPES[poi.Type] then shops else interactive
		local zone = kit:Box(parent, Vector3.new(8, 8, 8), CFrame.new(poi.Entrance.X, 4.8, poi.Entrance.Z), Color3.fromRGB(255, 122, 69), Enum.Material.ForceField,
			{ Transparency = 1, CanCollide = false, CanQuery = true, Name = poi.Id, CastShadow = false })
		zone:SetAttribute("PoiId", poi.Id)
		zone:SetAttribute("PoiType", poi.Type)
		zone:SetAttribute("DisplayName", poi.Name)
		zone:SetAttribute("District", poi.District)
		zone:SetAttribute("Generated", true)
	end
end

type BuildOptions = { Yield: boolean?, OnProgress: ((string, number) -> ())? }

function WorldBuilder.Build(options: BuildOptions?)
	local opts = options or {}
	local started = os.clock()
	local kit = Kit.new(if opts.Yield == false then 0 else Config.World.BuildYieldEvery)
	local world = ensureFolder(workspace, "World")
	world:SetAttribute("WorldReady", false)

	local steps = {
		{ "Doğma noktaları", function() WorldBuilder.BuildSpawns(kit, world) end },
		{ "Zemin ve bloklar", function() LandBuilder.BuildGround(kit, world) end },
		{ "Su ve tepeler", function() LandBuilder.BuildTerrain(kit, world) end },
		{ "Kıyı ve sınırlar", function() LandBuilder.BuildCoast(kit, world) end },
		{ "Yollar", function() RoadBuilder.Build(kit, world) end },
		{ "Binalar", function() BuildingBuilder.Build(kit, world) end },
		{ "Dekor", function() PropBuilder.Build(kit, world) end },
		{ "Etkileşim noktaları", function() WorldBuilder.BuildInteractionPoints(kit, world) end },
	}
	local errors = {}
	for index, step in steps do
		local ok, err = pcall(step[2])
		if not ok then
			table.insert(errors, step[1] .. ": " .. tostring(err))
			warn("[WorldGen] Adım hatası:", step[1], err)
		end
		world:SetAttribute("BuildProgress", index / #steps)
		if opts.OnProgress then
			opts.OnProgress(step[1], index / #steps)
		end
	end

	local seconds = os.clock() - started
	world:SetAttribute("PartCount", kit.Count)
	world:SetAttribute("BuildSeconds", math.floor(seconds * 10) / 10)
	world:SetAttribute("WorldReady", true)
	print(string.format("[WorldGen] Dünya hazır: %d parça, %.1f sn, %d hata", kit.Count, seconds, #errors))
	return { PartCount = kit.Count, Seconds = seconds, Errors = errors }
end

-- clearTerrain = true ise Terrain da silinir (dikkat: elle yaptığın arazi de gider)
function WorldBuilder.Clear(clearTerrain: boolean?)
	local world = workspace:FindFirstChild("World")
	if world then
		for _, name in GENERATED do
			local f = world:FindFirstChild(name)
			if f then
				f:Destroy()
			end
		end
		for _, name in { "SpawnPoints", "Shops", "InteractiveLocations" } do
			local f = world:FindFirstChild(name)
			if f then
				for _, child in f:GetChildren() do
					if child:GetAttribute("Generated") then
						child:Destroy()
					end
				end
			end
		end
		world:SetAttribute("Baked", nil)
		world:SetAttribute("WorldReady", nil)
	end
	if clearTerrain then
		workspace.Terrain:Clear()
	end
	print("[WorldGen] Üretilmiş dünya silindi.")
end

-- Studio düzenleme modunda tek seferde inşa et ve kalıcı yap
function WorldBuilder.Bake()
	if RunService:IsRunning() then
		warn("[WorldGen] Bake sadece düzenleme modunda (Play kapalıyken) çalıştırılmalı.")
		return
	end
	WorldBuilder.Clear()
	local result = WorldBuilder.Build({ Yield = false })
	local world = workspace:FindFirstChild("World")
	if world then
		world:SetAttribute("Baked", true)
		world:SetAttribute("WorldReady", nil)
	end
	print("[WorldGen] Pişirme tamamlandı. Place'i kaydetmeyi unutma (Ctrl+S).")
	return result
end

return WorldBuilder
