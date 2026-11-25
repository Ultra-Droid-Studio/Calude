-- VehicleController: yerel oyuncu araçtayken sürüş (Bölüm 8.2, 8.3, 9.2, 21.2, 21.3).
--
-- Sürücü olunca araç fiziğinin ağ sahibi bu istemcidir; tekerlek motorlarını ve direksiyon servolarını
-- burada her karede ayarlarız → gecikmesiz, gerçek fizikle sürüş. Diğer oyuncular konumu çoğaltma ile görür.
-- Sunucuya sadece görsel durum (far, stop, sinyal, korna) gönderilir; sunucu sürücü olduğumuzu doğrular.
--
-- Giriş kaynakları: klavye (W/A/S/D, Space, H, F, L, Q, E, R), gamepad (tetikler + sol çubuk),
-- mobil butonlar (MobileControlsController araç düzeni). Hepsi InputController eylemlerinden geçer.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local CarPhysics = require(script.Parent.Parent:WaitForChild("Vehicles"):WaitForChild("CarPhysics"))
local RemoteRegistry = require(Shared.RemoteRegistry)
local Signal = require(Shared.Utilities.Signal)
local Maid = require(Shared.Utilities.Maid)
local Log = require(Shared.Utilities.Log).new("Vehicle")

local VehicleController = {
	Name = "VehicleController",
	Priority = 6,
	Entered = Signal.new(), -- (model, isDriver)
	Exited = Signal.new(),
}

local player = Players.LocalPlayer
local controllers
local maid = Maid.new()
local playerControls = nil

local exitRemote: RemoteEvent
local stateRemote: RemoteEvent
local flipRemote: RemoteEvent

-- Aktif araç durumu
local current = nil :: any

-- Fizik adımından önce çalışan bağlantı: PreSimulation (dt) yoksa Stepped (time, dt)
local function connectPreSimulation(fn: (number) -> ()): RBXScriptConnection
	local ok, signal = pcall(function()
		return (RunService :: any).PreSimulation
	end)
	if ok and signal then
		return signal:Connect(fn)
	end
	return RunService.Stepped:Connect(function(_, dt)
		fn(dt)
	end)
end

local function getControls()
	if playerControls then
		return playerControls
	end
	local ok, controls = pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		return playerModule:GetControls()
	end)
	if ok then
		playerControls = controls
	else
		Log.Warn("PlayerModule kontrolleri alınamadı:", controls)
	end
	return playerControls
end

local function setDefaultControls(enabled: boolean)
	local controls = getControls()
	if controls then
		pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
end

local function findVehicleModel(seat: Instance): Model?
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("VehicleId") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- ===== Gamepad analog değerleri =====
local stickX, triggerR, triggerL = 0, 0, 0

-- Motosiklet (eski fizik): tetikler dijital gibi davranır — Aşama 2 öncesiyle birebir aynı his
local function readInputs()
	local input = controllers.InputController
	local throttle = math.max(if input:IsActionActive("VehGas") then 1 else 0, if triggerR > 0.1 then 1 else 0)
	local brake = math.max(if input:IsActionActive("VehBrake") then 1 else 0, if triggerL > 0.1 then 1 else 0)
	local steer = (if input:IsActionActive("VehRight") then 1 else 0) - (if input:IsActionActive("VehLeft") then 1 else 0)
	if math.abs(stickX) > 0.15 then
		steer = stickX
	end
	local touchSteer = input:GetAnalog("VehSteer") -- mobil direksiyon pedi (Aşama 3)
	if math.abs(touchSteer) > 0.02 then
		steer = touchSteer
	end
	return throttle, brake, math.clamp(steer, -1, 1), input:IsActionActive("VehHandbrake"), input:IsActionActive("VehHorn")
end

-- Otomobil (Aşama 2): tetikler ANALOG; çubuk ölü bölgesi yeniden ölçeklenir ve hafif üstel eğri uygulanır
-- (merkez çevresinde ince ayar, uçta tam direksiyon).
local STICK_DEADZONE = 0.12
local STICK_EXPO = 1.5
local function readCarInputs()
	local input = controllers.InputController
	local throttle = math.max(if input:IsActionActive("VehGas") then 1 else 0, triggerR)
	local brake = math.max(if input:IsActionActive("VehBrake") then 1 else 0, triggerL)
	local steer = (if input:IsActionActive("VehRight") then 1 else 0) - (if input:IsActionActive("VehLeft") then 1 else 0)
	local magnitude = math.abs(stickX)
	if magnitude > STICK_DEADZONE then
		local scaled = math.clamp((magnitude - STICK_DEADZONE) / (1 - STICK_DEADZONE), 0, 1)
		steer = math.sign(stickX) * scaled ^ STICK_EXPO
	end
	local touchSteer = input:GetAnalog("VehSteer") -- mobil direksiyon pedi (eğri pedin kendisinde)
	if math.abs(touchSteer) > 0.02 then
		steer = touchSteer
	end
	return throttle, brake, math.clamp(steer, -1, 1), input:IsActionActive("VehHandbrake"), input:IsActionActive("VehHorn")
