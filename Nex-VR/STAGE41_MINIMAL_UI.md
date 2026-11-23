# Stage 41 — Minimalist Quest arayüzü (dock, Library, pencereler)

## İstek
Dock, uygulama menüsü (Library) ve pencereler Quest ekran görüntülerindeki gibi çok sade, şık ve güzel renk tonunda olsun.

## Değişiklikler (`app/src/main/assets/index.html`)
- **Library** (`Launcher.render`): görseldeki düzen. Üstte ortalanmış "Library" başlığı ve arama hapı, solda sade menü
  (seçili öğe açık renkli hap), ortada 5 sütun kare ikon + altında ad, sağda düz "Filtre / Sırala" satırları.
  Arka plan yarı saydam mor-gri, büyük yuvarlak köşe (42), pencere düğmeleri yerine yalnızca küçük Kapat.
  Kaydırma okları sağ alta taşındı. Çizilen alan ve tıklama alanları aynı `B()` düğme sistemiyle durur.
- **Dock** (`dockBg`, `dockRender`, `HTILE`): koyu buzlu hap, ince kenar, yumuşak gölge; saat kapsülü ve yuvarlak düğmeler daha düz;
  Library düğmesi açıkken beyaz daire + koyu simge; ayırıcı ve tutma çubuğu daha silik. Yerleşim/ölçüler değişmedi.
- **Pencereler** (`WM.paint`, `Pill.paint`): teal gradyan yerine sakin koyu antrasit; köşe 28; alt hap düz, gradyansız.

## Test
`node --check` temiz; `tools/*.test.js` (browser hariç) geçti. `icontheme.test.js` yeni Library kodunu denetleyecek şekilde güncellendi.

## DOĞRULANMADI
Gerçek cihazda / ekranda görülmedi. Renkler (`rgba(64,60,84,.80)` Library, `rgba(41,43,48,.975)` pencere, `rgba(32,34,40,..)` dock)
ve sütun sayısı (`cols=5`, `ts=88`) kodda tek yerden ayarlanır.

## Stage 41b — Referansa birebir Library + Dock
- **Dock** (`dockRender`): arka plan yok. Ortada VR · Library (beyaz daire) · Pencereleri küçült; altında saat · wifi · pil (dokununca Hızlı ayarlar);
  solda ortam küçük resmi (Sinema) + Kamera; sağda Tanı (zil) · Hızlı ayarlar · avatar (Ayarlar). Altta silik tutma çubuğu (sürükleme).
  Dock genişliği sabit; **sabitlenen uygulamalar artık dock'ta görünmez**, Library'den açılır (sabitleme verisi korunur).
- **Library**: kutu/kenarlık yok, çok hafif buzlu mor-gri zemin, gölgeli ince yazı; Kapat düğmesi kaldırıldı (dock'taki Library düğmesi açıp kapatır).
- Test: `icontheme.test.js` yeni dock'a göre güncellendi. `browser.test.js` bu ortamda zaman aşımına uğruyor (önceden de hariç tutulmuştu).

## Stage 41c — Dock eski haline döndü
Dock'un referanstaki çıplak 3 düğmeli hâli (41b) geri alındı: sabitlenen uygulamalı sade koyu hap dock (Stage 41) geri geldi,
dock genişliği yine ikon sayısına göre uzar. Library 41b'deki referans görünümünde kaldı.
