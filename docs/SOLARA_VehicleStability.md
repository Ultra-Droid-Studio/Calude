# SOLARA — Araç fizik kararlılığı düzeltmesi

Durum: **uygulandı; yol geometrisi çevrimdışı test edildi (PASS). Sürüş Roblox Studio'da test EDİLMEDİ →
Studio testinden önce tamamlanmış sayılmaz.** Analiz: `docs/SOLARA_VehicleStability_Analysis.md`.
Derleme: `place/SOLARA_VehicleStability.rbxlx` (önceki her şey + bu düzeltme).

Trafik sistemi, NPC'ler, araçların azami hızı, ivmesi, freni, yay ve sönüm değerleri değişmedi.

## Yapılanlar
### Yol (`ServerScriptService/WorldGen/RoadBuilder.lua`) — yol düzeni ve görünüm aynı
| Önce | Şimdi |
|---|---|
| Şerit çizgileri ve yaya geçidi şeritleri (2834 parça) çarpışmalı, yoldan 0.03 yüksek | Sadece görsel (`CanCollide = false`); bariyerler çarpışmalı kaldı |
| Rampa/otoyol birleşimlerinde 0.18–1.27 studluk basamaklar | Yol ucu bağlandığı platform/tabliye yüksekliğinde biter. Rampa tabliyeye ya da yönlü platforma açılı girdiğinde ana parça en uzak kenar kesişiminde biter, kenarın içinde kalan kısım yüzeyin 0.02 altında düz dolgu olur (boşluk ve çıkıntı yok) |
| Otoyol köşe diskleri yoldan 0.06 aşağıda | Yolla aynı seviye ve yanındaki yolun renginde |

### Araba (`Vehicles/CarPhysics.lua`, yer dosyası)
* Otomatik karşı direksiyon, hıza bağlı direksiyon sınırını en fazla ölçülen kayma açısı kadar aşabilir (yüksek hızda
  ~5° sınırın üstüne 15–17° eklenebiliyordu).
* Kayma algılama eşiği çekiş kontrolü payının üstünde: sadece pikap değişti (0.22 → 0.30); diğer araçlarda aynı.
* Fizik adımlama sabit: `Workspace.PhysicsSteppingMethod = Fixed` (`tools/place_patches.json`, değer 1).

### Motosiklet (`Controllers/VehicleController.lua`, `Vehicles/VehicleFactory.lua`)
* Çekiş kontrolü: tahrikli teker hedefi yer hızı + %12 (en az 1.5 stud/sn) patinaj; eskiden her zaman azami hız.
  Tork aynı → yerde hızlanma değişmez; havadaki teker artık azami hıza fırlamaz.
* ABS: frenlenen teker yer hızının %90'ının altına inmez.
* Yatış hedefi en fazla 1.5 rad/sn (~86°/sn) değişir.
* Dik tutma (`AlignOrientation`): tork toplam ağırlık × g × 60 → × 12 (40° yatışta gerekenin ~17 katı),
  tepki 30 → 18. Yeni bir dengeleme eklenmedi.
* F4 paneli motosikleti de gösterir: ön/arka teker teması, sıkışma, teker yüzey hızı ↔ yer hızı, yerden kesilme
  sayısı, çekiş kontrolü / ABS etkin mi, burun açısı, yatış hedefi / gerçek.

## Test
* `python3 tools/test_road_surface.py <lupa>` — **gerçek** `RoadBuilder.lua`'yı (bu dosya için Luau → Lua dönüşümüyle)
  gerçek haritayla kurar, her yolun üç şerit çizgisinde düğümden 45 stud boyunca 0.25 stud aralıkla sürüş yüzeyini
  ölçer, şüpheli noktayı 0.01 stud aralıkla yeniden ölçer.
  * Eski kod: 2834 çarpışmalı ince çizgi, şeritler boyunca 131 basamak (en büyük 1.30 stud). FAIL.
  * Yeni kod: çarpışmalı ince çizgi 0, basamak (> 0.025) **0**. PASS.
  * Her iki kodda da aynı 86 "yüzey yok" örneği var (rampa virajlarının dış köşesi ve 3 açılı kavşak): önceden
    var olan küçük boşluklar, bu çalışmada dokunulmadı.
* Lint: önceki durumla aynı (1 hata + 5 uyarı, hepsi eski dosyalarda).
* **İstenen 10 sürüş testi Roblox fiziği gerektirir; burada yapılamadı.** Aşağıdaki liste Studio içindir.

## Studio'da test (F4 açık)
1. Araba düşük / orta / yüksek hız: titreme, gövde sarsıntısı var mı? Paneldeki `temas 4/4` yüksek hızda düşüyor mu?
2. Yüksek hızda düz giderken ve şerit değiştirirken (çizgilerin üstünden geçerken) sarsıntı?
3. Otoyola rampadan gir/çık: rampa bitiminde vuruş var mı?
4. Yüksek hızda kontrollü viraj; hızlan ve sert fren: savrulma?
5. Motosiklet düşük / orta / yüksek hız; hızlanırken ve yön değiştirirken: paneldeki R tekerinin `kesilme` sayısı
   artıyor mu, `temas YOK` görülüyor mu, `ÇK AKTİF` ne sıklıkta?
6. Motosikletle sert fren: `ABS AKTİF`, arka teker kayıyor mu?
7. 10+ dakika sürüş: kararlılık.
8. Workspace özelliklerinde PhysicsSteppingMethod = **Fixed** görünüyor mu? Yollarda çizgiler ve kavşaklar eskisi
   gibi görünüyor mu (otoyol köşe disklerinde görsel titreşim var mı)?

## Bilinen sınırlamalar
* Studio'da test edilmedi; motosikletin arka teker kalkmasının tam mekanizması kanıtlanamadı (telemetri bunun için).
* Düzeltilen 49 rampa/platform birleşiminde NPC araçların şerit yükseklikleri değiştirilmedi (trafik sistemine
  dokunulmadı): bu birleşimlerde NPC araçlar birkaç stud boyunca yolun en fazla ~0.8 stud altında/üstünde görünebilir.
* Teker kütlesi (yaysız kütle %31–40) değiştirilmedi; yol düzeltmesinden sonra hâlâ sıçrama görülürse ikinci adım.
* Rampa virajlarındaki küçük boşluklar (yukarıda) ayrı bir düzeltme gerektirir.
* `PhysicsSteppingMethod` enum değeri (1 = Fixed) Studio'da doğrulanmalı.
