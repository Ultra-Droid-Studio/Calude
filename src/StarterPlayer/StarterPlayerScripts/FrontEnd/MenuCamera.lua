-- MenuCamera: ana menü kamera çekimleri. CameraController:RequestScripted için "supplier" üretir;
-- kameranın CFrame'ini yine SADECE CameraController yazar (mimari kuralı korunur).
--
--   Title  : şehir merkezinin kulelerine bakan, yörüngede yavaşça kayan hava çekimi.
--   Pause  : oyun içi menüde oyuncunun etrafında yavaş dönen çekim (her zaman akmış bölgede kalır).
-- "Hareketi azalt" açıkken iki çekim de sabit durur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontEndConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FrontEndConfig"))

local MenuCamera = {}

local DEG = math.pi / 180

local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

-- Yörüngede açıya göre kamera konumu
local function titlePosition(angleDeg: number): Vector3
	local shot = FrontEndConfig.MenuShot
	local a = angleDeg * DEG
	return Vector3.new(shot.Pivot.X + shot.Radius * math.cos(a), shot.Height, shot.Pivot.Z + shot.Radius * math.sin(a))
end

function MenuCamera.TitleCFrame(t: number, reduceMotion: boolean): CFrame
	local shot = FrontEndConfig.MenuShot
	local alpha
	if reduceMotion then
		alpha = 0.5
	else
		local phase = (t / shot.Period) % 2
		alpha = easeInOut(if phase <= 1 then phase else 2 - phase)
	end
	local angle = shot.StartAngle + (shot.EndAngle - shot.StartAngle) * alpha
	return CFrame.lookAt(titlePosition(angle), shot.Target)
end

-- Akış ve şehir-hazır kontrolü için çekimin ortası
function MenuCamera.TitleProbe(): (Vector3, Vector3)
	local shot = FrontEndConfig.MenuShot
	return titlePosition((shot.StartAngle + shot.EndAngle) / 2), shot.Target
end

-- getReduceMotion: () -> boolean
function MenuCamera.TitleSupplier(getReduceMotion: () -> boolean)
	local elapsed = 0
	local shot = FrontEndConfig.MenuShot
	local focus = CFrame.new(shot.Target)
	return function(dt: number)
		elapsed += dt
		return MenuCamera.TitleCFrame(elapsed, getReduceMotion()), shot.FieldOfView, focus
	end
end

-- getRoot: () -> BasePart? (oyuncunun HumanoidRootPart'ı). Yoksa son bilinen noktada kalır.
function MenuCamera.PauseSupplier(getRoot: () -> BasePart?, getReduceMotion: () -> boolean, startYaw: number)
	local shot = FrontEndConfig.PauseShot
	local yaw = startYaw
	local lastCenter: Vector3? = nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return function(dt: number)
		local root = getRoot()
		if root and root.Parent then
			lastCenter = root.Position
			params.FilterDescendantsInstances = { root.Parent }
		end
		local center = (lastCenter or FrontEndConfig.MenuShot.Target) + Vector3.new(0, shot.LookHeight, 0)
		if not getReduceMotion() then
			yaw += shot.DegreesPerSecond * DEG * dt
		end
		local offset = Vector3.new(math.sin(yaw) * shot.Radius, shot.Height, math.cos(yaw) * shot.Radius)
		-- Duvar/bina arkasına girmesin: merkezden dışarı küre atışı
		local position = center + offset
		local hit = workspace:Spherecast(center, shot.CollisionRadius, offset, params)
		if hit then
			position = center + offset.Unit * math.max(hit.Distance - 0.5, 3)
		end
		return CFrame.lookAt(position, center), shot.FieldOfView, CFrame.new(center)
	end
end

return MenuCamera
