-- MobileControlsController: dokunmatik cihazlar için ÖZEL buton katmanı (Bölüm 21).
--
-- Yaya (OnFoot): Depar (toggle) ve Kamera modu. Joystick ve zıplama Roblox'un kendi dokunmatik kontrolleridir;
-- bizim butonlar zıplama butonunun SOLUNA ve ÜSTÜNE dizilir.
--
-- Sürüş (Aşama 3): yerleşimin tamamı ReplicatedStorage/Modules/DrivingLayout'tan gelir (HUD ile aynı hesap):
--   sol alt  : analog direksiyon pedi (parmağın konumu = direksiyon açısı) ya da ◀ ▶ butonları (ayar)
--   sağ alt  : büyük GAZ, solunda FREN, frenin üstünde EL FRENİ, gazın üstünde KORNA
--   üst sağ  : İN · FAR · ÇEVİR;   sinyaller direksiyonun üstünde
--   ayrılmış : sol üst harita alanı, üst orta hız çubuğu (VehicleHUDController)
-- tools/test_driving_layout.py bu yerleşimi 10 ekran boyutu × ölçek × araç türü için çakışma/taşma/
-- en küçük dokunma hedefi (44 px) açısından denetler.
--
-- Sürüşte Roblox'un joystick ve zıplama butonu gizlenir (GuiService.TouchControlsEnabled = false):
-- zıplama koltuktan atar ve gaz butonunun altında kalabilirdi.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UIConfig = require(Modules.UIConfig)
local DrivingLayout = require(Modules:WaitForChild("DrivingLayout"))
local Log = require(Shared.Utilities.Log).new("MobileControls")

local MobileControlsController = {
	Name = "MobileControlsController",
	Priority = 8,
}

