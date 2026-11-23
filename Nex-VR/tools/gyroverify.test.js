// Stage 65 — sensör doğrulama / otomatik mod: Cam nesnesi kaynaktan çıkarılıp sahte ortamda gerçekten çalıştırılır.
const fs = require('fs'), path = require('path'), assert = require('assert'), vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '..', 'app', 'src', 'main', 'assets', 'index.html'), 'utf8');

function block(src, startMarker) {
  const i = src.indexOf(startMarker); assert(i >= 0, startMarker + ' yok');
  let j = src.indexOf('{', i), d = 0, k = j;
  for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (!d) break; } }
  return src.slice(i, k + 1);
}
const camSrc = block(html, 'const Cam={');
const matSrc = block(html, 'window.__nxNativeMatrix=function');
const gravSrc = block(html, 'window.__nxNativeGrav=function');

// Küçük THREE taklidi (yalnız hibrit/ölü bölge yolunun kullandıkları)
class Q { constructor(x = 0, y = 0, z = 0, w = 1) { this.x = x; this.y = y; this.z = z; this.w = w; }
  dot(o) { return this.x * o.x + this.y * o.y + this.z * o.z + this.w * o.w; }
  copy(o) { this.x = o.x; this.y = o.y; this.z = o.z; this.w = o.w; return this; }
  setFromEuler(e) { // 'YXZ'
    const c1 = Math.cos(e.x / 2), c2 = Math.cos(e.y / 2), c3 = Math.cos(e.z / 2), s1 = Math.sin(e.x / 2), s2 = Math.sin(e.y / 2), s3 = Math.sin(e.z / 2);
    this.x = s1 * c2 * c3 + c1 * s2 * s3; this.y = c1 * s2 * c3 - s1 * c2 * s3; this.z = c1 * c2 * s3 - s1 * s2 * c3; this.w = c1 * c2 * c3 + s1 * s2 * s3; return this; }
  slerp(q, t) { let d = this.dot(q), sg = d < 0 ? -1 : 1; // nlerp (küçük açılarda slerp ile aynı)
    this.x += (sg * q.x - this.x) * t; this.y += (sg * q.y - this.y) * t; this.z += (sg * q.z - this.z) * t; this.w += (sg * q.w - this.w) * t;
    const n = Math.hypot(this.x, this.y, this.z, this.w); this.x /= n; this.y /= n; this.z /= n; this.w /= n; return this; } }
class E { constructor(x = 0, y = 0, z = 0, o = 'YXZ') { this.x = x; this.y = y; this.z = z; this.order = o; } set(x, y, z, o) { this.x = x; this.y = y; this.z = z; if (o) this.order = o; return this; } }

function make({ java = true, sensor = 'rv', D = true, nativeOk = true, nativeEvents = 0, webEvents = 0 } = {}) {
  const timers = []; let now = 0; const toasts = []; const calls = { start: 0, stop: 0 };
  const listeners = {};
  const ctx = {
    window: { DeviceOrientationEvent: D ? function () {} : undefined, AndroidBridge: java ? {
      nativeGyroAvailable: () => nativeOk, nativeGyroStart: () => { calls.start++; return true; }, nativeGyroStop: () => { calls.stop++; } } : undefined },
    NX_T: 't', Dev: { java, sensor }, Diag: { toast: (m, c) => toasts.push(m) }, WM: { repaintAll() {} },
    performance: { now: () => now }, THREE: { Quaternion: Q, Euler: E }, clamp: (v, a, b) => Math.min(b, Math.max(a, v)),
    Settings: { v: {} }, XR: {}, Input: {},
    setTimeout: (f, ms) => { timers.push({ f, at: now + ms }); return timers.length; }, clearTimeout: id => { if (id) timers[id - 1] = null; },
    addEventListener: (n, f) => { listeners[n] = f; }, removeEventListener: (n, f) => { if (listeners[n] === f) delete listeners[n]; },
  };
  if (ctx.window.AndroidBridge) ctx.AndroidBridge = ctx.window.AndroidBridge; // tarayıcıda window === global
  else delete ctx.window.AndroidBridge;
  vm.createContext(ctx);
  vm.runInContext(camSrc.replace('const Cam=', 'var Cam=') + ';\n' + matSrc.replace('window.__nxNativeMatrix=', 'var nm=window.__nxNativeMatrix=') + ';\n' + gravSrc.replace('window.__nxNativeGrav=', 'var ng=window.__nxNativeGrav='), ctx);
  const Cam = ctx.Cam;
  Cam.nm = { set() {} }; Cam.nq = { setFromRotationMatrix() {} };
  Cam.cam = { quaternion: new Q(), position: { z: 0 }, rotation: { set() {} } }; Cam._q2 = new Q(); Cam._e2 = new E();
  const advance = ms => { now += ms; timers.forEach((t, i) => { if (t && t.at <= now) { timers[i] = null; t.f(); } }); };
  const feedNative = n => { for (let i = 0; i < n; i++) { now += 16; ctx.nm(1, 0, 0, 0, 1, 0, 0, 0, 1); } };
  const feedGrav = (n, x, y, z) => { for (let i = 0; i < n; i++) { now += 16; ctx.ng(x, y, z); } };
  // g verilirse her karede yerçekimi örneği de gelir (gerçek sensör gibi); verilmezse yalnız kare ilerler
  const run = (n, g, dt = 0.016) => { for (let i = 0; i < n; i++) { now += 16; if (g) ctx.ng(g[0], g[1], g[2]); Cam.update(dt); } };
  const feedWeb = n => { for (let i = 0; i < n; i++) listeners.deviceorientation && listeners.deviceorientation({ alpha: 1, beta: 2, gamma: 3 }); };
  return { Cam, ctx, toasts, calls, listeners, advance, feedNative, feedGrav, feedWeb, run };
}

