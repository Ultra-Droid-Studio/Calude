-- VehicleService: araçların sunucu tarafı (Bölüm 8.3, 9, 15.2, 26, 27.2).
--   * Harita verisindeki noktalara park halindeki araçları doğurur.
--   * Binme: ProximityPrompt → sunucu doğrular (mesafe, koltuk boş mu, oyuncu canlı mı) → Sit.
--   * Sürücü koltuğu tek kişilik; sürücü olunca araç fiziğinin sahibi o oyuncu olur (gecikmesiz sürüş).
--   * İnme: istemci ister → sunucu güvenli iniş noktası bulur.
--   * Far/stop/sinyal/korna: sürücüden gelen durum doğrulanır ve herkes için uygulanır.
--   * Oyuncuya uzak park araçları sabitlenir (fizik maliyeti yok); terk edilmiş araçlar yerine döner.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteRegistry = require(Shared.RemoteRegistry)
local MapDefinitions = require(Shared.MapDefinitions)
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local RateLimiter = require(Shared.Utilities.RateLimiter)
local Signal = require(Shared.Utilities.Signal)
local Log = require(Shared.Utilities.Log).new("VehicleService")

local VehicleService = {
	Name = "VehicleService",
	Priority = 50,
	VehicleEntered = Signal.new(), -- (player, model, isDriver)
	VehicleExited = Signal.new(), -- (player, model)
}

local VehicleFactory -- Init'te yüklenir
local services
local folder: Folder
local records: { [Model]: any } = {}
local seatRecords: { [Seat]: any } = {}
local masslessBackup: { [Model]: { BasePart } } = {}

local enterLimiter = RateLimiter.new(3, 1)
local exitLimiter = RateLimiter.new(3, 1)
local stateLimiter = RateLimiter.new(20, 15)
local flipLimiter = RateLimiter.new(1, 0.33)

local ACTIVATE_RADIUS = 220 -- bu mesafede oyuncu varsa park aracı fiziğe açılır
local FREEZE_RADIUS = 320 -- herkes bu mesafeden uzaksa sabitlenir
local RESPAWN_IDLE = 300 -- sn
local MAX_ENTER_DISTANCE = 14

local HEAD_ON = Color3.fromRGB(255, 246, 225)
local HEAD_OFF = Color3.fromRGB(220, 220, 210)
local TAIL_OFF = Color3.fromRGB(120, 20, 24)
local TAIL_DIM = Color3.fromRGB(170, 24, 28)
local TAIL_BRAKE = Color3.fromRGB(255, 40, 40)
local AMBER_ON = Color3.fromRGB(255, 170, 40)
local AMBER_OFF = Color3.fromRGB(255, 150, 30)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local isHungUp: (any) -> boolean

-- ===== Yardımcılar =====
local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function excludeList(extra: { Instance }?)
	local list = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if extra then
		for _, e in extra do
			table.insert(list, e)
		end
	end
	return list
end

local function groundY(x: number, z: number, fromY: number?): number?
	groundParams.FilterDescendantsInstances = excludeList()
	local hit = workspace:Raycast(Vector3.new(x, fromY or 400, z), Vector3.new(0, -800, 0), groundParams)
	return if hit then hit.Position.Y else nil
end

