# Stage 55 — VR modunda titreme / sıçrama düzeltmesi

## Belirti
Dock'taki VR düğmesiyle stereo VR açılınca sahne (özellikle dock) titriyor, oraya buraya sıçrıyordu.

## Kök nedenler (kaynak incelemesiyle bulundu)
1. **Gimbal kilidi:** Native sensör kodu, dönüşü `SensorManager.getOrientation()` Euler açılarıyla (azimut/pitch/roll) gönderiyordu. Telefon gözlükte dik durduğunda bu açılar tekil noktaya (±90°) yaklaşır; en küçük baş hareketinde açılar 180° sıçrar.
2. **Çift ekran-döndürme:** Java `remapCoordinateSystem` ile ekran döndürmesini uyguluyor, JS de `screen.orientation.angle` ile bir daha uyguluyordu.
3. **Euler sözleşmesi uyuşmazlığı:** Native açılar W3C `deviceorientation` (alpha/beta/gamma) sözleşmesine uymuyor, ama aynı `Cam.g` alanına yazılıyordu. Tarayıcının kendi `deviceorientation` olayı da çalışıyorsa iki kaynak birbirini ezip kamerayı gidip geliyordu.
4. **Düşük hız:** Native veri ~30 Hz ile sınırlıydı, çizim 60 fps; kare başına sabit `slerp(.2)` merdiven gibi takılma yapıyordu.
5. **Yedek sensör gürültüsü:** İvmeölçer + manyetometre yolunda süzgeç yoktu.

## Düzeltme
- Java artık **ekrana göre döndürülmüş 3x3 dönüş matrisini** gönderir (`window.__nxNativeMatrix`); Euler yok, gimbal kilidi yok. Ekran döndürmesi yalnızca Java'da uygulanır.
- JS matrisi quaternion'a çevirir (`Cam.nq`), ENU → three.js dönüşümünü `Cam.QM` ile yapar. Native veri geliyorsa **yalnızca o** kullanılır; tarayıcı `deviceorientation` yolu sadece yedektir.
- Yumuşatma kare hızından bağımsız (`1-exp(-dt*k)`); native yolda k=45 (düşük gecikme), eski yolda 14.
- Native hız sınırı 32 ms → 8 ms (~120 Hz tavan). Yedek sensörde ivmeölçer/manyetometreye düşük geçiren süzgeç eklendi.
- Native yön, VR başladığında/`Cam.reset()` çağrıldığında **bakılan yöne merkezlenir** (oyun rotasyon vektörünün yönü keyfî olduğundan dock arkada kalmasın diye).

## Doğrulanmayanlar
- Android derlemesi ve gerçek cihaz testi bu ortamda yapılmadı. Java değişikliği kaynak düzeyinde; derleme hatası çıkarsa logcat'i paylaşın.
- Matris zinciri sayısal olarak kontrol edildi (kuzeye bakış = birim, 90° sola bakış = Y'de +90°).
- Yedek (ivmeölçer + manyetometre) yolu hâlâ gerçek jiroskop kadar kararlı olmayabilir.
