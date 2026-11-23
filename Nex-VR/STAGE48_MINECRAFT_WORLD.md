# Stage 48 — Minecraft dünyası (3D, dosyasız)

Duvar kağıdı galerisine, "Roblox evi"nin yanına ikinci bir 3D kare eklendi: **"Minecraft (3D)"**. Roblox evinden farklı olarak hiçbir `.glb`/model dosyası kullanmıyor — tüm dünya `index.html` içindeki `MCTex`/`MCWorld` ile tamamen koddan (prosedürel) üretiliyor, Sinema'nın yeni 2 numaralı odası olarak.

## Ne var
* **Zemin**: oyuncunun etrafında 16×16 gerçek çim bloğu (tek `InstancedMesh`, tek çizim çağrısı) — her blokta üstte çim, yanda çim+toprak geçişi, altta toprak; 48×16'lık piksel doku atlasından (`NearestFilter`, mip yok) UV'si elle eşlenmiş gerçek Minecraft tarzı blok dokusu. Bloklu alanın ötesinde ufka kadar devam eden düz, tekrarlanan çim dokulu bir zemin.
* **9 ağaç**: gövdeler ve yapraklar da birer `InstancedMesh` (toplam 9 gövde + 207 yaprak bloğu, 2 çizim çağrısı); gövdede kabuk + kesit halkası dokusu, yapraklarda ayrı piksel doku.
* **Gökyüzü/atmosfer**: mavi gökyüzü küresi, güneş, kutu-bulut kümeleri, güneş ışığı + ortam ışığı.
* **Canlılar**: 3 köylü (cübbe + burun + alfa dokulu göz yüzü), 3 domuz (gövde + 4 bacak + burun + yüz), 2 zombi (yeşil ten, yırtık giysi, öne uzanmış kollar, çukur gözlü yüz) — hepsi blok gövdeli, kendi piksel dokularıyla; köylüler ve zombiler oyuncuya dönük (`lookAt`), domuzlar rastgele yönlere.
* **Durağan diorama**: diğer Sinema odaları gibi oyuncu merkezde sabit durur, yalnızca etrafına bakar — gezinme yok (kullanıcının istediği gibi).

## Teknik
* `Cinema.ROOMS` dizisine 2 numaralı oda eklendi (Roblox evinden sonra, panorama odalarından önce); `nexus.cinRoom` aralığı 0–7'ye genişletildi.
* `Cinema.loadMinecraft()` / `this.mg`: Roblox'un `loadRoblox()`/`this.rg`'siyle aynı desende, ama dosya indirmediği için **senkron** (anında) kuruluyor.
* `Cinema.applyRoom()` oda 1 ve oda 2'yi aynı "yüklenene kadar salon görünür" mantığıyla kapsayacak şekilde genelleştirildi.
* Duvar kağıdı galerisindeki özel 3D kareler artık tek bir `SP3D` listesinden üretiliyor (Roblox evi + Minecraft), kod tekrarı yok.
* Sınama: `node tools/mcworld-smoke.test.js` (yeni — sahte THREE/canvas ile `MCWorld.build()`'in hatasız çalıştığını ve blok/ağaç/yaprak sayılarını doğrular) ve `node tools/wallart.test.js`, `node tools/glbroom.test.js` (regresyon yok).
