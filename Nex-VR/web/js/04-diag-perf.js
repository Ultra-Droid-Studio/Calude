'use strict';
  const Diag={
    toast(m,c,ms){
      const t=$('#toast');
      t.textContent=m;
      t.style.color=c||'';
      t.style.display='block';
      clearTimeout(this._t);
      this._t=setTimeout(()=>t.style.display='none',ms||Settings.v.toastms||3800)
    },
    say(t){
      const r=$('#sr');
      r.textContent='';
      setTimeout(()=>{
        r.textContent=t
        },30)
    },
    fail(a,b,h){
      $('#errT').textContent=a;
      $('#errB').textContent=b;
      $('#errH').textContent=h||'';
      $('#err').style.display='flex'
    },
    groups(){
      const y=(b)=>b?'ok':'wn',cam=navigator.mediaDevices&&navigator.mediaDevices.getUserMedia;
      return[
        {g:'Ekran',r:[['Viewport',innerWidth+' × '+innerHeight,'ok'],['Ekran',screen.width+' × '+screen.height,'ok'],['Piksel oranı',String(devicePixelRatio),'ok']]},
        {g:'Güvenlik',r:[['Güvenli bağlam',isSecureContext?'evet':'hayır ('+location.protocol+')',y(isSecureContext)]]},
        {g:'Grafik',r:[['WebGL',Renderer.r?(Renderer.lost?'bağlam kayıp':'çalışıyor'):'yok',Renderer.r&&!Renderer.lost?'ok':'no'],['Render modu','Önizleme / Stereo','ok'],['FPS (ölçülen)',Perf.fps.toFixed(1),'ok'],['Sahne nesnesi',Scene.scene?String(Scene.count()):'-','ok']]},
        {g:'VR',r:[['WebXR','kaldırıldı (artık kullanılmıyor)','na'],['VR modu','Stereo / Cardboard','ok']]},
        {g:'Girdiler',r:[['Yön sensörü API',window.DeviceOrientationEvent?'var':'desteklenmiyor',y(window.DeviceOrientationEvent)],['Sensör modu',Cam.statusText(),Cam.gyro&&Cam.src!=='verify'?'ok':'na'],['Kamera API',cam?'var':'desteklenmiyor',y(cam)],['El takibi',Hand.status,Hand.on?'ok':'na'],['El algılama',Hand.on?Hand.ema.toFixed(0)+' ms / '+Math.round(1000/Hand.iv)+' Hz':'-','na']]},
        {g:'Depolama',r:[['Yerel depolama',Storage.ok?'kullanılabilir':'kullanılamıyor',Storage.ok?'ok':'no'],['CPU / GPU / RAM','Bilinmiyor','na']]}]
    },
    report(){
      let t='NEXUS VR WEB tanı raporu\nTarayıcı: '+navigator.userAgent+'\n';
      this.groups().forEach(g=>{
        t+='['+g.g+']\n';
        g.r.forEach(r=>t+='  '+r[0]+': '+r[1]+'\n')
        });
      return t
    }
  };
  const Perf={
    fps:0,
    f:0,
    t:performance.now(),
    hist:[],
    lo:0,
    hi:0,
    tick(){
      this.f++;
      const n=performance.now();
      if(n-this.t>=500){
        this.fps=this.f*1000/(n-this.t);
        this.f=0;
        this.t=n;
        this.hist.push(this.fps);
        if(this.hist.length>60)this.hist.shift();
        this.auto();
        Quality.step(this.fps)
      }
    },
    /* Stage 61 — otomatik çözünürlük (düzeltildi):
       - hedef fps cihaza göre (cap yoksa 60); eşikler hedefin %70 / %92'si
       - çözünürlük düşürmek fps'e fayda etmediyse (darboğaz el takibi/CPU) adım GERİ ALINIR ve bir süre tekrar düşürülmez
       - her adımdan sonra ölçümün oturması için bekleme (hold); yükseltme 2 sn yeterli (eskiden 5 sn + sabit 55 fps)
       - yükseltmeden hemen sonra tekrar düşme gerekirse (salınım) alt değerde 30 sn kilitlenir */
    hold:0,lock:0,upAt:-1e9,probe:null,
    auto(){
      const v=Settings.v;
      if(!v.autoq||XR.session||!Renderer.r||document.hidden)return;
      const now=performance.now();
      if(now<this.hold)return;
      const phone=Renderer.phone(),stereo=Stereo.on,minS=phone?(stereo?.8:.75):.6;
      const target=App.cap()||60,lowT=target*.7,hiT=target*.92;
      const pr=this.probe;
      if(pr){
        this.probe=null;
        if(pr.dir<0&&this.fps<pr.fps*1.08){
          Renderer.scale=pr.prev;Renderer.resize();
          this.lock=now+45000;this.lo=0;this.hi=0;this.hold=now+1200;
          return
        }
      }
      if(this.fps<lowT){
        this.hi=0;
        if(++this.lo>=3&&Renderer.scale>minS&&now>=this.lock){
          const prev=Renderer.scale;
          if(now-this.upAt<8000)this.lock=now+30000;
          Renderer.scale=Math.max(minS,+(prev-.1).toFixed(1));
          this.probe={fps:this.fps,prev,dir:-1};
          Renderer.resize();
          this.lo=0;this.hold=now+1600
        }
      }
      else if(this.fps>hiT&&Renderer.scale<1){
        this.lo=0;
        if(++this.hi>=4){
          Renderer.scale=Math.min(1,+(Renderer.scale+.1).toFixed(1));
          this.upAt=now;
          Renderer.resize();
          this.hi=0;this.hold=now+1600
        }
      }else{
        this.lo=0;
        this.hi=0
      }
    }
  };
