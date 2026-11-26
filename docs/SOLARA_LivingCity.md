# SOLARA — Yaşayan Şehir (gelişmiş NPC ve trafik)

Durum: **kodlandı ve çevrimdışı test edildi (gerçek modüller + gerçek harita, `tools/test_ambient.py` → PASS).
Roblox Studio'da test EDİLMEDİ → Studio testinden önce tamamlanmış sayılmaz.**
Derleme: `place/SOLARA_LivingCity.rbxlx` (temel yer dosyası + `src/` içindeki her şey: Aşama 1–6, düzeltmeler,
araba paketi bağlantısı ve bu çalışma). Araba modelleri hâlâ Studio'da içe aktarılmayı bekliyor (`docs/SOLARA_CarPack.md`).

Mevcut sistem silinmedi, baştan yazılmadı: Aşama 6'nın trafik ve yaya modülleri geliştirildi; harita, yollar ve
binalar değişmedi (kapılar istemcide, harita verisinden hesaplanan yerel modeller).

## 1. Ölçülen sonuç (aynı test düzeneği, merkez, öğle)

| Ölçü | Önce (Aşama 6, 24 araç) | Önce, 64 araç | Şimdi (64 araç, 80 yaya) |
|---|---|---|---|
| Ortalama hız (duruşlar dahil) | 11.2–12.1 | 10.7–10.9 | 12.3–13.1 |
| Caddede hareket halindeyken ort. hız | 17.7 | 16.6 | 20.3–20.6 |
| Öndeki kalkınca kalkış gecikmesi | 0.68 sn | 0.71 sn | 0.32–0.34 sn |
| Yeşil yanınca ilk aracın kalkışı | — | — | 0.10 sn (1 adım) |
| Araç yoğunluğu (100 stud şerit başına) | ~0.10 | 0.22–0.26 | cadde 0.36, ara sokak 0.19 |
| Ekranda görünürken kaybolan araç (5 dk) | 25–28 | 61–63 | 0 |
| Araç çakışması / yayaya çarpma / kırmızıda geçiş | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Kavşağı 10 sn'den uzun tıkayan araç | 0–2 | 0–3 | 0 |
| Yaya sayısı | 32 | 32 | 80 |
| Yayanın geçitte bekleme payı | ~%30 | — | %23 |
| Yayanın bir adımda en büyük dönüşü | 180° (köşede ani) | — | 34° (≈340°/sn) |
| Binaya giren / çıkan yaya (10 dk) | — | — | 143 / 446 |
| Duran araç payı | %31–33 | %34–35 | %37–39 |

