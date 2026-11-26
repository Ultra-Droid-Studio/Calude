-- DoorRenderer: bina kapıları (Yaşayan Şehir). Sadece bu istemcide, sadece oyuncunun yakınında, HAVUZLU.
--
-- Dünya (sunucunun ürettiği binalar) DEĞİŞMEZ: kapı, Shared/Ambient/Entrances kaydındaki noktaya yerel bir model
-- olarak konur (kasa + kanat + kapı boşluğu). Binanın kendi kapı parçası olan stillerde (ev, sıra ev, dükkân, tuğla
-- apartman) kanat o parçanın hemen önüne oturur; cam lobili binalarda cam kapı. Bir yaya kapıya yaklaşıp girerken ya
-- da binadan çıkarken (PedSim: entrance.OpenUntil) kanat dışarı doğru açılır, içerisi karanlık görünür, sonra kapanır.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Entrances = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ambient"):WaitForChild("Entrances"))

local DoorRenderer = {}

local RADIUS = 130 -- bu yarıçaptaki kapılar çizilir
local RELEASE = 150
local OPEN_ANGLE = math.rad(82)
local SPEED = math.rad(220) -- açılma hızı (°/sn)

local rgb = Color3.fromRGB
local LEAF = {
	house_a = { rgb(110, 76, 52), Enum.Material.Wood },
	house_b = { rgb(96, 70, 52), Enum.Material.Wood },
	townhouse = { rgb(40, 48, 60), Enum.Material.Wood },
	apartment_brick = { rgb(90, 64, 46), Enum.Material.Wood },
	deco_lowrise = { rgb(236, 236, 232), Enum.Material.SmoothPlastic },
	storefront = { rgb(60, 60, 64), Enum.Material.Metal },
	storefront_plain = { rgb(60, 60, 64), Enum.Material.Metal },
}
local GLASS = { rgb(150, 190, 210), Enum.Material.Glass } -- lobi/AVM/ofis cam kapısı

local folder: Folder?
local reg = nil
local pool: { Model } = {}
local active: { [any]: { Model: Model, Angle: number, Hinge: CFrame, Leaf: BasePart, Dark: BasePart } } = {}
local lastScan, lastFocus = 0, nil
local simTime = 0

function DoorRenderer.Init(registry)
	reg = registry
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "SolaraDoors"
		f.Parent = Workspace
		folder = f
	end
end

local function newPart(model: Model, name: string): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function build(): Model
	local m = Instance.new("Model")
	m.Name = "NPC_Door"
	newPart(m, "JambL")
	newPart(m, "JambR")
	newPart(m, "Head")
	newPart(m, "Dark")
	newPart(m, "Leaf")
	return m
end

-- e: Entrances kaydı. Kapı düzlemi e.(X, Y, Z), dışa normal (NX, NZ)
local function place(model: Model, e)
	local w, h = e.Width, e.Height
	local out = Vector3.new(e.NX, 0, e.NZ)
	local right = Vector3.new(-e.NZ, 0, e.NX) -- dışarıdan bakınca sağ (normal × yukarı)
	local base = Vector3.new(e.X, e.Y, e.Z)
	-- kapı düzleminin dış yüzü (binanın kapı parçasının hemen önü)
	local frame = CFrame.fromMatrix(base + out * 0.06, right, Vector3.yAxis, -out)
	local trim = rgb(48, 48, 52)
	local jl, jr, hd = model.JambL :: BasePart, model.JambR :: BasePart, model.Head :: BasePart
	for _, j in { jl, jr } do
		j.Size = Vector3.new(0.3, h, 0.36)
		j.Color = trim
		j.Material = Enum.Material.SmoothPlastic
	end
	jl.CFrame = frame * CFrame.new(-w / 2 - 0.15, h / 2, -0.12)
	jr.CFrame = frame * CFrame.new(w / 2 + 0.15, h / 2, -0.12)
	hd.Size = Vector3.new(w + 0.6, 0.3, 0.36)
	hd.Color = trim
	hd.CFrame = frame * CFrame.new(0, h + 0.15, -0.12)
	local dark = model.Dark :: BasePart
	dark.Size = Vector3.new(w, h, 0.05)
	dark.Color = rgb(12, 12, 14)
	dark.Material = Enum.Material.SmoothPlastic
	dark.CFrame = frame * CFrame.new(0, h / 2, 0.02)
	dark.Transparency = 1
	local style = LEAF[e.Style] or GLASS
	local leaf = model.Leaf :: BasePart
	leaf.Size = Vector3.new(w - 0.1, h - 0.1, 0.22)
	leaf.Color = style[1]
	leaf.Material = style[2]
	leaf.Transparency = (style == GLASS) and 0.35 or 0
	leaf.Reflectance = (style == GLASS) and 0.15 or 0
	-- menteşe: dışarıdan bakınca sol kenar; kanat dışarı doğru açılır (binanın içine girmez)
	local hinge = frame * CFrame.new(-w / 2 + 0.05, (h - 0.1) / 2 + 0.05, -0.14)
	leaf.CFrame = hinge * CFrame.new((w - 0.1) / 2, 0, 0)
	return hinge, leaf, dark
end

local function release(key)
	local a = active[key]
	if a then
		a.Model.Parent = nil
		table.insert(pool, a.Model)
		active[key] = nil
	end
end

-- 10 Hz: yakındaki kapıları al/bırak. focus nil → hepsini bırak
function DoorRenderer.Update(focus: Vector3?, time: number)
	simTime = time
	if not reg or not folder then
		return
	end
	if not focus then
		for key in active do
			release(key)
		end
		lastFocus = nil
		return
	end
	local now = os.clock()
	if lastFocus and (focus - lastFocus).Magnitude < 8 and now - lastScan < 0.5 then
		return
	end
	lastScan, lastFocus = now, focus
	for e, a in active do
		if (Vector3.new(e.X, 0, e.Z) - Vector3.new(focus.X, 0, focus.Z)).Magnitude > RELEASE then
			release(e)
		end
		local _ = a
	end
	for _, e in Entrances.Near(reg, focus.X, focus.Z, RADIUS) do
		if not active[e] then
			local model = table.remove(pool) or build()
			local hinge, leaf, dark = place(model, e)
			model.Parent = folder
			active[e] = { Model = model, Angle = 0, Hinge = hinge, Leaf = leaf, Dark = dark }
		end
	end
end

-- Her kare: kullanımda olan kapıları aç/kapat
function DoorRenderer.Animate(dt: number)
	for e, a in active do
		local target = ((e.OpenUntil or 0) > simTime) and OPEN_ANGLE or 0
		if a.Angle ~= target then
			local step = SPEED * dt
			if math.abs(target - a.Angle) <= step then
				a.Angle = target
			else
				a.Angle += if target > a.Angle then step else -step
			end
			local w = a.Leaf.Size.X
			-- dışarı açılış: menteşe ekseninde, dış yöne (−Z yerel) dönüş
			a.Leaf.CFrame = a.Hinge * CFrame.Angles(0, -a.Angle, 0) * CFrame.new(w / 2, 0, 0)
			a.Dark.Transparency = if a.Angle > 0.05 then 0 else 1
		end
	end
end

function DoorRenderer.ActiveCount(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

return DoorRenderer
