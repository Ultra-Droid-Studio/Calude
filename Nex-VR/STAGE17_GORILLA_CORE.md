# Stage 17 - GORILLA RUN çekirdeği (Aşama 2-4)

Bu sürüm, Stage 16 üzerine **NEXUS VR: GORILLA RUN** oyununun çekirdeğini ekler. Win7 simülatörüne, normal tarayıcıya,
Stage 16 kaydırma kodlarına ve Java dosyalarına dokunulmamıştır.

## Ne eklendi
| Dosya | Amaç |
|---|---|
| `app/src/main/assets/gorilla-phys.js` | Fizik çekirdeği (THREE/DOM bağımsız): çarpışma dünyası, iki el, itiş, tutunma/tırmanma, sabit adım, test haritası. Tüm sabitler `CFG` içinde. |
| `app/src/main/assets/gorilla.js` | Oyun katmanı: sahne, karakter (gövde + iki kol + iki el), dokunmatik girdi, menü/HUD, kayıt, yaşam döngüsü. |
| `tools/gorilla-phys.test.js` | Fizik birim testleri (`node tools/gorilla-phys.test.js`). |
| `tools/gorilla-smoke.test.js` | Sahte THREE/DOM ile yaşam döngüsü duman testi. |

## `index.html` içindeki değişiklikler (21 satır, hepsi küçük kanca)
- `window.NEXUS` nesnesine `Game, Planets, Cinema, Launcher` eklendi.
- `App.frame` içinde `Gorilla.tick(dt)` çağrısı (mevcut tek render döngüsü kullanılır).
- Dock/launcher kaydı: `['gorilla','Goril','gorilla']`, simge, ve `spawn`/`isOpen` dalları; ilk açılışta dock'a sabitlenir.
- `Game`, `Planets`, `Cinema` açılırken `Gorilla` kapanır.
- Goril açıkken 2B el çizimi/önizlemesi gizlenir.
- `gorilla-phys.js` ve `gorilla.js` için iki `<script src>` etiketi.

## Nasıl açılır
Dock'taki **Goril** simgesine dokun (yoksa Uygulamalar listesinden). Menüden **Oyuna başla**.

## Kontroller (dokunmatik test modu)
- **Sol / sağ alt bölge = sol / sağ el.** Basılı tut: el yere basar. Parmağı **aşağı çek**: el geri gider, gövde ileri itilir. Yana kaydır: el yana.
- **TUT** (her elin yanında): tırmanılabilir yüzeye (ağaç gövdesi, dal, kaya) tutunur; tutarken ilgili alanda parmağı **yukarı/aşağı** kaydırmak eli yukarı/aşağı götürür. Tırmanmak için eller sırayla yukarı uzatılıp çekilir.
- **Orta alan:** bakış. **ZIPLA:** destekli zıplama (yalnızca bir yüzeye değerken; menüden kapatılabilir). **II:** duraklat.
- Android geri tuşu: oynarken duraklatır, menüdeyken NEXUS VR'a döner.

## Doğrulananlar (bu ortamda)
- `node --check`: `index.html` satır içi betikleri, `gorilla-phys.js`, `gorilla.js` temiz.
- Fizik birim testleri: 18 kontrol geçti (ayakta durma, itiş, hız korunumu, takip kaybı, ışınlanan el, uzun kare, duvar köşesi, zıplama kuralları, tırmanma + bırakma, 20000 adımlık rastgele girdi: NaN yok, hız sınırı korundu, harita altına düşme yok).
- Duman testi: aç/duraklat/geri tuşu/kapat, durum geri yükleme, 20 kez aç-kapa sonrası sahne ve DOM temiz, bozuk kayıt, WebXR oturumunda açılmama.
- Testler sırasında iki gerçek hata bulunup düzeltildi (duvar köşesinde sahte geri kayma; gripsiz elin ağaca yapışması).

## DOĞRULANMADI / EKSİK (açık liste)
- **Derleme (Gradle/APK) yapılmadı**, **gerçek cihazda veya gerçek WebView'da çalıştırılmadı**. Render (görünüm), dokunmatik his, kare hızı ve parametre ayarı cihazda test edilmeli. Duman testi sahte THREE kullanır; gerçek WebGL çıktısını doğrulamaz.
- **El takibi (kamera, 2B) ve WebXR denetleyici girdisi bağlı değil.** Mevcut `Hand` 2B landmark verir; dünya uzayında güvenilir 3B el konumu üretmez. Fizik API'si (`Sim.setHand(i, valid, x, y, z, grip)`) kaynaktan bağımsızdır; yeni kaynaklar aynı çağrıyı kullanacak. WebXR oturumunda oyun şimdilik açılmaz ve kullanıcıya nedeni söylenir.
- Stereo modda arayüz (DOM) çift göze çizilmez.
- Harita yalnızca **test haritasıdır** (Emerald Forest, kozmetikler, mağaza, ses, eğitim, kalite profilleri, adaptif performans henüz yok). Çarpışma taraması düz döngüdür (küçük harita için yeterli; büyük harita için mekânsal bölümleme gerekecek).
- Hava kontrolü parametresi henüz yok. Dokunmatik modda gövde yönü kamera yönünü izler.
- `three.min.js` projede yok; derleme sırasında `fetchThree` indirir (ilk derlemede internet gerekir). `gradle-wrapper.jar` hâlâ eksik (Stage 16'dan kalan durum).
