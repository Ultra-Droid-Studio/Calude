-- MathUtil: kamera ve hareket için kare hızından bağımsız yumuşatma yardımcıları.

local MathUtil = {}

-- Kare hızından bağımsız üstel yaklaşım katsayısı. sharpness büyüdükçe hedefe hızlı varır.
function MathUtil.SmoothAlpha(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

function MathUtil.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Açıyı (radyan) en kısa yoldan yaklaştırır
function MathUtil.LerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

function MathUtil.FlatVector(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

return MathUtil
