# Stage 36 — WebWorker el takibi akıcılık düzeltmesi

## Tespit edilen sorun
`Hand.tick()` hem `requestVideoFrameCallback` hem de ana render döngüsünden çağrılıyordu. Fonksiyonun başındaki `step()` ise el filtreleme, etkileşim/raycast ve çizim güncellemelerini yapıyordu. Böylece aynı ekran döngüsünde bu işlerin iki kez çalışması mümkün oluyordu. Worker çıkarımı ayrı olsa da ana thread'de gereksiz çift iş yükü oluşuyordu.

## Değişiklik
- `tick(t, videoFrame=false)` parametresi eklendi.
- Ana render döngüsü `step()` çağrısını yapmaya devam ediyor.
- `requestVideoFrameCallback` artık `tick(..., true)` çağırıyor ve yalnızca yeni kamera karesinin çıkarım zamanlamasını yönetiyor.
- Worker, GPU/CPU seçimi, model, kamera çözünürlüğü, iki el algılama, OneEuro filtreleri, jestler ve uygulama etkileşimleri değiştirilmedi.

## Beklenen etki
Ana thread'deki el filtreleme/etkileşim/çizim işlerinin çift çalışması engellenir. Bu, özellikle Android tabletlerde gereksiz CPU ve GC baskısını azaltıp arayüzün daha tutarlı kalmasına yardımcı olmalıdır. Gerçek FPS ve sıcaklık kazanımı cihaz üzerinde ölçülmelidir; hiçbir yazılım değişikliği her cihazda kusursuz akıcılık garantisi veremez.

## Test
- `node --check` ile HTML içindeki JavaScript blokları doğrulanmalı.
- `tools/mediapipe-worker.test.js` ve diğer proje testleri çalıştırılmalı.
- Android WebView üzerinde gerçek kamera/Worker testi yapılmalı.
