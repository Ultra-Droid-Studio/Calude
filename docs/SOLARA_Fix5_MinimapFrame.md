# SOLARA — Hata düzeltme 5: Mini harita içeriğinin çerçeve dışına taşması

Durum: **düzeltme uygulandı, Roblox Studio'da test edilmedi.**
Derleme: `place/SOLARA_Fix5_MinimapFrame.rbxlx` (Aşama 1–4 + Düzeltme 1–5)
Kullanıcı gözlemi: Sokaklar mini haritanın alanından dışarı çıkıyor, altındaki yönlendirme yazısına kadar ve
onu da geçerek uzanıyor. İstek: bir çerçeve olsun, harita onun içinde kalsın, dışına çıkamasın.

## Neden
1. **Döndürülmüş öğeler kırpılmıyordu.** `MapCanvas` her yol parçasını ve rota çizgisini `Rotation` ile çiziyordu
   (yatay yol 0°/180°, dikey yol ±90°, eğik yollar başka açılar). Roblox'un eski davranışında `ClipsDescendants`
   döndürülmüş öğeleri kırpmaz → dikey ve ters yönlü yollar, rota çizgisi kabın dışına taşıyordu.
2. **Kırpma CanvasGroup'a bağlıydı** (Düzeltme 4'te güvenlik kırpıcısı eklendi; yine de döndürülmüş öğeler için
   yeterli değildi).
3. Koordinat dönüşümü doğru: mini harita oyuncuyu merkezde tutuyor (`MapCanvas:SetView`), işaretler doğru yerde;
   sorun hesap değil kırpma.

## Değişiklikler
| Dosya | Değişiklik |
|---|---|
| `FrontEnd/Map/MapCanvas.lua` | Haritada **hiç döndürülmüş öğe yok**: eksene paralel yol/rota parçası = tek dikdörtgen (genişlik/yükseklik yer değiştirir), eğik olanlar (919 yolun 29'u) = üst üste binen yuvarlak noktalar. Rota kalınlığı yakınlaşmayla değişince eğik rota noktaları gerekirse yeniden dizilir (boşluk kalmaz). Tam haritada oyuncu oku (tek döndürülmüş öğe) görüntü alanının dışındaysa gizlenir. Yol GUI parçası 919 → 1806 (bir kez çizilir, karo ayıklaması aynı). |
| `Controllers/MinimapController.lua` | Mini harita artık sabit kare bir **çerçeve**: `ClipsDescendants = true` olan sıradan bir Frame (CanvasGroup kaldırıldı) + aynı dikdörtgende görünür kenarlık (beyaz, 2 px). "N" işareti çerçevenin içine alındı. Yönlendirme paneli harita öğelerinin üstünde (ZIndex 10). |

Korunanlar: mini haritanın konumu ve boyutu (DrivingLayout), yakınlaştırma davranışı, merkez oku, GPS rotası,
hedef iğnesi, önemli yer simgeleri, tam ekran harita.

Görünüm değişikliği: mini harita yuvarlaktan **köşeli kareye** döndü (istenen çerçeve). Köşeler bilerek düz:
`ClipsDescendants` yuvarlak köşelere uymaz; yuvarlak köşede harita köşeden taşardı.

## Studio test senaryoları
1. Yürü ve araç sür (yavaş/hızlı): hiçbir sokak, rota çizgisi veya simge çerçevenin dışına çıkmamalı; yönlendirme
   paneli her zaman okunur kalmalı.
2. Dikey (kuzey-güney) sokaklarda ve eğik yollarda (otoyol rampaları, kırsal yollar) özellikle kontrol et.
3. Hedef seç (M → bir yer): rota çizgisi çerçevede kırpılmalı; yol dışı bitişte kesikli son kısım da.
4. Tam ekran harita: yolları/rotayı panele doğru kaydır → harita görünümünün dışına (sağ panele) taşmamalı; oyuncu
   oku görünüm dışına kaydırılınca gizlenmeli.
5. Çözünürlükler: masaüstü 1280×720, 1920×1080, 2560×1440; Device Emulator'da telefon (yatay/dikey) ve tablet.
6. Mobil/tablette düşük grafik kalitesinde 1. adım (önceki siyah katman da gelmemeli).

## Bilinen sorunlar
* Eğik yollar yakından (tam haritada en yakın zoom) hafif "boncuklu" kenarlı görünebilir.
* Uzun yolların karo ayıklaması orta noktaya göre (önceden de böyleydi); çok uzun bir yol, orta noktası görünüm
  dışındaysa kenarda geç görünebilir.
