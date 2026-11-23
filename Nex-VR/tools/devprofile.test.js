// Stage 63 — cihaz sınıfı/seviyesi: Java kuralı (DeviceProfile.tierOf) ile JS yedek kuralının tutarlılığı + kaynak kontrolleri.
const fs = require('fs'), path = require('path'), assert = require('assert');
const root = path.join(__dirname, '..', 'app', 'src', 'main');
const html = fs.readFileSync(path.join(root, 'assets', 'index.html'), 'utf8');
const dp = fs.readFileSync(path.join(root, 'java/com/nexus/vr/DeviceProfile.java'), 'utf8');
const main = fs.readFileSync(path.join(root, 'java/com/nexus/vr/MainActivity.java'), 'utf8');
const mirror = fs.readFileSync(path.join(root, 'java/com/nexus/vr/AppMirror.java'), 'utf8');

// Java kuralının birebir JS karşılığı
const tierOf = (lowRam, ram, cores, arm64, sdk) => {
  if (lowRam || (ram > 0 && ram <= 3.2) || !arm64 || cores <= 4) return 0;
  if (ram >= 5.0 && cores >= 8 && sdk >= 29) return 2;
  return 1;
};
// Kaynakta aynı eşikler var mı?
assert(/ramGiB > 0 && ramGiB <= 3\.2/.test(dp) && /ramGiB >= 5\.0 && cores >= 8 && sdk >= 29/.test(dp), 'Java eşikleri değişmiş');

// Örnek cihazlar
assert.strictEqual(tierOf(false, 3.6, 8, true, 30), 1, 'Tab S6 Lite (4 GB) orta kalmalı');
assert.strictEqual(tierOf(false, 2.7, 8, true, 30), 0, '3 GB cihaz düşük');
assert.strictEqual(tierOf(true, 1.8, 8, true, 30), 0, 'isLowRamDevice düşük');
assert.strictEqual(tierOf(false, 3.8, 4, true, 30), 0, '4 çekirdek düşük');
assert.strictEqual(tierOf(false, 3.8, 8, false, 30), 0, '32-bit düşük');
assert.strictEqual(tierOf(false, 7.4, 8, true, 33), 2, '8 GB flagship yüksek');
assert.strictEqual(tierOf(false, 5.4, 8, true, 29), 2, '6 GB Android 10 yüksek');
assert.strictEqual(tierOf(false, 5.4, 8, true, 28), 1, 'Android 9 yüksek sayılmaz');
assert.strictEqual(tierOf(false, 0, 8, true, 33), 1, 'RAM bilinmiyorsa orta');

// JS tarafı
assert(/const Dev=\(\(\)=>\{/.test(html), 'Dev yok');
assert(/AndroidBridge\.deviceProfile\(NX_T\)/.test(html), 'köprü çağrısı yok');
assert(/quality:Dev\.tier>=2\?1:0/.test(html), 'varsayılan kalite seviyeye bağlı değil');
assert(/mobLite=\/Android\|iPad\|Tablet\|Mobile\/i\.test\(navigator\.userAgent\)&&d\.tier<2/.test(html), 'Dev.mobLite seviyeye bağlı değil');
assert(/get lite\(\)\{const g=Settings\.v\.ghand\|0;return g===1\?true:g===2\?false:!!Dev\.mobLite\}/.test(html), 'Hand.lite ayara bağlı değil');
assert(/phone\(\)\{return Dev\.phone&&Dev\.android\}/.test(html), 'Renderer.phone hâlâ lite bağımlı');
assert(/window\.__nxTrim=function/.test(html), '__nxTrim yok');
// Dev, kullanıldığı her yerden önce tanımlanmalı
const iDev = html.indexOf('const Dev=');
assert(iDev > 0 && iDev < html.indexOf('const DEF=') && iDev < html.indexOf('const Renderer='), 'Dev geç tanımlı');

// Java tarafı
assert(/public String deviceProfile\(String t\)/.test(main) && /tokenOk\(t\)/.test(main.slice(main.indexOf('deviceProfile'), main.indexOf('deviceProfile') + 200)), 'köprü jetonsuz');
assert(/public void onTrimMemory\(int level\)/.test(main), 'onTrimMemory yok');
assert(/maxAppWindows\(\)/.test(main) && /userMaxWin/.test(main) && !/dev\.tier == 0\) return dev\.phone \? 1 : 2/.test(main), 'pencere sınırı yalnızca kullanıcı ayarına bağlı olmalı');
assert(/applyProfile\(dp\)/.test(mirror) && /maxW > 0 && rw2 > maxW/.test(mirror), 'AppMirror profili yok');
// Stage 59 telefon-orta değerleri korunmuş mu?
assert(/maxW = PH_MAX_W; minGap = PH_MIN_GAP_MS; maxGap = PH_MAX_GAP_MS/.test(mirror), 'Stage 59 değerleri bozulmuş');
console.log('devprofile.test.js: OK');

// Stage 64 — Ayarlar → Grafik: elle ayarlar + Android pencere pill'i
{
  const html2 = fs.readFileSync(path.join(__dirname, '..', 'app/src/main/assets/index.html'), 'utf8');
  const main2 = fs.readFileSync(path.join(__dirname, '..', 'app/src/main/java/com/nexus/vr/MainActivity.java'), 'utf8');
  for (const k of ['ghand', 'gaa', 'pxb', 'ghz', 'gwin']) assert(new RegExp(k + ':0').test(html2), 'DEF eksik: ' + k);
  for (const l of ['El takibi profili', 'Kenar yumuşatma', 'Piksel bütçesi', 'Yenileme hızı', 'Android pencere sayısı']) assert(html2.includes("step('" + l + "'"), 'ayar satırı yok: ' + l);
  assert(/\(!!u\.chrome\|\|u\.skin==='shz'\)/.test(html2), "Android pencerelerinde pill yok");
  assert(/setRefreshRate\(int hz, String t\)/.test(main2) && /shzSetMaxWin\(int n, String t\)/.test(main2), 'köprü yöntemleri yok');
  console.log('Stage 64 kontrolleri tamam');
}

// Stage 65 — sensör sınıfı (DeviceProfile.sensorOf) kural + kaynak kontrolü
const sensorOf = (rv, acc, mag) => rv ? 'rv' : (acc && mag ? 'am' : (acc ? 'acc' : 'none'));
assert(/static String sensorOf\(boolean rotationVector, boolean accel, boolean magnetic\)/.test(dp), 'sensorOf yok');
assert(/if \(rotationVector\) return "rv";/.test(dp) && /if \(accel && magnetic\) return "am";/.test(dp), 'sensorOf kuralı değişmiş');
assert(/o\.put\("sensor", sensor\)/.test(dp), 'sensör JSON alanı yok');
assert.strictEqual(sensorOf(true, true, true), 'rv'); assert.strictEqual(sensorOf(false, true, true), 'am');
assert.strictEqual(sensorOf(false, true, false), 'acc'); assert.strictEqual(sensorOf(false, false, false), 'none');
assert(/d\.sensor=String\(j\.sensor\|\|''\)/.test(html), 'Dev.sensor köprüden okunmuyor');
assert(/if \(accel\) return "acc";/.test(dp), 'sensorOf acc sınıfı yok');
