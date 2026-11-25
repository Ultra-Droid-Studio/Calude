-- MinimapController: köşe haritası + yönlendirme paneli (Aşama 4).
--
-- Yerleşim DrivingLayout'tan: masaüstü sol alt (harita) + hemen üstünde yönlendirme; dokunmatik sol üst +
-- altında yönlendirme. Sürüş HUD'u ve mobil butonlar aynı hesaptan beslendiği için çakışmazlar.
-- Harita kuzey-yukarıdır; oyuncu oku ortada sabit, yönü döner. Kare başına yazılan: harita konumu, ok açısı.
-- Yakınlaştırma yürürken sabit, araçta hızla açılır (≈300 → ≈800 stud yarıçap).
-- Sadece oyun sırasında görünür (ana menüde gizli). Dokununca/tıklayınca tam harita açılır.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DrivingLayout = require(Modules:WaitForChild("DrivingLayout"))

local FrontEnd = script.Parent.Parent:WaitForChild("FrontEnd")
local Theme = require(FrontEnd:WaitForChild("Theme"))
local Strings = require(FrontEnd:WaitForChild("Strings"))
local MapCanvas = require(FrontEnd:WaitForChild("Map"):WaitForChild("MapCanvas"))

local MinimapController = {
	Name = "MinimapController",
	Priority = 13, -- FrontEnd (11) ve Navigation (7) sonrası
}

local C = Theme.Colors
local player = Players.LocalPlayer
local controllers

local SCALE_ON_FOOT = 0.34 -- piksel/stud (temel boyutlu harita için; harita boyutuna göre ölçeklenir)
local SCALE_SLOW = 0.22
local SCALE_FAST = 0.12
local REFERENCE_SIZE = 200 -- yukarıdaki ölçekler bu piksel çaplı harita içindir

local gui: ScreenGui
local root: Frame
local clip: Frame
local canvas
local arrow: Frame
local northTag: TextLabel
local openButton: TextButton
local guide: Frame
local guideIcon: Frame
local guideDistance: TextLabel
local guideText: TextLabel
local guideSub: TextLabel
local currentScale = SCALE_ON_FOOT
local accumulator = 0
local guideAccumulator = 0

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

-- Manevra oku: gövde + uç; dönüş açısı kadar döndürülür. Varış = halka.
local function buildGuideIcon(parent: Instance): Frame
	local holder = new("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeYY, Parent = parent })
	local arrowFrame = new("Frame", { Name = "Arrow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), Parent = holder })
	new("Frame", { Name = "Shaft", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromScale(0.16, 0.62), BackgroundColor3 = C.AccentAlt, BorderSizePixel = 0, Parent = arrowFrame })
	for _, sign in { -1, 1 } do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + sign * 0.14, 0.24),
			Size = UDim2.fromScale(0.16, 0.42),
			Rotation = sign * 40,
			BackgroundColor3 = C.AccentAlt,
			BorderSizePixel = 0,
			Parent = arrowFrame,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bar })
	end
	local ring = new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6), BackgroundTransparency = 1, Visible = false, Parent = holder })
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	new("UIStroke", { Color = C.AccentAlt, Thickness = 4, Parent = ring })
	return holder
end

local MANEUVER_TEXT = {
	Left = "Nav.Left", Right = "Nav.Right", SlightLeft = "Nav.SlightLeft", SlightRight = "Nav.SlightRight",
	UTurn = "Nav.UTurn", Continue = "Nav.Continue", Arrive = "Nav.Arrive",
}

