# Stage 52 — Native el takibi yük dengeleme

## Sorun
Native CameraX analiz hattı, el takibi açıkken her kamera karesini 640×480 RGBA olarak alıyordu. MediaPipe önceki kareyi işlerken kareler atılsa da CameraX callback'leri ve yüksek çözünürlüklü görüntü kopyalama/döndürme maliyeti devam edebiliyordu. Bu yük, aynı cihazda çalışan Three.js sahnesi, WebView tarayıcı ve pencere etkileşimleriyle CPU/bellek bant genişliği için yarışır.

## Değişiklik
- Hafif cihaz profilinde analiz çözünürlüğü 320×240'a indirildi.
- Standart profilde analiz çözünürlüğü 480×360 olarak ayarlandı.
- El takibi analiz girişi hafif profilde en fazla 30 Hz, standart profilde en fazla 40 Hz olacak şekilde sınırlandı.
- Kare aralığı kontrolü bitmap kopyalama, döndürme ve MediaPipe MPImage oluşturulmasından önce yapılır; atılan kareler bu pahalı işlemlere girmez.
- `lite` profili değişirse CameraX oturumu yeniden yapılandırılır; eski çözünürlükte kalmaz.
- Kamera önizleme çözünürlüğü kullanıcının kamera kalitesi ayarından bağımsız kalır. Bu değişiklik yalnızca MediaPipe analiz hattını etkiler.

## Beklenen etki
Özellikle hafif cihazlarda el takibinin CPU/bellek bant genişliği tüketimi azalır. 320×240 analiz, el landmark'ları için yeterli ayrıntıyı çoğu normal kullanım mesafesinde korurken piksel sayısını 640×480'e göre %75 azaltır. 30 Hz giriş sınırı, UI/3D render döngüsüne daha fazla işlem zamanı bırakır.

## Doğrulama sınırı
Kaynak ve mevcut JavaScript testleri kontrol edildi. Bu ortamda Android SDK/Gradle cihaz derlemesi ve fiziksel tablet FPS/ısı ölçümü yapılamadı. Dolayısıyla gerçek cihaz kazancı ölçülmüş sonuç değil, hedeflenen optimizasyondur. İlk cihaz testinde el algılama kararlılığı ve üst bilgi satırındaki çıkarım/ gecikme değerleri kontrol edilmelidir.