Duran araç payı iyileşmedi: duruşların yarısından fazlası kırmızı ışık (haritada 211 ışıklı kavşak, 116 studluk
bloklar). Yaya sayısı 32'den 80'e çıktığı için araçlar yayalara daha sık yol veriyor (duruşların %9'u). Analizde
koyduğum "duruş ≤ %25" ve "caddede hareketliyken ≥ 35" hedefleri **tutmadı**: 116 studluk blokta 13 stud/sn² ivmeyle
araç 70 hıza zaten çıkamıyor (0→70 için ~190 stud gerekir). Hızı artırmak için ivmeyi gerçek dışı yükseltmedim.

## 2. Trafik
### Yoğunluk (2.1)
* **Şehir yoğunluğu ayarı** (Ayarlar → Grafik → Şehir yoğunluğu: Düşük / Normal / Yüksek, varsayılan Normal).
  Aynı anda en fazla araç:

  | Cihaz | Düşük | Normal | Yüksek |
  |---|---|---|---|
  | Masaüstü | 36 | 64 | 90 |
  | Tablet (dokunmatik, ekranın kısa kenarı ≥ 700) | 22 | 38 | 50 |
  | Telefon | 14 | 26 | 34 |

* **Yol sınıfı ağırlığı**: doğma olasılığı = şerit uzunluğu × sınıf (cadde 1, otoyol 0.8, ara sokak 0.2, kırsal 0.3);
  kavşakta üst sınıf yola dönmek daha olası → caddeler yoğun (0.36), ara sokaklar seyrek (0.19).
* Bölge ve saat yoğunluğu (Aşama 6) korunur; şehrin her yerine dağılım.
* **Uyarlanır kalite**: kare hızı 3 sn boyunca 35 FPS'in altındaysa bütçe %10 azalır (en az %50), 8 sn boyunca
  55'in üstündeyse geri artar. Fazla araç sadece görünmeyenlerden kaldırılır.
* Doğma: görünmeyen yerde 90 studdan, görünen yerde 300 studdan uzakta; ilk girişte hızlı doldurma.
* **Kaldırma: görünen araç kaldırılmaz** (ekranda ve bir binanın arkasında değilse); 680 studu geçerse kaldırılır.

### Hız ve dur-kalk (2.2, 2.3)
| Ayar | Önce | Şimdi |
|---|---|---|
| İvme / konfor freni / acil fren | 9 / 11 / 32 | 13 / 14 / 36 |
| Takip süresi / duruş mesafesi | 1.3 sn / 6 | 1.0 sn / 4.5 |
| Viraj güvenli hızı (yanal ivme) | 9 | 12 |
| Dur levhası bekleme | 0.8 sn | 0.6 sn |
| Engel arkasında şerit değiştirme | 2.5 sn | 1.5 sn |

* **Öngörü**: öndeki kalkınca boşluğun açılacağı hesaba katılır → kuyruk 0.33 sn aralıkla çözülür.
* **Sarsıntısız kalkış**: ivme artışı sınırlı (45 stud/sn³), fren her zaman anında (güvenlik etkilenmez).
* **Titreme yok**: duran araç küçük bir boşluk için santim santim sürünmez (eşik). Sebepsiz kalk-dur ~%0.5
  (yayaya yol verme ve kuyrukta çizgiye ilerleme hariç).
* **Viraja yaklaşma**: dönüşün güvenli hızına şerit sonunda inecek kadar sabit fren (eskiden bağlantıya girince sert
  fren yapılıyordu; arkadaki yetişemiyordu — testte bulundu).

### Kavşaklar (2.4)
* **Işık planı**: cadde/otoyol fazı 20 sn, kesişen ara sokak 11 sn (eşit sınıfta 14/14); 124 kavşakta ana yol
  önceliği. **Yeşil dalga**: ana yol boyunca ofset (55 stud/sn). Hepsi haritadan hesaplanır: bütün oyuncular aynı
  ışığı görür. İki fazın aynı anda yeşil/sarı olmadığı test edildi.
* Sola dönen araç yeşil boyunca karşı akış yüzünden dönemediyse **sarıda döner** (duramayacak karşı araç yoksa).
* **Kavşağı tıkama yok**: çıkışta aracın tamamen sığacağı yer yoksa ya da çıkış kapalıysa (yolda duran oyuncu/araç:
  "Kapalı") kavşağa girilmez; çıkıştaki yaya geçidinde yaya varsa çizgide beklenir ("Geçit").
* **Kapalı yol → başka yön**: 4 sn'den uzun "dolu/kapalı/engel" bekleyen araç kavşakta başka çıkışı seçer.
* Engel yüzünden giremeyen araç 2 sn sonra geçiş iznini bırakır (diğer yönler boşuna beklemez).
* Kavşaktan çıkıp arkası kavşakta kalan aracın gövdesi bir yönün yolunu kesiyorsa o yön girmez, içerideki araç durur.
* Otoyol/rampa düğümlerinde (platformsuz) çakışma hesabına şeritlerin son/ilk 15 studu da katıldı (rampa döngüsünün
  otoyol şeridiyle çakıştığı yer testte bulundu).
* Kilit bekçisi: 75 sn hiç kıpırdamayan, görünmeyen ve uzaktaki araç kaldırılır (son güvenlik ağı). Testte bekçinin
  devreye girmesi hata sayılır (gerçek kilit 0).

### Çeşitlilik (2.5)
* Bölge türüne göre araç karışımı: merkezde sedan/kompakt/taksi, sanayide van/pikap/servis aracı, kırsalda pikap/SUV,
  sahil ve tatil bölgesinde spor araç.
* Taksi oranı bölgeye göre (merkez ×2.2, havalimanı ×3, kırsal ×0.1).
* Sedan, hatchback (kompakt), SUV, spor, taksi: Quaternius CC0 modelleri. **Ticari (van/pikap/servis) araçlar kutu
  görünümde kalır** (pakette karşılığı yok; ikinci bir CC0 paket gönderirsen eklerim). Renkler aracın kendi
  paletinden.

## 3. Yayalar (3.1, 3.2)
* **Bütçe**: masaüstü 45 / 80 / 110, tablet 25 / 45 / 60, telefon 18 / 30 / 40 (Düşük / Normal / Yüksek).
* **Yumuşak hareket**: yön dönüş hızıyla değişir (≈340°/sn; köşede ani dönme yok), hız ivmeli (kalkış 6, duruş 8
  stud/sn²), geçit başında ve hedefte yavaşlayarak durur.
* **Amaç**: hedef en az 70 stud uzakta (olduğu yerde dönüp durma yok), gereksiz karşıya geçmeye rota cezası (30), saate
  göre bina kapısına gitme (eve dönüş, işe/dükkâna giriş).
* **Yaya ışığı**: ana yol kısa yan yeşil yüzünden geniş caddeyi neredeyse hiç geçemiyordu → yaya, karşı trafiğe yeşil
  yanana kadar kalan süre geçiş süresinin 0.7 katından uzunsa başlar; geç kalanı araçlar bekler. Kırmızıda başlama 0.
* Araçla karşılıklı bekleme (yaya aracın köşesini, araç yayayı bekliyor) çözüldü: yaya duran aracın etrafından dolaşır,
  araç gövdesinin yanındaki yayayı "önümde" saymaz.
* **Görünen yaya kaldırılmaz**; uzak yayalarda komşu/engel taraması yapılmaz (maliyet LOD).

## 4. Binaya giriş/çıkış (4)
* **Kayıt sistemi** (`Shared/Ambient/Entrances.lua`): 13 bina stili için kapı yeri BuildingBuilder'ın cephe
  formüllerinden hesaplanır; binanın kendi kapı parçası olan stillerde (müstakil ev, sıra ev, dükkân, tuğla apartman)
  tam o parçanın önü. **1278 kapı** (6 kapı kaldırıma ulaşamadığı için elendi). Her kapı:
  `BuildingEntrance`/`BuildingExit` = aynı kapı, `NPCDestination` = kapı düğümü, `PedestrianWaypoint` = kaldırımdaki
  bağlantı noktası.
* Kapı ile kaldırım arasında cepheye dik düz yürüme yolu; **yoldan ve başka arsalardan geçmediği test edildi**; kapı
  düğümü çıkmaz uçtur (kısa yol olarak kullanılamaz).
* **Davranış** (`PedSim`): Kapı (yaklaş, kapıya dön, 0.5–1.1 sn bekle, kapı açılır) → Gir (1.5 sn'de eşikten geçer,
  içeride kararır, kaldırılır). Çıkış: kapı açılır, içeriden belirir, dışarı yürür, yoluna devam eder. Aynı kapıyı
  aynı anda biri kullanıyorsa sıradaki bekler. Test: binaya giren her yaya kapı boşluğunun içinde kayboldu (duvarda 0).
* Saate göre: gece eve, sabah işe, öğlen dükkâna, akşam eve dönüş; kapıdan çıkarak doğma oranı da saate göre.
* **Kapı görseli** (`Ambient/DoorRenderer.lua`): sadece oyuncunun 130 stud yakınında, havuzlu; kasa + kanat + açıkken
  karanlık kapı boşluğu; kanat dışarı açılır (binanın içine girmez). İç mekân yok (istenmemişti).

## 5. NPC modeli ve animasyon (3.3, 5)
* **Model** (`Ambient/PedRenderer.lua`): kodla kurulan **R15 iskeleti** (16 parça, standart R15 eklem adları), 3 boy,
  gövde genişliği, 6 ten rengi; kıyafet: tişört, uzun kol, ceket, takım elbise (kravat), elbise/etek, şort; saç: kısa,
  uzun, topuz, kel; kep, bere; sırt çantası, omuz çantası, gözlük. Yüz Roblox'un yerleşik dokusu. **Dış model yok →
  lisans sorunu yok.** Humanoid/Animator yok (80 yayada pahalı).
* **Animasyon** (`Shared/Ambient/PedAnim.lua`): **hazır Roblox animasyonları KULLANILMADI** (analizde öneri buydu;
  değiştirdim). Neden: Roblox'un varsayılan yürüme animasyonu 16 stud/sn karakter adımına göre çizilmiş; 4–6 stud/sn
  yürüyen yayada ya ayak kayar ya da ağır çekim görünür ve bunu burada test edemem. Yerine ters kinematikle yürüme:
  basan ayak yere sabit (test: sabit hızda kayma 0.000 stud, hızlanma/yavaşlamada en fazla 0.09), salınan ayak yerden
  kalkar, kollar karşı bacakla salınır, kalça doğal iner-kalkar.

  | İstenen | Karşılığı |
  |---|---|
  | Idle | nefes, ağırlık aktarma, ara sıra etrafa bakma |
  | Walk | IK yürüyüş, adım boyu ve sıklığı gerçek hızdan |
  | Turn | dönüşün içine eğilme, baş dönüş yönüne; yerinde dönüşte kısa ayak adımları |
  | Stop / StartWalking | hız rampasıyla adım kısalır/uzar, ayaklar gövdenin altına toplanır |
  | DoorApproach | kapıya dönme, bekleme, sağ kolla kapıyı itme |
  | EnterBuilding / ExitBuilding | kapı boşluğundan yumuşak geçiş + eşikte kararma / belirme |

* Görsel kontrol: `docs/livingcity_ped_preview.png` (`tools/preview_ped.py` — gerçek PedAnim pozları, Roblox'un Motor6D
  formülüyle çizildi: yürüyüş döngüsü yandan; duruş, yürüyüş, kapı, dönüş).
* Animasyon LOD: 45 stud içinde her kare, 90'a kadar iki karede bir, ötesinde duruş pozu.

## 6. Performans (6)
* Havuz: araç, yaya, kapı modelleri yeniden kullanılır.
* Sabit bütçe + cihaz sınıfı + uyarlanır kalite; uzak araç ve yayalar iki karede bir konumlanır.
* Doğma adayları önbellekli (odağa göre, 3 sn), uzak yayada tarama yok, görünürlük ışını 0.5 sn önbellekli.
* Simülasyon maliyeti (çevrimdışı Lua 5.4, Luau değil): trafik 64 araçta ~0.8 ms, yaya 80'de ~1.0 ms, 10 Hz.
* **Cihazda FPS ölçülmedi** (Studio'da senin ölçmen gerekiyor; aşağıda).

## 7. Testler (`python3 tools/test_ambient.py <lupa>` → RESULT: PASS)
[1] şerit grafiği · [2] kaldırım grafiği · [2b] kaldırımsız veride yaya yok · [3] merkez 10 dk + akış ölçüleri +
yaya ve kapı hedefleri · [3b] 5 tohum × 4 dk · [4] park etmiş araçla kapalı şerit · [4b] kavşak çıkışı kapalı ·
[5] yoldan karşıya yürüyen oyuncu · [6] hareketli oyuncu ve iki oyuncu · [7] gece/öğle · [8] yoğunluk ön ayarları ·
[9] ışık planları · [10] kapı kaydı · [11] yürüme animasyonu.
Ek: farklı tohumlarla 18 × 5 dk çakışma/çarpma taraması, 16 × 4 dk kilit taraması, 8 × 4 dk Yüksek yoğunluk (90 araç),
18 × 5 dk hareketli oyuncu, 4 × 10 dk kavşak tıkama taraması — son kodla hepsi temiz.

Bu çalışma sırasında testlerin yakaladığı ve düzeltilen hatalar (hepsi yeni yoğunlukta ortaya çıktı):
1. Viraja yaklaşırken geç ve sert fren → arkadan çarpma. 2. Kavşaktan çıkıp yaya geçidinde duran aracın arkası
kavşakta kalıyordu → çapraz araç çarpıyordu. 3. Dönüşe ayrılan öndeki araç izin alınmadan görülmüyordu.
4. Kavşakta duran aracın hemen arkasında hızlı doğma. 5. Aynı şeritten dönen aracın gövdesi düz gidenin yolunda.
6. Kuyruk rezervasyonu şebekede kilitlenme yaratıyordu. 7. Yaya ile araç birbirini bekliyordu (kilit).
8. Şerit değiştiren araç dururken yana kayıp yayaya değiyordu. 9. Dönüşteki araç yanındaki yayayı yok sayıyordu.
10. Sola dönen araç karşı akışta hiç dönemiyordu. 11. Oyuncu yüzünden giremeyen araç izni bırakmıyordu (kilit).
12. Şerit değiştirme yolu eski şeridi hesaba katmıyordu → park etmiş araca giriyordu. 13. Yolda yürüyen oyuncunun ve
park etmiş aracın dibinde doğma. 14. Otoyol düğümünde rampa döngüsü ile otoyol şeridi çakışması görülmüyordu.
15. Kavşak içinde yaya akışı için 10 sn'den uzun bekleme. 16. Yürümeye başlarken ilk adımda ayak kayması.

## 8. Studio'da senin test etmen gerekenler
1. Ayarlar → Grafik → Şehir yoğunluğu: Düşük/Normal/Yüksek değişince araç ve yaya sayısı değişiyor mu?
2. F7 hata ayıklama paneli: cihaz sınıfı, yoğunluk, kalite %, FPS, araç/yaya sayısı, bina giren/çıkan.
3. Trafik: kalkışlar hızlı ve sarsıntısız mı, kavşakta yığılma/üst üste binme var mı, caddeler ara sokaklardan yoğun mu?
4. Yolun ortasında dur / arabanı kavşak çıkışına park et: araçlar duruyor, kavşağı tıkamıyor, başka yöne dönüyor mu?
5. Yayalar: yürüyüş doğal mı, ayak kayıyor mu, köşede yumuşak dönüyor mu, duruş/kalkış?
6. Bir evin/dükkânın önünde bekle: yaya kapıya yürüyüp kapıyı itip giriyor mu, kapı açılıp kapanıyor mu, yaya duvarın
   içine girmeden kapı boşluğunda kayboluyor mu; binadan çıkan yaya?
7. Kapı modeli binanın kendi kapısıyla örtüşüyor mu (ev, sıra ev, dükkân, tuğla apartman)? Cam lobili binalarda?
8. Telefon ve tablette FPS (MicroProfiler); düşükse kalite otomatik azalıyor mu?

## 9. Bilinen sınırlamalar
* Studio'da test edilmedi; telefon/tablet FPS'i ölçülmedi.
* Duruş payı ve caddede hız hedefleri tutmadı (bkz. 1).
* Kapı görseli 130 studda belirir (uzaktan kapı yok); iç mekân yok; 44 stilden 13'ünde kapı var (diğer stillerde
  — fabrika, depo, hastane, villa vb. — cephe geometrisini doğrulamadım, kapı eklemedim).
* Ticari araçların 3D modeli yok (kutu).
* NPC'ler Roblox tarzı blok insan (gerçekçi değil); özel çizilmiş animasyon yok (kapı kolu tutma vb.).
* Simülasyon deterministik değil (tablo sırası) → test sayıları çalıştırmadan çalıştırmaya biraz değişir.
* Yolun ortasında uzun süre duran oyuncunun önündeki araçlar onu bekler (bilinçli; ezmezler).

## 10. Değişen / eklenen dosyalar
* `src/ReplicatedStorage/Shared/Ambient/TrafficSim.lua`, `TrafficGraph.lua`, `PedSim.lua`, `PedGraph.lua`
* yeni: `Shared/Ambient/Entrances.lua`, `Shared/Ambient/PedAnim.lua`, `StarterPlayerScripts/Ambient/DoorRenderer.lua`
* `StarterPlayerScripts/Ambient/PedRenderer.lua` (R15 model), `TrafficRenderer.lua` (bölgeye göre taksi)
* `StarterPlayerScripts/Controllers/AmbientController.lua`, `Modules/AmbientConfig.lua`
* `Shared/SettingsSchema.lua` + `FrontEnd/Strings.lua` (Şehir yoğunluğu ayarı, TR/EN), `Shared/CarModelKit.lua`
* `tools/test_ambient.py`, `tools/ambient_data.py` (arsalar), yeni `tools/preview_ped.py`, `docs/livingcity_ped_preview.png`
