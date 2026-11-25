# SOLARA — Hata düzeltme 1: Menü geçişinden sonra kaybolan yazılar

Durum: **düzeltme uygulandı, Roblox Studio'da test edilmedi.**
Derleme: `place/SOLARA_Fix1_MenuFade.rbxlx` (Aşama 1–4 + bu düzeltme)

## Neden
`FrontEnd/Fader.lua`, ekranı gizlerken saydamlık tween'lerini başlatıp aynı süreli `task.delay` ile
"taban" saydamlıkları geri yazıyordu. Roblox bu ikisinin sırasını garanti etmez: tween'in son karesi
geri yazmadan sonra gelirse gizlenen ekrandaki yazılar ≈1 saydamlıkta kalır; ekran tekrar açılınca bu
değer yeni taban olarak alınır → yazılar kalıcı görünmez, sadece odak sisteminin her açılışta yeniden
çizdiği vurgu kutuları/çizgileri görünür.

## Değişiklik
Tek dosya: `StarterPlayer/StarterPlayerScripts/FrontEnd/Fader.lua` — `finish()` taban değerleri geri
yazmadan önce o geçişin tween'lerini `Cancel()` ile durdurur. Başka davranış, tasarım veya süre değişmedi.

## Etkilenen (düzelen) yerler
Fader kullanan her şey: Ana menü, Garaj, Ayarlar, Harita ekranları, alt bilgi (tuş ipuçları), menü arka
planı, yedek arka plan sahnesi, bildirim kutusu.

## Korunanlar
Ekranlar yeniden oluşturulmuyor/silinmiyor; event bağlantıları değişmedi; UI tasarımı, animasyon süreleri
ve odak sistemi aynı.

## Studio test senaryoları
1. Ana menü → GARAJ → Geri → AYARLAR → Geri; 20 kez tekrarla. Logo, buton yazıları, alt yazılar, durum
   satırı ve oyuncu kartı her seferinde tam görünmeli.
2. Aynı akışı hızlı yap (geçiş bitmeden Geri'ye bas).
3. Ayarlar'da sekmeler arasında gez, değer değiştir, Geri → ana menü düzgün.
4. Oyun içi menü (P / ☰): aç → Garaj/Ayarlar/Harita → Geri → kapat; tekrar aç. Arka plan ve tuş ipuçları
   kaybolmamalı.
5. Ayarlar → Grafik → "Hareketi azalt" AÇIK iken 1. adımı tekrarla.
6. Tablet ve telefon (Device Emulator ve gerçek cihaz): 1. ve 4. adımlar.
7. Bozulma yine görülürse komut çubuğunda (Client görünümü):
   `local c = game.Players.LocalPlayer.PlayerGui.SolaraFrontEnd.Safe.Canvas.MainScreen.Column print(c.Logo.Wordmark.TextTransparency, c.Buttons.Button_01.Content.Label.TextTransparency)`
   çıktısını ve ekran görüntüsünü gönder.

## Bilinen sorunlar
- Geçiş başında odak vurgusu bir an eski butonda görünebilir (geçiş bitince düzeliyor; kalıcı değil).
- Bu düzeltme koddan çıkarılan nedene dayanır; Studio'da doğrulanmadı.
