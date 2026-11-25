-- MapScreen: tam ekran harita ve hedef seçimi (Aşama 4). FrontEnd menüsünün bir ekranıdır (M tuşu,
-- menüdeki HARİTA butonu ya da köşe haritasına dokunma ile açılır).
--
-- Girişler:
--   Fare      sürükle = kaydır, tekerlek = imlecin altına yakınlaş, tıkla = hedef (simgeye tıklarsan o yer)
--   Dokunmatik sürükle = kaydır, iki parmak = yakınlaş, dokun = hedef
--   Klavye/gamepad  WASD / ok / sol çubuk = kaydır, Q E / LB RB = yakınlaş, Enter / A = artı işaretine hedef koy
-- Sağ panel: mevcut hedef, rota uzunluğu, "temizle", "konumuma dön" ve uzaklığa göre sıralı yerler listesi.
-- Harita bir kez çizilir (ilk açılışta); kaydırma/yakınlaştırma sadece konum/ölçek değiştirir.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontEnd = script.Parent.Parent
local Theme = require(FrontEnd.Theme)
local Widgets = require(FrontEnd.Widgets)
local Strings = require(FrontEnd.Strings)
local Focus = require(FrontEnd.Focus)
local MapCanvas = require(FrontEnd:WaitForChild("Map"):WaitForChild("MapCanvas"))
local MapDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapDefinitions"))

local C = Theme.Colors
local new = Widgets.new

local MapScreen = {}
MapScreen.__index = MapScreen

local PANEL_WIDTH = 330
local MIN_ZOOM, MAX_ZOOM = 0.03, 1.2
local PAN_STEP = 60 -- tasarım pikseli / tuş tekrarı

-- ctx: Parent, GetScale, OnMove, Back, Navigation (NavigationController), IsTouch () -> boolean
function MapScreen.new(ctx)
	local self = setmetatable({}, MapScreen)
	self._ctx = ctx
	self._nav = ctx.Navigation
	self.Focus = Focus.new(ctx.GetScale, ctx.OnMove)
	self.Focus:SetItems({})
	self._zoom = 0.15
	self._cx, self._cz = 0, 0
	self._canvas = nil

	self.Root = new("Frame", { Name = "MapScreen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = ctx.Parent })

	-- Harita görünümü
	self._view = new("Frame", {
		Name = "MapView",
		Position = UDim2.fromOffset(24, 20),
		Size = UDim2.new(1, -(PANEL_WIDTH + 64), 1, -76),
		BackgroundColor3 = C.Background,
		ClipsDescendants = true,
		Active = true,
		Parent = self.Root,
	}, { Widgets.Stroke(C.White, 0.85) })
	self._crosshair = new("Frame", {
		Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1, ZIndex = 20, Parent = self._view,
	}, { Widgets.Round(), Widgets.Stroke(C.White, 0.1, 2) })
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 21, Parent = self._crosshair }, { Widgets.Round() })

	-- Sağ panel
	local panel = Widgets.Panel({ Name = "Panel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 20), Size = UDim2.new(0, PANEL_WIDTH, 1, -76), Parent = self.Root })
	Widgets.Padding(18, 18, 16, 16).Parent = panel
	Widgets.Label({ Text = Strings.Get("Map.Title"), FontFace = Theme.Fonts.Display, TextSize = Theme.Text.Heading, Size = UDim2.new(1, -110, 0, 36), Parent = panel })
	Widgets.SmallButton(panel, { Name = "Back", Text = "‹  " .. Strings.Get("Settings.Back"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), OnActivate = ctx.Back })

	self._destName = Widgets.Label({ FontFace = Theme.Fonts.Title, TextSize = Theme.Text.Body, Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, Parent = panel })
	self._destInfo = Widgets.Label({ FontFace = Theme.Fonts.Light, TextSize = Theme.Text.Small, TextColor3 = C.TextMuted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 36), Parent = panel })
	local buttons = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 36), Parent = panel }, { Widgets.List(8, true) })
	Widgets.SmallButton(buttons, { Text = Strings.Get("Map.Clear"), LayoutOrder = 1, OnActivate = function()
		self._nav:ClearDestination()
	end })
	Widgets.SmallButton(buttons, { Text = Strings.Get("Map.Recenter"), LayoutOrder = 2, OnActivate = function()
		self:_recenter()
	end })
	Widgets.SectionLabel(panel, Strings.Get("Map.Places"), 0, false).Position = UDim2.fromOffset(0, 160)
	self._list = new("ScrollingFrame", {
		Name = "Places", Position = UDim2.fromOffset(0, 186), Size = UDim2.new(1, 0, 1, -186), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageTransparency = 0.6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Selectable = false, Parent = panel,
	}, { Widgets.List(4) })

	self:_connectInput()
	self._nav.RouteChanged:Connect(function()
		self:_refreshCard()
		if self._canvas then
			self._canvas:SetRoute(self._nav:GetRoute())
		end
	end)
	self._nav.DestinationChanged:Connect(function(destination)
		self:_refreshCard()
		if self._canvas then
			self._canvas:SetDestination(destination and destination.Position)
		end
	end)
	return self