local function collectLights(model: Model)
	local lights = { Head = {}, Tail = {}, Reverse = {}, IndL = {}, IndR = {}, LightBar = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Headlight" then
				table.insert(lights.Head, d)
			elseif d.Name == "TailLight" then
				table.insert(lights.Tail, d)
			elseif d.Name == "ReverseLight" then
				table.insert(lights.Reverse, d)
			elseif d.Name == "IndicatorL" then
				table.insert(lights.IndL, d)
			elseif d.Name == "IndicatorR" then
				table.insert(lights.IndR, d)
			end
		end
	end
	return lights
end

local function applyLights(record)
	local model = record.Model
	local on = model:GetAttribute("Lights") == true
	local braking = model:GetAttribute("Braking") == true
	local reversing = model:GetAttribute("Reversing") == true
	for _, p in record.Lights.Head do
		p.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Color = if on then HEAD_ON else HEAD_OFF
		local beam = p:FindFirstChild("Beam")
		if beam and beam:IsA("Light") then
			beam.Enabled = on
		end
	end
	for _, p in record.Lights.Tail do
		p.Material = if (on or braking) then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Color = if braking then TAIL_BRAKE elseif on then TAIL_DIM else TAIL_OFF
	end
	for _, p in record.Lights.Reverse do
		p.Material = if reversing then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Color = if reversing then HEAD_ON else HEAD_OFF
	end
end

local function setIndicatorPhase(record, phaseOn: boolean)
	local mode = record.Model:GetAttribute("Indicator")
	local left = phaseOn and (mode == "L" or mode == "H")
	local right = phaseOn and (mode == "R" or mode == "H")
	for _, p in record.Lights.IndL do
		p.Material = if left then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Color = if left then AMBER_ON else AMBER_OFF
	end
	for _, p in record.Lights.IndR do
		p.Material = if right then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Color = if right then AMBER_ON else AMBER_OFF
	end
end

-- Park freni: tüm motorlar sıfır hız + fren torku; direksiyon düz
local function applyParkingBrake(record)
	local brake = record.Model:GetAttribute("BrakeTorque") or 1e5
	for _, d in record.Model:GetDescendants() do
		if d:IsA("HingeConstraint") then
			d.AngularVelocity = 0
			d.MotorMaxTorque = brake
		elseif d:IsA("CylindricalConstraint") then
			d.TargetAngle = 0
		elseif d:IsA("AlignOrientation") and d.Name == "Upright" then
			d.PrimaryAxis = Vector3.new(0, 1, 0)
			d.Enabled = VehicleDefinitions.IsMotorcycle(record.Def)
		end
	end
end

local function setAnchored(record, anchored: boolean)
	if record.Anchored == anchored then
		return
	end
	record.Anchored = anchored
	VehicleFactory.SetAnchored(record.Model, anchored)
end

local function nearestPlayerDistance(position: Vector3): number
	local best = math.huge
	for _, p in Players:GetPlayers() do
		local root = getRoot(p)
		if root then
			best = math.min(best, (root.Position - position).Magnitude)
		end
	end
	return best
end

-- ===== Karakter ↔ araç =====
local function setCharacterMassless(character: Model, value: boolean)
	if value then
		local changed = {}
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") and not d.Massless then
				d.Massless = true
				table.insert(changed, d)
			end
		end
		masslessBackup[character] = changed
	else
		local changed = masslessBackup[character]
		masslessBackup[character] = nil
		if changed then
			for _, d in changed do
				if d.Parent then
					d.Massless = false
				end
			end
		end
	end
end

-- R15 avatarda elleri direksiyona / gidona yerleştir (avatar kol boyuna IK uyum sağlar)
local function addHandIK(model: Model, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	for _, side in { "Left", "Right" } do
		local target = model:FindFirstChild("Hand" .. string.sub(side, 1, 1), true)
		local root = character:FindFirstChild(side .. "UpperArm")
		local hand = character:FindFirstChild(side .. "Hand")
		if target and target:IsA("Attachment") and root and hand then
			local ik = Instance.new("IKControl")
			ik.Name = "VehicleIK_" .. side
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = root
			ik.EndEffector = hand
			ik.Target = target
			ik.Weight = 0.9
			ik.SmoothTime = 0.08
			ik.Parent = humanoid
		end
	end
end

local function removeHandIK(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, child in humanoid:GetChildren() do
			if child:IsA("IKControl") and string.sub(child.Name, 1, 10) == "VehicleIK_" then
				child:Destroy()
			end
		end
	end
end

local function onSeated(record, seat: Seat, humanoid: Humanoid)
	local character = humanoid.Parent :: Model
	local player = Players:GetPlayerFromCharacter(character)
	local isDriver = seat:GetAttribute("DriverSeat") == true
	record.Occupants[seat] = { Player = player, Character = character }
	record.LastActive = os.clock()
	setAnchored(record, false)
	setCharacterMassless(character, true)
	local prompt = seat:FindFirstChild("EnterPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	if isDriver then
		addHandIK(record.Model, character)
		record.Driver = player
		record.Model:SetAttribute("DriverUserId", if player then player.UserId else 0)
		if player then
			VehicleFactory.SetNetworkOwner(record.Model, player)
		end
		-- gece ise farlar otomatik açık
		record.Model:SetAttribute("Lights", workspace:GetAttribute("IsNight") == true)
		applyLights(record)
		local engine = record.Chassis:FindFirstChild("Engine")
		if engine and engine:IsA("Sound") then
			engine:Play()
		end
	end
	if player then
		VehicleService.VehicleEntered:Fire(player, record.Model, isDriver)
	end
end

local function onUnseated(record, seat: Seat)
	local info = record.Occupants[seat]
	record.Occupants[seat] = nil
	record.LastActive = os.clock()
	local prompt = seat:FindFirstChild("EnterPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = true
	end
	if info and info.Character then
		setCharacterMassless(info.Character, false)
		removeHandIK(info.Character)
		-- araçtan inişteki ani konum değişimi hız hilesi sanılmasın
		info.Character:SetAttribute("ServerTeleportAt", workspace:GetServerTimeNow())
	end
	if seat:GetAttribute("DriverSeat") then
		record.Driver = nil
		local model = record.Model
		model:SetAttribute("DriverUserId", nil)
		model:SetAttribute("Braking", false)
		model:SetAttribute("Reversing", false)
		model:SetAttribute("Indicator", "")
		model:SetAttribute("Lights", false)
		applyLights(record)
		setIndicatorPhase(record, false)
		for _, name in { "Engine", "Horn" } do
			local s = record.Chassis:FindFirstChild(name)
			if s and s:IsA("Sound") then
				s:Stop()
			end
		end
		-- Sahipliği sunucuya geri al ve aracı frenle (istemci son karede gaz bırakmış olabilir)
		task.delay(0.3, function()
			if record.Driver == nil and model.Parent then
				VehicleFactory.SetNetworkOwner(model, nil)
				applyParkingBrake(record)
			end
		end)
	end
	if info and info.Player then
		VehicleService.VehicleExited:Fire(info.Player, record.Model)
	end
end

local function register(model: Model, defId: string, spot: CFrame?)
	local def = VehicleDefinitions.Get(defId)
	local record = {
		Model = model,
		DefId = defId,
		Def = def,
		Chassis = model.PrimaryPart,
		Spot = spot,
		Driver = nil,
		Occupants = {},
		LastActive = os.clock(),
		Anchored = false,
		Lights = collectLights(model),
		BlinkOn = false,
	}
	records[model] = record
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") and d:GetAttribute("VehicleSeat") then
			seatRecords[d] = record
			d:GetPropertyChangedSignal("Occupant"):Connect(function()
				local hum = d.Occupant
				if hum then
					onSeated(record, d, hum)
				else
					onUnseated(record, d)
				end
			end)
			local prompt = d:FindFirstChild("EnterPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Triggered:Connect(function(player)
					VehicleService:_tryEnter(player, d)
				end)
			end
		end
	end
	model.Destroying:Connect(function()
		records[model] = nil
		for seat, r in seatRecords do
			if r == record then
				seatRecords[seat] = nil
			end
		end
	end)
	return record
end

-- Otomobil takıldı mı? (kaldırım/engel üstünde asılı: en az iki tekerlek yere değmiyor)
-- Sadece oyuncu isteğinde (oran sınırlı) çağrılır: 4 kısa ışın.
local hangParams = RaycastParams.new()
hangParams.FilterType = Enum.RaycastFilterType.Exclude
hangParams.RespectCanCollide = true
isHungUp = function(record): boolean
	local model = record.Model
	hangParams.FilterDescendantsInstances = excludeList({ model })
	local grounded = 0
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Wheel") then
			local reach = part.Size.Y / 2 + 0.6
			if workspace:Raycast(part.Position, Vector3.new(0, -reach, 0), hangParams) then
				grounded += 1
			end
		end
	end
	return grounded <= 2
end

-- ===== Genel API =====
function VehicleService:SpawnVehicle(defId: string, cframe: CFrame, options: any?)
	local model = VehicleFactory.Build(defId, cframe, options)
	if not model then
		return nil
	end
	local record = register(model, defId, if options and options.Spot then options.Spot else nil)
	if options and options.Anchored then
		setAnchored(record, true)
	end
	model.Parent = folder
	return record
end

-- Zemin yüksekliğini bulup aracı yere oturtarak doğurur
function VehicleService:SpawnAtGround(defId: string, x: number, z: number, yaw: number, options: any?)
	local def = VehicleDefinitions.Get(defId)
	if not def then
		return nil
	end
	local y = groundY(x, z) or 0
	-- Sürüş yüksekliği fabrikanın formülünden (tek kaynak; motosiklette eski değer aynen korunur)
	local ride = VehicleFactory.ComputeRideHeight(def)
	local cf = CFrame.new(x, y + ride + 0.15, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local opts = options or {}
	opts.Spot = cf
	return self:SpawnVehicle(defId, cf, opts)
end

function VehicleService:GetRecordForPlayer(player: Player)
	for _, record in records do
		for _, info in record.Occupants do
			if info.Player == player then
				return record
			end
		end
	end
	return nil
end

function VehicleService:ResetToSpot(record)
	if not record.Spot or next(record.Occupants) then
		return
	end
	setAnchored(record, true)
	record.Model:PivotTo(record.Spot)
	applyParkingBrake(record)
	record.LastActive = os.clock()
end

function VehicleService:_tryEnter(player: Player, seat: Seat)
	if not enterLimiter:Check(player) then
		return
	end
	local record = seatRecords[seat]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = getRoot(player)
	if not record or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if seat.Occupant ~= nil or humanoid.SeatPart ~= nil then
		return
	end
	if (root.Position - seat.Position).Magnitude > MAX_ENTER_DISTANCE then
		return -- mesafe doğrulaması (Bölüm 26)
	end
	setAnchored(record, false)
	seat:Sit(humanoid)
end

-- Güvenli iniş noktası: önce koltuk tarafı, sonra diğer taraf, arka, en son üst
local function findExitCFrame(record, seat: Seat, character: Model): CFrame
	local chassisCF = record.Chassis.CFrame
	local def = record.Def
	local halfW = (if def.Type == "Motorcycle" then 1.2 else def.Width / 2)
	local localSeat = chassisCF:PointToObjectSpace(seat.Position)
	local side = if localSeat.X > 0.1 then 1 else -1
	local candidates = {
		Vector3.new(side * (halfW + 2.5), 0, localSeat.Z),
		Vector3.new(-side * (halfW + 2.5), 0, localSeat.Z),
		Vector3.new(0, 0, def.Length / 2 + 3),
		Vector3.new(0, 0, -(def.Length / 2 + 3)),
	}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { record.Model, character }
	params.RespectCanCollide = true
	local from = seat.Position + Vector3.new(0, 1, 0)
	for _, offset in candidates do
		local target = chassisCF:PointToWorldSpace(offset)
		target = Vector3.new(target.X, from.Y, target.Z)
		local blocked = workspace:Raycast(from, target - from, params)
		if not blocked then
			local down = workspace:Raycast(target + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
			if down then
				local look = chassisCF.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				local pos = down.Position + Vector3.new(0, 3.2, 0)
				return CFrame.lookAt(pos, pos + (if flatLook.Magnitude > 0.01 then flatLook else Vector3.new(0, 0, -1)))
			end
		end
	end
	-- her yer kapalıysa: aracın üstü
	return CFrame.new(record.Chassis.Position + Vector3.new(0, def.Length * 0.25 + 6, 0))
end

function VehicleService:ExitVehicle(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local seat = humanoid.SeatPart
	if not seat or not seat:IsA("Seat") or not seatRecords[seat] then
		return
	end
	local record = seatRecords[seat]
	local exitCF = findExitCFrame(record, seat, character :: Model)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	task.defer(function()
		if character and character.Parent then
			(character :: Model):PivotTo(exitCF)
		end
	end)
end

-- ===== Yaşam döngüsü =====
function VehicleService:Init(allServices)
	services = allServices
	VehicleFactory = require(ServerScriptService:WaitForChild("Vehicles"):WaitForChild("VehicleFactory"))
	local body, wheels = VehicleFactory.BodyGroup, VehicleFactory.WheelGroup
	for _, group in { body, wheels } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(group)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(body, wheels, false)
	folder = workspace:FindFirstChild("Vehicles") or Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace
end

function VehicleService:Start()
	local exitRemote = RemoteRegistry.Get("VehicleRemotes", "RequestExit") :: RemoteEvent
	local stateRemote = RemoteRegistry.Get("VehicleRemotes", "DriveState") :: RemoteEvent
	local flipRemote = RemoteRegistry.Get("VehicleRemotes", "RequestFlip") :: RemoteEvent

	exitRemote.OnServerEvent:Connect(function(player)
		if exitLimiter:Check(player) then
			VehicleService:ExitVehicle(player)
		end
	end)

	stateRemote.OnServerEvent:Connect(function(player, state)
		if not stateLimiter:Check(player) or type(state) ~= "table" then
			return
		end
		local record = VehicleService:GetRecordForPlayer(player)
		if not record or record.Driver ~= player then
			return -- sadece sürücü
		end
		local model = record.Model
		if type(state.Lights) == "boolean" then
			model:SetAttribute("Lights", state.Lights)
		end
		if type(state.Braking) == "boolean" then
			model:SetAttribute("Braking", state.Braking)
		end
		if type(state.Reversing) == "boolean" then
			model:SetAttribute("Reversing", state.Reversing)
		end
		if state.Indicator == "" or state.Indicator == "L" or state.Indicator == "R" or state.Indicator == "H" then
			model:SetAttribute("Indicator", state.Indicator)
			if state.Indicator == "" then
				setIndicatorPhase(record, false)
			end
		end
		if type(state.Horn) == "boolean" then
			local horn = record.Chassis:FindFirstChild("Horn")
			if horn and horn:IsA("Sound") then
				if state.Horn and not horn.IsPlaying then
					horn:Play()
				elseif not state.Horn and horn.IsPlaying then
					horn:Stop()
				end
			end
			model:SetAttribute("Horn", state.Horn)
		end
		applyLights(record)
	end)

	flipRemote.OnServerEvent:Connect(function(player)
		if not flipLimiter:Check(player) then
			return
		end
		local record = VehicleService:GetRecordForPlayer(player)
		if not record then
			-- yakındaki (inmiş) araç da düzeltilebilir
			local root = getRoot(player)
			if root then
				for _, r in records do
					if (r.Chassis.Position - root.Position).Magnitude < 16 and not next(r.Occupants) then
						record = r
						break
					end
				end
			end
		end
		if not record then
			return
		end
		local chassis = record.Chassis
		if chassis.AssemblyLinearVelocity.Magnitude > 8 then
			return -- sadece durmuş araçlar
		end
		-- Ters/yan dönmüş araç VEYA (otomobil) tekerlekleri yere değmeyen, takılı kalmış araç
		local tipped = chassis.CFrame.UpVector.Y <= 0.6
		if not tipped and not (VehicleDefinitions.UsesCarPhysics(record.Def) and isHungUp(record)) then
			return
		end
		local look = chassis.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local pos = chassis.Position + Vector3.new(0, 4, 0)
		record.Model:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
		for _, d in record.Model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Physical") then
				d.AssemblyLinearVelocity = Vector3.zero
				d.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end)

	-- Park araçlarını dünya hazır olunca doğur
	task.spawn(function()
		local world = services.WorldService
		if world and not world:IsReady() then
			world.WorldReady:Wait()
		end
		local count = 0
		for index, spot in MapDefinitions.GetVehicleSpots() do
			local ok, err = pcall(function()
				local record = self:SpawnAtGround(spot.DefId, spot.Position.X, spot.Position.Z, spot.Yaw, { Seed = index * 7919, Anchored = true })
				if record then
					count += 1
				end
			end)
			if not ok then
				Log.Warn("Araç doğurulamadı:", spot.DefId, err)
			end
			if index % 8 == 0 then
				task.wait()
			end
		end
		Log.Info("Park halindeki araçlar:", count)
	end)

	-- Yönetim döngüsü: sabitleme, terk edilmiş araç, hız doğrulama
	local accumulator = 0
	local lastSpeedWarn = {}
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 then
			return
		end
		accumulator = 0
		local now = os.clock()
		for model, record in records do
			local chassis = record.Chassis
			if not chassis or not chassis.Parent then
				continue
			end
			local occupied = next(record.Occupants) ~= nil
			local distance = nearestPlayerDistance(chassis.Position)
			if occupied then
				record.LastActive = now
				if record.Driver then
					local speed = chassis.AssemblyLinearVelocity.Magnitude
					local limit = record.Def.MaxSpeed * 1.45 + 25
					if speed > limit and (now - (lastSpeedWarn[model] or 0)) > 10 then
						lastSpeedWarn[model] = now
						Log.Warn(string.format("Şüpheli araç hızı: %s %.0f (limit %.0f)", record.Driver.Name, speed, limit))
					end
				end
			else
				if chassis.Position.Y < -60 then
					VehicleService:ResetToSpot(record)
				elseif record.Anchored and distance < ACTIVATE_RADIUS then
					setAnchored(record, false)
				elseif not record.Anchored and distance > FREEZE_RADIUS and chassis.AssemblyLinearVelocity.Magnitude < 1 then
					setAnchored(record, true)
				end
				if record.Spot and now - record.LastActive > RESPAWN_IDLE and distance > 260
					and (chassis.Position - record.Spot.Position).Magnitude > 25 then
					VehicleService:ResetToSpot(record)
				end
			end
		end
	end)

	-- Sinyal yanıp sönme (sadece sinyali açık araçlar)
	task.spawn(function()
		local phase = false
		while true do
			task.wait(0.4)
			phase = not phase
			for _, record in records do
				local mode = record.Model:GetAttribute("Indicator")
				if mode and mode ~= "" then
					setIndicatorPhase(record, phase)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		enterLimiter:Forget(player)
		exitLimiter:Forget(player)
		stateLimiter:Forget(player)
		flipLimiter:Forget(player)
	end)
end

return VehicleService
