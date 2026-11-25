-- VehicleTelemetryController: otomobil telemetrisi + otomatik test ölçümleri (Aşama 2, geliştirme aracı).
--
-- F4 ile açılır/kapanır. Test pisti açıkken (Workspace.SolaraTestCourseReady) otomobile binince kendiliğinden açılır.
-- Ölçümler hem panelde hem Output'ta "[TEST]" satırı olarak görünür (Studio test raporu için kopyalanabilir).
--
-- Kaydediciler:
--   ACCEL     dururken gaza basınca başlar: 0-60 / 0-100 / 0-140 km/s süreleri, ulaşılan azami hız.
--   BRAKE     ≥80 km/s'te tam frene basınca: durma mesafesi (stud / m), süre, 100→0 eşdeğeri, en büyük yana kayma.
--   Kapılı testler (Slalom, Hairpin, Rough, LaneChange): başlangıç → bitiş kapısı süresi, koni temasları,
--             en büyük yanal g, yana kayma; Rough'ta dikey ivme RMS'i, dip vurma ve havada kalma sayısı.
--   SKIDPAD   R 90 halkasında ≥5 sn dönünce: sürdürülebilir en yüksek yanal g.
-- Kare başına tablo yaratılmaz; panel 10 Hz güncellenir.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local UIConfig = require(Modules.UIConfig)

local VehicleTelemetryController = {
	Name = "VehicleTelemetryController",
	Priority = 12,
}

local player = Players.LocalPlayer
local controllers
local gui: ScreenGui
local liveLabel: TextLabel
local resultsLabel: TextLabel
local visible = false
local userToggled = false

local REAL_G = 9.81 / VehicleDefinitions.MetersPerStud
local KMH = VehicleDefinitions.ToKmh(1)
local MAX_RESULTS = 10

local results: { string } = {}
local ACCEL_MARKS = { 60, 100, 140 }

-- ===== Pist verisi (kapılar, koniler, skidpad) =====
type Gate = { Part: BasePart, Test: string, Role: string }
local gates: { Gate } = {}
local cones: { [string]: { BasePart } } = {}
local skidCenter: BasePart? = nil

