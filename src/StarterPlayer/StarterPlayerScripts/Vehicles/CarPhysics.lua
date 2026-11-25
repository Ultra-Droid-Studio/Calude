-- CarPhysics: otomobil sürüş modeli (Aşama 2). Sadece SÜRÜCÜNÜN istemcisinde, araç fiziğinin ağ sahibi
-- o istemciyken çalışır. Her karede fiziksel kısıtlamaların hedeflerini yazar; kuvvetleri Roblox fiziği üretir.
--
-- Fiziksel parçalar (VehicleFactory._tuneCar kurar):
--   Yay + amortisör (aks başına frekans/sönüm), balast (ağırlık dağılımı), tekerlek motorları (çekiş/fren tork
--   kaynağı), direksiyon servoları, şasi "Forces" (kaldırma + aero + yuvarlanma), "Stability" torku, "Upright".
--
-- Bu modülün katmanları (her karede, sırayla):
--   1. Giriş şekillendirme  gaz/fren rampası, ileri↔geri vites mantığı, hıza bağlı direksiyon hızı
--   2. Direksiyon           tutuş sınırlı açı + Ackermann + kayarken kendiliğinden karşı direksiyon
--   3. Motor                sanal vites, güç eğrisi, vites değişiminde çekiş kesintisi
--   4. Tekerlek başına      süspansiyon sıkışması → yük; kayma açısı/oranı → statik/kinetik tutuş;
--                           zemin malzemesi; motor hedefi (çekiş kontrolü / ABS / el freni / yerinde tutma)
--   5. Şasi kuvvetleri      hava direnci, yuvarlanma direnci, yere basma
--   6. Denge                yerde: savrulma hızı hedefe bağlanır; havada: dönme sönümü + dik tutma
--   7. Kurtarma             takılma/devrilme algılanırsa sunucudan düzeltme istenir (sunucu doğrular)
--
-- Kare başına tablo/closure yaratılmaz; zemin için karede TEK ışın atılır (tekerlekler sırayla).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local VehiclePhysics = require(Shared.VehiclePhysics)

local CarPhysics = {}
CarPhysics.__index = CarPhysics

local C = VehiclePhysics.Constants
local DRIVE_SIGN = VehicleDefinitions.DriveSign
local REAL_G = 9.81 / VehicleDefinitions.MetersPerStud -- telemetri: gerçek g (stud/sn²)
local WHEEL_ORDER = { "FL", "FR", "RL", "RR" }
local REVERSE_DELAY = 0.35 -- sn: durduktan sonra geri vitese geçiş beklemesi
local MU_STEP = 50 -- μ 1/50 = 0.02 adımla yazılır (gereksiz özellik yazımı olmasın)

-- PhysicalProperties önbelleği (μ 0.01 adımla) → sürtünme değişiminde yeni nesne yaratılmaz
local propCache: { [number]: PhysicalProperties } = {}
local function frictionProps(key: number): PhysicalProperties
	local props = propCache[key]
	if not props then
		props = PhysicalProperties.new(0.9, key / 50, 0, 100, 1)
		propCache[key] = props
	end
	return props
end

local function approach(current: number, target: number, rateUp: number, rateDown: number, dt: number): number
	if target > current then
		return math.min(target, current + rateUp * dt)
	end
	return math.max(target, current - rateDown * dt)
end

