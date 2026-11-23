# Stage 72 — El yerine GERÇEK 3B Quest kontrolcü modeli

- El silueti, parmak ve eklem çizimi kaldırıldı. Yalnızca bilek (0) ve orta parmak tabanı (9) kullanılır.
- Kontrolcü Three.js ile 3B kurulur (`nexCtrl3D`): halka (torus), sap, baş, yüz paneli, joystick, 2 düğme, tetik ≈ 10 mesh.
  Geometri/malzeme tüm slotlarda paylaşılır. Kamera çocuğu olduğu için stereo/VR'da iki göze de otomatik girer.
- `nexCtrl3DPlace`: kontrolcü bilek konumunda (kamera önünde ~0.45-0.8 m, el boyuna göre) durur ve imlecin baktığı noktaya döner.
- Işın + nokta YALNIZCA bir pencere/düğme üstündeyken (`s.hit`) ya da sürüklemede (`s.mode==='ui'`) görünür.
  Nokta pencerenin önünde (depthTest kapalı) ve uzaklıkla ölçeklenir (ekranda sabit boy).
- Çimdik = tetik: tetik içeri girer ve parlar, nokta turkuaz olur. Dwell (bekleyerek tıklama) mevcut Input/KBD mantığıyla aynen çalışır.
- Sol kontrolcü: aynı model negatif x ölçekle aynalanır. Ters görünürse `Hand.ctrlFlip=true`.
- Test: `node tools/handpaint.test.js` (16 kontrol, sahte THREE ile). Gerçek cihazda denenmedi, görünüm ekranda görülmedi.
- Not: `shizuku.test.js` ve `browser.test.js` Stage 71'de de kırıktı.
