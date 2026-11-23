/* node tools/gorilla-smoke.test.js -- sahte THREE/DOM ile yaşam döngüsü + girdi kaynakları duman testi (gerçek render DEĞİL) */
const path = require('path'); const A = path.join(__dirname, '../app/src/main/assets/');
let fails = 0; const ok = (c, m, x) => { console.log((c ? 'PASS ' : 'FAIL ') + m + (x !== undefined ? '  [' + x + ']' : '')); if (!c) fails++; };

const live = { n: 0, made: 0 };                                   // sızıntı sayacı: üretilen - serbest bırakılan GPU kaynakları
class Disp { constructor() { live.n++; live.made++; } dispose() { if (!this._d) { this._d = true; live.n--; } } }
class V3 { constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; } set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; } copy(o) { this.x = o.x; this.y = o.y; this.z = o.z; return this; } clone() { return new V3(this.x, this.y, this.z); } length() { return Math.hypot(this.x, this.y, this.z); } multiplyScalar(k) { this.x *= k; this.y *= k; this.z *= k; return this; } }
class Q { constructor() { this.x = 0; this.y = 0; this.z = 0; this.w = 1; } copy() { return this; } setFromUnitVectors() { return this; } setFromEuler() { return this; } setFromRotationMatrix() { return this; } }
class Eul { constructor() { this.x = 0; this.y = 0; this.z = 0; } set() { return this; } setFromQuaternion() { return this; } }
class Obj { constructor() { this.position = new V3(); this.scale = new V3(1, 1, 1); this.rotation = { set() { }, y: 0 }; this.quaternion = new Q(); this.children = []; this.visible = true; } set() { } add(o) { this.children.push(o); } remove(o) { this.children = this.children.filter(c => c !== o); } }
const noop = new Proxy(function () { }, { get: (t, k) => k === 'addColorStop' ? () => { } : noop, apply: () => noop });
class Geo extends Disp { setAttribute() { } computeBoundingSphere() { } }
global.THREE = {
  Group: Obj, Mesh: class extends Obj { constructor(g, m) { super(); this.geometry = g; this.material = m; } },
  InstancedMesh: class extends Obj { constructor(g, m, n) { super(); this.geometry = g; this.material = m; this.count = n; this.instanceMatrix = {}; } setMatrixAt() { } setColorAt() { } },
  HemisphereLight: Obj, DirectionalLight: Obj, BufferGeometry: Geo, BufferAttribute: class { }, SphereGeometry: Geo, PlaneGeometry: Geo,
  MeshLambertMaterial: class extends Disp { constructor(o) { super(); Object.assign(this, o); } }, MeshBasicMaterial: class extends Disp { constructor(o) { super(); Object.assign(this, o); } },
  CanvasTexture: class extends Disp { constructor() { super(); this.repeat = { set() { } }; } }, RepeatWrapping: 1, DoubleSide: 2, BackSide: 1, AdditiveBlending: 2,
  Matrix4: class { compose() { return this; } makeBasis() { return this; } }, Euler: Eul, Color: class { setRGB() { return this; } }, Vector3: V3, Quaternion: Q
};
global.document = { hidden: false, head: null, body: null, createElement: null, getElementById: null, addEventListener() { }, removeEventListener() { } };
class El { constructor(t) { this.tag = t; this.style = {}; this.classList = { add() { }, remove() { } }; this.l = {}; this.children = []; this.attrs = {}; this.textContent = ''; this.innerHTML = ''; this.width = 0; this.height = 0; }
  appendChild(c) { this.children.push(c); return c; } addEventListener(t, f) { (this.l[t] = this.l[t] || []).push(f); } setPointerCapture() { } remove() { } getAttribute(k) { return this.attrs[k]; } getContext() { return noop; }
  fire(t, e) { (this.l[t] || []).forEach(f => f(Object.assign({ preventDefault() { }, stopPropagation() { }, target: this }, e))); } }
