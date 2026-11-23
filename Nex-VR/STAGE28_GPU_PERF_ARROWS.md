# Stage 28 — GPU tarayıcı performansı + bakış okları

## Performans (GpuPage.java, VirtualDisplay aynen duruyor)
- Uyarlanır kare hızı: JPEG sıkıştırma süresinin hareketli ortalaması × 1.8 kadar beklenir (33–160 ms); işlemci doyurulmaz.
- Hareket (kaydırma/video) sırasında hafif JPEG (kalite 58); hareket durunca 240 ms sonra tek keskin kare (kalite 84).
- ImageReader tampon sayısı 3 → 2.
- Kare boyutu panel pikseline eşit (1.25× → 1.0×, ≤1408×900): daha az sıkıştırma, daha az doku yükü.

## Bakış okları (index.html)
- Bakış modu (el takibi kapalı, XR yok) açıkken tarayıcı penceresinin sağında yukarı/aşağı ok şeridi çıkar; sayfa alanı o kadar daralır.
- Oka bakılı tutulursa sayfa tekrar tekrar kayar (≈0.65 sn aralık). El modunda şerit görünmez.

## DOĞRULANMADI
- Java derlenmedi, cihazda denenmedi. Kalite 58/84 ve aralıklar cihazda ayarlanabilir (GpuPage.java üst sabitler).
