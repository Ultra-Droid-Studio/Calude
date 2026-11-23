# Stage 31 — "VR başlatılamadı" (pcol / length) düzeltmesi

## Belirti
Açılışta «VR başlatılamadı — Cannot read properties of undefined (reading 'length') @ pcol (index.html)».

## Neden
Stage 29'da yeni sekme sayfasının kısayolları `Settings.v.pins` anahtarına yazıldı. Aynı anahtarı dock'a sabitlenen uygulamalar
(`'cinema'`, `'gorilla'`, `'win7pc'`, ...) da kullanıyor. Liste dizgi + `{u,t}` nesnesi karışınca `BR.pins()` dizgi öğesinde
`p.u` bulamadı → `hostOf(undefined)` → `pcol(undefined)` → `.length` hatası. Aynı çakışma dock'u da (`Pins.get`) bozabilirdi.

## Düzeltme (`index.html`)
- Tarayıcı kısayolları artık ayrı anahtarda: `Settings.v.bpins` (`BR.pins`, `addPin`, `delPin`).
- Açılışta geçiş: eski karışık `pins` içindeki `{u,t}` nesneleri `bpins`'e taşınır, `pins` yalnızca dizgi kalır (ayarları silmek gerekmez).
- `pcol` boş/undefined değere dayanıklı.
- `tools/browser.test.js` yeni anahtara göre güncellendi (92 kontrol geçti).

## DOĞRULANMADI
Android derlemesi ve cihaz testi yapılmadı; yalnızca JS sözdizimi ve `browser.test.js`.