const ids = {};
document.head = new El('head'); document.body = new El('body');
document.createElement = t => new El(t); document.getElementById = id => ids[id] || null;
const origAppend = El.prototype.appendChild; El.prototype.appendChild = function (c) { if (c.id) ids[c.id] = c; return origAppend.call(this, c); };
const origRemove = El.prototype.remove; El.prototype.remove = function () { if (this.id) delete ids[this.id]; };
const winL = {}; global.window = global; global.addEventListener = (t, f) => (winL[t] = winL[t] || []).push(f); global.removeEventListener = (t, f) => { winL[t] = (winL[t] || []).filter(x => x !== f); };
global.innerWidth = 1280; global.innerHeight = 800;
global.localStorage = { s: {}, getItem(k) { return this.s[k] === undefined ? null : this.s[k]; }, setItem(k, v) { this.s[k] = v; } };
let hist = 0; global.history = { pushState() { hist++; }, back() { hist--; setTimeout(() => (winL.popstate || []).forEach(f => f()), 0); } };

const toasts = [], panel = { visible: true }, panel2 = { visible: false };
// WebXR denetleyici taklidi
const ctrls = [0, 1].map(() => { const c = new Obj(); c.userData = {}; c.l = {}; c.addEventListener = (t, f) => { (c.l[t] = c.l[t] || []).push(f); }; c.removeEventListener = (t, f) => { c.l[t] = (c.l[t] || []).filter(x => x !== f); }; c.add(new Obj()); return c; });
const N = global.NEXUS = {
  Scene: { scene: new Obj(), sky: { visible: true }, floor: { visible: true }, ring: { visible: true }, dirty: false, grad: () => new Disp() },
  Cam: { rig: new Obj(), cam: new Obj(), yaw: 0.7, pitch: 0.2, zoom: 0, reset() { this.yaw = this.pitch = this.zoom = 0; } }, XR: { session: null, ctrls },
  Renderer: { scale: 1, resizes: 0, resize() { this.resizes++; }, r: { xr: { getController: i => ctrls[i] } } }, Stereo: { on: false },
  WM: { panels: [panel, panel2], repaintAll() { } }, Diag: { toast: (m) => toasts.push(m) }, Hand: { on: false, lite: false, clr() { }, setPreview() { }, start() { this.on = true; }, stop() { this.on = false; } },
  Game: { on: false, exit() { } }, Planets: { on: false, exit() { } }, Cinema: { on: false, exit() { } }, Launcher: { open: false, close() { } }
};
N.Scene.scene.fog = { near: 12, far: 48, color: { set() { }, clone() { return { c: 1 }; }, copy() { } } };
N.Cam.rig.position.set(0, 1.6, 0);
require(A + 'gorilla-phys.js'); require(A + 'gorilla-art.js'); require(A + 'gorilla-npc.js'); require(A + 'gorilla-audio.js'); require(A + 'gorilla.js');   // Stage 74: NPC + ses modülleri de yüklü
const G = window.Gorilla;
const lm = (cx, cy, size, fist) => { // 21 landmark: bilek (0), orta eklem (9), uç noktalar (8,12,16,20)
  const q = Array.from({ length: 21 }, () => ({ x: cx, y: cy })); q[0] = { x: cx, y: cy + size / 2 }; q[9] = { x: cx, y: cy - size / 2 };
  [8, 12, 16, 20].forEach((i, k) => { q[i] = { x: cx + (k - 1.5) * 0.01, y: cy + size / 2 - size * (fist ? 1.1 : 2.2) }; }); return q; };
const slot = (id, cx, cy, size, fist) => ({ id, on: true, hasT: true, lastSeen: performance.now(), dq: lm(cx, cy, size, fist) });

