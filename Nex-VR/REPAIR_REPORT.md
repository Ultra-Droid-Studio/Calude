# NEXUS VR — Kaynak İnceleme ve Düzeltme Raporu

## 1. Bulgular ve kök nedenler

- **Windows 7 paneli için WebView yaşam döngüsü:** `index.html` içindeki `WM.close()` pencere mesh'ini kaldırıyor, fakat `BF` tarafından oluşturulan yerel Android WebView katmanını serbest bırakmıyordu. Bu, pencere kapandıktan sonra eski WebView katmanının ekranda kalmasına ve yeniden açılışta eski örneğin yeniden kullanılmasına yol açabilecek gerçek bir kaynak/yaşam döngüsü hatasıdır.
- **Windows 7 içindeki alt WebView kimlikleri:** `win7simu.html` iframe shim'i her simülatör örneğinde `f1`, `f2` gibi yerel kimlikler üretirken Android tarafındaki `childViews` haritası ortaktı. Kimlikler ana simülatör örneğiyle kapsamlandırılmadığından birden fazla web uygulaması/simülatör alt görünümü arasında çakışma riski vardı.
- **WebView ölçeklendirme:** Ana WebView, gömülü web uygulamaları ve eski `Win7Activity` `setLoadWithOverviewMode(true)` kullanıyordu. Bu ayar viewport meta etiketine ek olarak tüm sayfayı genel olarak sığdırmaya çalışabilir. Responsive sayfaların kendi viewport düzenini koruması için overview mode kapatıldı ve metin yakınlaştırması açıkça %100'e sabitlendi.
- **Çalışma zamanı teşhisi:** Alt WebView oluşturma hataları sessizce yutuluyordu; JavaScript konsol hataları, ana çerçeve yükleme hataları ve renderer kapanması yeterince görünür değildi. Bu durum kök nedeni cihazda teşhis etmeyi zorlaştırıyordu. Logcat kayıtları ve Windows 7 ana çerçevesi için tekrar deneme ekranı eklendi.
- **VR dünya koordinatları:** `Cam.update()` kamera/rig yönelimini güncelliyor; `WM.place()` ise pencere mesh'inin dünya konumunu yalnızca pencere oluşturma/düzenleme işlemlerinde ayarlıyor. Kaynak kodunda baş hareketi başına world-locked pencereleri kameranın önüne taşıyan bir işlem bulunmadı. Bu nedenle bu aşamada koordinat sistemi keyfî biçimde yeniden yazılmadı; gerçek cihazda ölçüm olmadan geometri sorunu çözüldü denemez.
- **El takibi (bu raporun ilk yazıldığı aşama):** O tarihte `Hand.tick()` içindeki MediaPipe çıkarımı ana iş parçacığında senkron çalışıyordu. Bu durum Stage 35'te giderildi: model/WASM başlatması ve `detectForVideo` artık `mediapipe-worker.js` içinde çalışır; ana sayfa yalnızca aktarılabilir kareleri gönderir ve landmark sonuçlarını işler. Fiziksel cihaz doğrulaması Stage 35 raporunda ayrıca belirtilmiştir.

## 2. Değiştirilen dosyalar

- `app/src/main/java/com/nexus/vr/MainActivity.java`
  - Responsive viewport ayarları düzeltildi (`setLoadWithOverviewMode(false)`, `setTextZoom(100)`).
  - Ana/alt WebView yükleme ve JavaScript konsol hataları Logcat'e kaydediliyor.
  - Windows 7 alt WebView ana çerçeve yüklemesi başarısız olursa tekrar deneme ekranı gösteriliyor.
  - Alt WebView renderer kapanması yakalanıp ilgili görünüm temizleniyor.
  - Windows 7 içindeki alt WebView kimlikleri ana simülatör ID'siyle kapsamlandırıldı.
  - Bir simülatör/uygulama WebView'i yok edilirken ona bağlı alt WebView'ler de temizleniyor.
- `app/src/main/java/com/nexus/vr/Win7Activity.java`
  - Viewport ölçeklendirmesi düzeltildi.
  - Eski Activity yolu kullanılırsa yükleme ve JavaScript hataları Logcat'e yazılıyor; ana çerçeve yükleme hatasında tekrar deneme ekranı var.
- `app/src/main/assets/index.html`
  - Web uygulaması paneli kapatıldığında yerel WebView ve alt kaynakları da bırakılıyor; yeniden açma yeni bir WebView oluşturabiliyor.

## 3. Test sonuçları

- `index.html` ve `win7simu.html` içindeki satır içi JavaScript blokları `node --check` ile kontrol edildi: **başarılı**.
- Projedeki XML dosyaları XML parser ile kontrol edildi: **başarılı**.
- Üretilen ZIP arşivinin bütünlük kontrolü: **başarılı**.
- Android derlemesi **çalıştırılamadı**. `./gradlew assembleDebug --no-daemon` wrapper JAR'ını `raw.githubusercontent.com` adresinden indirmeye çalıştı ancak ortam DNS/ağ hatası nedeniyle `Could not resolve host` verdi. Bu çalışma ortamında kullanılabilir `android.jar`/Android SDK veya sistem Gradle kurulumu da bulunamadı.
- Android cihaz/Logcat testi yapılmadı. Bu yüzden Windows 7 açılışı, YouTube görünümü, VR baş takibi ve gerçek cihaz FPS'i cihaz üzerinde doğrulanmış sayılmaz.

