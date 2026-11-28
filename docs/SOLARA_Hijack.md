# SOLARA — Trafikteki araçları çalma (F)

Durum: **kod hazır; çevrimdışı testler PASS; lint önceki durumda. Oyunda test EDİLMEDİ.**

## Oyuncu ne görür
* Yakındaki (70 stud) NPC araçlarda **sürücü koltuğunda bir yaya oturur** (yayalarla aynı gerçekçi modeller; eller
  direksiyona uzanmış; alçak spor arabalarda bacaklar öne uzanık, sırt hafif yaslanmış). Uzaktaki araçlarda sürücü
  yok (performans); en fazla 12 sürücü aynı anda.
* Araç durmuş ya da yavaşken (< 14 stud/sn) sürücü kapısının yanına gelince **"Çal" [F]** istemi (kolda Y, mobilde
  dokun; kısa basılı tutma 0.2 sn).
* F →
  1. Araç trafikten çıkar ve olduğu yerde durur (fren lambası yanar).
  2. Karakterin sürücü kapısına yürür, araca döner, sağ kolunu kapıya uzatır.
  3. Sürücüyü dışarı çekip iter: sürücü **ragdoll** olup yere düşer, sonra kalkar ve kaldırımdan yürüyüp gider
     (çarpışmadaki yaya akışının aynısı).
  4. Sunucu aynı aracı (aynı model, aynı renk, aynı yerde, yere oturtulmuş) **gerçek, sürülebilir araç** yapar ve seni
     sürücü koltuğuna oturtur; NPC görseli o anda kalkar. Diğer oyuncular da bu aracı görür.
* Olmazsa (uzak, geçersiz, çok sık): kısa bildirim; NPC araç orada park etmiş gibi kalır, uzaklaşınca kalkar.
* **Kapı açılma animasyonu yok:** araba modellerinde kapılar gövdeyle tek parça (ayrı kapı parçası yok). Kapısı açılan
  araçlar için kapıları ayrı parça olan modeller gerekir.

## Sunucu kuralları (`VehicleService:Hijack`)
* İstek: `VehicleRemotes.RequestHijack(tanım, model adı | nil, boya Color3 | nil, CFrame)`, sonuç `HijackResult`.
* 4 sn'de bir istek; oyuncu yaşıyor, araçta değil; aracın 16 stud yakınında (dikeyde 10); tanım trafikte olan bir
  otomobil; model adı o tanımın modellerinden ya da trafik varyantı (polis) olmalı.
* Oyuncu başına bir çalıntı araç: yenisi çalınınca öncekinin boşsa kaldırılır. Çalıntı aracın park yeri yok; boş
  bırakılıp 3 dk geçerse ve oyunculardan 200 stud uzaksa kaldırılır.

## Kod
| Dosya | Değişiklik |
|---|---|
| `Shared/RemoteRegistry.lua` | `RequestHijack`, `HijackResult` |
| `Services/VehicleService.lua` | `Hijack` (doğrulama, doğurma, oturtma), çalıntı araç temizliği |
| `Vehicles/VehicleFactory.lua` | seçenekler: `BodyModel` (belirli model), `OwnPaint` (modelin kendi rengi) |
| `Ambient/TrafficRenderer.lua` | sürücü koltuğu + kapı noktası + "Çal" istemi, boya bilgisi, `HijackInfo`, `Ghost` |
| `Ambient/PedRenderer.lua` | `SitIn` / `LeaveSeat` (oturma pozları: normal ve alçak koltuk) |
| `Controllers/AmbientController.lua` | sürücüleri yakın araçlara oturtma, istem açma, çalma sahnesi |

## Testler
* `tools/test_hijack.py` (gerçek TrafficRenderer / PedRenderer / PedMeshRig, Roblox taklidiyle) — PASS: 12 araba +
  polis + kutu yedek araçta sürücü koltuğu solda, gövde içinde, oturan yetişkine yetecek alçaklıkta; kapı noktası
  kapının dışında; "Çal" [F]; oturan sürücünün başı tavanın altında, gövde arabanın içinde, kalça koltukta, dizler
  ve eller önde, araç köküne kaynaklı; LeaveSeat ayırıyor; HijackInfo tanım/model/boya veriyor.
  Görsel: `docs/hijack_preview.png` (camlar çizilmeden, sürücüler görünsün diye).
* Diğer testler (arabalar, trafik ışıkları, yayalar, çarpışma, sokak lambaları) yeniden PASS.
* Sunucu doğrulaması ve oyuncunun kapıya yürüyüp oturması oyunda denenmeli.
