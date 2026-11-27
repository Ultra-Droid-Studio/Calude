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
--
-- Yaşayan Şehir: bütçe = AmbientConfig[cihaz sınıfı][Şehir yoğunluğu ayarı] × uyarlanır kalite. Cihaz sınıfı:
-- Desktop (dokunmatik değil), Tablet (dokunmatik, ekranın kısa kenarı ≥ 700), Mobile (telefon). Uyarlanır kalite:
-- kare hızı uzun süre 35'in altındaysa bütçe %10'ar azalır (en az %50), 55'in üstüne çıkınca geri artar.
-- Görünen NPC kaldırılmaz (IsVisible: ekranda ve bir bina arkasında değil).

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
local PedAnim = require(AmbientShared:WaitForChild("PedAnim"))
local Entrances = require(AmbientShared:WaitForChild("Entrances"))
local MapDefinitions = require(Shared:WaitForChild("MapDefinitions"))
local VehicleDefinitions = require(Shared:WaitForChild("VehicleDefinitions"))
local AmbientConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AmbientConfig"))
local Log = require(Shared.Utilities.Log).new("Ambient")

local AmbientFolder = script.Parent.Parent:WaitForChild("Ambient")
local TrafficRenderer = require(AmbientFolder:WaitForChild("TrafficRenderer"))
local PedRenderer = require(AmbientFolder:WaitForChild("PedRenderer"))
local SignalRenderer = require(AmbientFolder:WaitForChild("SignalRenderer"))
local DoorRenderer = require(AmbientFolder:WaitForChild("DoorRenderer"))
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
-- Kaza modelleri: yaya (ragdoll → kalkma → yürümeye devam) ya da araç (fizik → toparlanma → trafiğe dönüş).
-- Geri dönemeyenler (devrilmiş araç, yol bulamayan yaya) eskisi gibi oyuncu uzaklaşınca havuza döner.
local wrecks: { any } = {}
local SIM_DT = 1 / AmbientConfig.SimRate
local accumulator = 0
local active = false
local debugOn = false
local lastDebug = 0
local lastSignals = 0
local costTraffic, costPeds = 0, 0
local quality = 1 -- uyarlanır kalite çarpanı (0.5..1)
local frameDt = 1 / 60
local slowFor, fastFor = 0, 0
local frameNo = 0
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

local function deviceClass(): string
	if not controllers.InputController:IsTouch() then
		return "Desktop"
	end
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(800, 400)
	return if math.min(size.X, size.Y) >= 700 then "Tablet" else "Mobile"
end

local function densityPreset(): string
	local settings = controllers.SettingsController
	local value = settings and settings:Get("CityDensity")
	return if type(value) == "string" then value else "Normal"
end

-- t: sayı | { Desktop = sayı | { Low, Normal, High }, Tablet = ..., Mobile = ... }
local function budget(t: any): number
	if type(t) == "number" then
		return t
	end
	local row = t[deviceClass()] or t.Mobile or t.Desktop
	if type(row) == "number" then
		return row
	end
	return row[densityPreset()] or row.Normal
end

local function limit(kind: string): number
	local override = Workspace:GetAttribute(if kind == "Vehicles" then "AmbientMaxVehicles" else "AmbientMaxPedestrians")
	if type(override) == "number" then
		return math.max(0, math.floor(override))
	end
	local t = if kind == "Vehicles" then TCFG.MaxVehicles else PCFG.MaxPedestrians
	return math.floor(budget(t) * quality + 0.5)
end

-- Uyarlanır kalite: kare süresi ortalaması (her karede) → bütçe çarpanı
local function updateQuality(dt: number)
	frameDt += (math.min(dt, 0.25) - frameDt) * 0.05
	if frameDt > 1 / 35 then
		slowFor += dt
		fastFor = 0
		if slowFor > 3 and quality > 0.5 then
			quality = math.max(0.5, quality - 0.1)
			slowFor = 0
			Log.Info(string.format("Kare hızı düşük (%.0f FPS): NPC bütçesi %%%d", 1 / frameDt, math.round(quality * 100)))
		end
	elseif frameDt < 1 / 55 then
		fastFor += dt
		slowFor = 0
		if fastFor > 8 and quality < 1 then
			quality = math.min(1, quality + 0.1)
			fastFor = 0
		end
	else
		slowFor, fastFor = 0, 0
	end
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
	if state ~= "Playing" and state ~= "Paused" and state ~= "Entering" then
		return false -- Entering: kamera karaktere inerken şehir canlı olsun
	end
	return subjectPart() ~= nil
