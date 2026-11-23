# Web uygulaması kataloğu (PhoneXR'dan esinlenen)

"Uygulamalar" penceresine **Katalog** sekmesi eklendi (Library sol menüsünde de **Katalog** girişi var).

- 26 hazır web uygulaması, 6 kategori: Medya, Google, Sohbet, Üretkenlik, Tasarım, Keşif.
- Karta dokun: eklenir. Eklenmişse "Eklendi · Aç" yazar ve uygulamayı açar.
- Eklenenler Uygulamalarım, Library (Web filtresi) ve dock sabitleme listesinde görünür; aynı renk ve harf işaretini kullanır.
- Kaldırınca katalogda tekrar "Ekle" olur. Veri `nexus.apps` içinde kalıcıdır.
- Marka logosu kullanılmadı; her uygulamanın kendi renk geçişi ve harf işareti vardır.
- PhoneXR kodundan yalnızca uygulama adı/adres listesi fikri alındı, kod kopyalanmadı.

## Doğrulananlar (Node, sahte canvas)
Katalog verisi (26 benzersiz, https), ekle/aç/kaldır mantığı ve kalıcılık, iki sekmenin tüm kategori/sayfa kombinasyonlarında düğmelerin pencereye sığması ve çakışmaması, NaN yok, `node --check` temiz, eski gorilla testleri geçiyor.

## Doğrulanmadı
Gerçek cihazda/WebView'da görünüm ve dokunma hissi denenmedi; APK derlenmedi. Google siteleri (Gmail, Drive vb.) gömülü WebView'da oturum açmayı engelleyebilir; YouTube, Discord, Telegram, Figma gibi çoğu site sorunsuz çalışır.
