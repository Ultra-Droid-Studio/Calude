/* NEXUS VR: GORILLA RUN — Stage 74 NPC sistemi (dolaşan, çevreyi algılayan, oyuncuya tepki veren goriller).
   Mantık katmanı THREE/DOM'dan bağımsızdır (Node'da test edilir: tools/gorilla-npc.test.js); görsel katman
   (makeView) yalnızca oyunda, GorillaArt ile kurulur.

   Durum makinesi (her NPC'de tek durum; davranışlar karışmaz):
     IDLE → (bekle, etrafa bak) → EXPLORE (A* ile rastgele yürünebilir hedef) | TURN (yerinde dön)
     EXPLORE/WALK → hedefe vardı → IDLE ; önü kapandı → AVOID (yana kay) → yeniden yol planla
     herhangi → oyuncu görüldü → DETECT (dur, oyuncuya dön, tepki) → meraklı: INTERACT (yaklaş, el salla) /
                                                                     ürkek: kaç (EXPLORE, uzak hedef)
     uzaklaştıysa → RETURN (yuvasına dön)
   Performans: yakın NPC her karede, orta mesafe her 3. karede, uzak her 8. karede, görüş alanı dışındaki
   (ve 6 m'den uzak) NPC her 12. karede güncellenir; atlanan süre biriktirilip tek adımda uygulanır (hız aynı kalır).
   Yol bulma: dünya bir kez 1 m'lik ızgaraya örneklenir (yürünebilir/engel), A* düğüm sınırıyla çalışır. */