end

-- Nokta oyuncunun ekranında görünüyor mu? (ekran içinde ve kameradan bakışı bir binayla kapanmamış)
local function isVisible(x: number, y: number, z: number, _dist: number?): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	local target = Vector3.new(x, y + 2.5, z)
	local _, onScreen = camera:WorldToViewportPoint(target)
	if not onScreen then
		return false
	end
	local origin = camera.CFrame.Position
	local hit = Workspace:Raycast(origin, target - origin, rayParams)
	return not (hit ~= nil and (hit.Position - origin).Magnitude < (target - origin).Magnitude - 4)
end

-- Doğma noktası uygun mu? (uzaksa ya da ekran dışında / bir binanın arkasındaysa doğabilir)
local function canSpawn(visibleMin: number)
	return function(x: number, y: number, z: number, dist: number): boolean
		if dist >= visibleMin then
			return true
		end
		return not isVisible(x, y, z, dist)
	end
end

-- Bölge türüne göre araç karışımı (AmbientConfig.Traffic.DistrictMix)
local function mixAt(x: number, z: number)
	local d = MapDefinitions.GetDistrictAt(Vector3.new(x, 0, z))
	return d and TCFG.DistrictMix and TCFG.DistrictMix[d.Type] or nil
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
				local vel = root.AssemblyLinearVelocity -- yola doğru yürüyen oyuncu önceden görülsün
				table.insert(forTraffic, { X = p.X, Y = p.Y - 2, Z = p.Z, R = R.Player, Kind = "Player", VX = vel.X, VZ = vel.Z })
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
	-- kaza modelleri: yoldaki kaza aracı ve yerde yatan yaya trafiği durdurur / şerit değiştirtir
	for _, w in wrecks do
		local c = w.Model.PrimaryPart
		if c then
			local p = if w.Ped then w.Pos or c.Position else c.Position
			if (p - focus).Magnitude < 400 then
				table.insert(forTraffic, {
					X = p.X, Y = p.Y, Z = p.Z, R = if w.Ped then R.Pedestrian else R.Vehicle,
					Kind = if w.Ped then "Pedestrian" else "Vehicle",
				})
				table.insert(forPeds, { X = p.X, Z = p.Z, R = if w.Ped then 1.5 else 3, Kind = if w.Ped then "Player" else "Vehicle", Speed = 0 })
			end
		end
	end
	for _, p in peds.Peds do
		if p.State == "Geç" or (p.Link and p.Link.Crossing) then
			local spd = p.CurSpeed or 0
			table.insert(forTraffic, {
				X = p.X, Y = p.Y, Z = p.Z, R = R.Pedestrian, Kind = "Pedestrian", VX = (p.HX or 0) * spd, VZ = (p.HZ or 0) * spd,
			})
		end
	end
	return forTraffic, forPeds
end

-- ===== Model eşleme =====
local function syncModels()
	for _, v in traffic.Spawned do
		if not v.Removed and not vehicleModels[v] then
			local mix = mixAt(v.X, v.Z)
			vehicleModels[v] = TrafficRenderer.Acquire(v.Kind.Id, lightsOn, mix and mix.Taxi)
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
			p.Anim = PedAnim.new(p.Seed or math.random())
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
	for _, w in wrecks do
		if w.Ped then
			PedRenderer.Release(w.Model)
		else
			TrafficRenderer.Release(w.Model)
		end
	end
	wrecks = {}
	syncModels()
	traffic.Despawned, peds.Despawned = {}, {}
	SignalRenderer.Update(graph, nil, 0, 0)
	DoorRenderer.Update(nil, 0)
end

