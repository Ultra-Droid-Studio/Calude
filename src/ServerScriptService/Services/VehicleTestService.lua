-- VehicleTestService: otomobil fiziği test pistini kurar (Aşama 2). SADECE Studio'da ve isteğe bağlı.
--
-- Açmak: Studio'da Play'den ÖNCE Workspace'i seç → Attributes → "+" → SolaraTestCourse (boolean) = true.
-- Açıkken: test pisti kurulur, her otomobil modelinden bir tane başlangıç çizgisine dizilir ve oyuncu
-- her doğduğunda (OYNA / yeniden doğma) pistin başına ışınlanır. Canlı sunucuda hiçbir şey yapmaz.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local Log = require(Shared.Utilities.Log).new("VehicleTest")

local VehicleTestService = {
	Name = "VehicleTestService",
	Priority = 60, -- VehicleService (50) ve CharacterService (20) başladıktan sonra
}

local ATTRIBUTE = "SolaraTestCourse"

local services

local function carIds(): { string }
	local list = {}
	for id, def in VehicleDefinitions.Catalog do
		if VehicleDefinitions.UsesCarPhysics(def) then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

function VehicleTestService:Init(allServices)
	services = allServices
end

function VehicleTestService:Start()
	if not RunService:IsStudio() or workspace:GetAttribute(ATTRIBUTE) ~= true then
		if RunService:IsStudio() then
			Log.Info("Test pisti kapalı (Workspace attribute SolaraTestCourse = true ile açılır)")
		end
		return
	end
	local Course = require(ServerScriptService:WaitForChild("Testing"):WaitForChild("VehicleTestCourse"))
	local _, carSpots, playerStart = Course.Build()

	local VehicleFactory = require(ServerScriptService:WaitForChild("Vehicles"):WaitForChild("VehicleFactory"))
	for index, id in carIds() do
		local spot = carSpots[index]
		if spot then
			local def = VehicleDefinitions.Get(id)
			local cf = spot + Vector3.new(0, VehicleFactory.ComputeRideHeight(def) + 0.15, 0)
			local ok, err = pcall(function()
				services.VehicleService:SpawnVehicle(id, cf, { Seed = index, Spot = cf })
			end)
			if not ok then
				Log.Warn("Test aracı doğurulamadı:", id, err)
			end
		end
	end

	services.CharacterService.CharacterReady:Connect(function(player, character, info)
		task.wait(0.2)
		if player.Character ~= character or not character.Parent then
			return
		end
		-- sunucu ışınlaması: hareket doğrulaması bunu hile sanmasın
		character:SetAttribute("ServerTeleportAt", workspace:GetServerTimeNow())
		character:PivotTo(playerStart + Vector3.new(0, (info and info.RootHeight) or 3, 0))
	end)
	workspace:SetAttribute("SolaraTestCourseReady", true)
	Log.Info("Test pisti hazır:", #carIds(), "otomobil başlangıçta")
end

return VehicleTestService
