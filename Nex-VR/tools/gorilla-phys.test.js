/* node tools/gorilla-phys.test.js  -- fizik çekirdeği birim testleri (THREE/DOM gerekmez) */
const { World, Sim, testMap, CFG } = require('../app/src/main/assets/gorilla-phys.js');
let fails = 0;
const ok = (c, m, extra) => { console.log((c ? 'PASS ' : 'FAIL ') + m + (extra !== undefined ? '  [' + extra + ']' : '')); if (!c) fails++; };
const mk = () => { const m = testMap(); const s = new Sim(new World(m.colliders)); s.spawn = m.spawn; s.reset(); return s; };
const FR = 1 / 60;
const planted = (z, grip) => [[true, 0.3, -Math.sqrt(0.95 * 0.95 - z * z), z, grip], [true, -0.3, -Math.sqrt(0.95 * 0.95 - z * z), z, grip]];
const setBoth = (s, z, grip) => planted(z, grip).forEach((a, i) => s.setHand(i, ...a));
const run = (s, secs, fn) => { const n = Math.round(secs / FR); for (let i = 0; i < n; i++) { if (fn) fn(i, n); s.step(FR); } };

// 1) Ellerle ayakta durma: kararlı, titremesiz
{ const s = mk(); setBoth(s, -0.45); run(s, 2);
  const sp = Math.hypot(s.vel.x, s.vel.y, s.vel.z);
  ok(Math.abs(s.body.y - 1.0) < 0.2 && sp < 0.3, '1 ellerle ayakta durma kararlı', 'y=' + s.body.y.toFixed(3) + ' hız=' + sp.toFixed(3)); }

// 2) Her iki el yerde geri çekilince gövde ileri (-Z) gider ve bırakınca hız korunur
{ const s = mk(); setBoth(s, -0.45); run(s, 0.5);
  const z0 = s.body.z;
  run(s, 0.3, (i, n) => setBoth(s, -0.45 + 0.8 * (i + 1) / n));
  const moved = z0 - s.body.z;
  ok(moved > 0.4, '2a el geri çekme gövdeyi ileri taşıdı', 'ilerleme=' + moved.toFixed(2) + ' m');
  setBoth(s, 0.35); run(s, 0.01);
  const vz = s.vel.z;
  ok(vz < -1, '2b temasta ileri hız oluştu', 'vz=' + vz.toFixed(2));
  // eller havaya kalkınca hız korunur
  const handsUp = () => { s.setHand(0, true, 0.3, 0.3, -0.3, false); s.setHand(1, true, -0.3, 0.3, -0.3, false); };
  handsUp(); run(s, 0.05, handsUp);
  ok(s.vel.z < -0.8, '2c temas bitince gövde hızı korunuyor', 'vz=' + s.vel.z.toFixed(2)); }

// 3) Takip kaybı: ani itiş yok
{ const s = mk(); setBoth(s, -0.45); run(s, 0.5);
  run(s, 0.1, (i, n) => setBoth(s, -0.45 + 0.4 * (i + 1) / n));
  const before = Math.hypot(s.vel.x, s.vel.z);
  s.setHand(0, false); s.setHand(1, false);
  run(s, 0.3);
  const after = Math.hypot(s.vel.x, s.vel.z);
  ok(after <= before + 0.05 && Math.hypot(s.vel.x, s.vel.y, s.vel.z) < CFG.maxH + 0.1, '3a takip kaybında hız artmıyor', before.toFixed(2) + ' -> ' + after.toFixed(2));
  // takip geri gelince uzak bir noktaya ışınlanan el itiş üretmez
  const bz = s.body.z, by = s.body.y;
  s.setHand(0, true, 0.3, -0.85, 0.5, false); s.setHand(1, true, -0.3, -0.85, 0.5, false);
  run(s, 0.05);
  ok(Math.abs(s.body.z - bz) < 0.3 && s.body.y > 0.25, '3b takip dönüşünde fırlama yok', 'dz=' + (s.body.z - bz).toFixed(3)); }

// 4) Çok uzun kare (0.5 s): zeminden geçme / fırlama yok
{ const s = mk(); s.body.y = 3; setBoth(s, -0.45); s.step(0.5); s.step(0.5); run(s, 1);
  ok(s.body.y > 0.25 && s.body.y < 3.5, '4 uzun karede zemin altına düşmedi', 'y=' + s.body.y.toFixed(2)); }

// 5) Duvara koşu: duvarın içinden geçmez
{ const s = mk(); s.body.x = 1; s.body.z = 4; s.vel.z = 8;
  run(s, 1.5, () => { s.setHand(0, false); s.setHand(1, false); });
  ok(s.body.z <= 6 - CFG.bodyR + 0.02 && s.body.z > 5.4, '5a gövde duvara kadar gitti ama içine girmedi', 'z=' + s.body.z.toFixed(2));
  ok(Math.abs(s.vel.z) < 0.3, '5b duvar köşesinde sahte geri kayma yok', 'vz=' + s.vel.z.toFixed(2)); }

