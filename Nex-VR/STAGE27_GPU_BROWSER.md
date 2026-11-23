# Stage 27 — GPU tarayıcı (video, çökme ve pencere dışına taşma düzeltmesi)

## Sorun
Tarayıcı WebView'i görünmez ana ekran görünümünde tutulup `View.draw()` ile bitmap'e alınıyordu (800×500, JPEG 52).
`draw()` videoyu (ayrı GPU katmanı) yakalayamaz, WebView ekranda asılı kalabilir ve her kare ana iş parçacığını yorar.

## Çözüm (yalnızca `nexus-browser`)
Tarayıcı artık uygulamaya ait özel bir **VirtualDisplay** içinde, gerçek GPU hızlandırmalı bir `Presentation` penceresinde çalışır
(PhoneXR'ın kullandığı Android API deseni; kod kopyalanmadı, sıfırdan yazıldı). Kareler `ImageReader` ile alınır,
**arka plan iş parçacığında** JPEG'e sıkıştırılır ve sayfaya **itilir** (poll yok, ~25 kare/sn sınırı, meşgulken en yeni kare kazanır).
- Video / WebGL / CSS katmanları gerçek ekrandaki gibi çizilir.
- WebView ana ekrana hiç eklenmez → pencerenin dışına çıkamaz, ekranda asılı kalamaz.
- El çimdiği ve bakış girdisi aynı `touchView` / `gazeInteractInView` yolundan gider (WebView `childViews` içinde).
- Çözünürlük panele göre (içeriğin ~1.25 katı, ≤1600×1000), CSS genişliği tablet düzeni (≈853; PC sürümünde 1280).
- Gizlenince WebView duraklatılır, son kare korunur (yeniden gösterimde boş kalmaz).
- Render süreci ölürse tarayıcı sıfırlanır ve bir sonraki açışta yeniden oluşturulur (uygulama kapanmaz).

## Dokunulmayanlar (kasıtlı)
Win7 (ve içindeki tarayıcılar), `win7simu.html`, `Win7Activity`, web uygulamaları, oyunlar ve dock eski yolda aynen kalır.
GPU yolu kurulamazsa (`GpuPage.open` null) otomatik eski yola düşülür. Ayarlar → «GPU tarayıcı (video, deneysel)» ile kapatılabilir
(tarayıcı kapatılıp açılınca geçerli olur).

## Dosyalar
`GpuPage.java` (yeni) · `MainActivity.java` (gpuPages, create/destroy/setRect2/prepareGazeView kancaları, isGpu/setGpu/gpuSize) ·
`index.html` (BF: gpu, gpuFrame, gpuSize, gpuPaint; Ayarlar anahtarı) · test: `node tools/gpubrowser.test.js` (32 kontrol).

## DOĞRULANMADI / AÇIK EKSİKLER
- **Java derlenmedi, cihazda denenmedi** (bu ortamda javac/Android SDK/cihaz yok); yalnızca parantez dengesi ve JS testleri yapıldı.
  Derleme hatası çıkarsa hata metnini gönderin.
- Kare sayfaya hâlâ JPEG ile taşınır (Three.js, WebView içinde olduğu için Android GL dokusunu doğrudan alamaz). Yüksek çözünürlüklü
  video akıcılığı cihaza bağlı; kasarsa `MIN_GAP_MS` (GpuPage.java) artırılabilir veya `QUALITY` düşürülebilir.
- Bazı cihazlarda ImageReader satır dolgusu (stride) farklı olabilir; kod bunu karşılar ama gerçek cihazda görülmedi.
- Tam ekran video düğmesi çalışmaz (`onShowCustomView` yok). DRM'li (Netflix vb.) içerik oynamaz.
- Sayfa içi metin alanlarına VR klavyesiyle yazma bu aşamada yok (önceki aşamalardaki gibi).
- Web uygulamaları da GPU yoluna alınabilir (`MainActivity.create` içindeki `wantGpu` koşulu); riskten kaçınmak için şimdilik yalnızca tarayıcı.
