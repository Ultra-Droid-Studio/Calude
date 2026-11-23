# Stage 44 — MediaPipe Android'in kendi native kütüphanesinde (Web Worker / WASM yok)

## İstek
MediaPipe'yi Web Worker ve WebView'in içinden çıkar; Android native kütüphanesiyle çalıştır. Akıcı, hızlı, iki el ve parmaklar tam algılansın.

## Mimari
```
CameraX (native, en çok 60 fps)
  ├─ ImageAnalysis (RGBA 640x480, yalnızca EN TAZE kare) → MediaPipe HandLandmarker (LIVE_STREAM, GPU → CPU yedek)
  │        └─ sonuç → kompakt metin → WebMessagePort (yalnızca en son sonuç) → index.html `Hand.onNative` → mevcut `ingest`/Turbo el hattı
  └─ Preview → WebView'in ARKASINDAKİ PreviewView (kamera arka planı; WebView saydam, sayfa `html.npass` ile saydamlaşır)
```
- Yeni: `NativeCam.java`. `MainActivity`: `nativeCamAvailable / nativeCamStart / nativeCamStop` (oturum anahtarı ister), arkada `PreviewView`, saydam WebView, yaşam döngüsü (onPause/onResume/onDestroy/dönme).
- `build.gradle`: CameraX 1.3.4 + `com.google.mediapipe:tasks-vision:0.10.14`, `android.useAndroidX=true`, `fetchHandModel` görevi (`assets/hand_landmarker.task`, indirilemezse derleme durmaz), ABI: arm64-v8a + armeabi-v7a.
- Mesaj biçimi: `R|yaş_ms|çıkarım_ms|elSayısı|Etiket,skor,x,y,z,...` (el başına 21 nokta). `yaş_ms` = gerçek kamera yakalama → gönderim süresi; Turbo gecikme telafisi artık gerçek yaşı kullanır.
- Kare hızı: cihazın verdiği en yüksek (≤60) AE aralığı seçilir; düşük ışıkta 30'a inebilsin diye alt sınır düşük tutulur.
- Gecikme birikmez: `STRATEGY_KEEP_ONLY_LATEST` + tek iş parçacıklı çözümleyici + WebView'e giden her sonuç yalnızca en sonuncusudur.

## Otomatik geri düşüş (eski yol silinmedi)
Native yol şu durumlarda kullanılmaz ve eski Worker + getUserMedia yolu aynen çalışır: model APK'da yok, kamera izni yok, GPU **ve** CPU başlatma başarısız, kamera açılamadı, çalışırken hata, **VR-stereo (yan yana) modu** (native önizleme iki göze bölünemez). Stereo açılıp kapanınca doğru yola otomatik geçilir. Hata olursa bir uyarı gösterilir ve o oturumda native tekrar denenmez.

## Test
- `node tools/nativehand.test.js` (21 kontrol): mesaj biçimi, `Hand.onNative` ayrıştırma, `NHand.msg` yönlendirme; Java `num()` ile aynı biçimlendirme.
- Diğer testler değişmedi ve geçti (`browser.test.js` 92 kontrol geçer; süreç sonunda kapanmaması eskiden de vardı).

## DOĞRULANMADI (önemli)
Bu ortamda internet, Android SDK ve `javac` yok: **Java kodu derlenmedi, uygulama cihazda çalıştırılmadı.** İlk derlemede çıkabilecekler:
1. Sürüm adları: `tasks-vision:0.10.14`, CameraX `1.3.4` bulunamazsa `app/build.gradle` içindeki sürümü güncelle.
2. Saydam WebView + arkadaki PreviewView bazı cihazlarda titreyebilir; sorunda `PreviewView.ImplementationMode.COMPATIBLE` zaten seçili, `PERFORMANCE`'ı deneme.
3. Ekran 180° dönünce yön: `onRotation()` hedef dönüşü günceller; ters görürsen `NativeCam.analyze` içindeki `deg` kullanımına bak.
4. Landmark → ekran eşlemesi eskisi gibi (görüntü ekrana gerilir); önizleme `cover` kırpar. Bu fark Stage 43'te de vardı.
5. Ayarlar: tespit güveni `NHand.opts` içinde (0.42 / 0.45 lite).
