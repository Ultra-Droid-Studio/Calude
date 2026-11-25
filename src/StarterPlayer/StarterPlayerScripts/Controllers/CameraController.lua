-- CameraController: BİRLEŞİK kamera denetleyicisi (Bölüm 19).
--
-- Kuralı: Kameranın CFrame'ini SADECE bu modül yazar. Diğer sistemler kamerayı
-- doğrudan değiştirmez; bunun yerine "istek" (override) bırakır:
--
--   CameraController:RequestMode(owner, mode, priority)          -- takip modları (Vehicle, Motorcycle)
--   CameraController:RequestScripted(owner, mode, priority, fn)  -- Menu / Cinematic: fn(dt) -> CFrame, FOV?
--   CameraController:Release(owner)
--   CameraController:PlayCinematic(keyframes, owner?)            -- güvenli, zaman aşımlı geçiş
--
-- En yüksek öncelikli istek kazanır; hiç istek yoksa oyuncunun ayarlardaki modu (temel mod) kullanılır.
-- Böylece bir sistem çökse bile Release ile ya da güvenlik zamanlayıcısıyla kamera normale döner.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Shared.Constants)
local Signal = require(Shared.Utilities.Signal)
local MathUtil = require(Shared.Utilities.MathUtil)
local CameraConfig = require(Modules.CameraConfig)
local Log = require(Shared.Utilities.Log).new("Camera")

local CameraController = {
	Name = "CameraController",
	Priority = 5,
	ModeChanged = Signal.new(), -- (newMode, oldMode)
}

local Modes = Constants.CameraModes
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local controllers

local RENDER_NAME = "OW_CameraController"
local DEG = math.pi / 180

-- ===== Durum =====
local baseMode = CameraConfig.DefaultMode
local currentMode: string? = nil
local overrides: { [string]: { Mode: string, Priority: number, Supplier: ((number) -> (CFrame, number?))?, Order: number } } = {}
local overrideOrder = 0

local targetYaw, targetPitch = 0, -10 * DEG
local yaw, pitch = targetYaw, targetPitch
local userDistance: { [string]: number } = {} -- oyuncunun moda göre yakınlaştırma tercihi
local currentDistance = 6
local pivot: Vector3? = nil
local snapNextFrame = true
local currentFov = 70
local followSubject: BasePart? = nil -- araç modunda takip edilecek parça (Aşama 3)
local autoFollowHeading = false -- araçta: oyuncu kamerayı çevirmezse aracın arkasına döner
local lastLookInput = 0
local AUTO_FOLLOW_DELAY = 1.2

local cursorFreeOwners: { [string]: boolean } = {}
local rightMouseHeld = false
local pendingTouchDelta = Vector2.zero
local cameraTouches: { [InputObject]: boolean } = {}
local gamepadLook = Vector2.zero
local lastPinchScale: number? = nil

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = true
raycastParams.IgnoreWater = true
local filterRefreshTimer = 0

local characterParts: { BasePart } = {}
local lastTransparency = -1
local lastHeadOnly = false
local consecutiveErrors = 0
local descendantConnection: RBXScriptConnection? = nil
local running = false

-- ===== Yardımcılar =====
local function getSettings()
	return controllers.SettingsController
end

local function getProfile(mode: string)
	return CameraConfig.Profiles[mode] or CameraConfig.Profiles.ThirdPerson
end

local function isFollowMode(mode: string): boolean
	return CameraConfig.Profiles[mode] ~= nil
end

local function resolveMode(): (string, any)
	local best = nil
	for _, entry in overrides do
		if not best or entry.Priority > best.Priority or (entry.Priority == best.Priority and entry.Order > best.Order) then
			best = entry
		end
	end
	if best then
		return best.Mode, best
	end
	return baseMode, nil
end

local function isCursorFree(): boolean
	return next(cursorFreeOwners) ~= nil
end

