# Stage 24 — Telefonlu VR gözlük profilleri

## Eklenenler
- Ayarlar içinde yeni **VR ayarları** sekmesi.
- Başlangıç profilleri: Google Cardboard, VR Box, VR Sensation, VR SHINECON, BOBOVR/Z4, DESTEK, Merge VR ve Genel/özel gözlük.
- Profil seçip **Profili uygula** ile başlangıç değerlerini uygulama.
- Elle ayarlanabilen gözler arası stereo ayrımı, VR görüş açısı, dikey görüntü hizası ve VR render ölçeği.
- Ayarlar kalıcı ayarlara kaydedilir; VR modu açılırken profil kullanılır. VR modu kapanınca normal kamera görüş açısı geri yüklenir.
- Stereo modunda seçilen gözler arası mesafe ve dikey hizalama uygulanır. VR render ölçeği, stereo görüntünün GPU yükünü azaltmak/artırmak için kullanılır.

## Önemli not
Bu marka seçenekleri **başlangıç profilleridir**, üreticilerden doğrulanmış optik ölçüler değildir. Aynı markanın farklı modelleri ve telefonların ekran boyutları değişebilir. Kullanıcı gözlüğünü takıp görüntüyü gözle kontrol ederek ayarları ince ayarlamalıdır.

Bu aşamada tam Cardboard SDK QR profili okuma ve Brown lens-distortion mesh düzeltmesi eklenmedi. Bu nedenle profiller, stereo ayırma/FOV/hizalama/render yükü ayarları sağlar; bütün mercek bozulmalarını otomatik düzelttiği iddia edilmez.

## Test
- `node --check` ile ana HTML içindeki JavaScript blokları sözdizimi kontrolünden geçirildi.
- `tools/*.test.js` içindeki 10 test dosyası çalıştırıldı; tümü başarılı.
- Fiziksel Android cihaz ve VR gözlüğü üzerinde çalışma testi bu ortamda yapılmadı.
