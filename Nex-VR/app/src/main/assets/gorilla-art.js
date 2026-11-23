/* NEXUS VR: GORILLA RUN - görsel katman (özgün low-poly orman kanyonu, gorilla modeli, el modeli).
   Tüm dokular canvas ile üretilir (dış görsel dosyası yok). Geometri saf JS ile üretilip tek tek birleştirilir:
   tüm tahta/kaya/gövde yüzeyleri malzeme başına TEK çizim çağrısıdır (mobil GPU için). Saf geometri kısmı node'da test edilir. */
(function (root) {
  'use strict';
  var PI = Math.PI;

  /* ---------- tohumlu rastgele ---------- */
  function rng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0; var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  /* ---------- 3x3 matris yardımcıları (satır sıralı, sütunlar yerel eksenler) ---------- */
  var I3 = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  function mul3(A, B) {
    var o = new Array(9);
    for (var r = 0; r < 3; r++) for (var c = 0; c < 3; c++) o[r * 3 + c] = A[r * 3] * B[c] + A[r * 3 + 1] * B[3 + c] + A[r * 3 + 2] * B[6 + c];
    return o;
  }
  function rotY(a) { var c = Math.cos(a), s = Math.sin(a); return [c, 0, s, 0, 1, 0, -s, 0, c]; }       // sim ile aynı: x'=x c+z s ; z'=-x s+z c
  function rotX(a) { var c = Math.cos(a), s = Math.sin(a); return [1, 0, 0, 0, c, -s, 0, s, c]; }
  function rotZ(a) { var c = Math.cos(a), s = Math.sin(a); return [c, -s, 0, s, c, 0, 0, 0, 1]; }
  function apply3(M, v) { return [M[0] * v[0] + M[1] * v[1] + M[2] * v[2], M[3] * v[0] + M[4] * v[1] + M[5] * v[2], M[6] * v[0] + M[7] * v[1] + M[8] * v[2]]; }
  function norm(v) { var l = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  /* +Y eksenini dir yönüne çeviren dönüş */
  function rotFromY(dir) {
    var y = norm(dir), ref = Math.abs(y[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
    var x = norm(cross(y, ref)), z = cross(x, y);
    return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
  }
  function basis(x, y, z) { return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]]; }

  /* ---------- ilkel şekiller: üçgen listesi {pos, uv}, merkez orijinde ---------- */
  function boxP(w, h, d, tile) {
    var x = w / 2, y = h / 2, z = d / 2, T = tile || 2, pos = [], uv = [];
    function quad(a, b, c, d2, ua, ub, uc, ud) {
      pos.push.apply(pos, a.concat(b, c, a, c, d2)); uv.push.apply(uv, ua.concat(ub, uc, ua, uc, ud));
    }
    // +X, -X (u=z, v=y), +Y, -Y (u=x, v=z), +Z, -Z (u=x, v=y)
    quad([x, -y, z], [x, -y, -z], [x, y, -z], [x, y, z], [z / T, -y / T], [-z / T, -y / T], [-z / T, y / T], [z / T, y / T]);
    quad([-x, -y, -z], [-x, -y, z], [-x, y, z], [-x, y, -z], [-z / T, -y / T], [z / T, -y / T], [z / T, y / T], [-z / T, y / T]);
    quad([-x, y, z], [x, y, z], [x, y, -z], [-x, y, -z], [-x / T, z / T], [x / T, z / T], [x / T, -z / T], [-x / T, -z / T]);
    quad([-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z], [-x / T, -z / T], [x / T, -z / T], [x / T, z / T], [-x / T, z / T]);
    quad([-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z], [-x / T, -y / T], [x / T, -y / T], [x / T, y / T], [-x / T, y / T]);
    quad([x, -y, -z], [-x, -y, -z], [-x, y, -z], [x, y, -z], [x / T, -y / T], [-x / T, -y / T], [-x / T, y / T], [x / T, y / T]);
    return { pos: pos, uv: uv };
  }
  function cylP(r0, r1, h, seg, tile, caps) {
    var pos = [], uv = [], T = tile || 2, y0 = -h / 2, y1 = h / 2;
    for (var i = 0; i < seg; i++) {
      var a0 = i / seg * 2 * PI, a1 = (i + 1) / seg * 2 * PI, c0 = Math.cos(a0), s0 = Math.sin(a0), c1 = Math.cos(a1), s1 = Math.sin(a1);
      var A = [c0 * r0, y0, s0 * r0], B = [c1 * r0, y0, s1 * r0], C = [c1 * r1, y1, s1 * r1], D = [c0 * r1, y1, s0 * r1];
      var u0 = a0 * r0 / T, u1 = a1 * r0 / T, v1 = h / T;
      pos.push.apply(pos, A.concat(B, C, A, C, D)); uv.push(u0, 0, u1, 0, u1, v1, u0, 0, u1, v1, u0, v1);
      if (caps !== false) {
        if (r1 > 1e-4) { pos.push(0, y1, 0, c0 * r1, y1, s0 * r1, c1 * r1, y1, s1 * r1); uv.push(0, 0, c0 * r1 / T, s0 * r1 / T, c1 * r1 / T, s1 * r1 / T); }
        if (r0 > 1e-4) { pos.push(0, y0, 0, c1 * r0, y0, s1 * r0, c0 * r0, y0, s0 * r0); uv.push(0, 0, c1 * r0 / T, s1 * r0 / T, c0 * r0 / T, s0 * r0 / T); }
      }
    }
    return { pos: pos, uv: uv };
  }
  function sphP(r, ws, hs) {
    var pos = [], uv = [];
    function P(i, j) { var th = j / hs * PI, ph = i / ws * 2 * PI; return [r * Math.sin(th) * Math.cos(ph), r * Math.cos(th), r * Math.sin(th) * Math.sin(ph)]; }
    for (var j = 0; j < hs; j++) for (var i = 0; i < ws; i++) {
      var a = P(i, j), b = P(i + 1, j), c = P(i + 1, j + 1), d = P(i, j + 1);
      var ua = [i / ws, j / hs], ub = [(i + 1) / ws, j / hs], uc = [(i + 1) / ws, (j + 1) / hs], ud = [i / ws, (j + 1) / hs];
      if (j > 0) { pos.push.apply(pos, a.concat(b, d)); uv.push.apply(uv, ua.concat(ub, ud)); }
      if (j < hs - 1) { pos.push.apply(pos, b.concat(c, d)); uv.push.apply(uv, ub.concat(uc, ud)); }
    }
    return { pos: pos, uv: uv };
  }
  function quadP(w, h) {
    var x = w / 2, y = h / 2;
    return { pos: [-x, -y, 0, x, -y, 0, x, y, 0, -x, -y, 0, x, y, 0, -x, y, 0], uv: [0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1] };
  }

  /* ---------- Batch: dönüştür + renk + düz (facet) normal; dışbükey şekillerde dışa bakacak biçimde sarım düzeltilir ---------- */
  function Batch() { this.pos = []; this.nrm = []; this.uv = []; this.col = []; }
  /* o: {s:[sx,sy,sz], r:3x3, t:[x,y,z], c:[r,g,b], flip:false => sarımı elleme, up:true => normal +Y} */
  Batch.prototype.add = function (prim, o) {
    o = o || {};
    var S = o.s || [1, 1, 1], R = o.r || I3, t = o.t || [0, 0, 0], c = o.c || [1, 1, 1], p = prim.pos, uv = prim.uv, n = p.length / 9;
    for (var k = 0; k < n; k++) {
      var V = [];
      for (var q = 0; q < 3; q++) { var i = k * 9 + q * 3, w = apply3(R, [p[i] * S[0], p[i + 1] * S[1], p[i + 2] * S[2]]); V.push([w[0] + t[0], w[1] + t[1], w[2] + t[2]]); }
      var e1 = [V[1][0] - V[0][0], V[1][1] - V[0][1], V[1][2] - V[0][2]], e2 = [V[2][0] - V[0][0], V[2][1] - V[0][1], V[2][2] - V[0][2]], N = cross(e1, e2);
      var nl = Math.sqrt(N[0] * N[0] + N[1] * N[1] + N[2] * N[2]);
      if (nl < 1e-12) continue;                                   // dejenere üçgen (kutup)
      N = [N[0] / nl, N[1] / nl, N[2] / nl];
      var order = [0, 1, 2];
      if (o.up) { if (N[1] < 0) { order = [0, 2, 1]; N = [-N[0], -N[1], -N[2]]; } }
      else if (o.flip !== false) {
        var cx = (V[0][0] + V[1][0] + V[2][0]) / 3 - t[0], cy = (V[0][1] + V[1][1] + V[2][1]) / 3 - t[1], cz = (V[0][2] + V[1][2] + V[2][2]) / 3 - t[2];
        if (N[0] * cx + N[1] * cy + N[2] * cz < 0) { order = [0, 2, 1]; N = [-N[0], -N[1], -N[2]]; }
      }
      for (q = 0; q < 3; q++) {
        var vi = order[q];
        this.pos.push(V[vi][0], V[vi][1], V[vi][2]); this.nrm.push(N[0], N[1], N[2]);
        this.uv.push(uv[k * 6 + vi * 2], uv[k * 6 + vi * 2 + 1]); this.col.push(c[0], c[1], c[2]);
      }
    }
    return this;
  };
  Batch.prototype.tris = function () { return this.pos.length / 9; };
  Batch.prototype.geometry = function (T) {
    var g = new T.BufferGeometry();
    g.setAttribute('position', new T.BufferAttribute(new Float32Array(this.pos), 3));
    g.setAttribute('normal', new T.BufferAttribute(new Float32Array(this.nrm), 3));
    g.setAttribute('uv', new T.BufferAttribute(new Float32Array(this.uv), 2));
    g.setAttribute('color', new T.BufferAttribute(new Float32Array(this.col), 3));
    g.computeBoundingSphere();
    return g;
  };

  /* ---------- dokular (canvas; node'da çağrılmaz) ---------- */
  function mk(s) { var c = document.createElement('canvas'); c.width = c.height = s; return c; }
  function rgb(r, g, b) { return 'rgb(' + (r | 0) + ',' + (g | 0) + ',' + (b | 0) + ')'; }
  var TEX = {
    bark: function (s, R) {
      var c = mk(s), x = c.getContext('2d'); x.fillStyle = '#5a3f27'; x.fillRect(0, 0, s, s);
      for (var i = 0; i < s * 1.4; i++) { var k = 30 + R() * 70, w = 1 + R() * s / 22, h = s * (0.25 + R() * 0.75), px = R() * s, py = R() * s; x.fillStyle = rgb(k + 38, k + 18, k - 6); x.fillRect(px, py, w, h); if (py + h > s) x.fillRect(px, py - s, w, h); }
      for (i = 0; i < s * 0.6; i++) { x.fillStyle = 'rgba(25,15,8,' + (0.25 + R() * 0.3) + ')'; x.fillRect(R() * s, R() * s, 1 + R() * 2, s * (0.1 + R() * 0.5)); }
      return c;
    },
    rock: function (s, R) {
      var c = mk(s), x = c.getContext('2d'), pal = ['#7a6b7e', '#5f5266', '#8d7f88', '#4f4555', '#74665a', '#6a5a70'];
      x.fillStyle = '#625669'; x.fillRect(0, 0, s, s);
      for (var i = 0; i < s / 2.5; i++) {
        var cx = R() * s, cy = R() * s, rx = s * (0.05 + R() * 0.12), ry = rx * (0.6 + R() * 0.7);
        for (var dx = -1; dx <= 1; dx++) for (var dy = -1; dy <= 1; dy++) {
          x.beginPath(); x.ellipse(cx + dx * s, cy + dy * s, rx, ry, R() * PI, 0, 2 * PI); x.fillStyle = pal[(R() * pal.length) | 0]; x.fill();
          x.lineWidth = Math.max(1, s / 90); x.strokeStyle = 'rgba(20,12,28,.55)'; x.stroke();
        }
      }
      return c;
    },
    wood: function (s, R) {
      var c = mk(s), x = c.getContext('2d'), n = 4, ph = s / n;
      for (var i = 0; i < n; i++) {
        var k = R() * 28; x.fillStyle = rgb(196 + k, 112 + k * 0.7, 80 + k * 0.5); x.fillRect(0, i * ph, s, ph);
        for (var g = 0; g < 14; g++) { x.fillStyle = 'rgba(90,40,22,' + (0.12 + R() * 0.2) + ')'; x.fillRect(R() * s, i * ph + R() * ph, s * (0.15 + R() * 0.5), Math.max(1, s / 128)); }
        x.fillStyle = 'rgba(50,22,12,.8)'; x.fillRect(0, i * ph, s, Math.max(1.5, s / 64));
        x.fillStyle = 'rgba(50,22,12,.5)'; x.fillRect(R() * s, i * ph, Math.max(1.5, s / 70), ph);
      }
      return c;
    },
    ground: function (s, R) {
      var c = mk(s), x = c.getContext('2d'); x.fillStyle = '#5d7d38'; x.fillRect(0, 0, s, s);
      for (var i = 0; i < s * 3; i++) { x.fillStyle = rgb(60 + R() * 50, 100 + R() * 60, 30 + R() * 30); x.fillRect(R() * s, R() * s, 1 + R() * 3, 1 + R() * 3); }
      for (i = 0; i < s / 4; i++) { var g = 110 + R() * 70; x.fillStyle = rgb(g, g - 6, g - 14); x.beginPath(); x.ellipse(R() * s, R() * s, 1.5 + R() * s / 40, 1 + R() * s / 55, R() * PI, 0, 2 * PI); x.fill(); }
      for (i = 0; i < 5; i++) { var gx = R() * s, gy = R() * s, gr = s * (0.12 + R() * 0.18), gr2 = x.createRadialGradient(gx, gy, 0, gx, gy, gr); gr2.addColorStop(0, 'rgba(8,20,6,.45)'); gr2.addColorStop(1, 'rgba(8,20,6,0)'); x.fillStyle = gr2; x.fillRect(gx - gr, gy - gr, gr * 2, gr * 2); }
      return c;
    },
    shingle: function (s, R) {
      var c = mk(s), x = c.getContext('2d'), n = 8, h = s / n; x.fillStyle = '#6f6a76'; x.fillRect(0, 0, s, s);
      for (var r = 0; r < n; r++) for (var q = -1; q < n; q++) {
        var cx = (q + (r % 2) * 0.5) * h + h / 2, k = 120 + R() * 40; x.beginPath(); x.arc(cx, r * h, h * 0.62, 0, PI); x.fillStyle = rgb(k, k - 6, k + 6); x.fill(); x.strokeStyle = 'rgba(20,16,26,.7)'; x.lineWidth = Math.max(1, s / 100); x.stroke();
      }
      return c;
    },
    fur: function (s, R) {
      var c = mk(s), x = c.getContext('2d'); x.fillStyle = '#c8c8c8'; x.fillRect(0, 0, s, s);
      for (var i = 0; i < s * 4; i++) { var k = 150 + R() * 105; x.fillStyle = rgb(k, k, k); x.fillRect(R() * s, R() * s, 1, 1 + R() * 3); }
      return c;
    },
    white: function (s, R) { var c = mk(s), x = c.getContext('2d'); x.fillStyle = '#ece9e2'; x.fillRect(0, 0, s, s); for (var i = 0; i < s; i++) { x.fillStyle = 'rgba(120,110,100,' + R() * 0.12 + ')'; x.fillRect(R() * s, R() * s, 2, 2); } return c; },
    leaf: function (s, R) {
      var c = mk(s), x = c.getContext('2d'), pal = ['#1f6b2e', '#2c8a3c', '#16542a', '#3aa04a'];
      for (var i = 0; i < 26; i++) {
        var cx = s * (0.12 + R() * 0.76), cy = s * (0.12 + R() * 0.76), L = s * (0.1 + R() * 0.14), a = R() * PI;
        x.save(); x.translate(cx, cy); x.rotate(a); x.beginPath(); x.moveTo(-L, 0); x.quadraticCurveTo(0, -L * 0.55, L, 0); x.quadraticCurveTo(0, L * 0.55, -L, 0); x.fillStyle = pal[(R() * pal.length) | 0]; x.fill(); x.restore();
      }
      return c;
    },
    flame: function (s) {
      var c = mk(s), x = c.getContext('2d'), g = x.createRadialGradient(s / 2, s * 0.66, s * 0.04, s / 2, s * 0.62, s * 0.46);
      g.addColorStop(0, 'rgba(255,245,170,1)'); g.addColorStop(0.35, 'rgba(255,170,40,.95)'); g.addColorStop(0.75, 'rgba(230,70,10,.55)'); g.addColorStop(1, 'rgba(160,20,0,0)');
      x.fillStyle = g; x.beginPath(); x.moveTo(s * 0.5, s * 0.02); x.quadraticCurveTo(s * 0.92, s * 0.55, s * 0.72, s * 0.9); x.quadraticCurveTo(s * 0.5, s * 1.02, s * 0.28, s * 0.9); x.quadraticCurveTo(s * 0.08, s * 0.55, s * 0.5, s * 0.02); x.fill();
      return c;
    }
  };

  var DARK = [0.1, 0.11, 0.14], GRAY = [0.7, 0.7, 0.73], FACE = [0.3, 0.28, 0.31];
  function hex(h) { return [((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255]; }
  function scl(c, k) { return [c[0] * k, c[1] * k, c[2] * k]; }

  /* ---------- gorilla modeli (yerel eksen: -Z ileri, y yukarı; ayak yerde) ---------- */
  function addGorilla(b, o) {
    var Ry = rotY(o.yaw || 0), base = [o.x || 0, o.y || 0, o.z || 0], fur = o.fur || [0.2, 0.2, 0.22], sg = o.seg || 7;
    function put(prim, lp, s, c, lr) { var w = apply3(Ry, lp); b.add(prim, { s: s, r: lr ? mul3(Ry, lr) : Ry, t: [base[0] + w[0], base[1] + w[1], base[2] + w[2]], c: c }); }
    function limb(a, e, r0, r1, c) {
      var d = [e[0] - a[0], e[1] - a[1], e[2] - a[2]], len = Math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
      put(cylP(r0, r1, len, 6, 2, true), [(a[0] + e[0]) / 2, (a[1] + e[1]) / 2, (a[2] + e[2]) / 2], [1, 1, 1], c, rotFromY(d));
    }
    var sph = sphP(1, sg, 5), box = boxP(1, 1, 1, 1);
    put(sph, [0, 0.55, 0.05], [0.4, 0.4, 0.32], fur);                       // gövde
    put(sph, [0, 0.58, -0.26], [0.25, 0.26, 0.07], GRAY);                   // gri göğüs
    put(sph, [0, 0.98, -0.12], [0.2, 0.19, 0.19], fur);                     // kafa
    put(sph, [0, 0.96, -0.29], [0.14, 0.13, 0.07], FACE);                   // yüz
    [-1, 1].forEach(function (s) {
      put(sph, [s * 0.055, 1.01, -0.345], [0.04, 0.04, 0.025], [1, 1, 1]);  // göz akı
      put(sph, [s * 0.055, 1.01, -0.368], [0.018, 0.018, 0.012], [0.02, 0.02, 0.03]);
      limb([s * 0.38, 0.72, 0], [s * 0.5, 0.45, -0.2], 0.09, 0.08, fur);    // üst kol
      limb([s * 0.5, 0.45, -0.2], [s * 0.38, 0.12, -0.5], 0.08, 0.07, fur); // ön kol
      put(box, [s * 0.38, 0.1, -0.54], [0.13, 0.07, 0.15], DARK);           // el
      limb([s * 0.2, 0.32, 0.05], [s * 0.26, 0.14, -0.3], 0.12, 0.1, fur);  // uyluk
      put(box, [s * 0.26, 0.06, -0.42], [0.14, 0.07, 0.2], DARK);           // ayak
    });
    put(box, [0, 1.07, -0.3], [0.2, 0.035, 0.07], scl(fur, 0.55));          // kaş
    var h = o.hat;
    if (h === 'party') {
      var cols = [[0.9, 0.15, 0.2], [1, 0.8, 0.1], [0.2, 0.75, 0.3], [0.2, 0.45, 0.95]];
      for (var i = 0; i < 4; i++) put(cylP(0.13 - i * 0.03, 0.1 - i * 0.03, 0.075, 8, 1, i === 0), [0, 1.2 + i * 0.075, -0.1], [1, 1, 1], cols[i]);
    } else if (h === 'tophat') {
      put(cylP(0.12, 0.12, 0.26, 10, 1, true), [0, 1.3, -0.1], [1, 1, 1], [0.04, 0.04, 0.05]);
      put(cylP(0.2, 0.2, 0.025, 10, 1, true), [0, 1.17, -0.1], [1, 1, 1], [0.04, 0.04, 0.05]);
    } else if (h === 'bucket') {
      put(cylP(0.2, 0.14, 0.12, 8, 1, true), [0, 1.2, -0.1], [1, 1, 1], [0.98, 0.85, 0.2]);
      put(cylP(0.27, 0.27, 0.02, 8, 1, true), [0, 1.15, -0.1], [1, 1, 1], [0.98, 0.85, 0.2]);
    } else if (h === 'pie') {
      put(cylP(0.17, 0.16, 0.06, 10, 1, true), [0, 1.2, -0.1], [1, 1, 1], [0.86, 0.66, 0.34]);
    } else if (h === 'muff') {
      [-1, 1].forEach(function (s) { put(sph, [s * 0.21, 1.02, -0.1], [0.07, 0.08, 0.05], [1, 0.82, 0.9]); });
    }
  }

  /* ---------- oyuncu avatarı: gövde/kol/el; kollar iki kemikli (dirsek) basit IK ile ---------- */
  function makePlayer(T, furHex, texFur) {
    var fur = hex(furHex), reg = [];
    var mat = new T.MeshLambertMaterial({ vertexColors: true, map: texFur || null }); reg.push(mat);
    var g = new T.Group();
    // gövde: kamera içine girmesin diye yalnızca göğüs-karın (kafa yok)
    var tb = new Batch(), sph = sphP(1, 9, 6);
    tb.add(sph, { s: [0.3, 0.27, 0.2], t: [0, -0.2, 0.02], c: fur });
    tb.add(sph, { s: [0.2, 0.2, 0.07], t: [0, -0.2, -0.165], c: GRAY });
    tb.add(sph, { s: [0.26, 0.2, 0.2], t: [0, -0.5, 0.05], c: fur });
    var tg = tb.geometry(T); reg.push(tg);
    var torso = new T.Mesh(tg, mat); torso.frustumCulled = false; g.add(torso);
    var lb = new Batch(); lb.add(cylP(1, 0.86, 1, 7, 2, true), { c: fur }); var upG = lb.geometry(T); reg.push(upG);
    var lb2 = new Batch(); lb2.add(cylP(0.86, 0.7, 1, 7, 2, true), { c: fur }); var loG = lb2.geometry(T); reg.push(loG);
    function handGeo(fist) {
      var hb = new Batch(), bx = boxP(1, 1, 1, 1);
      if (!fist) {
        hb.add(bx, { s: [0.1, 0.035, 0.1], t: [0, 0, 0.02], c: DARK });                  // avuç
        for (var f = 0; f < 4; f++) hb.add(bx, { s: [0.022, 0.026, 0.085 - Math.abs(f - 1.5) * 0.008], t: [-0.036 + f * 0.024, 0, 0.115], c: DARK });
        hb.add(bx, { s: [0.026, 0.026, 0.07], r: rotY(-0.7), t: [0.07, -0.005, 0.045], c: DARK }); // başparmak
      } else {
        hb.add(bx, { s: [0.11, 0.07, 0.1], t: [0, -0.005, 0.03], c: DARK });
        for (f = 0; f < 4; f++) hb.add(bx, { s: [0.025, 0.03, 0.03], t: [-0.039 + f * 0.026, -0.04, 0.085], c: DARK });
        hb.add(bx, { s: [0.03, 0.03, 0.055], r: rotY(-0.5), t: [0.07, -0.03, 0.065], c: DARK });
      }
      return hb.geometry(T);
    }
    var hgO = handGeo(false), hgF = handGeo(true); reg.push(hgO, hgF);
    var arms = [];
    for (var i = 0; i < 2; i++) {
      var up = new T.Mesh(upG, mat), lo = new T.Mesh(loG, mat), ho = new T.Mesh(hgO, mat), hf = new T.Mesh(hgF, mat);
      [up, lo, ho, hf].forEach(function (m) { m.frustumCulled = false; g.add(m); });
      arms.push({ up: up, lo: lo, hand: ho, fist: hf });
    }
    var V = function (x, y, z) { return new T.Vector3(x, y, z); }, Y = V(0, 1, 0), q = new T.Quaternion(), m4 = new T.Matrix4();
    var L1 = 0.5, L2 = 0.56;
    function place(mesh, a, e, r) {
      var dx = e.x - a.x, dy = e.y - a.y, dz = e.z - a.z, len = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1e-4;
      mesh.position.set((a.x + e.x) / 2, (a.y + e.y) / 2, (a.z + e.z) / 2); mesh.scale.set(r, len, r);
      mesh.quaternion.setFromUnitVectors(Y, V(dx / len, dy / len, dz / len));
    }
    var P = {
      group: g, torso: torso, arms: arms, reg: reg, mat: mat,
      /* body: gövde dünya konumu; yaw; hands[i]={valid,x,y,z,contact,grip,n:{x,y,z}} dünya konumları */
      pose: function (body, yaw, hands) {
        g.position.set(body.x, body.y, body.z); g.rotation.set(0, yaw, 0);
        var cy = Math.cos(yaw), sy = Math.sin(yaw);
        for (var i = 0; i < 2; i++) {
          var H = hands[i], A = arms[i], side = i === 0 ? -1 : 1;
          var vis = !!H.valid; A.up.visible = A.lo.visible = vis; A.hand.visible = vis && !H.grip; A.fist.visible = vis && !!H.grip;
          if (!vis) continue;
          // dünya -> avatar yerel (yalnızca yaw)
          var rx = H.x - body.x, ry = H.y - body.y, rz = H.z - body.z, lx = rx * cy - rz * sy, lz = rx * sy + rz * cy;
          var S = V(side * 0.3, -0.02, 0.0), E = V(lx, ry, lz), dx = E.x - S.x, dy = E.y - S.y, dz = E.z - S.z, d = Math.sqrt(dx * dx + dy * dy + dz * dz), dm = L1 + L2 - 0.015;
          if (d > dm) { var k = dm / d; E.set(S.x + dx * k, S.y + dy * k, S.z + dz * k); dx *= k; dy *= k; dz *= k; d = dm; }
          if (d < 0.12) d = 0.12;
          var ux = dx / d, uy = dy / d, uz = dz / d;
          // dirsek: eksenin dik düzleminde, dışa-aşağı-arkaya doğru kutup
          var px = side * 0.7, py = -0.6, pz = 0.55, pd = px * ux + py * uy + pz * uz, ox = px - pd * ux, oy = py - pd * uy, oz = pz - pd * uz, ol = Math.sqrt(ox * ox + oy * oy + oz * oz) || 1;
          ox /= ol; oy /= ol; oz /= ol;
          var a = (L1 * L1 - L2 * L2 + d * d) / (2 * d), hh = Math.sqrt(Math.max(0, L1 * L1 - a * a));
          var El = V(S.x + ux * a + ox * hh, S.y + uy * a + oy * hh, S.z + uz * a + oz * hh);
          place(A.up, S, El, 0.075); place(A.lo, El, E, 0.065);
          // el yönü: parmaklar ön kol yönünde; temasta avuç içi yüzeye bakar
          var f = norm([E.x - El.x, E.y - El.y, E.z - El.z]), up = [0, 1, 0];
          if (H.contact && H.n) { var nn = [H.n.x * cy - H.n.z * sy, H.n.y, H.n.x * sy + H.n.z * cy]; up = nn; }
          var dp = f[0] * up[0] + f[1] * up[1] + f[2] * up[2], fz = norm([f[0] - dp * up[0], f[1] - dp * up[1], f[2] - dp * up[2]]);
          if (isNaN(fz[0]) || Math.abs(dp) > 0.98) fz = f;
          var xr = norm(cross(up, fz)), yr = cross(fz, xr);
          m4.makeBasis(V(xr[0], xr[1], xr[2]), V(yr[0], yr[1], yr[2]), V(fz[0], fz[1], fz[2]));
          q.setFromRotationMatrix(m4);
          A.hand.position.copy(E); A.hand.quaternion.copy(q); A.fist.position.copy(E); A.fist.quaternion.copy(q);
        }
      },
      dispose: function () { reg.forEach(function (x) { try { x.dispose(); } catch (e) { } }); }
    };
    return P;
  }

  /* ---------- dünya ---------- */
  function noiseWall(R, CAN, seg, rows, top) {
    var ph = [R() * 6.28, R() * 6.28, R() * 6.28], pos = [], uv = [];
    function rad(th, y) { var n = 0.5 * Math.sin(5 * th + ph[0] + 0.2 * y) + 0.3 * Math.sin(11 * th + ph[1] - 0.35 * y) + 0.2 * Math.sin(23 * th + ph[2] + 0.6 * y); return CAN + 0.4 + (n * 0.5 + 0.5) * 3.2 - 0.02 * y; }
    function P(i, j) { var th = i / seg * 2 * PI, y = -1 + j / rows * top, r = rad(th, y); return [Math.cos(th) * r, y, Math.sin(th) * r, i / seg * 2 * PI * CAN / 7, (y + 1) / 7]; }
    for (var j = 0; j < rows; j++) for (var i = 0; i < seg; i++) {
      var A = P(i, j), B = P(i + 1, j), C = P(i + 1, j + 1), D = P(i, j + 1);
      [[A, C, B], [A, D, C]].forEach(function (t) { t.forEach(function (v) { pos.push(v[0], v[1], v[2]); uv.push(v[3], v[4]); }); });
    }
    return { pos: pos, uv: uv };
  }

  function buildWorld(T, map, opt) {
    opt = opt || {};
    var q = opt.quality == null ? 1 : opt.quality, ts = [64, 128, 192][q], R = rng(4242), reg = [];
    var group = new T.Group(); group.visible = false;
    function tx(kind, rep) {
      var t = new T.CanvasTexture(TEX[kind](ts, rng(kind.length * 977 + 13)));
      t.wrapS = t.wrapT = T.RepeatWrapping; if (rep) t.repeat.set(rep, rep); reg.push(t); return t;
    }
    function mat(kind, extra) { var m = new T.MeshLambertMaterial(Object.assign({ map: tx(kind), vertexColors: true }, extra || {})); reg.push(m); return m; }
    var M = { wood: mat('wood'), rock: mat('rock'), trunk: mat('bark'), shingle: mat('shingle'), white: mat('white') };
    var B = { wood: new Batch(), rock: new Batch(), trunk: new Batch(), shingle: new Batch(), white: new Batch() };
    var seg = q === 0 ? 6 : 8;

    map.colliders.forEach(function (c) {
      var b = B[c.mat]; if (!b || c.ground || c.type === 'ring') return;
      var tint = 0.9 + R() * 0.2, col = [tint, tint, tint];
      if (c.type === 'box') {
        var w = c.max.x - c.min.x, h = c.max.y - c.min.y, d = c.max.z - c.min.z;
        b.add(boxP(w, h, d, 2), { t: [c.min.x + w / 2, c.min.y + h / 2, c.min.z + d / 2], c: col });
      } else if (c.type === 'obb') {
        b.add(boxP(c.h.x * 2, c.h.y * 2, c.h.z * 2, 2), { r: c.rot, t: [c.c.x, c.c.y, c.c.z], c: col });
      } else if (c.type === 'cyl') {
        var tp = c.taper || [1, 1], hh = c.y1 - c.y0;
        b.add(cylP(c.R * tp[0], c.R * tp[1], hh, seg, 2, true), { t: [c.x, (c.y0 + c.y1) / 2, c.z], c: col });
      } else if (c.type === 'seg') {
        var dv = [c.b.x - c.a.x, c.b.y - c.a.y, c.b.z - c.a.z], ln = Math.sqrt(dv[0] * dv[0] + dv[1] * dv[1] + dv[2] * dv[2]);
        b.add(cylP(c.R, c.R * 0.65, ln, 5, 2, true), { r: rotFromY(dv), t: [(c.a.x + c.b.x) / 2, (c.a.y + c.b.y) / 2, (c.a.z + c.b.z) / 2], c: col });
      }
    });
    var meshes = {};
    Object.keys(B).forEach(function (k) {
      if (!B[k].tris()) return;
      var geo = B[k].geometry(T); reg.push(geo); var m = new T.Mesh(geo, M[k]); m.frustumCulled = false; group.add(m); meshes[k] = m;
    });

    // zemin
    var gb = new Batch(), CAN = map.canyon || 33, DS = 40, ring = [];
    var gt = tx('ground'), gm = new T.MeshLambertMaterial({ map: gt, vertexColors: true, side: T.DoubleSide }); reg.push(gm);
    for (var i = 0; i < DS; i++) {
      var a0 = i / DS * 2 * PI, a1 = (i + 1) / DS * 2 * PI, rr = CAN + 6;
      var pr = { pos: [0, 0, 0, Math.cos(a1) * rr, 0, Math.sin(a1) * rr, Math.cos(a0) * rr, 0, Math.sin(a0) * rr], uv: [0, 0, Math.cos(a1) * rr / 8, Math.sin(a1) * rr / 8, Math.cos(a0) * rr / 8, Math.sin(a0) * rr / 8] };
      gb.add(pr, { up: true });
    }
    var ggeo = gb.geometry(T); reg.push(ggeo); var gmesh = new T.Mesh(ggeo, gm); gmesh.frustumCulled = false; group.add(gmesh);

    // kanyon duvarı
    var wb = new Batch(), wt = tx('rock'), wm = new T.MeshLambertMaterial({ map: wt, vertexColors: true, side: T.DoubleSide, color: 0xb8a8c0 }); reg.push(wm);
    wb.add(noiseWall(R, CAN, q === 0 ? 28 : 40, q === 0 ? 6 : 9, 55), { flip: false });
    var wgeo = wb.geometry(T); reg.push(wgeo); var wmesh = new T.Mesh(wgeo, wm); wmesh.frustumCulled = false; group.add(wmesh);

    // yapraklar: çapraz kartlar, tek InstancedMesh (alphaTest: sıralama gerekmez)
    var lt = tx('leaf'), lm = new T.MeshLambertMaterial({ map: lt, alphaTest: 0.5, side: T.DoubleSide }); reg.push(lm);
    var lb = new Batch(); lb.add(quadP(1, 1), { flip: false }); lb.add(quadP(1, 1), { flip: false, r: rotY(PI / 2) }); lb.add(quadP(1, 1), { flip: false, r: rotX(PI / 2) });
    var lgeo = lb.geometry(T); reg.push(lgeo);
    var L = map.leaves.slice(), imesh = new T.InstancedMesh(lgeo, lm, Math.max(1, L.length)); imesh.frustumCulled = false;
    for (i = L.length - 1; i > 0; i--) { var j = (R() * (i + 1)) | 0, tmp = L[i]; L[i] = L[j]; L[j] = tmp; }   // alt küme rastgele eşit dağılsın
    var m4 = new T.Matrix4(), qq = new T.Quaternion(), e = new T.Euler(), one = new T.Vector3(), pp = new T.Vector3(), col = new T.Color();
    L.forEach(function (l, k) {
      e.set((R() - 0.5) * 0.6, R() * 6.283, (R() - 0.5) * 0.6); qq.setFromEuler(e); pp.set(l[0], l[1], l[2]); one.set(l[3] * 1.6, l[3] * 1.6, l[3] * 1.6);
      m4.compose(pp, qq, one); imesh.setMatrixAt(k, m4);
      if (imesh.setColorAt) { var g = 0.75 + R() * 0.4; col.setRGB(g * 0.9, g, g * 0.85); imesh.setColorAt(k, col); }
    });
    imesh.instanceMatrix.needsUpdate = true; if (imesh.instanceColor) imesh.instanceColor.needsUpdate = true;
    imesh.count = L.length; group.add(imesh);

    // şenlik ateşi
    var ft = new T.CanvasTexture(TEX.flame(64)); reg.push(ft);
    var fm = new T.MeshBasicMaterial({ map: ft, transparent: true, blending: T.AdditiveBlending, depthWrite: false, side: T.DoubleSide, fog: false }); reg.push(fm);
    var fg = new T.PlaneGeometry(1, 1); reg.push(fg);
    var fires = [];
    for (i = 0; i < 3; i++) { var fq = new T.Mesh(fg, fm); fq.position.set(map.fire.x, 0.75, map.fire.z); fq.rotation.y = i * PI / 3; group.add(fq); fires.push(fq); }

    // ateş çevresindeki gorilla topluluğu: her biri tek çizim çağrısı
    var ft2 = new T.CanvasTexture(TEX.fur(64, rng(5))); ft2.wrapS = ft2.wrapT = T.RepeatWrapping; reg.push(ft2);
    var npcs = [];
    map.npcs.forEach(function (n) {
      var nb = new Batch(); addGorilla(nb, { x: n.x, z: n.z, yaw: n.yaw, fur: hex(n.fur), hat: n.hat, seg: q === 0 ? 6 : 8 });
      var ng = nb.geometry(T), nm = new T.MeshLambertMaterial({ vertexColors: true, map: ft2 }); reg.push(ng, nm);
      var nmesh = new T.Mesh(ng, nm); nmesh.frustumCulled = false; group.add(nmesh); npcs.push(nmesh);
    });

    var W = {
      group: group, meshes: meshes, leaves: imesh, leafTotal: L.length, npcs: npcs, fires: fires, ft2: ft2,
      setQuality: function (lv) {
        imesh.count = Math.max(1, Math.floor(L.length * [0.45, 0.75, 1][lv]));
        npcs.forEach(function (n, k) { n.visible = lv >= 1 || k < 3; });
        wmesh.visible = true;
      },
      update: function (dt, t) {
        for (var k = 0; k < fires.length; k++) {
          var f = fires[k], s = 1 + 0.18 * Math.sin(t * 9 + k * 2.1) + 0.1 * Math.sin(t * 17.3 + k);
          f.scale.set(0.9 * s, 1.35 * (1.05 + 0.2 * Math.sin(t * 11 + k * 1.3)), 1); f.position.y = 0.4 + f.scale.y * 0.38;
        }
      },
      dispose: function () { reg.forEach(function (x) { try { x.dispose(); } catch (e2) { } }); }
    };
    W.setQuality(q);
    return W;
  }

  var API = { rng: rng, Batch: Batch, boxP: boxP, cylP: cylP, sphP: sphP, quadP: quadP, rotY: rotY, rotFromY: rotFromY, mul3: mul3, apply3: apply3, addGorilla: addGorilla, hex: hex, buildWorld: buildWorld, makePlayer: makePlayer, TEX: TEX, noiseWall: noiseWall };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  root.GorillaArt = API;
})(typeof window !== 'undefined' ? window : globalThis);