(async () => {
  // 1) Java "sensör yok" diyor, yerel yol yok → hiç denenmez, dokunmatik kalır
  let t = make({ sensor: 'none', nativeOk: false, D: true });
  await t.Cam.enableGyro();
  assert.strictEqual(t.Cam.gyro, false); assert(!t.listeners.deviceorientation); assert.strictEqual(t.calls.start, 0);
  assert.strictEqual(t.Cam.statusText(), 'sensör yok');

  // 2) Yerel sensör canlı → yerel seçilir, web dinleyicisi kaldırılır
  t = make({ sensor: 'rv' });
  await t.Cam.enableGyro();
  assert.strictEqual(t.Cam.src, 'verify'); assert(t.listeners.deviceorientation, 'doğrulama sırasında web dinleyicisi açık');
  assert.strictEqual(t.Cam.gyroLive(), false, 'doğrulanırken dokunmatik bakış serbest');
  t.feedNative(50); t.feedWeb(3); t.advance(1800);
  assert.strictEqual(t.Cam.src, 'native'); assert(!t.listeners.deviceorientation, 'web dinleyicisi kaldırılmalı');
  assert(t.Cam.hz > 10, 'Hz ölçülmedi'); assert.strictEqual(t.Cam.gyro, true); assert.strictEqual(t.calls.stop, 0);
  assert(/yerel/.test(t.Cam.statusText()));

  // 3) Yerel veri yok ama WebView olayı geliyor → web seçilir, yerel kapatılır
  t = make({ sensor: 'rv' });
  await t.Cam.enableGyro(); t.feedWeb(40); t.advance(1800);
  assert.strictEqual(t.Cam.src, 'web'); assert.strictEqual(t.calls.stop, 1); assert(t.listeners.deviceorientation);
  assert.strictEqual(t.Cam.gyroLive(), true);

  // 4) Hiçbir yoldan veri yok (sanal/ölü sensör) → kapanır, dokunmatik serbest, dead işareti
  t = make({ sensor: 'rv' });
  await t.Cam.enableGyro(); t.advance(1800);
  assert.strictEqual(t.Cam.gyro, false); assert.strictEqual(t.Cam.dead, true); assert(!t.listeners.deviceorientation);
  assert.strictEqual(t.Cam.gyroLive(), false); assert.strictEqual(t.calls.stop, 1);
  assert(t.toasts.some(m => /veri vermiyor/.test(m)));
  // elle tekrar açılınca dead sıfırlanır
  await t.Cam.enableGyro(); assert.strictEqual(t.Cam.dead, false); assert.strictEqual(t.Cam.gyro, true);

  // 5) Tek web olayı (duran telefon, Chromium yalnızca değişimde olay yollar) yeterli
  t = make({ sensor: 'rv', nativeOk: false });
  await t.Cam.enableGyro(); t.feedWeb(1); t.advance(1800);
  assert.strictEqual(t.Cam.src, 'web'); assert.strictEqual(t.Cam.gyro, true);

  // 6) Doğrulama beklerken kapatılırsa zamanlayıcı etkisiz
  t = make({ sensor: 'rv' });
  await t.Cam.enableGyro(); t.Cam.disableGyro(); t.advance(5000);
  assert.strictEqual(t.Cam.dead, false); assert.strictEqual(t.Cam.gyro, false);

  // 7) 'am' (jiroskopsuz) sınıfı uyarı verir
  t = make({ sensor: 'am' });
  await t.Cam.enableGyro(); t.feedGrav(50, 0, 9.8, 0); t.advance(1800); t.feedGrav(2, 0, 9.8, 0);
  assert(t.toasts.some(m => /Jiroskop yok: hibrit/.test(m)));
  assert(/hibrit/.test(t.Cam.statusText()) && t.Cam.src === 'native' && t.Cam.hOk);
  assert.strictEqual(t.Cam.hybridLive(), true, 'hibrit canlı'); assert.strictEqual(t.Cam.gyroLive(), false, 'tam yönelim yok → yaw dokunmayla');

  // 7b) Hibrit: eğim yerçekiminden, yön dokunmayla; yeniden çizim yok = quaternion sabit
  t = make({ sensor: 'acc' });
  await t.Cam.enableGyro(); t.feedGrav(50, 0, 9.8, 0); t.advance(1800);
  const g30 = [0, Math.sqrt(.75) * 9.8, -0.5 * 9.8]; // ekran yukarı bakıyor: pitch +30°
  t.run(80, g30);
  let q = t.Cam.cam.quaternion;
  assert(Math.abs(q.x - Math.sin(15 * Math.PI / 180)) < 0.01 && Math.abs(q.w - Math.cos(15 * Math.PI / 180)) < 0.01, 'pitch 30° değil: ' + JSON.stringify(q));
  t.Cam.yaw = 1; t.run(80, g30); q = t.Cam.cam.quaternion;
  assert(q.y > 0.2, 'yaw dokunmadan gelmiyor'); // yaw=1 rad → y bileşeni belirgin
  // yatış: telefon saat yönünde 20° yatık → ax negatif; kamera z-dönüşü = atan2(ax, ay) negatif
  t.Cam.yaw = 0; const th = 20 * Math.PI / 180; t.run(80, [-Math.sin(th) * 9.8, Math.cos(th) * 9.8, 0]); q = t.Cam.cam.quaternion;
  assert(q.z < -0.1, 'yatış işareti yanlış: ' + q.z);

  // 7c) Ölü bölge: 0,02° değişim → quaternion hiç oynamaz; 1° → oynar; durunca yine sabit
  t = make({ sensor: 'acc' });
  await t.Cam.enableGyro(); t.feedGrav(50, 0, 9.8, 0); t.advance(1800);
  t.run(60, [0, 9.8, 0]);
  const snap = () => { const c = t.Cam.cam.quaternion; return [c.x, c.y, c.z, c.w].join(); };
  const rad = d => d * Math.PI / 180, tilt = d => [0, Math.cos(rad(d)) * 9.8, -Math.sin(rad(d)) * 9.8];
  const base = snap();
  t.run(30, tilt(0.02)); assert.strictEqual(snap(), base, '0,02° değişim ölü bölgeye takılmalı');
  t.run(80, tilt(1)); const moved = snap(); assert.notStrictEqual(moved, base, '1° değişim görünmeli');
  t.run(30, tilt(1)); assert.strictEqual(snap(), moved, 'oturduktan sonra sabit kalmalı (render yok)');
  assert(t.Cam.dzMove === false, 'durunca dzMove kapanmalı');

  // 8) Kaynak kontrolleri
  assert(/else if\(!Cam\.gyroLive\(\)\)\{\s*Cam\.yaw-=dx\*k;/.test(html), 'tam yönelimde dokunmatik bakış kapanmıyor');
  assert(/if\(!Cam\.gyro&&!Cam\.dead\)await Cam\.enableGyro\(\)/.test(html), 'Stereo ölü sensörü yeniden deniyor');
  assert(/Cam\.nCnt\+\+/.test(html), 'native sayaç yok');
  assert(/if\(Cam\.hybridLive\(\)\)Cam\.yaw-=dx\*k/.test(html), 'hibritte dokunmatik yaw yok');
  const main = fs.readFileSync(path.join(__dirname, '..', 'app', 'src', 'main', 'java', 'com', 'nexus', 'vr', 'MainActivity.java'), 'utf8');
  assert(/__nxNativeGrav/.test(main) && !/TYPE_MAGNETIC_FIELD/.test(main) && !/getRotationMatrix\(rotation, null/.test(main), 'Java hibrit yol/pusula kaldırma');
  console.log('gyroverify.test.js: tamam');
})().catch(e => { console.error(e); process.exit(1); });