local function refreshFilter()
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	if followSubject then
		local model = followSubject:FindFirstAncestorOfClass("Model")
		table.insert(list, model or followSubject)
	end
	raycastParams.FilterDescendantsInstances = list
end

-- Kamera mevcut açısından yaw/pitch'i al (sinematikten oyuna geçişte zıplama olmasın)
local function syncAnglesFromCamera()
	local look = camera.CFrame.LookVector
	targetYaw = math.atan2(-look.X, -look.Z)
	targetPitch = math.asin(math.clamp(look.Y, -1, 1))
	yaw, pitch = targetYaw, targetPitch
end

-- ===== Karakter görünürlüğü (birinci şahıs / çok yakın kamera) =====
local function collectCharacterParts(character: Model?)
	table.clear(characterParts)
	lastTransparency = -1
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(characterParts, d)
		end
	end
end

local function isHeadPart(part: BasePart): boolean
	if part.Name == "Head" then
		return true
	end
	-- Aksesuarlar (şapka, saç, gözlük...) birinci şahısta görüşü kapatır
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
end

local function applyCharacterTransparency(value: number, headOnly: boolean)
	if math.abs(value - lastTransparency) < 0.02 and headOnly == lastHeadOnly then
		return
	end
	lastTransparency = value
	lastHeadOnly = headOnly
	for _, part in characterParts do
		if part.Parent then
			if headOnly then
				part.LocalTransparencyModifier = if isHeadPart(part) then value else 0
			else
				part.LocalTransparencyModifier = value
			end
		end
	end
end

-- ===== Mod geçişi =====
local function setAutoRotate(enabled: boolean)
	local humanoid = controllers.CharacterController:GetHumanoid()
	if humanoid then
		humanoid.AutoRotate = enabled
	end
end

local function onModeChanged(newMode: string, oldMode: string?)
	local wasFollow = oldMode == nil or isFollowMode(oldMode)
	if isFollowMode(newMode) then
		if not wasFollow then
			-- Senaryolu kameradan dönüş: mevcut bakış açısını koru, pivotu anında yerleştir
			syncAnglesFromCamera()
		end
		snapNextFrame = true
		local profile = getProfile(newMode)
		if userDistance[newMode] == nil then
			userDistance[newMode] = profile.Distance
		end
		currentDistance = math.min(currentDistance, userDistance[newMode])
	end
	-- Birinci şahısta karakter kameranın yönüne döner
	setAutoRotate(newMode ~= Modes.FirstPerson)
	applyCharacterTransparency(0, false)
	CameraController.ModeChanged:Fire(newMode, oldMode)
	Log.Info("Kamera modu:", newMode)
end

local function updateResolvedMode()
	local mode = resolveMode()
	if mode ~= currentMode then
		local old = currentMode
		currentMode = mode
		onModeChanged(mode, old)
	end
end

-- ===== Giriş =====
local function applyLookInput(dt: number, profile)
	local s = getSettings()
	local sensitivity = s:Get("CameraSensitivity")
	local invert = if s:Get("InvertY") then -1 else 1

	-- Fare
	local wantLock = not isCursorFree() and not controllers.InputController:IsTouch()
	if wantLock then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	elseif rightMouseHeld then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if wantLock or rightMouseHeld then
		local delta = UserInputService:GetMouseDelta()
		if delta.Magnitude > 0.5 then
			lastLookInput = os.clock()
		end
		targetYaw -= delta.X * CameraConfig.MouseSensitivity * sensitivity
		targetPitch -= delta.Y * CameraConfig.MouseSensitivity * sensitivity * invert
	end

	-- Dokunmatik
	if pendingTouchDelta.Magnitude > 0 then
		lastLookInput = os.clock()
		targetYaw -= pendingTouchDelta.X * CameraConfig.TouchSensitivity * sensitivity
		targetPitch -= pendingTouchDelta.Y * CameraConfig.TouchSensitivity * sensitivity * invert
		pendingTouchDelta = Vector2.zero
	end

	-- Gamepad
	if gamepadLook.Magnitude > CameraConfig.GamepadDeadzone then
		lastLookInput = os.clock()
		local rate = CameraConfig.GamepadSensitivity * sensitivity * dt
		targetYaw -= gamepadLook.X * rate
		targetPitch += gamepadLook.Y * rate * invert
	end

	targetPitch = math.clamp(targetPitch, profile.MinPitch * DEG, profile.MaxPitch * DEG)