local function build()
	gui = new("ScreenGui", {
		Name = "SolaraMinimap",
		ResetOnSpawn = false,
		DisplayOrder = 7, -- araç HUD'unun (6) üstünde, menünün (50) altında
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	})
	root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })

	-- Harita çerçevesi (Hata düzeltme 4 + 5): sabit kare alan, ClipsDescendants'lı SIRADAN Frame. CanvasGroup
	-- kullanılmaz (düşük bellekte kırpamayıp 10240²'lik koyu tuvali ekrana yayıyordu); harita tuvalinde döndürülmüş
	-- öğe yok, bu yüzden bu kırpma her cihazda tam çalışır. Görünür kenarlık = "Ring" (aynı dikdörtgen).
	-- Köşeler bilerek düz: ClipsDescendants UICorner'a uymaz, yuvarlak köşede harita dışarı taşardı.
	clip = new("Frame", {
		Name = "Minimap", BackgroundColor3 = MapCanvas.LandColor, BackgroundTransparency = 0,
		ClipsDescendants = true, Parent = root,
	})
	canvas = MapCanvas.new(clip, { Detail = "Mini" })
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, ZIndex = 4, Parent = root })
	new("UIStroke", { Color = C.White, Transparency = 0.35, Thickness = 2, Parent = ring })
	arrow = MapCanvas.MakeArrow(root, 5)
	northTag = new("TextLabel", {
		Name = "North", BackgroundColor3 = C.Background, BackgroundTransparency = 0.2, Text = "N", TextScaled = true,
		FontFace = Theme.Fonts.Title, TextColor3 = C.Accent, AutoLocalize = false, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5, Parent = root,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = northTag })
	openButton = new("TextButton", { Name = "Open", Text = "", BackgroundTransparency = 1, AutoButtonColor = false, ZIndex = 6, Parent = root })
	openButton.Activated:Connect(function()
		local frontEnd = controllers.FrontEndController
		if frontEnd and frontEnd.OpenMap then
			frontEnd:OpenMap()
		end
	end)

	-- Yönlendirme paneli
	guide = new("Frame", { Name = "Guidance", BackgroundColor3 = C.Background, BackgroundTransparency = 0.15, Visible = false, ZIndex = 10, Parent = root })
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = guide })
	new("UIStroke", { Color = C.AccentAlt, Transparency = 0.55, Thickness = 1.5, Parent = guide })
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = guide })
	guideIcon = buildGuideIcon(guide)
	guideDistance = new("TextLabel", {
		Name = "Distance", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0.5, 0),
		TextScaled = true, FontFace = Theme.Fonts.Display, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, AutoLocalize = false, Parent = guide,
	})
	guideText = new("TextLabel", {
		Name = "Instruction", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.28, 0),
		TextScaled = true, FontFace = Theme.Fonts.Body, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, AutoLocalize = false, Parent = guide,
	})
	guideSub = new("TextLabel", {
		Name = "Remaining", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.22, 0),
		TextScaled = true, FontFace = Theme.Fonts.Light, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Right, AutoLocalize = false, Parent = guide,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
	return ring
end

local ringFrame: Frame

local function place(target: GuiObject, r)
	target.Position = UDim2.fromOffset(r.X, r.Y)
	target.Size = UDim2.fromOffset(r.W, r.H)
end

local function layout()
	local area = root.AbsoluteSize
	if area.X < 10 then
		return
	end
	local rects
	if controllers.InputController:IsTouch() then
		local scale = controllers.SettingsController:Get("MobileButtonScale") or 1
		local base = DrivingLayout.ButtonSize(area.X, area.Y, scale)
		local vehicle = controllers.VehicleController:GetCurrent()
		local kind = if vehicle then (if not vehicle.IsDriver then "Passenger" elseif vehicle.IsBike then "Motorcycle" else "Car") else "Car"
		rects = DrivingLayout.Touch(area.X, area.Y, base, { Kind = kind, Steering = controllers.SettingsController:Get("MobileSteering") })
	else
		rects = DrivingLayout.Desktop(area.X, area.Y)
	end
	local m = rects.Minimap
	place(clip, m)
	place(ringFrame, m)
	place(openButton, m)
	local arrowSize = math.floor(math.clamp(m.W * 0.13, 14, 28))
	arrow.Position = UDim2.fromOffset(m.X + m.W / 2, m.Y + m.H / 2)
	arrow.Size = UDim2.fromOffset(arrowSize, arrowSize)
	local tag = math.floor(math.clamp(m.W * 0.12, 14, 24))
	northTag.Position = UDim2.fromOffset(m.X + m.W / 2, m.Y + tag / 2 + 3) -- çerçevenin içinde
	northTag.Size = UDim2.fromOffset(tag, tag)
	local g = rects.Guidance
	place(guide, g)
	-- panel içi: sol kare ikon, sağda metin
	local iconW = g.H - 8
	guideDistance.Position = UDim2.fromOffset(iconW + 6, 0)
	guideDistance.Size = UDim2.new(0.55, -(iconW + 6), 0.48, 0) -- sağdaki kalan-mesafe yazısıyla çakışmasın
	guideText.Position = UDim2.new(0, iconW + 6, 0.5, 0)
	guideText.Size = UDim2.new(1, -(iconW + 6), 0.3, 0)
	guideSub.Position = UDim2.new(0, 0, 0.04, 0)
	guideSub.Size = UDim2.new(1, 0, 0.3, 0)
end

local function shouldShow(): boolean
	local frontEnd = controllers.FrontEndController
	return frontEnd == nil or frontEnd:GetState() == "Playing"
end

local function updateGuidance()
	local navigation = controllers.NavigationController
	local route = navigation:GetRoute()
	local progress = navigation:GetProgress()
	local status = navigation:GetStatus()
	local destination = navigation:GetDestination()
	if not destination then
		guide.Visible = false
		return
	end
	guide.Visible = true
	local arrowFrame = guideIcon:FindFirstChild("Arrow") :: Frame
	local ringIcon = guideIcon:FindFirstChild("Ring") :: Frame
	if not route or not progress then
		arrowFrame.Visible, ringIcon.Visible = false, true
		guideDistance.Text = "—"
		guideText.Text = Strings.Get(if status == "NoRoadNearStart" then "Map.NoRoad" else "Map.Unreachable")
		guideSub.Text = ""
		return
	end
	local nextManeuver = progress.Next
	local arriving = nextManeuver.Type == "Arrive"
	arrowFrame.Visible, ringIcon.Visible = not arriving, arriving
	if not arriving then
		arrowFrame.Rotation = math.clamp(nextManeuver.Angle, -150, 150)
		if nextManeuver.Type == "UTurn" then
			arrowFrame.Rotation = 180
		end
	end
	guideDistance.Text = Strings.Distance(progress.NextDistance)
	if navigation:IsRerouting() then
		guideText.Text = Strings.Get("Nav.Rerouting")
	elseif arriving and route.Offroad then
		local destinationPos = route.Destination
		local last = route.Points[#route.Points]
		local gap = math.sqrt((destinationPos.X - last.X) ^ 2 + (destinationPos.Z - last.Z) ^ 2)
		guideText.Text = Strings.Get("Nav.OffroadEnd", Strings.Distance(gap))
	else
		local text = Strings.Get(MANEUVER_TEXT[nextManeuver.Type] or "Nav.Continue")
		if nextManeuver.Street ~= "" and not arriving then
			text ..= " · " .. nextManeuver.Street
		elseif arriving and destination.Name then
			text ..= " · " .. destination.Name
		end
		guideText.Text = text
	end
	guideSub.Text = Strings.Get("Nav.Remaining", Strings.Distance(progress.Remaining))
end

local function step(dt: number)
	local show = shouldShow()
	if gui.Enabled ~= show then
		gui.Enabled = show
	end
	if not show then
		return
	end
	local navigation = controllers.NavigationController
	local subject = navigation:GetSubject()
	if not subject then
		return
	end
	-- Yakınlaştırma: yürürken sabit; araçta hızla uzaklaş
	local target = SCALE_ON_FOOT
	local vehicle = controllers.VehicleController:GetCurrent()
	if vehicle then
		local speedFrac = math.clamp(subject.AssemblyLinearVelocity.Magnitude / math.max(vehicle.Def.MaxSpeed, 1), 0, 1)
		target = SCALE_SLOW + (SCALE_FAST - SCALE_SLOW) * speedFrac
	end
	currentScale += (target - currentScale) * math.clamp(dt * 1.5, 0, 1)
	local size = clip.AbsoluteSize
	local scale = currentScale * (size.X / REFERENCE_SIZE)
	local position = subject.Position
	canvas:SetView(position.X, position.Z, scale, size)
	arrow.Rotation = navigation:GetHeading()
end

function MinimapController:Init(allControllers)
	controllers = allControllers
end

function MinimapController:Start()
	ringFrame = build()
	layout()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	controllers.InputController.DeviceChanged:Connect(layout)
	controllers.SettingsController.Changed:Connect(function(key)
		if key == "MobileButtonScale" or key == "MobileSteering" then
			layout()
		end
	end)
	controllers.VehicleController.Entered:Connect(layout)
	controllers.VehicleController.Exited:Connect(layout)

	local navigation = controllers.NavigationController
	navigation.RouteChanged:Connect(function(route)
		canvas:SetRoute(route)
		updateGuidance()
	end)
	navigation.DestinationChanged:Connect(function(destination)
		canvas:SetDestination(destination and destination.Position)
		updateGuidance()
	end)

	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		guideAccumulator += dt
		if accumulator >= 1 / 30 then
			local ok, err = pcall(step, accumulator)
			accumulator = 0
			if not ok then
				warn("[Minimap]", err)
			end
		end
		if guideAccumulator >= 0.2 then
			guideAccumulator = 0
			if gui.Enabled then
				pcall(updateGuidance)
			end
		end
	end)
end

return MinimapController
