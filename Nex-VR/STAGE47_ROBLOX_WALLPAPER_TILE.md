# Stage 47 — Duvar kağıdı galerisine Roblox evi (3D)

Ayarlar → Görünüm → Duvar kağıdı galerisine yeni bir kare eklendi: **"Roblox evi (3D)"**.

* Diğer karelerin aksine düz panorama görüntü **uygulamaz**. Dokununca `roblox_house.glb` dosyasından yüklenen, zaten projede var olan Sinema oda 1 ("Roblox evi") 3 boyutlu ortam olarak açılır — gezilebilir gerçek 3D sahne, resim değil.
* Tıklanınca: açık olan Oyun/Gezegenler/Gorilla modları kapatılır, Sinema odası 1'e ayarlanır (`Cinema.setRoom(1)`), Ayarlar penceresi kapanır ve Sinema `Cinema.enter()` ile açılır.
* Kare, diğer duvar kağıtlarından ayırt edilsin diye kırmızı→mor→lacivert gradyan ve ev ikonuyla çizilir; oda şu an açıksa beyaz çerçeveyle vurgulanır.
* `WALL` dizisine dokunulmadı (kayıtlı `wp` ayarı bozulmaz); galerinin ızgara satır sayısı yeni kareyi kapsayacak şekilde güncellendi.
* Sınama: `node tools/wallart.test.js` (mevcut tüm kontroller geçiyor).
