-- CarModelKit: içe aktarılan 3D otomobil modellerini (CarModelConfig) araçlara giydirir.
-- Sunucu (oyuncu araçları, VehicleFactory) ve istemci (NPC trafiği, TrafficRenderer) aynı modülü kullanır.
--
-- Kalibrasyon (model başına bir kez): Studio'nun içe aktarıcısı yönü/birimi nasıl yorumlarsa yorumlasın, modelin
-- KENDİ tekerlekleri ölçülür:
--   ön = ön teker ortası − arka teker ortası,  sağ = sağ tekerler − sol tekerler,  yukarı = sağ × ön,
--   orijin = dört teker merkezinin ortası (teker merkezi yüksekliğinde).
-- Her parça bu çerçeveye göre saklanır; giydirirken hedef çerçeveye ölçekle yerleştirilir.
-- Görsel parçalar kütlesiz, çarpışmasız ve ışın sorgusuna kapalıdır (fizik ve kamera etkilenmez).
-- Tekerlek görselleri Motor6D ile bağlanır: dönüş (spin) Motor6D.Transform ile istemcide oynatılır.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CarModelConfig"))

local CarModelKit = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
local cache: { [string]: any } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, ...)
	if not warned[key] then
		warned[key] = true
		warn("[CarModelKit]", ...)
	end
end