(function (root) {
  'use strict';

  var ST = { IDLE: 0, WALK: 1, EXPLORE: 2, TURN: 3, AVOID: 4, DETECT: 5, INTERACT: 6, RETURN: 7 };
  var STN = ['Boşta', 'Yürüyor', 'Keşif', 'Dönüyor', 'Engelden kaçıyor', 'Oyuncuyu gördü', 'Etkileşim', 'Geri dönüyor'];
  var CFG = {
    r: 0.36,            // gövde yarıçapı (yatay çarpışma)
    walk: 1.25,         // yürüme hızı m/s
    run: 2.6,           // kaçış hızı
    turnRate: 3.2,      // rad/s
    seeDist: 7,         // görme mesafesi
    seeFov: 0.5,        // cos(60°): ön yarım koni
    nearDist: 2.6,      // arkadan da fark eder
    personal: 1.6,      // meraklı NPC oyuncuya bu kadar yaklaşır
    forget: 9,          // bu mesafeden uzak oyuncu unutulur
    roam: 9,            // yuvadan en çok bu kadar uzaklaşır
    cell: 1,            // yol ızgarası hücresi (m)
    maxNodes: 1600,     // A* düğüm sınırı (kare bütçesi)
    lodNear: 10, lodMid: 22
  };

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function rng(seed) { var a = seed >>> 0; return function () { a = (a + 0x6D2B79F5) >>> 0; var t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  function angDiff(a, b) { var d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return d; }

  /* ---------- yol ızgarası + A* ---------- */
  function Nav(world, map, cfg) {
    cfg = cfg || CFG;
    var R = (map.canyon || 33) - 2.2, C = cfg.cell, N = Math.ceil(R * 2 / C) + 1;
    this.C = C; this.N = N; this.o = -R; this.R = R;
    this.walk = new Uint8Array(N * N);
    var p = { x: 0, y: 0.55, z: 0 }, probe = cfg.r + 0.12;
    for (var j = 0; j < N; j++) for (var i = 0; i < N; i++) {
      var x = this.o + i * C, z = this.o + j * C;
      if (x * x + z * z > R * R) continue;
      p.x = x; p.z = z; p.y = 0.55;
      var h = world.query(p, probe, false);
      if (h && !(h.collider && h.collider.ground)) continue;
      p.y = 1.2; h = world.query(p, probe, false);
      if (h && !(h.collider && h.collider.ground)) continue;
      this.walk[j * N + i] = 1;
    }
    this.g = new Float32Array(N * N); this.from = new Int32Array(N * N); this.seen = new Uint32Array(N * N); this.stamp = 0;
    this.heap = new Int32Array(N * N); this.f = new Float32Array(N * N);
  }
  Nav.prototype.idx = function (x, z) {
    var i = Math.round((x - this.o) / this.C), j = Math.round((z - this.o) / this.C);
    if (i < 0 || j < 0 || i >= this.N || j >= this.N) return -1;
    return j * this.N + i;
  };
  Nav.prototype.ok = function (x, z) { var k = this.idx(x, z); return k >= 0 && this.walk[k] === 1; };
  Nav.prototype.nearestOk = function (x, z) {
    var k = this.idx(x, z); if (k >= 0 && this.walk[k]) return k;
    var N = this.N, ci = Math.round((x - this.o) / this.C), cj = Math.round((z - this.o) / this.C);
    for (var r = 1; r < 6; r++) for (var dj = -r; dj <= r; dj++) for (var di = -r; di <= r; di++) {
      if (Math.abs(di) !== r && Math.abs(dj) !== r) continue;
      var i = ci + di, j = cj + dj; if (i < 0 || j < 0 || i >= N || j >= N) continue;
      if (this.walk[j * N + i]) return j * N + i;
    }
    return -1;
  };
  /* Izgara üzerinde düz çizgi yürünebilir mi (yol sadeleştirme için) */
  Nav.prototype.los = function (ax, az, bx, bz) {
    var d = Math.hypot(bx - ax, bz - az), n = Math.ceil(d / (this.C * 0.5));
    for (var s = 1; s < n; s++) { var t = s / n; if (!this.ok(ax + (bx - ax) * t, az + (bz - az) * t)) return false; }
    return true;
  };
  /* A*: 8 komşu, ikili yığın, düğüm sınırı. Dönen: [{x,z},...] (başlangıç hariç) ya da null */
  Nav.prototype.path = function (ax, az, bx, bz, maxNodes) {
    var N = this.N, s = this.nearestOk(ax, az), t = this.nearestOk(bx, bz);
    if (s < 0 || t < 0) return null;
    if (s === t) return [{ x: bx, z: bz }];
    var st = ++this.stamp, g = this.g, f = this.f, from = this.from, seen = this.seen, heap = this.heap, hn = 0, ti = t % N, tj = (t / N) | 0;
    var H = function (k) { var di = Math.abs(k % N - ti), dj = Math.abs(((k / N) | 0) - tj); return (di + dj) + (1.4142 - 2) * Math.min(di, dj); };
    var push = function (k) { var i = hn++; heap[i] = k; while (i > 0) { var p = (i - 1) >> 1; if (f[heap[p]] <= f[heap[i]]) break; var tmp = heap[p]; heap[p] = heap[i]; heap[i] = tmp; i = p; } };
    var pop = function () { var top = heap[0]; heap[0] = heap[--hn]; var i = 0; for (;;) { var l = i * 2 + 1, r = l + 1, m = i; if (l < hn && f[heap[l]] < f[heap[m]]) m = l; if (r < hn && f[heap[r]] < f[heap[m]]) m = r; if (m === i) break; var tmp = heap[m]; heap[m] = heap[i]; heap[i] = tmp; i = m; } return top; };
    seen[s] = st; g[s] = 0; f[s] = H(s); from[s] = -1; push(s);
    var closed = st + 0.5, expanded = 0, lim = maxNodes || CFG.maxNodes, found = false;
    var DI = [1, -1, 0, 0, 1, 1, -1, -1], DJ = [0, 0, 1, -1, 1, -1, 1, -1], DC = [1, 1, 1, 1, 1.4142, 1.4142, 1.4142, 1.4142];
    var cl = this.cl || (this.cl = new Float64Array(N * N));
    while (hn > 0) {
      var k = pop();
      if (cl[k] === closed) continue;
      cl[k] = closed;
      if (k === t) { found = true; break; }
      if (++expanded > lim) break;
      var ki = k % N, kj = (k / N) | 0;
      for (var d = 0; d < 8; d++) {
        var ni = ki + DI[d], nj = kj + DJ[d];
        if (ni < 0 || nj < 0 || ni >= N || nj >= N) continue;
        var nk = nj * N + ni;
        if (!this.walk[nk] || cl[nk] === closed) continue;
        if (d >= 4 && (!this.walk[kj * N + ni] || !this.walk[nj * N + ki])) continue;   // köşe kesme yok
        var ng = g[k] + DC[d];
        if (seen[nk] !== st || ng < g[nk]) { seen[nk] = st; g[nk] = ng; f[nk] = ng + H(nk); from[nk] = k; push(nk); }
      }
    }
    if (!found) return null;
    var pts = [], c = t;
    while (c !== -1 && c !== s) { pts.push({ x: this.o + (c % N) * this.C, z: this.o + ((c / N) | 0) * this.C }); c = from[c]; }
    pts.reverse();
    pts[pts.length - 1] = { x: bx, z: bz };
    // görüş hattı ile sadeleştir
    var out = [], cx = ax, cz = az, i = 0;
    while (i < pts.length) {
      var j = pts.length - 1;
      while (j > i && !this.los(cx, cz, pts[j].x, pts[j].z)) j--;
      out.push(pts[j]); cx = pts[j].x; cz = pts[j].z; i = j + 1;
    }
    return out;
  };

  /* ---------- NPC ---------- */
  function Npc(id, home, look, seed) {
    this.id = id; this.home = { x: home.x, z: home.z };
    this.x = home.x; this.z = home.z; this.y = 0; this.yaw = (seed % 628) / 100; this.vx = 0; this.vz = 0;
    this.st = ST.IDLE; this.t = 1 + (seed % 7) * 0.3; this.path = null; this.pi = 0; this.goal = null;
    this.look = look || {}; this.curious = (seed % 3) !== 0;      // 2/3 meraklı, 1/3 ürkek
    this.rand = rng(seed * 7919 + 13);
    this.acc = 0; this.frame = id; this.lod = 0; this.visible = true;
    this.phase = 0; this.speed = 0; this.headYaw = 0; this.react = 0; this.wave = 0; this.jumpV = 0;
    this.seen = false; this.soundCd = 0; this.avoidT = 0; this.avoidDir = 1; this.stuck = 0; this.lastX = home.x; this.lastZ = home.z;
    this.events = [];
  }

  function Manager(world, map, opt) {
    opt = opt || {};
    this.cfg = Object.assign({}, CFG, opt.cfg || {});
    this.world = world; this.map = map;
    this.nav = new Nav(world, map, this.cfg);
    this.list = [];
    this.frame = 0;
    this.stats = { updated: 0, skipped: 0, paths: 0, ms: 0 };
    this.grid = {};        // NPC'ler arası uzamsal karma (2 m)
    var homes = opt.homes || defaultHomes(map, this.nav, opt.count || 6, opt.seed || 99);
    for (var i = 0; i < homes.length; i++) this.list.push(new Npc(i, homes[i], homes[i].look, (opt.seed || 99) * 31 + i * 101));
  }

  /* Yuvalar: kanyon içinde, yürünebilir, birbirinden ve başlangıçtan uzak noktalar */
  function defaultHomes(map, nav, n, seed) {
    var R = rng(seed), out = [], furs = [0x7a4a2a, 0x3b3b44, 0xc8a070, 0x5a6b8a, 0x8a3a3a, 0x4a7a4a, 0x9a7ad0], hats = [null, 'party', null, 'bucket', 'tophat', null, 'pie'];
    var tries = 0, sp = map.spawn || { x: 0, z: 0 };
    while (out.length < n && tries++ < 500) {
      var a = R() * Math.PI * 2, r = 5 + R() * ((map.canyon || 33) - 9), x = Math.cos(a) * r, z = Math.sin(a) * r;
      if (!nav.ok(x, z) || Math.hypot(x - sp.x, z - sp.z) < 4) continue;
      var far = true; for (var k = 0; k < out.length; k++) if (Math.hypot(out[k].x - x, out[k].z - z) < 6) far = false;
      if (!far) continue;
      out.push({ x: x, z: z, look: { fur: furs[out.length % furs.length], hat: hats[out.length % hats.length] } });
    }
    return out;
  }

  /* Oyuncu bilgisi: {x,y,z, fx,fz (bakış yönü), hands:[{x,y,z,vx,vy,vz,valid}]} */
  Manager.prototype.update = function (dt, P) {
    var t0 = typeof performance !== 'undefined' ? performance.now() : 0;
    var C = this.cfg; this.frame++;
    this.stats.updated = 0; this.stats.skipped = 0;
    this._hash();
    for (var i = 0; i < this.list.length; i++) {
      var n = this.list[i];
      n.acc += dt;
      var dx = n.x - P.x, dz = n.z - P.z, d = Math.sqrt(dx * dx + dz * dz);
      var inView = d < 6 || (P.fx * dx + P.fz * dz) > -0.35 * d;   // ±110° görüş konisi (VR'da hızlı baş dönüşü için geniş)
      var every = d < C.lodNear ? 1 : d < C.lodMid ? 3 : 8;
      if (!inView) every = Math.max(every, 12);
      n.lod = d < C.lodNear ? 0 : d < C.lodMid ? 1 : 2;
      n.visible = inView;
      if ((this.frame + n.id) % every !== 0 && n.acc < 0.5) { this.stats.skipped++; continue; }
      var h = Math.min(n.acc, 0.5); n.acc = 0;
      this._think(n, h, P, d);
      this._move(n, h);
      this.stats.updated++;
    }
    this._separate();
    if (t0) this.stats.ms = performance.now() - t0;
  };

  Manager.prototype._hash = function () {
    var g = this.grid; for (var k in g) g[k].length = 0;
    for (var i = 0; i < this.list.length; i++) {
      var n = this.list[i], key = Math.floor(n.x / 2) + ',' + Math.floor(n.z / 2);
      (g[key] || (g[key] = [])).push(n);
    }
  };
  /* NPC'ler birbirinin içine girmesin (uzamsal karma ile yalnızca komşular denetlenir) */
  Manager.prototype._separate = function () {
    var g = this.grid, R2 = this.cfg.r * 2;
    for (var i = 0; i < this.list.length; i++) {
      var a = this.list[i], gx = Math.floor(a.x / 2), gz = Math.floor(a.z / 2);
      for (var ox = -1; ox <= 1; ox++) for (var oz = -1; oz <= 1; oz++) {
        var cell = g[(gx + ox) + ',' + (gz + oz)]; if (!cell) continue;
        for (var k = 0; k < cell.length; k++) {
          var b = cell[k]; if (b.id <= a.id) continue;
          var dx = b.x - a.x, dz = b.z - a.z, d = Math.sqrt(dx * dx + dz * dz);
          if (d < R2 && d > 1e-6) { var push = (R2 - d) / 2, ux = dx / d, uz = dz / d; a.x -= ux * push; a.z -= uz * push; b.x += ux * push; b.z += uz * push; }
        }
      }
    }
  };

  Manager.prototype._plan = function (n, gx, gz) {
    this.stats.paths++;
    var p = this.nav.path(n.x, n.z, gx, gz, this.cfg.maxNodes);
    n.path = p; n.pi = 0; n.goal = p ? { x: gx, z: gz } : null;
    return !!p;
  };
  Manager.prototype._randomGoal = function (n, cx, cz, rad) {
    for (var k = 0; k < 12; k++) {
      var a = n.rand() * Math.PI * 2, r = 2 + n.rand() * rad, x = cx + Math.cos(a) * r, z = cz + Math.sin(a) * r;
      if (this.nav.ok(x, z)) return { x: x, z: z };
    }
    return null;
  };
  /* Kaçış hedefi: oyuncudan uzaklaşan yönde (±45°), yürünebilir ve oyuncuya en uzak aday */
  Manager.prototype._fleeGoal = function (n, px, pz, dist) {
    var ax = n.x - px, az = n.z - pz, base = Math.atan2(ax, az), best = null, bd = -1;
    for (var k = 0; k < 10; k++) {
      var a = base + (n.rand() - 0.5) * 1.6, r = dist * (0.7 + n.rand() * 0.6), x = n.x + Math.sin(a) * r, z = n.z + Math.cos(a) * r;
      if (!this.nav.ok(x, z)) continue;
      var d = Math.hypot(x - px, z - pz); if (d > bd) { bd = d; best = { x: x, z: z }; }
    }
    return best;
  };
  Manager.prototype._set = function (n, st, t) { n.st = st; n.t = t == null ? 0 : t; if (st !== ST.WALK && st !== ST.EXPLORE) { n.path = null; } };

  Manager.prototype._think = function (n, h, P, d) {
    var C = this.cfg; n.t -= h; n.soundCd -= h; n.react = Math.max(0, n.react - h);
    var dx = P.x - n.x, dz = P.z - n.z, fwd = Math.sin(n.yaw) * -dx + Math.cos(n.yaw) * -dz;   // NPC -Z'ye bakar
    var sees = d < C.nearDist || (d < C.seeDist && fwd > C.seeFov * d);
    // dokunuş: oyuncunun eli hızlıca NPC'ye değdi → "ebelendi" tepkisi
    if (P.hands) for (var i = 0; i < P.hands.length; i++) {
      var H = P.hands[i]; if (!H || !H.valid) continue;
      var hx = H.x - n.x, hz = H.z - n.z, hy = H.y - (n.y + 0.7);
      if (hx * hx + hz * hz < 0.5 * 0.5 && Math.abs(hy) < 0.8) {
        var sp = Math.sqrt((H.vx || 0) * (H.vx || 0) + (H.vy || 0) * (H.vy || 0) + (H.vz || 0) * (H.vz || 0));
        if (n.react <= 0) { n.react = 1.2; n.jumpV = 2.6 + Math.min(2, sp * 0.3); n.events.push('tag'); n.seen = true;
          var g = this._fleeGoal(n, P.x, P.z, 5);
          if (g && this._plan(n, g.x, g.z)) { this._set(n, ST.EXPLORE, 6); n.flee = true; } }
      }
    }
    if (sees && !n.seen && n.st !== ST.DETECT && n.react <= 0) {
      n.seen = true; this._set(n, ST.DETECT, 1.1); n.events.push('see'); return;
    }
    if (n.seen && d > C.forget) { n.seen = false; if (n.st === ST.INTERACT || n.st === ST.DETECT) this._set(n, ST.RETURN); }
    switch (n.st) {
      case ST.IDLE:
        n.headYaw = Math.sin(n.phase * 0.7) * 0.6; n.phase += h;
        if (n.t <= 0) {
          var home = Math.hypot(n.x - n.home.x, n.z - n.home.z);
          if (home > C.roam * 1.3) { this._set(n, ST.RETURN); break; }
          if (n.rand() < 0.65) {
            var g2 = this._randomGoal(n, n.home.x, n.home.z, C.roam);
            if (g2 && this._plan(n, g2.x, g2.z)) { this._set(n, ST.EXPLORE, 20); n.flee = false; break; }
          }
          this._set(n, ST.TURN, 0.5 + n.rand() * 0.6); n.turnTo = n.yaw + (n.rand() - 0.5) * 3;
        }
        break;
      case ST.TURN:
        n.yaw += clamp(angDiff(n.yaw, n.turnTo), -C.turnRate * h, C.turnRate * h);
        if (n.t <= 0) this._set(n, ST.IDLE, 1 + n.rand() * 2.5);
        break;
      case ST.DETECT:
        n.yaw += clamp(angDiff(n.yaw, Math.atan2(-dx, -dz)), -C.turnRate * 1.5 * h, C.turnRate * 1.5 * h);
        n.headYaw *= 0.8;
        if (n.t <= 0) {
          if (n.curious) this._set(n, ST.INTERACT, 6 + n.rand() * 4);
          else { var g3 = this._fleeGoal(n, P.x, P.z, 6); if (g3 && this._plan(n, g3.x, g3.z)) { this._set(n, ST.EXPLORE, 8); n.flee = true; } else this._set(n, ST.IDLE, 1); }
        }
        break;
      case ST.INTERACT:
        n.yaw += clamp(angDiff(n.yaw, Math.atan2(-dx, -dz)), -C.turnRate * h, C.turnRate * h);
        n.wave += h;
        if (d > C.personal + 0.4) { this._steer(n, P.x, P.z, h, C.walk * 0.8); }
        else { n.speed = 0; n.vx = n.vz = 0; }
        if (n.soundCd <= 0 && d < 4) { n.events.push('hoot'); n.soundCd = 4 + n.rand() * 3; }
        if (n.t <= 0 || d > C.forget) this._set(n, ST.RETURN);
        break;
      case ST.AVOID:
        n.avoidT -= h;
        var sx = Math.cos(n.yaw) * n.avoidDir, sz = -Math.sin(n.yaw) * n.avoidDir;
        this._steer(n, n.x + sx, n.z + sz, h, C.walk * 0.7);
        if (n.avoidT <= 0) {
          var goal = n.goal; this._set(n, ST.IDLE, 0.2);
          if (goal && this._plan(n, goal.x, goal.z)) this._set(n, ST.WALK, 15);
        }
        break;
      case ST.RETURN:
        if (!n.path) { if (!this._plan(n, n.home.x, n.home.z)) { this._set(n, ST.IDLE, 1); break; } n.t = 25; n.flee = false; }
        /* fall through */
      case ST.WALK:
      case ST.EXPLORE:
        if (!n.path || n.pi >= n.path.length || n.t <= 0) { n.flee = false; this._set(n, ST.IDLE, 1 + n.rand() * 3); n.speed = 0; break; }
        var wp = n.path[n.pi], wd = Math.hypot(wp.x - n.x, wp.z - n.z);
        if (wd < 0.45) { n.pi++; break; }
        // engel algılama: önündeki noktayı yokla (dünya + diğer NPC'ler)
        if (this._blocked(n)) { n.st = ST.AVOID; n.avoidT = 0.7; n.avoidDir = n.rand() < 0.5 ? -1 : 1; n.stuck = 0; break; }
        this._steer(n, wp.x, wp.z, h, n.flee ? C.run : C.walk);
        // takılma: hareket etmiyorsa yeniden planla
        var mv = Math.hypot(n.x - n.lastX, n.z - n.lastZ); n.lastX = n.x; n.lastZ = n.z;
        if (mv < 0.05 * h) { if ((n.stuck += h) > 1.2) { n.stuck = 0; var gg = n.goal; if (!gg || !this._plan(n, gg.x, gg.z)) this._set(n, ST.IDLE, 1); } } else n.stuck = 0;
        break;
    }
  };

  Manager.prototype._blocked = function (n) {
    var fx = -Math.sin(n.yaw), fz = -Math.cos(n.yaw), px = n.x + fx * 0.75, pz = n.z + fz * 0.75;
    var p = this._pp || (this._pp = { x: 0, y: 0.55, z: 0 }); p.x = px; p.z = pz; p.y = 0.55;
    var h = this.world.query(p, this.cfg.r, false);
    if (h && !(h.collider && h.collider.ground)) return true;
    for (var i = 0; i < this.list.length; i++) { var o = this.list[i]; if (o === n) continue; var dx = o.x - px, dz = o.z - pz; if (dx * dx + dz * dz < 0.36) return true; }
    return false;
  };

  Manager.prototype._steer = function (n, tx, tz, h, speed) {
    var C = this.cfg, want = Math.atan2(-(tx - n.x), -(tz - n.z)), da = angDiff(n.yaw, want);
    n.yaw += clamp(da, -C.turnRate * h, C.turnRate * h);
    var align = Math.max(0, Math.cos(da));                 // dönerken yavaşla
    var s = speed * align; n.speed += (s - n.speed) * Math.min(1, h * 6);
    n.vx = -Math.sin(n.yaw) * n.speed; n.vz = -Math.cos(n.yaw) * n.speed;
  };

  /* Konum güncelle + dünya ile yatay çarpışma + zıplama */
  Manager.prototype._move = function (n, h) {
    var C = this.cfg;
    if (n.st === ST.IDLE || n.st === ST.TURN || n.st === ST.DETECT) { n.speed *= Math.max(0, 1 - h * 8); n.vx = -Math.sin(n.yaw) * n.speed; n.vz = -Math.cos(n.yaw) * n.speed; }
    n.x += n.vx * h; n.z += n.vz * h;
    var p = this._mp || (this._mp = { x: 0, y: 0.55, z: 0 }); p.x = n.x; p.y = 0.55; p.z = n.z;
    var r = this.world.resolve(p, C.r);
    if (r.hit) { n.x = r.p.x; n.z = r.p.z; }
    // kanyon sınırı (güvenlik)
    var R = this.nav.R, d = Math.hypot(n.x, n.z); if (d > R) { n.x *= R / d; n.z *= R / d; }
    // tepki zıplaması
    if (n.y > 0 || n.jumpV > 0) { n.y += n.jumpV * h; n.jumpV -= 9.8 * h; if (n.y <= 0) { n.y = 0; n.jumpV = 0; } }
    n.phase += h * (1 + n.speed * 3.2);
  };

  /* Oyuncu gövdesini NPC'lerin dışına it (iki yönlü çarpışma: NPC'ler de oyuncudan biraz kaçar) */
  Manager.prototype.collidePlayer = function (body, vel, bodyR) {
    var R = this.cfg.r + bodyR, hit = false;
    for (var i = 0; i < this.list.length; i++) {
      var n = this.list[i]; if (body.y > n.y + 1.5 || body.y < n.y - 0.2) continue;
      var dx = body.x - n.x, dz = body.z - n.z, d = Math.sqrt(dx * dx + dz * dz);
      if (d >= R || d < 1e-6) continue;
      var ux = dx / d, uz = dz / d, pen = R - d;
      body.x += ux * pen * 0.7; body.z += uz * pen * 0.7; n.x -= ux * pen * 0.3; n.z -= uz * pen * 0.3;
      var vn = vel.x * ux + vel.z * uz; if (vn < 0) { vel.x -= vn * ux; vel.z -= vn * uz; }
      hit = true;
    }
    return hit;
  };

  /* ---------- görsel katman (yalnızca tarayıcıda) ----------
     Yakın: eklemli model (gövde+kafa tek mesh, 2 kol + 2 bacak ayrı mesh, omuz/kalçadan döner; 5 çizim çağrısı).
     Uzak (LOD 2): tüm vücut tek statik mesh (1 çizim çağrısı). Geometriler NPC'ler arasında paylaşılır. */
  function makeView(T, ART, mgr, furTex, quality) {
    var reg = [], group = new T.Group(), q = quality == null ? 1 : quality;
    var seg = q === 0 ? 6 : 8, sph = ART.sphP(1, seg, 5), box = ART.boxP(1, 1, 1, 1);
    var mats = {};
    function mat(fur) { var k = fur; if (!mats[k]) { mats[k] = new T.MeshLambertMaterial({ vertexColors: true, map: furTex || null, color: fur }); reg.push(mats[k]); } return mats[k]; }
    function geo(fill) { var b = new ART.Batch(); fill(b); var g = b.geometry(T); reg.push(g); return g; }
    var W = [1, 1, 1], DARK = [0.16, 0.15, 0.17], GRAY = [0.72, 0.72, 0.75];
    // gövde + kafa (tek parça; renk materyalden gelir, köşe rengi beyaz → çarpılır)
    var bodyG = geo(function (b) {
      b.add(sph, { s: [0.4, 0.4, 0.32], t: [0, 0.6, 0.05], c: W });
      b.add(sph, { s: [0.25, 0.26, 0.07], t: [0, 0.63, -0.26], c: GRAY });
      b.add(sph, { s: [0.2, 0.19, 0.19], t: [0, 1.03, -0.12], c: W });
      b.add(sph, { s: [0.14, 0.13, 0.07], t: [0, 1.01, -0.29], c: [0.42, 0.38, 0.4] });
      [-1, 1].forEach(function (s) {
        b.add(sph, { s: [0.04, 0.04, 0.025], t: [s * 0.055, 1.06, -0.345], c: [1.6, 1.6, 1.6] });
        b.add(sph, { s: [0.018, 0.018, 0.012], t: [s * 0.055, 1.06, -0.368], c: [0.02, 0.02, 0.03] });
      });
      b.add(box, { s: [0.2, 0.035, 0.07], t: [0, 1.12, -0.3], c: [0.55, 0.55, 0.55] });
    });
    // kol: pivot omuzda (0,0,0), aşağı-ileri uzanır; el ucu koyu
    var armG = geo(function (b) {
      b.add(ART.cylP(0.085, 0.07, 0.62, 6, 2, true), { t: [0, -0.31, 0], c: W });
      b.add(box, { s: [0.13, 0.07, 0.15], t: [0, -0.64, -0.03], c: DARK });
    });
    var legG = geo(function (b) {
      b.add(ART.cylP(0.11, 0.09, 0.36, 6, 2, true), { t: [0, -0.18, 0], c: W });
      b.add(box, { s: [0.14, 0.07, 0.2], t: [0, -0.37, -0.05], c: DARK });
    });
    var hatG = {};
    function hat(kind) {
      if (!kind || hatG[kind] !== undefined) return hatG[kind] || null;
      var col = { party: [0.95, 0.3, 0.35], bucket: [0.98, 0.85, 0.2], tophat: [0.05, 0.05, 0.06], pie: [0.86, 0.66, 0.34] }[kind] || [1, 1, 1];
      hatG[kind] = geo(function (b) {
        if (kind === 'party') b.add(ART.cylP(0.12, 0.02, 0.26, 8, 1, true), { t: [0, 1.31, -0.1], c: col });
        else if (kind === 'tophat') { b.add(ART.cylP(0.12, 0.12, 0.24, 10, 1, true), { t: [0, 1.32, -0.1], c: col }); b.add(ART.cylP(0.2, 0.2, 0.025, 10, 1, true), { t: [0, 1.2, -0.1], c: col }); }
        else if (kind === 'bucket') { b.add(ART.cylP(0.2, 0.14, 0.12, 8, 1, true), { t: [0, 1.24, -0.1], c: col }); }
        else b.add(ART.cylP(0.17, 0.16, 0.06, 10, 1, true), { t: [0, 1.22, -0.1], c: col });
      });
      return hatG[kind];
    }
    var hatMat = new T.MeshLambertMaterial({ vertexColors: true }); reg.push(hatMat);
    var views = mgr.list.map(function (n) {
      var furHex = n.look.fur || 0x444444, m = mat(furHex), g = new T.Group();
      var body = new T.Mesh(bodyG, m); g.add(body);
      var parts = [];
      [[-0.38, 0.95, 0.0, armG], [0.38, 0.95, 0.0, armG], [-0.2, 0.38, 0.05, legG], [0.2, 0.38, 0.05, legG]].forEach(function (a) {
        var piv = new T.Group(); piv.position.set(a[0], a[1], a[2]); var mm = new T.Mesh(a[3], m); piv.add(mm); g.add(piv); parts.push(piv);
      });
      var hg = hat(n.look.hat); if (hg) { var hm = new T.Mesh(hg, hatMat); g.add(hm); }
      // uzak LOD: aynı model tek mesh (statik poz)
      var far = new T.Mesh(geo(function (b) { ART.addGorilla(b, { x: 0, z: 0, yaw: Math.PI, fur: ART.hex(furHex), hat: n.look.hat, seg: 6 }); }), new T.MeshLambertMaterial({ vertexColors: true, map: furTex || null }));
      reg.push(far.material); far.visible = false;
      group.add(g); group.add(far);
      // gölge lekesi (tek dörtgen, ucuz): ayak altında yumuşak koyu daire
      return { g: g, body: body, parts: parts, far: far };
    });
    var shadowTex = (function () {
      if (typeof document === 'undefined') return null;
      var c = document.createElement('canvas'); c.width = c.height = 64; var x = c.getContext('2d'); if (!x || !x.createRadialGradient) return null;
      var gr = x.createRadialGradient(32, 32, 2, 32, 32, 31); gr.addColorStop(0, 'rgba(0,0,0,0.55)'); gr.addColorStop(1, 'rgba(0,0,0,0)'); x.fillStyle = gr; x.fillRect(0, 0, 64, 64);
      var t = new T.CanvasTexture(c); reg.push(t); return t;
    })();
    var shG = new T.PlaneGeometry(1.1, 1.1); reg.push(shG);
    var shM = new T.MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false, color: 0xffffff }); reg.push(shM);
    var shadows = views.map(function () { var s = new T.Mesh(shG, shM); s.rotation.x = -Math.PI / 2; s.position.y = 0.02; s.renderOrder = 1; group.add(s); return s; });

    return {
      group: group,
      sync: function (time) {
        for (var i = 0; i < mgr.list.length; i++) {
          var n = mgr.list[i], v = views[i], near = n.lod < 2;
          v.g.visible = near && n.visible; v.far.visible = !near && n.visible;
          shadows[i].visible = n.visible && n.lod < 2; shadows[i].position.x = n.x; shadows[i].position.z = n.z;
          var o = near ? v.g : v.far;
          o.position.set(n.x, n.y, n.z); o.rotation.y = n.yaw;
          if (!near || !n.visible) continue;
          // yürüyüş: dörtlü (knuckle-walk) salınım; boşta: nefes + baş; tepki: göğüs vurma
          var w = Math.sin(n.phase * 3.0), amp = Math.min(1, n.speed / 1.2) * 0.55, P = v.parts;
          var beat = n.react > 0 ? Math.sin(time * 18) * 0.5 : 0, wave = n.st === ST.INTERACT ? Math.sin(n.wave * 6) * 0.6 : 0;
          P[0].rotation.x = w * amp + (n.react > 0 ? -1.2 + beat : 0); P[1].rotation.x = -w * amp + (n.react > 0 ? -1.2 - beat : 0) + (wave ? -2.2 + wave * 0.5 : 0);
          P[0].rotation.z = n.react > 0 ? 0.6 : 0; P[1].rotation.z = n.react > 0 ? -0.6 : (wave ? -0.4 : 0);
          P[2].rotation.x = -w * amp * 0.8; P[3].rotation.x = w * amp * 0.8;
          v.body.position.y = n.speed < 0.1 ? Math.sin(time * 1.6 + n.id) * 0.012 : Math.abs(w) * 0.03 * amp;
        }
      },
      dispose: function () { reg.forEach(function (x) { try { x.dispose(); } catch (e) { } }); }
    };
  }

  var API = { ST: ST, STN: STN, CFG: CFG, Nav: Nav, Npc: Npc, Manager: Manager, makeView: makeView };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  root.GorillaNPC = API;
})(typeof window !== 'undefined' ? window : globalThis);