end

local function connectInput()
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			rightMouseHeld = true
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			-- Joystick ve butonlar "processed" gelir; boş ekran dokunuşları kamerayı çevirir
			cameraTouches[input] = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightMouseHeld = false
		elseif input.UserInputType == Enum.UserInputType.Touch then
			cameraTouches[input] = nil
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.zero
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch then
			if cameraTouches[input] then
				-- İki parmak aynı anda kameradaysa pinch işler, çevirme yapma
				local count = 0
				for _ in cameraTouches do
					count += 1
				end
				if count == 1 then
					pendingTouchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
				end
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			local mode = currentMode
			if mode and isFollowMode(mode) then
				local profile = getProfile(mode)
				local d = (userDistance[mode] or profile.Distance) - input.Position.Z * CameraConfig.ZoomStep
				userDistance[mode] = math.clamp(d, profile.MinDistance, profile.MaxDistance)
			end
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale, _, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			lastPinchScale = scale
		elseif state == Enum.UserInputState.Change and lastPinchScale then
			local mode = currentMode
			if mode and isFollowMode(mode) then
				local profile = getProfile(mode)
				local ratio = scale / math.max(lastPinchScale, 0.01)
				local d = (userDistance[mode] or profile.Distance) / math.max(ratio, 0.01)
				userDistance[mode] = math.clamp(d, profile.MinDistance, profile.MaxDistance)
			end
			lastPinchScale = scale
		else
			lastPinchScale = nil
		end
	end)
end

-- ===== Çarpışma =====
local function castSafe(origin: Vector3, target: Vector3, radius: number): Vector3
	local offset = target - origin
	local length = offset.Magnitude
	if length < 1e-3 then
		return target
	end
	local result = workspace:Spherecast(origin, radius, offset, raycastParams)
	if result then
		return origin + offset.Unit * math.max(result.Distance - 0.05, 0)
	end
	return target
end