## 4. Kalan doğrulamalar

- AndroidIDE veya Android Studio'da internet/Gradle wrapper erişimi olan ortamda `./gradlew assembleDebug` çalıştırılmalı.
- Cihazda Windows 7 panelini art arda aç/kapat ve Logcat'te `NEXUS-WebView`, `NEXUS-JS` kayıtlarını incele.
- YouTube ve farklı responsive siteler tablet üzerinde kontrol edilmeli.
- VR baş takibi sırasında panelin dünya konumu ve boyutu ölçülmeli. Native WebView overlay'leri VR oturumunda gizlendiğinden, web içeriğinin gerçek WebXR sahnesinde gösterimi ayrıca test edilmelidir.
- El takibi performansı cihaz üzerinde ölçülmedi; MediaPipe çıkarımının ana iş parçacığında çalışması devam eden bir performans sınırıdır.

## 5. Teslim sınırı

Bu ZIP, kaynak kod düzeltmelerini içerir; APK içermez. Derleme ve fiziksel cihaz testi yapılmadığından, yalnızca kaynak düzeyindeki kontroller başarıyla tamamlanmıştır.


## 6. Bakış etkileşimi — kaynak düzeyi ekleme (2026-10-28)

- `index.html` içine el takibi ve WebXR denetleyicisi kullanılmıyorken etkin olan merkez bakış göstergesi eklendi. Stereo görünümde aynı mantıksal hedefi gösteren iki görsel işaret sol/sağ viewport merkezlerine yerleştirilir; hedefleme tek merkez kamera ışınıyla yapılır.
- Var olan `Scene.pick()` ve `Input.hover()`/`Input.dwell` mimarisi yeniden kullanıldı; ayrı bir sahne veya ikinci raycast hedef listesi kurulmadı. Gaze tıklaması mevcut panelin canvas üzerinde çizilen `btns` kayıtlarına gerçek `fn` callback'i çağırır.
- `u.chrome` olarak işaretli pencerelerin başlık alanına yaklaşık 1,9 saniye bakılması mevcut `rayCyl` ve `WM.place` taşıma yolunu kullanarak gaze sürüklemesini başlatır. Baş hareketi boyunca aynı ray ile pencere güncellenir; başlık alanına yeniden sabitlenmiş bakış yaklaşık 1,8 saniye sürerse bırakılır.
- **Sınırlama:** Bu proje gerçek WebXR desteği olan bir WebView'de `XR` oturumunu ayrı bir yoldan başlatabiliyor; bu ek gaze katmanı WebXR kontrolcü oturumu açıkken devre dışıdır. Stereo emülasyonunda imleçlerin sol/sağ görünüm merkezleri görseldir; gerçek cihaz optik hizalaması fiziksel VR gözlüğüyle doğrulanmamıştır.
- **Sınırlama:** Ana NEXUS VR sahnesindeki WebView/HTML içeriği Android tarafından ayrı native WebView katmanları olarak yönetilir. Bu değişiklik, bu katmanların DOM öğelerine gaze koordinatlarını ileten genel bir MotionEvent köprüsü oluşturmaz. Dolayısıyla üçüncü taraf web sayfalarının, form alanlarının, video kontrollerinin ve Windows 7 `Win7Activity` ekranının tüm DOM kontrollerinde evrensel gaze tıklaması bu kaynak değişikliğiyle garanti edilmez. Windows 7 simülatörünün ayrı Activity ekranında baş yönelimi/Three.js raycaster mevcut değildir.
- Derleme ve cihaz testleri bu ortamda çalıştırılmadı; aşağıdaki kaynak kontrolleri ayrıca yürütülmelidir.


## 6. Bakışla gerçek WebView tıklaması — ek aşama

- `MainActivity.Bridge.gazeTapAt(x, y, token)` eklendi. Token doğrulamasından sonra ekran koordinatının altındaki en üst görünür alt WebView'i bulur ve o WebView'e kısa bir Android `MotionEvent` DOWN/UP çifti iletir.
- Ana Three.js gaze yöneticisi, bakış hedefi canlı web uygulaması veya tarayıcı panelinin yüzeyi olduğunda bu köprüyü çağırır. Böylece bağlantı, form, DOM butonu ve WebView'in kendi klavye/fokus davranışı native WebView tarafından işlenir.
- Koordinatlar CSS pikselinden Android fiziksel piksele `devicePixelRatio` ile çevrilir; alt WebView'in ekran sınırlarına göre yerel koordinat hesaplanır. Çakışan alt WebView'lerde kök görünüm sırası kullanılarak üstteki görünüm seçilir.
- Güvenlik için köprü mevcut oturum token'ını zorunlu tutar; ana WebView'e veya görünmez alt WebView'lere olay göndermez.
- Doğrulama sınırı: Java/Android derlemesi ve fiziksel cihaz testi bu ortamda çalıştırılmadı. Bu aşamada bir gaze tap gönderimi uygulanmıştır; WebView üzerinde bakışla sürükleme/kaydırma henüz eklenmiş sayılmaz.
