# Stage 64 — Grafik ayarları elle + Android pencere pill'i + pencere sınırı kalktı

## İstenenler
1. Android uygulama pencerelerinin altına, normal uygulama penceresindeki ile aynı **pencere çubuğu (pill)**.
2. "En çok 2 pencere" (sınıf/seviyeye göre pencere sınırı) mantığı **kaldırıldı**.
3. El takibi profili, kenar yumuşatma, piksel bütçesi, yenileme hızı ve pencere sayısı **Ayarlar → Grafik** bölümünden elle ayarlanır.

## Değişiklikler
**Pill:** `Pill.want` artık `skin:'shz'` (Android uygulama penceresi) için de true. Aynı 4 düğme: Klavye, Büyüt, Küçült, Kapat. Üstteki dış çubuk olduğu gibi duruyor. "Pencere çubuğu (altta)" ayarı kapatılırsa Android pencerelerinde de pill kalkar.

**Pencere sınırı:** `MainActivity.maxAppWindows()` artık cihaz sınıfı/seviyesine bakmaz. Sınır yalnızca ayardan gelir (`shzSetMaxWin`); "Sınırsız" seçiliyken bile güvenlik için en çok 16. Sınıra ulaşılırsa uygulama normal ekranda açılır ve bildirim gösterilir.

**Ayarlar → Grafik (yeni 5 satır, hepsi "Otomatik" varsayılan = Stage 63 davranışı):**

| Satır | Seçenekler | Not |
|---|---|---|
| El takibi profili | Otomatik / Hafif (320×240) / Standart (480×360) | Hemen geçerli, el takibi açıksa yeniden başlar |
| Kenar yumuşatma | Otomatik / Kapalı / Açık | WebGL bağlamı açılışta kurulduğu için **uygulamayı yeniden başlatınca** geçerli |
| Piksel bütçesi | Otomatik / ×0.5 … ×2 | Telefonda MP bütçesi çarpanı, tablette piksel oranı sınırı çarpanı; seçilince "Piksel oranı sınırı" ayarını geçersiz kılar |
| Yenileme hızı | Otomatik / cihazın desteklediği Hz değerleri | `preferredDisplayModeId`; aynı çözünürlükteki en yakın mod |
| Android pencere sayısı | Sınırsız / 1 / 2 / 3 / 4 / 6 / 8 / 12 | |

Ayrıca `rowsCard` sayısı (5 → 11) düzeltildi; kart artık tüm satırları kaplıyor. `Hand.lite` artık getter (ayara bağlı); render bütçesi/kenar yumuşatma otomatik kararı `Dev.mobLite` ile eskisi gibi cihaz seviyesine bağlı kalır. `DeviceProfile` JSON'una `hzs` (desteklenen Hz listesi) eklendi. Sürüm 1.11 / kod 12.

## Test
`node tools/devprofile.test.js`, `shizuku.test.js`, `autoq.test.js` güncellendi ve geçiyor (`shizuku.test.js`'teki eski sürüm kontrolü de güncellendi).

## Doğrulanmadı
Derlenmedi, cihazda denenmedi (bu ortamda Android SDK yok). Özellikle: Android penceresi pill'inin konumu/hizası, yüksek Hz isteğinin bazı cihazlarda yok sayılması, çok sayıda pencerede bellek/ısınma. Sorun olursa `adb logcat -s NEXUS-Dev NEXUS-Mirror NEXUS-Shell` çıktısını gönder.
