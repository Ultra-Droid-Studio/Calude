/* node tools/gorilla-art.test.js -- geometri üreticileri (saf JS) + sahte THREE/canvas ile buildWorld/makePlayer akışı. Gerçek WebGL çıktısını DOĞRULAMAZ. */
const path = require('path'); const A = path.join(__dirname, '../app/src/main/assets/');
let fails = 0; const ok = (c, m, x) => { console.log((c ? 'PASS ' : 'FAIL ') + m + (x !== undefined ? '  [' + x + ']' : '')); if (!c) fails++; };
const P = require(A + 'gorilla-phys.js'), Art = require(A + 'gorilla-art.js');

// --- saf geometri: dışbükey şekillerde tüm normaller dışa bakıyor, UV/renk uzunlukları tutarlı
function outward(prim, S, name) {
  const b = new Art.Batch().add(prim, { s: S || [1, 1, 1], t: [3, 2, 1] });
  let bad = 0; for (let i = 0; i < b.pos.length; i += 9) { const cx = (b.pos[i] + b.pos[i + 3] + b.pos[i + 6]) / 3 - 3, cy = (b.pos[i + 1] + b.pos[i + 4] + b.pos[i + 7]) / 3 - 2, cz = (b.pos[i + 2] + b.pos[i + 5] + b.pos[i + 8]) / 3 - 1; if (b.nrm[i] * cx + b.nrm[i + 1] * cy + b.nrm[i + 2] * cz <= 0) bad++; }
  ok(bad === 0 && b.uv.length / 2 === b.pos.length / 3 && b.col.length === b.pos.length, name + ': normaller dışa bakıyor, öznitelik uzunlukları tutarlı', b.tris() + ' üçgen');
}
outward(Art.boxP(2, 1, 3, 2), null, 'kutu'); outward(Art.cylP(0.5, 0.3, 2, 8, 2, true), null, 'silindir'); outward(Art.sphP(1, 8, 6), [0.4, 0.3, 0.2], 'küre');
{ const b = new Art.Batch().add(Art.cylP(1, 1, 2, 6, 2, true), { r: Art.rotFromY([1, 0, 0]) }); let mx = 0, mn = 0; for (let i = 0; i < b.pos.length; i += 3) { mx = Math.max(mx, b.pos[i]); mn = Math.min(mn, b.pos[i]); } ok(Math.abs(mx - 1) < 1e-6 && Math.abs(mn + 1) < 1e-6, 'rotFromY: +Y ekseni +X yönüne döndü'); }
{ const b = new Art.Batch().add({ pos: [0, 0, 0, 1, 0, 0, 0, 0, 1], uv: [0, 0, 1, 0, 0, 1] }, { up: true }); ok(b.nrm[1] > 0.99, 'up:true düz yüzeyi yukarı bakıtıyor'); }
{ const b = new Art.Batch(); Art.addGorilla(b, { x: 0, z: 0, yaw: 0, fur: [1, 0.3, 0.6], hat: 'party' }); let bad = b.pos.some(v => !isFinite(v)); ok(!bad && b.tris() > 250 && b.tris() < 1500, 'gorilla modeli üretildi (sonlu, makul üçgen sayısı)', b.tris() + ' üçgen'); }
// NPC yönü: yaw=atan2(nx,nz) ile modelin "ileri" (-Z) ekseni merkeze bakmalı
{ const n = P.forestMap(1717).npcs[0], f = Art.apply3(Art.rotY(n.yaw), [0, 0, -1]), d = Math.hypot(n.x, n.z); ok(f[0] * (-n.x / d) + f[2] * (-n.z / d) > 0.99, 'NPC gorilla ateşe bakıyor'); }

