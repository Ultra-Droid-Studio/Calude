# Stage 71 — El çizimi düzeltmesi + modelin internetten inmesi

## El çizimi
- `#hd` canvas'ı `desynchronized:true` ile açılıyordu; şeffaf WebView + native kamera önizlemesi
  birlikteyken bazı cihazlarda bu düşük gecikmeli katman görünmez kalabiliyor. İki `getContext` çağrısından
  da kaldırıldı (`web/js/13-hand.js`).
- Eski kayıtlı "El çizimi kapalı" ayarı bir defalığına açılır (`Settings.v.hdraw2` bayrağı).
- Doğrulanmadı: gerçek cihazda denenmedi.

## Model APK'da değil, internetten
- `app/build.gradle`: `fetchHandModel` görevi kaldırıldı; `hand_landmarker.task` artık APK'ya girmez.
- `NativeCam.ensureModel()`: uygulama her açılışta modeli arka planda indirir
  (`filesDir/hand_landmarker.task`). İndirilemezse önceki açılıştan kalan kopya kullanılır.
- Model `setModelAssetBuffer` ile dosyadan yüklenir.
- İlk açılışta internet yoksa ve hiç kopya yoksa native el takibi kapalı kalır (eski Worker yolu da internet ister).
- Açtıktan birkaç saniye sonra el takibini aç: indirme bitmeden istenirse yedek yola düşer.
- Derleme yapılmadı; testler (`node tools/*.test.js`) geçti.

## Android pencere çubuğu (pil)
- Android (Shizuku) pencerelerinin altındaki çubuk uzatıldı (canvas 640 → 960 px, dik pencerede de sığar).
- Çubuğa **Dik/Yatay** düğmesi, **yukarı ok** ve **aşağı ok** eklendi (sol → sağ: Dik/Yatay, ↑, ↓, Klavye, Büyüt, Küçült, Kapat).
  Oklar uygulamayı kaydırır; basılı tutunca (bakış/çimdik beklemesiyle) tekrarlar.
- Pencerenin içindeki küçük yüzen Dik/Yatay ve ↑/↓ ikonları kaldırıldı; Geri ve "gerçek ekranda aç" ikonları pencerede kaldı.
- Dosyalar: `web/js/07-window-ui.js` (Pill), `web/js/16-launcher-shizuku.js`. Cihazda denenmedi.
- Test: `shizuku.test.js` içindeki "başlık çubuğunda Klavye düğmesi" Stage 67'den beri zaten başarısız, bu aşamayla ilgisi yok.
