# SOLARA — Şehir genişletme planı (Bölüm 1: analiz + plan)

Durum: **sadece plan; kod değiştirilmedi.** Her aşama ayrı onay ve Roblox Studio testiyle ilerler.

## 1. Mevcut şehir (ölçüm: `MapData` + `BuildingBuilder`, çevrimdışı sayım)

* Dünya **çalışma anında** `MapData`'dan üretilir (ya da Studio'da "pişirilir"). Binalar `BuildingBuilder` stillerinden
  çıkar: 1333 arsa, 19 bölge, 45 bina stili, 90 önemli yer (POI). Her bina arsanın tohumuyla (seed) her seferinde aynı.
* Binaların **içi dolu** (cephe = tek beton kutu + önüne cam, kapı plakası, tente, tabela). İç mekân yok.
* Kapı kayıt sistemi var (Yaşayan Şehir): 1278 kapı, her biri kaldırıma bağlı, NPC'ler girip çıkıyor
  (`Shared/Ambient/Entrances.lua`). Kapı görselleri istemcide, oyuncuya 130 stud yakınken.
* Tabelalar: hepsi aynı biçim — siyah zemin üzerine **her zaman yanan** neon şerit, tek yazı tipi (`Kit:Label`).
  Süsleme dükkânları (`storefront_plain`) 16 isimlik listeden rastgele isim alıyor ("Bakery", "Pharmacy"... tekrar ediyor).
* Işık: `WeatherService` gün-gece döngüsü, `Workspace.IsNight`, `StreetLamp` etiketli lambalar gece yanıyor.
  Tabelalar ve vitrinler gece/gündüz ayrımı yapmıyor.
* **Silah, envanter ve para sistemi YOK** (yalnızca boş `InventoryRemotes` ve boş silah animasyon yerleri).

### Bölgeler ve ticari karakter
| Bölge | Tür | Bina dağılımı (öne çıkanlar) | Ticari potansiyel |
|---|---|---|---|
| Solara Centro | şehir merkezi | 51 ofis, 40 modern apartman, 36 kule, 7 dükkân, AVM, sinema, atari salonu | Ana cadde: kulelerin zemin katlarına vitrin, büyük market, restoran, eczane, internet kafe (atari salonunun yanı) |
| Costa Verano | sahil | 54 art deco alçak bina, 34 modern apartman, 20 süs dükkânı, 7 otel; Ocean Drive, Sol Boulevard | **Şehrin kimliği**: pastel art deco + gece neon (Vice City havası); kafe, restoran, fast food, otel |
| Old Riverside | eski mahalle | 41 tuğla apartman, 38 sıra ev, 24 süs dükkânı | Mahalle sokakları: fırın, bakkal, manav, lokanta, milyoncu |
| Vista Norte | kasaba | 210 ev, 24 süs dükkânı, süpermarket | Kasaba çarşısı: süpermarket, eczane, fırın, küçük market |
| Isla Coral | tatil adası | 31 art deco, 17 süs dükkânı, villalar | Sahil kafeleri, dondurma, dalış dükkânı |
| Palm Heights / Bayview | konut | ~460 müstakil ev, 4 dükkân | Sakin: köşe bakkalı, kafe, fırın |
| Ironside | sanayi | depo, fabrika, liman | Silah dükkânı ve yedek parça için uygun kenar bölge |
| Dry Creek / Pinebrook | kırsal kasaba | az sayıda dükkân | Yerel dükkânlar (mevcut) |

* Dükkân arsaları: 127 (ortalama 53 × 57 stud, yükseklik ~22) + 90 art deco bina. Dükkânların önü 158 sokakta,
  57 caddede (avenue).
* Mevcut POI dükkânları: 2 süpermarket, 7 köşe marketi, 2 manav, 6 kafe, 9 restoran, 3 fast food, 7 genel mağaza.

## 2. Temel kararlar

1. **Harita yeniden kurulmaz.** Yollar, arsalar, bina yerleri ve boyutları aynı kalır. Değişen: dükkân stillerinin
   cephesi ve seçilen dükkânların gövdesi (içi boş kabuk + gerçek kapı açıklığı).
2. **İşletme kaydı** (`Shared/Businesses.lua`, yeni): arsa → işletme türü, özgün isim, marka kimliği (renk, yazı tipi,
   tabela biçimi). Harita verisi değişmez; işletmeler ayrı, düzenlenebilir bir tablodadır. Önce bölgeler ve caddeler
   seçilir, sonra işletmeler bölgeye uygun türden atanır (her binaya rastgele dükkân yok).
