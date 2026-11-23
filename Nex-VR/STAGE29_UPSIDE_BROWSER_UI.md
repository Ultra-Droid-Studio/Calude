# Stage 29 — UPSIDEvr tarayıcı arayüzü (sekmeler, adres çubuğu, yeni sekme sayfası)

Kaynak: `UPSIDEvr-nextvr-pkg.zip` → `WindowChrome.kt` (drawBar) ve `assets/browser/home.html`. Kod kopyalanmadı; bizim canvas tabanlı `index.html` tarayıcı paneline uyarlandı.

## Üst çubuk (Chrome görünümü)
- Gri sekme şeridi, beyaz etkin sekme (alt kenarı araç çubuğuna açılan kavisli), her sekmede ×, sonda +.
- Araç çubuğu: geri / ileri (gidilemiyorsa soluk) / yenile, yuvarlak adres alanı (sayfa yokken Google «G», sayfa varken kilit; sağ ucunda ☆ yer imi), sağda eklenti kutusu, ayırıcı, profil dairesi, ⋮ menü.
- Eklenti ve profil yalnızca görünüş (UPSIDEvr'deki gibi), dokununca bilgi mesajı verir.
- Bakış modunda sağdaki yukarı/aşağı ok şeridi (Stage 28) korunur; el modunda ok düğmeleri adres alanının yanında kalır.
- Menü (⋮) açık renk oldu.

## Yeni sekme sayfası (home.html uyarlaması)
- Renkli «NEXTvr» yazısı, yuvarlak arama alanı (+ yeni sekme, «Ara» düğmesi), 4 kutucuk: saat/tarih, Yer imleri, Geçmiş, Tercihler.
- Kısayol daireleri (varsayılan: YouTube, Wikipedia, Twitch, GitHub, Moon Rider) + «Kısayol ekle».
- Pencereler: Yer imleri, Son ziyaret edilenler (+ Geçmişi temizle), Tercihler (Masaüstü sitesi, Reklam engelleme, Adres çubuğu), Kısayol ekle (adres VR klavyesiyle girilir, adından alan adı alınır; en çok 12).
- Kısayollar `Settings.v.pins` içinde saklanır; yoksa varsayılanlar gösterilir.

## Bilerek farklı
- home.html gerçek bir WebView sayfası olarak değil canvas olarak çizilir (VR klavyesi ve bakış/el girdisi böyle çalışıyor). Sitelerin favicon'ları yüklenmez (canvas dokusunu bozar); yerine renkli harf.

## DOĞRULANMADI
- Görsel olarak cihazda görülmedi; yalnızca JS sözdizimi + `tools/browser.test.js` (92 kontrol, yeni düzen için güncellendi) çalıştırıldı. Yerleşim sapması olursa ekran görüntüsü gönderin.