end

-- ===== Yardımcılar =====
function MapScreen:_viewport(): Vector2
	local s = math.max(self._ctx.GetScale(), 0.01)
	return self._view.AbsoluteSize / s -- MapCanvas birimleri FrontEnd tuvalinin (UIScale öncesi) birimleridir
end

function MapScreen:_apply()
	if self._canvas then
		self._canvas:SetView(self._cx, self._cz, self._zoom, self:_viewport())
	end
end

function MapScreen:_recenter()
	local subject = self._nav:GetSubject()
	if subject then
		self._cx, self._cz = subject.Position.X, subject.Position.Z
	end
	self:_apply()
end

function MapScreen:_zoomAt(factor: number, localPoint: Vector2?)
	local viewport = self:_viewport()
	local point = localPoint or viewport / 2
	local wx, wz = self._canvas:ViewToWorld(point, self._cx, self._cz, viewport)
	self._zoom = math.clamp(self._zoom * factor, MIN_ZOOM, MAX_ZOOM)
	-- imlecin altındaki dünya noktası yerinde kalsın
	self._cx = wx - (point.X - viewport.X / 2) / self._zoom
	self._cz = wz - (point.Y - viewport.Y / 2) / self._zoom
	self:_apply()
end

function MapScreen:_selectAt(localPoint: Vector2)
	local viewport = self:_viewport()
	local x, z = self._canvas:ViewToWorld(localPoint, self._cx, self._cz, viewport)
	local poi = self._canvas:POINear(x, z, 16)
	if poi then
		self._nav:SetDestinationPOI(poi.Id)
	else
		self._nav:SetWaypoint(x, z)
	end
end

function MapScreen:_localFromScreen(screen: Vector3 | Vector2): Vector2
	local s = math.max(self._ctx.GetScale(), 0.01)
	local p = Vector2.new(screen.X, screen.Y) - self._view.AbsolutePosition
	return p / s
end

