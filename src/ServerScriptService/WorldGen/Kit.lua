-- Kit: dünya inşası için parça fabrikası.
-- Tüm parçalar buradan geçer → sayım, periyodik bekleme (sunucu donmaz) ve tutarlı varsayılanlar.

local CollectionService = game:GetService("CollectionService")

local Kit = {}
Kit.__index = Kit

export type Kit = typeof(setmetatable({} :: { Count: number, YieldEvery: number }, Kit))

local CYL_ROT = CFrame.Angles(0, 0, math.pi / 2) -- silindir ekseni X → Y

function Kit.new(yieldEvery: number?): Kit
	return setmetatable({ Count = 0, YieldEvery = yieldEvery or 0 }, Kit)
end

function Kit._tick(self: Kit)
	self.Count += 1
	if self.YieldEvery > 0 and self.Count % self.YieldEvery == 0 then
		task.wait()
	end
end

local function finish(part: BasePart, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	part.Anchored = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false -- dekor parçaları Touched olayı üretmesin (performans)
	if props then
		for key, value in props do
			(part :: any)[key] = value
		end
	end
end

-- Dikdörtgen parça
function Kit.Box(self: Kit, parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cframe
	finish(p, color, material, props)
	p.Parent = parent
	self:_tick()
	return p
end

-- Dik silindir: cframe silindirin MERKEZİ, ekseni dünya Y yönünde
function Kit.Cylinder(self: Kit, parent: Instance, height: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = cframe * CYL_ROT
	finish(p, color, material, props)
	p.Parent = parent
	self:_tick()
	return p
end

function Kit.Ball(self: Kit, parent: Instance, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = cframe
	finish(p, color, material, props)
	p.Parent = parent
	self:_tick()
	return p
end

-- Kama: eğimli yüz -Z (ön) ve yukarı bakar; dik yüz +Z (arka) tarafında
function Kit.Wedge(self: Kit, parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cframe
	finish(p, color, material, props)
	p.Parent = parent
	self:_tick()
	return p
end

-- Bir parçanın yüzüne yazı (tabela). Metin çok uzunsa otomatik küçülür.
function Kit.Label(self: Kit, part: BasePart, face: Enum.NormalId, text: string, textColor: Color3?, glow: boolean?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = if glow then 0 else 1
	gui.MaxDistance = 600 -- uzaktan çizilmez (performans)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
	return gui
end

function Kit.Folder(_self: Kit, parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Kit.Model(_self: Kit, parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.Tag(_self: Kit, instance: Instance, tag: string)
	CollectionService:AddTag(instance, tag)
end

-- İki üst-yüzey noktası arasında eğimli "şerit" (yol, kaldırım, çizgi) üretmek için CFrame.
-- Döndürülen CFrame parçanın MERKEZİ; parçanın üst yüzü a→b doğrusu üzerinde olur.
function Kit.StripCFrame(a: Vector3, b: Vector3, thickness: number, lateral: number?): (CFrame, number)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf
	if length < 1e-3 then
		cf = CFrame.new(mid)
	else
		cf = CFrame.lookAt(mid, b)
	end
	return cf * CFrame.new(lateral or 0, -thickness / 2, 0), length
end

Kit.Colors = table.freeze({
	Asphalt = Color3.fromRGB(58, 60, 64),
	AsphaltLight = Color3.fromRGB(74, 76, 80),
	Sidewalk = Color3.fromRGB(196, 192, 184),
	Curb = Color3.fromRGB(170, 166, 160),
	LineWhite = Color3.fromRGB(236, 236, 230),
	LineYellow = Color3.fromRGB(242, 196, 60),
	Concrete = Color3.fromRGB(176, 172, 164),
	Barrier = Color3.fromRGB(190, 186, 178),
	Grass = Color3.fromRGB(104, 146, 82),
	GrassDark = Color3.fromRGB(78, 118, 64),
	Dirt = Color3.fromRGB(140, 110, 76),
	Sand = Color3.fromRGB(226, 206, 156),
	Wood = Color3.fromRGB(122, 86, 56),
	Leaf = Color3.fromRGB(76, 128, 62),
	Pine = Color3.fromRGB(52, 96, 58),
	Metal = Color3.fromRGB(120, 124, 130),
	Glass = Color3.fromRGB(110, 150, 170),
	SignGreen = Color3.fromRGB(28, 104, 62),
	Accent = Color3.fromRGB(255, 122, 69),
	Teal = Color3.fromRGB(64, 196, 214),
})

return Kit
