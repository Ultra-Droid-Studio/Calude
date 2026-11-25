-- AmbientController: trafik ve yaya yapay zekâsının istemci tarafı (Aşama 6).
--
-- Mimari:
--   Shared/Ambient/TrafficGraph  şerit + kavşak grafiği (MapDefinitions'tan; RoadBuilder ile aynı geometri)
--   Shared/Ambient/PedGraph      kaldırım + geçit grafiği
--   Shared/Ambient/TrafficSim    araç yapay zekâsı (IDM, ışık/dur/yol ver, rezervasyon, engel, şerit değiştirme)
--   Shared/Ambient/PedSim        yaya yapay zekâsı (hedef, mola, geçitte bekleme, kaçınma)
--   Ambient/*Renderer            görseller + havuz (bu istemcide yerel parçalar)
--   Ambient/AmbientDebug         F7: rotalar, durma çizgileri, geçitler, durum etiketleri, istatistik
--
-- Simülasyon her oyuncunun kendi cihazında, oyuncunun çevresinde 10 Hz çalışır; görüntü her karede ara değerlenir.
-- Ağ trafiği yoktur. Işıklar sunucu saatine bağlıdır (Workspace:GetServerTimeNow) → herkes aynı ışığı görür.
-- Diğer oyuncular ve araçları engel olarak algılanır.
--
-- Çalışma anı sınır geçersiz kılma (Studio testleri için, Workspace attribute'ları):
--   AmbientEnabled (bool), AmbientMaxVehicles (sayı), AmbientMaxPedestrians (sayı)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AmbientShared = Shared:WaitForChild("Ambient")
local TrafficGraph = require(AmbientShared:WaitForChild("TrafficGraph"))
local PedGraph = require(AmbientShared:WaitForChild("PedGraph"))
local TrafficSim = require(AmbientShared:WaitForChild("TrafficSim"))
local PedSim = require(AmbientShared:WaitForChild("PedSim"))
local MapDefinitions = require(Shared:WaitForChild("MapDefinitions"))
local VehicleDefinitions = require(Shared:WaitForChild("VehicleDefinitions"))
local AmbientConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AmbientConfig"))
local Log = require(Shared.Utilities.Log).new("Ambient")

local AmbientFolder = script.Parent.Parent:WaitForChild("Ambient")
local TrafficRenderer = require(AmbientFolder:WaitForChild("TrafficRenderer"))
local PedRenderer = require(AmbientFolder:WaitForChild("PedRenderer"))
local SignalRenderer = require(AmbientFolder:WaitForChild("SignalRenderer"))
local AmbientDebug = require(AmbientFolder:WaitForChild("AmbientDebug"))

local AmbientController = {
	Name = "AmbientController",
	Priority = 40,
}

local player = Players.LocalPlayer
local controllers
local graph, pedGraph, traffic, peds
local ready = false
local vehicleModels: { [any]: Model } = {}
local pedModels: { [any]: Model } = {}
local wrecks: { { Model: Model, Ped: boolean, Until: number } } = {}
local SIM_DT = 1 / AmbientConfig.SimRate
local accumulator = 0
local active = false
local debugOn = false
local lastDebug = 0
local lastSignals = 0
local costTraffic, costPeds = 0, 0
local lightsOn = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local TCFG = AmbientConfig.Traffic
local PCFG = AmbientConfig.Pedestrians

-- ===== Yardımcılar =====
local function dayWeight(hour: number): number
	if hour >= 7 and hour < 19 then
		return 1
	elseif hour >= 22 or hour < 5 then
		return 0
	elseif hour < 7 then
		return (hour - 5) / 2
	end
	return 1 - (hour - 19) / 3
end

local function districtDensity(x: number, z: number, hour: number): number
	local d = MapDefinitions.GetDistrictAt(Vector3.new(x, 0, z))
	if not d then
		return 0.1
	end
	local w = dayWeight(hour)
	return d.NightDensity + (d.DayDensity - d.NightDensity) * w
end

local function isMobile(): boolean
	return controllers.InputController:IsTouch()
end

local function limit(kind: string): number
	local override = Workspace:GetAttribute(if kind == "Vehicles" then "AmbientMaxVehicles" else "AmbientMaxPedestrians")
	if type(override) == "number" then
		return math.max(0, math.floor(override))
	end
	local t = if kind == "Vehicles" then TCFG.MaxVehicles else PCFG.MaxPedestrians
	return if isMobile() then t.Mobile else t.Desktop
end

local function enabled(): boolean
	local override = Workspace:GetAttribute("AmbientEnabled")
	if override == false then
		return false
	end
	return AmbientConfig.Enabled
end

local function subjectPart(): BasePart?
	local nav = controllers.NavigationController
	return nav and nav:GetSubject()
end

local function shouldRun(): boolean
	if not ready or not enabled() then
		return false
	end
	local fe = controllers.FrontEndController
	local state = fe and fe:GetState()
	if state ~= "Playing" and state ~= "Paused" then
		return false
	end
	return subjectPart() ~= nil
end

-- Doğma noktası görünür mü? (uzaksa ya da ekran dışında / bir binanın arkasındaysa doğabilir)
local function canSpawn(visibleMin: number)
	return function(x: number, y: number, z: number, dist: number): boolean
		if dist >= visibleMin then
			return true
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return true
		end
		local target = Vector3.new(x, y + 2.5, z)
		local _, onScreen = camera:WorldToViewportPoint(target)
		if not onScreen then
			return true
		end
		local origin = camera.CFrame.Position
		local hit = Workspace:Raycast(origin, target - origin, rayParams)
		return hit ~= nil and (hit.Position - origin).Magnitude < (target - origin).Magnitude - 4
	end
end

local function vehicleModelOf(seat: Instance?): Model?
	local m = seat and seat:FindFirstAncestorWhichIsA("Model")
	while m and not CollectionService:HasTag(m, "Vehicle") do
		local parent = m.Parent
		m = if parent and parent:IsA("Model") then parent else nil
	end
	return m
end

-- Engeller: oyuncular (yaya ya da araçta), sahipsiz oyuncu araçları; trafik için karşıdan geçen NPC yayalar
local function gatherObstacles(focus: Vector3)
	local forTraffic, forPeds = {}, {}
	local seen = {}
	local R = TCFG.ObstacleRadius
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - focus).Magnitude < 700 then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			local model = vehicleModelOf(humanoid and humanoid.SeatPart)
			if model and model.PrimaryPart then
				if not seen[model] then
					seen[model] = true
					local c = model.PrimaryPart
					local p, vel = c.Position, c.AssemblyLinearVelocity
					table.insert(forTraffic, { X = p.X, Y = p.Y, Z = p.Z, R = R.Vehicle, Kind = "Vehicle" })
					table.insert(forPeds, { X = p.X, Z = p.Z, R = 3, Kind = "Vehicle", Speed = vel.Magnitude })
				end
			else
				local p = root.Position
				table.insert(forTraffic, { X = p.X, Y = p.Y - 2, Z = p.Z, R = R.Player, Kind = "Player" })
				table.insert(forPeds, { X = p.X, Z = p.Z, R = 2, Kind = "Player" })
			end
		end
	end
	for _, model in CollectionService:GetTagged("Vehicle") do
		if not seen[model] and model:IsA("Model") and model.PrimaryPart then
			local c = model.PrimaryPart
			local p = c.Position
			if (p - focus).Magnitude < 400 then
				seen[model] = true
				table.insert(forTraffic, { X = p.X, Y = p.Y, Z = p.Z, R = R.Vehicle, Kind = "Vehicle" })
				local speed = c.AssemblyLinearVelocity.Magnitude
				if speed > 3 then
					table.insert(forPeds, { X = p.X, Z = p.Z, R = 3, Kind = "Vehicle", Speed = speed })
				end
			end
		end
	end
	for _, p in peds.Peds do
		if p.State == "Geç" or (p.Link and p.Link.Crossing) then
			table.insert(forTraffic, { X = p.X, Y = p.Y, Z = p.Z, R = R.Pedestrian, Kind = "Pedestrian" })
		end
	end
	return forTraffic, forPeds
end

-- ===== Model eşleme =====
local function syncModels()
	for _, v in traffic.Spawned do
		if not v.Removed and not vehicleModels[v] then
			vehicleModels[v] = TrafficRenderer.Acquire(v.Kind.Id, lightsOn)
			v.PX, v.PY, v.PZ, v.PHX, v.PHZ = v.X, v.Y, v.Z, v.HX, v.HZ
		end
	end
	for _, v in traffic.Despawned do
		local model = vehicleModels[v]
		if model then
			vehicleModels[v] = nil
			TrafficRenderer.Release(model)
		end
	end
	for _, p in peds.Spawned do
		if not p.Removed and not pedModels[p] then
			pedModels[p] = PedRenderer.Acquire()
			p.PX, p.PY, p.PZ, p.PHX, p.PHZ = p.X, p.Y, p.Z, p.HX, p.HZ
			p.AnimPhase = math.random() * math.pi * 2
		end
	end
	for _, p in peds.Despawned do
		local model = pedModels[p]
		if model then
			pedModels[p] = nil
			PedRenderer.Release(model)
		end
	end
end

local function clearAll()
	if not traffic then
		return
	end
	for _, v in table.clone(traffic.Vehicles) do
		traffic:Remove(v, "Kapat")
	end
	for _, p in table.clone(peds.Peds) do
		peds:Remove(p, "Kapat")
	end
	syncModels()
	traffic.Despawned, peds.Despawned = {}, {}
	SignalRenderer.Update(graph, nil, 0, 0)
end

-- ===== Kaza: oyuncunun aracı NPC araca/yayaya çarparsa NPC fiziğe geçer (bu istemcide), sonra havuza döner =====
local function handleCollisions()
	local current = controllers.VehicleController:GetCurrent()
	if not current or not current.IsDriver or not current.Chassis then
		return
	end
	local chassis = current.Chassis
	local p = chassis.Position
	local vel = chassis.AssemblyLinearVelocity
	local myHalfLen = (current.Def.Length or 12) / 2
	for _, v in table.clone(traffic.Vehicles) do
		local dx, dz = p.X - v.X, p.Z - v.Z
		local d2 = dx * dx + dz * dz
		if d2 < 900 and math.abs(p.Y - v.Y) < 8 then
			-- 0.2 sn sonraki konum NPC kutusuna giriyor mu (sabit kutuya hızla çarpıp duvar gibi durmasın)
			local fx, fz = dx + vel.X * 0.2, dz + vel.Z * 0.2
			local along = fx * v.HX + fz * v.HZ
			local side = -fx * v.HZ + fz * v.HX
			local npcVel = Vector3.new(v.HX * v.V, 0, v.HZ * v.V)
			local rel = (vel - npcVel).Magnitude
			if math.abs(along) < v.Len / 2 + myHalfLen and math.abs(side) < v.Width / 2 + 2.5 and rel > 10 then
				local model = vehicleModels[v]
				vehicleModels[v] = nil
				traffic:Remove(v, "Kaza")
				traffic.Despawned = {}
				if model then
					TrafficRenderer.MakePhysical(model, npcVel)
					table.insert(wrecks, { Model = model, Ped = false, Until = os.clock() + 10 })
				end
			end
		end
	end
	if vel.Magnitude > 6 then
		for _, ped in table.clone(peds.Peds) do
			local dx, dz = ped.X - p.X, ped.Z - p.Z
			if dx * dx + dz * dz < (myHalfLen + 1.5) ^ 2 and math.abs(ped.Y - p.Y) < 6 then
				local model = pedModels[ped]
				pedModels[ped] = nil
				peds:Remove(ped, "Kaza")
				peds.Despawned = {}
				if model then
					PedRenderer.MakePhysical(model, vel * 0.6 + Vector3.new(0, 18, 0))
					table.insert(wrecks, { Model = model, Ped = true, Until = os.clock() + 8 })
				end
			end
		end
	end
end

local function cleanWrecks(focus: Vector3)
	local now = os.clock()
	for i = #wrecks, 1, -1 do
		local w = wrecks[i]
		local root = w.Model.PrimaryPart
		local far = not root or (root.Position - focus).Magnitude > 80 or root.Position.Y < -50
		if now > w.Until + 30 or (now > w.Until and far) then
			if w.Ped then
				PedRenderer.Release(w.Model)
			else
				TrafficRenderer.Release(w.Model)
			end
			table.remove(wrecks, i)
		end
	end
end

-- ===== Adım ve görüntü =====
local function statsText(focus: Vector3, time: number, hour: number, tDensity: number, pDensity: number): string
	local ts, pst = traffic.Stats, peds.Stats
	local stuck = 0
	for _, v in traffic.Vehicles do
		if v.Blocked > 10 then
			stuck += 1
		end
	end
	local lines = {
		string.format("TRAFİK  araç %d/%d (havuz %d)   yaya %d/%d (havuz %d)", #traffic.Vehicles, limit("Vehicles"), TrafficRenderer.PoolCount(), #peds.Peds, limit("Pedestrians"), PedRenderer.PoolCount()),
		string.format("adım  trafik %.2f ms   yaya %.2f ms (10 Hz, ort.)", costTraffic * 1000, costPeds * 1000),
		string.format("araç  doğan %d  kalkan %d  reddedilen %d", ts.Spawns, ts.Despawns, ts.Rejected),
		string.format("kavşak geçişi %d  şerit değiştirme %d  tıkalı>10sn %d", ts.Entries, ts.LaneChanges, stuck),
		string.format("yaya  doğan %d  geçiş %d  vazgeçen %d  yol yok %d", pst.Spawns, pst.Crossings, pst.GaveUp, pst.PathFail),
		string.format("ışık direği %d   kaza modeli %d", SignalRenderer.ActiveCount(), #wrecks),
		string.format("saat %02d:%02d  yoğunluk trafik %.2f  yaya %.2f", math.floor(hour), math.floor(hour % 1 * 60), tDensity, pDensity),
	}
	-- en yakın kontrollü kavşak
	local best, bestD = nil, math.huge
	for _, node in graph.Nodes do
		if node.Control ~= "Free" then
			local d = (node.X - focus.X) ^ 2 + (node.Z - focus.Z) ^ 2
			if d < bestD then
				best, bestD = node, d
			end
		end
	end
	if best then
		local text = string.format("kavşak #%d %s (%.0f stud)", best.Id, best.Control, math.sqrt(bestD))
		if best.Control == "Signal" then
			local s1, r1 = TrafficGraph.SignalState(graph, best, 1, time)
			local s2, r2 = TrafficGraph.SignalState(graph, best, 2, time)
			text ..= string.format("  faz1 %s %.0fs  faz2 %s %.0fs", s1, r1, s2, r2)
		end
		table.insert(lines, text)
	end
	table.insert(lines, "F7: kapat")
	return table.concat(lines, "\n")
end

local function simStep()
	local subject = subjectPart()
	if not subject then
		return
	end
	local focus = subject.Position
	local time = Workspace:GetServerTimeNow()
	local hour = Lighting.ClockTime
	-- önceki pozlar (ara değer için)
	for _, v in traffic.Vehicles do
		v.PX, v.PY, v.PZ, v.PHX, v.PHZ = v.X, v.Y, v.Z, v.HX, v.HZ
	end
	for _, p in peds.Peds do
		p.PX, p.PY, p.PZ, p.PHX, p.PHZ = p.X, p.Y, p.Z, p.HX, p.HZ
	end
	local forTraffic, forPeds = gatherObstacles(focus)
	local foci = { { X = focus.X, Z = focus.Z } }
	local w = dayWeight(hour)
	local here = districtDensity(focus.X, focus.Z, hour)
	local tDensity = (TCFG.NightFactor + (1 - TCFG.NightFactor) * w) * math.clamp(here * 1.25 + 0.15, 0.3, 1)
	local pDensity = peds:HourDensity(hour) * math.clamp(here * 1.2, 0.1, 1)
	local t0 = os.clock()
	traffic:Step(SIM_DT, {
		Time = time, Focus = foci, Obstacles = forTraffic, MaxVehicles = limit("Vehicles"), Density = tDensity,
		CanSpawn = canSpawn(TCFG.SpawnVisibleMin),
		DensityAt = function(x, z)
			return districtDensity(x, z, hour) * 1.25 + 0.1
		end,
	})
	local t1 = os.clock()
	peds:Step(SIM_DT, {
		Time = time, Hour = hour, Focus = foci, Obstacles = forPeds, MaxPeds = limit("Pedestrians"), Density = pDensity,
		CanSpawn = canSpawn(PCFG.SpawnVisibleMin),
		DensityAt = function(x, z)
			return districtDensity(x, z, hour) * 1.2
		end,
	})
	local t2 = os.clock()
	costTraffic += ((t1 - t0) - costTraffic) * 0.05
	costPeds += ((t2 - t1) - costPeds) * 0.05
	syncModels()
	handleCollisions()
	cleanWrecks(focus)
	-- farlar: akşam/gece
	local night = hour >= 18.5 or hour < 6.5
	if night ~= lightsOn then
		lightsOn = night
		for _, model in vehicleModels do
			TrafficRenderer.SetLights(model, night)
		end
	end
	local now = os.clock()
	if now - lastSignals > 0.25 then
		lastSignals = now
		SignalRenderer.Update(graph, focus, time, 320)
	end
	if debugOn and now - lastDebug > AmbientConfig.Debug.RefreshInterval then
		lastDebug = now
		AmbientDebug.Update({
			Graph = graph, TG = TrafficGraph, PedGraph = pedGraph, PG = PedGraph, Traffic = traffic, Peds = peds,
			VehicleModels = vehicleModels, PedModels = pedModels, Focus = focus, Time = time, Config = AmbientConfig,
			Stats = statsText(focus, time, hour, tDensity, pDensity),
		})
	end
end

local function render(dt: number, alpha: number)
	for v, model in vehicleModels do
		local root = model.PrimaryPart
		if root then
			local x = v.PX + (v.X - v.PX) * alpha
			local y = v.PY + (v.Y - v.PY) * alpha
			local z = v.PZ + (v.Z - v.PZ) * alpha
			local hx = v.PHX + (v.HX - v.PHX) * alpha
			local hz = v.PHZ + (v.HZ - v.PHZ) * alpha
			if hx * hx + hz * hz < 1e-4 then
				hx, hz = v.HX, v.HZ
			end
			local pos = Vector3.new(x, y, z)
			root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(hx, v.Slope or 0, hz))
			TrafficRenderer.SetBrake(model, v.Brake)
		end
	end
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local animR2 = PCFG.AnimateRadius * PCFG.AnimateRadius
	for p, model in pedModels do
		local x = p.PX + (p.X - p.PX) * alpha
		local y = p.PY + (p.Y - p.PY) * alpha
		local z = p.PZ + (p.Z - p.PZ) * alpha
		local hx = p.PHX + (p.HX - p.PHX) * alpha
		local hz = p.PHZ + (p.HZ - p.PHZ) * alpha
		if hx * hx + hz * hz < 1e-4 then
			hx, hz = p.HX, p.HZ
		end
		PedRenderer.Place(model, Vector3.new(x, y, z), hx, hz)
		local dx, dz = x - camPos.X, z - camPos.Z
		if dx * dx + dz * dz < animR2 then
			local moving = if p.State == "Yürü" or p.State == "Geç" then (p.Moving or 1) else 0
			p.AnimPhase = (p.AnimPhase or 0) + dt * p.Speed * 1.7 * moving
			PedRenderer.Animate(model, p.AnimPhase, math.min(moving * 1.2, 1))
		end
	end
end

local function onHeartbeat(dt: number)
	local run = shouldRun()
	if not run then
		if active then
			active = false
			clearAll()
			if debugOn then
				AmbientDebug.Disable()
			end
		end
		return
	end
	active = true
	accumulator += dt
	if accumulator > SIM_DT * 3 then
		accumulator = SIM_DT -- uzun takılmadan sonra yetişmeye çalışma (tek adım)
	end
	while accumulator >= SIM_DT do
		accumulator -= SIM_DT
		local ok, err = pcall(simStep)
		if not ok then
			Log.Error("Ambient adımı hata verdi:", err)
		end
	end
	render(dt, accumulator / SIM_DT)
end

function AmbientController:Init(allControllers)
	controllers = allControllers
end

function AmbientController:Start()
	if not AmbientConfig.Enabled then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		local data = MapDefinitions.GetData()
		local kinds = {}
		for _, k in TCFG.Kinds do
			local def = VehicleDefinitions.Get(k.Id)
			if def then
				table.insert(kinds, { Id = k.Id, Weight = k.Weight, Length = def.Length, Width = def.Width, MaxSpeed = def.MaxSpeed })
			end
		end
		local steps = 0
		graph = TrafficGraph.Build(data, TCFG, {
			Yield = function()
				steps += 1
				if steps % 2 == 0 then
					task.wait() -- kurulumu karelere yay (takılma olmasın)
				end
			end,
		})
		pedGraph = PedGraph.Build(data, graph)
		traffic = TrafficSim.new(graph, TCFG, kinds, TrafficGraph, os.clock() * 1000)
		peds = PedSim.new(pedGraph, graph, traffic, PCFG, PedGraph, TrafficGraph, os.clock() * 777)
		TrafficRenderer.Init()
		PedRenderer.Init()
		SignalRenderer.Init(graph, TrafficGraph)
		local laneCount, connCount, walkCount = #graph.Lanes, #graph.Connectors, #pedGraph.Links
		ready = true
		AmbientController._updateRayFilter()
		Log.Info(string.format("Trafik/yaya hazır: %d şerit, %d kavşak bağlantısı, %d kaldırım bağlantısı (%.0f ms)",
			laneCount, connCount, walkCount, (os.clock() - t0) * 1000))
		if walkCount == 0 then
			Log.Warn("Kaldırım grafiği boş: haritada kaldırım verisi okunamadı → yaya doğmaz (MapDefinitions kaldırım bayrağı).")
		end
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	controllers.InputController.ActionBegan:Connect(function(action: string)
		if action == "AmbientDebug" then
			debugOn = not debugOn
			if not debugOn then
				AmbientDebug.Disable()
			end
		end
	end)
	-- görünürlük ışını kendi karakterimize ve NPC'lere çarpmasın
	player.CharacterAdded:Connect(function()
		AmbientController._updateRayFilter()
	end)
end

function AmbientController._updateRayFilter()
	local filter = {}
	if player.Character then
		table.insert(filter, player.Character)
	end
	if ready then
		table.insert(filter, TrafficRenderer.Folder())
		table.insert(filter, PedRenderer.Folder())
	end
	rayParams.FilterDescendantsInstances = filter
end

-- Dış sistemler için (ör. ileride görev/polis): anlık sayılar
function AmbientController:GetCounts(): (number, number)
	if not ready then
		return 0, 0
	end
	return #traffic.Vehicles, #peds.Peds
end

return AmbientController
