'use strict';
  /* ---------- Stage 74: kare profilleyici + darboğaz sınıflandırma + uyarlanır kalite + debug monitörü ----------
     Ölçüm her zaman açıktır ama çok ucuzdur: bölüm başına iki performance.now() ve sabit boyutlu dizilere toplama
     (kare başına bellek ayırma yok). Monitör (HUD) kapalıyken DOM'a hiç dokunulmaz. */
  const Prof={
    S:['input','hand','game','phys','npc','ui','render'],
    INPUT:0,HAND:1,GAME:2,PHYS:3,NPC:4,UI:5,RENDER:6,
    acc:new Float64Array(7),avg:new Float64Array(7),peak:new Float64Array(7),
    n:0,fStart:0,lastT:0,
    /* kare aralığı ve CPU süresi (ms, üstel ortalama), düşen kare, açıklanamayan duraksama (GC/sistem şüphesi) */
    dtAvg:16.7,cpuAvg:0,cpuPeak:0,drops:0,dropsWin:0,stalls:0,frames:0,lastDropAt:0,
    gpuMs:-1,gpu:null,
    now(){return performance.now()},
    add(i,t0){this.acc[i]+=performance.now()-t0},
    begin(t){
      const dt=this.lastT?t-this.lastT:16.7;this.lastT=t;
      if(dt>0&&dt<1000){
        this.dtAvg+=(dt-this.dtAvg)*.05;
        const tgt=1000/this.targetHz();
        if(dt>tgt*1.6){this.drops++;this.dropsWin++;this.lastDropAt=t;
          /* normalde akıcıyken TEK uzun kare ve o karede ölçülen JS işi küçük → JS dışı duraksama (çöp toplama,
             shader derleme, sistem). Sürekli yavaşsa bu sayılmaz (o durum GPU/ekran bileşimi darboğazıdır). */
          if(this.cpuLast<tgt*.5&&this.dtAvg<tgt*1.25)this.stalls++}
      }
      this.fStart=performance.now();
      for(let i=0;i<7;i++)this.acc[i]=0
    },
    cpuLast:0,
    end(){
      const cpu=performance.now()-this.fStart;this.cpuLast=cpu;this.frames++;
      this.cpuAvg+=(cpu-this.cpuAvg)*.05;if(cpu>this.cpuPeak)this.cpuPeak=cpu;
      for(let i=0;i<7;i++){const v=this.acc[i];this.avg[i]+=(v-this.avg[i])*.05;if(v>this.peak[i])this.peak[i]=v}
      if(this.gpu)this.gpu.poll()
    },
    targetHz(){const c=App.cap();return c||Dev.hz||60},
    /* her 2 sn'de tepe değerleri sıfırla (monitörde "son 2 sn en kötü") */
    stallsWin:0,_st0:0,
    decay(){this.peak.fill(0);this.cpuPeak=0;this.dropsWin=0;this.stallsWin=this.stalls-this._st0;this._st0=this.stalls},
    /* GPU süresi: yalnızca WebGL zaman sorgusu uzantısı varsa (Android WebView'de çoğu zaman yok → "ölçülemiyor") */
    initGpu(r){
      try{
        const gl=r.getContext(),w2=typeof WebGL2RenderingContext!=='undefined'&&gl instanceof WebGL2RenderingContext;
        const ext=w2?gl.getExtension('EXT_disjoint_timer_query_webgl2'):gl.getExtension('EXT_disjoint_timer_query');
        if(!ext){this.gpuMs=-1;return}
        const P=this;
        this.gpu={q:null,busy:false,
          start(){if(this.busy)return;this.q=w2?gl.createQuery():ext.createQueryEXT();if(w2)gl.beginQuery(ext.TIME_ELAPSED_EXT,this.q);else ext.beginQueryEXT(ext.TIME_ELAPSED_EXT,this.q);this.open=true},
          stop(){if(!this.open)return;this.open=false;if(w2)gl.endQuery(ext.TIME_ELAPSED_EXT);else ext.endQueryEXT(ext.TIME_ELAPSED_EXT);this.busy=true},
          poll(){
            if(!this.busy||!this.q)return;
            const av=w2?gl.getQueryParameter(this.q,gl.QUERY_RESULT_AVAILABLE):ext.getQueryObjectEXT(this.q,ext.QUERY_RESULT_AVAILABLE_EXT),dis=gl.getParameter(ext.GPU_DISJOINT_EXT);
            if(av&&!dis){const ns=w2?gl.getQueryParameter(this.q,gl.QUERY_RESULT):ext.getQueryObjectEXT(this.q,ext.QUERY_RESULT_EXT);const ms=ns/1e6;P.gpuMs=P.gpuMs<0?ms:P.gpuMs+(ms-P.gpuMs)*.1}
            if(av||dis){if(w2)gl.deleteQuery(this.q);else ext.deleteQueryEXT(this.q);this.q=null;this.busy=false}
          }}
      }catch(e){this.gpu=null;this.gpuMs=-1}
    },
    /* Darboğaz tahmini: hedef kare süresine göre en çok neyin taştığı. Kesin değil; ölçülebilen verilerden çıkarım. */
    bottleneck(){
      const tgt=1000/this.targetHz(),fps=1000/Math.max(1,this.dtAvg),ok=fps>=this.targetHz()*.9;
      const why=[];
      if(Quality.thermal>=2)why.push('ısınma (termal '+Quality.thermal+')');
      if(this.gpuMs>tgt*.85)why.push('GPU');
      if(this.cpuAvg>tgt*.7){let m=0;for(let i=1;i<7;i++)if(this.avg[i]>this.avg[m])m=i;why.push('CPU/JS: '+this.S[m])}
      if(Hand.on&&Hand.ema>tgt*1.5)why.push('el takibi çıkarımı');
      if(!ok&&this.cpuAvg<tgt*.5&&this.gpuMs<0)why.push('GPU / ekran bileşimi olası (GPU süresi ölçülemiyor, JS işi küçük)');
      if(this.stallsWin>2)why.push('ara sıra JS dışı duraksama (GC/derleme/sistem)');
      if(!why.length&&!ok)why.push('bilinmiyor');
      return ok&&!why.length?'yok':why.join(', ')
    }
  };
  /* ---------- Uyarlanır kalite: Performans (0) / Dengeli (1) / Kalite (2) ----------
     Cihaz sınıfından başlar; FPS hedefin altında KALICI olarak kalırsa (6 sn) bir kademe iner, uzun süre (25 sn)
     rahatsa ve cihaz ısınmıyorsa bir kademe çıkar. Isınma ciddiyse (termal ≥ 3) hemen iner ve soğuyana kadar çıkmaz.
     Ani gidip gelme yok: her değişimden sonra 10 sn bekleme. El takibi bu kademeden ETKİLENMEZ (öncelikli). */
  const Quality={
    NAMES:['Performans','Dengeli','Kalite'],
    level:1,thermal:0,lo:0,hi:0,hold:0,listeners:[],
    init(){
      const v=Settings.v.gq;
      this.level=v===0||v===1||v===2?v:(Dev.tier>=2?2:Dev.tier>=1?1:0);
      this.hold=performance.now()+8000
    },
    auto(){return !(Settings.v.gq===0||Settings.v.gq===1||Settings.v.gq===2)},
    set(l,why){
      l=clamp(l|0,0,2);if(l===this.level)return;
      this.level=l;this.hold=performance.now()+10000;this.lo=this.hi=0;
      for(const f of this.listeners)try{f(l)}catch(e){}
      if(why)try{Diag.toast('Kalite: '+this.NAMES[l]+' ('+why+')','var(--warn)',2200)}catch(e){}
    },
    on(f){this.listeners.push(f)},
    /* Perf.tick her 0.5 sn çağırır */
    step(fps){
      if(!this.auto()||document.hidden)return;
      const now=performance.now(),tgt=Prof.targetHz();
      if(this.thermal>=3&&this.level>0&&now>this.hold-8000){this.set(this.level-1,'cihaz ısındı');return}
      if(now<this.hold)return;
      if(fps<tgt*.85){this.hi=0;if(++this.lo>=12&&this.level>0)this.set(this.level-1,'FPS düşük')}
      else if(fps>tgt*.97&&this.thermal<2){this.lo=0;if(++this.hi>=50&&this.level<2&&this.level<this.cap())this.set(this.level+1,'FPS rahat')}
      else{this.lo=Math.max(0,this.lo-1);this.hi=Math.max(0,this.hi-1)}
    },
    cap(){return Dev.tier>=2?2:Dev.tier>=1?2:1}
  };
  window.__nxThermal=l=>{Quality.thermal=l|0;if(l>=3&&Quality.auto()&&Quality.level>0)Quality.set(Quality.level-1,'cihaz ısındı')};
  /* ---------- Debug / performans monitörü (Ayarlar → "Performans monitörü") ---------- */
  const PerfHud={
    el:null,t:0,dec:0,ni:null,niAt:0,
    sync(){
      const want=!!Settings.v.pdbg;
      if(want&&!this.el){
        const e=document.createElement('pre');e.id='nxhud';
        e.style.cssText='position:fixed;left:8px;top:calc(8px + env(safe-area-inset-top));z-index:99995;margin:0;padding:8px 10px;max-width:min(92vw,560px);'+
          'background:rgba(0,0,0,.72);color:#e8f2ff;font:11px/1.35 ui-monospace,monospace;border-radius:10px;pointer-events:none;white-space:pre-wrap';
        document.body.appendChild(e);this.el=e
      }else if(!want&&this.el){this.el.remove();this.el=null}
    },
    tick(t){
      if(!this.el)return;
      if(t-this.t<500)return;
      this.t=t;
      if(t-this.dec>2000){this.dec=t;Prof.decay()}
      if(t-this.niAt>1000){this.niAt=t;try{const j=window.AndroidBridge&&AndroidBridge.perfInfo&&AndroidBridge.perfInfo(NX_T);this.ni=j?JSON.parse(j):null}catch(e){this.ni=null}}
      const P=Prof,f=n=>n.toFixed(1),sl=Hand.slots||[],ni=this.ni,mem=performance.memory;
      const hs=i=>{const s=sl[i];if(!Hand.on||!s||!s.on)return '–';const k=s.kv||s.kin;return (s.label==='Right'?'sağ ':s.label==='Left'?'sol ':'')+(s.conf==null?'?':s.conf.toFixed(2))+(s.kin?' (native)':'')+(k?' bük '+Array.from(k.subarray(2,7),x=>Math.round(x*9)).join(''):'')};
      const lines=[
        'FPS '+f(1000/Math.max(1,P.dtAvg))+' / hedef '+P.targetHz()+'  kare '+f(P.dtAvg)+' ms  düşen '+P.drops+' (2sn: '+P.dropsWin+')  duraksama '+P.stalls,
        'CPU kare '+f(P.cpuAvg)+' ms (tepe '+f(P.cpuPeak)+')  GPU '+(P.gpuMs<0?'ölçülemiyor':f(P.gpuMs)+' ms')+'  çözünürlük ×'+Renderer.scale,
        P.S.map((n,i)=>n+' '+f(P.avg[i])).join('  '),
        'El: '+(Hand.on?(Hand.native?'native ':'worker ')+'çıkarım '+Math.round(Hand.ema)+' ms  gecikme '+Math.round(Hand.lat||0)+' ms  sonuç '+(Hand.sInf||0)+'/sn  kamera '+(NHand.camFps||'?')+' fps '+(NHand.camSize||''):'kapalı'),
        'El 1 güven '+hs(0)+'   El 2 güven '+hs(1)+'   landmark '+(Hand.on?sl.filter(s=>s&&s.on).length*21:0),
        'Kalite '+Quality.NAMES[Quality.level]+(Quality.auto()?' (oto)':'')+'  termal '+Quality.thermal+'  darboğaz: '+P.bottleneck(),
        'Pencere '+WM.panels.filter(p=>!p.userData.dock&&!p.userData.kbd).length+'  WebView '+(ni?ni.views:'?')+'  Android uyg. '+(ni?ni.mirrors:'?')+
          '  JS yığın '+(mem?Math.round(mem.usedJSHeapSize/1048576)+' MB':'?')+(ni?'  native '+Math.round(ni.nh/1048576)+' MB  boş RAM '+Math.round(ni.avail/1048576)+' MB'+(ni.low?' (DÜŞÜK)':''):'')
      ];
      if(window.Gorilla&&Gorilla.on&&Gorilla.stats)lines.push(Gorilla.stats());
      this.el.textContent=lines.join('\n')
    }
  };
