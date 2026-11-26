-- MapView: minimap, tam harita ve GPS'in ortak görünüm hesapları (saf matematik, Instance yok).
-- tools/test_map_view.py bu dosyayı doğrudan çalıştırır; bu yüzden tip açıklaması kullanılmaz.
--
-- Kural: harita tuvalinin konumu, tuvale UYGULANAN ölçekle hesaplanır. Eskiden ölçek (UIScale) sadece %1 değişince
-- güncellenip konum her seferinde yeni ölçekle hesaplanıyordu; araçta (hıza bağlı yakınlık) harita merkezi oyuncudan
-- 100 stud'a kadar kayıyor, eşik aşılınca geri zıplıyordu.

local MapView = {}

local function round(x)
	return math.floor(x + 0.5)
end

-- Tuval kökünün görüntü alanındaki konumu (tam birime yuvarlanır: harita bütün olarak kayar, parçalar birbirine göre
-- oynamaz). Dünya noktası (cx, cz), görüntü alanının merkezine düşer (en fazla 0.5 birim hata).
function MapView.RootOffset(cx, cz, scale, viewportX, viewportY, half)
	return round(viewportX / 2 - (cx + half) * scale), round(viewportY / 2 - (cz + half) * scale)
end

-- Uygulanan yakınlık: hedeften `step` (oran) kadar uzaklaşınca hedefe geçer. Böylece binlerce harita parçasının
-- yeniden yerleşimi her karede değil, birkaç yüzde birlik adımlarda olur. Konum hatası oluşturmaz (konum her zaman
-- uygulanan ölçekle hesaplanır).
function MapView.ZoomStep(applied, target, step)
	if applied == nil or applied <= 0 or math.abs(target - applied) > applied * step then
		return target
	end
	return applied
end

-- Kuzey = 0°, doğu (+X) = 90°. Bakış vektörünün yatay bileşeni çok küçükse (araç dikleşmiş/devrilmiş) yön
-- tanımsızdır: son geçerli yön korunur (eskiden ok rastgele yönlere dönüyordu).
MapView.MinHorizontal = 0.3
function MapView.Heading(lookX, lookZ, last)
	if math.sqrt(lookX * lookX + lookZ * lookZ) < MapView.MinHorizontal then
		return last or 0
	end
	return math.deg(math.atan2(lookX, -lookZ))
end

-- İki açı arasındaki en kısa fark (derece, -180..180)
function MapView.AngleDelta(a, b)
	return (a - b + 180) % 360 - 180
end

return MapView
