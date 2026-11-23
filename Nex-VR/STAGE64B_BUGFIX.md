# Stage 64b — Hata taraması düzeltmeleri

- **index.html (Hand.start):** `const tr` try bloğunda kalıyordu, `CamFps.read(tr)` ReferenceError'ı sessizce yutuyordu; `CamFps.cur` hiç güncellenmiyordu. `tr` artık dış kapsamda (`let tr=null`).
- **Testler güncellendi** (kod değil, testler eskiydi): `lobby.test.js` (WebXR kaldırıldı), `qsmenu.test.js` (`shz` görünümü eklendi), `mcworld-smoke.test.js` (Node'da sahte `Image`).
- **Paket:** `.github/workflows/build.yml` eklendi (README'de anılıyordu, pakette yoktu). `gradlew` çalıştırılabilir izinle paketlendi.
- **Hâlâ geçerli:** `gradle-wrapper.jar`, `three.min.js`, `hand_landmarker.task` pakette yok; ilk derlemede internetten inerler. Java derlenmedi, cihazda denenmedi.
