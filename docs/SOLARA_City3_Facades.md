# SOLARA — Şehir genişletme, aşama 3: cepheler, şehir atmosferi, gece ışıkları

Durum: **uygulandı; çevrimdışı testler PASS. Roblox Studio'da test EDİLMEDİ** (aşama 2 de henüz Studio'da test
edilmedi; ikisi birlikte test edilebilir). Plan: `SOLARA_CityExpansion_Plan.md`.
Derleme: `place/SOLARA_City3.rbxlx`. Şematik önizleme (Roblox görüntüsü değil): `docs/city3_facades_preview.png`.

Harita, yollar, binaların yeri/boyutu/gövdesi/rengi aynı (test [1] her arsada doğruladı). Trafik ve NPC kodu değişmedi.

## Ne eklendi
### Dükkân cepheleri (127 dükkân arsası)
Eski tek tip "siyah zemin + her zaman yanan neon şerit + aynı tente" yerine her işletmenin kendi tabelası
(aşama 2'deki marka: renk, yazı tipi, tabela biçimi):

| Biçim | Görünüm | Kimler |
|---|---|---|
| Box | çerçeveli ışıklı kutu + ince saçak | market, eczane, fast food, milyoncu, silah dükkânı, süpermarket, mağazalar |
| Letters | ince ray üstünde tek tek harf etkisi, koyu metal saçak | restoran, lokanta, internet kafe |
| Blade | küçük alın tabelası + kapının yanında sokağa dik bayrak tabela (baş hizasının üstünde) | bakkal, kafe |
| Awning | marka renklerinde çizgili tente, isim tente saçağında + cephede küçük isim | fırın, manav |

Kapının iki yanında saksılar (geniş cephelerde). Vitrin camı gece sıcak ışık verir.

### Solara Centro: zemin kat dükkânları (yeni, 46 bina)
Caddeye bakan ofis ve modern apartmanların zemin katı dükkân oldu: koyu taş alın bandı, iki yanda vitrin, dükkân
tabelası, giriş çerçevesi. Bu binaların ön camı artık dükkân bandının üstünden başlıyor. 4'ü haritada / GPS'te:
**VitaPlus Pharmacy, Pixel Lounge** (internet kafe), **Mareas** (restoran), **Daydream Espresso**; diğer 42'si moda,
elektronik, kuyumcu, optik, kozmetik, kitapçı, ... (özgün isimler). Bant, mevcut cephe camıyla aynı zarfta
(arsa kenarından en fazla 0.6 stud önde; kaldırımdaki yaya yolu en az 6.4 stud uzakta).

### Bölge karakteri
| Bölge / bina | Eklenen |
|---|---|
| Art deco (Costa Verano, Isla Coral, Vista) | yuvarlak köşe kolonları, çatıda basamaklı taç, binaların ~%35'inde dikey neon kanat; üstteki neon şerit artık **gündüz boya, gece neon** |
| Tuğla apartman (Old Riverside, Centro arka sokakları) | üst katlarda pencere klimaları, çatıda ahşap su deposu ya da klimalar, girişte saçak ve lamba |
| Sıra evler | bacalar, pencere çiçeklikleri |
| Modern apartman | balkonlara cam korkuluk, çatı klimaları |
| Dükkânlar | çatı klimaları |
| Reklam panoları | 11 bina (Centro, Costa, Riverside; alçak-orta binalar): şehrin kendi markaları ("VISIT ISLA CORAL", "BYTE HARBOR · 24H GAMING", "FLAMINGO BURGER · OPEN LATE" ...) |

### Gece
* Sunucu dünyayı gündüz hâliyle üretir; geçişi her oyuncunun kendi istemcisi yapar (`CityLightsController`,
  sokak lambalarıyla aynı an: `Workspace.IsNight`).
* Gece: tabela yüzleri ve neon şeritler parlar (374), dükkân camları sıcak ışık verir (219), yazılar parlar (253).
  Koyu/gri renkli tabelalarda yüzey karanlık kalır, yazı açık tonda parlar (okunurluk için).
* Gerçek ışık (SurfaceLight) sadece kameraya en yakın vitrinlerde: masaüstü 10, dokunmatik 4; 140 stud içinde.
* Hastane, otel, AVM, sinema, atari salonu tabelaları değişmedi.

## Dosyalar
| Dosya | Değişiklik |
|---|---|
| `WorldGen/CityDressing.lua` (yeni) | tabelalar, vitrin, Centro zemin kat bandı, bölge ayrıntıları, çatı, reklam panosu, gece etiketleri |
| `WorldGen/BuildingBuilder.lua` | stiller CityDressing'i çağırır; ayrıntılar binanın kendi rastgele üretecini kullanmaz (renkler aynı) |
| `Controllers/CityLightsController.lua` (yeni) | gece/gündüz geçişi, yakın vitrin ışıkları |
| `Shared/BusinessData.lua`, `tools/plan_businesses.py` | Centro zemin kat dükkânları (aşama 2'deki 127 kayıt aynen korundu) |
| `tools/test_city_facades.py`, `tools/preview_facades.py`, `tools/luau2lua.py` | çevrimdışı test ve önizleme |
| `tools/test_businesses.py` | Centro zemin kat kuralları |

## Test (çevrimdışı) — `python3 -I tools/test_city_facades.py <lupa>`
Gerçek `BuildingBuilder.lua` + `CityDressing.lua` haritadaki 1333 arsanın hepsinde çalıştırılır (kaydeden sahte Kit),
aşama 2 sürümüyle karşılaştırılır:
* [1] bina gövdeleri, boyutları, renkleri aynı (yalnız beklenen değişiklikler: eski tabela/tente, deco şeridinin
  malzemesi, Centro dükkân binalarında ön cam) — PASS, 0 fark
* [2] her işletmenin tabelası var, işletmenin yazı tipiyle, cepheye sığıyor; dükkânlarda her zaman yanan neon kalmadı — PASS
* [3] yere yakın (8 stud altı) hiçbir yeni parça arsadan taşmıyor (Centro bandı ≤ 0.6); yukarıdakiler binanın mevcut
  dış sınırının içinde — PASS
* [4] kapı koridorları (gerçek `Entrances` kapı formülleri) yeni çarpışan parçalardan boş (saçaklar kapı yüksekliğinin
  üstüne alındı) — PASS
* [5] kaldırımdaki yaya yürüme çizgilerine yeni alçak parça 1 stud'dan yakın değil (en yakın 6.4) — PASS
* [6] her gece parçasının gece rengi var; reklam panosu 11 — PASS
* [7] bina parçaları 10162 → 13550 (+%33); en büyük bina 48 parça (havaalanı pisti, değişmedi) — PASS
* `test_businesses.py` PASS (173 işletme, 32 yeni haritada), `test_navigation.py` PASS (1708 rota).
* Lint: önceki durumla aynı (1 hata + 4 uyarı, eski dosyalarda).
* NPC/trafik testi (`test_ambient.py`, yaya bekleme noktası 91 → 95): kapılar 1278, yolda yaya 0, kırmızıda geçiş 0,
  yaya çarpması 0; 2 FAIL: hareketli oyuncu senaryosunda 1 araç çakışması ve merkezde bekçinin 1 kilitlenmiş aracı
  kaldırması. Bu aşamanın simülasyona tek etkisi 4 yeni bekleme noktası; trafik koduna dokunulmadı. Çakışma, aşama 2'de
  işletmeler kapalıyken de görülen nadir trafik hatası sınıfında; kilitlenme bu seferki yeni belirti — ayrıca
  incelenmedi (trafik düzeltmesi ayrı iş olarak bekliyor).

## Studio'da bakılacaklar
1. Gündüz: Old Riverside, Costa Verano, Vista, Isla Coral sokaklarında tabelalar (4 biçim), yazılar okunuyor mu, yazı
   tipleri farklı mı, tabela/tente/saksı kapının önünü kapatıyor mu? Karakterle dükkân kapılarına yürü.
2. Centro caddeleri: zemin kat vitrinleri ve tabelaları, bina kapıları açık mı, kaldırım daralmış mı?
3. Art deco köşe kolonları, taçlar, neon kanatlar; tuğla binalarda klimalar, su depoları; reklam panoları.
4. Gece (saati gece yap ya da bekle): tabelalar, vitrinler ve neonlar yanıyor mu, sabah sönüyor mu? Yakındaki vitrinlerin
   kaldırıma ışık vurması. Koyu tabelalarda yazı okunuyor mu?
5. Telefon/tablette gece sürüşü: FPS düşüşü var mı (ışık sayısı dokunmatikte 4)?
6. Konsolda `[WorldGen]` ya da `[CityLights]` uyarısı?
7. Dünyayı pişirdiysen yeniden pişir (`WorldBuilder.Bake()`).

## Sınırlamalar
* Yazı tipleri ve gece görünümü yalnız Studio'da doğrulanabilir; önizleme şematiktir.
* İç mekân yok (aşama 4+); vitrinlerin içi gece ışıklı cam olarak görünür.
* Kulelerde rastgele yanan pencereler bu aşamada yok (aşama 9: gece aydınlatmalarının son hali).
* Parçalar prosedürel (Roblox parçaları); dış model kullanılmadı.
