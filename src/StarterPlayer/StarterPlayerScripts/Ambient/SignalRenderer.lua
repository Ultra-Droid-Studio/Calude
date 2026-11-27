-- SignalRenderer: ışıklı kavşaklarda görünür trafik ışıkları (Aşama 6). Sadece bu istemcide, yakın kavşaklarda.
--
-- Harita verisinde 211 ışıklı kavşak var ama dünyada ışık direği yok; NPC'ler ışığa uyduğu için oyuncunun da
-- ışığı görmesi gerekir. Her yaklaşım kolunun sağ kaldırım köşesine, durma çizgisi hizasına bir direk konur.
-- Işık durumu TrafficGraph.SignalState'ten (sunucu saati) gelir → tüm oyuncularda aynı. Direkler havuzdan.
--
-- 3D model (kullanıcının verdiği Kenney trafik ışıkları, CC0; tools/trafficlights_convert.py): sunucu
-- ReplicatedStorage.TrafficLightModels'a koyar (ModelAssetService). Üç tip: A (tek direk), B (direk + sokak lambası,
-- gece yanar), C (yola uzanan kollu direk; çok şeritli yollarda). Yanan camlar Red/Yellow/Green adlı parçalardır.
-- Parçalar adlarından bulunur (TL_<Tip>_<Rol>_<rrggbb>) ve TrafficLightData'daki üç noktayla (direk, kırmızı cam,
-- yeşil cam) kalibre edilir: içe aktarıcının ölçeği, konumu ve dönüşü önemli değil. Model yoksa eski kutu direk.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local TrafficLightData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TrafficLightData"))

local SignalRenderer = {}

local RED = Color3.fromRGB(255, 50, 40)
local YELLOW = Color3.fromRGB(255, 190, 40)
local GREEN = Color3.fromRGB(60, 230, 110)
local OFF = Color3.fromRGB(40, 40, 44)
local POLE = Color3.fromRGB(58, 62, 68)
local LAMP_NIGHT = Color3.fromRGB(255, 226, 160)
local MODEL_FOLDER = "TrafficLightModels"
local LENS_ON = { Red = RED, Yellow = YELLOW, Green = GREEN }

local folder: Folder
local pools: { [string]: { Model } } = {} -- tip ("A" / "B" / "C" / "Box") → boştaki direkler
local active: { [string]: { Model: Model, Kind: string, Node: any, Phase: number, State: string? } } = {}
local approaches: { any } = {} -- { Key, Node, Phase, Position, Look, Wide, Hash }
local TG
local templates: { [string]: { any } }? = nil
local warned = false

local function v3(t): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Üç noktadan (direk ortası p, kırmızı cam r, yeşil cam g) dönüş: Y = yukarı (yeşilden kırmızıya), X = camdan direğe
-- (yatay bileşen)
local function axes(p: Vector3, r: Vector3, g: Vector3): CFrame
	local up = (r - g).Unit
	local h = p - r
	h = (h - up * h:Dot(up)).Unit
	return CFrame.fromMatrix(Vector3.zero, h, up)
end

-- İçe aktarılan şablonları bul ve kalibre et (bir kez; klasör yoksa / hazır değilse sonra yine denenir)
local function loadTemplates()
	if templates then
		return templates
	end
	local source = ReplicatedStorage:FindFirstChild(MODEL_FOLDER)
	if not source or source:GetAttribute("Ready") == false then
		return nil
	end
	local found = {}
	for _, d in source:GetDescendants() do
		if d:IsA("BasePart") then
			local kind, role, hex = string.match(d.Name, "^TL_(%u)_(%a+)_(%x%x%x%x%x%x)")
			if kind and TrafficLightData.Types[kind] then
				found[kind] = found[kind] or {}
				table.insert(found[kind], { Part = d, Role = role, Color = Color3.fromHex(hex) })
			end
		end
	end
	local result = {}
	for kind, list in found do
		local data = TrafficLightData.Types[kind]
		local byRole = {}
		for _, e in list do
			byRole[e.Role] = byRole[e.Role] or e.Part
		end
		if byRole.Pole and byRole.Red and byRole.Green then
			local pm, rm, gm = v3(data.PoleCenter), v3(data.RedCenter), v3(data.GreenCenter)
			local pi, ri, gi = byRole.Pole.Position, byRole.Red.Position, byRole.Green.Position
			local k = (ri - gi).Magnitude / (rm - gm).Magnitude -- içe aktarmanın birim başına stud oranı
			local rot = axes(pi, ri, gi) * axes(pm, rm, gm):Inverse()
			local modelToImport = CFrame.new(pi - (rot * pm) * k) * rot
			local studs = TrafficLightData.StudsPerUnit / k
			local entries = {}
			for _, e in list do
				local rel = modelToImport:ToObjectSpace(e.Part.CFrame)
				table.insert(entries, {
					Template = e.Part, Role = e.Role, Color = e.Color,
					Offset = CFrame.new(rel.Position * studs) * rel.Rotation,
					Size = e.Part.Size * studs,
				})
			end
			result[kind] = entries
		elseif not warned then
			warned = true
			warn("[SignalRenderer] " .. kind .. " trafik ışığı modelinde direk/cam parçası eksik; eski direk kullanılacak")
		end
	end
	if next(result) == nil then
		return nil
	end
	templates = result
	return templates
