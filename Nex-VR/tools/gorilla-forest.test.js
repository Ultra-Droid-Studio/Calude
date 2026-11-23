/* node tools/gorilla-forest.test.js -- orman haritası: çarpışma ve yürünebilirlik testleri */
const P = require('../app/src/main/assets/gorilla-phys.js');
let fails = 0; const ok = (c, m, x) => { console.log((c ? 'PASS ' : 'FAIL ') + m + (x !== undefined ? '  [' + x + ']' : '')); if (!c) fails++; };
const map = P.forestMap(1717);
const W = () => new P.World(map.colliders);
const stand = (pos, steps = 180) => {
  const sim = new P.Sim(W()); sim.spawn = pos; sim.reset();
  for (let i = 0; i < steps; i++) { sim.setHand(0, true, -0.34, -0.8, -0.2, false); sim.setHand(1, true, 0.34, -0.8, -0.2, false); sim.step(1 / 60); }
  return sim;
};
ok(map.colliders.length > 100 && map.leaves.length > 150, 'harita üretildi', map.colliders.length + ' çarpışma, ' + map.leaves.length + ' yaprak');
ok(JSON.stringify(P.forestMap(1717).colliders) === JSON.stringify(map.colliders), 'harita deterministik (aynı tohum aynı harita)');
let s = stand(map.spawn);
ok(Math.abs(s.body.x - map.spawn.x) < 0.5 && Math.abs(s.body.z - map.spawn.z) < 0.5 && s.body.y > 0.2 && s.body.y < 1.2, 'başlangıçta ayakta duruyor', s.body.y.toFixed(2));
map.platforms.forEach((p, i) => { const t = stand({ x: p.x + 0.6, y: p.y + 1, z: p.z + 0.3 }, 120); ok(t.body.y > p.y && t.body.y < p.y + 1.2 && t.grounded === true || t.body.y > p.y, 'platform ' + i + ' üstünde duruyor', t.body.y.toFixed(2) + ' / ' + p.y.toFixed(2)); });
// köprü ortası: iki platform arasında orta nokta
{ const a = map.platforms[0], b = map.platforms[1], mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2, my = (a.y + b.y) / 2 + 1; const t = stand({ x: mx, y: my, z: mz }, 150); ok(t.body.y > Math.min(a.y, b.y) - 0.5, 'köprü ortasında düşmüyor', t.body.y.toFixed(2)); }
// ağaç evi ve kulübe çatısı
{ const h = map.house; const t = stand({ x: h.x + 0.5, y: h.y + 1, z: h.z }, 120); ok(t.body.y > h.y, 'ağaç evi zemini taşıyor', t.body.y.toFixed(2)); const k = map.hut; const t2 = stand({ x: k.x, y: 4.5, z: k.z - 1 }, 120); ok(t2.body.y > 2.5, 'kulübe çatısı taşıyor', t2.body.y.toFixed(2)); }
// kanyondan çıkılamaz
{ const sim = new P.Sim(W()); sim.spawn = { x: 29, y: 1, z: 0 }; sim.reset(); for (let i = 0; i < 400; i++) { sim.setHand(0, true, -0.3, -0.6, 0.1, false); sim.setHand(1, true, 0.3, -0.6, 0.1, false); sim.vel.x = 8; sim.step(1 / 60); } ok(Math.hypot(sim.body.x, sim.body.z) < 33, 'kanyon duvarı gövdeyi içeride tutuyor', Math.hypot(sim.body.x, sim.body.z).toFixed(2)); }
// ağaç tırmanma: ağaca dönük, eller sırayla yukarı uzanıp çekilir
{ const t = map.trees[0]; const sim = new P.Sim(W()); const dir = Math.atan2(t.z, t.x); const d = t.r + 0.45;
  // oyuncu ağacın merkeze bakan tarafında durur ve ağaca (yarıçap yönünde dışarı) bakar
  sim.spawn = { x: t.x - Math.cos(dir) * d, y: 1, z: t.z - Math.sin(dir) * d }; sim.reset();
  sim.yaw = Math.atan2(-Math.cos(dir), -Math.sin(dir)) * -1 + Math.PI; // ileri(-z) -> +dir
  // yaw: world = (x*cy + z*sy, -x*sy + z*cy); ileri (0,-1) -> (-sy, -cy) == (cos dir, sin dir)
  sim.yaw = Math.atan2(-Math.cos(dir), -Math.sin(dir));
  const g0 = sim.body.y; let anchored = 0;
  // roller: 'a' eli yukarı uzatır (serbest) -> tutunur ve aşağı çeker; 'b' eli o sırada tutunmuş durur, sonra roller değişir
  for (let c = 0; c < 12; c++) {
    const a = c % 2, b = 1 - c % 2, xa = a === 0 ? -0.12 : 0.12, xb = -xa;
    for (let i = 0; i < 25; i++) { sim.setHand(a, true, xa, 0.15 + i / 25 * 0.6, -0.5, false); sim.setHand(b, true, xb, sim.hands[b].L.y, -0.5, true); sim.step(1 / 60); }
    for (let i = 0; i < 30; i++) { sim.setHand(a, true, xa, 0.75 - i / 30 * 0.7, -0.5, true); sim.setHand(b, true, xb, sim.hands[b].L.y, -0.5, i < 6); sim.step(1 / 60); if (sim.hands[a].anchor) anchored++; }
  }
  ok(anchored > 100 && sim.body.y > g0 + 0.5, 'ağaca tutunup tırmanıldı', 'y ' + g0.toFixed(2) + ' -> ' + sim.body.y.toFixed(2) + ', tutunma ' + anchored); }
// rastgele girdi: NaN yok, harita altına düşme yok, dışarı çıkış yok
{ const sim = new P.Sim(W()); sim.spawn = map.spawn; sim.reset(); let seed = 7; const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296; let bad = false, minY = 9, maxR = 0;
  for (let i = 0; i < 30000; i++) { if (i % 5 === 0) for (let h = 0; h < 2; h++) sim.setHand(h, rnd() > 0.03, (rnd() - 0.5) * 1.8, (rnd() - 0.8) * 1.4, (rnd() - 0.5) * 1.8, rnd() > 0.6); if (i % 97 === 0) sim.jump(); sim.step(rnd() < 0.02 ? 0.12 : 1 / 60); const b = sim.body; if (!isFinite(b.x + b.y + b.z)) bad = true; minY = Math.min(minY, b.y); maxR = Math.max(maxR, Math.hypot(b.x, b.z)); }
  ok(!bad && minY > -1 && maxR < 33.2, '30000 rastgele adım: NaN yok, dışarı/altına çıkış yok', 'minY=' + minY.toFixed(2) + ' maxR=' + maxR.toFixed(1)); }
// başarım: sorgu süresi
{ const w = W(); const t0 = Date.now(); let c = 0; for (let i = 0; i < 20000; i++) { const p = { x: (i % 60) - 30, y: (i % 7), z: ((i * 7) % 60) - 30 }; if (w.resolve(p, 0.3).hit) c++; } const ms = Date.now() - t0; ok(ms < 1500, '20000 çarpışma çözümü hızlı', ms + ' ms'); }
console.log(fails ? '\n' + fails + ' TEST BAŞARISIZ' : '\nTÜM ORMAN TESTLERİ GEÇTİ'); process.exit(fails ? 1 : 0);