// 6) Havada zıplama yok / yerde destekli zıplama
{ const s = mk(); s.body.y = 6; s.setHand(0, false); s.setHand(1, false); run(s, 0.1);
  ok(s.jump() === false, '6a havada zıplanamıyor');
  const t = mk(); setBoth(t, -0.45); run(t, 0.6);
  ok(t.jump() === true && t.vel.y > 4, '6b temasta destekli zıplama', 'vy=' + t.vel.y.toFixed(2)); }

// 7) Tırmanma: gövde ağaç gövdesine tutunup el değiştirerek yükselir, bırakınca düşer
{ const s = mk(); s.body.x = 5; s.body.z = -8 + 0.9; s.body.y = 1.5; s.yaw = 0;
  // eller gövdeye (cyl R=.45 merkez 5,-8) +z tarafında; gövde merkezinin 0.5 önünde (-z)
  const reachUp = (y) => [[true, 0.15, y, -0.55, true], [true, -0.15, y, -0.55, true]];
  const y0 = s.body.y;
  for (let cycle = 0; cycle < 4; cycle++) {
    // el yukarı uzat (tutunmadan), tutun, aşağı çek
    run(s, 0.15, () => { s.setHand(0, true, 0.15, 0.55, -0.55, false); s.setHand(1, true, -0.15, 0.55, -0.55, false); });
    run(s, 0.1, () => { s.setHand(0, true, 0.15, 0.55, -0.55, true); s.setHand(1, true, -0.15, 0.55, -0.55, true); });
    run(s, 0.4, (i, n) => { const y = 0.55 - 0.8 * (i + 1) / n; s.setHand(0, true, 0.15, y, -0.55, true); s.setHand(1, true, -0.15, y, -0.55, true); });
  }
  const gained = s.body.y - y0;
  ok(gained > 0.5, '7a tırmanma yükseklik kazandırdı', 'kazanç=' + gained.toFixed(2) + ' m');
  const rCyl = Math.hypot(s.body.x - 5, s.body.z + 8);
  ok(rCyl >= 0.45 + CFG.bodyR - 0.03, '7b gövde ağacın içine girmedi', 'r=' + rCyl.toFixed(2));
  s.setHand(0, true, 0.15, 0.2, -0.55, false); s.setHand(1, true, -0.15, 0.2, -0.55, false);
  const yHold = s.body.y; run(s, 0.6);
  ok(s.body.y < yHold - 1.2, '7c bırakınca düşüyor (gripsiz el ağaca yapışmıyor)', yHold.toFixed(2) + ' -> ' + s.body.y.toFixed(2)); }

// 8) Tutunan el çok uzaklaşırsa bırakır; tutunma yalnızca tırmanılabilir yüzeyde
{ const s = mk(); s.body.y = 0.95; setBoth(s, -0.45, true); run(s, 0.3);
  ok(!s.hands[0].anchor && !s.hands[1].anchor, '8 zeminde (tırmanılamaz) tutunma oluşmaz'); }

// 9) Rastgele girdi: sonlu, sınırlı, zemin altına inmeyen
{ const s = mk(); let seed = 12345; const R = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
  let bad = 0, maxV = 0, minY = 1e9;
  for (let i = 0; i < 20000; i++) {
    const hv = R() > 0.1;
    s.setHand(0, hv, (R() - .5) * 2, (R() - .5) * 2, (R() - .5) * 2, R() > 0.7);
    s.setHand(1, R() > 0.1, (R() - .5) * 2, (R() - .5) * 2, (R() - .5) * 2, R() > 0.7);
    s.yaw += (R() - .5) * 0.2;
    s.step(R() < 0.02 ? 0.4 : FR * (0.5 + R()));
    const b = s.body, v = s.vel;
    if (![b.x, b.y, b.z, v.x, v.y, v.z].every(Number.isFinite)) bad++;
    maxV = Math.max(maxV, Math.hypot(v.x, v.z)); minY = Math.min(minY, b.y);
  }
  ok(bad === 0, '9a 20000 rastgele adımda NaN/Infinity yok');
  ok(maxV <= CFG.maxH + 0.01, '9b yatay hız sınırı korunuyor', 'maks=' + maxV.toFixed(2));
  ok(minY > -1, '9c gövde haritanın altına inmedi', 'minY=' + minY.toFixed(2) + ' respawns=' + s.respawns); }

// 10) Adım sayısı sınırlı (uzun kare yüzlerce adım çalıştırmaz)
{ const s = mk(); s.step(5); ok(s.lastStepCount <= CFG.maxSteps, '10 uzun karede adım sayısı sınırlı', 'adım=' + s.lastStepCount); }

console.log(fails ? '\n' + fails + ' TEST BAŞARISIZ' : '\nTÜM TESTLER GEÇTİ');
process.exit(fails ? 1 : 0);