-- Araçtaki fiziksel parçaları toplar. Akış (streaming) yüzünden eksikse nil döner; çağıran sonra tekrar dener.
function CarPhysics.new(model: Model, def)
	if not VehicleDefinitions.UsesCarPhysics(def) then
		return nil
	end
	local chassis = model.PrimaryPart
	local forces = chassis and chassis:FindFirstChild("Forces")
	local stability = chassis and chassis:FindFirstChild("Stability")
	local upright = chassis and chassis:FindFirstChild("Upright")
	if not (chassis and forces and stability and upright) then
		return nil
	end
	local d = VehiclePhysics.Derive(def)
	local p = def.Physics
	local wheels = {}
	for _, name in WHEEL_ORDER do
		local wheel = model:FindFirstChild("Wheel_" .. name)
		local knuckle = model:FindFirstChild("Knuckle_" .. name)
		local motor = knuckle and knuckle:FindFirstChild("Motor_" .. name)
		local strut = knuckle and knuckle:FindFirstChild("Suspension_" .. name)
		if not (wheel and knuckle and motor and strut) then
			return nil
		end
		local rear = string.sub(name, 1, 1) == "R"
		local driveShare = if rear then (1 - p.DriveSplitFront) / 2 else p.DriveSplitFront / 2
		table.insert(wheels, {
			Name = name,
			Wheel = wheel,
			Knuckle = knuckle,
			Motor = motor,
			Strut = strut,
			Rear = rear,
			Left = string.sub(name, 2, 2) == "L",
			Steers = strut:GetAttribute("Steer") == true,
			DriveShare = driveShare,
			BrakeShare = if rear then (1 - p.BrakeBiasFront) / 2 else p.BrakeBiasFront / 2,
			Sag = if rear then d.SagRear else d.SagFront,
			BaseMu = p.TireGrip * (if rear then p.GripRear else p.GripFront),
			MuKey = -1,
			Sliding = false,
			SurfaceGrip = 1,
			SurfaceRolling = 1,
			-- telemetri
			Compression = 0,
			Load = 1,
			SlipRatio = 0,
			SlipAngle = 0,
			Mu = 0,
			Contact = false,
			SteerError = 0, -- gerçek direksiyon açısı − istenen (°)
			SteerMean = 0,
			Wobble = 0, -- titreme: hatanın ortalamasından ortalama sapması (°)
		})
	end
	local sprung = model:GetAttribute("SprungMass") or chassis.AssemblyMass
	local total = model:GetAttribute("TotalMass") or sprung
	local hx, hz = def.Track / 2, def.Wheelbase / 2
	local unsprung = math.max(total - sprung, 0)
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Exclude
	probe.FilterDescendantsInstances = { model }
	probe.RespectCanCollide = true

	local self = setmetatable({
		Model = model,
		Def = def,
		P = p,
		D = d,
		Chassis = chassis,
		Forces = forces,
		Stability = stability,
		Upright = upright,
		Wheels = wheels,
		Mass = total,
		BaseLift = forces:GetAttribute("BaseLift") or 0,
		HoldTorque = model:GetAttribute("BrakeTorque") or 0,
		-- savrulma ataleti (yaklaşık): gövde dikdörtgen + köşelerdeki tekerlekler
		YawInertia = sprung * (def.Length * def.Length + def.Width * def.Width) / 12 + unsprung * (hx * hx + hz * hz),
		Probe = probe,
		ProbeIndex = 1,
		-- durum
		Throttle = 0,
		BrakeInput = 0,
		Steer = 0,
		SteerDeg = 0,
		Reverse = false,
		StopTime = 0,
		Gear = 1,
		ShiftTimer = 0,
		Handbrake = 0,
		AirTime = 0,
		StuckTime = 0,
		TipTime = 0,
		LastRecovery = -100,
		LastVelocity = chassis.AssemblyLinearVelocity,
		RecoveryRequested = false,
		RearSliding = false, -- önceki karede arka lastiklerden biri kayıyor muydu
		-- telemetri (her karede yazılır, yeniden yaratılmaz)
		Telemetry = {
			Speed = 0, ForwardSpeed = 0, Gear = "N", RpmNorm = 0, Throttle = 0, Brake = 0,
			Steer = 0, SteerDeg = 0, SteerLimit = 0, SideSlip = 0, YawRate = 0, LongG = 0, LatG = 0,
			Contacts = 0, Handbrake = 0, StabilityTorque = 0, Airborne = false,
			-- Gösterge ışıkları (HUD): sürüş yardımı bu karede müdahale ediyor mu
			AbsActive = false, TcActive = false, EscActive = false,
		},
	}, CarPhysics)
	return self
end

-- Sürücü araçtan inerken: yerinde tut, kuvvetleri sıfırla, lastikleri normale döndür (yerel değerler)
function CarPhysics:Release()
	for _, w in self.Wheels do
		w.Motor.AngularVelocity = 0
		w.Motor.MotorMaxTorque = self.HoldTorque * 3
		local key = math.floor(w.BaseMu * MU_STEP + 0.5)
		w.Wheel.CustomPhysicalProperties = frictionProps(key)
		w.MuKey = key
		if w.Steers then
			w.Strut.TargetAngle = 0
		end
	end
	self.Forces.Force = Vector3.new(0, self.BaseLift, 0)
	self.Stability.Torque = Vector3.zero
	self.Upright.Enabled = false