3. **Kabuk sunucuda, iç mekân istemcide.** Girilebilir dükkânın duvarları, zemini, tavanı ve kapı açıklığı sunucuda
   (herkes için çarpışma). Raflar, ürünler, mobilya ve iç ışıklar **istemcide, oyuncu yakınken** (≈90 stud) havuzdan
   kurulur, uzaklaşınca kaldırılır. Bu, Yaşayan Şehir'deki kapı/NPC yöntemiyle aynı ve mobil için en hafifi.
4. **Model kaynağı.** Bu ortamdan Roblox Creator Store'a erişemiyorum ve model içe aktaramıyorum. Öneri:
   * Varsayılan: özenli, düşük parça sayılı **prosedürel Roblox modelleri** (her eşya bir kez şablon olarak tanımlanır,
     tekrar kullanılır; doğru ölçek, uygun materyal).
   * İsteğe bağlı yükseltme: `ReplicatedStorage.ShopAssets` klasörü — Studio'da sen lisansı uygun (CC0 ya da kendi)
     bir model koyarsan prosedürel olanın yerine o kullanılır (araç paketindeki `VehicleModels` yöntemi).
   * Dürüst beklenti: parça tabanlı modellerle "GTA 6 seviyesi" mümkün değil; hedef tutarlı, temiz, canlı bir şehir.
5. **Silah dükkânı** yalnızca görsel bir işletme olur (vitrin, tezgâh, dekoratif sergi). Satın alma, envanter ya da para
   sistemi olmadığı için "satın al" düğmesi veya çalışıyormuş gibi bir etkileşim eklenmez.
6. **Gece/gündüz:** tabela ve vitrin ışıkları `Workspace.IsNight`'a bağlanır (gündüz düz renk, gece parlak). Gerçek ışık
   kaynakları (SurfaceLight/PointLight) sadece oyuncuya yakın, sayısı sınırlı; uzakta sadece parlak materyal.

## 3. Şehir kimliği (Bölüm 2)

| Bölge | Mimari dil | Gündüz | Gece |
|---|---|---|---|
| Costa Verano / Isla Coral | Art deco: yuvarlatılmış köşeler, yatay şeritler, pastel (pembe, turkuaz, krem), tenteler, balkon, çatı kulesi | Doğal pastel, güneş tentesi | Cephe kenarlarında **seçili** pembe/turkuaz/mor neon şeritler, aydınlık vitrinler |
| Solara Centro | Modern cam kuleler; ana caddede zemin katta sürekli vitrin bandı, reklam panoları | Cam, beton, gri-mavi | Vitrin bandı ve reklam panoları aydınlık, kulelerde rastgele yanan pencereler |
| Old Riverside | Eski tuğla, sıra evler, dar dükkânlar, ahşap tabelalar, saçak, klima üniteleri | Sıcak tuğla, yeşil/kırmızı tente | Sarı sıcak ışık, küçük asılı tabelalar |
| Vista Norte / kasabalar | Alçak kasaba çarşısı, düz çatılar, yan tabela | Açık renkler | Sade, sıcak vitrin ışığı |

Ortak detaylar (bölgeye göre farklı yoğunlukta): balkon ve teras, çatı korkuluğu, su deposu, klima üniteleri,
cephe pervazları, yan (bayrak) tabelalar, kaldırım saksıları, bank, çöp kutusu, reklam panosu. Her şeyi neon ile
doldurmak yok: neon sadece Costa/Coral'ın seçili cephelerinde ve tabelalarda.

## 4. İşletmeler ve yerleşim (Bölüm 3–4)

Önerilen dağılım (pilot sonrası genişletilir; isimler özgün, değiştirilebilir):

