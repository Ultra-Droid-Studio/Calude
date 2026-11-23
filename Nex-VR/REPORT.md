# NEXUS VR — Gaze-control implementation report

## 7. Bakışla WebView etkileşimi — 3. aşama

- `gazeInteractAt()` eklendi. Merkez bakış noktası üstteki görünür gömülü WebView alanına denk gelirse etkileşim Android UI kuyruğuna aktarılır.
- WebView alanının üst kenarına bakışla bekleme, sayfayı yukarı; alt kenarına bakışla bekleme, sayfayı aşağı kaydırır. İç bölgede bekleme normal `ACTION_DOWN`/`ACTION_UP` dokunuşu üretir; bağlantılar, düğmeler ve form alanları WebView tarafından işlenir.
- Yöntem mevcut token doğrulamasını kullanır ve ana uygulamanın birincil WebView'ini hedeflemez; üstten alta değil, en üstteki görünür çocuk WebView seçilir.
- Bu aşamada baş hareketiyle WebView üzerinde sürekli sürükleme/serbest kaydırma ve gerçek WebXR/stereo içindeki yerel WebView katmanları tamamlanmış sayılmaz. Android derlemesi ve fiziksel cihaz testi bu ortamda yapılmadı.


## 7. Aşama 4 — gerçek bakış koordinatını WebView'e iletme

- Önceki aşamada WebView etkileşimi sabit ekran merkezine gönderiliyordu. Bu aşamada Three.js raycast sonucundaki `h.point`, kamera izdüşümüyle ekran koordinatına çevrilir.
- Ekran koordinatları `devicePixelRatio` ile Android overlay'in kullandığı fiziksel piksel ölçeğine dönüştürülür.
- Etkileşim yalnızca izdüşüm görünür viewport sınırları içindeyse gönderilir; token doğrulaması ve üstteki görünür WebView seçimi korunur.
- JavaScript sözdizimi ve ZIP bütünlüğü kontrol edilebilir; Android derlemesi ve gerçek cihaz testi bu ortamda doğrulanmadı.


## 8. Aşama 5 — stereo modda panel içi bakış etkileşimi

- Stereo modunda gizlenen yerel WebView katmanına, paneldeki bakış konumunu normalize edilmiş koordinatlarla aktarmak için `gazeInteractInView()` eklendi. Normal moddaki `gazeInteractAt()` yolu korunur.
- `prepareGazeView()` gizli WebView'i içerik çözünürlüğünde tutar ve sayfanın duraklatılmasını önler; bu sayede stereo görüntüdeki panel yüzeyine bakarak dokunma/kaydırma olayının arka plandaki WebView'e iletilmesi hedeflenir.
- WebView boyutu değişmedikçe hazırlama çağrısı tekrarlanmaz; her karede Android UI kuyruğuna gereksiz iş yollanmasını engellemek için boyut önbelleği eklendi.
- HTML içindeki JavaScript blokları `node --check` ile doğrulandı. Android Gradle derlemesi, VR gözlüğü ve gerçek cihaz testi bu ortamda çalıştırılmadı; bu nedenle stereo etkileşim henüz cihaz üzerinde doğrulanmış kabul edilmemeli.


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
