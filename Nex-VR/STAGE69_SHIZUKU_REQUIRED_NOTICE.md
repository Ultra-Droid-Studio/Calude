# Stage 69 — Shizuku bağlı değilse uyarı göster, uygulamayı açma

## İstenen
Android uygulamasına tıklanınca Shizuku bağlı değilse uygulama normal ekranda açılmasın;
"Bu uygulamayı pencerede açmak istiyorsanız Shizuku ile bağlantısını kurun" yazısı çıksın.

## Değişiklik — `app/src/main/assets/index.html` → `SHZ.tryOpen`
- Shizuku çalışmıyorsa (durum 0) ya da izin reddedilmişse (durum 2): uygulama açılmaz,
  5 sn'lik uyarı yazısı çıkar. Eskiden 60 sn'de bir uyarıp uygulamayı normal ekranda açıyordu.
- İzin isteniyor/bağlanıyor durumları (1, 3) aynen kaldı: izin verilince uygulama kendiliğinden açılır.
- Ayarlar'da "Android uygulamaları VR penceresinde" kapalıysa eskisi gibi normal ekranda açılır.
- Pencerenin "gerçek ekranda aç" ikonu da eskisi gibi çalışır.
