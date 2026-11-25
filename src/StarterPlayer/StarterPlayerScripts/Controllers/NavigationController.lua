-- NavigationController: GPS durumu (Aşama 4). Hedef, rota, ilerleme, yeniden rota, varış.
-- Harita görünümleri (minimap, tam harita) sadece buradan OKUR; rota hesabı Shared/Navigation'da.
--
-- Konum kaynağı: araçtaysak aracın şasisi, değilsek karakterin kökü (MapDefinitions ile aynı dünya koordinatı).
-- Güncelleme 10 Hz; rota yalnızca hedef değişince ya da oyuncu rotadan sapınca yeniden hesaplanır.
-- Hedef yerel bir tercihtir (sunucuya gitmez); yeniden doğmada korunur.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapDefinitions = require(Shared.MapDefinitions)
local Navigation = require(Shared:WaitForChild("Navigation"))
local Signal = require(Shared.Utilities.Signal)
local Log = require(Shared.Utilities.Log).new("Navigation")

local NavigationController = {
	Name = "NavigationController",
	Priority = 7,
	DestinationChanged = Signal.new(), -- (destination | nil)
	RouteChanged = Signal.new(), -- (route | nil, status)   status: "Active" | "Unreachable" | "NoRoadNearStart" | "Cleared"
	Arrived = Signal.new(), -- (destination)
}

local UPDATE_INTERVAL = 0.1
local REROUTE_DEVIATION = 35 -- stud: rotadan bu kadar uzaklaşınca…
local REROUTE_AFTER = 1.2 -- sn sürerse yeniden hesapla
local REROUTE_COOLDOWN = 1.0
local ARRIVE_DISTANCE = 30 -- stud (≈ 8 m)

local controllers
local nav = nil
local destination = nil -- { Kind = "POI" | "Waypoint", Id, Name, Position: Vector3 }
local route = nil
local progress = nil
local status = "Idle" -- Idle | Active | Unreachable | NoRoadNearStart | Arrived
local offRouteTime = 0
local lastRouteAt = -100
local beacon: Part? = nil

-- ===== Konum =====
function NavigationController:GetSubject(): BasePart?
	local vehicle = controllers.VehicleController and controllers.VehicleController:GetCurrent()
	if vehicle and vehicle.Chassis and vehicle.Chassis.Parent then
		return vehicle.Chassis
	end
	return controllers.CharacterController:GetRootPart()
end

-- Kuzey = 0°, doğu (+X) = 90° (haritada saat yönü)
function NavigationController:GetHeading(): number
	local subject = self:GetSubject()
	if not subject then
		return 0
	end
	local look = subject.CFrame.LookVector
	return math.deg(math.atan2(look.X, -look.Z))
end

