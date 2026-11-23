# Stage 46 — Yeni duvar kağıtları

İlk açılışta gelen yerleşik duvar kağıtları (eski hâli: 4 satırlık düz gradyan şeritler) 360° panoramalara çevrildi. Dosya eklenmedi: hepsi `index.html` içinde `WallArt` ile canvas'ta çizilir (2048×1024, ~50–200 ms).

| # | Ad | İçerik |
|---|----|--------|
| 0 | Gün batımı | bulutlar, güneş, 3 katman dağ, sakin deniz + güneş yansıması |
| 1 | Gece | yıldızlar, soluk Samanyolu, dolunay, dağlar, göl yansıması |
| 2 | Aurora | 3 katmanlı kuzey ışığı perdeleri, çam ormanı, göl |
| 3 | Okyanus | gündüz gökyüzü, bulutlar, dalgalar, güneş ışıltısı |
| 4 | Derin uzay | nebula bulutları + sarmal galaksi + yıldız alanı |
| 5 | Nebula | pembe/turuncu/mor gaz bulutları, toz sütunları, genç yıldız kümesi |
| 6 | Samanyolu | tepenin üstünden geçen Samanyolu bandı, toz şeritleri, çekirdek |
| 7 | Gezegen | halkalı gaz devi, iki uydu, yıldız tarlası |
| 8 | Kara delik | yığılma diski, ışık halkası, mor nebula |
| 9 | Neon | synthwave güneşi, dağ silüeti, perspektifli neon ızgara zemin |
| 10 | Dünya | yörüngeden Dünya (kıtalar, bulutlar, atmosfer), Ay |

* İlk 4 sıra/ad aynı kaldı: kayıtlı `wp` ayarı bozulmaz.
* Ayarlar → Görünüm: 4 sütunlu galeri, küçük resimler gerçek görüntüden (VR dışında boş zamanda üretilir; hazır olana kadar eski gradyan görünür).
* Başlangıçta bakılan yön (−Z) ana öğeye (güneş, gezegen, kara delik…) denk gelir.
* Çizim başarısız olursa eski gradyana düşer. "Dosyadan" ile kendi panoramanı yükleme aynen çalışır.
* Sınama: `node tools/wallart.test.js`.
