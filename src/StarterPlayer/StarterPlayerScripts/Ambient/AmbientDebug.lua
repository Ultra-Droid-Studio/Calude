-- AmbientDebug: trafik ve yaya yapay zekâsı için hata ayıklama görünümü (Aşama 6). F7 ile aç/kapa.
--
-- Çizer (oyuncunun çevresinde, AmbientConfig.Debug.DrawRadius):
--   * şerit merkezleri (mavi), kavşak bağlantı eğrileri (yeşil), durma çizgileri (ışık durumuna göre kırmızı/sarı/yeşil,
--     dur levhasında beyaz, yol ver'de turuncu)
--   * kaldırım yürüyüş çizgileri (beyaz) ve karşıya geçitler (yaya yeşilinde yeşil, değilse turuncu)
--   * her aracın üstünde durum etiketi (Sür / Kırmızı / Dur / Sıra / Çakışma / Dolu / Engel / SolDönüş / YolVer)
--   * her yayanın üstünde durum (Yürü / Bekle / Geç / Mola)
-- ve ekranda bir istatistik paneli (sayılar, havuz, adım süresi, doğurma/kaldırma, geçişler, takılanlar).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AmbientDebug = {}

local folder: Folder? = nil
local statics: Folder? = nil
local gui: ScreenGui? = nil
local label: TextLabel? = nil
local stopLines: { { Part: BasePart, Node: any, Phase: number, Control: string } } = {}
local crossings: { { Part: BasePart, Link: any } } = {}
local tags: { [any]: BillboardGui } = {}
local lastStaticFocus: Vector3? = nil

local STATE_COLOR = {
	["Sür"] = Color3.fromRGB(120, 230, 140), ["Kırmızı"] = Color3.fromRGB(255, 80, 70), ["Sarı"] = Color3.fromRGB(255, 200, 60),
	["Dur"] = Color3.fromRGB(255, 255, 255), ["Engel"] = Color3.fromRGB(255, 140, 40), ["Dolu"] = Color3.fromRGB(200, 120, 255),
	["Çakışma"] = Color3.fromRGB(255, 120, 200), ["Sıra"] = Color3.fromRGB(200, 200, 200), ["Sırada"] = Color3.fromRGB(170, 170, 170),
}

local function line(parent: Instance, a: Vector3, b: Vector3, color: Color3, thickness: number): Part?
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then
		return nil
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.25
	p.Size = Vector3.new(thickness, thickness, len)
	p.CFrame = CFrame.lookAt(a + d / 2, b)
	p.Parent = parent
	return p
end

local function ensure()
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "SolaraAmbientDebug"
	folder.Parent = Workspace
	gui = Instance.new("ScreenGui")
	gui.Name = "SolaraAmbientDebug"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 99
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(1, 0)
	l.Position = UDim2.new(1, -12, 0, 60)
	l.Size = UDim2.fromOffset(330, 250)
	l.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	l.BackgroundTransparency = 0.25
	l.TextColor3 = Color3.fromRGB(230, 235, 240)
	l.Font = Enum.Font.Code
	l.TextSize = 13
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.AutoLocalize = false
	l.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = l
	label = l
end

function AmbientDebug.Disable()
	if folder then
		folder:Destroy()
	end
	if gui then
		gui:Destroy()
	end
	folder, statics, gui, label = nil, nil, nil, nil
	table.clear(stopLines)
	table.clear(crossings)
	table.clear(tags)
	lastStaticFocus = nil
end

local function drawStatics(env, focus: Vector3, radius: number)
	if statics then
		statics:Destroy()
	end
	table.clear(stopLines)
	table.clear(crossings)
	local f = Instance.new("Folder")
	f.Name = "Static"
	f.Parent = folder
	statics = f
	local graph, TG = env.Graph, env.TG
	local r2 = radius * radius
	local lift = Vector3.new(0, 0.35, 0)
	for _, lane in TG.LanesNear(graph, focus.X, focus.Z, radius) do
		local a = Vector3.new(lane.X0, lane.Y0, lane.Z0) + lift
		local b = Vector3.new(lane.X1, lane.Y1, lane.Z1) + lift
		if (a - focus).Magnitude < radius * 1.5 or (b - focus).Magnitude < radius * 1.5 then
			line(f, a, b, Color3.fromRGB(70, 150, 255), 0.25)
			-- durma çizgisi
			local node = graph.Nodes[lane.To]
			if node.Control ~= "Free" then
				local x, y, z = TG.LanePoint(lane, lane.StopS)
				local c = Vector3.new(x, y, z) + lift
				local r = Vector3.new(lane.RX, 0, lane.RZ) * (lane.LaneWidth / 2)
				local part = line(f, c - r, c + r, Color3.new(1, 1, 1), 0.5)
				if part then
					table.insert(stopLines, { Part = part, Node = node, Phase = node.ArmPhase[lane.Edge] or 1, Control = node.Control })
				end
			end
		end
	end
	for _, node in graph.Nodes do
		local dx, dz = node.X - focus.X, node.Z - focus.Z
		if dx * dx + dz * dz < r2 * 0.4 then
			for _, c in node.Connectors do
				for i = 1, #c.PX - 1 do
					line(f, Vector3.new(c.PX[i], c.PY[i], c.PZ[i]) + lift, Vector3.new(c.PX[i + 1], c.PY[i + 1], c.PZ[i + 1]) + lift, Color3.fromRGB(80, 220, 120), 0.18)
				end
			end
		end
	end
	local pg = env.PedGraph
	if pg then
		for _, l in env.PG.LinksNear(pg, focus.X, focus.Z, radius) do
			local a = Vector3.new(l.A.X, pg.Top + 0.3, l.A.Z)
			local b = Vector3.new(l.B.X, pg.Top + 0.3, l.B.Z)
			line(f, a, b, Color3.fromRGB(235, 235, 235), 0.2)
		end
		for _, l in pg.Links do
			if l.Crossing then
				local dx, dz = l.A.X - focus.X, l.A.Z - focus.Z
				if dx * dx + dz * dz < r2 then
					local part = line(f, Vector3.new(l.A.X, pg.Top + 0.4, l.A.Z), Vector3.new(l.B.X, pg.Top + 0.4, l.B.Z), Color3.fromRGB(255, 150, 40), 0.45)
					if part then
						table.insert(crossings, { Part = part, Link = l })
					end
				end
			end
		end
	end
end

local function tag(agent, adornee: BasePart, text: string, color: Color3)
	local bb = tags[agent]
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 22)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "T"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Code
		t.TextSize = 13
		t.TextStrokeTransparency = 0.4
		t.AutoLocalize = false
		t.Parent = bb
		bb.Parent = folder
		tags[agent] = bb
	end
	bb.Adornee = adornee
	local t = bb:FindFirstChild("T") :: TextLabel
	t.Text = text
	t.TextColor3 = color