| Tür | Adet | Nerede | Örnek isim |
|---|---|---|---|
| Süpermarket | 2 (mevcut) | Centro ana cadde, Vista Norte | SolMart, Norte Market |
| Küçük market | 4–5 | Palm Heights, Bayview, Costa yan sokak | Corner 24, Bayview Corner Store (mevcut) |
| Bakkal | 4 | Riverside, Vista, Palm | Esquina Siete, Don Tito's |
| Fırın | 4 | Riverside, Vista, Bayview, Costa | Horno Dorado, Miga & Co. |
| Manav | 3 | Riverside (mevcut), Costa (mevcut), Vista | Verde Fresco |
| Eczane | 3 | Centro, Vista, Costa | Farmacia Brisa, SolaCare |
| Restoran (modern) | 3 | Centro, Costa Ocean Drive | Azul Kitchen, Trattoria Luna (mevcut) |
| Fast food | 3 (mevcut) + 1 | Centro, Costa | Flamingo Burger, Taco Ola (mevcut) |
| Mahalle lokantası | 3 | Riverside, Vista, Dry Creek | Old Mill Diner (mevcut), Mamá Lucía |
| Kafe | 6 (mevcut) + 2 | Centro, Costa, Coral, Palm | Brew & Bay Café (mevcut), Brisa Coffee |
| İnternet kafe | 2 | Centro (atari salonunun yakını), Riverside | Byte Harbor, Pixel Lounge |
| Milyoncu | 2 | Riverside, Vista | Todo Mil, Casa 99 |
| Silah dükkânı | 1 | Ironside, ana yola bakan kenar arsa | Gulfline Outfitters |

