# SOLARA — Şehir genişletme, aşama 2: bölgeler ve işletme kaydı

Durum: **uygulandı; çevrimdışı testler PASS. Roblox Studio'da test EDİLMEDİ.** Plan: `SOLARA_CityExpansion_Plan.md`.
Derleme: `place/SOLARA_City2.rbxlx` (önceki her şey + bu aşama). Dağılım görseli: `docs/city_businesses_preview.png`.

Kararlar (onaylandı): bina üretimi değişebilir (harita düzeni aynı), pilot sokak **Old Riverside**, silah dükkânı
şimdilik yalnızca bir yer (satın alma sistemi yok), yeni işletmeler haritada ve GPS'te görünür.

## Ne değişti
| Dosya | Değişiklik |
|---|---|
| `Shared/BusinessData.lua` (yeni, üretilmiş) | 127 işletme: arsa, tür, özgün isim, marka (yazı tipi, ana/ikinci renk, tabela biçimi). Elle düzenlenebilir |
| `Shared/Businesses.lua` (yeni) | Tür kataloğu (TR/EN adı, harita kategorisi) ve `Apply`: arsalara işletme kaydı, yeni işletmeleri POI yapar |
| `Shared/MapDefinitions.lua` | Ayrıştırma sonunda `Businesses.Apply`; dükkân türleri listesine işletme türleri eklendi |
| `WorldGen/BuildingBuilder.lua`, `WorldGen/Kit.lua` | Süs dükkânlarının (`storefront_plain`) tabelası: işletmenin adı, marka rengi (yazı + tente), marka yazı tipi. Binanın gövdesi, rengi, boyutu, yeri aynı (rastgele sayı sırası korundu) |
| `FrontEnd/Map/MapCanvas.lua`, `FrontEnd/Strings.lua` | Yeni türlerin harita simgeleri; yeni kategori "Silah dükkânı" (Si). "Hastane" kategori adı "Sağlık" oldu (eczane de burada) |
| `tools/plan_businesses.py` | Seçimi yapan araç (kurallar aşağıda). `tools/test_businesses.py`, `tools/business_map_preview.py` |
| `tools/ambient_data.py`, `tools/test_navigation.py` | Çevrimdışı testler oyunla aynı veriyi kullansın diye işletme POI'lerini de yükler |

Mevcut 36 dükkân POI'sinin adı ve türü değişmedi (sadece marka bilgisi eklendi, tabelaları bu aşamada aynı).

## Bölgeler ve dağılım
| Bölge | Karakter | Yeni (haritada) | Diğer dükkânlar |
|---|---|---|---|
| Old Riverside (pilot) | eski mahalle | 2 fırın, 2 bakkal, manav, eczane, internet kafe, milyoncu, kafe, **silah dükkânı** (Ironside'a en yakın arsa) | berber, terzi, nalbur, plakçı, ... |
| Vista Norte | kasaba çarşısı | eczane, fırın, 2 bakkal, milyoncu, manav, market, fast food | nalbur, çiçekçi, kitapçı, optik, ... |
| Costa Verano | sahil, ana cadde | restoran, fast food, eczane, fırın, kafe | butik, sörf, dondurma, kuyumcu, galeri, ... |
| Isla Coral | tatil adası | restoran, fast food, fırın | sörf, dondurma, butik, seyahat, ... |
| Dry Creek | kasaba | bakkal, fırın | nalbur, berber, çamaşırhane, spor |
| Solara Centro | merkez | — (boş dükkân arsası yok; zemin kat vitrinleri aşama 3'te cepheyle gelir: eczane, internet kafe, restoran) | — |

Toplam (haritada): süpermarket 2, market 8, bakkal 5, fırın 6, manav 4, eczane 3, restoran 7, fast food 6, lokanta 4,
kafe 8, internet kafe 1, milyoncu 2, silah dükkânı 1, mağaza 7. Haritada olmayan 63 küçük dükkân (24 tür) artık
tekrarsız özgün isimli.

Seçim kuralları: ana cadde türleri (eczane, restoran, kafe, fast food, internet kafe) önce caddeye bakan arsayı,
mahalle türleri ara sokağı seçer; aynı türden iki işletme arasında en az 200–600 stud (türe göre); her seçim ilçedeki
diğer işletmelerden en uzak arsayı tercih eder (yayılım). İsimler ve markalar özgündür, gerçek marka kopyası yoktur.

## Test (çevrimdışı)
* `tools/test_businesses.py` — gerçek `Businesses.lua` + `BusinessData.lua` + `Entrances.lua`, gerçek harita: arsa başına
  bir işletme, sadece dükkân arsaları, tüm istenen türler var, isimler tekrarsız (diğer POI'lerle de), yazı tipleri
  geçerli, tür içinde marka tekrarsız, mahalle türleri doğru bölgede, silah dükkânı kuralı, aynı tür mesafesi, kotalar,
  POI kimliği/giriş noktası kuralı, giriş noktası yolda değil, **28 yeni işletmenin 28'inin de kaldırıma ulaşan
  doğrulanmış kapısı var**. PASS. (Bilgi: önceden var olan 3 kırsal POI'nin kaldırımsız yolda kapısı yok; değişmedi.)
* `tools/test_navigation.py` — 14 doğma noktasından 118 yerin hepsine rota (1652 rota) PASS.
* `tools/test_ambient.py` — trafik/yaya/kapı testleri yeni POI'lerle (yeni yaya bekleme noktaları): sonuç rapora eklenir.
* Lint: önceki durumla aynı (1 hata + 4 uyarı, eski dosyalarda).

## Studio'da bakılacaklar
1. Old Riverside, Vista, Costa, Coral, Dry Creek'te dükkân tabelaları: her birinde farklı isim, renk ve yazı tipi;
   yazı okunuyor mu, tabelaya sığıyor mu?
2. Tam harita: yeni simgeler (fırın, eczane, silah dükkânı "Si" ...), yerler listesinde yeni isimler.
3. Bir yeni işletmeyi (ör. Old Riverside'da "Gulfline Outfitters" ya da "Byte Harbor") hedef seç: GPS seni dükkânın
   önüne getiriyor mu, varış doğru yerde mi?
4. Konsolda `[WorldGen]` uyarısı (bina üretilemedi / bilinmeyen yazı tipi) var mı?
5. Dünyayı pişirdiysen (`WorldBuilder.Bake()`), tabelaların değişmesi için yeniden pişir.

## Sınırlamalar
* Bu aşama veri + tabela ismi; cephe, iç mekân, gece ışıkları sonraki aşamalarda.
* Mevcut 36 dükkânın tabelası henüz eski tek biçimde; marka bilgileri aşama 3'te kullanılacak.
* Centro'da yeni işletme yok (boş dükkân arsası yok) — aşama 3'te kulelerin zemin katlarına eklenecek.
* Yazı tiplerinin Roblox'ta görünümü Studio'da kontrol edilmeli.