-- ===== Kare güncellemesi =====
local function stepFollow(dt: number, mode: string)
	local profile = getProfile(mode)
	local character = controllers.CharacterController
	local root = character:GetRootPart()
	local subject: BasePart? = followSubject or root
	if not subject or not subject.Parent then
		return -- karakter yok (ölüm/yeniden doğma): son kareyi koru
	end

	applyLookInput(dt, profile)

	-- Araç kamerası: oyuncu bir süre bakış girişi yapmazsa aracın gidiş yönünün arkasına yumuşakça döner
	if autoFollowHeading and followSubject and os.clock() - lastLookInput > AUTO_FOLLOW_DELAY then
		local velocity = followSubject.AssemblyLinearVelocity
		local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if flatSpeed > 4 then
			local look = followSubject.CFrame.LookVector
			local heading = math.atan2(-look.X, -look.Z)
			-- geri giderken kamerayı ters çevirme
			local alpha = MathUtil.SmoothAlpha(2.2, dt)
			targetYaw = MathUtil.LerpAngle(targetYaw, heading, alpha)
			targetPitch = MathUtil.Lerp(targetPitch, -12 * DEG, alpha)
		end
	end

	local smoothing = getSettings():Get("CameraSmoothing")
	local rotAlpha = if smoothing then MathUtil.SmoothAlpha(profile.RotationSharpness, dt) else 1
	yaw = MathUtil.LerpAngle(yaw, targetYaw, rotAlpha)
	pitch = MathUtil.Lerp(pitch, targetPitch, rotAlpha)

	-- Pivot: avatarın GERÇEK göz yüksekliği (kısa/uzun avatarlar, R6/R15)
	local eyeHeight = if followSubject then 0 else character:GetEyeHeight()
	local targetPivot = subject.Position + Vector3.new(0, eyeHeight, 0)
	-- Işınlanma algılama: hedef çok uzaktaysa yumuşatma yerine anında yerleş
	if pivot and ((pivot :: Vector3) - targetPivot).Magnitude > 25 then
		snapNextFrame = true
	end
	if snapNextFrame or pivot == nil or profile.Distance == 0 then
		pivot = targetPivot
	else
		pivot = (pivot :: Vector3):Lerp(targetPivot, MathUtil.SmoothAlpha(profile.FollowSharpness, dt))
	end
	local pivotPos = pivot :: Vector3

	local rotation = CFrame.fromOrientation(pitch, yaw, 0)
	local yawOnly = CFrame.fromOrientation(0, yaw, 0)

	local cameraPosition: Vector3
	if profile.Distance == 0 then
		-- Birinci şahıs: göz hizası, hafif ileri (gövdeye bakınca içini görmesin)
		local forward = yawOnly.LookVector
		cameraPosition = pivotPos + Vector3.new(0, profile.ShoulderOffset.Y, 0) + forward * 0.25
		applyCharacterTransparency(1, true)

		-- Karakter kameranın yönüne bakar (koltukta değilse)
		local humanoid = character:GetHumanoid()
		if root and humanoid and humanoid.SeatPart == nil and humanoid.Health > 0 then
			root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)
		end
		currentDistance = 0
	else
		local side = getSettings():Get("ShoulderSide")
		local shoulder = profile.ShoulderOffset
		-- 1) Pivot → omuz noktası (yan + yukarı), duvara girmesin
		local shoulderTarget = pivotPos + yawOnly:VectorToWorldSpace(Vector3.new(shoulder.X * side, shoulder.Y, 0))
		local shoulderPoint = castSafe(pivotPos, shoulderTarget, profile.CollisionRadius)

		-- 2) Omuz → geri (oyuncu yakınlaştırma tercihi)
		local wanted = userDistance[mode] or profile.Distance
		local backTarget = shoulderPoint - rotation.LookVector * wanted
		local safePoint = castSafe(shoulderPoint, backTarget, profile.CollisionRadius)
		local allowed = (safePoint - shoulderPoint).Magnitude

		if snapNextFrame or allowed < currentDistance then
			currentDistance = allowed -- içeri anında (duvar içinden görmemek için)
		else
			currentDistance = MathUtil.Lerp(currentDistance, allowed, MathUtil.SmoothAlpha(6, dt)) -- dışarı yumuşak
		end
		cameraPosition = shoulderPoint - rotation.LookVector * currentDistance

		-- Kamera kafaya çok yaklaşırsa karakteri soldur
		local closeness = (cameraPosition - pivotPos).Magnitude
		local fadeDistance = CameraConfig.CharacterFadeDistance
		if closeness < fadeDistance and not followSubject then
			applyCharacterTransparency(math.clamp(1 - (closeness / fadeDistance), 0, 0.9), false)
		else
			applyCharacterTransparency(0, false)
		end
	end
	snapNextFrame = false

	camera.CFrame = CFrame.new(cameraPosition) * rotation
	camera.Focus = CFrame.new(pivotPos)

	-- FOV: depar sırasında hafif artış = hız hissi
	local fovTarget = profile.FieldOfView + getSettings():Get("FieldOfViewOffset")
	if character:GetMovementState() == Constants.MovementStates.Sprint then
		fovTarget += profile.SprintFovBoost
	end
	currentFov = MathUtil.Lerp(currentFov, fovTarget, MathUtil.SmoothAlpha(8, dt))
	camera.FieldOfView = currentFov
end

