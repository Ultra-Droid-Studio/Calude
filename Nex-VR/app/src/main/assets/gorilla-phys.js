/* NEXUS VR: GORILLA RUN - fizik çekirdeği (THREE/DOM bağımsız).
   Tüm sabitler CFG içinde toplanır. Çarpışma geometrisi görsel geometriden ayrıdır.
   Koordinatlar metre; +Y yukarı; oyuncu başlangıçta -Z yönüne bakar. */
(function (root) {
  'use strict';

  var CFG = {
    gravity: 9.8,        // m/s^2
    airDrag: 0.12,       // 1/s doğrusal hava direnci
    maxH: 9,             // maks yatay hız
    maxUp: 11,           // maks yukarı hız
    maxDown: 25,         // maks düşüş hızı
    bodyR: 0.3,          // gövde küre yarıçapı
    handR: 0.1,          // el küre yarıçapı
    arm: 0.95,           // kol uzunluğu (omuzdan el merkezine)
    reach: 1.05,         // elin gövdeye göre ulaşabileceği en uzak mesafe
    friction: 1.0,       // yüzeye basılı el hareketinin gövdeye aktarılma oranı
    push: 1.0,           // itiş kazancı
    velSmooth: 0.55,     // temasta hız süzgeci (0..1, yüksek = hızlı tepki)
    maxShift: 0.35,      // tek fizik adımında bir elin gövdeyi en çok taşıyacağı mesafe
    maxPushVel: 12,      // el hareketinden türeyen itiş hızı üst sınırı
    maxHandJump: 0.7,    // tek karede bu kadar atlayan el verisi ışınlanma sayılır, itiş üretmez
    inputSmooth: 0,      // el girdisi süzgeci (0 = kapalı; takip gürültüsü için artırılabilir)
    gripTol: 0.07,       // tutunma için yüzeye en fazla bu kadar uzaklık
    gripBreak: 1.35,     // tutunan el bu mesafeden uzaklaşırsa bırakır
    step: 1 / 90,        // sabit fizik adımı
    maxSteps: 4,         // bir karede en çok bu kadar adım (uzun kare fırlatmasın)
    jump: 4.6,           // destekli zıplama hızı
    jumpCooldown: 0.4,
    jumpWindow: 0.2,     // son temastan sonra zıplamaya izin verilen süre
    killY: -25           // bunun altında başlangıca döner
  };

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function fin(v) { return typeof v === 'number' && isFinite(v); }

  /* ---------- çarpışma dünyası ---------- */
  function World(colliders) {
    this.list = [];
    var self = this;
    (colliders || []).forEach(function (c) { self.add(c); });
  }
  World.prototype.add = function (c) {
    var o = Object.assign({}, c);
    if (o.type === 'cyl') {
      o.min = { x: o.x - o.R, y: o.y0, z: o.z - o.R };
      o.max = { x: o.x + o.R, y: o.y1, z: o.z + o.R };
    } else if (o.type === 'seg') {        // dal: a->b doğru parçası + yarıçap R
      var R = o.R;
      o.min = { x: Math.min(o.a.x, o.b.x) - R, y: Math.min(o.a.y, o.b.y) - R, z: Math.min(o.a.z, o.b.z) - R };
      o.max = { x: Math.max(o.a.x, o.b.x) + R, y: Math.max(o.a.y, o.b.y) + R, z: Math.max(o.a.z, o.b.z) + R };
    } else if (o.type === 'ring') {       // kanyon duvarı: iç yarıçap R, dışarı çıkılamaz
      o.min = { x: o.x - o.R - 4, y: o.y0, z: o.z - o.R - 4 };
      o.max = { x: o.x + o.R + 4, y: o.y1, z: o.z + o.R + 4 };
      o.big = true;
    } else if (o.type === 'obb') {        // eğik kutu: merkez c, yarı boyut h, rot = 3x3 (satır sıralı, yerel->dünya)
      var m = o.rot, ex = 0, ey = 0, ez = 0;
      ex = Math.abs(m[0]) * o.h.x + Math.abs(m[1]) * o.h.y + Math.abs(m[2]) * o.h.z;
      ey = Math.abs(m[3]) * o.h.x + Math.abs(m[4]) * o.h.y + Math.abs(m[5]) * o.h.z;
      ez = Math.abs(m[6]) * o.h.x + Math.abs(m[7]) * o.h.y + Math.abs(m[8]) * o.h.z;
      o.min = { x: o.c.x - ex, y: o.c.y - ey, z: o.c.z - ez };
      o.max = { x: o.c.x + ex, y: o.c.y + ey, z: o.c.z + ez };
    }
    if (o.max.x - o.min.x > 40 || o.max.z - o.min.z > 40) o.big = true;
    this.list.push(o);
    this.dirty = true;
    return o;
  };

  /* Düzgün ızgara (xz) geniş evre: büyük nesneler her zaman, küçükler yalnızca kendi hücrelerinde test edilir. */
  var CELL = 4;
  World.prototype._build = function () {
    this.grid = {}; this.bigs = [];
    for (var i = 0; i < this.list.length; i++) {
      var c = this.list[i];
      if (c.big) { this.bigs.push(c); continue; }
      var x0 = Math.floor(c.min.x / CELL), x1 = Math.floor(c.max.x / CELL), z0 = Math.floor(c.min.z / CELL), z1 = Math.floor(c.max.z / CELL);
      for (var gx = x0; gx <= x1; gx++) for (var gz = z0; gz <= z1; gz++) {
        var k = gx + ',' + gz; (this.grid[k] || (this.grid[k] = [])).push(c);
      }
    }
    this.dirty = false;
  };
  /* Stage 74: aday listesi her sorguda yeniden ayrılmaz (kare başına onlarca dizi → çöp toplama takılması).
     Sorgular iç içe çağrılmadığı için tek bir tampon yeterli. */
  World.prototype._cands = function (p, r) {
    if (this.dirty !== false) this._build();
    var out = this._out || (this._out = []), seen = this._seen = (this._seen || 0) + 1;
    out.length = 0;
    for (var b = 0; b < this.bigs.length; b++) out.push(this.bigs[b]);
    var x0 = Math.floor((p.x - r) / CELL), x1 = Math.floor((p.x + r) / CELL), z0 = Math.floor((p.z - r) / CELL), z1 = Math.floor((p.z + r) / CELL);
    for (var gx = x0; gx <= x1; gx++) for (var gz = z0; gz <= z1; gz++) {
      var a = this.grid[gx + ',' + gz]; if (!a) continue;
      for (var i = 0; i < a.length; i++) { var c = a[i]; if (c._s !== seen) { c._s = seen; out.push(c); } }
    }
    return out;
  };

  function obbContact(p, r, c) {
    var m = c.rot, dx = p.x - c.c.x, dy = p.y - c.c.y, dz = p.z - c.c.z;
    // dünya -> yerel (rot devrik)
    var lx = m[0] * dx + m[3] * dy + m[6] * dz, ly = m[1] * dx + m[4] * dy + m[7] * dz, lz = m[2] * dx + m[5] * dy + m[8] * dz;
    var h = c.h, b = { min: { x: -h.x, y: -h.y, z: -h.z }, max: { x: h.x, y: h.y, z: h.z } };
    var t = boxContact({ x: lx, y: ly, z: lz }, r, b);
    if (!t) return null;
    // yerel -> dünya
    var nx = m[0] * t.nx + m[1] * t.ny + m[2] * t.nz, ny = m[3] * t.nx + m[4] * t.ny + m[5] * t.nz, nz = m[6] * t.nx + m[7] * t.ny + m[8] * t.nz;
    var px = c.c.x + m[0] * t.px + m[1] * t.py + m[2] * t.pz, py = c.c.y + m[3] * t.px + m[4] * t.py + m[5] * t.pz, pz = c.c.z + m[6] * t.px + m[7] * t.py + m[8] * t.pz;
    return { nx: nx, ny: ny, nz: nz, depth: t.depth, px: px, py: py, pz: pz };
  }

  function segContact(p, r, c) {
    var a = c.a, b = c.b, abx = b.x - a.x, aby = b.y - a.y, abz = b.z - a.z;
    var l2 = abx * abx + aby * aby + abz * abz, t = l2 > 1e-12 ? ((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / l2 : 0;
    t = clamp(t, 0, 1);
    var qx = a.x + abx * t, qy = a.y + aby * t, qz = a.z + abz * t;
    var vx = p.x - qx, vy = p.y - qy, vz = p.z - qz, d = Math.sqrt(vx * vx + vy * vy + vz * vz), R = c.R + r;
    if (d >= R) return null;
    var nx, ny, nz;
    if (d > 1e-9) { nx = vx / d; ny = vy / d; nz = vz / d; } else { nx = 0; ny = 1; nz = 0; }
    return { nx: nx, ny: ny, nz: nz, depth: R - d, px: qx + nx * c.R, py: qy + ny * c.R, pz: qz + nz * c.R };
  }

  function ringContact(p, r, c) {
    if (p.y + r < c.y0 || p.y - r > c.y1) return null;
    var dx = p.x - c.x, dz = p.z - c.z, d = Math.sqrt(dx * dx + dz * dz), depth = d + r - c.R;
    if (depth <= 0) return null;
    var nx = -1, nz = 0; if (d > 1e-9) { nx = -dx / d; nz = -dz / d; }
    return { nx: nx, ny: 0, nz: nz, depth: depth, px: c.x - nx * 0 + (d > 1e-9 ? dx / d * c.R : c.R), py: p.y, pz: c.z + (d > 1e-9 ? dz / d * c.R : 0) };
  }

  function boxContact(p, r, b) {
    var cx = clamp(p.x, b.min.x, b.max.x), cy = clamp(p.y, b.min.y, b.max.y), cz = clamp(p.z, b.min.z, b.max.z);
    var dx = p.x - cx, dy = p.y - cy, dz = p.z - cz, d2 = dx * dx + dy * dy + dz * dz;
    if (d2 > r * r) return null;
    if (d2 > 1e-12) {
      var d = Math.sqrt(d2);
      return { nx: dx / d, ny: dy / d, nz: dz / d, depth: r - d, px: cx, py: cy, pz: cz };
    }
    // merkez kutunun içinde: en yakın yüzden dışarı
    var m = [
      [p.x - b.min.x, -1, 0, 0], [b.max.x - p.x, 1, 0, 0],
      [p.y - b.min.y, 0, -1, 0], [b.max.y - p.y, 0, 1, 0],
      [p.z - b.min.z, 0, 0, -1], [b.max.z - p.z, 0, 0, 1]
    ];
    var best = m[0];
    for (var i = 1; i < 6; i++) if (m[i][0] < best[0]) best = m[i];
    return { nx: best[1], ny: best[2], nz: best[3], depth: best[0] + r, px: p.x, py: p.y, pz: p.z };
  }

  function cylContact(p, r, c) {
    var dx = p.x - c.x, dz = p.z - c.z, d = Math.sqrt(dx * dx + dz * dz);
    var inSpan = p.y >= c.y0 && p.y <= c.y1;
    if (inSpan) {
      var nx = 1, nz = 0;
      if (d > 1e-9) { nx = dx / d; nz = dz / d; }
      var depth = c.R + r - d;
      if (depth <= 0) return null;
      return { nx: nx, ny: 0, nz: nz, depth: depth, px: c.x + nx * c.R, py: p.y, pz: c.z + nz * c.R };
    }
    var cy = clamp(p.y, c.y0, c.y1), cpx, cpz;
    if (d <= c.R) { cpx = p.x; cpz = p.z; }
    else { cpx = c.x + dx / d * c.R; cpz = c.z + dz / d * c.R; }
    var vx = p.x - cpx, vy = p.y - cy, vz = p.z - cpz, dist = Math.sqrt(vx * vx + vy * vy + vz * vz);
    if (dist > r) return null;
    if (dist < 1e-9) return { nx: 0, ny: p.y > c.y1 ? 1 : -1, nz: 0, depth: r, px: cpx, py: cy, pz: cpz };
    return { nx: vx / dist, ny: vy / dist, nz: vz / dist, depth: r - dist, px: cpx, py: cy, pz: cpz };
  }

  /* En derin teması döndürür. climbOnly: yalnızca tırmanılabilir nesneler. */
  World.prototype.query = function (p, r, climbOnly) {
    var best = null, L = this._cands(p, r);
    for (var i = 0; i < L.length; i++) {
      var c = L[i];
      if (climbOnly && !c.climb) continue;
      if (p.x + r < c.min.x || p.x - r > c.max.x || p.y + r < c.min.y || p.y - r > c.max.y || p.z + r < c.min.z || p.z - r > c.max.z) continue;
      var h = c.type === 'cyl' ? cylContact(p, r, c) : c.type === 'seg' ? segContact(p, r, c) : c.type === 'obb' ? obbContact(p, r, c) : c.type === 'ring' ? ringContact(p, r, c) : boxContact(p, r, c);
      if (h && (!best || h.depth > best.depth)) { best = h; best.collider = c; }
    }
    return best;
  };

  /* Küreyi nesnelerin dışına çıkarır (en çok 4 yineleme). */
  World.prototype.resolve = function (p, r) {
    var q = { x: p.x, y: p.y, z: p.z }, nx = 0, ny = 0, nz = 0, hit = false, col = null, depth = 0, ns = [];
    for (var i = 0; i < 4; i++) {
      var h = this.query(q, r, false);
      if (!h) break;
      q.x += h.nx * h.depth; q.y += h.ny * h.depth; q.z += h.nz * h.depth;
      ns.push({ x: h.nx, y: h.ny, z: h.nz });
      nx += h.nx; ny += h.ny; nz += h.nz; depth += h.depth;
      if (!hit) col = h.collider;
      hit = true;
    }
    var l = Math.sqrt(nx * nx + ny * ny + nz * nz);
    if (l > 1e-9) { nx /= l; ny /= l; nz /= l; }
    return { hit: hit, p: q, n: { x: nx, y: ny, z: nz }, ns: ns, collider: col, depth: depth };
  };

  /* Tutunulabilir yüzeye yakın mı? El merkezinin yüzeye değeceği konumu döndürür. */
  World.prototype.near = function (p, r, tol) {
    var h = this.query(p, r + tol, true);
    if (!h) return null;
    return { x: h.px + h.nx * r, y: h.py + h.ny * r, z: h.pz + h.nz * r, n: { x: h.nx, y: h.ny, z: h.nz }, collider: h.collider };
  };

  /* ---------- simülasyon ---------- */
  function mkHand() {
    return {
      valid: true, grip: false,
      L: { x: 0, y: -0.3, z: -0.35 }, prevL: { x: 0, y: -0.3, z: -0.35 }, inp: { x: 0, y: -0.3, z: -0.35 },
      skip: true, contact: false, anchor: null,
      pos: { x: 0, y: 0, z: 0 }, n: { x: 0, y: 1, z: 0 }, col: null
    };
  }

  function Sim(world, cfg) {
    this.cfg = Object.assign({}, CFG, cfg || {});
    this.world = world;
    this.spawn = { x: 0, y: 1.0, z: 0 };
    this.body = { x: 0, y: 1.0, z: 0 };
    this.vel = { x: 0, y: 0, z: 0 };
    this.yaw = 0;
    this.hands = [mkHand(), mkHand()];
    this.grounded = false;
    this.time = 0;
    this.lastContact = -9;
    this.jumpCd = 0;
    this.acc = 0;
    this.respawns = 0;
    this.lastStepCount = 0;
    this.reset();
  }

  Sim.prototype.reset = function () {
    var s = this.spawn;
    this.body.x = s.x; this.body.y = s.y; this.body.z = s.z;
    this.vel.x = this.vel.y = this.vel.z = 0;
    var self = this;
    this.hands.forEach(function (h) { h.anchor = null; h.contact = false; h.skip = true; h.grip = false; });
    this.acc = 0;
  };

  /* Bir el için girdi. valid=false: takip yok -> itiş/tutunma üretilmez, son konum korunur. */
  Sim.prototype.setHand = function (i, valid, x, y, z, grip) {
    var h = this.hands[i], C = this.cfg;
    if (!valid || !fin(x) || !fin(y) || !fin(z)) {
      h.valid = false; h.anchor = null; h.contact = false; h.grip = false;
      return;
    }
    var l = Math.sqrt(x * x + y * y + z * z);
    if (l > C.reach) { var k = C.reach / l; x *= k; y *= k; z *= k; }
    if (!h.valid) {
      // takip geri geldi: eli ışınlayarak yerleştir, bu karede itiş üretme
      h.valid = true; h.L.x = h.prevL.x = x; h.L.y = h.prevL.y = y; h.L.z = h.prevL.z = z; h.skip = true;
    } else {
      var jx = x - h.L.x, jy = y - h.L.y, jz = z - h.L.z;
      if (Math.sqrt(jx * jx + jy * jy + jz * jz) > C.maxHandJump) {
        h.L.x = h.prevL.x = x; h.L.y = h.prevL.y = y; h.L.z = h.prevL.z = z; h.skip = true;
      }
    }
    h.inp.x = x; h.inp.y = y; h.inp.z = z;
    h.grip = !!grip;
  };

  Sim.prototype.jump = function () {
    if (this.jumpCd > 0) return false;
    if (this.time - this.lastContact > this.cfg.jumpWindow) return false;
    this.vel.y = Math.max(this.vel.y, this.cfg.jump);
    this.jumpCd = this.cfg.jumpCooldown;
    this.lastContact = -9;
    return true;
  };

  Sim.prototype.step = function (dt) {
    var C = this.cfg;
    if (!fin(dt) || dt <= 0) return;
    this.acc += Math.min(dt, C.maxSteps * C.step);
    var n = Math.min(C.maxSteps, Math.floor(this.acc / C.step + 1e-6));
    if (n < 1) return;
    this.acc -= n * C.step;
    if (this.acc > C.step) this.acc = 0;
    this.lastStepCount = n;

    // el girdisini süz ve bu karenin adımlarına bölünecek farkı hazırla
    var a = 1 - clamp(C.inputSmooth, 0, 0.95);
    var hs = this.hands;
    for (var i = 0; i < 2; i++) {
      var h = hs[i];
      if (!h.valid) continue;
      h.prevL.x = h.L.x; h.prevL.y = h.L.y; h.prevL.z = h.L.z;
      h.L.x += (h.inp.x - h.L.x) * a; h.L.y += (h.inp.y - h.L.y) * a; h.L.z += (h.inp.z - h.L.z) * a;
      if (h.skip) { h.prevL.x = h.L.x; h.prevL.y = h.L.y; h.prevL.z = h.L.z; }
    }
    for (var k = 0; k < n; k++) this._sub(C.step, k + 1, n);
    for (i = 0; i < 2; i++) hs[i].skip = false;
    this.time += n * C.step;
    if (this.jumpCd > 0) this.jumpCd = Math.max(0, this.jumpCd - n * C.step);

    var b = this.body, v = this.vel;
    if (!fin(b.x + b.y + b.z + v.x + v.y + v.z) || b.y < C.killY) { this.respawns++; this.reset(); }
  };

  Sim.prototype._sub = function (h, k, n) {
    var C = this.cfg, b = this.body, v = this.vel, W = this.world, hs = this.hands;
    var gripping = hs[0].anchor || hs[1].anchor;
    if (!gripping) v.y -= C.gravity * h;
    var dk = 1 - C.airDrag * h; v.x *= dk; v.y *= dk; v.z *= dk;
    b.x += v.x * h; b.y += v.y * h; b.z += v.z * h;
    this._bodyCollide();

    var cy = Math.cos(this.yaw), sy = Math.sin(this.yaw);
    var sc = this._sc || (this._sc = { Lk: { x: 0, y: 0, z: 0 }, dl: { x: 0, y: 0, z: 0 }, off: { x: 0, y: 0, z: 0 }, Wd: { x: 0, y: 0, z: 0 } });
    var rot = function (x, y, z, o) { o.x = x * cy + z * sy; o.y = y; o.z = -x * sy + z * cy; return o; };

    var pushX = 0, pushY = 0, pushZ = 0, nx = 0, ny = 0, nz = 0, cN = 0, gripN = 0, gx = 0, gy = 0, gz = 0;
    for (var i = 0; i < 2; i++) {
      var H = hs[i];
      if (!H.valid) { H.contact = false; H.anchor = null; continue; }
      var t1 = k / n, Lk = sc.Lk;
      Lk.x = H.prevL.x + (H.L.x - H.prevL.x) * t1;
      Lk.y = H.prevL.y + (H.L.y - H.prevL.y) * t1;
      Lk.z = H.prevL.z + (H.L.z - H.prevL.z) * t1;
      var dl = rot((H.L.x - H.prevL.x) / n, (H.L.y - H.prevL.y) / n, (H.L.z - H.prevL.z) / n, sc.dl);
      var off = rot(Lk.x, Lk.y, Lk.z, sc.off);
      var Wd = sc.Wd; Wd.x = b.x + off.x; Wd.y = b.y + off.y; Wd.z = b.z + off.z;
      var wasContact = H.contact;

      if (!H.grip) H.anchor = null;
      if (H.grip && !H.anchor) {
        var nr = W.near(Wd, C.handR, C.gripTol);
        if (nr) H.anchor = nr;
      }
      if (H.anchor) {
        var sx = H.anchor.x - Wd.x, sy2 = H.anchor.y - Wd.y, sz = H.anchor.z - Wd.z;
        var dist = Math.sqrt((Wd.x - b.x) * (Wd.x - b.x) + (Wd.y - b.y) * (Wd.y - b.y) + (Wd.z - b.z) * (Wd.z - b.z));
        var sl = Math.sqrt(sx * sx + sy2 * sy2 + sz * sz);
        if (sl > C.gripBreak) { H.anchor = null; H.contact = false; continue; }
        if (sl > C.maxShift) { var q = C.maxShift / sl; sx *= q; sy2 *= q; sz *= q; }
        b.x += sx; b.y += sy2; b.z += sz;
        gx += sx; gy += sy2; gz += sz; gripN++;
        H.contact = true; H.pos.x = H.anchor.x; H.pos.y = H.anchor.y; H.pos.z = H.anchor.z;
        H.n = H.anchor.n; H.col = H.anchor.collider;
        continue;
      }

      var res = W.resolve(Wd, C.handR);
      if (res.hit) {
        var corr = { x: res.p.x - Wd.x, y: res.p.y - Wd.y, z: res.p.z - Wd.z };
        var nn = res.n, push = { x: 0, y: 0, z: 0 };
        if (!H.skip) {
          // elin gövdeye göre hareketinin tersi; yüzeye doğru olmayan normal bileşen atılır
          push.x = -dl.x * C.friction * C.push; push.y = -dl.y * C.friction * C.push; push.z = -dl.z * C.friction * C.push;
          var pn = push.x * nn.x + push.y * nn.y + push.z * nn.z;
          if (pn < 0) { push.x -= pn * nn.x; push.y -= pn * nn.y; push.z -= pn * nn.z; }
        }
        var sh = { x: corr.x + push.x, y: corr.y + push.y, z: corr.z + push.z };
        var sl2 = Math.sqrt(sh.x * sh.x + sh.y * sh.y + sh.z * sh.z);
        if (sl2 > C.maxShift) { var q2 = C.maxShift / sl2; sh.x *= q2; sh.y *= q2; sh.z *= q2; }
        b.x += sh.x; b.y += sh.y; b.z += sh.z;
        pushX += push.x / h; pushY += push.y / h; pushZ += push.z / h;
        nx += nn.x; ny += nn.y; nz += nn.z; cN++;
        H.contact = true; H.pos.x = res.p.x; H.pos.y = res.p.y; H.pos.z = res.p.z; H.n = nn; H.col = res.collider;
        if (!wasContact && !H.skip) { H.touches = (H.touches || 0) + 1; H.touchV = Math.sqrt(dl.x * dl.x + dl.y * dl.y + dl.z * dl.z) / h; H.touchMat = res.collider && res.collider.mat; }
      } else {
        H.contact = false; H.pos.x = Wd.x; H.pos.y = Wd.y; H.pos.z = Wd.z;
      }
    }

    if (gripN > 0) {
      // tutunma: hız, elin sabit kalmasını sağlayan gövde hareketinden gelir
      var s = C.velSmooth;
      v.x += (gx / h / gripN - v.x) * s; v.y += (gy / h / gripN - v.y) * s; v.z += (gz / h / gripN - v.z) * s;
      this.lastContact = this.time;
    } else if (cN > 0) {
      var nl = Math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nl > 1e-9) { nx /= nl; ny /= nl; nz /= nl; } else { nx = 0; ny = 1; nz = 0; }
      pushX /= cN; pushY /= cN; pushZ /= cN;
      var pm = Math.sqrt(pushX * pushX + pushY * pushY + pushZ * pushZ);
      if (pm > C.maxPushVel) { var q3 = C.maxPushVel / pm; pushX *= q3; pushY *= q3; pushZ *= q3; }
      var vn = v.x * nx + v.y * ny + v.z * nz;
      var tx = v.x - vn * nx, ty = v.y - vn * ny, tz = v.z - vn * nz;
      var pnn = pushX * nx + pushY * ny + pushZ * nz;
      var ptx = pushX - pnn * nx, pty = pushY - pnn * ny, ptz = pushZ - pnn * nz;
      var sm = C.velSmooth, ptm = Math.sqrt(ptx * ptx + pty * pty + ptz * ptz);
      // zemin benzeri yüzeyde sürtünme gövdeyi durdurur; duvarda yalnızca el aktif hareket ediyorsa
      if (ny > 0.5 || ptm > 0.2) {
        tx += (ptx - tx) * sm; ty += (pty - ty) * sm; tz += (ptz - tz) * sm;
      }
      var vn2 = Math.max(0, vn, pnn);
      v.x = tx + vn2 * nx; v.y = ty + vn2 * ny; v.z = tz + vn2 * nz;
      this.lastContact = this.time;
    }
    this._bodyCollide();

    var hh = Math.sqrt(v.x * v.x + v.z * v.z);
    if (hh > C.maxH) { var q4 = C.maxH / hh; v.x *= q4; v.z *= q4; }
    v.y = clamp(v.y, -C.maxDown, C.maxUp);
  };

  Sim.prototype._bodyCollide = function () {
    var b = this.body, v = this.vel, r = this.world.resolve(b, this.cfg.bodyR);
    this.grounded = false;
    if (!r.hit) return;
    b.x = r.p.x; b.y = r.p.y; b.z = r.p.z;
    for (var i = 0; i < r.ns.length; i++) {
      var n = r.ns[i], vn = v.x * n.x + v.y * n.y + v.z * n.z;
      if (vn < 0) { v.x -= vn * n.x; v.y -= vn * n.y; v.z -= vn * n.z; }
      if (n.y > 0.6) { this.grounded = true; this.lastContact = this.time; }
    }
  };

  /* ---------- test haritası (görsel ve çarpışma aynı veriden) ---------- */
  function testMap() {
    function box(x0, y0, z0, x1, y1, z1, o) {
      return Object.assign({ type: 'box', min: { x: x0, y: y0, z: z0 }, max: { x: x1, y: y1, z: z1 } }, o || {});
    }
    return {
      spawn: { x: 0, y: 1.0, z: 0 },
      colliders: [
        box(-80, -10, -80, 80, 0, 80, { mat: 'grass', ground: true }),
        box(-2, 0, -10, 2, 0.8, -8, { mat: 'wood' }),
        box(-2, 0, -13, 2, 1.6, -11, { mat: 'wood' }),
        box(-2, 0, -16, 2, 2.4, -14, { mat: 'wood' }),
        box(-6.5, 0, -4, -4.8, 1.2, -2.6, { mat: 'rock', climb: true }),
        box(-3, 0, 6, 6, 2.5, 6.4, { mat: 'rock' }),
        { type: 'cyl', x: 5, z: -8, R: 0.45, y0: 0, y1: 7, mat: 'trunk', climb: true },
        box(5.2, 5.9, -8.25, 8.4, 6.2, -7.75, { mat: 'trunk', climb: true }),
        box(8, 5.8, -9.5, 11, 6.2, -6.5, { mat: 'wood' })
      ]
    };
  }


  /* ---------- Orman kanyonu haritası (özgün tasarım; görsel ve çarpışma aynı veriden) ---------- */
  function mulberry(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0; var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function v3n(x, y, z) { var l = Math.sqrt(x * x + y * y + z * z) || 1; return [x / l, y / l, z / l]; }
  /* a -> b boyunca uzanan eğimli tahta (obb). genişlik w, kalınlık t; üst yüzey a-b doğrusunun t/2 altındadır. */
  function plankObb(a, b, w, t, o) {
    var f = v3n(b.x - a.x, b.y - a.y, b.z - a.z), len = Math.sqrt(Math.pow(b.x - a.x, 2) + Math.pow(b.y - a.y, 2) + Math.pow(b.z - a.z, 2));
    var right = v3n(f[1] * 0 - f[2] * 1, f[2] * 0 - f[0] * 0, f[0] * 1 - f[1] * 0); // cross(f, up)
    var up = [right[1] * f[2] - right[2] * f[1], right[2] * f[0] - right[0] * f[2], right[0] * f[1] - right[1] * f[0]];
    var rot = [right[0], up[0], f[0], right[1], up[1], f[1], right[2], up[2], f[2]];
    return Object.assign({
      type: 'obb', rot: rot, h: { x: w / 2, y: t / 2, z: len / 2 },
      c: { x: (a.x + b.x) / 2 - up[0] * t / 2, y: (a.y + b.y) / 2 - up[1] * t / 2, z: (a.z + b.z) / 2 - up[2] * t / 2 }
    }, o || {});
  }
  function bx(x0, y0, z0, x1, y1, z1, o) {
    return Object.assign({ type: 'box', min: { x: x0, y: y0, z: z0 }, max: { x: x1, y: y1, z: z1 } }, o || {});
  }

  function forestMap(seed) {
    var R = mulberry(seed || 1717), PI = Math.PI, cols = [], leaves = [], npcs = [], trees = [];
    var CAN = 33;
    cols.push(bx(-90, -10, -90, 90, 0, 90, { mat: 'grass', ground: true }));
    cols.push({ type: 'ring', x: 0, z: 0, R: CAN - 0.6, y0: -10, y1: 80, mat: 'rock' });

    // şenlik ateşi: taş halka
    for (var i = 0; i < 8; i++) {
      var a = i / 8 * 2 * PI, sx = Math.cos(a) * 0.95, sz = Math.sin(a) * 0.95;
      cols.push(bx(sx - 0.22, 0, sz - 0.2, sx + 0.22, 0.32, sz + 0.2, { mat: 'rock' }));
    }
    // ateşin etrafındaki oturan goriller (yalnızca süs, hafif çarpışma)
    var furs = [0xf06aa8, 0x2cc0f0, 0x3a46e8, 0xe83a26, 0xb44ed8], hats = ['muff', 'party', 'tophat', 'bucket', 'pie'];
    [150, 195, 235, 285, 330].forEach(function (deg, k) {
      var an = deg * PI / 180, nx = Math.cos(an) * 2.5, nz = Math.sin(an) * 2.5;
      npcs.push({ x: nx, z: nz, yaw: Math.atan2(nx, nz), fur: furs[k], hat: hats[k] });
      cols.push({ type: 'cyl', x: nx, z: nz, R: 0.34, y0: 0, y1: 1.2, mat: 'fur' });
    });

    // ağaçlar
    var N = 16, placed = [];
    for (i = 0; i < N; i++) {
      var ang = i / N * 2 * PI + (R() - 0.5) * 0.35, rad = 11 + R() * 16;
      var tx = Math.cos(ang) * rad, tz = Math.sin(ang) * rad;
      if (Math.hypot(tx - 0, tz - 9.5) < 5) { tx += 6; }
      var h = 11 + R() * 6.5, r = 0.38 + R() * 0.17;
      placed.push({ x: tx, z: tz, h: h, r: r, ang: Math.atan2(tz, tx) });
      cols.push({ type: 'cyl', x: tx, z: tz, R: r, y0: 0, y1: h, mat: 'trunk', climb: true, taper: [1.12, 0.7] });
      var nb = 4 + Math.floor(R() * 3);
      for (var b = 0; b < nb; b++) {
        var by = h * (0.42 + 0.5 * (b + R() * 0.6) / nb), ba = R() * 2 * PI, bl = 2.3 + R() * 2.4, up = 0.4 + R() * 1.1;
        var ex = tx + Math.cos(ba) * bl, ez = tz + Math.sin(ba) * bl, ey = by + up;
        cols.push({ type: 'seg', a: { x: tx, y: by, z: tz }, b: { x: ex, y: ey, z: ez }, R: 0.085 + R() * 0.03, mat: 'trunk', climb: true });
        for (var q = 0; q < 3; q++) {
          var f = 0.45 + q * 0.28;
          leaves.push([tx + (ex - tx) * f, by + (ey - by) * f + 0.25, tz + (ez - tz) * f, 1.3 + R() * 1.0]);
        }
      }
      for (q = 0; q < 3; q++) leaves.push([tx + (R() - 0.5) * 1.4, h - 0.6 + q * 0.9, tz + (R() - 0.5) * 1.4, 1.7 + R() * 0.9]);
      trees.push(placed[placed.length - 1]);
    }

    // tahta platformlar (her ikinci ağacın çevresinde) ve aralarında eğimli köprüler
    var order = placed.filter(function (_, k) { return k % 2 === 0; }), plats = [], hgt = 4.2;
    order.forEach(function (t, k) {
      hgt = Math.max(3.2, Math.min(6.5, hgt + (R() - 0.5) * 2.2));
      var cx = t.x * 0.86, cz = t.z * 0.86, hs = 1.8;
      plats.push({ x: cx, z: cz, y: hgt, hs: hs });
      cols.push(bx(cx - hs, hgt - 0.25, cz - hs, cx + hs, hgt, cz + hs, { mat: 'wood' }));
    });
    for (i = 0; i < plats.length; i++) {
      var A = plats[i], B = plats[(i + 1) % plats.length], dx = B.x - A.x, dz = B.z - A.z, dl = Math.hypot(dx, dz), ux = dx / dl, uz = dz / dl;
      var te = A.hs * 0.98 / Math.max(Math.abs(ux), Math.abs(uz));
      var pa = { x: A.x + ux * te, y: A.y, z: A.z + uz * te };
      var pb = { x: B.x - ux * te, y: B.y, z: B.z - uz * te };
      cols.push(plankObb(pa, pb, 1.5, 0.16, { mat: 'wood' }));
    }
    // yerden platformlara rampalar
    [0, Math.floor(plats.length / 2)].forEach(function (k) {
      var P = plats[k], d = Math.hypot(P.x, P.z), ox = P.x / d, oz = P.z / d, e2 = P.hs * 0.98 / Math.max(Math.abs(ox), Math.abs(oz));
      var top = { x: P.x - ox * e2, y: P.y, z: P.z - oz * e2 };
      var len = P.y / 0.36, bot = { x: top.x - ox * len, y: 0.02, z: top.z - oz * len };
      cols.push(plankObb(bot, top, 1.9, 0.16, { mat: 'wood' }));
    });

    // ağaç evi (direkler üzerinde) + uzun rampa
    var hx = -15, hz = 8, hy = 5.4;
    [[-2, -2], [2, -2], [-2, 2], [2, 2]].forEach(function (o) {
      cols.push({ type: 'cyl', x: hx + o[0], z: hz + o[1], R: 0.2, y0: 0, y1: hy, mat: 'trunk', climb: true });
    });
    cols.push(bx(hx - 2.4, hy - 0.25, hz - 2.4, hx + 2.4, hy, hz + 2.4, { mat: 'wood' }));
    cols.push(bx(hx - 2.4, hy, hz - 2.4, hx + 2.4, hy + 2.1, hz - 2.2, { mat: 'wood' }));
    cols.push(bx(hx - 2.4, hy, hz - 2.4, hx - 2.2, hy + 2.1, hz + 2.4, { mat: 'wood' }));
    cols.push(bx(hx + 2.2, hy, hz - 2.4, hx + 2.4, hy + 2.1, hz + 2.4, { mat: 'wood' }));
    cols.push(plankObb({ x: hx - 2.5, y: hy + 2.1, z: hz }, { x: hx, y: hy + 3.4, z: hz }, 5.2, 0.15, { mat: 'wood' }));
    cols.push(plankObb({ x: hx + 2.5, y: hy + 2.1, z: hz }, { x: hx, y: hy + 3.4, z: hz }, 5.2, 0.15, { mat: 'wood' }));
    cols.push(plankObb({ x: hx + 8.8, y: 0.02, z: hz }, { x: hx + 2.4, y: hy, z: hz }, 1.9, 0.16, { mat: 'wood' }));

    // yerde kiremit çatılı kulübe: beyaz direkler
    var kx = 10, kz = 7;
    cols.push(bx(kx - 1.9, 0, kz - 1.9, kx + 1.9, 0.18, kz + 1.9, { mat: 'white' }));
    [[-1.6, -1.6], [1.6, -1.6], [-1.6, 1.6], [1.6, 1.6]].forEach(function (o) {
      cols.push({ type: 'cyl', x: kx + o[0], z: kz + o[1], R: 0.12, y0: 0.18, y1: 2.5, mat: 'white' });
    });
    cols.push(plankObb({ x: kx, y: 3.5, z: kz }, { x: kx, y: 2.45, z: kz - 2.3 }, 4.3, 0.12, { mat: 'shingle' }));
    cols.push(plankObb({ x: kx, y: 3.5, z: kz }, { x: kx, y: 2.45, z: kz + 2.3 }, 4.3, 0.12, { mat: 'shingle' }));

    // kaya bloklar (kanyon kenarında)
    for (i = 0; i < 8; i++) {
      var ra = R() * 2 * PI, rr = 22 + R() * 8, rw = 1.4 + R() * 1.8, rh = 0.8 + R() * 1.6, rd = 1.2 + R() * 1.6;
      var rx = Math.cos(ra) * rr, rz = Math.sin(ra) * rr;
      cols.push(bx(rx - rw / 2, 0, rz - rd / 2, rx + rw / 2, rh, rz + rd / 2, { mat: 'rock', climb: true }));
    }

    return {
      spawn: { x: 0, y: 1.0, z: 9.5 }, colliders: cols, leaves: leaves, npcs: npcs, trees: trees,
      fire: { x: 0, z: 0 }, canyon: CAN, platforms: plats, hut: { x: kx, z: kz }, house: { x: hx, z: hz, y: hy }
    };
  }

  var API = { CFG: CFG, World: World, Sim: Sim, testMap: testMap, forestMap: forestMap };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  root.GorillaPhys = API;
})(typeof window !== 'undefined' ? window : globalThis);
