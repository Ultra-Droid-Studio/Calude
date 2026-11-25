-- SignalRenderer: ışıklı kavşaklarda görünür trafik ışıkları (Aşama 6). Sadece bu istemcide, yakın kavşaklarda.
--
-- Harita verisinde 211 ışıklı kavşak var ama dünyada ışık direği yok; NPC'ler ışığa uyduğu için oyuncunun da
-- ışığı görmesi gerekir. Her yaklaşım kolunun sağ kaldırım köşesine, durma çizgisi hizasına bir direk konur.
-- Işık durumu TrafficGraph.SignalState'ten (sunucu saati) gelir → tüm oyuncularda aynı. Direkler havuzdan.

local Workspace = game:GetService("Workspace")

local SignalRenderer = {}

local RED = Color3.fromRGB(255, 50, 40)
local YELLOW = Color3.fromRGB(255, 190, 40)
local GREEN = Color3.fromRGB(60, 230, 110)
local OFF = Color3.fromRGB(40, 40, 44)
local POLE = Color3.fromRGB(58, 62, 68)

local folder: Folder
local pool: { Model } = {}
local active: { [string]: { Model: Model, Node: any, Phase: number, State: string? } } = {}
local approaches: { any } = {} -- { Key, Node, Phase, Position, Look }
local TG

local function build(): Model
	local model = Instance.new("Model")
	model.Name = "TrafficLight"
	local function p(name: string, size: Vector3, color: Color3, material: Enum.Material?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = name == "Pole"
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = name == "Pole"
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end
	local pole = p("Pole", Vector3.new(0.6, 12, 0.6), POLE)
	model.PrimaryPart = pole
	p("Head", Vector3.new(1.4, 3.6, 1), Color3.fromRGB(24, 26, 30))
	p("Red", Vector3.new(0.9, 0.9, 0.2), OFF, Enum.Material.Neon)
	p("Yellow", Vector3.new(0.9, 0.9, 0.2), OFF, Enum.Material.Neon)
	p("Green", Vector3.new(0.9, 0.9, 0.2), OFF, Enum.Material.Neon)
	return model
end

local function place(model: Model, position: Vector3, look: Vector3)
	-- yer: direk tabanı; ışık başı direğin tepesinde, yaklaşan trafiğe bakar
	local base = CFrame.lookAt(position, position + look)
	local parts = model:GetChildren()
	for _, part in parts do
		if part:IsA("BasePart") then
			if part.Name == "Pole" then
				part.CFrame = base * CFrame.new(0, 6, 0)
			elseif part.Name == "Head" then
				part.CFrame = base * CFrame.new(0, 10.4, -0.2)
			elseif part.Name == "Red" then
				part.CFrame = base * CFrame.new(0, 11.5, -0.75)
			elseif part.Name == "Yellow" then
				part.CFrame = base * CFrame.new(0, 10.4, -0.75)
			elseif part.Name == "Green" then
				part.CFrame = base * CFrame.new(0, 9.3, -0.75)
			end
		end
	end
end

local function setState(model: Model, state: string)
	for _, name in { "Red", "Yellow", "Green" } do
		local part = model:FindFirstChild(name) :: BasePart
		local on = (name == "Red" and state == "R") or (name == "Yellow" and state == "Y") or (name == "Green" and state == "G")
		part.Color = if on then (if name == "Red" then RED elseif name == "Yellow" then YELLOW else GREEN) else OFF
	end
end

-- graph: TrafficGraph sonucu; trafficGraphModule: TrafficGraph (SignalState)
function SignalRenderer.Init(graph, trafficGraphModule)
	TG = trafficGraphModule
	folder = Instance.new("Folder")
	folder.Name = "SolaraTrafficLights"
	folder.Parent = Workspace
	-- yaklaşım kolları: her ışıklı düğümde, düğüme giren şerit grubunun kaldırım tarafı
	for _, node in graph.Nodes do
		if node.Control == "Signal" then
			local seen = {}
			for _, lane in node.InLanes do
				local group = lane.Group
				if not seen[group] then
					seen[group] = true
					local curb = group[#group]
					local s = curb.StopS
					local t = s / math.max(curb.Length, 0.1)
					local x = curb.X0 + (curb.X1 - curb.X0) * t + curb.RX * (curb.LaneWidth / 2 + 2.5)
					local z = curb.Z0 + (curb.Z1 - curb.Z0) * t + curb.RZ * (curb.LaneWidth / 2 + 2.5)
					local y = graph.Meta.BlockTop or 0.8
					if curb.Y1 > 2 then
						y = curb.Y1 -- yükseltilmiş yol (nadiren)
					end
					table.insert(approaches, {
						Key = node.Id .. ":" .. lane.Edge .. ":" .. lane.From,
						Node = node,
						Phase = node.ArmPhase[lane.Edge] or 1,
						Position = Vector3.new(x, y, z),
						Look = Vector3.new(-curb.UX, 0, -curb.UZ),
					})
				end
			end
		end
	end
end

-- Yakındaki direkleri görünür yap, uzaklaşanları havuza ver; ışık durumlarını güncelle
function SignalRenderer.Update(graph, focus: Vector3?, time: number, radius: number)
	if not focus then
		for key, entry in active do
			entry.Model.Parent = nil
			table.insert(pool, entry.Model)
			active[key] = nil
		end
		return
	end
	local r2 = radius * radius
	local keep = {}
	for _, a in approaches do
		local d = a.Position - focus
		if d.X * d.X + d.Z * d.Z < r2 then
			keep[a.Key] = a
		end
	end
	for key, entry in active do
		if not keep[key] then
			entry.Model.Parent = nil
			table.insert(pool, entry.Model)
			active[key] = nil
		end
	end
	for key, a in keep do
		local entry = active[key]
		if not entry then
			local model = table.remove(pool) or build()
			-- direk tabanı: zemine ışınla otur (kaldırım varsa kaldırım, yoksa zemin)
			if not a.Grounded then
				a.Grounded = true
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { folder }
				local hit = Workspace:Raycast(a.Position + Vector3.new(0, 15, 0), Vector3.new(0, -40, 0), params)
				if hit then
					a.Position = Vector3.new(a.Position.X, hit.Position.Y, a.Position.Z)
				end
			end
			place(model, a.Position, a.Look)
			model.Parent = folder
			entry = { Model = model, Node = a.Node, Phase = a.Phase, State = nil }
			active[key] = entry
		end
		local state = TG.SignalState(graph, entry.Node, entry.Phase, time)
		if state ~= entry.State then
			entry.State = state
			setState(entry.Model, state)
		end
	end
end

function SignalRenderer.ActiveCount(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

return SignalRenderer
