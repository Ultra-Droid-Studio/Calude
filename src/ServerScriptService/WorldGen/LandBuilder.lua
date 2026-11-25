-- LandBuilder: zemin karoları, bloklar, su (Terrain), tepeler, kumsal, rıhtım duvarları, harita sınırı.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapDefinitions = require(ReplicatedStorage.Shared.MapDefinitions)

local LandBuilder = {}

local WATER_TOP = -1.5
local WATER_BOTTOM = -14
local BED_BOTTOM = -26

local BLOCK_MATERIAL = {
	Concrete = { Enum.Material.Concrete, Color3.fromRGB(184, 180, 172) },
	Pavement = { Enum.Material.Pavement, Color3.fromRGB(206, 196, 178) },
	Grass = { Enum.Material.Grass, Color3.fromRGB(106, 150, 84) },
	Asphalt = { Enum.Material.Asphalt, Color3.fromRGB(110, 108, 104) },
}

local function fillTerrainRect(terrain: Terrain, x0: number, z0: number, x1: number, z1: number, yBottom: number, yTop: number, material: Enum.Material, doYield: boolean)
	-- FillBlock büyük bölgeleri tek çağrıda doldurabilir ama 2048'lik parçalara bölmek daha güvenli
	local step = 1024
	local x = x0
	while x < x1 do
		local xe = math.min(x + step, x1)
		local z = z0
		while z < z1 do
			local ze = math.min(z + step, z1)
			local size = Vector3.new(xe - x, yTop - yBottom, ze - z)
			local center = Vector3.new((x + xe) / 2, (yBottom + yTop) / 2, (z + ze) / 2)
			terrain:FillBlock(CFrame.new(center), size, material)
			z = ze
		end
		x = xe
		if doYield then
			task.wait()
		end
	end
end

-- Su türüne göre derinlik ve taban: açık deniz tabansız (koyu mavi derinlik), göl/nehir çamur tabanlı
local WATER_SPEC = {
	sea = { Bottom = -13.5, Bed = nil },
	bay = { Bottom = -13.5, Bed = Enum.Material.Sand },
	river = { Bottom = -13.5, Bed = Enum.Material.Mud },
	lake = { Bottom = -17.5, Bed = Enum.Material.Mud },
	pond = { Bottom = -5.5, Bed = Enum.Material.Mud },
}

function LandBuilder.BuildTerrain(kit, _world: Instance)
	local data = MapDefinitions.GetData()
	local terrain = workspace.Terrain
	local doYield = kit.YieldEvery > 0
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 146, 82))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(226, 206, 156))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(128, 120, 110))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(86, 74, 56))
	terrain.WaterColor = Color3.fromRGB(36, 120, 150)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8

	for _, w in data.Water do
		local spec = WATER_SPEC[w.Kind] or WATER_SPEC.sea
		if spec.Bed then
			fillTerrainRect(terrain, w.X0, w.Z0, w.X1, w.Z1, spec.Bottom - 8, spec.Bottom, spec.Bed, doYield)
		end
		fillTerrainRect(terrain, w.X0, w.Z0, w.X1, w.Z1, spec.Bottom, WATER_TOP, Enum.Material.Water, doYield)
	end

	for index, h in data.Hills do
		local material = if h.Radius > 120 then Enum.Material.Rock else Enum.Material.Grass
		terrain:FillBall(Vector3.new(h.X, h.CenterY, h.Z), h.Radius, material)
		-- Büyük kayalık tepelerin üstünü çimle kapla (doğal görünüm)
		if material == Enum.Material.Rock then
			terrain:FillBall(Vector3.new(h.X, h.CenterY + h.Radius * 0.35, h.Z), h.Radius * 0.62, Enum.Material.Grass)
		end
		if doYield and index % 6 == 0 then
			task.wait()
		end
	end
end

function LandBuilder.BuildGround(kit, world: Instance)
	local data = MapDefinitions.GetData()
	local meta = data.Meta
	local folder = kit:Folder(world, "Ground")

	for _, g in data.Ground do
		local size = Vector3.new(g.X1 - g.X0, 4, g.Z1 - g.Z0)
		kit:Box(folder, size, CFrame.new((g.X0 + g.X1) / 2, -2, (g.Z0 + g.Z1) / 2), Color3.fromRGB(104, 146, 82), Enum.Material.Grass, { CastShadow = false })
	end

	-- Bloklar (kaldırımla aynı yükseklikte arsa zemini)
	local blocksFolder = kit:Folder(world, "Blocks")
	for _, b in data.Blocks do
		local spec = BLOCK_MATERIAL[b.Material] or BLOCK_MATERIAL.Concrete
		local h = meta.BlockTop
		kit:Box(blocksFolder, Vector3.new(b.X1 - b.X0, h, b.Z1 - b.Z0), CFrame.new((b.X0 + b.X1) / 2, h / 2, (b.Z0 + b.Z1) / 2), spec[2], spec[1], { CastShadow = false })
	end
