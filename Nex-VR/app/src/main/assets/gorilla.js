/* NEXUS VR: GORILLA RUN - oyun katmanı (Aşama 2-4 çekirdeği).
   Bağımlılıklar: window.THREE (r128), window.NEXUS (index.html), window.GorillaPhys (gorilla-phys.js).
   Bu dosya NEXUS'un kendi render döngüsünü kullanır (ikinci bir döngü başlatmaz);
   index.html her karede Gorilla.tick(dt) çağırır. */
(function () {
  'use strict';

  var GAME_NAME = 'NEXUS VR: GORILLA RUN';
  var SAVE_KEY = 'nexus.gorilla.v1';
  var P = window.GorillaPhys, ART = window.GorillaArt;

  /* ---------- SaveSystem: bozuk/eksik kayıt varsayılana döner ---------- */
  var FURS = [0x2a2a30, 0xf06aa8, 0x2cc0f0, 0x3a46e8, 0xe83a26, 0xb44ed8];
  var FURCSS = ['#2a2a30', '#f06aa8', '#2cc0f0', '#3a46e8', '#e83a26', '#b44ed8'];
  var Save = {
    d: null,
    defaults: function () { return { assist: true, sens: 1, debug: false, fur: 0, quality: 'auto', cam: true, camScale: 1 }; },
    load: function () {
      var o = {};
      try { o = JSON.parse(localStorage.getItem(SAVE_KEY) || '{}'); } catch (e) { o = {}; }
      if (!o || typeof o !== 'object' || Array.isArray(o)) o = {};
      var d = this.defaults();
      if (typeof o.assist === 'boolean') d.assist = o.assist;
      if (typeof o.debug === 'boolean') d.debug = o.debug;
      if (typeof o.cam === 'boolean') d.cam = o.cam;
      if (typeof o.sens === 'number' && isFinite(o.sens)) d.sens = Math.min(2.5, Math.max(0.4, o.sens));
      if (typeof o.camScale === 'number' && isFinite(o.camScale)) d.camScale = Math.min(1.6, Math.max(0.6, o.camScale));
      if (typeof o.fur === 'number' && o.fur >= 0 && o.fur < FURS.length) d.fur = o.fur | 0;
      if (o.quality === 'auto' || o.quality === 0 || o.quality === 1 || o.quality === 2) d.quality = o.quality;
      this.d = d;
      return d;
    },
    save: function () { try { localStorage.setItem(SAVE_KEY, JSON.stringify(this.d)); } catch (e) { } }
  };

  var REST = { y: -0.25, z: -0.45, x: 0.34 };   // el dinlenme konumu (yüzeye değmez)
  var FOG = [[18, 62], [20, 82], [24, 110]];     // kalite başına sis (yakın, uzak)
  var RSCALE = [0.8, 0.92, 1];                    // kalite başına çözünürlük çarpanı (yalnızca dokunmatik/ekran modu)

  var G = {
    name: GAME_NAME,
    on: false,
    st: 'off',            // off | menu | play | paused
    N: null, g: null, sim: null, ui: null, prev: null, world: null, player: null, map: null,
    pad: null, look: null, jumpReq: false, resp: 0, dbgT: 0, time: 0,
    xr: false, q: 1, ema: 0.016, qT: 0, qAge: 0, camSide: {}, camGrip: [false, false], camBase: 0, camSeen: [0, 0], camT: 0, xrBtn: [false, false],

    toggle: function () { this.on ? this.exit() : this.enter(); },
    /* index.html: oyun açıkken kamera el verisi oyuna ait; panel etkileşimi üretme */
    ownsHands: function () { return !!(this.on && Save.d && Save.d.cam); },

    /* ---------- yaşam döngüsü ---------- */
    enter: function () {
      if (this.on) return;
      var N = window.NEXUS, T = window.THREE;
      if (!N || !T || !N.Scene || !N.Scene.scene || !N.Cam || !P || !ART) return;
      if (N.Game && N.Game.on) N.Game.exit();
      if (N.Planets && N.Planets.on) N.Planets.exit();
      if (N.Cinema && N.Cinema.on) N.Cinema.exit();
      if (N.Launcher && N.Launcher.open) N.Launcher.close();
      this.N = N;
      Save.load();
      this.xr = !!(N.XR && N.XR.session);
      this.q = this.pickQuality();
      try { this.build(); } catch (e) {
        try { this.dispose(); } catch (e2) { }
        if (N.Diag) N.Diag.toast('Goril sahnesi oluşturulamadı: ' + (e && e.message), 'var(--err)', 4200);
        return;
      }
      var S = N.Scene, C = N.Cam;
      this.prev = {
        vis: N.WM.panels.map(function (m) { return [m, m.visible]; }),
        sky: S.sky.visible, fl: S.floor.visible, rg: S.ring.visible,
        fog: [S.scene.fog.near, S.scene.fog.far, S.scene.fog.color.clone()],
        rig: C.rig.position.clone(), yaw: C.yaw, pitch: C.pitch, zoom: C.zoom,
        rscale: N.Renderer ? N.Renderer.scale : 1
      };
      this.prev.vis.forEach(function (a) { a[0].visible = false; });
      S.sky.visible = S.floor.visible = S.ring.visible = false;
      S.scene.fog.color.set(0xa9b9c6);
      this.applyQuality(this.q, true);
      C.reset();
      this.sim.reset();
      this.resp = 0; this.time = 0; this.ema = 0.016; this.qAge = 0; this.camBase = 0; this.camSide = {}; this.camGrip = [false, false];
      this.g.visible = true;
      try { if (N.Hand && N.Hand.clr) N.Hand.clr(); if (N.Hand && N.Hand.setPreview) N.Hand.setPreview(); } catch (e) { }
      this.on = true;
      this.buildUI();
      this.bindLifecycle();
      this.hookXR(this.xr);
      try { if (N.Hand) { N.Hand.uiOwner = -1; N.Hand.lookOwner = -1; } } catch (e) { }
      this.setState(this.autoPlay() ? 'play' : 'menu');
      if (this.autoPlay() && !this.xr && Save.d.cam) this.ensureCamera(false);   // telefon VR: menü yok, kamera eli hemen
      S.dirty = true;
      try { N.WM.repaintAll(); } catch (e) { }
    },

    autoPlay: function () { var N = this.N; return !!((N.XR && N.XR.session) || (N.Stereo && N.Stereo.on)); },

    exit: function (fromPop) {
      if (!this.on) return;
      var N = this.N, S = N.Scene, C = N.Cam, p = this.prev;
      this.on = false; this.st = 'off';
      this.hookXR(false);
      this.unbindLifecycle(fromPop);
      this.destroyUI();
      if (p) {
        p.vis.forEach(function (a) { a[0].visible = a[1]; });
        S.sky.visible = p.sky; S.floor.visible = p.fl; S.ring.visible = p.rg;
        S.scene.fog.near = p.fog[0]; S.scene.fog.far = p.fog[1]; S.scene.fog.color.copy(p.fog[2]);
        C.rig.position.copy(p.rig); C.yaw = p.yaw; C.pitch = p.pitch; C.zoom = p.zoom;
        if (N.Renderer && p.rscale != null) { N.Renderer.scale = p.rscale; try { N.Renderer.resize(); } catch (e) { } }
      }
      if (this._startedHand) { this._startedHand = false; try { if (N.Hand && N.Hand.on && N.Hand.stop) N.Hand.stop(); } catch (e) { } }
      this.dispose();
      this.prev = null;
      try { if (N.Hand && N.Hand.setPreview) N.Hand.setPreview(); } catch (e) { }
      S.dirty = true;
      try { N.WM.repaintAll(); } catch (e) { }
    },

    /* Android geri tuşu / sayfa gizlenmesi / dokunmatik kaybı */
    bindLifecycle: function () {
      var self = this;
      this._vis = function () { if (document.hidden && self.st === 'play') self.setState('paused'); };
      document.addEventListener('visibilitychange', this._vis);
      this._pushed = false; this._ign = false;
      this._pop = function () {
        if (!self.on) return;
        if (self._ign) { self._ign = false; return; }
        self._pushed = false;
        if (self.st === 'play') { self.setState('paused'); self.pushHist(); }
        else self.exit(true);
      };
      window.addEventListener('popstate', this._pop);
      this.pushHist();
    },
    pushHist: function () { try { history.pushState({ nxg: 1 }, ''); this._pushed = true; } catch (e) { this._pushed = false; } },
    unbindLifecycle: function (fromPop) {
      if (this._vis) document.removeEventListener('visibilitychange', this._vis);
      if (this._pop) window.removeEventListener('popstate', this._pop);
      this._vis = this._pop = null;
      if (this._pushed && !fromPop) { this._ign = true; try { history.back(); } catch (e) { this._ign = false; } }
      this._pushed = false;
    },

    setState: function (s) {
      this.st = s;
      if (s !== 'play') { this.pad.forEach(function (p) { p.id = null; p.grip = false; p.on = false; }); this.look.id = null; this.jumpReq = false; }
      this.renderUI();
    },

    /* ---------- kalite: telefon < tablet < masaüstü/VR; otomatik düşürme ---------- */
    pickQuality: function () {
      var N = this.N, sq = Save.d.quality;
      if (sq === 0 || sq === 1 || sq === 2) return sq;
      if (this.xr) return 1;                                   // Quest sınıfı mobil GPU: orta, 72-90 Hz için
      if (N.Hand && N.Hand.lite) return Math.min(innerWidth, innerHeight) < 600 ? 0 : 1;
      return 2;
    },
    applyQuality: function (q, force) {
      var N = this.N; if (!force && q === this.q) return;
      this.q = q;
      if (this.world) this.world.setQuality(q);
      var f = N.Scene.scene.fog; f.near = FOG[q][0]; f.far = FOG[q][1];
      if (!this.xr && N.Renderer) { N.Renderer.scale = (this.prev ? this.prev.rscale : 1) * RSCALE[q]; try { N.Renderer.resize(); } catch (e) { } }
      N.Scene.dirty = true;
    },
    autoTune: function (dt) {
      this.ema += (Math.min(dt, 0.1) - this.ema) * 0.06;
      this.qAge += dt;
      if (Save.d.quality !== 'auto' || this.qAge < 4 || this.q <= 0) return;
      var limit = this.xr ? 0.0155 : 0.030;                    // 64 FPS (VR) / 33 FPS altına düşerse bir kademe in
      if (this.ema > limit) { this.qT += dt; if (this.qT > 2.5) { this.qT = 0; this.qAge = 0; this.applyQuality(this.q - 1); if (this.N.Diag) this.N.Diag.toast('Akıcılık için görsel kalite düşürüldü', null, 1800); } }
      else this.qT = Math.max(0, this.qT - dt);
    },

    /* ---------- dünya ---------- */
    build: function () {
      var T = THREE, N = window.NEXUS, self = this;
      var map = this.map = P.forestMap(1717);
      this.sim = new P.Sim(new P.World(map.colliders));
      this.sim.spawn = map.spawn; this.sim.reset();

      var g = this.g = new T.Group();
      g.visible = false;
      g.add(new T.HemisphereLight(0xdcecff, 0x5b6638, 0.95));
      var sun = new T.DirectionalLight(0xfff0d2, 0.8); sun.position.set(-10, 30, 14); g.add(sun);

      this.world = ART.buildWorld(T, map, { quality: this.q });
      g.add(this.world.group); this.world.group.visible = true;
      var skyTex = this._ski = N.Scene.grad([[0, '#3f8fe8'], [0.5, '#a9d4fa'], [1, '#e6f3ff']], 8, 128);
      this.sky = new T.Mesh(new T.SphereGeometry(90, 12, 8), new T.MeshBasicMaterial({ map: skyTex, side: T.BackSide, fog: false, depthWrite: false }));
      this.sky.renderOrder = -1;
      g.add(this.sky);
      this.makeAvatar();
      N.Scene.scene.add(g);
    },
    makeAvatar: function () {
      if (this.player) { this.g.remove(this.player.group); this.player.dispose(); }
      if (!this.furTex) this.furTex = this.world.ft2;
      this.player = ART.makePlayer(THREE, FURS[Save.d.fur] || FURS[0], this.furTex);
      this.g.add(this.player.group);
    },

    dispose: function () {
      var N = this.N, g = this.g;
      if (g) {
        if (N && N.Scene && N.Scene.scene) N.Scene.scene.remove(g);
        if (this.world) try { this.world.dispose(); } catch (e) { }
        if (this.player) try { this.player.dispose(); } catch (e) { }
        if (this._ski) try { this._ski.dispose(); } catch (e) { }
        if (this.sky) { try { this.sky.geometry.dispose(); this.sky.material.dispose(); } catch (e) { } }
      }
      this.g = null; this.sim = null; this.world = null; this.player = null; this.sky = null; this._ski = null; this.furTex = null; this.map = null;
    },

    /* ---------- girdi 1: dokunmatik ---------- */
    touchHand: function (i) {
      var p = this.pad[i], side = i === 0 ? -1 : 1, A = this.sim.cfg.arm;
      if (!p.on && !p.grip) return null;
      var dx = p.x - p.ox, dy = p.y - p.oy, x = side * 0.3 + Math.max(-1, Math.min(1, dx / 220)) * 0.25;
      if (p.grip) {
        var y = Math.max(-0.8, Math.min(0.95, 0.1 - dy / 150 * 0.8));
        return [true, side * 0.25, y, -0.5, true];
      }
      var u = Math.max(-0.35, Math.min(1, dy / 150)), z = -0.45 + 0.8 * u;
      return [true, x, -Math.sqrt(Math.max(0.04, A * A - z * z)), z, false];
    },
    restHand: function (i) { return [true, (i === 0 ? -1 : 1) * REST.x, REST.y, REST.z, false]; },

    /* ---------- girdi 2: kamera ile gerçek el takibi (MediaPipe landmark) ----------
       Ekran konumu -> kol yönü, görünen el boyutu -> ileri/geri (kameraya yaklaşan el ileri), yumruk -> tut. */
    ensureCamera: function (toast) {
      var N = this.N, H = N.Hand;
      if (!H) return;
      if (H.on || this._starting) return;
      this._starting = true; var self = this;
      try { var r = H.start && H.start(); this._startedHand = true; if (r && r.then) r.then(function () { self._starting = false; }, function () { self._starting = false; }); else this._starting = false; } catch (e) { this._starting = false; }
      if (toast && N.Diag) N.Diag.toast('Kamera eli açılıyor…', null, 1600);
    },
    camHands: function (dt) {
      var N = this.N, Hd = N.Hand;
      if (!Hd || !Hd.on || !Hd.slots) return null;
      var now = performance.now(), list = [];
      Hd.slots.forEach(function (s) {
        if (!s.on || !s.hasT || !s.dq || now - (s.lastSeen || 0) > 380) return;
        var q = s.dq, w = q[0], m = q[9];
        var sz = Math.hypot((w.x - m.x) * 1.333, w.y - m.y);
        if (!(sz > 0.012)) return;
        var tip = 0, ids = [8, 12, 16, 20];
        for (var k = 0; k < 4; k++) tip += Math.hypot((q[ids[k]].x - w.x) * 1.333, q[ids[k]].y - w.y);
        var cx = (w.x + m.x) / 2, cy = (w.y + m.y) / 2;
        list.push({ id: s.id, sx: Hd.mirror ? 1 - cx : cx, sy: cy, sz: sz, fist: tip / 4 / sz });
      });
      var out = [null, null];
      if (!list.length) return out;
      var sideOf = this.camSide;
      if (list.length >= 2) {
        list.sort(function (a, b) { return a.sx - b.sx; });
        sideOf[list[0].id] = 0; sideOf[list[1].id] = 1; list = [list[0], list[1]];
        list[0].side = 0; list[1].side = 1;
      } else {
        var h = list[0], prev = sideOf[h.id], side = prev != null ? prev : (h.sx < 0.5 ? 0 : 1);
        if (prev === 0 && h.sx > 0.64) side = 1; else if (prev === 1 && h.sx < 0.36) side = 0;
        sideOf[h.id] = side; h.side = side;
      }
      var sc = Save.d.camScale;
      for (var i = 0; i < list.length; i++) {
        var L = list[i];
        if (!this.camBase) this.camBase = L.sz; else this.camBase += (L.sz - this.camBase) * Math.min(1, dt / 6);
        var gripOn = this.camGrip[L.side];
        gripOn = gripOn ? L.fist < 1.85 : L.fist < 1.5;       // histerezis: yumruk = tut
        this.camGrip[L.side] = gripOn;
        var ln = Math.max(-0.7, Math.min(0.7, Math.log(L.sz / this.camBase)));
        out[L.side] = [true, (L.sx - 0.5) * 1.7 * sc, 0.35 - L.sy * 1.3 * sc, -0.35 - ln * 1.0, gripOn];
      }
      return out;
    },

    /* ---------- girdi 3: WebXR denetleyicileri (tracking uzayı; gövde = baş - 0.25 m) ---------- */
    hookXR: function (on) {
      var N = this.N, self = this;
      if (!on) {
        (this._ctrlL || []).forEach(function (a) { try { a[0].removeEventListener('connected', a[1]); } catch (e) { } });
        this._ctrlL = [];
        if (N && N.XR && N.XR.ctrls) N.XR.ctrls.forEach(function (c) { if (c.children[0]) c.children[0].visible = true; });
        return;
      }
      this._ctrlL = [];
      try {
        var xr = N.Renderer.r.xr;
        for (var i = 0; i < 2; i++) {
          var c = xr.getController(i);
          var fn = (function (cc) { return function (e) { cc.userData.nxIS = e.data; }; })(c);
          c.addEventListener('connected', fn); this._ctrlL.push([c, fn]);
        }
      } catch (e) { }
      if (N.XR && N.XR.ctrls) N.XR.ctrls.forEach(function (c) { if (c.children[0]) c.children[0].visible = false; });
    },
    xrHands: function () {
      var N = this.N, out = [null, null];
      try {
        var xr = N.Renderer.r.xr, sess = N.XR.session, cam = N.Cam.cam, head = cam.position;
        for (var i = 0; i < 2; i++) {
          var c = xr.getController(i), is = c.userData.nxIS || (sess && sess.inputSources && sess.inputSources[i]);
          if (!c.visible) continue;
          var side = is && is.handedness === 'left' ? 0 : is && is.handedness === 'right' ? 1 : i;
          var gp = is && is.gamepad, b = gp && gp.buttons, grip = !!(b && ((b[1] && (b[1].pressed || b[1].value > 0.5)) || (b[0] && b[0].value > 0.8)));
          if (b) {
            var jb = !!((b[4] && b[4].pressed) || (b[5] && b[5].pressed));
            if (jb && !this.xrBtn[side]) this.jumpReq = true;
            this.xrBtn[side] = jb;
          }
          out[side] = [true, c.position.x - head.x, c.position.y - head.y + 0.25, c.position.z - head.z, grip];
        }
      } catch (e) { }
      return out;
    },

    tick: function (dt) {
      if (!this.on || !this.sim) return;
      var N = this.N, sim = this.sim, C = N.Cam;
      N.Scene.dirty = true;
      if (!isFinite(dt) || dt <= 0) dt = 1 / 60;
      this.time += dt;
      var xr = !!(N.XR && N.XR.session);
      if (xr !== this.xr) this.onXRChange(xr);
      if (xr) { this._e.setFromQuaternion(C.cam.quaternion, 'YXZ'); this.headYaw = this._e.y; sim.yaw = 0; }
      else { this._e.setFromQuaternion(C.cam.quaternion, 'YXZ'); sim.yaw = this._e.y; this.headYaw = sim.yaw; }
      this.autoTune(dt);
      if (this.world) this.world.update(dt, this.time);
      if (this.st === 'play') {
        var xh = xr ? this.xrHands() : null, ch = !xr && Save.d.cam ? this.camHands(dt) : null;
        for (var i = 0; i < 2; i++) {
          var a = xh && xh[i] ? xh[i] : ch && ch[i] ? ch[i] : this.touchHand(i);
          if (!a) a = this.restHand(i);
          this.camSeen[i] = (xh && xh[i]) || (ch && ch[i]) ? 1 : 0;
          sim.setHand(i, a[0], a[1], a[2], a[3], a[4]);
        }
        if (this.jumpReq) { this.jumpReq = false; if (Save.d.assist) sim.jump(); }
        sim.step(dt);
        if (sim.respawns !== this.resp) { this.resp = sim.respawns; if (N.Diag) N.Diag.toast('Başlangıca döndün', null, 1800); }
      }
      this.sync();
      this.hud(dt);
    },

    onXRChange: function (xr) {
      this.xr = xr;
      this.hookXR(xr);
      if (this.ui) this.ui.root.style.display = xr ? 'none' : '';
      if (xr) { this.applyQuality(Save.d.quality === 'auto' ? 1 : this.pickQuality(), true); this.setState('play'); }
      else { this.applyQuality(this.pickQuality(), true); this.setState('paused'); }
    },

    hud: function (dt) {
      var ui = this.ui; if (!ui) return;
      if ((this.dbgT += dt) < 0.2) return;
      this.dbgT = 0;
      var sim = this.sim, v = sim.vel, h = sim.hands, txt = '';
      if (Save.d.cam && !this.xr && this.st === 'play') txt += 'Kamera eli: sol ' + (this.camSeen[0] ? '✓' : '–') + '  sağ ' + (this.camSeen[1] ? '✓' : '–') + '  (yumruk = tut)';
      if (Save.d.debug) txt += (txt ? '\n' : '') + 'hız ' + Math.hypot(v.x, v.z).toFixed(1) + ' m/s  dikey ' + v.y.toFixed(1) + '  temas ' + (h[0].contact ? 'S' : '-') + (h[1].contact ? 'D' : '-') + (h[0].anchor ? ' tutS' : '') + (h[1].anchor ? ' tutD' : '') + '  ' + (sim.grounded ? 'zeminde' : 'havada') + '  adım ' + sim.lastStepCount + '  kalite ' + ['düşük', 'orta', 'yüksek'][this.q] + '  ' + (1 / Math.max(0.001, this.ema)).toFixed(0) + ' fps';
      ui.dbg.textContent = txt;
    },

    /* fizik durumunu görsel nesnelere ve kameraya aktar */
    sync: function () {
      var sim = this.sim, b = sim.body, N = this.N, C = N.Cam;
      var cy = Math.cos(sim.yaw), sy = Math.sin(sim.yaw), hands = this._hv || (this._hv = [{}, {}]);
      if (this.xr) {
        var hp = C.cam.position;                                  // baş, tracking uzayında: rig'i gövdeye göre kaydır
        C.rig.position.set(b.x - hp.x, b.y + 0.25 - hp.y, b.z - hp.z);
      } else C.rig.position.set(b.x, b.y + 0.25, b.z);
      this.sky.position.set(b.x, b.y, b.z);
      for (var i = 0; i < 2; i++) {
        var H = sim.hands[i], o = hands[i];
        if (H.contact) { o.x = H.pos.x; o.y = H.pos.y; o.z = H.pos.z; }
        else { o.x = b.x + H.L.x * cy + H.L.z * sy; o.y = b.y + H.L.y; o.z = b.z - H.L.x * sy + H.L.z * cy; }
        o.valid = H.valid; o.contact = H.contact; o.grip = !!H.anchor || (H.grip && H.contact); o.n = H.n;
      }
      this.player.pose(b, this.headYaw || 0, hands);
    },

    /* ---------- arayüz (DOM katmanı) ---------- */
    buildUI: function () {
      var self = this, d = document;
      this.pad = [{ id: null, on: false, grip: false, gid: null, ox: 0, oy: 0, x: 0, y: 0 }, { id: null, on: false, grip: false, gid: null, ox: 0, oy: 0, x: 0, y: 0 }];
      this.look = { id: null, x: 0, y: 0 };
      this._e = this._e || new THREE.Euler();
      var css = d.createElement('style'); css.id = 'gor-css';
      css.textContent =
        '#gor{position:fixed;inset:0;z-index:99990;touch-action:none;user-select:none;-webkit-user-select:none;font-family:system-ui,sans-serif;color:#fff}' +
        '#gor *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}' +
        '.gz{position:absolute;touch-action:none}.gpad{bottom:0;width:34%;height:64%}.gpad span{position:absolute;bottom:14px;left:0;right:0;text-align:center;opacity:.55;font-size:13px;letter-spacing:.08em;pointer-events:none}' +
        '.gpad::before{content:"";position:absolute;inset:10px 12px 8px;border:2px dashed rgba(255,255,255,.28);border-radius:28px}' +
        '.gb{position:absolute;min-width:78px;height:52px;padding:0 16px;border-radius:26px;border:2px solid rgba(255,255,255,.55);background:rgba(10,30,20,.55);color:#fff;font:700 15px system-ui;touch-action:none;backdrop-filter:blur(4px)}' +
        '.gb.dn{background:rgba(46,204,113,.75)}' +
        '#gor-m{position:absolute;inset:0;background:rgba(5,15,10,.72);display:flex;align-items:center;justify-content:center;padding:16px;overflow:auto}' +
        '.gcard{width:min(480px,100%);max-height:100%;overflow:auto;padding:22px;border-radius:22px;background:linear-gradient(150deg,#16301f,#0b1a12);border:1px solid rgba(120,230,160,.4)}' +
        '.gcard h2{margin:0 0 4px;font-size:22px}.gcard p{margin:0 0 14px;font-size:13px;opacity:.75;line-height:1.45}' +
        '.gcard button.gm{display:block;width:100%;min-height:50px;margin:8px 0;border-radius:14px;border:0;background:#2ecc71;color:#062010;font:800 16px system-ui}' +
        '.gcard button.gs{background:#26402f;color:#fff;font-weight:600}' +
        '.gcard label{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:10px 0;font-size:14px}' +
        '.gcard select{background:#26402f;color:#fff;border:1px solid rgba(120,230,160,.4);border-radius:10px;padding:8px;font:600 14px system-ui}' +
        '.gsw{display:flex;gap:8px;margin:6px 0 10px}.gsw i{flex:1;height:36px;border-radius:10px;border:3px solid transparent}.gsw i.on{border-color:#fff}' +
        '#gor-d{position:absolute;left:10px;top:calc(8px + env(safe-area-inset-top));font:12px ui-monospace,monospace;text-shadow:0 1px 3px #000;pointer-events:none;white-space:pre}' +
        '#gor-h{position:absolute;left:0;right:0;bottom:8px;text-align:center;font-size:12px;opacity:.7;pointer-events:none;text-shadow:0 1px 3px #000}';
      d.head.appendChild(css);
      var root = d.createElement('div'); root.id = 'gor';
      var lookZ = d.createElement('div'); lookZ.className = 'gz'; lookZ.style.cssText = 'inset:0';
      var pads = [0, 1].map(function (i) {
        var e = d.createElement('div'); e.className = 'gz gpad'; e.style[i === 0 ? 'left' : 'right'] = '0';
        e.innerHTML = '<span>' + (i === 0 ? 'SOL EL' : 'SAĞ EL') + '</span>'; return e;
      });
      var grips = [0, 1].map(function (i) {
        var b = d.createElement('button'); b.className = 'gb'; b.textContent = 'TUT'; b.style.bottom = '66%'; b.style[i === 0 ? 'left' : 'right'] = '3%'; return b;
      });
      var jump = d.createElement('button'); jump.className = 'gb'; jump.textContent = 'ZIPLA'; jump.style.cssText += ';left:50%;bottom:16px;transform:translateX(-50%)';
      var pause = d.createElement('button'); pause.className = 'gb'; pause.textContent = 'II'; pause.style.cssText += ';right:12px;top:calc(8px + env(safe-area-inset-top));min-width:52px;padding:0';
      var dbg = d.createElement('div'); dbg.id = 'gor-d';
      var hint = d.createElement('div'); hint.id = 'gor-h'; hint.textContent = 'Elini kameraya göster: eller ekranda gorilla kollarını oynatır. Yumruk yap = tut. Ya da alt bölgelere dokun.';
      var menu = d.createElement('div'); menu.id = 'gor-m';
      [lookZ].concat(pads, grips, [jump, pause, dbg, hint, menu]).forEach(function (e) { root.appendChild(e); });
      d.body.appendChild(root);
      this.ui = { root: root, menu: menu, dbg: dbg, hint: hint, jump: jump, pause: pause, grips: grips, pads: pads, look: lookZ };
      if (this.xr) root.style.display = 'none';

      var cap = function (el, e) { try { el.setPointerCapture(e.pointerId); } catch (x) { } };
      lookZ.addEventListener('pointerdown', function (e) { if (self.st !== 'play' || self.look.id !== null) return; self.look.id = e.pointerId; self.look.x = e.clientX; self.look.y = e.clientY; cap(lookZ, e); e.preventDefault(); });
      lookZ.addEventListener('pointermove', function (e) {
        if (e.pointerId !== self.look.id) return;
        var k = 0.005 * Save.d.sens, C = self.N.Cam;
        C.yaw -= (e.clientX - self.look.x) * k; C.pitch -= (e.clientY - self.look.y) * k;
        self.look.x = e.clientX; self.look.y = e.clientY; e.preventDefault();
      });
      var endLook = function (e) { if (e.pointerId === self.look.id) self.look.id = null; };
      lookZ.addEventListener('pointerup', endLook); lookZ.addEventListener('pointercancel', endLook);
      pads.forEach(function (el, i) {
        var p = self.pad[i];
        el.addEventListener('pointerdown', function (e) { if (self.st !== 'play' || p.id !== null) return; p.id = e.pointerId; p.on = true; p.ox = p.x = e.clientX; p.oy = p.y = e.clientY; cap(el, e); e.preventDefault(); });
        el.addEventListener('pointermove', function (e) { if (e.pointerId === p.id) { p.x = e.clientX; p.y = e.clientY; e.preventDefault(); } });
        var end = function (e) { if (e.pointerId === p.id) { p.id = null; p.on = false; } };
        el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end);
      });
      grips.forEach(function (el, i) {
        var p = self.pad[i];
        el.addEventListener('pointerdown', function (e) { if (self.st !== 'play') return; p.gid = e.pointerId; p.grip = true; if (!p.on) { p.ox = p.x = e.clientX; p.oy = p.y = e.clientY; } el.classList.add('dn'); cap(el, e); e.preventDefault(); e.stopPropagation(); });
        el.addEventListener('pointermove', function (e) { if (e.pointerId === p.gid && !p.on) { p.x = e.clientX; p.y = e.clientY; } });
        var end = function (e) { if (e.pointerId === p.gid) { p.gid = null; p.grip = false; el.classList.remove('dn'); } };
        el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end);
      });
      jump.addEventListener('pointerdown', function (e) { if (self.st === 'play') self.jumpReq = true; e.preventDefault(); e.stopPropagation(); });
      pause.addEventListener('pointerdown', function (e) { if (self.st === 'play') self.setState('paused'); e.preventDefault(); e.stopPropagation(); });
    },

    destroyUI: function () {
      var d = document, c = d.getElementById('gor-css'), r = d.getElementById('gor');
      if (r) r.remove(); if (c) c.remove();
      this.ui = null;
    },

    renderUI: function () {
      var ui = this.ui, self = this, s = this.st;
      if (!ui) return;
      var play = s === 'play';
      ui.menu.style.display = play ? 'none' : 'flex';
      ['jump', 'pause'].forEach(function (k) { ui[k].style.display = play ? '' : 'none'; });
      ui.grips.forEach(function (b) { b.style.display = play ? '' : 'none'; });
      ui.hint.style.display = play ? '' : 'none';
      ui.dbg.style.display = play ? '' : 'none';
      if (play) return;
      var D = Save.d, cam = D.cam, q = D.quality;
      var sw = FURCSS.map(function (c, i) { return '<i data-a="fur" data-v="' + i + '" style="background:' + c + '"' + (i === D.fur ? ' class="on"' : '') + '></i>'; }).join('');
      var camSt = !cam ? 'kapalı' : (this.N.Hand && this.N.Hand.on ? 'açık (' + (this.N.Hand.status || '') + ')' : 'kamera başlatılacak');
      ui.menu.innerHTML =
        '<div class="gcard"><h2>' + GAME_NAME + '</h2>' +
        '<p>' + (s === 'paused' ? 'Duraklatıldı.' : 'Orman kanyonu: ağaçlara tırman, tahta köprülerde koş, ateşin çevresinde dolan. Eller zemine basıp geri çekilerek ilerletir.') + '</p>' +
        '<button class="gm" data-a="play">' + (s === 'paused' ? 'Devam et' : 'Oyuna başla') + '</button>' +
        '<button class="gm gs" data-a="restart">Haritayı yeniden başlat</button>' +
        '<div style="font-size:13px;opacity:.75;margin-top:6px">Tüy rengi</div><div class="gsw">' + sw + '</div>' +
        '<label>Kamera ile gerçek el takibi<input type="checkbox" data-a="cam"' + (cam ? ' checked' : '') + '></label>' +
        '<p style="margin:-4px 0 8px">Durum: ' + camSt + '. Yumruk = tut. Elini kameraya yaklaştır = ileri uzan.</p>' +
        '<label>El hareket ölçeği<input type="range" min="0.6" max="1.6" step="0.1" value="' + D.camScale + '" data-a="camScale"></label>' +
        '<label>Görsel kalite<select data-a="quality">' + [['auto', 'Otomatik'], [0, 'Düşük (telefon)'], [1, 'Orta (tablet)'], [2, 'Yüksek']].map(function (o) { return '<option value="' + o[0] + '"' + (String(q) === String(o[0]) ? ' selected' : '') + '>' + o[1] + '</option>'; }).join('') + '</select></label>' +
        '<label>Destekli zıplama düğmesi<input type="checkbox" data-a="assist"' + (D.assist ? ' checked' : '') + '></label>' +
        '<label>Bakış hassasiyeti<input type="range" min="0.4" max="2.5" step="0.1" value="' + D.sens + '" data-a="sens"></label>' +
        '<label>Hata ayıklama bilgisi<input type="checkbox" data-a="debug"' + (D.debug ? ' checked' : '') + '></label>' +
        '<button class="gm gs" data-a="exit">NEXUS VR’a dön</button></div>';
      ui.menu.onclick = function (e) {
        var t = e.target, a = t && t.getAttribute && t.getAttribute('data-a');
        if (a === 'play') { if (Save.d.cam) self.ensureCamera(false); self.setState('play'); }
        else if (a === 'restart') { self.sim.reset(); self.resp = self.sim.respawns; self.N.Cam.reset(); if (Save.d.cam) self.ensureCamera(false); self.setState('play'); }
        else if (a === 'exit') self.exit();
        else if (a === 'fur') { Save.d.fur = parseInt(t.getAttribute('data-v'), 10) || 0; Save.save(); self.makeAvatar(); self.renderUI(); }
      };
      ui.menu.onchange = function (e) {
        var t = e.target, a = t && t.getAttribute && t.getAttribute('data-a');
        if (a === 'assist') Save.d.assist = !!t.checked;
        else if (a === 'debug') Save.d.debug = !!t.checked;
        else if (a === 'cam') { Save.d.cam = !!t.checked; if (Save.d.cam) self.ensureCamera(true); }
        else if (a === 'camScale') Save.d.camScale = Math.min(1.6, Math.max(0.6, parseFloat(t.value) || 1));
        else if (a === 'sens') Save.d.sens = Math.min(2.5, Math.max(0.4, parseFloat(t.value) || 1));
        else if (a === 'quality') { Save.d.quality = t.value === 'auto' ? 'auto' : parseInt(t.value, 10); self.applyQuality(self.pickQuality(), true); self.qAge = 0; }
        Save.save();
      };
    }
  };

  window.Gorilla = G;
})();