(async () => {
  G.enter();
  ok(G.on && G.st === 'menu', 'enter -> menu durumu');
  ok(!panel.visible && !panel2.visible && !N.Scene.sky.visible, 'NEXUS panelleri/gökyüzü gizlendi');
  ok(N.Scene.scene.children.includes(G.g) && ids.gor, 'oyun grubu ve arayüz eklendi');
  ok(G.q === 2, 'masaüstünde varsayılan kalite yüksek');
  G.tick(1 / 60); ok(G.sim.vel.y === 0, 'menüde fizik çalışmıyor');
  G.setState('play');
  // --- dokunmatik
  const [L, R] = G.ui.pads; const sy0 = 600;
  L.fire('pointerdown', { pointerId: 1, clientX: 100, clientY: sy0 }); R.fire('pointerdown', { pointerId: 2, clientX: 900, clientY: sy0 });
  for (let i = 0; i < 60; i++) G.tick(1 / 60);
  const zA = G.sim.body.z;
  for (let i = 0; i < 20; i++) { L.fire('pointermove', { pointerId: 1, clientX: 100, clientY: sy0 + i * 8 }); R.fire('pointermove', { pointerId: 2, clientX: 900, clientY: sy0 + i * 8 }); G.tick(1 / 60); }
  ok(G.sim.body.z < zA - 0.3, 'dokunmatik el çekme gövdeyi ileri taşıdı', 'dz=' + (G.sim.body.z - zA).toFixed(2));
  ok(Math.abs(N.Cam.rig.position.z - G.sim.body.z) < 1e-9, 'kamera rig gövdeyi izliyor');
  L.fire('pointerup', { pointerId: 1 }); R.fire('pointerup', { pointerId: 2 });
  ok(!G.pad[0].on && !G.pad[1].on, 'parmak kalkınca el serbest');
  const yaw0 = N.Cam.yaw; G.ui.look.fire('pointerdown', { pointerId: 3, clientX: 500, clientY: 300 }); G.ui.look.fire('pointermove', { pointerId: 3, clientX: 560, clientY: 300 });
  ok(N.Cam.yaw < yaw0, 'bakış alanı yaw değiştirdi'); G.ui.look.fire('pointerup', { pointerId: 3 });
  G.ui.jump.fire('pointerdown', { pointerId: 4 }); G.tick(1 / 60);

  // --- kamera ile gerçek el takibi
  G.sim.reset(); N.Hand.on = true; N.Hand.mirror = true;
  N.Hand.slots = [slot(0, 0.75, 0.55, 0.14, false), slot(1, 0.25, 0.55, 0.14, false)];       // ham x: aynalanınca 0.75 -> 0.25 (sol)
  for (let i = 0; i < 5; i++) { N.Hand.slots.forEach(s => s.lastSeen = performance.now()); G.tick(1 / 60); }
  ok(G.camSeen[0] === 1 && G.camSeen[1] === 1, 'iki kamera eli algılandı');
  ok(G.sim.hands[0].inp.x < 0 && G.sim.hands[1].inp.x > 0, 'ekranın solundaki el sol el, sağındaki sağ el', G.sim.hands[0].inp.x.toFixed(2) + ' / ' + G.sim.hands[1].inp.x.toFixed(2));
  ok(!G.sim.hands[0].grip && !G.sim.hands[1].grip, 'açık el: tutma yok');
  N.Hand.slots = [slot(0, 0.75, 0.55, 0.14, true), slot(1, 0.25, 0.55, 0.14, true)];
  for (let i = 0; i < 4; i++) { N.Hand.slots.forEach(s => s.lastSeen = performance.now()); G.tick(1 / 60); }
  ok(G.sim.hands[0].grip && G.sim.hands[1].grip, 'yumruk = tut');
  const yHi = G.sim.hands[0].inp.y; N.Hand.slots = [slot(0, 0.75, 0.2, 0.14, false), slot(1, 0.25, 0.2, 0.14, false)];
  for (let i = 0; i < 4; i++) { N.Hand.slots.forEach(s => s.lastSeen = performance.now()); G.tick(1 / 60); }
  ok(G.sim.hands[0].inp.y > yHi, 'el ekranda yukarı çıkınca kol yukarı kalkıyor', yHi.toFixed(2) + ' -> ' + G.sim.hands[0].inp.y.toFixed(2));
  const sizeBefore = G.sim.hands[0].inp.z; N.Hand.slots = [slot(0, 0.75, 0.55, 0.3, false), slot(1, 0.25, 0.55, 0.3, false)];
  for (let i = 0; i < 4; i++) { N.Hand.slots.forEach(s => s.lastSeen = performance.now()); G.tick(1 / 60); }
  ok(G.sim.hands[0].inp.z < sizeBefore, 'el kameraya yaklaşınca ileri uzanıyor', sizeBefore.toFixed(2) + ' -> ' + G.sim.hands[0].inp.z.toFixed(2));
  N.Hand.slots = [slot(0, 0.5, 0.5, 0.14, false)]; N.Hand.slots[0].lastSeen = performance.now() - 2000;
  G.tick(1 / 60); ok(G.camSeen[0] === 0 && G.camSeen[1] === 0 && G.sim.hands[0].valid, 'takip kaybında eski veri kullanılmıyor, el dinlenme konumuna dönüyor');
  ok(G.ownsHands() === true, 'oyun açıkken kamera elleri oyuna ait (panel etkileşimi kapalı)');
  N.Hand.on = false; N.Hand.slots = [];

  // --- WebXR oturumu: oyun açılıyor, menü yok, denetleyici girdisi
  G.ui.pause.fire('pointerdown', { pointerId: 5 }); ok(G.st === 'paused', 'duraklat düğmesi');
  N.XR.session = { inputSources: [] };
  ctrls[0].visible = true; ctrls[1].visible = true;
  ctrls[0].userData.nxIS = { handedness: 'left', gamepad: { buttons: [{ value: 0 }, { pressed: false, value: 0 }, {}, {}, { pressed: false }, { pressed: false }] } };
  ctrls[1].userData.nxIS = { handedness: 'right', gamepad: { buttons: [{ value: 0 }, { pressed: true, value: 1 }, {}, {}, { pressed: false }, { pressed: false }] } };
  N.Cam.cam.position.set(0.3, 1.6, -0.2);
  ctrls[0].position.set(0.1, 1.0, -0.5); ctrls[1].position.set(0.6, 1.1, -0.5);
  G.tick(1 / 72);
  ok(G.xr && G.st === 'play' && G.ui.root.style.display === 'none', 'XR başlayınca oyun oynanıyor, DOM arayüzü gizli');
  ok(G.sim.yaw === 0, 'XR: gövde yönü sabit (rig dönmez)');
  ok(Math.abs(G.sim.hands[0].inp.x - (0.1 - 0.3)) < 1e-6 && Math.abs(G.sim.hands[0].inp.z - (-0.5 + 0.2)) < 1e-6, 'XR: sol denetleyici baş-göreli el konumuna çevrildi');
  ok(G.sim.hands[1].grip && !G.sim.hands[0].grip, 'XR: sağ el squeeze = tut');
  ok(Math.abs(N.Cam.rig.position.x - (G.sim.body.x - 0.3)) < 1e-9 && Math.abs(N.Cam.rig.position.y - (G.sim.body.y + 0.25 - 1.6)) < 1e-9, 'XR: rig, baş gövdenin 0.25 m üstünde kalacak şekilde kaydırıldı');
  ok(ctrls[0].children[0].visible === false, 'XR: oyun sırasında denetleyici ışını gizli');
  ctrls[0].userData.nxIS.gamepad.buttons[4].pressed = true; G.sim.time = 0; G.sim.lastContact = 0; G.tick(1 / 72);
  ok(G.xrBtn[0] === true, 'XR: A/X düğmesi zıplama isteği üretti (kenar algılama)');
  ctrls[1].visible = false; G.tick(1 / 72); ok(G.sim.hands[1].inp !== undefined && G.camSeen[1] === 0, 'XR: takip edilmeyen denetleyici yok sayılıyor');
  N.XR.session = null; G.tick(1 / 72);
  ok(!G.xr && G.st === 'paused' && G.ui.root.style.display === '' && ctrls[0].children[0].visible === true, 'XR bitince menüye dönüldü, ışınlar geri geldi');
  G.setState('play');

  // --- otomatik kalite
  const q0 = G.q, sc0 = N.Renderer.scale; for (let i = 0; i < 400; i++) G.tick(0.05);
  ok(G.q < q0 && N.Renderer.scale < sc0, 'yavaş karelerde kalite otomatik düştü', q0 + ' -> ' + G.q + ', ölçek ' + N.Renderer.scale.toFixed(2));
  // telefon profili
  G.exit(); N.Hand.lite = true; global.innerWidth = 390; global.innerHeight = 800; G.enter(); ok(G.q === 0, 'telefonda düşük kalite seçiliyor'); G.exit();
  global.innerWidth = 1024; global.innerHeight = 768; G.enter(); ok(G.q === 1, 'tablette orta kalite seçiliyor'); G.exit(); N.Hand.lite = false; global.innerWidth = 1280; global.innerHeight = 800;
  // --- Cardboard / stereo: menü beklemeden oyun
  N.Stereo.on = true; G.enter(); ok(G.st === 'play', 'stereo (telefon VR) modunda doğrudan oyun başlıyor'); G.exit(); N.Stereo.on = false;

  G.enter(); G.setState('paused');
  // arka plana alma
  G.setState('play'); document.hidden = true; G._vis(); ok(G.st === 'paused', 'sayfa gizlenince oyun duraklıyor'); document.hidden = false;
  G._pop(); await new Promise(r => setTimeout(r, 5));
  ok(!G.on, 'geri tuşu (popstate) menüden çıkıyor');
  ok(panel.visible && !panel2.visible && N.Scene.sky.visible, 'çıkışta panel/gökyüzü durumu geri yüklendi (önceki gizli panel gizli kaldı)');
  ok(N.Cam.yaw === 0.7 && N.Cam.rig.position.y === 1.6, 'çıkışta kamera durumu geri yüklendi');
  ok(N.Renderer.scale === 1, 'çıkışta render ölçeği geri yüklendi');
  ok(G.g === null && !ids.gor, 'sahne grubu ve DOM kaldırıldı');
  // sızıntı: 20 kez aç-kapa sonrası canlı GPU kaynağı artmıyor
  const base = live.n; for (let i = 0; i < 20; i++) { G.enter(); G.setState('play'); G.tick(1 / 60); G.exit(); await new Promise(r => setTimeout(r, 1)); }
  ok(!G.on && N.Scene.scene.children.length === 0 && !ids.gor && !ids['gor-css'], '20 aç/kapat sonrası sahne ve DOM temiz');
  ok(live.n === base, 'GPU kaynağı sızıntısı yok (geometri/malzeme/doku)', 'canlı=' + live.n + ' taban=' + base + ' toplam üretilen=' + live.made);
  // kamera eli: oyun kamerayı kendisi başlattıysa çıkışta kapatır
  N.Hand.on = false; localStorage.s['nexus.gorilla.v1'] = JSON.stringify({ cam: true }); G.enter(); ok(!N.Hand.on, 'menü açılırken kamera kendiliğinden açılmıyor (gizlilik: kullanıcı dokunuşu gerekir)'); G.ui.menu.onclick({ target: { getAttribute: k => k === 'data-a' ? 'play' : null } }); ok(N.Hand.on && G.st === 'play', 'Oyuna başla dokunuşu kamera elini başlattı'); G.exit(); ok(!N.Hand.on, 'çıkışta kendi başlattığı kamerayı kapattı');
  // bozuk kayıt
  localStorage.s['nexus.gorilla.v1'] = '{bozuk'; G.enter(); ok(G.on && G.st === 'menu', 'bozuk kayıtla çökmeden açılıyor'); G.exit();
  localStorage.s['nexus.gorilla.v1'] = JSON.stringify({ sens: 999, assist: 'x', quality: 7, fur: 99, camScale: -3 }); G.enter(); ok(G.on, 'geçersiz alanlı kayıtla açılıyor'); ok(G.q >= 0 && G.q <= 2, 'geçersiz kalite değeri varsayılana döndü'); G.exit();
  console.log(fails ? '\n' + fails + ' TEST BAŞARISIZ' : '\nTÜM DUMAN TESTLERİ GEÇTİ'); process.exit(fails ? 1 : 0);
})().catch(e => { console.error('İSTİSNA', e); process.exit(2); });