-- Parça adı → rol ve (tekerlekse) hangi teker. İçe aktarıcının eklediği önek/sonekleri tolere eder.
local function roleOf(name: string, modelName: string): (string?, string?)
	local n = name
	if string.sub(n, 1, #modelName + 1) == modelName .. "_" then
		n = string.sub(n, #modelName + 2)
	end
	local wheel, kind = string.match(n, "^Wheel_(%u%u)_(%a+)")
	if wheel then
		return kind, wheel
	end
	local role = string.match(n, "^(%a+%d?)")
	if role and Config.Roles[role] then
		return role, nil
	end
	return nil, nil
end

-- Model hazır mı? (ReplicatedStorage.<Folder>.<name> var ve kalibre edilebiliyor)
function CarModelKit.Get(name: string)
	local cached = cache[name]
	if cached ~= nil then
		return cached or nil
	end
	local folder = ReplicatedStorage:FindFirstChild(Config.Folder)
	local model = folder and folder:FindFirstChild(name)
	if not model then
		return nil
	end
	local entries = {}
	local wheelParts = { FL = {}, FR = {}, RL = {}, RR = {} }
	local tires = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role, wheel = roleOf(d.Name, name)
			if role then
				table.insert(entries, { Template = d, Role = role, Wheel = wheel })
				if wheel then
					table.insert(wheelParts[wheel], d)
					if role == "Tire" then
						tires[wheel] = d
					end
				end
			end
		end
	end
	for _, w in WHEELS do
		if #wheelParts[w] == 0 then
			warnOnce(name, name, "modelinde Wheel_" .. w .. "_* parçası yok; kutu görünüm kullanılacak.")
			cache[name] = false
			return nil
		end
	end
	local centers = {}
	for _, w in WHEELS do
		local sum = Vector3.zero
		for _, p in wheelParts[w] do
			sum += p.Position
		end
		centers[w] = sum / #wheelParts[w]
	end
	local front = ((centers.FL + centers.FR) - (centers.RL + centers.RR)) / 2
	local right = ((centers.FR - centers.FL) + (centers.RR - centers.RL)) / 2
	if front.Magnitude < 1e-3 or right.Magnitude < 1e-3 then
		warnOnce(name, name, "modelinin tekerlek konumları okunamadı.")
		cache[name] = false
		return nil
	end
	local f = front.Unit
	local r = (right - f * right:Dot(f)).Unit
	local up = r:Cross(f).Unit
	local origin = (centers.FL + centers.FR + centers.RL + centers.RR) / 4
	local frame = CFrame.fromMatrix(origin, r, up) -- LookVector = ön
	local tire = tires.FL or wheelParts.FL[1]
	local radius = math.max(tire.Size.X, tire.Size.Y, tire.Size.Z) / 2
	local roof, minZ, maxZ, maxX = -math.huge, math.huge, -math.huge, 0
	for _, e in entries do
		e.Offset = frame:ToObjectSpace(e.Template.CFrame)
		if e.Wheel then
			e.Center = frame:PointToObjectSpace(centers[e.Wheel])
		end
		local half = e.Template.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = e.Offset * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
					if not e.Wheel then
						roof = math.max(roof, c.Y)
					end
					minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
					maxX = math.max(maxX, math.abs(c.X))
				end
			end
		end
	end
	local info = {
		Name = name,
		Entries = entries,
		Wheelbase = front.Magnitude,
		Track = right.Magnitude,
		WheelRadius = radius,
		RoofY = roof, -- teker merkezinden tavana
		Length = maxZ - minZ,
		Width = maxX * 2,
	}
	cache[name] = info
	return info
end

-- defId için kullanılacak model (yoksa nil). traffic = true → NPC'ye özel varyantlar (taksi) da olabilir.
function CarModelKit.Pick(defId: string, rng: Random, traffic: boolean?): string?
	if traffic then
		for _, v in Config.TrafficVariants[defId] or {} do
			if rng:NextNumber() < v.Chance and CarModelKit.Get(v.Model) then
				return v.Model
			end
		end
	end
	local available = {}
	for _, name in Config.ByDefinition[defId] or {} do
		if CarModelKit.Get(name) then
			table.insert(available, name)
		end
	end
	if #available == 0 then
		return nil
	end
	return available[rng:NextInteger(1, #available)]
end

function CarModelKit.PaintColors(name: string, paint: Color3?): (Color3, Color3)
	local colors = Config.Colors[name] or {}
	local base = if Config.FixedPaint[name] or not paint then (colors.Paint or Color3.new(0.8, 0.8, 0.8)) else paint
	local second
	if Config.Paint2Rule[name] == "Darker" then
		second = base:Lerp(Color3.new(0, 0, 0), 0.12)
	else
		second = colors.Paint2 or base
	end
	return base, second
end

-- Boyayı değiştir (havuzdan yeniden kullanılan NPC araçları için)
function CarModelKit.Repaint(parts: { BasePart }, name: string, paint: Color3?)
	local base, second = CarModelKit.PaintColors(name, paint)
	for _, p in parts do
		local role = p:GetAttribute("CarRole")
		if role == "Paint" then
			p.Color = base
		elseif role == "Paint2" then
			p.Color = second
		end
	end
end

-- Giydir. opts:
--   Frame: CFrame       hedef çerçeve: teker merkezlerinin ortası, teker merkezi yüksekliğinde; LookVector = ön
--   Scale: number       modelden hedefe ölçek
--   Parent: Instance
--   Body: BasePart      gövde parçalarının kaynaklanacağı parça (şasi / NPC kökü)
--   Wheels: { [string]: BasePart }?   teker görsellerinin bağlanacağı parçalar (FL/FR/RL/RR); yoksa Body
--   Paint: Color3?      gövde rengi (sabit boyalı modellerde yok sayılır)
--   Shadows: boolean?
-- Döndürür: { Parts = { BasePart }, Spin = { { Motor: Motor6D, Wheel: string } }, Lights = { Headlight = {}, TailLight = {} } }
function CarModelKit.Build(info, opts)
	local colors = Config.Colors[info.Name] or {}
	local base, second = CarModelKit.PaintColors(info.Name, opts.Paint)
	local s = opts.Scale
	local result = { Parts = {}, Spin = {}, Lights = { Headlight = {}, TailLight = {} } }
	for _, e in info.Entries do
		local p = e.Template:Clone()
		for _, child in p:GetChildren() do
			child:Destroy() -- içe aktarıcının eklediği görünüş/kaynak nesneleri: renk ve bağlantılar bizden
		end
		p.Size = e.Template.Size * s
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		local style = Config.Roles[e.Role] or {}
		p.Material = style.Material or Enum.Material.SmoothPlastic
		p.Transparency = style.Transparency or 0
		p.Reflectance = style.Reflectance or 0
		p.CastShadow = opts.Shadows ~= false and (e.Role == "Paint" or e.Role == "Paint2" or e.Role == "Dark" or e.Role == "Tire")
		p.Color = if e.Role == "Paint" then base elseif e.Role == "Paint2" then second else (colors[e.Role] or Color3.fromRGB(110, 110, 110))
		p:SetAttribute("CarRole", e.Role)
		p:SetAttribute("OffColor", p.Color)
		if e.Role == "Headlight" or e.Role == "TailLight" then
			p.Name = e.Role -- araç ışık sistemi (VehicleService) bu adlarla bulur
			table.insert(result.Lights[e.Role], p)
		elseif e.Wheel then
			p.Name = "CarWheel_" .. e.Wheel .. "_" .. e.Role
		else
			p.Name = "Car_" .. e.Role
		end
		local offset = e.Offset
		p.CFrame = opts.Frame * CFrame.new(offset.Position * s) * offset.Rotation
		if e.Wheel then
			local anchor = (opts.Wheels and opts.Wheels[e.Wheel]) or opts.Body
			local center = opts.Frame * CFrame.new(e.Center * s) -- teker merkezi, aracın eksenleriyle
			local motor = Instance.new("Motor6D")
			motor.Name = "SpinMotor"
			motor.Part0 = anchor
			motor.Part1 = p
			motor.C0 = anchor.CFrame:ToObjectSpace(center)
			motor.C1 = p.CFrame:ToObjectSpace(center)
			motor:SetAttribute("Wheel", e.Wheel)
			motor.Parent = p
			table.insert(result.Spin, { Motor = motor, Wheel = e.Wheel })
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = opts.Body
			weld.Part1 = p
			weld.Parent = p
		end
		p.Parent = opts.Parent
		table.insert(result.Parts, p)
	end
	return result
end

return CarModelKit
