-- FrontEndController: ana menü ve oyuna giriş akışı (Aşama 1). Durum makinesi + sahiplik kuralları.
-- Görsel katmanlar FrontEnd/ klasöründedir (Shell, Backdrop, Screens/*, Widgets...); bu dosya sadece yönetir.
--
-- Durumlar:
--   Title     İlk açılış. Karakter YOK (Players.CharacterAutoLoads = false). Menü kamerası şehri gösterir.
--   Spawning  OYNA'ya basıldı; sunucudan karakter bekleniyor (tek istek, zaman aşımlı, tekrar denenebilir).
--   Playing   Menü kapalı; normal oyun.
--   Paused    Oyun içinde menü yeniden açıldı (P / D-Pad Sol / dokunmatik ☰). Çok oyunculu dünya durmaz;
--             karakter yerinde kalır, oyun girişleri kilitlenir.
--
-- Sahiplik kuralları (mevcut mimariye uyum):
--   * Kamera: CFrame'i sadece CameraController yazar. Menü "FrontEnd" adına RequestScripted isteği bırakır;
--     kapanırken Release + SnapBehindCharacter → normal kamera eksiksiz geri gelir.
--   * Girişler: menü açıkken InputController "OnFoot" bağlamı kapanır, "Menu" bağlamı açılır; PlayerModule
--     kontrolleri, ProximityPrompt'lar, dokunmatik joystick/zıplama ve mobil butonlar kapanır.
--   * Araçtayken menü açılmaz (kontrolleri, kamerayı ve mobil düzeni araç sistemi yönetir).
--   * Tek ScreenGui (Shell). ResetOnSpawn = false; yeniden doğmada yeniden yaratılmaz.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local RemoteRegistry = require(Shared.RemoteRegistry)
local Signal = require(Shared.Utilities.Signal)
local Log = require(Shared.Utilities.Log).new("FrontEnd")
local FrontEndConfig = require(Modules.FrontEndConfig)

local FrontEndFolder = script.Parent.Parent:WaitForChild("FrontEnd")
local ScreensFolder = FrontEndFolder:WaitForChild("Screens")
local Strings = require(FrontEndFolder:WaitForChild("Strings"))
local Fader = require(FrontEndFolder:WaitForChild("Fader"))
local Shell = require(FrontEndFolder:WaitForChild("Shell"))
local MenuInput = require(FrontEndFolder:WaitForChild("MenuInput"))
local MenuCamera = require(FrontEndFolder:WaitForChild("MenuCamera"))
local MainScreen = require(ScreensFolder:WaitForChild("MainScreen"))
local SettingsScreen = require(ScreensFolder:WaitForChild("SettingsScreen"))
local GarageScreen = require(ScreensFolder:WaitForChild("GarageScreen"))
local MapScreen = require(ScreensFolder:WaitForChild("MapScreen"))

local FrontEndController = {
	Name = "FrontEndController",
	Priority = 11, -- diğer tüm kontrolcüler başladıktan sonra
	StateChanged = Signal.new(), -- (newState, oldState)
	Opened = Signal.new(), -- (mode)
	Closed = Signal.new(),
}

local OWNER = "FrontEnd"
local CAMERA_PRIORITY = 80 -- araç kamerası (20) ile sinematik (90) arasında
local HIDDEN_CORE_GUIS = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }

local player = Players.LocalPlayer
local controllers
local shell
local screens = {}

local state = "Title"
local menuVisible = false
local gameplayLocked = false
local currentScreenName: string? = nil
local spawnToken = 0
local lastSpawnStatus: string? = nil
local savedCoreGui: { [Enum.CoreGuiType]: boolean } = {}
local playerControls = nil
local grade: ColorCorrectionEffect? = nil
local streamRequestDone = false
local requestSpawnRemote: RemoteEvent

-- ===== Yardımcılar =====
local function reduceMotion(): boolean
	return controllers.SettingsController:Get("ReduceMotion") == true
end

local function duration(seconds: number): number
	return if reduceMotion() then 0 else seconds
end

local function playSound(kind: string)
	local audio = controllers.AudioController
	if audio and audio.PlayInterface then
		audio:PlayInterface(kind)
	end
end

local function setState(newState: string)
	if newState ~= state then
		local old = state
		state = newState
		FrontEndController.StateChanged:Fire(newState, old)
	end
end

local function inVehicle(): boolean
	return controllers.VehicleController ~= nil and controllers.VehicleController:IsInVehicle()
end

-- Araçtayken menü/harita sadece araç neredeyse dururken açılır (sürüş girişleri o sırada askıya alınır)
local STOPPED_SPEED = 3 -- stud/sn
local function vehicleMoving(): boolean
	local c = controllers.VehicleController and controllers.VehicleController:GetCurrent()
	return c ~= nil and c.Chassis ~= nil and c.Chassis.AssemblyLinearVelocity.Magnitude > STOPPED_SPEED
end

local function isTouch(): boolean
	return controllers.InputController:GetDeviceType() == Constants.DeviceTypes.Touch
end

local function currentScreen()
	return currentScreenName and screens[currentScreenName]
end

local function getControls()
	if not playerControls then
		local ok, controls = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
		end)
		if ok then
			playerControls = controls
		else
			Log.Warn("PlayerModule kontrolleri alınamadı:", controls)
		end
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

-- ===== Oyun girişlerini kilitle / aç =====
local function setCoreGuiHidden(hidden: boolean)
	for _, kind in HIDDEN_CORE_GUIS do
		pcall(function()
			if hidden then
				if savedCoreGui[kind] == nil then
					savedCoreGui[kind] = StarterGui:GetCoreGuiEnabled(kind)
				end
				StarterGui:SetCoreGuiEnabled(kind, false)
			elseif savedCoreGui[kind] ~= nil then
				StarterGui:SetCoreGuiEnabled(kind, savedCoreGui[kind])
				savedCoreGui[kind] = nil
			end
		end)
	end
end

local function lockGameplay(lock: boolean)
	if gameplayLocked == lock then
		return
	end
	gameplayLocked = lock
	local input = controllers.InputController
	if lock then
		setDefaultControls(false)
		ProximityPromptService.Enabled = false
		pcall(function()
			GuiService.TouchControlsEnabled = false
		end)
		controllers.MobileControlsController:SetLayout("Hidden")
		input:SetContext("OnFoot", false)
		if inVehicle() then
			input:SetContext("Vehicle", false) -- araç tuşları menü tuşlarıyla aynı önceliktedir; askıya al
		end
		input:SetContext("Menu", true)
		controllers.CharacterController:SetMovementLocked(OWNER, true)
		setCoreGuiHidden(true)
	else
		input:SetContext("Menu", false)
		input:SetContext("OnFoot", true)
		if inVehicle() then
			input:SetContext("Vehicle", true)
		end
		controllers.CharacterController:SetMovementLocked(OWNER, false)
		pcall(function()
			GuiService.TouchControlsEnabled = true
		end)
		-- Araçtaysa kontroller/istemler/mobil düzen araç sistemine aittir; dokunma.
		if not inVehicle() then
			setDefaultControls(true)
			ProximityPromptService.Enabled = true
			controllers.MobileControlsController:SetLayout("OnFoot")
		else
			controllers.MobileControlsController:SetLayout(controllers.VehicleController:GetMobileLayout())
		end
		setCoreGuiHidden(false)
	end
end

-- ===== Kamera =====
local function setGrade(on: boolean)
	local camera = workspace.CurrentCamera
	if on and (not grade or grade.Parent ~= camera) then
		if grade then
			grade:Destroy()
		end
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "SolaraMenuGrade"
		effect.Saturation = 0.12
		effect.Contrast = 0.06
		effect.TintColor = Color3.fromRGB(255, 240, 232)
		effect.Parent = camera -- kameraya bağlı efekt sadece bu oyuncuda görünür
		grade = effect
	end
	if grade then
		grade.Enabled = on
	end
end

local function requestMenuCamera(kind: string)
	local camera = controllers.CameraController
	local supplier
	if kind == "Pause" then
		local look = workspace.CurrentCamera.CFrame.LookVector
		local startYaw = math.atan2(-look.X, -look.Z) -- mevcut bakışın arkasından başla
		supplier = MenuCamera.PauseSupplier(function()
			return controllers.CharacterController:GetRootPart()
		end, reduceMotion, startYaw)
	else
		supplier = MenuCamera.TitleSupplier(reduceMotion)
	end
	camera:RequestScripted(OWNER, Constants.CameraModes.Menu, CAMERA_PRIORITY, supplier)
	setGrade(true)
end

-- smooth: oyun içi menüden dönüşte kamera yumuşakça arkaya kayar; perde arkasındaki girişte anında yerleşir
local function releaseMenuCamera(smooth: boolean?)
	local camera = controllers.CameraController
	camera:Release(OWNER)
	setGrade(false)
	if not inVehicle() then
		camera:SnapBehindCharacter(smooth)
	end
end

-- ===== Ekranlar =====
local function refreshHints()
	shell:SetHints(controllers.InputController:GetDeviceType(), if menuVisible then currentScreenName else nil, state == "Paused")
end

local function refreshPauseButton()
	shell:SetPauseButtonVisible(state == "Playing" and not menuVisible and isTouch() and not inVehicle())
end

local function navigate(name: string)
	if currentScreenName == name then
		return
	end
	local old = currentScreen()
	local target = screens[name]
	local d = duration(0.22)
	if old then
		old:OnHide()
		Fader.Fade(old.Root, false, d, if name == "Main" then 24 else -24)
	end
	currentScreenName = name
	target:OnShow()
	target.Focus:SetHighlight(not isTouch())
	Fader.Fade(target.Root, true, d, if name == "Main" then -24 else 24, function()
		target.Focus:Refresh()
	end)
	shell.Backdrop:SetStyle(if state == "Paused" then "Paused" else "Title", name ~= "Main", d)
	refreshHints()
end

local function showMenu(mode: string, animate: boolean)
	menuVisible = true
	screens.Main:SetMode(mode)
	if mode ~= "Title" then
		shell.Backdrop:SetFallbackVisible(false, 0) -- oyun içinde arka plan oyunun kendisi
	end
	shell:SetMenuShown(true, if animate then duration(0.35) else 0)
	currentScreenName = nil
	navigate("Main")
	refreshPauseButton()
	FrontEndController.Opened:Fire(mode)
end

local function hideMenu(d: number)
	menuVisible = false
	local screen = currentScreen()
	if screen then
		screen:OnHide()
		Fader.Fade(screen.Root, false, d, 0)
	end
	currentScreenName = nil
	shell:SetMenuShown(false, d)
	refreshPauseButton()
	FrontEndController.Closed:Fire()
end

-- ===== Oyun içi menü =====
local function openPause(): boolean
	if state ~= "Playing" or menuVisible then
		return menuVisible
	end
	if inVehicle() and vehicleMoving() then
		shell:Toast(Strings.Get("Toast.InVehicle"), duration(0.2))
		return false
	end
	lockGameplay(true)
	requestMenuCamera("Pause")
	setState("Paused")
	screens.Main:SetStatus(Strings.Get("Status.Paused"), "info")
	showMenu("Paused", true)
	playSound("Select")
	return true
end

-- Tam ekran harita: oyundaysa menüyü açıp doğrudan HARİTA ekranına geçer
local function openMap()
	if state == "Spawning" then
		return
	end
	if state == "Playing" and not openPause() then
		return
	end
	if menuVisible then
		navigate("Map")
	end
end

local function resume()
	if state ~= "Paused" then
		return
	end
	hideMenu(duration(0.25))
	lockGameplay(false)
	releaseMenuCamera(true)
	setState("Playing")
	refreshPauseButton()
	playSound("Back")
end

-- ===== Doğma (OYNA) =====
-- Karakter gelene ve sunucu onu doğma noktasına taşıyana (SpawnedAt) kadar bekler.
local function characterReady(deadline: number): Model?
	local firstSeen: number? = nil
	while os.clock() < deadline do
		if lastSpawnStatus == "Rejected" then
			return nil
		end
		local character = player.Character
		if character and character.Parent and character:FindFirstChild("HumanoidRootPart") and character:FindFirstChildOfClass("Humanoid") then
			if lastSpawnStatus == "Spawned" and character:GetAttribute(Constants.Attributes.SpawnedAt) ~= nil then
				return character
			end
			firstSeen = firstSeen or os.clock()
			if os.clock() - firstSeen > FrontEndConfig.ClientCharacterReadyTimeout then
				return character
			end
		end
		task.wait(0.1)
	end
	return nil
end

local function enterWorld(token: number)
	local character = characterReady(os.clock() + FrontEndConfig.ClientSpawnTimeout)
	if token ~= spawnToken or state ~= "Spawning" then
		return
	end
	if not character then
		Log.Warn("Doğma başarısız ya da zaman aşımı. Son durum:", lastSpawnStatus)
		setState("Title")
		screens.Main:SetBusy(false)
		screens.Main:SetStatus(Strings.Get("Status.SpawnFailed"), "error")
		playSound("Back")
		return
	end
	-- Perde arkasında: menüyü kapat, girişleri aç, kamerayı karaktere ver
	local fade = duration(0.35)
	shell:SetVeil(true, fade)
	if fade > 0 then
		task.wait(fade)
	end
	hideMenu(0)
	lockGameplay(false)
	releaseMenuCamera()
	screens.Main:SetBusy(false)
	setState("Playing")
	refreshPauseButton()
	task.wait(0.1) -- kamera yeni konumda bir kare otursun
	shell:SetVeil(false, duration(0.5))
	Log.Info("Oyuna girildi")
end

local function play()
	if state == "Paused" then
		resume()
		return
	end
	if state ~= "Title" then
		return -- çift tıklama / zaten bağlanıyor
	end
	setState("Spawning")
	spawnToken += 1
	lastSpawnStatus = nil
	screens.Main:SetBusy(true)
	screens.Main:SetStatus(Strings.Get("Status.Spawning"), "busy")
	requestSpawnRemote:FireServer()
	task.spawn(enterWorld, spawnToken)
end

-- ===== Şehir hazır mı? (Title arka planı) =====
local function cityVisible(): boolean
	if workspace:GetAttribute("WorldReady") ~= true or not streamRequestDone then
		return false
	end
	-- Çekimin ortasından kulelere ışın: kuleler akmışsa çarpar
	local from, target = MenuCamera.TitleProbe()
	local offset = target - from
	return workspace:Raycast(from, offset.Unit * (offset.Magnitude * 1.2)) ~= nil
end

local function cityWatchLoop()
	task.spawn(function()
		local ok = pcall(function()
			player:RequestStreamAroundAsync(FrontEndConfig.StreamFocus, FrontEndConfig.StreamRequestTimeout)
		end)
		if not ok then
			Log.Info("Akış isteği yapılamadı (StreamingEnabled kapalı olabilir)")
		end
		streamRequestDone = true
	end)
	task.spawn(function()
		while shell.Gui.Parent do
			if state == "Title" or state == "Spawning" then
				local visible = cityVisible()
				shell.Backdrop:SetFallbackVisible(not visible, duration(FrontEndConfig.BackdropFadeTime))
				if state == "Title" and not screens.Main:IsShowingError() then
					if workspace:GetAttribute("WorldReady") ~= true then
						local world = workspace:FindFirstChild("World")
						local progress = world and world:GetAttribute("BuildProgress")
						local percent = if type(progress) == "number" then math.floor(progress * 100) else 0
						screens.Main:SetStatus(Strings.Get("Status.CityLoading", percent), "busy")
					elseif not visible then
						screens.Main:SetStatus(Strings.Get("Status.CityStreaming"), "busy")
					else
						screens.Main:SetStatus(Strings.Get("Status.CityReady"), "ok")
					end
				end
			end
			task.wait(FrontEndConfig.CityProbeInterval)
		end
	end)
end

-- ===== Kurulum =====
local function build()
	local function onMove()
		playSound("Move")
	end
	local function back()
		playSound("Back")
		navigate("Main")
	end
	shell = Shell.new({
		OnPauseButton = function()
			openPause()
		end,
		OnLayout = function(compact: boolean)
			for _, screen in screens do
				screen:SetCompact(compact)
			end
		end,
	})
	local function getScale(): number
		return shell:GetScale()
	end
	screens.Main = MainScreen.new({
		Parent = shell.Canvas,
		GetScale = getScale,
		OnMove = onMove,
		Actions = {
			Play = play,
			Garage = function()
				navigate("Garage")
			end,
			Map = function()
				navigate("Map")
			end,
			Settings = function()
				navigate("Settings")
			end,
		},
	})
	screens.Settings = SettingsScreen.new({
		Parent = shell.Canvas,
		GetScale = getScale,
		OnMove = onMove,
		Settings = controllers.SettingsController,
		Back = back,
	})
	screens.Map = MapScreen.new({
		Parent = shell.Canvas,
		GetScale = getScale,
		OnMove = onMove,
		Back = back,
		Navigation = controllers.NavigationController,
		IsTouch = isTouch,
	})
	screens.Garage = GarageScreen.new({
		Parent = shell.Canvas,
		GetScale = getScale,
		OnMove = onMove,
		Back = back,
	})
	shell:UpdateLayout()
end

local function updateVersion()
	local mode = player:GetAttribute(Constants.Attributes.GameMode) or "Normal"
	shell:SetVersion(Strings.Get("Main.Version", Config.Version, Strings.Get("Mode." .. tostring(mode))))
end

local function connectInput()
	MenuInput.connect(controllers.InputController, {
		IsActive = function()
			return menuVisible and state ~= "Spawning" and currentScreen() ~= nil
		end,
		Navigate = function(kind: string, dir: number)
			local screen = currentScreen()
			if screen.HandleNavigate and screen:HandleNavigate(kind, dir) then
				return -- harita: kaydırma
			end
			screen.Focus:SetHighlight(true)
			if kind == "Move" then
				screen.Focus:Move(dir)
			else
				screen.Focus:Adjust(dir)
			end
		end,
		Accept = function()
			local screen = currentScreen()
			if screen.HandleAccept and screen:HandleAccept() then
				playSound("Select")
				return
			end
			screen.Focus:SetHighlight(true)
			if screen.Focus:Activate() then
				playSound("Select")
			end
		end,
		Back = function()
			if currentScreenName ~= "Main" then
				playSound("Back")
				navigate("Main")
			elseif state == "Paused" then
				resume()
			end
		end,
		Tab = function(dir: number)
			currentScreen():HandleTab(dir)
		end,
		Close = resume,
		Open = function()
			openPause()
		end,
		OpenMap = openMap,
	})
end

-- ===== Genel API =====
function FrontEndController:GetState(): string
	return state
end

function FrontEndController:IsMenuOpen(): boolean
	return menuVisible
end

-- Başka sistemler (ör. ileride harita) oyun içi menüyü açabilir
function FrontEndController:OpenPauseMenu()
	openPause()
end

-- Tam ekran haritayı aç (M tuşu, köşe haritasına dokunma)
function FrontEndController:OpenMap()
	openMap()
end

function FrontEndController:Init(allControllers)
	controllers = allControllers
end

function FrontEndController:Start()
	requestSpawnRemote = RemoteRegistry.Get("PlayerRemotes", "RequestSpawn") :: RemoteEvent
	local spawnStatusRemote = RemoteRegistry.Get("PlayerRemotes", "SpawnStatus") :: RemoteEvent
	spawnStatusRemote.OnClientEvent:Connect(function(status: any, detail: any)
		if type(status) ~= "string" then
			return
		end
		lastSpawnStatus = status
		if status == "Queued" and state == "Spawning" then
			screens.Main:SetStatus(Strings.Get("Status.WaitingWorld"), "busy")
		end
		Log.Info("Doğma durumu:", status, detail)
	end)

	build()
	updateVersion()
	player:GetAttributeChangedSignal(Constants.Attributes.GameMode):Connect(updateVersion)

	-- Başlangıç: menü açık, oyun girişleri kilitli, kamera şehirde, perde açılır
	lockGameplay(true)
	requestMenuCamera("Title")
	showMenu("Title", false)
	cityWatchLoop()
	shell:SetVeil(false, duration(0.8))

	connectInput()
	controllers.InputController.DeviceChanged:Connect(function(device)
		local screen = currentScreen()
		if screen then
			screen.Focus:SetHighlight(device ~= Constants.DeviceTypes.Touch)
		end
		refreshHints()
		refreshPauseButton()
	end)

	-- Menü açıkken araca binilirse (ör. bir motosiklet koltuğuna değdi) menüyü kapat; araç sistemi devralır
	controllers.VehicleController.Entered:Connect(function()
		if state == "Paused" then
			resume()
		end
		refreshPauseButton()
	end)
	controllers.VehicleController.Exited:Connect(refreshPauseButton)

	-- Menü açıkken yeniden doğulursa PlayerModule kontrolleri kapalı kalsın
	controllers.CharacterController.CharacterChanged:Connect(function(character)
		if character and gameplayLocked then
			task.defer(function()
				if gameplayLocked then
					setDefaultControls(false)
				end
			end)
		end
	end)
end

return FrontEndController
