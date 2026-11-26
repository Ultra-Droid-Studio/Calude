-- CityLightsController: şehrin gece ışıkları (Şehir genişletme, aşama 3). Sadece görsel, sadece bu oyuncuda.
--
-- Sunucu dünyayı her zaman GÜNDÜZ hâliyle üretir (CityDressing). Gece/gündüz geçişini burada yaparız:
--   * "NightGlow": tabela yüzü, neon şerit, reklam panosu → gece NightColor + Neon, gündüz kendi rengi/malzemesi
--   * "ShopWindow": dükkân camı → gece sıcak ışık (Neon, yarı saydam), gündüz cam
--   * "NightText": bu parçalardaki yazılar (SurfaceGui) gece ışıktan etkilenmez → parlar; "NightTextColor" niteliği
--     varsa (koyu tabela) yazı gece o açık renge geçer
--   * Gerçek ışık (SurfaceLight) sadece kameraya en yakın birkaç vitrinde (masaüstü 10, dokunmatik 4), havuzlu.
-- Gece bilgisi WeatherService'in yazdığı workspace "IsNight" niteliğinden (sokak lambalarıyla aynı an).
-- StreamingEnabled: yeni akan parçalar etiket sinyaliyle yakalanır ve o anki duruma getirilir.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CityLightsController = {
	Name = "CityLightsController",
	Priority = 40,
}

local controllers
local night = false
local dayState = setmetatable({}, { __mode = "k" }) -- part → { Color, Material, Transparency }
local applyJob = 0

local LIGHT_RADIUS = 140 -- stud: bu mesafeden uzak vitrine gerçek ışık verilmez
local LIGHT_COLOR = Color3.fromRGB(255, 214, 150)
local MAX_LIGHTS_DESKTOP = 10
local MAX_LIGHTS_TOUCH = 4
local lights = {} -- havuz: { Light = SurfaceLight, Part = BasePart? }

local dayTextColor = setmetatable({}, { __mode = "k" }) -- TextLabel → gündüz yazı rengi

local function setText(part: Instance, glowing: boolean)
	local nightText = part:GetAttribute("NightTextColor") -- koyu tabelada gece yazı rengi (CityDressing)
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") then
			child.LightInfluence = if glowing then 0 else 1
			child.Brightness = if glowing then 1.3 else 1
			if typeof(nightText) == "Color3" then
				for _, label in child:GetChildren() do
					if label:IsA("TextLabel") then
						if glowing then
							if not dayTextColor[label] then
								dayTextColor[label] = label.TextColor3
							end
							label.TextColor3 = nightText
						elseif dayTextColor[label] then
							label.TextColor3 = dayTextColor[label]
						end
					end
				end
			end
		end
	end
end

local function apply(part: Instance, isNight: boolean)
	if not part:IsA("BasePart") then
		return
	end
	local nightColor = part:GetAttribute("NightColor")
	local isWindow = CollectionService:HasTag(part, "ShopWindow")
	local isGlow = CollectionService:HasTag(part, "NightGlow")
	if (isWindow or isGlow) and typeof(nightColor) == "Color3" then
		if isNight then
			if not dayState[part] then
				dayState[part] = { Color = part.Color, Material = part.Material, Transparency = part.Transparency }
			end
			part.Color = nightColor
			part.Material = Enum.Material.Neon
			if isWindow then
				part.Transparency = 0.35
			end
		else
			local saved = dayState[part]
			if saved then
				part.Color = saved.Color
				part.Material = saved.Material
				part.Transparency = saved.Transparency
			end
		end
	end
	if CollectionService:HasTag(part, "NightText") then
		setText(part, isNight)
	end
end

local TAGS = { "NightGlow", "ShopWindow", "NightText" }

local function applyAll(isNight: boolean)
	applyJob += 1
	local job = applyJob
	task.spawn(function()
		local count = 0
		local seen = {}
		for _, tag in TAGS do
			for _, part in CollectionService:GetTagged(tag) do
				if job ~= applyJob then
					return -- daha yeni bir geçiş başladı
				end
				if not seen[part] then
					seen[part] = true
					apply(part, isNight)
					count += 1
					if count % 300 == 0 then
						task.wait() -- binlerce parça tek karede değişmesin
					end
				end
			end
		end
	end)
end

-- ===== Yakın vitrin ışıkları =====
local function maxLights(): number
	local input = controllers.InputController
	if input and input.IsTouch and input:IsTouch() then
		return MAX_LIGHTS_TOUCH
	end
	return MAX_LIGHTS_DESKTOP
end

local function releaseLights()
	for _, slot in lights do
		slot.Light.Enabled = false
		slot.Light.Parent = nil
		slot.Part = nil
	end
end

local function updateLights()
	if not night then
		releaseLights()
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local nearest = {}
	for _, part in CollectionService:GetTagged("ShopWindow") do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			local dist = (part.Position - origin).Magnitude
			if dist < LIGHT_RADIUS then
				table.insert(nearest, { Part = part, Dist = dist })
			end
		end
	end
	table.sort(nearest, function(a, b)
		return a.Dist < b.Dist
	end)
	local count = math.min(#nearest, maxLights())
	for i = 1, math.max(count, #lights) do
		local slot = lights[i]
		if i <= count then
			if not slot then
				local light = Instance.new("SurfaceLight")
				light.Face = Enum.NormalId.Front -- cam parçasının önü sokağa bakar (CityDressing yerel −Z)
				light.Range = 16
				light.Angle = 80
				light.Brightness = 1.4
				light.Color = LIGHT_COLOR
				light.Shadows = false
				slot = { Light = light, Part = nil }
				lights[i] = slot
			end
			local target = nearest[i].Part
			if slot.Part ~= target then
				slot.Part = target
				slot.Light.Parent = target
			end
			slot.Light.Enabled = true
		elseif slot then
			slot.Light.Enabled = false
			slot.Light.Parent = nil
			slot.Part = nil
		end
	end
end

function CityLightsController:IsNight(): boolean
	return night
end

function CityLightsController:Init(allControllers)
	controllers = allControllers
end

function CityLightsController:Start()
	night = workspace:GetAttribute("IsNight") == true
	applyAll(night)
	workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		local now = workspace:GetAttribute("IsNight") == true
		if now ~= night then
			night = now
			applyAll(night)
			updateLights()
		end
	end)
	for _, tag in TAGS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
			if night then
				apply(part, true)
			end
		end)
	end
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.5 then
			accumulator = 0
			local ok, err = pcall(updateLights)
			if not ok then
				warn("[CityLights]", err)
			end
		end
	end)
end

return CityLightsController