local player = Players.LocalPlayer
local controllers
local Strings -- FrontEnd/Strings (Init'te yüklenir)
local screenGui: ScreenGui? = nil
local root: Frame? = nil
local buttons: { [string]: GuiObject } = {}
local layoutName = "OnFoot"
local holdInputs: { [InputObject]: string } = {}
local warnedLayout = false

-- Sürüş butonları: { isim, etiket anahtarı, eylem, basılı-tut?, görünür olduğu düzenler, stil }
local VEHICLE_BUTTONS = {
	{ "SteerL", nil, "VehLeft", true, { Car = true, Motorcycle = true }, "ChevronL" },
	{ "SteerR", nil, "VehRight", true, { Car = true, Motorcycle = true }, "ChevronR" },
	{ "Gas", "Mobile.Gas", "VehGas", true, { Car = true, Motorcycle = true }, "Gas" },
	{ "Brake", "Mobile.Brake", "VehBrake", true, { Car = true, Motorcycle = true }, "Brake" },
	{ "Handbrake", "Mobile.Handbrake", "VehHandbrake", true, { Car = true }, "Round" },
	{ "Horn", "Mobile.Horn", "VehHorn", true, { Car = true, Motorcycle = true }, "Round" },
	{ "Exit", "Mobile.Exit", "VehExit", false, { Car = true, Motorcycle = true, Passenger = true }, "Round" },
	{ "Lights", "Mobile.Lights", "VehLights", false, { Car = true, Motorcycle = true }, "Round" },
	{ "Flip", "Mobile.Flip", "VehFlip", false, { Car = true }, "Round" },
	{ "IndL", nil, "VehIndLeft", false, { Car = true, Motorcycle = true }, "ChevronL" },
	{ "IndR", nil, "VehIndRight", false, { Car = true, Motorcycle = true }, "ChevronR" },
}
local vehicleButtons: { [string]: GuiObject } = {}

-- Direksiyon pedi
local pad: TextButton? = nil
local padKnob: Frame? = nil
local padInput: InputObject? = nil
local PAD_DEADZONE = 0.06
local PAD_CURVE = 1.25 -- merkez çevresinde ince ayar, uçta tam direksiyon

local CAMERA_LABELS = {
	ThirdPerson = "OMUZ",
	ThirdPersonAlt = "TAKİP",
	FirstPerson = "GÖZ",
}

local function text(key: string): string
	return if Strings then Strings.Get(key) else key
end

local function isVehicleLayout(name: string): boolean
	return name == "Car" or name == "Motorcycle" or name == "Passenger"
end

-- Roblox zıplama butonunun kapladığı alan (TouchGui'deki resmi yerleşimle aynı mantık)
local function getJumpButtonRect(viewport: Vector2): (number, number, number)
	local minAxis = math.min(viewport.X, viewport.Y)
	if minAxis <= 500 then
		return 70, 25, 20 -- boyut, sağ boşluk, alt boşluk
	end
	return 120, 50, 90
end

local function getUserScale(): number
	return controllers and controllers.SettingsController and controllers.SettingsController:Get("MobileButtonScale") or 1
end

local function getButtonSize(viewport: Vector2): number
	return DrivingLayout.ButtonSize(viewport.X, viewport.Y, getUserScale())
end

-- ===== Buton görünümü =====
local function decorate(button: GuiObject, radiusScale: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radiusScale, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = UIConfig.Colors.TextMuted
	stroke.Transparency = 0.3
	stroke.Parent = button
end

local function makeButton(name: string, label: string, radiusScale: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.AutoLocalize = false
	button.Text = label
	button.TextScaled = true
	button.FontFace = UIConfig.Fonts.Title
	button.TextColor3 = UIConfig.Colors.Text
	button.BackgroundColor3 = UIConfig.Colors.Background
	button.BackgroundTransparency = UIConfig.Mobile.BackgroundTransparency
	button.AnchorPoint = Vector2.new(1, 1)
	decorate(button, radiusScale or 0.5)
	local padding = Instance.new("UIPadding")
	local p = UDim.new(0.22, 0)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = p, p, p, p
	padding.Parent = button
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = button

	-- Basma geri bildirimi
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(button, UIConfig.Tween.Fast, { BackgroundTransparency = 0.1 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(button, UIConfig.Tween.Normal, { BackgroundTransparency = UIConfig.Mobile.BackgroundTransparency }):Play()
		end
	end)
	return button
end

-- İki ince çubuktan ok başı (glif yazı tipine bağlı kalmasın). Kare buton varsayılır.
-- Çubuk boyu L = 0.42; 40° açıyla tepe noktasında birleşirler: merkezler tepeden (L/2)(cos40, sin40) uzakta.
local function addChevron(button: GuiObject, pointsLeft: boolean)
	local halfX, halfY = 0.21 * math.cos(math.rad(40)), 0.21 * math.sin(math.rad(40))
	local apexX = if pointsLeft then 0.42 else 0.58
	for _, sign in { -1, 1 } do -- -1 üst çubuk, +1 alt çubuk
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(apexX + (if pointsLeft then halfX else -halfX), 0.5 + sign * halfY)
		bar.Size = UDim2.new(0.42, 0, 0, 4)
		bar.Rotation = (if pointsLeft then 1 else -1) * sign * 40
		bar.BackgroundColor3 = UIConfig.Colors.Text
		bar.BorderSizePixel = 0
		bar.Parent = button
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bar
	end
end

local function setActiveLook(button: GuiObject, active: boolean)
	local stroke = button:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Color = if active then UIConfig.Colors.Accent else UIConfig.Colors.TextMuted
		stroke.Thickness = if active then 3 else 2
	end
	if button:IsA("TextButton") then
		button.TextColor3 = if active then UIConfig.Colors.Accent else UIConfig.Colors.Text
	end
end

-- ===== Direksiyon pedi =====
local function setPadValue(x: number?)
	local input = controllers.InputController
	if x == nil then
		input:SetAnalog("VehSteer", nil)
		if padKnob then
			padKnob.Position = UDim2.fromScale(0.5, 0.5)
		end
		return
	end
	local magnitude = math.abs(x)
	local steer = 0
	if magnitude > PAD_DEADZONE then
		steer = math.sign(x) * ((magnitude - PAD_DEADZONE) / (1 - PAD_DEADZONE)) ^ PAD_CURVE
	end
	input:SetAnalog("VehSteer", steer)
	if padKnob then
		padKnob.Position = UDim2.fromScale((x + 1) / 2, 0.5)
	end
end

local function updatePadFrom(position: Vector3)
	if not pad then
		return
	end
	local width = math.max(pad.AbsoluteSize.X, 1)
	local rel = (position.X - pad.AbsolutePosition.X) / width
	setPadValue(math.clamp(rel * 2 - 1, -1, 1))
end

local function releasePad()
	padInput = nil
	setPadValue(nil)
	if pad then
		setActiveLook(pad, false)
	end
end

local function buildPad(parent: Instance)
	local p = Instance.new("TextButton")
	p.Name = "SteerPad"
	p.Text = ""
	p.AutoButtonColor = false
	p.AutoLocalize = false
	p.BackgroundColor3 = UIConfig.Colors.Background
	p.BackgroundTransparency = 0.5
	p.Visible = false
	decorate(p, 0.5)
	-- ray ve orta çizgi
	local rail = Instance.new("Frame")
	rail.AnchorPoint = Vector2.new(0.5, 0.5)
	rail.Position = UDim2.fromScale(0.5, 0.5)
	rail.Size = UDim2.new(0.86, 0, 0, 4)
	rail.BackgroundColor3 = UIConfig.Colors.TextMuted
	rail.BackgroundTransparency = 0.4
	rail.BorderSizePixel = 0
	rail.Parent = p
	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.new(0, 2, 0.5, 0)
	center.BackgroundColor3 = UIConfig.Colors.TextMuted
	center.BorderSizePixel = 0
	center.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.06)
	label.Size = UDim2.fromScale(0.6, 0.22)
	label.TextScaled = true
	label.FontFace = UIConfig.Fonts.Title
	label.TextColor3 = UIConfig.Colors.TextMuted
	label.TextTransparency = 0.3
	label.AutoLocalize = false
	label.Text = text("Mobile.Steer")
	label.Parent = p
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromScale(0.62, 0.62)
	knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
	knob.BackgroundColor3 = UIConfig.Colors.Accent
	knob.BackgroundTransparency = 0.15
	knob.BorderSizePixel = 0
	knob.Parent = p
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0.5, 0)
	kc.Parent = knob

	p.InputBegan:Connect(function(io)
		if padInput == nil and (io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1) then
			padInput = io
			setActiveLook(p, true)
			updatePadFrom(io.Position)
		end
	end)
	p.Parent = parent
	pad = p
	padKnob = knob
end

-- ===== Yerleşim =====
local function placeRect(button: GuiObject?, r)
	if button and r then
		button.AnchorPoint = Vector2.zero
		button.Position = UDim2.fromOffset(r.X, r.Y)
		button.Size = UDim2.fromOffset(r.W, r.H)
	end
end

local function layout()
	if not screenGui or not root then
		return
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	local size = getButtonSize(viewport)
	local jumpSize, jumpRight, jumpBottom = getJumpButtonRect(viewport)
	local gap = UIConfig.Mobile.Spacing

	-- Yaya düzeni (zıplama butonuna göre; değişmedi)
	local sprint = buttons.Sprint
	if sprint then
		sprint.AnchorPoint = Vector2.new(1, 1)
		sprint.Size = UDim2.fromOffset(size, size)
		sprint.Position = UDim2.new(1, -(jumpRight + jumpSize + gap), 1, -jumpBottom)
	end
	local cam = buttons.Camera
	if cam then
		local small = math.floor(size * 0.8)
		cam.AnchorPoint = Vector2.new(1, 1)
		cam.Size = UDim2.fromOffset(small, small)
		cam.Position = UDim2.new(1, -jumpRight, 1, -(jumpBottom + jumpSize + gap))
	end

	-- Sürüş düzeni (DrivingLayout)
	if isVehicleLayout(layoutName) then
		local area = root.AbsoluteSize
		local steering = controllers.SettingsController:Get("MobileSteering") or "Pad"
		local rects = DrivingLayout.Touch(area.X, area.Y, size, { Kind = layoutName, Steering = steering })
		for name, b in vehicleButtons do
			placeRect(b, rects[name])
		end
		placeRect(pad, rects.Pad)
		if RunService:IsStudio() and not warnedLayout then
			local problems = DrivingLayout.FindOverlaps(rects, 2)
			if #problems > 0 then
				warnedLayout = true
				Log.Warn("Sürüş düzeni çakışması:", table.concat(problems, ", "), "ekran", area)
			end
		end
	end
end

local function applyLayoutVisibility()
	if buttons.Sprint then
		buttons.Sprint.Visible = layoutName == "OnFoot"
	end
	if buttons.Camera then
		buttons.Camera.Visible = layoutName == "OnFoot"
	end
	local steering = controllers.SettingsController:Get("MobileSteering") or "Pad"
	local usePad = steering == "Pad"
	for _, def in VEHICLE_BUTTONS do
		local b = vehicleButtons[def[1]]
		if b then
			local visible = def[5][layoutName] == true
			if def[1] == "SteerL" or def[1] == "SteerR" then
				visible = visible and not usePad
			end
			b.Visible = visible
		end
	end
	if pad then
		pad.Visible = usePad and (layoutName == "Car" or layoutName == "Motorcycle")
	end
end

local function releaseAllHolds()
	for io, action in holdInputs do
		holdInputs[io] = nil
		controllers.InputController:Trigger(action, false)
	end
	for _, b in vehicleButtons do
		setActiveLook(b, false)
	end
	releasePad()
end

local function build()
	if screenGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	-- Roblox üst çubuğu ve çentik dışında kalan alan (sürüş butonları üst çubuğun altına yerleşir)
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local area = Instance.new("Frame")
	area.Name = "Root"
	area.Size = UDim2.fromScale(1, 1)
	area.BackgroundTransparency = 1
	area.Parent = gui
	root = area

	local sprint = makeButton("Sprint", text("Mobile.Sprint"))
	sprint.Activated:Connect(function()
		local input = controllers.InputController
		input:Trigger("Sprint", not input:IsActionActive("Sprint"))
	end)
	sprint.Parent = area
	buttons.Sprint = sprint

	local cam = makeButton("Camera", CAMERA_LABELS[controllers.CameraController:GetMode()] or text("Mobile.Camera"))
	cam.Activated:Connect(function()
		controllers.InputController:Trigger("CameraCycle", true)
		controllers.InputController:Trigger("CameraCycle", false)
	end)
	cam.Parent = area
	buttons.Camera = cam

	buildPad(area)

	for _, def in VEHICLE_BUTTONS do
		local name, labelKey, action, hold, style = def[1], def[2], def[3], def[4], def[6]
		local radius = if style == "Gas" or style == "Brake" then 0.22 else 0.5
		local b = makeButton(name, if labelKey then text(labelKey) else "", radius)
		b.Visible = false
		if style == "ChevronL" or style == "ChevronR" then
			addChevron(b, style == "ChevronL")
		elseif style == "Gas" then
			b.BackgroundColor3 = UIConfig.Colors.Accent
			b.BackgroundTransparency = 0.35
		end
		if hold then
			b.InputBegan:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
					holdInputs[io] = action
					controllers.InputController:Trigger(action, true)
					setActiveLook(b, true)
				end
			end)
		else
			b.Activated:Connect(function()
				controllers.InputController:Trigger(action, true)
				controllers.InputController:Trigger(action, false)
			end)
		end
		b.Parent = area
		vehicleButtons[name] = b
	end

	-- Parmak butondan / pedden kayarak kalksa bile bırakılır
	UserInputService.InputChanged:Connect(function(io)
		local current = padInput
		if not current then
			return
		end
		if io == current or (current.UserInputType == Enum.UserInputType.MouseButton1 and io.UserInputType == Enum.UserInputType.MouseMovement) then
			updatePadFrom(io.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		local current = padInput
		if current and (io == current or (current.UserInputType == Enum.UserInputType.MouseButton1 and io.UserInputType == Enum.UserInputType.MouseButton1)) then
			releasePad()
		end
		local action = holdInputs[io]
		if action then
			holdInputs[io] = nil
			controllers.InputController:Trigger(action, false)
			for _, def in VEHICLE_BUTTONS do
				if def[3] == action and vehicleButtons[def[1]] then
					setActiveLook(vehicleButtons[def[1]], false)
				end
			end
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	screenGui = gui
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	Log.Info("Mobil kontroller oluşturuldu")
end

-- Roblox'un joystick/zıplama katmanı: yayayken açık, sürüşte ve menüde kapalı (sadece dokunmatikte)
local function applyRobloxTouchControls()
	if not controllers.InputController:IsTouch() then
		return
	end
	pcall(function()
		GuiService.TouchControlsEnabled = layoutName == "OnFoot"
	end)
end

local function refreshVisibility()
	local isTouch = controllers.InputController:IsTouch()
	if isTouch and not screenGui then
		build()
	end
	if screenGui then
		screenGui.Enabled = isTouch and layoutName ~= "Hidden"
		applyLayoutVisibility()
		layout()
	end
	applyRobloxTouchControls()
end

-- "OnFoot" | "Car" | "Motorcycle" | "Passenger" | "Hidden" (diyalog, menü)
function MobileControlsController:SetLayout(name: string)
	layoutName = name
	-- düzen değişince basılı kalan araç eylemlerini ve direksiyonu bırak
	releaseAllHolds()
	refreshVisibility()
end

function MobileControlsController:GetLayout(): string
	return layoutName
end

function MobileControlsController:Init(allControllers)
	controllers = allControllers
	local ok, strings = pcall(function()
		return require(script.Parent.Parent:WaitForChild("FrontEnd"):WaitForChild("Strings"))
	end)
	if ok then
		Strings = strings
	end
end

function MobileControlsController:Start()
	local input = controllers.InputController
	input.DeviceChanged:Connect(refreshVisibility)
	input.ActionBegan:Connect(function(action)
		if action == "Sprint" and buttons.Sprint then
			setActiveLook(buttons.Sprint, true)
		end
	end)
	input.ActionEnded:Connect(function(action)
		if action == "Sprint" and buttons.Sprint then
			setActiveLook(buttons.Sprint, false)
		end
	end)
	controllers.SettingsController.Changed:Connect(function(key)
		if key == "MobileButtonScale" or key == "MobileSteering" then
			releaseAllHolds()
			applyLayoutVisibility()
			layout()
		end
	end)
	controllers.CameraController.ModeChanged:Connect(function(mode)
		if buttons.Camera and CAMERA_LABELS[mode] then
			(buttons.Camera :: TextButton).Text = CAMERA_LABELS[mode]
		end
	end)
	-- Ölünce depar toggle'ı kapat
	controllers.CharacterController.CharacterChanged:Connect(function()
		if input:IsActionActive("Sprint") and input:IsTouch() then
			input:Trigger("Sprint", false)
		end
	end)
	refreshVisibility()
end

return MobileControlsController
