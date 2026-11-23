# Stage 66 — Hibrit mod (jiroskopsuz cihaz) + ölü bölge

## Hibrit mod
Rotation-vector sensörü olmayan cihazlarda (sınıf `am` ya da yeni `acc`) eski yol ivmeölçer+manyetometreyi birleştiriyordu;
pusula yönü kapalı alanda gürültülü/kaymalıydı. Artık:
- **Eğim (pitch) ve yatış (roll)** yalnız ivmeölçerden (yerçekimi); **yön (yaw)** dokunma/sürükleme ile. Manyetometre kullanılmaz.
- Java (`MainActivity.onSensorChanged`): uyarlanır alçak geçiren süzgeç (ivme büyüklüğü 9,81'den saptıkça katsayı 0,18 → ~0,015:
  baş hareketi sırasında yerçekimine az güven), ekran döndürmesine göre ekran eksenlerine çevirir, en çok ~60 Hz
  `window.__nxNativeGrav(x,y,z)` gönderir.
- JS (`Cam.update`): pitch = asin(−gz), roll = atan2(gx, gy); neredeyse dik yukarı/aşağı bakışta (|gz| > 0,83–0,93) yatış sönümlenir.
  `Cam.hybridLive()` doğruysa sürüklemede yalnız yaw değişir (pitch sensörden gelir).
- `DeviceProfile.sensorOf`: yeni `acc` sınıfı (yalnız ivmeölçer). Doğrulama (Stage 65) hibrit olayları da sayar;
  açılışta "Jiroskop yok: hibrit mod (eğim sensörden, yönü parmakla çevir)" bildirimi, Performans → Sensör satırında "hibrit".

## Ölü bölge (histerezis)
Hedef ile mevcut kamera quaternion'u arasındaki fark **0,10°'yi aşınca** hareket başlar, **0,03°'nin altına inince** durur
(`Cam.dzOn/dzOff`). Durunca quaternion değişmez → kare döngüsündeki `ch` denetimi sahneyi yeniden çizmez: sensör gürültüsü artık
her karede tam render tetiklemez, GPU/pil dinlenir. Tüm sensör yollarında (rotation-vector, hibrit, web) geçerli.
0,1° ≈ 1–2 piksel altı; gözle görünmez. Eşikler `Cam` nesnesinde sabit; sorun olursa `dzOn` büyütülür ya da blok kaldırılır.

## Test
`node tools/gyroverify.test.js` genişletildi (THREE taklidiyle `Cam.update` gerçekten çalışır): hibrit eğim 30° → doğru quaternion,
yaw dokunmadan, yatış işareti, 0,02° değişim → quaternion oynamaz, 1° → oynar, oturunca sabit. `devprofile.test.js` `acc` sınıfıyla genişletildi.
Tüm testler geçiyor (`browser.test.js` orijinal pakette de işlem kapanmadığı için zaman aşımına düşüyor; 92 kontrol geçiyor).

## Doğrulanmadı
Java derlenmedi (yalnız sözdizimi taraması), cihazda denenmedi. Hibritte eksen işaretleri (özellikle yatay modda 90°/270° ekran
dönüşü) gerçek jiroskopsuz cihazda doğrulanmalı: yukarı bakınca görüntü yukarı kaymıyorsa `__nxNativeGrav` içindeki `pitch`
işaretini ters çevir. Hibrit yalnız ivmeölçerle çalıştığı için hızlı baş hareketinde kısa süreli sapma olur; yön her zaman parmakla ayarlanır.
