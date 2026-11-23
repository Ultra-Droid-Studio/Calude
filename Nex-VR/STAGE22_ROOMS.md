# Stage 22 - Sinemada oda seçimi: Roblox evi + gökyüzü ortamları

Stage 21 üzerine kuruludur. **Değişen/eklenen:** `assets/index.html` (yeni `GLBRoom` yükleyici + `Cinema` odalar), `assets/roblox_house.glb` (PhoneXR'dan, 7,9 MB), `tools/glbroom.test.js` ve `tools/envsky.test.js` (yeni). Java'ya dokunulmadı.

## Kullanım
Sinema modunda perdede **Oda: ...** düğmesi (her dokunuşta sıradaki oda: Salon, Roblox evi, Gün batımı, Gece, Uzay, Stüdyo, Brawl arena) (video seçilmemişken altta, video varken duraklatma satırında). Seçim hatırlanır. Roblox evi ilk seçimde yüklenir; o ana kadar salon görünür.

## Gökyüzü ortamları
PhoneXR `Environments.kt`'den JS'e çevrildi (`EnvSky`): gün batımı, gece, uzay, stüdyo. Dosya yok, 2048x1024 canvas ile çizilir, 360° küreye kaplanır; perde 3,4 m genişlikte, 3,9 m önde yüzer. Ortam değişince eski dokunun GPU kopyası bırakılır. Gerçek Chromium'da çizdirilip gözle kontrol edildi.

## Brawl Stars arenası
`assets/brawl.jpg` (1774x887, 360° resim, PhoneXR'dan) aynı küreye kaplanır; resmin ortası (logo) PhoneXR'daki gibi 70° sola döndürülür ki perdenin arkasında kalmasın. Küre `scale.x=-1` ile aynalanmadan görünür (yazı doğru okunur); yön hesabı Node'da sayısal doğrulandı. İlk seçimde yüklenir, o ana kadar salon görünür.

## Nasıl çalışıyor
- `GLBRoom`: THREE r128 için küçük glTF 2.0 .glb okuyucu (97 parça, 34 doku, şeffaf malzemeler, Lambert + ortam/yönlü ışık). Dış kütüphane gerekmez.
- Yerleşim PhoneXR'daki `ROBLOX_HOUSE` ile aynı: ölçek .225, oturma noktası kanepe, perde şöminenin üstündeki tablonun yerinde (2,7 m genişlik, 4,59 m uzaklık, 1,8 m yükseklik). Perde paneli oda değişince yeniden ölçülür.
- Dışarısı için açık mavi gökyüzü küresi.

## Doğrulananlar (Node)
`node tools/glbroom.test.js`: gerçek yükleyici kodu gerçek .glb ile çalıştırıldı: 97 mesh, 67 592 köşe, NaN/geçersiz indeks yok, oturma noktasının altında zemin y=0,03, tavan y=3,38, perde konumunda duvar yüzeyi var. Eski testler (oneeuro, browser, gorilla) geçiyor, `index.html` betikleri sözdizimi temiz.

## DOĞRULANMADI / AÇIK EKSİKLER
- **Cihazda ve Android derlemesinde denenmedi.** Görünüm (renk, aydınlatma, hız) gerçek tablette bakılmalı; 97 çizim çağrısı + 43 şeffaf malzeme düşük cihazda ağır olabilir.
- **Minecraft oturma odası eklenemedi:** PhoneXR paketinde modeli yok (kodda "oturma odası kaldırıldı" yazıyor). Model dosyası verilirse eklenir.
- Roblox evi modelinin lisansı/yazarı PhoneXR kaynağında belirtilmemiş; yayın öncesi Sketchfab'tan kontrol edilmeli.
- **Brawl Stars görseli telif hakkı korumalıdır (Supercell).** Yalnızca kişisel kullanım için; uygulamayı yayınlayacaksan `brawl.jpg`yi ve `Brawl arena` odasını çıkar.
- Ortamlar ve Brawl yönü sayısal doğrulandı ama tablette gözle bakılmadı.
- Odanın içinde yürüme/çarpışma yok; oturma noktası sabit.
