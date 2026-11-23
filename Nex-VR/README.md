# NEXUS VR (Android)

WebView tabanlı VR masaüstü. Tek Activity + `assets/index.html` (Three.js, WebXR, MediaPipe el takibi).

## Cihazda test durumu
- **Samsung Galaxy Tab S6 Lite**: APK kuruldu, uygulama açıldı. Tarayıcı, Win7 simülasyonu ve VR sahnesi düzgün çalışıyor.
- El takibinde daha önce gözlemlenen donma büyük ölçüde geçti; şu an nadiren, çok hafif bir takılma oluyor (ciddi bir sorun değil).

## Derleme gereksinimleri
| Gereken | Sürüm |
|---|---|
| JDK | **17 veya 21** (Android Studio'nun kendi JBR'si de olur) |
| Android SDK | Platform **34** + Build-Tools **34.0.0** |
| Gradle | 8.7 (wrapper kendisi indirir) |
| İnternet | İlk derlemede bağımlılıklar ve `three.min.js` için |

### Android Studio ile
Klasörü açın → Gradle sync → **Build > Build APK(s)**. SDK ve JDK'yı Studio kendisi kurar.

### Komut satırı
```bash
cp local.properties.example local.properties   # sdk.dir yolunu düzenleyin
./gradlew assembleDebug                         # Windows: gradlew.bat assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```
SDK'yı komut satırından kurmak için:
```bash
sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"
sdkmanager --licenses
```

### Bilgisayarsız / SDK'sız
Projeyi GitHub'a yükleyin; `.github/workflows/build.yml` APK'yı otomatik derler (Actions > Artifacts).