Yerleşim kuralları:
* Ana cadde (Centro avenue'ları, Ocean Drive, Sol Boulevard): büyük market, restoran, eczane, kafe, modern mağaza.
* Mahalle sokakları (Riverside, Vista): bakkal, fırın, manav, küçük market, lokanta, milyoncu.
* Aynı türden iki işletme arasında en az bir blok mesafe; her caddede tür çeşitliliği.
* Dış sergi, masa ve stantlar **sadece arsa içinde**: bina cephesi ile arsa sınırı arasındaki ön bahçede. Kaldırıma ve
  yola taşma, komşu kapının önünü kapatma yok. Bu çevrimdışı testle denetlenir.
* Mevcut POI'ler korunur; yeni işletmeler, rastgele isimli süs dükkânlarının (`storefront_plain`) ve uygun art deco
  binaların zemin katlarının yerini alır. İstersen haritada ve GPS'te de yer olarak görünürler (aşağıdaki sorular).

## 5. İç mekânlar (Bölüm 5)

* Pilotta her türden **bir** girilebilir örnek; sonra her türün 2–3 farklı yerleşim varyasyonu (aynı türün iki dükkânı
  birebir aynı olmasın: raf düzeni, renk, tezgâh yeri tohuma göre).
* Ölçüler: kapı en az 5 × 8 stud (R15 rahat geçer), koridorlar en az 4 stud, tavan 12–14 stud.
* Her iç mekân: zemin kaplaması, duvar rengi, tavan ışıkları, tezgâh/kasa, türe özel mobilya. Örnek içerikler:

| Tür | İçerik |
|---|---|
| Fırın | ekmek rafları, cam pasta vitrini, tezgâh, kasa, fırın ağzı (arka), un çuvalları |
| Bakkal / küçük market | dar raflar, içecek dolabı (ışıklı), cips/şeker standı, kasa, sepetler |
| Süpermarket | uzun raf sıraları, içecek reyonu, meyve-sebze reyonu, 3–4 kasa, alışveriş arabaları, depo kapısı |
| Manav | eğimli kasalar (renkli meyve/sebze), dış stant, terazi, kasa |
| Eczane | arkada düzenli ilaç kutusu rafları, danışma tezgâhı, bekleme sandalyeleri |
| Restoran / lokanta / fast food / kafe | masa-sandalye, sipariş tezgâhı, menü panosu, görünür mutfak; dışarıda masalar (ön bahçe) — dördü farklı düzen ve renkte |
| İnternet kafe | sıra sıra masa, monitör, klavye, oyuncu koltuğu, ağ dolabı, karşılama; mavi/mor iç ışık |
| Milyoncu | yoğun, renkli raflar: mutfak eşyası, oyuncak, temizlik, dekor |
| Silah dükkânı | kilitli cam vitrinler, duvar sergisi (dekoratif, markasız silüetler), tezgâh, güvenlik kapısı |

* Çarpışma: mobilya duvarlara ve birbirine girmez (çevrimdışı kutu çakışma testi); kapı önü ve geçitler boş kalır
  (en az 4 stud geçit testi).

## 6. Tabelalar (Bölüm 6)

* Her markanın kendi kimliği: renk paleti, yazı tipi (Roblox'un farklı yazı tipleri), tabela biçimi:
  kutu tabela, tek harf neon yazı, asılı/bayrak tabela, tente üstü yazı, vitrin camı yazısı, çatı panosu.
* Boyut cephe genişliğine göre sınırlı (gereksiz büyük değil), cephenin içinde (taşma testi), okunabilir.
* Gündüz: düz/mat renk. Gece: parlak; restoran, market ve eczane vitrinleri ışık verir.
* Gerçek marka, logo ya da başka oyunlardan isim kopyalanmaz.

## 7. NPC uyumu (Bölüm 7)

NPC sistemi yeniden yazılmaz. Her işletmeye veri olarak bağlantı noktaları eklenir:
`BusinessEntrance` (mevcut kapı kaydına işletme türü ve kimliği eklenir), `WaitSpot` (vitrin önü bekleme, sıra),
`BrowseSpot` (dış stant/manav kasası önü), `SeatSpot` (dış masalar). Bunlar `Entrances` ile aynı testten geçer
(kaldırıma bağlı, yolda değil, arsa içinde). Davranışları kullanmak ileriki bir aşamadır.

## 8. Performans (Bölüm 9)

* Her aşamada çevrimdışı parça sayımı (gerçek inşa kodu, sahte Kit ile) ve bir bütçe: cephe yükseltmesinin toplam parça
  artışı ve bina başına üst sınır raporlanır.
* İç mekânlar yalnızca yakında (≈90 stud), en fazla 2–3 aynı anda, havuzlu; iç ışıklar sadece içi kurulu dükkânda.
* Gece ışıkları: uzakta parlak materyal, yakında sınırlı sayıda gerçek ışık (en yakın N).
* Tekrarlanan eşyalar tek şablondan; gereksiz kopya yok. Dokunmatik cihazlarda ayrıntı ayarı (`GraphicsController`)
  ile iç mekân yarıçapı ve ışık sayısı düşer.
* Mobil/tablet FPS testi yalnızca cihazda yapılabilir.

## 9. Aşamalar (Bölüm 10 sırası, her biri ayrı onay + Studio testi)

| # | Aşama | Çıktı | Benim yapabileceğim test | Senin Studio testin |
|---|---|---|---|---|
| 1 | Analiz + plan | bu belge | — | — |
| 2 | Bölgeler ve işletme kaydı | `Businesses.lua`, bölge/cadde seçimi, isimler | dağılım ve mesafe kuralları, isim tekrarı yok | yok (veri) |
| 3 | Cephe ve atmosfer | bölge mimari kitleri, tabela sistemi, gece ışıkları | parça bütçesi, tabela taşma, arsa dışı taşma | gündüz/gece görünüm, FPS |
| 4 | Fırın, bakkal, küçük market, manav | kabuk + iç mekân + dış sergi | kapı/geçit ölçüsü, çakışma, kaldırım | içine gir, gez |
| 5 | Eczane, restoranlar, internet kafe | aynı | aynı | aynı |
| 6 | Süpermarket, milyoncu | aynı | aynı | aynı |
| 7 | Silah dükkânı (görsel) | aynı | aynı | aynı |
| 8 | İç mekân tamamlama ve varyasyonlar | tür başına 2–3 düzen | aynı | aynı |
| 9 | Tabela ve gece ışıklarının son hali | marka kimlikleri | sayı sınırları | gece turu |
| 10 | Performans ve görsel kalite | ayrıntı seviyesi, ölçümler | parça/ışık bütçesi | telefon + tablet |

Her aşama sonunda: derleme (`place/SOLARA_City<N>.rbxlx`), rapor, Studio test listesi. Senin testin gelmeden
sonraki aşamaya geçilmez.

## 10. Riskler / sınırlamalar
* Dünya üretimi (BuildingBuilder) değişecek: bu, açık onay gerektiren bir dünya değişikliği. Yol ve arsa düzeni aynı kalır.
* Pişirilmiş (baked) bir dünyan varsa yeniden pişirmen gerekir (`WorldBuilder.Bake()`).
* Kapı yerleri değişen dükkânlarda NPC kapı kaydı aynı formülle güncellenir ve test edilir.
* Görsel kalite parça tabanlı modellerle sınırlı; dışarıdan model istenirse lisans ve içe aktarma Studio'da senin tarafında.