end

-- env: Graph, TG, PedGraph, PG, Traffic, Peds, VehicleModels, PedModels, Focus, Time, Stats (tablo), Config
function AmbientDebug.Update(env)
	ensure()
	local focus = env.Focus
	if not focus then
		return
	end
	local radius = env.Config.Debug.DrawRadius
	if not lastStaticFocus or (lastStaticFocus - focus).Magnitude > radius * 0.35 then
		lastStaticFocus = focus
		drawStatics(env, focus, radius)
	end
	local TG, graph = env.TG, env.Graph
	for _, s in stopLines do
		if s.Control == "Signal" then
			local state = TG.SignalState(graph, s.Node, s.Phase, env.Time)
			s.Part.Color = if state == "G" then Color3.fromRGB(60, 230, 110) elseif state == "Y" then Color3.fromRGB(255, 190, 40) else Color3.fromRGB(255, 50, 40)
		elseif s.Control == "Yield" then
			s.Part.Color = Color3.fromRGB(255, 150, 40)
		end
	end
	for _, c in crossings do
		local l = c.Link
		local node = graph.Nodes[l.Node]
		local walk = (not l.Signal) or (node and TG.WalkAllowed(graph, node, l.ArmPhase, env.Time, 0))
		c.Part.Color = if walk then Color3.fromRGB(60, 230, 110) else Color3.fromRGB(255, 150, 40)
	end
	-- etiketler
	local alive = {}
	for v, model in env.VehicleModels do
		if model.PrimaryPart then
			alive[v] = true
			tag(v, model.PrimaryPart, string.format("#%d %s %d", v.Id, v.State or "?", math.floor(v.V * 1.008 + 0.5)), STATE_COLOR[v.State] or Color3.fromRGB(255, 230, 120))
		end
	end
	for p, model in env.PedModels do
		if model.PrimaryPart then
			alive[p] = true
			tag(p, model.PrimaryPart, p.State or "?", Color3.fromRGB(200, 220, 255))
		end
	end
	for agent, bb in tags do
		if not alive[agent] then
			bb:Destroy()
			tags[agent] = nil
		end
	end
	if label then
		label.Text = env.Stats
	end
end

return AmbientDebug
