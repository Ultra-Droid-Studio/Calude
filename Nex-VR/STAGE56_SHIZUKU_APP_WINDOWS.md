# Stage 56 — Shizuku ile Android uygulamalarını VR penceresinde açma (prototip)

## Ne yapar
Dock'tan / Library'den bir **Android uygulamasına** (ör. YouTube, Chrome, Minecraft) dokununca, uygulama gerçek ekranda
açılmak yerine uygulamanın ürettiği bir **VirtualDisplay** içinde açılır ve görüntüsü VR sahnesinde bir pencere olur.
Çimdik / bakış ile dokunma, sürükleme ve kaydırma uygulamaya gerçek dokunma olayı olarak gider.
Shizuku yoksa, izin verilmemişse veya uygulama yasak listesindeyse **eski davranış** (gerçek ekranda aç) korunur.

## Kullanıcı tarafı (bir kerelik)
1. Shizuku'yu kur ve başlat (Geliştirici seçenekleri → Kablosuz hata ayıklama → Shizuku'da "Eşle ve başlat").
2. Nex VR'da bir Android uygulamasına dokun → Shizuku izin penceresi çıkar → **İzin ver**. Uygulama kendiliğinden VR penceresinde açılır.
3. Kapatmak için: Lobi → Ayarlar → **Android uygulamaları VR penceresinde** anahtarı (varsayılan açık).
Pencere başlığında: **Geri** (BACK tuşu), yukarı/aşağı kaydır, **Normal ekranda aç**.

## Mimari
```
JS (AND.launch → SHZ.tryOpen → WM.spawn('shz:<paket>'))
  → AndroidBridge.shzOpen(id, paket, 1280, 720, 853)
      AppMirror: PUBLIC|OWN_CONTENT_ONLY VirtualDisplay + ImageReader  ─┐ kareler: JPEG → gpuFrame → __nxGpu → /_snap (GpuPage ile AYNI yol)
      ShizukuLink → ShellService (shell uid): am start --display <id> -n <bileşen>
  girdi: touchView / gazeInteractInView / scrollViewBy → AppMirror → ShellService → InputManager.injectInputEvent(displayId)
```
- `ShellService` (AIDL `IShellService`) Shizuku UserService olarak **shell yetkisiyle ayrı süreçte** çalışır.
- Pencere, mevcut web-uygulaması panel hattına `u.web={type:'shz'}` olarak bağlanır; `BF.gpu` kümesine eklenir, böylece boyutlandırma,
  kare boyama ve çimdik-dokunma yolları (Stage 26/27) **yeniden kullanılır**.

## Güvenlik
- Tüm yeni köprü yöntemleri oturum jetonu ister (`tokenOk`); iframe'deki siteler çağıramaz.
- AIDL'de keyfi komut YOK: yalnızca `launch`, `touch`, `key`, `swipe`, `stopPackage`. Bileşen/paket adları regex ile doğrulanır,
  komutlar argüman dizisiyle çalışır (kabuk dizesi birleştirme yok). `shzKey` yalnızca GERİ (4) kabul eder.
- Yasak liste (`ShizukuLink.DENY_PARTS`): banka/ödeme (bank, paypal, wallet, papara, garanti, ziraat, akbank, isbank…), Netflix/Disney/Prime/HBO
  vb., e-Devlet, sistem arayüzü, Nex VR ve Shizuku'nun kendisi → bunlar VR penceresinde AÇILMAZ, normal ekranda açılır.
  (`FLAG_SECURE` kullanan uygulamalar zaten siyah görünür.)

## Bilinen sınırlar
- **Derleme ve cihaz testi bu ortamda yapılmadı.** Java dosyaları yalnızca sözdizimi düzeyinde (jdk.compiler ile ayrıştırma) denetlendi;
  `node tools/shizuku.test.js` Java/AIDL/manifest/JS tutarlılığını denetler. İlk derlemede hata çıkarsa Gradle çıktısını paylaş.
- Kapatırken uygulama **force-stop** edilir: sanal ekran silinince görevleri gerçek ekrana taşınabildiği için önce durdurulur.
  Aynı uygulama normal ekranda da açıksa o da kapanır; açık oturum kaybolur.
- Görüntü JPEG ile akıtıldığı için ~30 kare/sn hedeflenir (Tab S6 Lite'ta oyunlarda gecikme beklenir).
- Pencere boyutlanınca (ilk açılıştan ~0,5 sn sonra, panel oranına göre) uygulama yeniden yapılandırılır; bazıları bir kez yeniden başlar.
- Klavye / yazı girişi yok (yalnızca dokunma, kaydırma, GERİ).
- Bazı uygulamalar ikinci ekranda açılmayı reddeder veya yeniden boyutlandırılamaz diye ana ekrana atlar. Deneme: PC'den
  `adb shell settings put global force_resizable_activities 1` (genel sistem ayarı; bu aşamada uygulama bunu kendisi DEĞİŞTİRMEZ).
- VirtualDisplay "güvenilir" (trusted) değil: IME ve sistem süslemeleri yok. Sonraki adım: ekranı Shizuku sürecinde oluşturmak.
- Ses normal hoparlörden çalar (VR sahnesine yönlendirme yok).

## Sorun giderme (logcat etiketleri)
`NEXUS-Shizuku` (bağlantı/izin), `NEXUS-Mirror` (sanal ekran, kare, başlatma). "uygulama sanal ekranda başlatılamadı" görürsen
bileşen adı ve display numarasıyla birlikte paylaş.

## Dosyalar
Yeni: `IShellService.aidl`, `ShellService.java`, `ShizukuLink.java`, `AppMirror.java`, `tools/shizuku.test.js`.
Değişen: `MainActivity.java` (köprü yöntemleri + mevcut yöntemlere yansıtma dalları), `AndroidManifest.xml`, `app/build.gradle`
(Shizuku 13.1.5, aidl, sürüm 1.7), `assets/index.html` (`SHZ`, `BF.get`, `WM.spawn`, `AND.launch`, lobi ayarı).