end

-- ===== Sunucuya görsel durum =====
local function pushState(force: boolean?)
	local c = current
	if not c or not c.IsDriver then
		return
	end
	local s = c.State
	local key = string.format("%s|%s|%s|%s|%s", tostring(s.Lights), s.Indicator, tostring(s.Braking), tostring(s.Reversing), tostring(s.Horn))
	local now = os.clock()
	if not force and (key == c.LastSentKey or now - c.LastSent < 0.12) then
		return
	end
	c.LastSentKey = key
	c.LastSent = now
	stateRemote:FireServer({
		Lights = s.Lights, Indicator = s.Indicator, Braking = s.Braking, Reversing = s.Reversing, Horn = s.Horn,
	})
end

-- ===== Sürüş döngüsü =====
local function setRearGrip(c, low: boolean)
	if c.LowGrip == low then
		return
	end
	c.LowGrip = low
	for _, wheel in c.RearWheels do
		wheel.CustomPhysicalProperties = PhysicalProperties.new(0.9, if low then c.Def.Grip * 0.45 else c.Def.Grip, 0, 100, 1)
	end
end

local function driveStep(dt: number)
	local c = current
	if not c or not c.IsDriver or not c.Chassis.Parent then
		return
	end
	local def = c.Def
	local chassis = c.Chassis
	local cf = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(cf.LookVector)
	local speed = velocity.Magnitude
	local throttle, brake, steerInput, handbrake, horn = readInputs()

	-- Direksiyon: yumuşak geçiş, bırakınca daha hızlı ortalanır
	local rate = if math.abs(steerInput) < 0.01 then 4.5 else 3.2
	c.Steer += math.clamp(steerInput - c.Steer, -rate * dt, rate * dt)
	local maxAngle = VehicleDefinitions.SteerAngleAt(def, speed)
	for _, steerConstraint in c.SteerConstraints do
		steerConstraint.TargetAngle = -c.Steer * maxAngle
	end

	-- Motor / fren / geri vites
	local R = def.WheelRadius
	local sign = VehicleDefinitions.DriveSign
	local driveTorque, brakeTorque, coastTorque = c.DriveTorque, c.BrakeTorque, c.CoastTorque
	local braking, reversing = false, false
	local driveVelocity, driveMax, freeMax = 0, coastTorque, coastTorque

	if throttle > 0.05 then
		if forwardSpeed < -2 then
			braking = true
			driveVelocity, driveMax, freeMax = 0, brakeTorque * throttle, brakeTorque * throttle
		else
			local taper = math.clamp(1 - (forwardSpeed / def.MaxSpeed) ^ 2, 0.12, 1)
			driveVelocity = sign * def.MaxSpeed / R
			driveMax = driveTorque * taper * throttle
			freeMax = 0 -- tahriksiz tekerlekler serbest döner
		end
	elseif brake > 0.05 then
		if forwardSpeed > 2 then
			braking = true
			driveVelocity, driveMax, freeMax = 0, brakeTorque * brake, brakeTorque * brake
		else
			reversing = true
			driveVelocity = -sign * def.ReverseSpeed / R
			driveMax = driveTorque * 0.6 * brake
			freeMax = 0
		end
	end

	for _, motor in c.Motors do
		local isRear = motor:GetAttribute("Rear") == true
		if handbrake and isRear then
			motor.AngularVelocity = 0
			motor.MotorMaxTorque = brakeTorque * 1.6
		elseif motor:GetAttribute("Driven") then
			motor.AngularVelocity = driveVelocity
			motor.MotorMaxTorque = driveMax
		else
			motor.AngularVelocity = 0
			motor.MotorMaxTorque = if braking then brakeTorque * math.max(throttle, brake) else freeMax
		end
	end
	setRearGrip(c, handbrake and speed > 8)

	-- Motosiklet: dik durma + viraj yatışı
	if c.Upright then
		local forward = cf.LookVector
		local right = forward:Cross(Vector3.yAxis)
		if right.Magnitude > 0.05 then
			right = right.Unit
			local baseUp = right:Cross(forward).Unit
			local lean = c.Steer * math.clamp(speed / 25, 0, 1) * math.rad(def.MaxLean or 30)
			c.Lean = lean
			c.Upright.PrimaryAxis = (baseUp * math.cos(lean) + right * math.sin(lean)).Unit
		end
	else
		-- Araba: uzun süre ters kalırsa otomatik düzeltme isteği
		if cf.UpVector.Y < 0.3 and speed < 4 then
			c.FlipTimer += dt
			if c.FlipTimer > 2.5 then
				c.FlipTimer = -4
				flipRemote:FireServer()
			end
		else
			c.FlipTimer = math.max(c.FlipTimer - dt, 0)
		end
	end

	c.Speed = speed
	c.ForwardSpeed = forwardSpeed
	c.Gear = if reversing then "R" elseif math.abs(forwardSpeed) < 1 and throttle < 0.05 then "N" else "D"
	c.State.Braking = braking or (handbrake and speed > 2)
	c.State.Reversing = reversing
	c.State.Horn = horn
	pushState(false)
