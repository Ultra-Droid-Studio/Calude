# Stage 63 — Telefon / tablet sınıfı + performans seviyesi

## Sorun
- `Hand.lite` UA'daki "Android" ile açılıyordu: güçlü bir tablet de güçlü bir telefon da en düşük profile düşüyordu
  (320×240 el analizi, kapalı kenar yumuşatma, en düşük piksel oranı). Stage 52'deki "standart profil" hiç kullanılmıyordu.
- Telefon/tablet ayrımı yalnızca `smallestScreenWidthDp < 600` idi; cihazın gücü (RAM, çekirdek, ABI, yenileme hızı) hiç ölçülmüyordu.

## Değişiklik
**Tek doğruluk kaynağı:** `DeviceProfile.java` (sınıf: telefon/tablet, seviye: 0 düşük / 1 orta / 2 yüksek).
Köprü: `AndroidBridge.deviceProfile(token)` → JSON. JS tarafında `Dev` (köprü yoksa aynı kuralla tahmin).

Seviye kuralı (temkinli): **düşük** = düşük-RAM bayrağı, ≤3,2 GiB, 32-bit ABI veya ≤4 çekirdek ·
**yüksek** = ≥5 GiB, ≥8 çekirdek, Android 10+, arm64 · **orta** = geri kalan (Tab S6 Lite orta kalır, davranışı değişmez).

| Alan | Düşük | Orta | Yüksek |
|---|---|---|---|
| El takibi (`Hand.lite`) | lite | lite (eskisi gibi) | **standart** 480×360 (yeni) |
| Varsayılan grafik kalitesi | Düşük | Düşük | **Orta** (kayıtlı ayar korunur) |
| Kenar yumuşatma | kapalı | kapalı | **açık** |
| Telefon piksel bütçesi | ×0,8 | ×1 (Stage 61) | ×1,3 |
| Tablet piksel sınırı (Düşük/Orta/Yüksek kalite) | .70/.90/1.05 | .75/1/1.15 (eskisi) | 1/1.25/1.5 |
| Yenileme hızı | varsayılan | varsayılan | **en yüksek mod istenir** (90/120 Hz) |
| Eşzamanlı Android uygulama penceresi | telefon 1 / tablet 2 | 2 / 3 | 3 / 4 |
| Uygulama penceresi sanal ekran (genişlik) | telefon 800, tablet 1024 | telefon 960 (Stage 59), tablet 1280 | telefon 1080, tablet 1280 |

Ek: `onTrimMemory` → JS `__nxTrim`: bellek baskısında çözünürlük ölçeği 0,85 / 0,7'ye iner, otomatik yükseltme 60 sn kilitlenir.
Performans penceresinde "Cihaz" satırı (sınıf · seviye · Hz · RAM) görünür.

## Test
`node tools/devprofile.test.js` (yeni). `shizuku.test.js` yeni yapıya göre güncellendi.
`qsmenu.test.js` ve `lobby.test.js` bu aşamadan ÖNCE de başarısızdı (orijinal zip'te aynı hata); bu aşamada dokunulmadı.

## Doğrulanmadı
Derlenmedi, cihazda denenmedi (bu ortamda Android SDK yok). Yüksek seviyede el analizinin 480×360'a çıkması ve
yüksek yenileme hızı isteği gerçek cihazda ısınma/pil açısından denenmeli. Sorun olursa `DeviceProfile.tierOf`
eşiklerini yükselt (örn. yüksek için ≥7 GiB) ya da `Hand.lite` satırını eski hâline getir.
