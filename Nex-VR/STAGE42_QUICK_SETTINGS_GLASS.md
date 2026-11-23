# Stage 42 — Hızlı ayarlar: dock üstünde açılan cam menü

## İstek
Dock'taki saat/wifi/pil kapsülüne dokununca «Hızlı ayarlar» normal pencere olarak açılmasın; referans görseldeki gibi
(iOS Control Center düzeni) dokunulan yerin hemen üstünde açılan, camsı bir menü olsun. Her giriş yönteminde çalışsın.

## Değişiklikler
- `index.html`: yeni `QS` modülü (Library'nin yanında). Pencere değil; `WM.create` ile `chrome:false, kbd:true, skin:'qs'` bir panel.
  Dock'un kapsülünün tam üstüne konumlanır (`QS.pos`), dışarı dokunma / Escape / Library açma ile kapanır, kapsül açıp kapatır.
- `WM.paint`: `skin:'qs'` panelde pencere zemini çizilmez (menü kendi cam kartlarını çizer).
- Düzen: 4 bağlantı yuvarlağı (Uçak, Mobil veri, Wi-Fi, Bluetooth) · medya kartı (önceki/oynat-duraklat/sonraki, ses çıkışı) ·
  dönme kilidi · fener · ekran zaman aşımı · parlaklık ve ses dikey kaydırıcıları. Boyutlar tuval genişliğine (`W/1000`) orantılıdır.
- Cam görünümü (`QS.layer`, bir kez çizilip önbelleğe alınır): dış gölge, koyu buzlu zemin, bulanık ışık lekeleri, çapraz parlama,
  gren dokusu ve gradyanlı ince kenar. Hover/çimdik/bekleme (dwell) geri bildirimi mevcut `B()` sistemiyle çalışır.
- Kaydırıcılar 20 dilimdir: dokunma, çimdik, bakış-bekleme ve fare aynı şekilde seviye seçer.
- `MainActivity.java` köprüsü: `sysState`, `setVolume`, `setBrightness`, `setTorch`, `setKeepOn`, `setRotationLock`, `mediaKey`, `openPanel`.
  Manifest: `ACCESS_WIFI_STATE`.

## Gerçek işlev / sınırlar
| Öğe | Davranış |
|---|---|
| Ses, parlaklık | Doğrudan değiştirilir (parlaklık yalnızca bu uygulama penceresi için) |
| Fener | Arka kamera flaşı; kamera/el takibi meşgulse bazı cihazlarda açılamaz (uyarı çıkar) |
| Dönme kilidi | Uygulamanın yönünü kilitler / `sensorLandscape`'e döndürür |
| Ekran zaman aşımı | Ekranı açık tutma bayrağını açar/kapatır |
| Medya | Medya tuşu olayı gönderir (önceki/oynat-duraklat/sonraki). Parça adı/kapağı Android bildirim erişimi ister, eklenmedi |
| Wi-Fi, Bluetooth, Uçak, Mobil veri | Android 10+ uygulamaların bunları doğrudan açıp kapatmasını yasaklar. Durum canlı gösterilir; dokununca ilgili sistem paneli açılır |
| Ses çıkışı (AirPlay simgesi) | Sistem ses paneli |

## Cam efekti hakkında
Menü, 3B sahnede bir doku olarak çizildiğinden arkasındaki gerçek görüntüyü (kamera, sahne) piksel olarak bulanıklaştıramaz;
bulanıklık, kartların içine çizilen yumuşak ışık lekeleri + buzlu tint + gren ile **taklit edilir**.

## DOĞRULANMADI
Gerçek cihazda görülmedi, Java derlenmedi (bu ortamda javac yok). `node tools/qsmenu.test.js` sahte tuvalle çizimi, düğme
alanlarını ve köprü çağrılarını denetler. Boyut/konum için `QS.pos` (R:1.7, span:.3647, h:.645) ve `CARDS` tek yerden ayarlanır.