-- ===== Kaza: oyuncunun aracı NPC araca/yayaya çarparsa NPC fiziğe geçer (bu istemcide); yaya ragdoll olur,
-- durulunca kalkıp yürümeye, araç toparlanıp trafiğe döner (updateWrecks) =====
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
					table.insert(wrecks, {
						Model = model, Ped = false, Until = os.clock() + 10, Kind = v.Kind, Phase = "Crash", Time = 0,
						Still = 0, Retry = 0,
					})
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
					PedRenderer.Knockdown(model, vel * 0.65 + Vector3.new(0, 14, 0))
					table.insert(wrecks, {
						Model = model, Ped = true, Until = os.clock() + 8, Phase = "Down", Seed = ped.Seed,
						Speed = ped.Speed, Anim = ped.Anim, HX = ped.HX or 0, HZ = ped.HZ or 1,
					})
				end
			end
		end
	end
end

-- Yer noktası (kaza modelinin altı; NPC'ler ve kaza modelleri hariç)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false
local function groundUnder(position: Vector3, ignore: Instance): Vector3?
	groundParams.FilterDescendantsInstances = { ignore, PedRenderer.Folder(), TrafficRenderer.Folder() }
	local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), groundParams)
	return if hit then hit.Position else nil
end

-- Her kare: kaza modellerini ilerlet
local function updateWrecks(dt: number)
	local current = controllers.VehicleController:GetCurrent()
	local playerCar = current and current.Chassis
	for i = #wrecks, 1, -1 do
		local w = wrecks[i]
		if w.Ped then
			if w.Phase == "Down" then
				local settled, hips = PedRenderer.StepDown(w.Model, dt)
				w.Pos = hips
				if settled then
					local ground = groundUnder(hips, w.Model)
					if ground then
						w.Ground = ground
						w.Phase = "GetUp"
						PedRenderer.StartGetUp(w.Model, ground, w.HX, w.HZ)
					else
						w.Phase = "Lying" -- suya/boşluğa düştü: uzaklaşınca kaldırılır
					end
				end
			elseif w.Phase == "GetUp" then
				if PedRenderer.StepGetUp(w.Model, dt) then
					local g = w.Ground
					local p = peds:Rejoin(g.X, g.Z, w.HX, w.HZ, w.Seed, w.Speed, 18)
					if p then
						pedModels[p] = w.Model
						p.Anim = w.Anim or PedAnim.new(w.Seed or math.random())
						p.PX, p.PY, p.PZ, p.PHX, p.PHZ = p.X, p.Y, p.Z, p.HX, p.HZ
						-- duruş yerinden kaldırımdaki yürüme çizgisine yumuşak geçiş
						p.Return = { Offset = g - Vector3.new(p.X, p.Y, p.Z), T = 0, D = 0.9 }
						table.remove(wrecks, i)
					else
						w.Phase = "Standing" -- yakında kaldırım yok: ayakta durur, uzaklaşınca kaldırılır
						PedRenderer.Neutral(w.Model)
					end
				end
			end
		elseif w.Phase == "Crash" then
			w.Time += dt
			local speed, upright, pos, look = TrafficRenderer.CrashState(w.Model)
			if speed < 1.5 then
				w.Still += dt
			else
				w.Still = 0
			end
			local playerNear = playerCar and (playerCar.Position - pos).Magnitude < 14
			if w.Time > 1.5 and w.Still > 0.8 and not playerNear then
				if not upright then
					w.Phase = "Wreck" -- devrildi: kalır, uzaklaşınca kaldırılır
				elseif os.clock() >= w.Retry then
					w.Retry = os.clock() + 1 -- şerit doluysa saniyede bir yeniden dene
					local v = traffic:Rejoin(w.Kind, pos.X, pos.Z, look.X, look.Z, 14)
					if v then
						TrafficRenderer.Recover(w.Model)
						vehicleModels[v] = w.Model
						v.PX, v.PY, v.PZ, v.PHX, v.PHZ = v.X, v.Y, v.Z, v.HX, v.HZ
						v.Return = { Offset = pos - Vector3.new(v.X, v.Y, v.Z), HX = look.X, HZ = look.Z, T = 0, D = 1.2 }
						table.remove(wrecks, i)
					end
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
		string.format("cihaz %s  yoğunluk %s  kalite %%%d  FPS %.0f", deviceClass(), densityPreset(), math.round(quality * 100), 1 / frameDt),
		string.format("adım  trafik %.2f ms   yaya %.2f ms (%d Hz, ort.)", costTraffic * 1000, costPeds * 1000, AmbientConfig.SimRate),
		string.format("araç  doğan %d  kalkan %d  reddedilen %d", ts.Spawns, ts.Despawns, ts.Rejected),
		string.format("kavşak geçişi %d  şerit değiştirme %d  yön değiştirme %d  kilit %d  tıkalı>10sn %d", ts.Entries, ts.LaneChanges, ts.Reroutes or 0, ts.Locked or 0, stuck),
		string.format("yaya  doğan %d  geçiş %d  vazgeçen %d  yol yok %d", pst.Spawns, pst.Crossings, pst.GaveUp, pst.PathFail),
		string.format("bina  giren %d  çıkan %d  kapı hedefi %d  kapı modeli %d", pst.Entered or 0, pst.Exited or 0, pst.DoorGoals or 0, DoorRenderer.ActiveCount()),
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
		IsVisible = isVisible,
		MixAt = mixAt,
		DensityAt = function(x, z)
			return districtDensity(x, z, hour) * 1.25 + 0.1
		end,
	})
	local t1 = os.clock()
	peds:Step(SIM_DT, {
		Time = time, Hour = hour, Focus = foci, Obstacles = forPeds, MaxPeds = limit("Pedestrians"), Density = pDensity,
		CanSpawn = canSpawn(PCFG.SpawnVisibleMin),
		IsVisible = isVisible,
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
	DoorRenderer.Update(focus, peds.Time) -- yakındaki kapılar (havuzlu), yaya giriş/çıkışında açılır
	if debugOn and now - lastDebug > AmbientConfig.Debug.RefreshInterval then
		lastDebug = now
		AmbientDebug.Update({
			Graph = graph, TG = TrafficGraph, PedGraph = pedGraph, PG = PedGraph, Traffic = traffic, Peds = peds,
			VehicleModels = vehicleModels, PedModels = pedModels, Focus = focus, Time = time, Config = AmbientConfig,
			Stats = statsText(focus, time, hour, tDensity, pDensity),
		})
	end
end

local FAR_RENDER2 = 260 * 260 -- bundan uzaktaki araçlar iki karede bir konumlanır (görünmez fark, yarı maliyet)

local function render(dt: number, alpha: number)
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	frameNo += 1
	for v, model in vehicleModels do
		local root = model.PrimaryPart
		local cdx, cdz = v.X - camPos.X, v.Z - camPos.Z
		local far = cdx * cdx + cdz * cdz > FAR_RENDER2
		if root and not (far and (frameNo + v.Id) % 2 == 1) then
			local x = v.PX + (v.X - v.PX) * alpha
			local y = v.PY + (v.Y - v.PY) * alpha
			local z = v.PZ + (v.Z - v.PZ) * alpha
			local hx = v.PHX + (v.HX - v.PHX) * alpha
			local hz = v.PHZ + (v.HZ - v.PHZ) * alpha
			if hx * hx + hz * hz < 1e-4 then
				hx, hz = v.HX, v.HZ
			end
			local back = v.Return
			if back then
				-- kazadan dönüş: modelin durduğu yerden şeritteki yerine yumuşakça
				back.T += dt
				local e = math.clamp(back.T / back.D, 0, 1)
				e = e * e * (3 - 2 * e)
				x += back.Offset.X * (1 - e)
				y += back.Offset.Y * (1 - e)
				z += back.Offset.Z * (1 - e)
				hx = back.HX + (hx - back.HX) * e
				hz = back.HZ + (hz - back.HZ) * e
				if e >= 1 then
					v.Return = nil
				end
			end
			local pos = Vector3.new(x, y, z)
			root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(hx, v.Slope or 0, hz))
			TrafficRenderer.SetBrake(model, v.Brake)
			local dx, dz = x - camPos.X, z - camPos.Z
			if dx * dx + dz * dz < 14400 then
				TrafficRenderer.Spin(model, v.V, dt) -- yakındaki dış modelli araçlarda teker dönüşü
			end
		end
	end
	DoorRenderer.Animate(dt)
	local animR2 = PCFG.AnimateRadius * PCFG.AnimateRadius
	local fullAnimR2 = (PCFG.FullAnimateRadius or 45) ^ 2
	for p, model in pedModels do
		local cdx, cdz = p.X - camPos.X, p.Z - camPos.Z
		local cd2 = cdx * cdx + cdz * cdz
		if cd2 > 14400 and (frameNo + p.Id) % 2 == 1 then
			continue -- 120 studdan uzak yaya iki karede bir konumlanır
		end
		local x = p.PX + (p.X - p.PX) * alpha
		local y = p.PY + (p.Y - p.PY) * alpha
		local z = p.PZ + (p.Z - p.PZ) * alpha
		local hx = p.PHX + (p.HX - p.PHX) * alpha
		local hz = p.PHZ + (p.HZ - p.PHZ) * alpha
		if hx * hx + hz * hz < 1e-4 then
			hx, hz = p.HX, p.HZ
		end
		local back = p.Return
		if back then
			-- kazadan kalkış: durduğu yerden kaldırımdaki yürüme çizgisine yumuşakça
			back.T += dt
			local e = math.clamp(back.T / back.D, 0, 1)
			e = e * e * (3 - 2 * e)
			x += back.Offset.X * (1 - e)
			y += back.Offset.Y * (1 - e)
			z += back.Offset.Z * (1 - e)
			if e >= 1 then
				p.Return = nil
			end
		end
		PedRenderer.Place(model, Vector3.new(x, y, z), hx, hz)
		PedRenderer.SetFade(model, p.Fade or 0)
		-- animasyon LOD: 45 stud içinde her kare, 90'a kadar iki karede bir (dt birikir), ötesinde duruş pozu
		local anim = p.Anim
		if anim and cd2 < animR2 then
			p.AnimDt = (p.AnimDt or 0) + dt
			if cd2 < fullAnimR2 or (frameNo + p.Id) % 2 == 0 then
				local adt = math.min(p.AnimDt, 0.1)
				p.AnimDt = 0
				-- dönüş hızı (görüntülenen yönden) ve kapı itme
				local lastH = p.AnimHX
				local turn = 0
				if lastH then
					local cross = lastH * hz - (p.AnimHZ or 0) * hx
					local dot = lastH * hx + (p.AnimHZ or 0) * hz
					turn = -math.atan2(cross, dot) / math.max(adt, 1e-3)
				end
				p.AnimHX, p.AnimHZ = hx, hz
				-- kapıyı itme: girmeden hemen önce ve girerken, çıkarken ilk yarım saniye
				local atDoor = p.State == "Kapı" and (p.Timer or 1) < 0.6
				local inDoor = p.State == "Gir" or (p.State == "Çık" and (p.Timer or 0) < 0.6)
				local reach = if atDoor or inDoor then 1 else 0
				local k = PedRenderer.Scale(model)
				local pose = PedAnim.Step(anim, adt, (p.CurSpeed or 0) / k, turn, reach)
				PedRenderer.Pose(model, pose)
				p.Posed = true
			end
		elseif p.Posed then
			p.Posed = false
			PedRenderer.Neutral(model)
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
	updateQuality(dt)
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
	local ok, err = pcall(updateWrecks, dt)
	if not ok then
		Log.Error("Kaza güncellemesi hata verdi:", err)
	end
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
		-- bina kapıları (arsa verisinden; harita değişmez): kaldırımı kapı noktalarında böler, kapı düğümleri ekler
		pedGraph.Entrances = Entrances.Build(data, pedGraph, PedGraph, graph, {
			Yield = function()
				task.wait()
			end,
		})
		traffic = TrafficSim.new(graph, TCFG, kinds, TrafficGraph, os.clock() * 1000)
		peds = PedSim.new(pedGraph, graph, traffic, PCFG, PedGraph, TrafficGraph, os.clock() * 777)
		TrafficRenderer.Init()
		PedRenderer.Init()
		SignalRenderer.Init(graph, TrafficGraph)
		local laneCount, connCount, walkCount = #graph.Lanes, #graph.Connectors, #pedGraph.Links
		DoorRenderer.Init(pedGraph.Entrances)
		ready = true
		AmbientController._updateRayFilter()
		Log.Info(string.format("Trafik/yaya hazır: %d şerit, %d kavşak bağlantısı, %d kaldırım bağlantısı, %d bina kapısı (%.0f ms)",
			laneCount, connCount, walkCount, #pedGraph.Entrances.List, (os.clock() - t0) * 1000))
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
