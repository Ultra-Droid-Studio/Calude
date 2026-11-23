# Stage 32 — App Store

## Ne eklendi
- **App Store** sistem uygulaması (dock'ta 2. sırada sabit, Library'de «App Store»). Daha önce **Uygulamalarım**'da duran App Store ikonu artık bu uygulamada; Uygulamalarım turuncu ızgara ikonuna geçti.
- **Bölümler** (sol menü): Öne Çıkan · Tümü · Medya · Google · Sohbet · Üretkenlik · Tasarım · Keşif · Yüklenenler (+ Ara).
  - Öne Çıkan: «Bugünün uygulaması» vitrini (günlük döner), Popüler (8, iki sayfa), Yeni eklenenler.
  - Listeler: 2 sütun × 5 satır, sayfalı.
- **Katalog 28 → 40** web uygulaması (Twitch, Vimeo, X, Facebook, LinkedIn, Trello, Google Çeviri, Desmos, Pixlr, Google Earth, Hacker News, Duolingo eklendi). Eski «Katalog» sekmesi aynı verinin kopyası olarak duruyor.
- **AL** düğmesi: kısa ilerleme çubuğu (%), sonra kurulum. Kurulunca **AÇ**, Yüklenenler'de **Sil**.
- **İkonlar:** indirmeden önce ve indirdikten sonra ilk açılışa kadar renkli **harf** karosu. **İlk açılışta** uygulamanın sitesinden ikon çekilir ve uygulamanın ikonu olur (Uygulamalarım, Library, dock, App Store).

## İkon nasıl çekiliyor
`AndroidBridge.fetchIcon(url, geriÇağrı, token)` (yeni, `MainActivity.java`):
1. Sayfa HTML'inin ilk 300 KB'ında `<link rel="…icon…">` aranır; `apple-touch-icon` ve büyük `sizes` önce.
2. Sonra `/favicon.ico`, en sonda Google ikon servisi (`s2/favicons`, 128 px).
3. En çok 6 aday denenir; ilk çözülebilen görüntü 128×128 PNG'e ortalanıp `data:image/png;base64,…` olarak JS'e döner.
4. JS ikonu `nexus.apps` içinde saklar (`ico`); kalıcıdır. Başarısız olursa harf kalır, 24 saat sonra bir sonraki açılışta yeniden denenir.

Neden yerel indirme: sitelerin ikonlarını tarayıcıdan (`<img>`) yüklemek CORS nedeniyle canvas dokusunu «kirletir» ve VR panelini bozar. `data:` URI kirletmez.

Güvenlik: oturum anahtarı (token) ister, yalnızca `https`, yerel/özel ağ adresleri ve yönlendirme sonucu engelli (`checkTarget`), ikon 1 MB, sayfa 300 KB ile sınırlı, geri çağrı adı doğrulanır, JS tarafı yalnızca `data:image/png;base64` kabul eder.

Çizilen iOS ikonlarına sahip 8 uygulama (YouTube, Spotify, …) **Katalog sekmesinden** eklenirse eski gibi çizimli ikonda kalır; **App Store'dan** inenler harf → site ikonu akışını izler (`st` bayrağı).
«Adres ekle» ile eklenen ve çizimi olmayan siteler de ilk açılışta ikon alır.

## Değişen yerler
`index.html`: `ICO` (yeni önbellek) · `IOSI.tile/keyOf/SYSK` · `ATILE` · `CATALOG` (+12) · `WebApps.wantIcon/addCat/def` · `STORE` (yeni) · `APPS.store` · `HTILE`/Library ızgarası/`appInfo` (`img`) · `SYS`, `QPAL`, dock sabitleme geçişi (`stoPin`).
`MainActivity.java`: `fetchIcon` + `iconCandidates/httpBytes/iconDataUri`.
Testler: `node tools/appstore.test.js` (161 kontrol, yeni) · `icontheme.test.js` güncellendi (81).

## Doğrulama
Node testleri (katalog, her bölüm/sayfa çizimi, düğme sınırları, indirme akışı, ikon geri çağrısı, kötü veri reddi, Java köprüsü kuralları) ve gerçek Chromium canvas'ında Öne Çıkan / Tümü / Yüklenenler görüntüleri gözle kontrol edildi.

## DOĞRULANMADI
- **Android derlemesi yapılmadı** (bu ortamda javac yok); `MainActivity.java` yalnızca parantez dengesi açısından kontrol edildi.
- Cihazda/VR'da görünüm, dokunma ve gerçek site ikonlarının indirilmesi denenmedi. Oturum açtıran siteler (Instagram, Facebook…) apple-touch-icon yerine genel bir ikon verebilir.
- Android'de `.ico` çözme cihaza göre değişebilir; çözülemezse Google ikon servisine düşer (internet gerekir).