end

-- ===== Otomobil sürüşü (Aşama 2 fizik modeli) =====
local CAR_INIT_TIMEOUT = 5
local function carStep(dt: number)
	local c = current
	if not c or not c.IsDriver or not c.Chassis.Parent then
		return
	end
	if not c.Car then
		-- Akış nedeniyle parçalar henüz gelmemiş olabilir: kısa süre tekrar dene
		c.Car = CarPhysics.new(c.Model, c.Def)
		if not c.Car then
			c.CarWait += dt
			if c.CarWait > CAR_INIT_TIMEOUT and not c.CarWarned then
				c.CarWarned = true
				Log.Warn("Otomobil fizik parçaları bulunamadı:", c.Model.Name)
			end
			return
		end
	end
	local throttle, brake, steer, handbrake, horn = readCarInputs()
	local car = c.Car
	car:Step(dt, throttle, brake, steer, handbrake)
	if car:ConsumeRecoveryRequest() then
		flipRemote:FireServer() -- sunucu: durmuş + (devrik veya takılı) ise düzeltir
	end
	local t = car.Telemetry
	c.Speed = t.Speed
	c.ForwardSpeed = t.ForwardSpeed
	c.Gear = t.Gear
	c.Steer = t.Steer
	c.State.Braking = car:IsBraking()
	c.State.Reversing = car:IsReversing()
	c.State.Horn = horn
	pushState(false)
end

-- ===== Binme / inme =====
local function leave()
	local c = current
	if not c then
		return
	end
	if c.Car then
		c.Car:Release() -- yerinde tut, kuvvetleri sıfırla, lastikleri normale döndür (sunucu devralana kadar)
	end
	current = nil
	maid:Clean()
	local camera = controllers.CameraController
	camera:Release("Vehicle")
	camera:SetFollowSubject(nil, nil, true) -- araç kamerasından karaktere yumuşak geçiş
	camera:SetAutoFollowHeading(false)
	camera:SnapBehindCharacter(true)
	controllers.InputController:SetContext("Vehicle", false)
	controllers.MobileControlsController:SetLayout("OnFoot")
	setDefaultControls(true)
	ProximityPromptService.Enabled = true
	stickX, triggerR, triggerL = 0, 0, 0
	VehicleController.Exited:Fire()
end

local function enter(seat: Seat)
	local model = findVehicleModel(seat)
	if not model then
		return
	end
	local def = VehicleDefinitions.Get(model:GetAttribute("DefId"))
	if not def then
		Log.Warn("Araç tanımı yok:", model:GetAttribute("DefId"))
		return
	end
	if current then
		leave()
	end
	local isDriver = seat:GetAttribute("DriverSeat") == true
	local isBike = VehicleDefinitions.IsMotorcycle(def)
	local c = {
		Model = model, Def = def, Seat = seat, IsDriver = isDriver, IsBike = isBike,
		Chassis = model.PrimaryPart :: BasePart,
		Motors = {}, SteerConstraints = {}, RearWheels = {},
		Upright = nil :: AlignOrientation?,
		DriveTorque = model:GetAttribute("DriveTorque") or 1e4,
		BrakeTorque = model:GetAttribute("BrakeTorque") or 1e4,
		CoastTorque = model:GetAttribute("CoastTorque") or 1e3,
		Steer = 0, Lean = 0, Speed = 0, ForwardSpeed = 0, Gear = "N", FlipTimer = 0, LowGrip = false,
		UsesCar = VehicleDefinitions.UsesCarPhysics(def), Car = nil, CarWait = 0, CarWarned = false,
		State = { Lights = model:GetAttribute("Lights") == true, Indicator = "", Braking = false, Reversing = false, Horn = false },
		LastSent = 0, LastSentKey = "",
	}
	for _, d in model:GetDescendants() do
		if d:IsA("HingeConstraint") and d:GetAttribute("Wheel") then
			table.insert(c.Motors, d)
		elseif d:IsA("CylindricalConstraint") and d:GetAttribute("Steer") then
			table.insert(c.SteerConstraints, d)
		elseif d:IsA("BasePart") and d:GetAttribute("Rear") and d:GetAttribute("Wheel") then
			table.insert(c.RearWheels, d)
		elseif d:IsA("AlignOrientation") and d.Name == "Upright" and isBike then
			c.Upright = d
		end
	end
	current = c

	-- Kamera çerçevesi aracın gerçek boyutundan (sınır kutusu): uzunluk ve şasi merkezine göre tavan yüksekliği
	local framing = nil
	local okBox, boxCFrame, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if okBox and c.Chassis then
		local roof = (boxCFrame.Position.Y + boxSize.Y / 2) - c.Chassis.Position.Y
		framing = { Length = boxSize.Z, RoofHeight = math.max(roof, 0.5), MaxSpeed = def.MaxSpeed }
	end
	local camera = controllers.CameraController
	camera:RequestMode("Vehicle", if isBike then "Motorcycle" else "Vehicle", 20)
	camera:SetFollowSubject(c.Chassis, framing, true)
	camera:SetAutoFollowHeading(true)
	camera:SnapBehindCharacter(true)

	setDefaultControls(false)
	ProximityPromptService.Enabled = false
	controllers.InputController:SetContext("Vehicle", true)
	controllers.MobileControlsController:SetLayout(if not isDriver then "Passenger" elseif isBike then "Motorcycle" else "Car")

	if isDriver then
		if c.UsesCar then
			-- Fizik adımından ÖNCE hedefleri yaz (bir kare gecikme olmasın)
			maid:Give(connectPreSimulation(carStep))
		else
			maid:Give(RunService.Heartbeat:Connect(driveStep)) -- motosiklet: eski adım, değişmedi
		end
		pushState(true)
	end
	-- Araç yok olursa (yeniden doğma vb.) güvenle çık
	maid:Give(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			leave()
		end
	end))
	VehicleController.Entered:Fire(model, isDriver)