end

local function buildModel(kind: string): Model
	local model = Instance.new("Model")
	model.Name = "TrafficLight_" .. kind
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	local list = (templates :: any)[kind]
	for _, e in list do
		local p = e.Template:Clone()
		for _, child in p:GetChildren() do
			child:Destroy()
		end
		p.Size = e.Size
		p.CFrame = e.Offset
		p.Anchored = true
		p.CanCollide = e.Role == "Pole"
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = e.Role == "Pole" or e.Role == "Housing"
		p.Color = e.Color
		p.Material = if e.Role == "Pole" then Enum.Material.Metal else Enum.Material.SmoothPlastic
		p.Transparency = 0
		p:SetAttribute("OffColor", e.Color)
		if LENS_ON[e.Role] then
			p.Name = e.Role -- setState bu adlarla bulur
		elseif e.Role == "Lamp" then
			p.Name = "Lamp"
			p:SetAttribute("NightColor", LAMP_NIGHT)
			CollectionService:AddTag(p, "NightGlow") -- CityLightsController gece yakar
		else
			p.Name = "TL_" .. e.Role
		end
		p.Parent = model
	end
	return model
end

-- Eski (model yokken) kutu direk
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
	if model.Name ~= "TrafficLight" then
		model:PivotTo(base) -- 3D model: kök = direğin ayağı, camlar LookVector yönünde, kol +X'e (yola)
		return
	end
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
		local on = (name == "Red" and state == "R") or (name == "Yellow" and state == "Y") or (name == "Green" and state == "G")
		for _, part in model:GetChildren() do
			if part.Name == name and part:IsA("BasePart") then
				local off = part:GetAttribute("OffColor")
				if typeof(off) == "Color3" then
					-- 3D model: yanan cam parlak (Neon), sönük cam kendi koyu rengi
					part.Color = if on then LENS_ON[name] else off
					part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				else
					part.Color = if on then LENS_ON[name] else OFF
				end
			end
		end
	end
end

-- Yaklaşım için direk tipi: çok şeritli yolda yola uzanan kollu C, diğerlerinde A ya da B (sabit, kavşağa göre)
local function kindFor(a): string
	if not loadTemplates() then
		return "Box"
	end
	local all = templates :: any
	local want = if a.Wide then "C" elseif a.Hash % 3 == 0 then "B" else "A"
	if all[want] then
		return want
	end
	for _, k in { "A", "B", "C" } do
		if all[k] then
			return k
		end
	end
	return "Box"
end

local function acquire(kind: string): Model
	local pool = pools[kind]
	local model = pool and table.remove(pool)
	if model then
		return model
	end
	return if kind == "Box" then build() else buildModel(kind)
end

local function release(entry)
	entry.Model.Parent = nil
	pools[entry.Kind] = pools[entry.Kind] or {}
	table.insert(pools[entry.Kind], entry.Model)
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
						Wide = #group >= 2,
						Hash = math.floor(math.abs(x) * 7 + math.abs(z) * 13),
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
			release(entry)
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
			release(entry)
			active[key] = nil
		end
	end
	for key, a in keep do
		local entry = active[key]
		if not entry then
			local kind = kindFor(a)
			local model = acquire(kind)
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
			entry = { Model = model, Kind = kind, Node = a.Node, Phase = a.Phase, State = nil }
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