local function stepScripted(dt: number, entry)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	applyCharacterTransparency(0, false)
	-- Supplier: fn(dt) -> CFrame, FOV?, Focus? (Focus: render ayrıntı/ışık merkezi; menü çekimleri için)
	local ok, cframe, fov, focus = pcall(entry.Supplier, dt)
	if ok and typeof(cframe) == "CFrame" then
		camera.CFrame = cframe
		if type(fov) == "number" then
			currentFov = fov
			camera.FieldOfView = fov
		end
		if typeof(focus) == "CFrame" then
			camera.Focus = focus
		end
	else
		Log.Warn("Senaryolu kamera fonksiyonu hata verdi, istek kaldırılıyor:", cframe)
		for owner, e in overrides do
			if e == entry then
				CameraController:Release(owner)
			end
		end
	end
end

local function restoreDefaultCamera()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	running = false
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = controllers.CharacterController:GetHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
		humanoid.AutoRotate = true
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	applyCharacterTransparency(0, false)
end

local function step(dt: number)
	local ok, err = pcall(function()
		if camera ~= workspace.CurrentCamera then
			camera = workspace.CurrentCamera
		end
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		filterRefreshTimer -= dt
		if filterRefreshTimer <= 0 then
			filterRefreshTimer = 0.5
			refreshFilter()
		end
		updateResolvedMode()
		local mode, entry = resolveMode()
		if entry and entry.Supplier then
			stepScripted(dt, entry)
		else
			stepFollow(dt, mode)
		end
	end)
	if ok then
		consecutiveErrors = 0
	else
		consecutiveErrors += 1
		Log.Warn("Kamera karesi hata verdi:", err)
		if consecutiveErrors >= CameraConfig.MaxConsecutiveErrors then
			Log.Error("Kamera güvenlik ağı devrede: Roblox varsayılan kamerasına dönülüyor.")
			restoreDefaultCamera()
		end
	end
end

-- ===== Genel API =====
function CameraController:GetMode(): string
	return currentMode or baseMode
end

function CameraController:SetBaseMode(mode: string)
	if not table.find(Constants.PlayerSelectableCameraModes, mode) then
		Log.Warn("Temel mod olarak seçilemez:", mode)
		return
	end
	baseMode = mode
	updateResolvedMode()
end

function CameraController:RequestMode(owner: string, mode: string, priority: number?)
	assert(isFollowMode(mode), "RequestMode sadece takip modları içindir: " .. tostring(mode))
	overrideOrder += 1
	overrides[owner] = { Mode = mode, Priority = priority or 10, Supplier = nil, Order = overrideOrder }
	updateResolvedMode()
end

function CameraController:RequestScripted(owner: string, mode: string, priority: number?, supplier: (number) -> (CFrame, number?))
	overrideOrder += 1
	overrides[owner] = { Mode = mode, Priority = priority or 50, Supplier = supplier, Order = overrideOrder }
	updateResolvedMode()
end

function CameraController:Release(owner: string)
	if overrides[owner] then
		overrides[owner] = nil
		updateResolvedMode()
	end
end

-- Araç sistemleri (Aşama 3) takip edilecek parçayı burada verir; nil → karakter
function CameraController:SetFollowSubject(part: BasePart?)
	followSubject = part
	snapNextFrame = true
	refreshFilter()
end

function CameraController:SetAutoFollowHeading(enabled: boolean)
	autoFollowHeading = enabled
end

function CameraController:SetCursorFree(owner: string, free: boolean)
	cursorFreeOwners[owner] = if free then true else nil
end

function CameraController:SnapBehindCharacter()
	local root = followSubject or controllers.CharacterController:GetRootPart()
	if root then
		local look = root.CFrame.LookVector
		targetYaw = math.atan2(-look.X, -look.Z)
		targetPitch = -10 * DEG
		yaw, pitch = targetYaw, targetPitch
		snapNextFrame = true
	end
	-- Ani yerleşmede birikmiş bakış girişini at (ör. menüdeyken yapılan dokunmatik kaydırmalar)
	pendingTouchDelta = Vector2.zero
	gamepadLook = Vector2.zero
