# Stage 65 — Otomatik sensör modu + "sensör gerçekten veri veriyor mu" kontrolü

## Sorun
- Sensör açıkken dokunmatik bakış kapanıyordu (`!Cam.gyro`). Sanal/ölü jiroskopta ya da hiç olay göndermeyen WebView'de
  ne sensör ne dokunma çalışıyor, kamera donuyordu; "Sensör açık" bildirimi de yanıltıcıydı.
- Hem WebView `deviceorientation` hem native sensör aynı anda dinleniyordu (aynı sensör iki kez).
- Cihazın hangi sensör yoluna sahip olduğu JS tarafına hiç bildirilmiyordu.

## Değişiklik
**Otomatik mod seçimi**
- `DeviceProfile.java`: `sensor` ("rv" rotation-vector · "am" ivmeölçer+pusula · "none") ve `gyro` (ham donanım jiroskobu var mı)
  alanları, `deviceProfile` JSON'unda. Saf kural: `DeviceProfile.sensorOf` (MainActivity'deki öncelikle aynı).
- JS `Dev.sensor` / `Dev.gyroHw`. `Cam.enableGyro()`:
  - Java "sensör yok" diyorsa (ve native yol yoksa) hiç denemez, dokunmatik bakışta kalır.
  - "am" sınıfında "Jiroskop yok: ivmeölçer+pusula modu (daha az hassas)" uyarısı verir.

**Veri doğrulama (1,8 sn)**
- Açılışta yerel + web yolu birlikte dinlenir; sonra:
  - yerel ≥2 örnek → **yerel** seçilir, web dinleyicisi kaldırılır (çift dinleme biter), Hz ölçülür (<15 Hz → "sanal olabilir" uyarısı);
  - yerel yok, web ≥1 olay → **web**, yerel dinleyici kapatılır (Chromium duran telefonda tek olay yollar, bu yüzden eşik 1);
  - hiçbiri yok → sensör kapanır, `Cam.dead=true`, dokunmatik bakışa dönülür ve uyarı çıkar.
- Doğrulanırken ve veri yokken dokunmatik bakış serbest (`Cam.gyroLive()`).
- Stereo VR başlarken ölü işaretli sensör tekrar denenmez; Hızlı ayarlardaki Sensör anahtarı elle yeniden dener.
- Performans penceresinde yeni "Sensör" satırı, Tanı'daki "Sensör modu" satırı durum + Hz gösterir.

## Test
`node tools/gyroverify.test.js` (yeni): `Cam` kaynaktan çıkarılıp sahte ortamda çalıştırılır; 7 senaryo
(sensör yok, yerel canlı, yalnız web, ölü sensör, duran telefon tek olay, doğrulama sırasında kapatma, "am" uyarısı).
`node tools/devprofile.test.js` sensör kuralıyla genişletildi. `autoq`, `shizuku`, `handsmooth`, `oneeuro` geçiyor.

## Doğrulanmadı
Java derlenmedi (bu ortamda Android SDK yok; yalnızca sözdizimi taraması yapıldı) ve cihazda denenmedi.
Gerçek cihazda Performans → "Sensör" satırına bak; sorun olursa `adb logcat -s NEXUS-Sensor` çıktısını gönder.