function MapScreen:_refreshCard()
	local destination = self._nav:GetDestination()
	local route = self._nav:GetRoute()
	local status = self._nav:GetStatus()
	if not destination then
		self._destName.Text = Strings.Get("Map.Title")
		self._destInfo.Text = Strings.Get(if status == "Arrived" then "Map.Arrived" else "Map.NoDestination")
		return
	end
	self._destName.Text = destination.Name or Strings.Get("Map.Waypoint")
	if route then
		local info = Strings.Get("Map.Route", Strings.Distance(route.Length))
		if route.Offroad then
			local last = route.Points[#route.Points]
			local gap = math.sqrt((route.Destination.X - last.X) ^ 2 + (route.Destination.Z - last.Z) ^ 2)
			info ..= "  ·  " .. Strings.Get("Map.Offroad", Strings.Distance(gap))
		end
		self._destInfo.Text = info
	elseif status == "NoRoadNearStart" then
		self._destInfo.Text = Strings.Get("Map.NoRoad")
	else
		self._destInfo.Text = Strings.Get("Map.Unreachable")
	end
end

-- Yerler listesi: oyuncuya uzaklığa göre (her açılışta yeniden sıralanır)
function MapScreen:_buildList()
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local subject = self._nav:GetSubject()
	local origin = if subject then subject.Position else Vector3.zero
	local entries = {}
	for _, poi in MapDefinitions.GetPOIs() do
		local d = (Vector3.new(poi.Entrance.X, 0, poi.Entrance.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude
		table.insert(entries, { Poi = poi, Distance = d })
	end
	table.sort(entries, function(a, b)
		return a.Distance < b.Distance
	end)
	for i, entry in entries do
		local poi = entry.Poi
		local category = MapCanvas.POICategory[poi.Type] or "Landmark"
		local row = Widgets.HitButton({ Name = poi.Id, Size = UDim2.new(1, -8, 0, 40), BackgroundColor3 = C.SurfaceHigh, BackgroundTransparency = 0.6, LayoutOrder = i, Parent = self._list })
		Widgets.Corner(8).Parent = row
		new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = MapCanvas.CategoryColor[category], BorderSizePixel = 0, Parent = row }, { Widgets.Round() })
		Widgets.Label({ Text = poi.Name, FontFace = Theme.Fonts.Body, TextSize = Theme.Text.Small, Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -100, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Widgets.Label({ Text = Strings.Distance(entry.Distance), FontFace = Theme.Fonts.Mono, TextSize = Theme.Text.Tiny, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(70, 40), Parent = row })
		row.Activated:Connect(function()
			self._nav:SetDestinationPOI(poi.Id)
			self._cx, self._cz = poi.Entrance.X, poi.Entrance.Z
			self:_apply()
		end)
	end
end

-- ===== Giriş =====
function MapScreen:_connectInput()
	local drag = nil -- { Input, Start (Vector2 ekran), Cx, Cz, Moved }
	self._view.InputBegan:Connect(function(io)
		if not self.Root.Visible or not self._canvas then
			return
		end
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			if drag == nil then
				drag = { Input = io, Start = Vector2.new(io.Position.X, io.Position.Y), Cx = self._cx, Cz = self._cz, Moved = false }
			end
		end
	end)
	self._view.InputChanged:Connect(function(io)
		if self.Root.Visible and self._canvas and io.UserInputType == Enum.UserInputType.MouseWheel then
			self:_zoomAt(if io.Position.Z > 0 then 1.2 else 1 / 1.2, self:_localFromScreen(io.Position))
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if not drag then
			return
		end
		local mouse = drag.Input.UserInputType == Enum.UserInputType.MouseButton1 and io.UserInputType == Enum.UserInputType.MouseMovement
		if mouse or io == drag.Input then
			local delta = Vector2.new(io.Position.X, io.Position.Y) - drag.Start
			if delta.Magnitude > 6 then
				drag.Moved = true
			end
			local s = math.max(self._ctx.GetScale(), 0.01)
			self._cx = drag.Cx - delta.X / s / self._zoom
			self._cz = drag.Cz - delta.Y / s / self._zoom
			self:_apply()
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if not drag then
			return
		end
		local mouse = drag.Input.UserInputType == Enum.UserInputType.MouseButton1 and io.UserInputType == Enum.UserInputType.MouseButton1
		if mouse or io == drag.Input then
			local finished = drag
			drag = nil
			if not finished.Moved and self.Root.Visible then
				self:_selectAt(self:_localFromScreen(io.Position))
				self._ctx.OnMove()
			end
		end
	end)
	local lastPinch = nil
	UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if not self.Root.Visible or not self._canvas then
			return
		end
		if state == Enum.UserInputState.Begin then
			lastPinch = scale
			drag = nil -- iki parmak: kaydırma iptal
		elseif state == Enum.UserInputState.Change and lastPinch then
			self:_zoomAt(scale / math.max(lastPinch, 0.01))
			lastPinch = scale
		else
			lastPinch = nil
		end
	end)
end

-- FrontEnd MenuInput kancaları (klavye/gamepad)
function MapScreen:HandleNavigate(kind: string, dir: number): boolean
	if not self._canvas then
		return true
	end
	local step = PAN_STEP / self._zoom
	if kind == "Move" then
		self._cz += dir * step
	else
		self._cx += dir * step
	end
	self:_apply()
	return true
end

function MapScreen:HandleAccept(): boolean
	if self._canvas then
		self:_selectAt(self:_viewport() / 2)
	end
	return true
end

function MapScreen:HandleTab(dir: number): boolean
	if self._canvas then
		self:_zoomAt(if dir > 0 then 1.35 else 1 / 1.35)
	end
	return true
end

function MapScreen:SetCompact(compact: boolean)
	-- dar ekranda panel daha dar
	local width = if compact then 270 else PANEL_WIDTH
	self._view.Size = UDim2.new(1, -(width + 64), 1, -76)
	local panel = self.Root:FindFirstChild("Panel")
	if panel then
		(panel :: Frame).Size = UDim2.new(0, width, 1, -76)
	end
end

function MapScreen:OnShow()
	if not self._canvas then
		self._canvas = MapCanvas.new(self._view, { Detail = "Full" }) -- ilk açılışta bir kez çizilir
		self._canvas.Root.ZIndex = 1
		self._canvas:SetRoute(self._nav:GetRoute())
		local destination = self._nav:GetDestination()
		self._canvas:SetDestination(destination and destination.Position)
	end
	self._crosshair.Visible = not self._ctx.IsTouch()
	self:_buildList()
	self:_refreshCard()
	self:_recenter()
	if self._render then
		self._render:Disconnect()
	end
	self._render = RunService.RenderStepped:Connect(function()
		local subject = self._nav:GetSubject()
		if subject and self._canvas then
			self._canvas:SetPlayer(subject.Position.X, subject.Position.Z, self._nav:GetHeading())
		end
	end)
	self.Focus:Refresh()
end

function MapScreen:OnHide()
	if self._render then
		self._render:Disconnect()
		self._render = nil
	end
end

return MapScreen