end

-- Uzun bir dikdörtgeni en fazla `step` uzunluğunda parçalara böler (Roblox parça sınırı 2048)
local function splitRect(x0: number, z0: number, x1: number, z1: number, step: number)
	local pieces = {}
	if x1 - x0 >= z1 - z0 then
		local x = x0
		while x < x1 do
			local xe = math.min(x + step, x1)
			table.insert(pieces, { x, z0, xe, z1 })
			x = xe
		end
	else
		local z = z0
		while z < z1 do
			local ze = math.min(z + step, z1)
			table.insert(pieces, { x0, z, x1, ze })
			z = ze
		end
	end
	return pieces
end

local BEACH_DROP = 6.3
local BEACH_YAW = { E = -90, W = 90, N = 0, S = 180 }

function LandBuilder.BuildCoast(kit, world: Instance)
	local data = MapDefinitions.GetData()
	local meta = data.Meta
	local h = meta.HalfSize
	local folder = kit:Folder(world, "Coast")
	local wallColor = Color3.fromRGB(150, 146, 138)

	for _, c in data.Coast do
		if c.Kind == "beach" then
			-- Kama: dik yüzü karaya, eğimi suya bakar
			local alongZ = c.Dir == "E" or c.Dir == "W"
			for _, r in splitRect(c.X0, c.Z0, c.X1, c.Z1, 400) do
				local sx, sz = r[3] - r[1], r[4] - r[2]
				local size = if alongZ then Vector3.new(sz, BEACH_DROP, sx) else Vector3.new(sx, BEACH_DROP, sz)
				local cf = CFrame.new((r[1] + r[3]) / 2, meta.RoadTop - BEACH_DROP / 2, (r[2] + r[4]) / 2) * CFrame.Angles(0, math.rad(BEACH_YAW[c.Dir] or -90), 0)
				kit:Wedge(folder, size, cf, Color3.fromRGB(226, 206, 156), Enum.Material.Sand, { CastShadow = false })
			end
		elseif c.Kind == "boardwalk" then
			for _, r in splitRect(c.X0, c.Z0, c.X1, c.Z1, 1800) do
				kit:Box(folder, Vector3.new(r[3] - r[1], 0.8, r[4] - r[2]), CFrame.new((r[1] + r[3]) / 2, 0.4, (r[2] + r[4]) / 2), Color3.fromRGB(150, 112, 76), Enum.Material.WoodPlanks)
			end
		elseif c.Kind == "seawall" then
			for _, r in splitRect(c.X0, c.Z0, c.X1, c.Z1, 1800) do
				kit:Box(folder, Vector3.new(r[3] - r[1], 12, r[4] - r[2]), CFrame.new((r[1] + r[3]) / 2, -5.2, (r[2] + r[4]) / 2), wallColor, Enum.Material.Concrete)
			end
		elseif c.Kind == "bank" then
			for _, r in splitRect(c.X0, c.Z0, c.X1, c.Z1, 1800) do
				kit:Box(folder, Vector3.new(r[3] - r[1], 6.4, r[4] - r[2]), CFrame.new((r[1] + r[3]) / 2, -3, (r[2] + r[4]) / 2), Color3.fromRGB(96, 82, 60), Enum.Material.Mud, { CastShadow = false })
			end
		end
	end

	-- Harita sınırı (görünmez duvarlar). Kuzey/batı/güneyde sırtlar, doğuda açık deniz.
	local bounds = kit:Folder(world, "Boundary")
	local thickness, height = 10, 600
	local function wall(x0: number, z0: number, x1: number, z1: number)
		for _, r in splitRect(x0, z0, x1, z1, 2000) do
			kit:Box(bounds, Vector3.new(r[3] - r[1], height, r[4] - r[2]), CFrame.new((r[1] + r[3]) / 2, height / 2 - 40, (r[2] + r[4]) / 2),
				Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false, CastShadow = false })
		end
	end
	wall(-h, -h - thickness, h, -h)
	wall(-h, h, h, h + thickness)
	wall(-h - thickness, -h, -h, h)
	wall(h, -h, h + thickness, h)
end

return LandBuilder