end

-- ===== Genel API (HUD için) =====
function VehicleController:GetCurrent()
	return current
end

function VehicleController:IsInVehicle(): boolean
	return current ~= nil
end

-- Mobil buton düzeni (menüden araca dönüşte geri yüklemek için)
function VehicleController:GetMobileLayout(): string
	local c = current
	if not c then
		return "OnFoot"
	end
	return if not c.IsDriver then "Passenger" elseif c.IsBike then "Motorcycle" else "Car"
end

function VehicleController:Init(allControllers)
	controllers = allControllers
end

function VehicleController:Start()
	exitRemote = RemoteRegistry.Get("VehicleRemotes", "RequestExit") :: RemoteEvent
	stateRemote = RemoteRegistry.Get("VehicleRemotes", "DriveState") :: RemoteEvent
	flipRemote = RemoteRegistry.Get("VehicleRemotes", "RequestFlip") :: RemoteEvent

	local input = controllers.InputController
	input.ActionBegan:Connect(function(action)
		local c = current
		if not c then
			return
		end
		if action == "VehExit" then
			exitRemote:FireServer()
		elseif not c.IsDriver then
			return
		elseif action == "VehLights" then
			c.State.Lights = not c.State.Lights
			pushState(true)
		elseif action == "VehIndLeft" then
			c.State.Indicator = if c.State.Indicator == "L" then "" else "L"
			pushState(true)
		elseif action == "VehIndRight" then
			c.State.Indicator = if c.State.Indicator == "R" then "" else "R"
			pushState(true)
		elseif action == "VehFlip" then
			flipRemote:FireServer()
		end
	end)

	UserInputService.InputChanged:Connect(function(io)
		if not current then
			return
		end
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickX = io.Position.X
		elseif io.KeyCode == Enum.KeyCode.ButtonR2 then
			triggerR = io.Position.Z
		elseif io.KeyCode == Enum.KeyCode.ButtonL2 then
			triggerL = io.Position.Z
		end
	end)
	-- Tetik bırakılınca son analog değer takılı kalmasın (gaz açık kalmasın)
	UserInputService.InputEnded:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.ButtonR2 then
			triggerR = 0
		elseif io.KeyCode == Enum.KeyCode.ButtonL2 then
			triggerL = 0
		elseif io.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickX = 0
		end
	end)

	-- Koltuk değişimi: binme/inme tespiti (sunucunun Sit/inişi buraya yansır)
	local function watchCharacter(character: Model?)
		if not character then
			leave()
			return
		end
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		local function check()
			local seat = humanoid.SeatPart
			if seat and seat:IsA("Seat") and seat:GetAttribute("VehicleSeat") then
				if not current or current.Seat ~= seat then
					enter(seat)
				end
			elseif current then
				leave()
			end
		end
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(check)
		humanoid.Died:Connect(leave)
		check()
	end
	controllers.CharacterController.CharacterChanged:Connect(watchCharacter)
	if controllers.CharacterController:GetCharacter() then
		task.spawn(watchCharacter, controllers.CharacterController:GetCharacter())
	end
end

return VehicleController