## Güvenlik özeti
- `AndroidBridge` artık oturuma özel rastgele anahtar ister; iframe'deki siteler uygulama listesine erişemez / uygulama başlatamaz.
- Kamera/mikrofon izni yalnızca uygulamanın kendi sayfasına verilir.
- Düz HTTP kapalı (arayüz `http://` adresleri `https://`'e çevirir), karma içerik kısıtlı, dosya/content erişimi kapalı, Safe Browsing açık, SSL hataları reddedilir.
- Proxy: yerel/özel ağ adresleri engelli, yalnızca `X-Frame-Options` ve CSP `frame-ancestors` kaldırılır, `X-Requested-With` sızdırılmaz.
- Ana çerçeve uygulama sayfası dışına gidemez; `index.html` iframe içinde gömülemez.
- Release build hâlâ debug imzalı: yayın için kendi keystore'unuzu ekleyin.

## Mobile hand-tracking performance
- Camera input is capped at 320×240 / 30 FPS on phones and tablets.
- MediaPipe still tracks up to two hands; inference cadence adapts to measured processing time.
- Hand drawing skips costly shadow, crease, and microtexture effects on handheld devices.
- WebGL antialiasing is disabled on handhelds and pixel ratio is capped lower to reduce GPU load.

## Hand model appearance and latency
- Rendered hand and forearm are semi-transparent.
- (Stage 39) Anında el modu varsayılan: ileri tahmin yok, ham ölçüm hemen çizilir.

## Quest 3 arayüzü
- Dock: koyu kapsül, solda avatar / saat-wifi-pil kapsülü (dokununca **Hızlı ayarlar**) / zil (Tanı) / VR halkası; ortada yuvarlatılmış kare uygulama ikonları, sağda Library düğmesi, altında tutma çubuğu. Dock göze doğru hafif eğik durur.
- Pencereler: Quest'in koyu petrol rengi, başlık üstte ortada, küçült ve kapat sağ üstte, hafif kavisli; "Ön yay" düzeninde yan yana, alt kenarları dock'un üstünde dizilir.
- Library: sol menü (Ara / Uygulamalar / Dünyalar), 3 sütunlu yatay kartlar, "Tümü" ve "Son kullanılan" açılır kutuları, dikey kaydırma.
- Klavye: koyu, yuvarlak tuşlu, mavi Enter; dock'un hemen altında, göze doğru eğik açıyla açılır; dock gizlenmez.
- El / Sensör / VR / Kamera / Düzen / Sıfırla düğmeleri **Hızlı ayarlar** penceresine taşındı (dock'taki saat kapsülüne dokun).

## Son değişiklikler (el, sinema, tarayıcı)
- El: parmaklar boğum boğum incelen, avuç + bilek çokgenli gerçek el silüeti. Dış katman siyah, iç kısım tamamen şeffaf (kamera/arka plan görünür). Çimdikte iki uç parlar. Çıkarım hızı cihaz yüküne göre ayarlanır, sayfa gizliyken ve el yokken seyreltilir.
- Sinema: koltuklar yumuşak kenarlı (köşe renkleriyle gölgelendirilmiş) ve tek geometride birleştirildi (tek çizim çağrısı). Halı/duvar dokuları önbelleğe alındı. Perde gerçek beyaz perde + siyah maskeleme çerçevesi; video yokken beyaz, oynarken siyah zemin.
- Tarayıcı: Quest tarayıcısı gibi sekme şeridi, geri/yenile/adres çubuğu/mikrofon/yer imi/menü. Yer imleri başlangıç sayfasına eklenir. Pencere başlık bandı koyulaştırıldı; renkler ve dock aynı.
- Sinema perdesi 16:9 ve küçültüldü (≈5,4×3 m), göz hizasının üstüne alındı; alt kısmı koltuklarla kapanmaz. Oynarken panel şeffaf, video doğrudan GPU dokusundan (VideoTexture) gelir; yalnızca yeni karede yüklenir. Oynatırken toz efekti durur, el algılama seyrekleşir.


## Stage 64b
Hata taraması düzeltmeleri: `STAGE64B_BUGFIX.md`.


## Stage 16 scroll fix
Normal browser up/down controls target the real browser WebView; URL-based web app panels now have their own up/down controls. See `STAGE16_SCROLL_FIX.md`.


## Stage 17 GORILLA RUN çekirdeği
Dock'ta **Goril** simgesi; dokunmatik test modunda iki elle itiş/tırmanma fiziği. Ayrıntı ve açık eksikler: `STAGE17_GORILLA_CORE.md`.


## Stage 18 Orman kanyonu + gerçek el kontrolü + VR
Özgün low-poly orman kanyonu haritası, gorilla modeli, kamera ile gerçek el takibi (yumruk = tut), WebXR denetleyici desteği ve otomatik kalite. Ayrıntı ve açık eksikler: `STAGE18_FOREST_CANYON.md`.


## Stage 20 Tarayıcı
Çoklu sekme (en çok 5), yer imi listesi (200), geçmiş (100), reklam engelleyici ve PC sürümü; menü (⋮) ve PhoneXR tarzı başlangıç sayfası (Favoriler / Yer imleri / Geçmiş / Ayarlar). Ayrıntı ve açık eksikler: `STAGE20_BROWSER.md`. Test: `node tools/browser.test.js`.


## Stage 21 One Euro düzeltmesi
El imleci ve iskelet süzgeci artık gerçekten hıza uyum sağlıyor (hız el boyuna göre ölçülüyor), `NaN`/zaman boşluğu hataları giderildi. Ayrıntı, ölçümler ve açık eksikler: `STAGE21_ONE_EURO.md`. Test: `node tools/oneeuro.test.js`.


## Stage 22 Sinema odaları
Sinemada **Oda** düğmesiyle Salon / Roblox evi / Gün batımı / Gece / Uzay / Stüdyo / Brawl arena seçilir (`GLBRoom` yükleyici, `roblox_house.glb`). Ayrıntı ve açık eksikler: `STAGE22_ROOMS.md`. Test: `node tools/glbroom.test.js`, `node tools/envsky.test.js`.


## Stage 23 Pencere çubuğu, cam TR klavye, el menüsü
Her pencerenin altında Quest/PhoneXR tarzı hap (başlık sürükle + klavye/büyüt/küçült/kapat), cam görünümlü Türkçe klavye (mavi Enter, ?123 sembol katmanı) ve avuç yüze dönükken açılan el menüsü. Ayrıntı ve açık eksikler: `STAGE23_WINDOW_HAND.md`. Test: `node tools/winhand.test.js`.


## Stage 25 El çizimi performans optimizasyonu
Parmaklar artık ayrı ayrı değil TEK path + TEK stroke() ile (hepsi aynı ortalama genişlikte) çiziliyor; her karede yeni dizi ayırma (hem landmark koordinatları hem avuç çokgeni) kaldırılıp önceden ayrılmış (preallocated) dizilerle değiştirildi. Elde başına canvas çizim çağrısı 48 → **7 (masaüstü) / 5 (mobil)** oldu (~%85-90 azalma). Algılama tarafı (MediaPipe modeli, GPU delegate, kamera limitleri, OneEuro) PhoneXR referans projesiyle karşılaştırıldı ve zaten aynı/doğru desenlerde olduğu görüldü, değiştirilmedi. Ayrıntı: `STAGE25_HAND_PERFORMANCE.md`. Test: `node tools/handpaint.test.js`.


## Stage 26 Windows 7 (VR): netlik, ölçek, el kontrolü
Win7 dokusu artık doğrudan WebView anlık görüntüsünden (1600×686, değişmeyen karede yük yok), arayüz masaüstü boyutlu (CSS 1280) görünüm alanında çalışır, çimdikle pencere sürükleme/tıklama/kaydırma yapılır ve içerideki tarayıcı WebView'leri görüntüye birleştirilir. Ayrıca tüm panellerde düz düğmeler çimdikle tıklanır. Ayrıntı ve açık eksikler: `STAGE26_WIN7_VR.md`. Test: `node tools/w7touch.test.js`.


## Stage 27 GPU tarayıcı
Tarayıcı artık ana ekrana eklenmeyen bir VirtualDisplay içinde (gerçek GPU penceresinde) çalışır; video açılır, pencere dışına taşmaz, kareler arka planda sıkıştırılıp itilir. Win7, oyunlar ve web uygulamaları değişmedi. Ayrıntı ve açık eksikler: `STAGE27_GPU_BROWSER.md`. Test: `node tools/gpubrowser.test.js`.


## Stage 30 iOS ikon teması
Sistem uygulamaları ve web uygulamaları iOS tarzı ikon temasına geçti (11 çizim: Tarayıcı, App Store, Instagram, Discord, Android, YouTube, GitHub, Spotify, WhatsApp, SoundCloud, Vikipedi; diğerleri kendi renk/glifiyle). Katalogda eksik olan **Instagram** ve **SoundCloud** eklendi (26 → 28). Ayrıntı: `STAGE30_ICON_THEME.md`. Test: `node tools/icontheme.test.js`.

## Stage 31 Kısayol çakışması düzeltmesi
«VR başlatılamadı (pcol / length)» hatası giderildi: tarayıcı kısayolları dock sabitlemeleriyle aynı `pins` anahtarını paylaşıyordu; artık `bpins` kullanıyor, eski ayarlar otomatik taşınır. Ayrıntı: `STAGE31_PINS_FIX.md`. Test: `node tools/browser.test.js`.

## Stage 32 App Store
Yeni **App Store** uygulaması: sol menüde bölümler (Öne Çıkan, Tümü, 6 kategori, Yüklenenler, Ara), 40 web uygulaması, **AL** düğmesiyle indirme. İndirmeden önce ve ilk açılışa kadar harf ikonu; **ilk açılışta sitenin kendi ikonu** çekilip uygulamanın ikonu olur (`AndroidBridge.fetchIcon`). App Store ikonu Uygulamalarım'dan buraya taşındı. Ayrıntı ve açık eksikler: `STAGE32_APPSTORE.md`. Test: `node tools/appstore.test.js`.

## Stage 34 Açılış başlatıcı sahnesi
Uygulama açılınca **Nexus VR** başlatıcı sahnesi gelir: Başlat, Ayarlar, Kalibrasyon, VR Ayarları, **El Takibi** anahtarı, Hakkında, Çıkış, Hızlı Erişim ve Tema çalışır; eller açıkken çimdik tıklama yapar. Ayrıntı ve açık eksikler: `STAGE34_LOBBY.md`. Test: `node tools/lobby.test.js`.

## Stage 38 Kamera 60 FPS
Kamera artık cihazın verebildiği en yüksek hızda (en çok 60 fps) açılır; mobilde 20-24 fps sınırı kaldırıldı, çıkarım aralığı gerçek kamera fps değerine göre ayarlanır. Ayrıntı: `STAGE38_CAMERA_60FPS.md`.

## Stage 39-40 Anında el + Quest tarzı el modeli + Kamera kalitesi ayarı
El takibi artık tahminsiz ve ara değerlemesiz: yeni ölçüm gelir gelmez el ve imleç ölçülen konuma oturur, çıkarım kare aralığı sınırı yok (Worker boşalınca hemen yeni kare). Ayar: **Anında el (ham veri, tahminsiz)**, varsayılan açık. El modeli Quest benzeri yarı saydam gri-mavi, parlak kenarlı, uca doğru incelen parmaklı ve solan ön kollu çizilir. Ayrıntı: `STAGE39_INSTANT_HAND_QUEST_MODEL.md`.

## Stage 41 Minimalist arayüz
Dock, Library ve pencereler Quest tarzı sade/koyu görünüme geçti; Library ortada başlık+arama, solda menü, 5 sütun kare ikon, sağda Filtre/Sırala. Ayrıntı: `STAGE41_MINIMAL_UI.md`.

## Stage 42 Hızlı ayarlar cam menüsü
Dock'taki saat kapsülü artık pencere değil, kapsülün üstünde açılan iOS Control Center düzeninde cam bir menü açar (ses, parlaklık, fener, dönme kilidi, ekran açık tut, medya tuşları, Wi-Fi/Bluetooth/Uçak/Veri durumu). Ayrıntı ve sınırlar: `STAGE42_QUICK_SETTINGS_GLASS.md`. Test: `node tools/qsmenu.test.js`.

## Stage 44 MediaPipe native
MediaPipe artık Web Worker/WASM yerine Android'in kendi native kütüphanesinde (CameraX + HandLandmarker GPU) çalışır; kamera arka planı da native önizlemedir. Native açılamazsa eski Worker yolu otomatik devreye girer. Ayrıntı ve doğrulanmamış noktalar: `STAGE44_NATIVE_MEDIAPIPE.md`. Test: `node tools/nativehand.test.js`.

## Stage 45 Native el gecikme/takılma düzeltmesi
Hassas yakalama zamanı (saat farkı kestirimi), UI iş parçacığından bağımsız gönderim, ack'li akış denetimi (JS takılınca eski sonuçlar birikmez), meşgulken kare atlama, kamera ISP gecikmesini azaltma, thread önceliği. Ayrıntı ve doğrulanmamış noktalar: `STAGE45_NATIVE_LATENCY.md`. Test: `node tools/nativehand.test.js`.

## Stage 46 Yeni duvar kağıtları
4 düz gradyan yerine 11 yerleşik 360° duvar kağıdı: Gün batımı, Gece, Aurora, Okyanus, Derin uzay, Nebula, Samanyolu, Gezegen, Kara delik, Neon, Dünya. Dosyasız, canvas ile çizilir; Ayarlar → Görünüm'de gerçek önizlemeli galeri. Ayrıntı: `STAGE46_WALLPAPERS.md`.

## Minecraft texture update (Stage 51)
The Minecraft 3D place now loads the user-provided terrain atlas and villager, pig, and zombie texture crops from `app/src/main/assets/minecraft/`. These are used by the in-world materials; the app's wider UI and VR controls are unchanged. See `STAGE51_MINECRAFT_USER_TEXTURES.md`.


## Stage 52 — Native el takibi yük dengeleme
Hafif cihazlarda MediaPipe analizini 320×240 / 30 Hz, standart profilde 480×360 / 40 Hz ile sınırlar. Ayrıntı: `STAGE52_NATIVE_HAND_LOAD_BALANCE.md`.

## Stage 53 — Reference-style hand outline

The live 2D hand overlay now uses a smooth white/lilac outer contour similar to the supplied reference image, with a compact circular finger-count badge. See `STAGE53_REFERENCE_HAND_OUTLINE.md`. The MediaPipe model and inference pipeline were not replaced; only the visualization layer changed.

## Stage 55 — VR modunda titreme düzeltmesi
Stereo VR'da sahnenin/dock'un titremesi ve sıçraması giderildi: yön sensörü artık Euler açıları yerine dönüş matrisiyle (gimbal kilidi yok), tek kaynaktan ve daha yüksek hızda geliyor. Ayrıntı ve doğrulanmayanlar: `STAGE55_VR_JITTER_FIX.md`.

## Stage 56 — Shizuku ile Android uygulamaları VR penceresinde (prototip)
Shizuku çalışıyor ve izin verilmişse dock/Library'deki Android uygulamaları gerçek ekranda değil, uygulamanın açtığı sanal ekranda (VirtualDisplay) açılır; görüntü VR penceresine akar, çimdik/bakış dokunma ve kaydırma uygulamaya gerçek dokunma olarak gider. Banka/ödeme/Netflix gibi uygulamalar yasak listesindedir (normal ekranda açılır). Derleme ve cihaz testi yapılmadı. Ayrıntı ve sınırlar: `STAGE56_SHIZUKU_APP_WINDOWS.md`. Test: `node tools/shizuku.test.js`.

## Stage 57 — Shizuku: klavye + sağlamlaştırma
Android uygulama pencerelerine canlı klavye (pencere çubuğundaki **Klavye** düğmesi), tuş beyaz listesi, açılışta yeniden deneme / servis sürüm denetimi / zaman aşımı / otomatik yeniden bağlanma, kapanış yarışı düzeltmesi ve açılamayan uygulamalar için net neden mesajları. Cihazda denenmeyenler ve bilinen sınırlar: `STAGE57_SHIZUKU_KEYBOARD_HARDENING.md`. Test: `node tools/shizuku.test.js`.

## Stage 58 — Güvenilir sanal ekran
Android uygulamaları artık Shizuku üzerinden güvenilir (trusted) sanal ekranda açılır: dosya seçici ve başlatıcının açtığı uygulamalar gerçek ekrana kaçmaz. Açılamazsa eski yola düşer. Ayrıntı ve doğrulanmamış noktalar: `STAGE58_TRUSTED_DISPLAY.md`. Test: `node tools/shizuku.test.js`.

## Stage 59 — Telefon profili
Telefonlarda Android uygulama pencereleri daha düşük çözünürlük, daha seyrek/hafif kare ve en çok 2 pencere ile çalışır. Ayrıntı: `STAGE59_PHONE_PROFILE.md`.

## Stage 60 — Dış üst çubuk + Dik/Yatay mod
Android uygulama pencerelerinde çubuk pencerenin dışında üstte, uygulama tam boy; çubuktan Dik/Yatay mod seçilir. Ayrıntı: `STAGE59_PHONE_PROFILE.md`.

## Stage 61 — Otomatik kalite / VR / el takibi
Telefonda VR ve el takibi açılınca çözünürlüğün aşırı düşmesi düzeltildi; otomatik çözünürlük akıllandı. Ayrıntı: `STAGE59_PHONE_PROFILE.md`. Test: `node tools/autoq.test.js`.

## Stage 62 — Çok akıcı el takibi
Simülasyonla ayarlı ölü bölgeli süzgeç (duran el titremesi ≈ −%56), daha yumuşak çizim, hızlı cihazda ≈60 Hz'e uyarlanır çıkarım ve termal denetim. Ayrıntı: `STAGE62_SMOOTH_HAND.md`. Test: `node tools/handsmooth.test.js`.


## Stage 63 — Telefon/tablet sınıfı + performans seviyesi
Cihaz artık telefon/tablet ve düşük/orta/yüksek seviye olarak ölçülür (`DeviceProfile.java`); render bütçesi, el takibi profili, kalite varsayılanı, yenileme hızı, uygulama penceresi sayısı ve sanal ekran boyutu buna göre ayarlanır. Orta seviye (Tab S6 Lite) davranışı değişmedi. Ayrıntı ve doğrulanmamış noktalar: `STAGE63_DEVICE_CLASS_TIER.md`. Test: `node tools/devprofile.test.js`.

## Stage 64 — Grafik ayarları elle + Android pencere pill'i
Android uygulama pencerelerine de normal pencerelerdeki alt pill geldi; sınıf/seviyeye göre pencere sınırı kaldırıldı. Ayarlar → Grafik'ten El takibi profili, Kenar yumuşatma, Piksel bütçesi, Yenileme hızı ve Android pencere sayısı elle ayarlanır (varsayılan Otomatik). Ayrıntı ve doğrulanmamış noktalar: `STAGE64_GRAPHICS_SETTINGS.md`.

## Stage 65
Otomatik sensör modu + sensörün gerçekten veri verip vermediği kontrolü (sanal/ölü jiroskopta dokunmatik bakışa otomatik dönüş): `STAGE65_SENSOR_AUTO_VERIFY.md`. Test: `node tools/gyroverify.test.js`.

## Stage 66
Hibrit mod (jiroskopsuz cihazlarda eğim ivmeölçerden, yön dokunmayla) + ölü bölge (sensör gürültüsü artık yeniden çizim tetiklemez): `STAGE66_HYBRID_DEADZONE.md`. Test: `node tools/gyroverify.test.js`.
