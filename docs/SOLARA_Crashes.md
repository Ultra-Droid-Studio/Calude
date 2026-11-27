# SOLARA — Çarpışma: yaya ragdoll'u, NPC aracın toparlanıp yoluna devam etmesi

Durum: **kod hazır; çevrimdışı testler PASS; lint önceki durumda. Oyunda test EDİLMEDİ** (fizik — savrulma, eklem
açıları, kalkış görünümü — ancak oyunda görülür).

## Eskiden
Oyuncunun aracı çarpınca NPC simülasyondan çıkarılıp tek parça fizik nesnesine dönüyordu: yaya kaskatı devriliyor,
araç olduğu yerde kalıyor, 8–10 sn sonra (oyuncu uzaklaşınca) ikisi de kayboluyordu.

## Şimdi
**Yaya (gerçekçi Rocketbox modeli):**
1. Çarpınca **ragdoll**: her uzva görünmez bir fizik gövdesi (kalça, göğüs, baş, üst kol, ön kol, uyluk, baldır = 11),
   eklemler açı sınırlı bilyeli eklem (diz/dirsek 80–85°, omuz 110°, bel 35°, boyun 45°). Uzuvlar birbirine
   çarpmaz (titreme yok), dünyaya, araçlara çarpar. Gövde aracın hızının %65'i + yukarı itişle savrulur, döner.
   Modelin kemikleri her karede bu gövdeleri izler (deri mesh doğal bükülür); çarpma anında poz sıçramaz.
2. Durulunca (en az 1.6 sn, 0.5 sn hareketsiz; en fazla 6 sn) **ayağa kalkar**: yattığı pozdan duruş pozuna 0.9 sn'lik
   yumuşak geçiş, düştüğü yerde.
3. En yakın kaldırıma (karşıya geçiş değil, ≤ 18 stud) **yeniden katılır**: aynı görünüm ve yürüme hızıyla, eski
   yönüne en yakın taraftan yürümeye devam eder; durduğu yerden kaldırımdaki yürüme çizgisine 0.9 sn'de süzülür.
4. Suya / boşluğa düşerse ya da yakında kaldırım yoksa eskisi gibi kalır, oyuncu uzaklaşınca kaldırılır.
R15 yedek yayalarda (model yüklenmezse) aynı akış: eklemler bilyeli ekleme döner, kalkışta anında geri bağlanır.

**NPC araç:**
1. Çarpınca fiziğe geçer (itilir, kayar, döner).
2. Durulunca (en az 1.5 sn, 0.8 sn hareketsiz, oyuncunun aracı 14 stud'dan uzakta) **devrilmemişse** aynı yöne giden
   en yakın şeride (≤ 14 stud; durma çizgisini geçmişse birkaç stud geri alınarak) **geri katılır**, önünde ve
   arkasında yer varsa. Şerit doluysa saniyede bir yeniden dener. Model durduğu yerden şeritteki yerine 1.2 sn'de
   yumuşakça oturur, sonra trafikle birlikte kalkar.
3. Devrildiyse ya da yol bulamazsa kaza aracı olarak kalır, oyuncu uzaklaşınca kaldırılır.

**Yoldaki kaza:** yerde yatan yaya ve kaza aracı artık NPC trafiği için engel: arkadan gelenler durur ya da şerit
değiştirir (eskiden içinden geçiyorlardı), yayalar etrafından dolaşır.

## Kod
| Dosya | Değişiklik |
|---|---|
| `Shared/Ambient/TrafficSim.lua` | `Rejoin(kind, x, z, hx, hz, maxDist)` |
| `Shared/Ambient/PedSim.lua` | `Rejoin(x, z, hx, hz, seed, speed, maxDist)` |
| `Ambient/PedMeshRig.lua` | `Ragdoll`, `StepRagdoll`, `StartGetUp`, `StepGetUp`, `Reset` (uzuv gövdeleri, eklemler, kemik izleme) |
| `Ambient/PedRenderer.lua` | `Knockdown`, `StepDown`, `StartGetUp`, `StepGetUp` (gerçekçi + R15); havuza dönüşte temizlik |
| `Ambient/TrafficRenderer.lua` | `CrashState`, `Recover` |
| `Controllers/AmbientController.lua` | kaza akışı (her kare), geri katılma, dönüş geçişi, kazalar engel olarak |

## Testler (çevrimdışı)
* `tools/test_crash.py` (gerçek harita, gerçek TrafficSim/PedSim) — PASS: itilmiş (3.5 stud yana, 25° dönük)
  araçların 10/12'si kendi yönündeki şeride ≤ 14 stud içinde, duran olarak katıldı (2'sinin şeridi doluydu: oyunda
  saniyede bir yeniden denenir); katılanların hepsi yoluna devam etti, 30 sn'de hiç üst üste binme yok; yoldan uzakta
  / dolu yerde katılma yok; 10/10 yaya kaldırımda (geçitte değil), aynı görünüm ve hızla katıldı, 9/10 yürümeye
  devam etti.
* `tools/test_peds.py` [8]–[10] (gerçek PedMeshRig / PedRenderer, Roblox taklidiyle) — PASS: 11 uzuv gövdesi, 10 eklem,
  55 çarpışmama kuralı; model kökten ayrılıp kalçaya bağlanıyor; çarpma anında poz sıçraması 0; uzuvlar düşüp dönünce
  kemikler birebir izliyor; durulunca 1.6 sn'de "durdu", 0.9 sn'de kalkış, sonunda gövdeler silinmiş, model kökte
  duruş pozunda, kaynaklar geri; havada havuza dönerse temizlik; R15 yedekte eklemler bilyeli ekleme dönüp geri geliyor.
* Fizik motorunun kendisi (savrulma, eklem sınırlarının görünümü, zemine oturma) taklitte yok: oyunda bakılmalı.
