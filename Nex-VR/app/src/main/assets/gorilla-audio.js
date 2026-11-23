/* NEXUS VR: GORILLA RUN — Stage 74 konumsal ses (Web Audio, dosya yok: sesler sentezlenir).
   • Ses havuzu: sabit sayıda (6) "ses yolu" (PannerNode + GainNode) bir kez kurulur ve yeniden kullanılır;
     aynı anda en çok 6 ses çalar, doluysa en eskisi kesilir. Kaynaklar (osilatör / gürültü) tek atımlıktır.
   • Aynı türden ses aynı yerde 90 ms içinde tekrar başlatılmaz (art arda temaslarda ses yığılması yok).
   • 30 m'den uzak sesler hiç başlatılmaz. Dinleyici her karede kameraya taşınır (VR'da baş dönüşü doğru eşlenir).
   • Ortam: tek döngüsel rüzgâr (süzülmüş gürültü) + ara sıra ağaçlardan kuş cıvıltısı.
   AudioContext yoksa (eski WebView / Node) her çağrı sessizce hiçbir şey yapmaz. */
(function (root) {
  'use strict';
  var A = {
    ctx: null, out: null, voices: [], noise: null, amb: null, last: {}, birdT: 3, on: false, hq: true,
    init: function (hq) {
      if (this.ctx) return true;
      var AC = root.AudioContext || root.webkitAudioContext;
      if (!AC) return false;
      try {
        var c = this.ctx = new AC();
        this.hq = hq !== false;
        this.out = c.createGain(); this.out.gain.value = 0.8; this.out.connect(c.destination);
        // tek bir gürültü tamponu (0.6 sn), tüm gürültü tabanlı seslerde paylaşılır
        var len = Math.floor(c.sampleRate * 0.6), buf = c.createBuffer(1, len, c.sampleRate), d = buf.getChannelData(0), s = 22222;
        for (var i = 0; i < len; i++) { s = (s * 16807) % 2147483647; d[i] = s / 1073741823.5 - 1; }
        this.noise = buf;
        for (var v = 0; v < 6; v++) {
          var p = c.createPanner();
          p.panningModel = this.hq ? 'HRTF' : 'equalpower';   // düşük seviyede HRTF'nin CPU maliyetinden kaçın
          p.distanceModel = 'inverse'; p.refDistance = 1.5; p.rolloffFactor = 1.1; p.maxDistance = 40;
          var g = c.createGain(); g.gain.value = 0; g.connect(p); p.connect(this.out);
          this.voices.push({ p: p, g: g, until: 0, src: [] });
        }
        return true;
      } catch (e) { this.ctx = null; return false; }
    },
    resume: function () { this.on = true; try { if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume(); } catch (e) { } this.ambient(true); },
    suspend: function () { this.on = false; this.ambient(false); try { if (this.ctx && this.ctx.state === 'running') this.ctx.suspend(); } catch (e) { } },
    setPos: function (node, x, y, z) {
      if (node.positionX) { node.positionX.value = x; node.positionY.value = y; node.positionZ.value = z; } else node.setPosition(x, y, z);
    },
    /* Dinleyici: konum + ileri/yukarı yön */
    listener: function (x, y, z, fx, fy, fz) {
      var c = this.ctx; if (!c || !this.on) return;
      var L = c.listener;
      if (L.positionX) { L.positionX.value = x; L.positionY.value = y; L.positionZ.value = z; L.forwardX.value = fx; L.forwardY.value = fy; L.forwardZ.value = fz; L.upX.value = 0; L.upY.value = 1; L.upZ.value = 0; }
      else { L.setPosition(x, y, z); L.setOrientation(fx, fy, fz, 0, 1, 0); }
      this.lx = x; this.lz = z;
    },
    voice: function () {
      var t = this.ctx.currentTime, best = this.voices[0];
      for (var i = 0; i < this.voices.length; i++) { var v = this.voices[i]; if (v.until <= t) return v; if (v.until < best.until) best = v; }
      best.src.forEach(function (s) { try { s.stop(); } catch (e) { } });
      return best;
    },
    /* kind: 'hoot' | 'beat' | 'tap' | 'bird' ; vol 0..1 ; mat: temas malzemesi (tap tınısı) */
    play: function (kind, x, y, z, vol, mat) {
      var c = this.ctx; if (!c || !this.on) return;
      if (this.lx != null && Math.hypot(x - this.lx, z - this.lz) > 30) return;
      var key = kind + ((x * 2) | 0) + ',' + ((z * 2) | 0), t = c.currentTime;
      if (this.last[key] && t - this.last[key] < 0.09) return;
      this.last[key] = t;
      var v = this.voice(), g = v.g.gain, src = v.src = [], dur = 0.3, V = Math.max(0.05, Math.min(1, vol == null ? 0.7 : vol));
      this.setPos(v.p, x, y, z);
      g.cancelScheduledValues(t); g.setValueAtTime(0, t);
      var osc = function (type, f0, f1, d0, d1) { var o = c.createOscillator(); o.type = type; o.frequency.setValueAtTime(f0, t + d0); o.frequency.exponentialRampToValueAtTime(f1, t + d1); o.connect(v.g); src.push(o); return o; };
      var nz = function (fType, f, q, rate) { var s = c.createBufferSource(); s.buffer = A.noise; if (rate) s.playbackRate.value = rate; var bf = c.createBiquadFilter(); bf.type = fType; bf.frequency.value = f; bf.Q.value = q; s.connect(bf); bf.connect(v.g); src.push(s); return s; };
      if (kind === 'hoot') {            // goril "huu-huu": iki yükselen ton
        dur = 0.75; var o = osc('sine', 260, 430, 0, 0.18); o.frequency.exponentialRampToValueAtTime(300, t + 0.32); o.frequency.setValueAtTime(280, t + 0.38); o.frequency.exponentialRampToValueAtTime(460, t + 0.55); o.frequency.exponentialRampToValueAtTime(320, t + 0.72);
        g.linearRampToValueAtTime(0.5 * V, t + 0.05); g.linearRampToValueAtTime(0.08 * V, t + 0.34); g.linearRampToValueAtTime(0.45 * V, t + 0.42); g.linearRampToValueAtTime(0, t + dur);
      } else if (kind === 'beat') {     // göğüs vurma: 3 boğuk vuruş
        dur = 0.55; var b = nz('lowpass', 180, 1.2, 0.6);
        for (var k = 0; k < 3; k++) { var tk = t + k * 0.16; g.setValueAtTime(0.9 * V, tk); g.exponentialRampToValueAtTime(0.01, tk + 0.12); }
        b.start(t); b.stop(t + dur); src.length = 1;
        v.until = t + dur; return;
      } else if (kind === 'tap') {      // el teması: malzemeye göre tını (tahta parlak, çimen yumuşak, kaya sert)
        dur = 0.12; var f = mat === 'wood' ? 1800 : mat === 'rock' ? 2600 : mat === 'trunk' ? 900 : 500;
        var n = nz('bandpass', f, 1.5, 1);
        g.setValueAtTime(0.8 * V, t); g.exponentialRampToValueAtTime(0.005, t + dur);
        n.start(t); n.stop(t + dur); v.until = t + dur; return;
      } else if (kind === 'bird') {     // kısa cıvıltı
        dur = 0.35; var ob = osc('sine', 2400, 3600, 0, 0.08); ob.frequency.exponentialRampToValueAtTime(2200, t + 0.16); ob.frequency.exponentialRampToValueAtTime(3800, t + 0.26);
        g.linearRampToValueAtTime(0.18 * V, t + 0.03); g.linearRampToValueAtTime(0, t + dur);
      } else return;
      src.forEach(function (s) { s.start(t); s.stop(t + dur + 0.02); });
      v.until = t + dur;
    },
    ambient: function (on) {
      var c = this.ctx; if (!c) return;
      if (on && !this.amb) {
        try {
          var s = c.createBufferSource(); s.buffer = this.noise; s.loop = true; s.playbackRate.value = 0.5;
          var f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 420; var g = c.createGain(); g.gain.value = 0.05;
          s.connect(f); f.connect(g); g.connect(this.out); s.start();
          this.amb = { s: s, g: g };
        } catch (e) { this.amb = null; }
      } else if (!on && this.amb) { try { this.amb.s.stop(); } catch (e) { } this.amb = null; }
    },
    /* her karede: ara sıra kuş sesi (ağaçlardan birinin tepesinden) */
    tick: function (dt, trees, R) {
      if (!this.ctx || !this.on || !trees || !trees.length) return;
      if ((this.gc = (this.gc || 0) + dt) > 10) { this.gc = 0; this.last = {}; }   // tekrar-önleme tablosu büyümesin
      if ((this.birdT -= dt) > 0) return;
      this.birdT = 4 + (R ? R() : Math.random()) * 6;
      var tr = trees[((R ? R() : Math.random()) * trees.length) | 0];
      this.play('bird', tr.x, tr.h * 0.85, tr.z, 0.6);
    },
    dispose: function () { this.ambient(false); try { if (this.ctx) this.ctx.close(); } catch (e) { } this.ctx = null; this.voices = []; this.on = false; this.last = {}; }
  };
  root.GorillaAudio = A;
})(typeof window !== 'undefined' ? window : globalThis);
