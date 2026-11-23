# Stage 59 — Telefon profili (Android uygulama pencereleri)

## Sorun
Android uygulamaları VR penceresinde her cihazda 1280×720 sanal ekran + 30 fps'e kadar JPEG hattıyla açılıyordu.
Tablette sorun yok; telefonlarda CPU/bellek yükü yüzünden takılma ve bozulma oluyordu.

## Değişiklik (yalnızca smallestScreenWidthDp < 600)
- Sanal ekran genişliği en çok 960 px (en/boy korunur). dpi cssW'ye göre yeniden hesaplanır, yani uygulamanın dp düzeni aynı kalır, piksel sayısı ~%44 azalır.
- Kare aralığı 33–160 ms yerine 55–220 ms, JPEG kalitesi hareket 58→48, durulma 84→78, durulma gecikmesi 240→320 ms.
- Eşzamanlı uygulama penceresi 3 yerine 2.
- Yeniden boyutlandırmada aynı sınır uygulanır. Tablet davranışı değişmedi.

## Doğrulanmadı
Derlenmedi ve cihazda denenmedi. Sorun sürerse `adb logcat -s NEXUS-Mirror NEXUS-Shell` çıktısını gönder.

# Stage 60 — Üst çubuk pencerenin dışında + Dik/Yatay mod
- Android uygulama penceresinde üst çubuk (başlık, Klavye, Geri, kaydırma, Normal ekranda aç) artık ayrı bir kapsül olarak
  pencerenin DIŞINDA, hemen üstünde. Uygulama alanı altındaki tuvali tamamen kaplar (kart arka planı yok, `skin:'shz'`).
- Çubukta **Dik / Yatay** düğmesi: dik modda dar ve uzun pencere (tuval 640 px), sanal ekran ~400 dp genişlikli telefon
  düzeninde (640×1138) yeniden boyutlanır. Yönelim uygulama (paket) başına hatırlanır; yeni açılışlar o yönde başlar.
- Uygulamanın kendisi yönelimi kilitliyse (yalnızca yatay oyun gibi) dik mod uygulamada görünmeyebilir.
- Derlenmedi/cihazda denenmedi; yalnızca JS sözdizimi ve `tools/shizuku.test.js` doğrulandı.

# Stage 61 — Otomatik çözünürlük / VR / el takibi kalite düzeltmesi
## Bulunan hatalar
- Piksel oranı, `Settings.dpr=1` yüzünden telefonlarda CSS pikseliyle sınırlıydı; VR modu (×0.72×0.85) ve el takibi (×0.78)
  çarpanları üst üste binip oran 0.55 tabanına iniyordu (ekran çözünürlüğünün yaklaşık %25'i). Üstüne otomatik çözünürlük
  de 0.6'ya kadar düşürüyordu.
- Otomatik çözünürlük, fps düşüşü CPU/el takibinden gelse bile (çözünürlük fayda etmez) sürekli düşürüyordu;
  geri yükseltme için 5 sn boyunca fps>55 gerekiyordu, 60 Hz telefonda neredeyse hiç olmuyordu.
## Düzeltme
- Telefonda (kısa kenar < 600 css px) piksel BÜTÇESİ: ekran boyutuna göre en az 1:1, düşük/orta/yüksek kalitede 0.9/1.3/1.9 MP.
  El takibi cezası 0.78 → 0.92, VR cezası yalnızca "VR performans ölçeği" (0.7–1). Taban: normal 0.8, VR 0.9. Tablet formülü değişmedi.
- Otomatik çözünürlük: hedef fps'e göre eşikler (%70 / %92), her adımdan sonra bekleme, fayda etmeyen adım geri alınır
  (45 sn kilit), yükseltme 2 sn'de, salınım olursa 30 sn kilit. Telefonda en düşük ölçek 0.75 (VR'da 0.8).
- Test: `node tools/autoq.test.js`. Cihazda denenmedi.