-- ===== Dünyadaki hedef işareti (sadece bu oyuncuda görünür: kameraya bağlı parça) =====
local function updateBeacon()
	if destination and status ~= "Arrived" then
		if not beacon then
			local p = Instance.new("Part")
			p.Name = "SolaraDestinationBeacon"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(64, 196, 214)
			p.Transparency = 0.6
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(260, 5, 5)
			beacon = p
		end
		local position = destination.Position
		beacon.CFrame = CFrame.new(position.X, position.Y + 130, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
		beacon.Parent = workspace.CurrentCamera
	elseif beacon then
		beacon.Parent = nil
	end
end

-- ===== Rota =====
local function recompute(reason: string)
	if not destination or not nav then
		return
	end
	local subject = NavigationController:GetSubject()
	if not subject then
		return -- karakter yok (menü): doğunca hesaplanır
	end
	lastRouteAt = os.clock()
	offRouteTime = 0
	local result, failure = nav:FindRoute(subject.Position, destination.Position)
	if result then
		route = result
		status = "Active"
		progress = Navigation.Progress(route, subject.Position, nil)
		Log.Info("Rota", reason, string.format("%.0f stud, %d manevra", route.Length, #route.Maneuvers))
	else
		route = nil
		progress = nil
		status = failure or "Unreachable"
		Log.Info("Rota bulunamadı:", status)
	end
	NavigationController.RouteChanged:Fire(route, status)
	updateBeacon()
end

-- ===== Genel API =====
function NavigationController:GetDestination()
	return destination
end

function NavigationController:GetRoute()
	return route
end

function NavigationController:GetProgress()
	return progress
end

function NavigationController:GetStatus(): string
	return status
end

function NavigationController:SetDestinationPOI(poiId: string): boolean
	local poi = MapDefinitions.GetPOI(poiId)
	if not poi then
		return false
	end
	destination = { Kind = "POI", Id = poi.Id, Name = poi.Name, Type = poi.Type, Position = Vector3.new(poi.Entrance.X, 0.8, poi.Entrance.Z) }
	status = "Idle"
	NavigationController.DestinationChanged:Fire(destination)
	recompute("hedef")
	return true
end

-- Haritada işaretlenen nokta (dünya X/Z). Y: zemin seviyesi varsayılır (yükseltilmiş yollar cezalandırılır).
function NavigationController:SetWaypoint(x: number, z: number)
	local half = MapDefinitions.GetMeta().HalfSize
	x, z = math.clamp(x, -half, half), math.clamp(z, -half, half)
	destination = { Kind = "Waypoint", Id = nil, Name = nil, Position = Vector3.new(x, 0.8, z) }
	status = "Idle"
	NavigationController.DestinationChanged:Fire(destination)
	recompute("işaret")
end

function NavigationController:ClearDestination()
	destination = nil
	route = nil
	progress = nil
	status = "Idle"
	NavigationController.DestinationChanged:Fire(nil)
	NavigationController.RouteChanged:Fire(nil, "Cleared")
	updateBeacon()
end

-- ===== Döngü =====
local function step()
	if not destination then
		return
	end
	local subject = NavigationController:GetSubject()
	if not subject then
		return
	end
	if not route then
		-- karakter yoktu ya da rota bulunamamıştı: ara sıra yeniden dene (oyuncu yola çıkmış olabilir)
		if os.clock() - lastRouteAt > (if status == "Idle" then 0 else 4) then
			recompute("bekleyen")
		end
		return
	end
	local position = subject.Position
	progress = Navigation.Progress(route, position, progress and progress.Segment)
	-- Varış: hedefe yakın ya da (yol dışı bitişte) yolun sonuna gelindi ve hedef yakın
	local toDestination = (Vector3.new(position.X, 0, position.Z) - Vector3.new(destination.Position.X, 0, destination.Position.Z)).Magnitude
	if toDestination < ARRIVE_DISTANCE or (not route.Offroad and progress.Remaining < ARRIVE_DISTANCE * 0.5) then
		status = "Arrived"
		local arrivedAt = destination
		route = nil
		progress = nil
		NavigationController.RouteChanged:Fire(nil, "Arrived")
		NavigationController.Arrived:Fire(arrivedAt)
		destination = nil
		NavigationController.DestinationChanged:Fire(nil)
		updateBeacon()
		return
	end
	-- Sapma → yeniden rota
	if progress.Deviation > REROUTE_DEVIATION then
		offRouteTime += UPDATE_INTERVAL
		if offRouteTime > REROUTE_AFTER and os.clock() - lastRouteAt > REROUTE_COOLDOWN then
			recompute("sapma")
		end
	else
		offRouteTime = 0
	end
end

function NavigationController:IsRerouting(): boolean
	return offRouteTime > 0.4
end

function NavigationController:Init(allControllers)
	controllers = allControllers
end

function NavigationController:Start()
	local ok, result = pcall(function()
		return Navigation.new(MapDefinitions.GetData())
	end)
	if ok then
		nav = result
	else
		Log.Warn("Navigasyon kurulamadı:", result)
	end
	-- Yeniden doğunca (konum değişti) rota yeni konumdan
	controllers.CharacterController.CharacterChanged:Connect(function(character)
		if character and destination then
			task.delay(1, function()
				recompute("doğma")
			end)
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < UPDATE_INTERVAL then
			return
		end
		accumulator = 0
		local okStep, err = pcall(step)
		if not okStep then
			Log.Warn("Navigasyon adımı hata verdi:", err)
		end
	end)
end

return NavigationController