end

-- Bir sonraki karede sunucuya kurtarma isteği gönderilmeli mi? (okununca sıfırlanır)
function CarPhysics:ConsumeRecoveryRequest(): boolean
	local requested = self.RecoveryRequested
	self.RecoveryRequested = false
	return requested
end

-- throttleIn, brakeIn: 0..1 (analog), steerIn: -1..1 (sağ +), handbrake: bool
function CarPhysics:Step(dt: number, throttleIn: number, brakeIn: number, steerIn: number, handbrake: boolean)
	local chassis = self.Chassis
	if not chassis.Parent or dt <= 0 then
		return
	end
	local def, d, p = self.Def, self.D, self.P
	local mass = self.Mass
	local cf = chassis.CFrame
	local forward, right, up = cf.LookVector, cf.RightVector, cf.UpVector
	local velocity = chassis.AssemblyLinearVelocity
	local angular = chassis.AssemblyAngularVelocity
	local vLong = velocity:Dot(forward)
	local vLat = velocity:Dot(right)
	local speed = velocity.Magnitude
	local planarSpeed = math.sqrt(vLong * vLong + vLat * vLat)

	-- ===== 1. Giriş: ileri / geri mantığı ve pedal rampaları =====
	local wantGas, wantBrake = throttleIn > 0.05, brakeIn > 0.05
	if self.Reverse then
		if wantGas and vLong > -C.HoldSpeed then
			self.Reverse = false -- neredeyse durdu ve gaza basıldı → ileri
		end
	elseif wantBrake and not wantGas and math.abs(vLong) < C.HoldSpeed then
		-- Durunca hemen geri gitme: fren tuşu durmuş araçta kısa bir süre tutulursa geri vitese geç
		self.StopTime += dt
		if self.StopTime > REVERSE_DELAY then
			self.Reverse = true
		end
	else
		self.StopTime = 0
	end
	local driveDemand, brakeDemand
	if self.Reverse then
		driveDemand, brakeDemand = brakeIn, throttleIn -- geride: "fren" tuşu gaz, "gaz" tuşu fren
	else
		driveDemand, brakeDemand = throttleIn, brakeIn
	end
	self.Throttle = approach(self.Throttle, driveDemand, p.ThrottleRise, p.ThrottleFall, dt)
	self.BrakeInput = approach(self.BrakeInput, brakeDemand, 7, 10, dt)
	self.Handbrake = approach(self.Handbrake, if handbrake then 1 else 0, 10, 3, dt)
	local throttle, brake, hb = self.Throttle, self.BrakeInput, self.Handbrake

	-- ===== 2. Direksiyon =====
	local speedFrac = math.clamp(planarSpeed / def.MaxSpeed, 0, 1)
	local rate = p.SteerRateLow + (p.SteerRateHigh - p.SteerRateLow) * speedFrac
	if math.abs(steerIn) < math.abs(self.Steer) or steerIn * self.Steer < 0 then
		rate *= 1.6 -- merkeze dönüş daha hızlı (bırakınca araç toparlanır)
	end
	self.Steer += math.clamp(steerIn - self.Steer, -rate * dt, rate * dt)
	local limit = VehiclePhysics.SteerLimit(def, d, planarSpeed)
	local steerDeg = self.Steer * limit
	-- Arka kayarken oyuncu direksiyonu bırakmışsa hız vektörüne doğru kendiliğinden karşı direksiyon.
	-- Sadece arka lastikler GERÇEKTEN kayarken (Hata düzeltme 3): normal sürüşte tekerleri kendi kendine oynatmasın.
	local sideSlip = if planarSpeed > 6 and vLong > 2 then math.atan2(vLat, vLong) else 0
	if self.RearSliding and math.abs(self.Steer) < 0.25 and math.abs(sideSlip) > math.rad(4) then
		steerDeg += math.clamp(math.deg(sideSlip) * p.CounterSteer, -def.MaxSteer * 0.5, def.MaxSteer * 0.5)
	end
	steerDeg = math.clamp(steerDeg, -def.MaxSteer, def.MaxSteer)
	self.SteerDeg = steerDeg
	-- Ackermann: iç teker daha fazla döner (dar virajda ön tekerler sürtmez)
	local innerDeg, outerDeg = steerDeg, steerDeg
	local absSteer = math.abs(steerDeg)
	if absSteer > 0.2 then
		local L, halfTrack = def.Wheelbase, def.Track / 2
		local radius = L / math.tan(math.rad(absSteer))
		local inner = math.deg(math.atan(L / math.max(radius - halfTrack, 0.5)))
		local outer = math.deg(math.atan(L / (radius + halfTrack)))
		local a = C.AckermannFactor
		local sign = if steerDeg > 0 then 1 else -1
		innerDeg = sign * math.min(absSteer + a * (inner - absSteer), def.MaxSteer * 1.15)
		outerDeg = sign * (absSteer + a * (outer - absSteer))
	end
	local turningRight = steerDeg > 0

	-- ===== 3. Motor ve vites =====
	local gears = p.Gears
	if self.Reverse then
		self.Gear = 1
	else
		local forwardSpeed = math.max(vLong, 0)
		if self.ShiftTimer > 0 then
			self.ShiftTimer -= dt
		elseif self.Gear < gears and forwardSpeed >= d.GearTops[self.Gear] * 0.97 and throttle > 0.1 then
			self.Gear += 1
			self.ShiftTimer = p.ShiftTime
		elseif self.Gear > 1 and forwardSpeed < d.GearTops[self.Gear - 1] * 0.75 then
			self.Gear -= 1
		end
	end
	local driveAccel
	if self.Reverse then
		driveAccel = d.ReverseAccel * throttle
	else
		local cut = if self.ShiftTimer > 0 then C.ShiftCut else 1
		driveAccel = VehiclePhysics.DriveAccel(d, math.max(vLong, 0), self.Gear) * throttle * cut
	end
	local driveForce = mass * driveAccel
	local holding = throttle < 0.02 and brake < 0.02 and hb < 0.5 and math.abs(vLong) < C.HoldSpeed

	-- ===== 4. Tekerlekler =====
	local contacts = 0
	local rearSliding = false
	local wobbleAlpha = math.clamp(dt * 2, 0, 1) -- ~0.5 sn zaman sabiti
	local absActive, tcActive = false, false
	local rollingFactor = 0
	local probeIndex = self.ProbeIndex
	for i, w in self.Wheels do
		local wheel, knuckle = w.Wheel, w.Knuckle
		local kcf = knuckle.CFrame
		local wForward, wRight = kcf.LookVector, kcf.RightVector
		local wv = wheel.AssemblyLinearVelocity
		local vl = wv:Dot(wForward)
		local vlat = wv:Dot(wRight)
		local R = wheel.Size.Y / 2
		local omega = (wheel.AssemblyAngularVelocity - knuckle.AssemblyAngularVelocity):Dot(wRight)
		local surfaceSpeed = omega * R * DRIVE_SIGN

		-- Süspansiyon: CurrentPosition sürüş konumunda -BumpRoom, tam açılmada -Travel
		local position = w.Strut.CurrentPosition
		local compression = position + def.Travel
		local contact = compression > 0.03
		local load = if contact then math.clamp(1 + (position + d.BumpRoom) / w.Sag, 0, 3) else 0
		local denominator = math.max(math.abs(vl), 3)
		local slipAngle = math.deg(math.atan(math.abs(vlat) / denominator))
		local slipRatio = (surfaceSpeed - vl) / denominator

		-- Statik ↔ kinetik tutuş (histerezisli: titreşmesin)
		if w.Sliding then
			if slipAngle < C.SlideExitAngle and math.abs(slipRatio) < C.SlideExitRatio then
				w.Sliding = false
			end
		elseif contact and planarSpeed > 3 and (slipAngle > C.SlideEnterAngle or math.abs(slipRatio) > C.SlideEnterRatio) then
			w.Sliding = true
		end

		-- Zemin (karede tek tekerlek)
		if i == probeIndex then
			local hit = workspace:Raycast(wheel.Position, -up * (R + 1), self.Probe)
			local surface = VehiclePhysics.Surface(if hit then hit.Material else nil)
			w.SurfaceGrip, w.SurfaceRolling = surface[1], surface[2]
		end

		local mu = w.BaseMu * w.SurfaceGrip
		if w.Sliding then
			mu *= C.KineticGrip
		end
		mu *= math.clamp(1 - C.LoadSensitivity * (load - 1), 0.85, 1.12)
		if w.Rear then
			mu *= 1 + (p.HandbrakeGrip - 1) * hb
		end
		local key = math.clamp(math.floor(mu * MU_STEP + 0.5), 2, 100)
		if key ~= w.MuKey then
			w.MuKey = key
			wheel.CustomPhysicalProperties = frictionProps(key)
		end

		-- Motor hedefi: hedef açısal hız + tork sınırı. Tork sınırı = kuvvet × yarıçap.
		local target, torque = 0, 0
		if w.Rear and hb > 0.5 then
			target, torque = 0, mass * d.HandbrakeAccel / 2 * R -- arka tekerler kilit
		elseif brake > 0.02 then
			-- ABS: tekerlek yüzey hızı (1 - AbsSlip) × araç hızının altına inmez → kilitlenmez
			local absTarget = if math.abs(vl) > 1.5 then vl * (1 - C.AbsSlip) else 0
			target = DRIVE_SIGN * absTarget / R
			torque = mass * d.BrakeAccel * brake * w.BrakeShare * R
		elseif holding then
			target, torque = 0, self.HoldTorque
		elseif w.DriveShare > 0 and throttle > 0.01 then
			-- Çekiş kontrolü: teker yüzeyi araçtan en fazla "allow" kadar hızlı dönebilir
			local allow = math.max(C.MinSlipSpeed, p.TractionSlip * math.abs(vl))
			local surfaceTarget
			if self.Reverse then
				surfaceTarget = math.max(math.min(vl, 0) - allow, -d.ReverseSpeed)
			else
				surfaceTarget = math.min(math.max(vl, 0) + allow, def.MaxSpeed)
			end
			target = DRIVE_SIGN * surfaceTarget / R
			torque = driveForce * w.DriveShare * R
		elseif w.DriveShare > 0 then
			target, torque = 0, mass * d.EngineBrakeAccel * w.DriveShare * R -- motor freni
		end
		w.Motor.AngularVelocity = target
		w.Motor.MotorMaxTorque = torque
		if contact and math.abs(vl) > 3 then
			if brake > 0.3 and slipRatio < -C.AbsSlip * 0.6 then
				absActive = true -- ABS kaymayı sınırlıyor
			elseif w.DriveShare > 0 and throttle > 0.3 and slipRatio > math.max(p.TractionSlip * 0.7, 0.05) then
				tcActive = true -- çekiş kontrolü patinajı sınırlıyor
			end
		end

		local wantedDeg = 0
		if w.Steers then
			wantedDeg = if (turningRight and not w.Left) or (not turningRight and w.Left) then innerDeg else outerDeg
			w.Strut.TargetAngle = -wantedDeg
		end
		-- Telemetri: mafsalın şasiye göre gerçek açısı (sağ +) ve titreme ölçüsü
		local actualDeg = math.deg(math.atan2(wForward:Dot(right), wForward:Dot(forward)))
		local steerError = actualDeg - wantedDeg
		w.SteerError = steerError
		w.SteerMean += (steerError - w.SteerMean) * wobbleAlpha
		w.Wobble += (math.abs(steerError - w.SteerMean) - w.Wobble) * wobbleAlpha
		if w.Rear and w.Sliding and contact then
			rearSliding = true
		end

		if contact then
			contacts += 1
			rollingFactor += w.SurfaceRolling
		end
		w.Compression = compression / def.Travel
		w.Load = load
		w.SlipRatio = slipRatio
		w.SlipAngle = slipAngle
		w.Mu = mu
		w.Contact = contact
	end
	self.ProbeIndex = (probeIndex % #self.Wheels) + 1
	self.RearSliding = rearSliding

	-- ===== 5. Şasi kuvvetleri: kaldırma (sabit) + hava direnci + yuvarlanma + yere basma =====
	local force = Vector3.new(0, self.BaseLift, 0)
	if speed > 0.5 then
		local direction = velocity / speed
		local resist = d.DragPerSpeed2 * speed * speed
		if contacts > 0 then
			resist += d.RollingAccel * (rollingFactor / contacts)
		end
		force -= direction * (mass * resist)
		if contacts > 0 and d.DownforcePerSpeed2 > 0 then
			force -= up * (mass * d.DownforcePerSpeed2 * vLong * vLong)
		end
	end
	self.Forces.Force = force

	-- ===== 6. Denge =====
	local yawRate = angular:Dot(up)
	local torque = Vector3.zero
	local stabilityTorque = 0
	if contacts >= 3 and planarSpeed > 10 and hb < 0.3 and not self.Reverse then
		-- Direksiyonun istediği savrulma hızı (sağa dönüş = negatif yaw), tutuş sınırıyla kırpılmış
		local wanted = -planarSpeed * math.tan(math.rad(steerDeg)) / def.Wheelbase
		local maxRate = d.LateralLimit * 1.1 / planarSpeed
		wanted = math.clamp(wanted, -maxRate, maxRate)
		local err = yawRate - wanted
		local deadband = 0.08
		if math.abs(err) > deadband then
			local excess = err - deadband * math.sign(err)
			stabilityTorque = math.clamp(-excess * p.StabilityGain * self.YawInertia, -self.YawInertia * 6, self.YawInertia * 6)
			torque = up * stabilityTorque
		end
	elseif contacts == 0 then
		torque = -angular * (self.YawInertia * 1.2) -- havada takla/fırıldak sönümü
	end
	self.Stability.Torque = torque

	-- ===== 7. Havada dik tutma, takılma ve devrilme kurtarma =====
	self.AirTime = if contacts == 0 then self.AirTime + dt else 0
	local airborne = self.AirTime > 0.35
	if self.Upright.Enabled ~= airborne then
		self.Upright.PrimaryAxis = Vector3.yAxis
		self.Upright.Enabled = airborne
	end
	local pushing = throttle > 0.5
	if pushing and planarSpeed < 1.5 and contacts <= 2 then
		self.StuckTime += dt
	else
		self.StuckTime = 0
	end
	if up.Y < 0.3 and speed < 4 then
		self.TipTime += dt
	else
		self.TipTime = 0
	end
	local now = os.clock()
	if (self.StuckTime > 2.5 or self.TipTime > 2.5) and now - self.LastRecovery > 5 then
		self.LastRecovery = now
		self.StuckTime, self.TipTime = 0, 0
		self.RecoveryRequested = true
	end

	-- ===== Telemetri =====
	local acceleration = (velocity - self.LastVelocity) / dt
	self.LastVelocity = velocity
	local t = self.Telemetry
	local smoothing = math.clamp(dt * 8, 0, 1)
	t.Speed = speed
	t.ForwardSpeed = vLong
	t.Gear = if self.Reverse then "R" elseif math.abs(vLong) < 0.5 and throttle < 0.05 then "N" else tostring(self.Gear)
	t.RpmNorm = if self.Reverse then 0.5 else math.clamp(math.max(vLong, 0) / d.GearTops[self.Gear], 0.15, 1)
	t.Throttle = throttle
	t.Brake = brake
	t.Steer = self.Steer
	t.SteerDeg = steerDeg
	t.SteerLimit = limit
	t.SideSlip = math.deg(sideSlip)
	t.YawRate = math.deg(yawRate)
	t.LongG += (acceleration:Dot(forward) / REAL_G - t.LongG) * smoothing
	t.LatG += (acceleration:Dot(right) / REAL_G - t.LatG) * smoothing
	t.Contacts = contacts
	t.Handbrake = hb
	t.StabilityTorque = stabilityTorque / math.max(self.YawInertia, 1)
	t.Airborne = airborne
	t.AbsActive = absActive
	t.TcActive = tcActive
	t.EscActive = math.abs(stabilityTorque) > self.YawInertia * 0.4
end

function CarPhysics:IsBraking(): boolean
	return self.BrakeInput > 0.05 or (self.Handbrake > 0.5 and self.Telemetry.Speed > 2)
end

function CarPhysics:IsReversing(): boolean
	return self.Reverse
end

return CarPhysics
