# Nex VR – Telefon Uyumluluğu Güncellemesi

Bu güncelleme mevcut arayüzü, sahne içeriğini, uygulama kimliğini ve tablet davranışını değiştirmeden telefonlardaki uyumluluk sorunlarını azaltmayı hedefler.

## Yapılan değişiklikler

- Android tam ekran/immersive görünümü tek bir yardımcı fonksiyondan tekrar uygular; uygulama odağı geri geldiğinde sistem çubukları yeniden gizlenir.
- Android 9+ ekran kesiklerinin bulunduğu cihazlarda `SHORT_EDGES` görüntüleme modu kullanılır.
- Telefon sınıfı ekranlarda (smallest width < 600 dp) tarayıcı ve Windows 7 için özel `VirtualDisplay` GPU penceresi yerine mevcut doğrudan WebView görüntüleme yolu seçilir. Tabletlerde GPU yolu korunur.
- WebView/Three.js boyutları pencere yeniden boyutlandığında, yön değiştiğinde ve `visualViewport` değiştiğinde yeniden hesaplanır.
- VR önizleme modunun yön sensörü için Android `SensorManager` tabanlı yerel yedek eklendi.
- Rotation Vector sensörü varsa kullanılır. Bu sensör yoksa ivmeölçer + manyetometre ile temel yön tahmini denenir.
- Sensör güncellemeleri yaklaşık 30 Hz ile sınırlandırılır; uygulama arka plana geçince sensör dinleyicileri bırakılır, geri dönünce yeniden bağlanır.

## Sınırlar ve test notu

- WebXR `immersive-vr` desteği cihazın Android sürümüne, WebView/Chromium sürümüne, sensörlerine ve WebXR çalışma zamanı desteğine bağlıdır. Yerel yön sensörü yedeği WebXR desteği oluşturmaz; yalnızca uygulamanın kendi VR önizlemesindeki kafa yönünü destekler.
- İvmeölçer + manyetometre yedeği, gerçek jiroskop/rotation-vector kadar akıcı veya kararlı olmayabilir; manyetik parazit yön bilgisini etkileyebilir.
- Farklı üreticilerin WebView uygulamaları ve GPU sürücüleri nedeniyle her Android telefonda kusursuz çalışma garantisi verilemez. Gerçek cihaz testi gereklidir.
- Bu ortamda Android SDK ve Gradle Wrapper JAR bulunmadığından APK derlemesi/cihaz testi yapılamadı. Java değişiklikleri kaynak düzeyinde eklendi; HTML içindeki JavaScript sözdizimi kontrol edildi.