local function registerCourseObject(d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	local test = d:GetAttribute("Test")
	if d.Name == "SkidpadCenter" then
		skidCenter = d
	elseif type(test) == "string" and d:GetAttribute("Role") then
		table.insert(gates, { Part = d, Test = test, Role = d:GetAttribute("Role") })
	elseif type(test) == "string" and d.Name == "Cone" then
		cones[test] = cones[test] or {}
		table.insert(cones[test], d)
	end
end

local function watchCourse(folder: Instance)
	for _, d in folder:GetDescendants() do
		registerCourseObject(d)
	end
	folder.DescendantAdded:Connect(registerCourseObject)
end

-- ===== Sonuç =====
local function report(text: string)
	local line = string.format("[TEST] %s", text)
	print(line)
	table.insert(results, 1, text)
	if #results > MAX_RESULTS then
		table.remove(results)
	end
end

-- ===== Kaydedici durumları =====
local accel = { State = "Idle", T0 = 0, P0 = Vector3.zero, Marks = { [60] = 0, [100] = 0, [140] = 0 }, LowThrottle = 0, TopKmh = 0 }
local brake = { Active = false, T0 = 0, P0 = Vector3.zero, V0 = 0, MaxSlip = 0, Yaw0 = 0, MaxYawRate = 0 }
local timed = {
	Test = nil :: string?, T0 = 0, MaxLat = 0, MaxSlip = 0, MaxYawRate = 0, Cones = 0, EntryKmh = 0,
	VertSum = 0, VertPeak = 0, Samples = 0, BottomOuts = 0, AirEvents = 0, LastVy = 0, WasBottomed = false, WasAir = false,
}
local coneHit: { [BasePart]: boolean } = {}
local skid = { Time = 0, Ema = 0, Best = 0, SpeedSum = 0, Samples = 0 }
local lastPosition: Vector3? = nil

local function carName(c): string
	return c.Def.DisplayName
end

local function headingOf(cf: CFrame): number
	local look = cf.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

local function resetRecorders()
	accel.State = "Idle"
	brake.Active = false
	timed.Test = nil
	table.clear(coneHit)
	skid.Time, skid.Ema = 0, 0
	lastPosition = nil
end

local function beginTimed(test: string, kmh: number)
	timed.Test = test
	timed.T0 = os.clock()
	timed.MaxLat, timed.MaxSlip, timed.MaxYawRate, timed.Cones = 0, 0, 0, 0
	timed.EntryKmh = kmh
	timed.VertSum, timed.VertPeak, timed.Samples, timed.BottomOuts, timed.AirEvents = 0, 0, 0, 0, 0
	timed.WasBottomed, timed.WasAir = false, false
	timed.LastVy = 0
	table.clear(coneHit)
end

local function finishTimed(c)
	local elapsed = os.clock() - timed.T0
	local name = carName(c)
	if timed.Test == "Rough" then
		local rms = if timed.Samples > 0 then math.sqrt(timed.VertSum / timed.Samples) / REAL_G else 0
		report(string.format("ROUGH %s t=%.2fs entry=%dkm/h vertRMS=%.2fg vertPeak=%.2fg bottomOuts=%d airborne=%d maxSlip=%.1f°",
			name, elapsed, timed.EntryKmh, rms, timed.VertPeak / REAL_G, timed.BottomOuts, timed.AirEvents, timed.MaxSlip))
	elseif timed.Test == "LaneChange" then
		report(string.format("LANECHANGE %s t=%.2fs entry=%dkm/h maxLat=%.2fg maxSlip=%.1f° maxYaw=%.0f°/s cones=%d",
			name, elapsed, timed.EntryKmh, timed.MaxLat, timed.MaxSlip, timed.MaxYawRate, timed.Cones))
	else
		report(string.format("%s %s t=%.2fs entry=%dkm/h maxLat=%.2fg maxSlip=%.1f° cones=%d",
			string.upper(timed.Test or "?"), name, elapsed, timed.EntryKmh, timed.MaxLat, timed.MaxSlip, timed.Cones))
	end
	timed.Test = nil
end

local function crossed(gatePart: BasePart, from: Vector3, to: Vector3): boolean
	local cf = gatePart.CFrame
	local a = cf:PointToObjectSpace(from)
	local b = cf:PointToObjectSpace(to)
	if (a.X < 0) == (b.X < 0) then
		return false
	end
	return math.abs(b.Z) <= gatePart.Size.Z / 2 and math.abs(b.Y) <= gatePart.Size.Y
end

-- ===== Her kare: ölçüm =====
local function step(dt: number)
	local vehicle = controllers.VehicleController
	local c = vehicle and vehicle:GetCurrent()
	local car = c and c.Car
	if not car or not c.IsDriver then
		if lastPosition then
			resetRecorders()
		end
		return
	end
	local t = car.Telemetry
	local chassis = car.Chassis
	local position = chassis.Position
	local kmh = t.Speed * KMH
	local now = os.clock()
	local name = carName(c)

	-- ACCEL
	if accel.State == "Idle" then
		if t.Speed < 0.5 and t.Throttle < 0.05 then
			accel.State = "Armed"
		end
	elseif accel.State == "Armed" then
		if t.Throttle > 0.02 and t.Gear ~= "R" then
			accel.State = "Running"
			accel.T0, accel.P0 = now, position
			accel.Marks[60], accel.Marks[100], accel.Marks[140] = 0, 0, 0
			accel.LowThrottle, accel.TopKmh = 0, 0
		elseif t.Speed > 1 then
			accel.State = "Idle"
		end
	elseif accel.State == "Running" then
		for _, mark in ACCEL_MARKS do
			if accel.Marks[mark] == 0 and kmh >= mark then
				accel.Marks[mark] = now - accel.T0
			end
		end
		accel.TopKmh = math.max(accel.TopKmh, kmh)
		accel.LowThrottle = if t.Throttle < 0.5 then accel.LowThrottle + dt else 0
		local topReached = t.Speed >= c.Def.MaxSpeed * 0.985
		if t.Brake > 0.05 or accel.LowThrottle > 0.4 or topReached or now - accel.T0 > 40 then
			local function mark(m: number): string
				return if accel.Marks[m] > 0 then string.format("%.2fs", accel.Marks[m]) else "—"
			end
			if accel.TopKmh > 30 then
				report(string.format("ACCEL %s 0-60=%s 0-100=%s 0-140=%s top=%dkm/h%s dist=%.0fstud",
					name, mark(60), mark(100), mark(140), math.floor(accel.TopKmh + 0.5),
					if topReached then " (tavan)" else "", (position - accel.P0).Magnitude))
			end
			accel.State = "Idle"
		end
	end

	-- BRAKE
	if not brake.Active then
		if t.Brake > 0.85 and kmh >= 80 and t.Throttle < 0.05 and t.Gear ~= "R" then
			brake.Active = true
			brake.T0, brake.P0, brake.V0 = now, position, kmh
			brake.MaxSlip, brake.MaxYawRate = 0, 0
			brake.Yaw0 = headingOf(chassis.CFrame)
		end
	else
		brake.MaxSlip = math.max(brake.MaxSlip, math.abs(t.SideSlip))
		brake.MaxYawRate = math.max(brake.MaxYawRate, math.abs(t.YawRate))
		if t.Speed < 0.5 then
			local dist = (position - brake.P0).Magnitude
			local normalized = dist * (100 / brake.V0) ^ 2
			local drift = (headingOf(chassis.CFrame) - brake.Yaw0 + 180) % 360 - 180
			report(string.format("BRAKE %s %d->0km/h dist=%.1fstud (%.1fm) t=%.2fs eq100->0=%.1fm maxSlip=%.1f° headingDrift=%.1f°",
				name, math.floor(brake.V0 + 0.5), dist, dist * VehicleDefinitions.MetersPerStud, now - brake.T0,
				normalized * VehicleDefinitions.MetersPerStud, brake.MaxSlip, drift))
			brake.Active = false
		elseif t.Brake < 0.3 then
			brake.Active = false -- frenden çıkıldı; geçersiz
		end
	end

	-- Kapılı testler
	if lastPosition then
		for _, g in gates do
			if g.Part.Parent and g.Test ~= "Accel" and crossed(g.Part, lastPosition, position) then
				if g.Role == "Start" and timed.Test ~= g.Test then
					beginTimed(g.Test, kmh)
				elseif g.Role == "Finish" and timed.Test == g.Test then
					finishTimed(c)
				end
			end
		end
	end
	if timed.Test then
		timed.MaxLat = math.max(timed.MaxLat, math.abs(t.LatG))
		timed.MaxSlip = math.max(timed.MaxSlip, math.abs(t.SideSlip))
		timed.MaxYawRate = math.max(timed.MaxYawRate, math.abs(t.YawRate))
		local list = cones[timed.Test]
		if list then
			local reach = c.Def.Width / 2 + 0.4
			for _, cone in list do
				if not coneHit[cone] and cone.Parent then
					local offset = cone.Position - position
					if offset.X * offset.X + offset.Z * offset.Z < reach * reach then
						coneHit[cone] = true
						timed.Cones += 1
					end
				end
			end
		end
		if timed.Test == "Rough" then
			local vy = chassis.AssemblyLinearVelocity.Y
			local ay = (vy - timed.LastVy) / dt
			timed.LastVy = vy
			if timed.Samples > 0 or math.abs(ay) < REAL_G * 5 then
				timed.VertSum += ay * ay
				timed.Samples += 1
				timed.VertPeak = math.max(timed.VertPeak, math.abs(ay))
			end
			local bottomed = false
			for _, w in car.Wheels do
				if w.Compression >= 0.97 then
					bottomed = true
				end
			end
			if bottomed and not timed.WasBottomed then
				timed.BottomOuts += 1
			end
			timed.WasBottomed = bottomed
			if t.Contacts == 0 and not timed.WasAir then
				timed.AirEvents += 1
			end
			timed.WasAir = t.Contacts == 0
		end
		if now - timed.T0 > 60 then
			timed.Test = nil -- terk edildi
		end
	end

	-- SKIDPAD
	if skidCenter and skidCenter.Parent then
		local offset = position - skidCenter.Position
		local radius = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
		if radius > 65 and radius < 115 and t.Speed > 15 and math.abs(t.SideSlip) < 12 and t.Contacts >= 3 then
			skid.Time += dt
			local alpha = math.clamp(dt / 1.5, 0, 1)
			skid.Ema += (math.abs(t.LatG) - skid.Ema) * alpha
			skid.SpeedSum += kmh
			skid.Samples += 1
			if skid.Time > 3 then
				skid.Best = math.max(skid.Best, skid.Ema)
			end
		elseif skid.Time > 0 then
			if skid.Time >= 5 then
				report(string.format("SKIDPAD %s sustainedLat=%.2fg avgSpeed=%dkm/h duration=%.1fs",
					name, skid.Best, math.floor(skid.SpeedSum / math.max(skid.Samples, 1)), skid.Time))
			end
			skid.Time, skid.Ema, skid.Best, skid.SpeedSum, skid.Samples = 0, 0, 0, 0, 0
		end
	end

	lastPosition = position
end

-- ===== Panel =====
local function bar(value: number, width: number): string
	local filled = math.clamp(math.floor(value * width + 0.5), 0, width)
	return string.rep("#", filled) .. string.rep(".", width - filled)
end

local function driveLabel(p): string
	if p.DriveSplitFront >= 0.99 then
		return "FWD"
	elseif p.DriveSplitFront <= 0.01 then
		return "RWD"
	end
	return string.format("AWD %d/%d", math.floor(p.DriveSplitFront * 100 + 0.5), math.floor((1 - p.DriveSplitFront) * 100 + 0.5))
end

local function refreshPanel()
	local vehicle = controllers.VehicleController
	local c = vehicle and vehicle:GetCurrent()
	local car = c and c.Car
	local lines = {}
	if car then
		local t = car.Telemetry
		local p = c.Def.Physics
		table.insert(lines, string.format("%s  %s  vites %s  devir %s", c.Def.DisplayName, driveLabel(p), t.Gear, bar(t.RpmNorm, 10)))
		table.insert(lines, string.format("hız %5.1f km/h   boyuna %+.2fg   yanal %+.2fg", t.Speed * KMH, t.LongG, t.LatG))
		table.insert(lines, string.format("gaz %3d%%  fren %3d%%  elfreni %3d%%", math.floor(t.Throttle * 100), math.floor(t.Brake * 100), math.floor(t.Handbrake * 100)))
		table.insert(lines, string.format("direksiyon %+.2f -> %+.1f° (sınır %.1f°)", t.Steer, t.SteerDeg, t.SteerLimit))
		table.insert(lines, string.format("kayma β %+.1f°  yaw %+.0f°/s  denge %+.1f", t.SideSlip, t.YawRate, t.StabilityTorque))
		table.insert(lines, string.format("temas %d/4  havada %s", t.Contacts, if t.Airborne then "EVET" else "hayır"))
		table.insert(lines, "TEKER  sıkış  yük   kayma%  açı°   μ    zemin  dir.hata°  titreme°")
		for _, w in car.Wheels do
			table.insert(lines, string.format("%-5s  %4.2f  %4.2f  %+5.0f  %5.1f  %4.2f  %4.2f  %+6.2f  %6.2f%s",
				w.Name, w.Compression, w.Load, w.SlipRatio * 100, w.SlipAngle, w.Mu, w.SurfaceGrip,
				w.SteerError, w.Wobble, if w.Sliding then "  KAYIYOR" else ""))
		end
	else
		table.insert(lines, "Otomobile sürücü olarak bin (motosiklet bu panelin dışında).")
	end
	liveLabel.Text = table.concat(lines, "\n")
	resultsLabel.Text = if #results > 0 then "SON ÖLÇÜMLER\n" .. table.concat(results, "\n") else "SON ÖLÇÜMLER\n(henüz yok)"
end

local function setVisible(value: boolean)
	visible = value
	gui.Enabled = value
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "SolaraTelemetry"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.fromOffset(10, 60)
	panel.Size = UDim2.fromOffset(470, 470)
	panel.BackgroundColor3 = UIConfig.Colors.Background
	panel.BackgroundTransparency = 0.25
	panel.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingTop, padding.PaddingRight = UDim.new(0, 10), UDim.new(0, 8), UDim.new(0, 10)
	padding.Parent = panel
	local function label(name: string, y: number, height: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, height)
		l.FontFace = UIConfig.Fonts.Mono
		l.TextSize = 13
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.TextWrapped = true
		l.AutoLocalize = false
		l.Parent = panel
		return l
	end
	liveLabel = label("Live", 0, 200, UIConfig.Colors.Text)
	resultsLabel = label("Results", 206, 250, Color3.fromRGB(255, 214, 150))
	panel.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

function VehicleTelemetryController:Init(allControllers)
	controllers = allControllers
end

function VehicleTelemetryController:Start()
	build()
	local course = workspace:FindFirstChild("SolaraTestCourse")
	if course then
		watchCourse(course)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "SolaraTestCourse" then
			watchCourse(child)
		end
	end)

	controllers.InputController.ActionBegan:Connect(function(action)
		if action == "ToggleTelemetry" then
			userToggled = true
			setVisible(not visible)
		end
	end)
	-- Test pistindeyken otomobile binince otomatik aç (oyuncu F4 ile kapattıysa açma)
	controllers.VehicleController.Entered:Connect(function(_, isDriver)
		if isDriver and not userToggled and workspace:GetAttribute("SolaraTestCourseReady") == true then
			setVisible(true)
		end
	end)

	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		while true do
			task.wait(0.1)
			if visible then
				pcall(refreshPanel)
			end
		end
	end)
end

return VehicleTelemetryController