end

-- Anahtar karelerle sinematik geçiş. Bitince (veya hata/zaman aşımında) kamera MUTLAKA geri döner.
-- keyframes: { { CFrame = CFrame, Duration = number, FieldOfView = number? }, ... }
-- İlk karenin Duration'ı yok sayılır (başlangıç noktası).
function CameraController:PlayCinematic(keyframes: { any }, owner: string?)
	local ownerName = owner or "Cinematic"
	assert(#keyframes >= 2, "En az 2 anahtar kare gerekli")
	local completed = Signal.new()
	local total = 0
	for i = 2, #keyframes do
		total += math.max(keyframes[i].Duration or 1, 0.01)
	end
	local elapsed = 0
	local finished = false

	local function finish()
		if finished then
			return
		end
		finished = true
		CameraController:Release(ownerName)
		completed:Fire()
	end

	local function ease(t: number): number
		return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2 -- cubic in-out
	end

	CameraController:RequestScripted(ownerName, Modes.Cinematic, 90, function(dt)
		elapsed += dt
		local time = elapsed
		for i = 2, #keyframes do
			local duration = math.max(keyframes[i].Duration or 1, 0.01)
			if time <= duration or i == #keyframes then
				local a, b = keyframes[i - 1], keyframes[i]
				local t = ease(math.clamp(time / duration, 0, 1))
				local fovA = a.FieldOfView or 70
				local fovB = b.FieldOfView or fovA
				if elapsed >= total then
					task.defer(finish)
				end
				return a.CFrame:Lerp(b.CFrame, t), MathUtil.Lerp(fovA, fovB, t)
			end
			time -= duration
		end
		task.defer(finish)
		return keyframes[#keyframes].CFrame, keyframes[#keyframes].FieldOfView
	end)

	-- Güvenlik zamanlayıcısı: ne olursa olsun kamera kilitli kalmaz (Bölüm 18.4)
	task.delay(total + 2, finish)

	return {
		Completed = completed,
		Cancel = finish,
	}
end

-- ===== Yaşam döngüsü =====
function CameraController:Init(allControllers)
	controllers = allControllers
end

function CameraController:Start()
	local settingsController = controllers.SettingsController
	baseMode = settingsController:Get("CameraMode")
	settingsController.Changed:Connect(function(key, value)
		if key == "CameraMode" then
			CameraController:SetBaseMode(value)
		end
	end)

	controllers.InputController.ActionBegan:Connect(function(action)
		if action == "CameraCycle" then
			local list = Constants.PlayerSelectableCameraModes
			local index = table.find(list, baseMode) or 0
			local nextMode = list[(index % #list) + 1]
			settingsController:Set("CameraMode", nextMode)
		elseif action == "FreeCursor" then
			CameraController:SetCursorFree("FreeCursorKey", true)
		end
	end)
	controllers.InputController.ActionEnded:Connect(function(action)
		if action == "FreeCursor" then
			CameraController:SetCursorFree("FreeCursorKey", false)
		end
	end)

	controllers.CharacterController.CharacterChanged:Connect(function(character)
		collectCharacterParts(character)
		if character then
			local root = controllers.CharacterController:GetRootPart()
			if root then
				-- Yeni doğumda kamera karakterin arkasına yerleşir
				task.defer(function()
					CameraController:SnapBehindCharacter()
				end)
			end
			setAutoRotate(currentMode ~= Modes.FirstPerson)
			if descendantConnection then
				descendantConnection:Disconnect()
			end
			descendantConnection = character.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") then
					table.insert(characterParts, d)
					lastTransparency = -1
				end
			end)
		elseif descendantConnection then
			descendantConnection:Disconnect()
			descendantConnection = nil
		end
	end)
	collectCharacterParts(controllers.CharacterController:GetCharacter())

	connectInput()
	updateResolvedMode()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, step)
	running = true
end

function CameraController:IsRunning(): boolean
	return running
end

return CameraController
