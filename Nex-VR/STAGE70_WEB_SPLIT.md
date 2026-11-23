# Stage 70 — index.html parçalara bölündü (davranış değişmedi)

## Yapılan
- `index.html` (8.891 satır) → `web/` altında: `style.css`, `head-guard.js`, `template.html`, 18 adet `js/NN-*.js`.
- `tools/build-html.js`: parçaları birleştirip `assets/index.html` üretir (`--check` ile sadece denetler),
  ayrıca `web/dev.html` (ayrı `<link>`/`<script>` ile, derlemeden tarayıcıda açmak için) üretir.
- `tools/htmlbuild.test.js`: güncellik, sözdizimi, çift tanım/çakışma, "tanımdan önce çağrı" denetimi.

## Doğrulama
- Üretilen `assets/index.html`, bölmeden önceki dosyayla **bayt bayt aynı** (498.563 karakter, `cmp` farksız).
  Dolayısıyla APK, Java'daki jeton enjeksiyonu ve regex tabanlı eski testler etkilenmedi.
- Tüm eski testler aynı sonucu veriyor (tek başarısız: `shizuku.test.js` "başlık çubuğunda Klavye düğmesi",
  Stage 67'den kalma, bu aşamayla ilgisi yok).
- Sahte ortamda tek parça (IIFE) ve dev (ayrı parça) sürümü aynı noktaya kadar aynı davranıyor.
  Gerçek tarayıcıda/WebView'de `web/dev.html` denenmedi.
