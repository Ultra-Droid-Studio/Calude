# web/ — Nex VR arayüz kaynakları

`app/src/main/assets/index.html` artık **elle düzenlenmez**; bu klasördeki parçalardan üretilir.

## Günlük kullanım
1. İlgili dosyayı düzenle (CSS → `style.css`, kod → `js/NN-*.js`, iskelet → `template.html`).
2. Birleştir: `node tools/build-html.js`  → `assets/index.html` güncellenir.
3. Derlemeden dene: tarayıcıda `web/dev.html` ya da (birleştirdiysen) `assets/index.html` aç.
4. Kontrol: `node tools/htmlbuild.test.js`  (ya da sadece `node tools/build-html.js --check`).

APK'ya sadece `assets/index.html` girer. `web/` APK'ya girmez.

## Parçalar (sıra önemli, NN sırayı belirler)
| Dosya | İçerik |
|---|---|
| 01-core | NX_T, Dev (cihaz sınıfı), `$`, clamp, Three.js yükleyici |
| 02-mediapipe | MediaPipe kaynakları, yerel model önbelleği |
| 03-wallart-settings | Duvar kâğıtları, Storage, DEF, Settings |
| 04-diag-perf | Diag (bildirim/hata), Perf |
| 041-prof | Stage 74: Prof (bölüm süreleri, GPU sorgusu, darboğaz), Quality (uyarlanır kalite), PerfHud (monitör) |
| 05-render-scene | Renderer, Cam, Scene |
| 06-draw-helpers | Çizim yardımcıları, ikonlar |
| 07-window-ui | W7Desk, Pill, HMenu, WM (pencere yöneticisi) |
| 08-browser-webapps | BR (tarayıcı), katalog, WebApps |
| 09-bf-store | BF (GPU kareleri), App Store |
| 10-apps | APPS (tüm uygulama pencereleri) |
| 11-dock | Dock çizimi |
| 12-keyboard-input-xr | Klavye, Stereo, Input, XR |
| 13-hand | El takibi (OneEuro, NHand, Hand) |
| 131-hand-feat | Stage 74: el özellikleri (native K blokları + aynı formüllerin JS yedeği) |
| 132-hand-contour | Stage 74: içi boş siyah parmak konturları (GPU shader) |
| 14-intro-world | Intro, GLBRoom, EnvSky, Minecraft dünyası |
| 15-cinema-games | Sinema, Places, Game, Gezegenler |
| 16-launcher-shizuku | AND, **SHZ (Shizuku)**, Pins, Launcher |
| 17-qs-lobby | Hızlı ayarlar (QS), Lobby |
| 18-app-boot | App (açılış) + `window.NEXUS` |

## Kurallar
- Her `js/` dosyası `'use strict';` satırıyla başlar (birleştirirken atılır).
- Yeni parça eklemek için `NN-ad.js` adıyla dosya aç; sıralama dosya adına göredir.
- Parça sınırı **üst seviye ifade** başında olmalı (bir `const X={...}` ortasında bölme).
- `assets/index.html` içinde kod IIFE içinde çalışır; `dev.html` içinde ayrı scriptler **global kapsamda** çalışır.
  İki yerde de aynı üst seviye isim iki kez tanımlanamaz (test bunu denetler).
