# Stage 30 — iOS ikon teması (sistem uygulamaları + web uygulamaları)

Kaynak: `UPSIDEvr-nextvr-pkg.zip` → `IosIcons.kt` ve `WebApps.kt`. `icons/light` ve `icons/dark` klasörleri **kullanılmadı**.
Kod kopyalanmadı; çizimler Kotlin Canvas'tan JS Canvas'a uyarlandı (`index.html` → `IOSI` modülü).

## Görünüm
Tam taşkın kare + yumuşak dikey gradyan + sol üstten gloss + gölgeli beyaz glif. Köşeleri çağıran yuvarlar.

## Çizimli ikonlar (11)
App Store, Tarayıcı (pusula), Instagram, Discord, Android, YouTube, GitHub, Spotify, WhatsApp, SoundCloud, Vikipedi.
- **Sistem:** Web → pusula, Uygulamalarım → App Store «A», Cihaz → Android robotu. Diğer sistem uygulamaları kendi renk + glifleriyle (gradyan/gloss/gölge) aynı temaya girer; Windows 7 «7» harfli kalır.
- **Web uygulamaları:** katalog anahtarına göre; kullanıcının «Adres ekle» ile eklediği siteler **alan adından** eşlenir (instagram.com, youtube.com, open.spotify.com, discord.com, github.com, whatsapp.com, soundcloud.com, wikipedia.org). Çizimi olmayanlar kendi renginde harf karosu (UPSIDEvr `letter()` karşılığı).
- Android uygulamalarının gerçek ikonları (AndroidBridge) aynen duruyor.

## Eklenen web uygulamaları (katalogda yoktu)
**Instagram** (Sohbet) ve **SoundCloud** (Medya). Katalog 26 → 28. Diğer 8 çizimli uygulama zaten vardı.
Eklenmiş sayılmaz: Katalog'dan tek dokunuşla eklenir (mevcut davranış).

## Değişen yerler (`index.html`)
`IOSI` (yeni) · `CATALOG` (+2) · `ATILE` (anahtar parametresi; Katalog + Uygulamalarım) · `HTILE` (dock) · Library ızgarası ·
`appInfo` (`ik`) · `QPAL.qcam` (dock kamera rengi). Test: `node tools/icontheme.test.js` (81 kontrol).

## Doğrulama
Çizimler headless Chromium'da gerçek canvas ile çizilip gözle kontrol edildi (kare + geniş Library kartı). Cihazda görülmedi.

## Bilerek farklı / açık
- Sitelerin gerçek favicon'ları indirilmez (UPSIDEvr'deki `fetchSiteIcon`): canvas dokusunu bozar; çizimi olmayan siteler harf karosu alır.
- Kotlin `CornerPathEffect` ve gölge yarıçapı canvas karşılıklarıyla yaklaşık eşlenir (piksel birebir değil).
- Library'de geniş kartlarda arka plan karta yayılır, glif kısa kenara göre ölçeklenir.