// --- sahte THREE + canvas ile akış
const draws = { geo: 0, mat: 0, tex: 0 };
const noop = new Proxy(function () { }, { get: (t, k) => k === 'addColorStop' ? () => { } : noop, apply: () => noop });
global.document = { createElement: () => ({ width: 0, height: 0, getContext: () => noop }) };
class V3 { constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; } set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; } copy(o) { this.x = o.x; this.y = o.y; this.z = o.z; return this; } }
class Q { constructor() { this.x = 0; this.y = 0; this.z = 0; this.w = 1; } setFromUnitVectors() { return this; } setFromEuler() { return this; } setFromRotationMatrix() { return this; } copy() { return this; } }
class Obj { constructor() { this.position = new V3(); this.scale = new V3(1, 1, 1); this.rotation = { set() { }, y: 0 }; this.quaternion = new Q(); this.children = []; this.visible = true; } add(o) { this.children.push(o); } }
class Disp { dispose() { this.disposed = true; } }
class BufGeo extends Disp { constructor() { super(); draws.geo++; this.a = {}; } setAttribute(k, v) { this.a[k] = v; } computeBoundingSphere() { } }
global.THREE = {
  Group: Obj, Mesh: class extends Obj { constructor(g, m) { super(); this.geometry = g; this.material = m; } },
  InstancedMesh: class extends Obj { constructor(g, m, n) { super(); this.geometry = g; this.material = m; this.count = n; this.instanceMatrix = {}; this.mats = n; } setMatrixAt() { } setColorAt() { } },
  BufferGeometry: BufGeo, BufferAttribute: class { constructor(a, n) { this.array = a; this.n = n; } }, PlaneGeometry: BufGeo,
  MeshLambertMaterial: class extends Disp { constructor(o) { super(); draws.mat++; Object.assign(this, o); } }, MeshBasicMaterial: class extends Disp { constructor(o) { super(); Object.assign(this, o); } },
  CanvasTexture: class extends Disp { constructor() { super(); draws.tex++; this.repeat = { set() { } }; } }, RepeatWrapping: 1, DoubleSide: 2, AdditiveBlending: 2,
  Matrix4: class { compose() { return this; } makeBasis() { return this; } }, Euler: class { set() { return this; } }, Color: class { setRGB() { return this; } },
  Vector3: V3, Quaternion: Q
};
const map = P.forestMap(1717);
for (const lv of [0, 1, 2]) {
  const t0 = Date.now(), w = Art.buildWorld(THREE, map, { quality: lv });
  const dc = Object.keys(w.meshes).length + 2 /*zemin+duvar*/ + 1 /*yaprak*/ + w.fires.length + w.npcs.length;
  let nan = false; Object.values(w.meshes).forEach(m => { const a = m.geometry.a.position.array; for (let i = 0; i < a.length; i++) if (!isFinite(a[i])) nan = true; });
  ok(!nan && w.leaves.count > 0 && dc < 30, 'buildWorld kalite ' + lv + ': sonlu geometri, çizim çağrısı ~' + dc, (Date.now() - t0) + ' ms, yaprak ' + w.leaves.count + '/' + w.leafTotal);
  w.update(0.016, 1.2); w.setQuality(0); ok(w.leaves.count < w.leafTotal, 'setQuality(0) yaprak sayısını azalttı', w.leaves.count);
  w.dispose();
}
const pl = Art.makePlayer(THREE, 0x2a2a30, null);
const hands = [{ valid: true, x: -0.4, y: 0.6, z: -0.5, contact: true, grip: false, n: { x: 0, y: 1, z: 0 } }, { valid: true, x: 0.5, y: 0.2, z: -0.7, contact: false, grip: true }];
pl.pose({ x: 1, y: 1, z: 2 }, 0.8, hands);
ok(pl.arms[0].hand.visible && !pl.arms[0].fist.visible && pl.arms[1].fist.visible && !pl.arms[1].hand.visible, 'avatar: açık el / yumruk görünürlüğü doğru');
hands[0].valid = false; pl.pose({ x: 1, y: 1, z: 2 }, 0.8, hands); ok(!pl.arms[0].up.visible, 'avatar: takip yoksa kol gizli');
hands[0] = { valid: true, x: 1, y: 1, z: 2, contact: false, grip: false }; pl.pose({ x: 1, y: 1, z: 2 }, 0, hands); ok(isFinite(pl.arms[0].hand.position.x), 'avatar: el gövde merkezinde olsa bile sayı bozulmuyor');
pl.dispose(); ok(true, 'avatar dispose çalıştı');
console.log(fails ? '\n' + fails + ' TEST BAŞARISIZ' : '\nTÜM GÖRSEL KATMAN TESTLERİ GEÇTİ'); process.exit(fails ? 1 : 0);
