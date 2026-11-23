# Stage 35 — MediaPipe Web Worker ayrıştırması

## Amaç
MediaPipe HandLandmarker modelinin yüklenmesi, WASM/GPU başlatması ve kare başına `detectForVideo` çıkarımının ana UI iş parçacığından çıkarılması.

## Uygulanan mimari
- `app/src/main/assets/mediapipe-worker.js` eklendi.
- MediaPipe kitaplığı, WASM çalışma zamanı ve `hand_landmarker.task` Worker içinde yüklenir.
- Worker önce IndexedDB'de önbelleğe alınmış dört yerel dosyayı kullanır; önbellek yoksa sürüm/ayna listesindeki çevrimiçi paketleri dener.
- GPU delegate önce, başarısız olursa CPU delegate denenir.
- Kamera akışı ana sayfada kalır. Kareler `createImageBitmap(video)` ile kopyalanıp transferable `ImageBitmap` olarak Worker'a aktarılır; kamera stream'i Worker'a verilmez.
- Worker aynı anda tek çıkarım yapar. Ana iş parçacığı `workerBusy` kilidiyle kare kuyruğunun birikmesini önler; yoğun cihazlarda eski kareler biriktirilmez.
- Landmark/handedness sonuçları ana iş parçacığına döner; mevcut slot eşleme, OneEuro filtreleri, çimdik, raycast, el çizimi ve etkileşim kodu değişmeden çalışır.
- Çıkarım süresi Worker tarafından ölçülür ve mevcut uyarlanabilir `iv` kare aralığı ayarlamasına aktarılır.
- Kamera kaybı/yeniden edinimi aynı Worker modelini korur; el takibi kapatıldığında Worker sonlandırılır ve bitmap kaynakları kapatılır.
- Yerel dosya indirme/IndexedDB önbelleği korunmuştur; MediaPipe kitaplığı artık ana thread'de import edilmez veya başlatılmaz.

## Değişen dosyalar
- `app/src/main/assets/index.html`
- `app/src/main/assets/mediapipe-worker.js`

## Doğrulama sınırı
Kaynak düzeyinde JavaScript sözdizimi ve mevcut Node testleri çalıştırılmalıdır. Android WebView üzerinde Worker + transferable ImageBitmap + MediaPipe GPU delegate davranışı fiziksel cihazda ayrıca doğrulanmalıdır. Bu değişiklik tek başına cihaz FPS artışı garantisi vermez; asıl faydası model/WASM/çıkarım yükünü UI thread'den ayırıp arayüzün takılmasını azaltmaktır.
