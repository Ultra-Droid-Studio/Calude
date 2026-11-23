'use strict';
  /* LOBBY:END */
  const App={
    entered:false,
    last:0,
    lastT:0,
    lq:[0,0,0,0,0],
    async boot(){
      const bar=$('#bar i'),st=$('#stage'),box=$('#stat');
      const row=(k,val,cls)=>{
        const d=document.createElement('div');
        d.innerHTML='<span></span><b class="'+cls+'"></b>';
        d.children[0].textContent=k;
        d.children[1].textContent=val;
        box.appendChild(d)
      };
      const step=(t,p)=>{
        st.textContent=t;
        bar.style.width=p+'%'
      };
      document.documentElement.classList.toggle('rm',!!Settings.v.reduce);
      step('Arayüz hazırlanıyor…',10);
      row('Çalıştırma',location.protocol==='file:'?'file:// — kamera kısıtlı':isSecureContext?'güvenli bağlam':'güvenli değil (kamera çalışmaz)',location.protocol==='file:'||!isSecureContext?'wn':'ok');
      step('three.js yükleniyor…',30);
      const ok=await loadThree();
      if(!ok){
        row('three.js','yüklenemedi','no');
        Diag.fail('three.js yüklenemedi','CDN\'e ulaşılamadı.','İnternet bağlantını kontrol et. Çevrimdışı kullanım için three.min.js (r128) dosyasını index.html ile aynı klasöre koy.');
        return
      }
      step('WebGL kontrol ediliyor…',50);
      Cam.init();
      if(!Renderer.init()){
        row('WebGL','kullanılamıyor','no');
        Diag.fail('WebGL kullanılamıyor','Tarayıcı WebGL bağlamı oluşturamadı.','Donanım hızlandırmayı açın veya başka bir tarayıcı deneyin.');
        return
      }
      row('WebGL','çalışıyor','ok');
      step('3D sahne hazırlanıyor…',65);
      Scene.init();
      Input.init();
      let wp=null;
      try{
        wp=localStorage.getItem('nexus.wp')
      }catch(e){}
      if(Settings.v.wp===-1&&wp)Scene.loadWP(wp,false);
      else Scene.setWP(Math.max(0,Settings.v.wp));
      step('Sensör desteği kontrol ediliyor…',78);
      row('Sensör API',window.DeviceOrientationEvent?'var (izin gerekebilir)':'yok',window.DeviceOrientationEvent?'ok':'wn');
      row('Kamera API',navigator.mediaDevices&&navigator.mediaDevices.getUserMedia?'var (el takibi isteğe bağlı)':'yok',navigator.mediaDevices?'ok':'wn');
      step('VR modu hazırlanıyor…',90);
      XR.ok=false;XR.support='Stereo/Cardboard modu';
      row('VR modu','Stereo (Cardboard) — WebXR kullanılmıyor','ok');
      step('Sistem hazır',100);
      const b=$('#start');
      const go=()=>{try{this.enter()}catch(e){console.error('NEXUS VR açılış hatası',e);Diag.fail('VR başlatılamadı',String(e&&e.message||e)+' @ '+String((e&&e.stack||'').split('\n').slice(1,4).map(x=>x.trim().replace(/^at /,'').slice(-90)).join(' | ')),'Uygulamayı yeniden başlat. Sorun sürerse Tanı ekranındaki hatayı paylaş.')}};
      try{
        Lobby.show(go) /* açılış: başlatıcı sahnesi (Başlat → VR masaüstü) */
      }catch(e){
        console.error('Başlatıcı sahnesi açılamadı, eski açılışa dönüldü',e);
        const ld=$('#load');if(ld)ld.style.display='flex';
        b.disabled=false;
        b.onclick=()=>Intro.run(go);
        b.focus()
      }
    },
    enter(){
      this.entered=true;
      $('#load').style.display='none';
      WebApps.init();
      if(Settings.v.pass)Pass.enable();
      if(Settings.v.awake)Sys.awake(true);
      document.addEventListener('fullscreenchange',()=>{
        if(!document.fullscreenElement&&Stereo.on&&Stereo.fs)Stereo.stop();
        WM.repaintAll()
      });
      WM.create({id:'dock',title:'',icon:'globe',dock:true,chrome:false,span:1.3,h:.36,R:1.8,y:.85,ang:0,gs:.55,tilt:.38,live:true,render:dockRender});Pins.fit();
      const saved=AppState.load();
      if(saved&&saved.length){
        saved.forEach(s=>{
          if(!s||!s.id)return;
          if(s.id.startsWith('app:')){
            if(!WebApps.list.find(a=>a.id===s.id.slice(4)))return
          }else if(!APPS[s.id])return;
          WM.spawn(s.id);
          const m=WM.panels.find(p=>p.userData.id===s.id);
          if(m){
            if(s.max&&!m.userData.max)WM.toggleMax(m);
            if(s.min)WM.minimize(m)
          }
        })
      }else if(saved===null){
        ['browser','settings','help'].forEach(id=>WM.spawn(id))
      }
      WM.layout(Settings.v.layout,true);
      Settings.apply();
      WM.focus(WM.panels[1]||WM.panels[0]||null);
      $('#hstop').onclick=()=>Hand.stop();
      $('#hswitch').onclick=()=>{
        Settings.v.hcam=Settings.v.hcam==='user'?'environment':'user';
        Settings.save();
        $('#hswitch').textContent=Settings.v.hcam==='user'?'Arka kameraya geç':'Ön kameraya geç';
        if(Hand.on)Hand.restart();
        else Diag.toast((Settings.v.hcam==='user'?'Ön':'Arka')+' kamera seçildi; el takibini açınca kullanılır');
      };
      $('#hswitch').textContent=Settings.v.hcam==='user'?'Arka kameraya geç':'Ön kameraya geç';
      let _resizeQueued=false;
      const _safeResize=()=>{if(_resizeQueued)return;_resizeQueued=true;requestAnimationFrame(()=>{_resizeQueued=false;Renderer.resize()})};
      addEventListener('resize',_safeResize,{passive:true});
      addEventListener('orientationchange',()=>setTimeout(_safeResize,250),{passive:true});
      if(window.visualViewport)window.visualViewport.addEventListener('resize',_safeResize,{passive:true});
      document.addEventListener('visibilitychange',()=>{
        Scene.dirty=true;
        if(!document.hidden&&Settings.v.awake&&!Sys.wl)Sys.awake(true);
        if(!document.hidden)Pass.check();
        Renderer.r.setAnimationLoop(document.hidden&&!XR.session?null:t=>this.frame(t))
        });
      addEventListener('pagehide',()=>{
        AppState.save();
        XR.session&&XR.session.end();
        Cam.gyro&&Cam.disableGyro();
        Hand.on&&Hand.stop();
        Pass.suspend();
        Renderer.r.setAnimationLoop(null)
        });
      // Android WebView bazen ilk çizimi sonraki kareye bırakabiliyor; sahneyi zorla yenile.
      Renderer.resize();
      Scene.dirty=true;
      Quality.init();Prof.initGpu(Renderer.r);PerfHud.sync();
      try{Renderer.r.render(Scene.scene,Cam.cam)}catch(renderError){console.error('İlk VR çizimi başarısız',renderError)}
      Renderer.r.setAnimationLoop(t=>this.frame(t));
      setInterval(()=>{
        if(document.hidden)return;
        if(!XR.session)BF.update();
        WM.panels.forEach(p=>p.visible&&p.userData.live&&(XR.session||inV(p))&&WM.paint(p))
      },300)
    },
    cap(){
      const v=Settings.v;
      let c=v.fpscap||0;
      if(v.saver)c=c?Math.min(c,30):30;
      return c
    },
    frame(t){
      if(Renderer.lost)return;
      const cp=XR.session?0:this.cap();
      if(cp&&t-this.lastT<1000/cp-3){Hand.tick(t);return}
      this.lastT=t;
      const dt=Math.min(.1,(t-this.last)/1000||.016);
      this.last=t;
      /* Stage 74: her bölümün CPU süresi ayrı ölçülür (Prof; monitör: Ayarlar → Performans monitörü) */
      Prof.begin(t);
      Perf.tick();
      let p0=Prof.now();
      Input.tick(dt);
      Prof.add(Prof.INPUT,p0);p0=Prof.now();
      Hand.tick(t);
      HMenu.tick();
      Prof.add(Prof.HAND,p0);p0=Prof.now();
      Cinema.tick();
      Game.tick();
      Planets.tick();
      if(window.Gorilla)Gorilla.tick(dt);   /* fizik ve NPC süreleri Gorilla içinde ayrıca PHYS/NPC'ye yazılır */
      Prof.add(Prof.GAME,p0);p0=Prof.now();
      W7Desk.sync();
      Cam.update(dt);
      WM.tick(performance.now());
      if(WM.need){
        WM.need=false;
        for(const p of WM.panels)if(p.visible)WM.paint(p)
      }
      Prof.add(Prof.UI,p0);
      PerfHud.tick(t);
      const q=Cam.cam.quaternion,z=Cam.cam.position.z,L=this.lq,ch=q.x!==L[0]||q.y!==L[1]||q.z!==L[2]||q.w!==L[3]||z!==L[4];
      if(ch){
        L[0]=q.x;
        L[1]=q.y;
        L[2]=q.z;
        L[3]=q.w;
        L[4]=z
      }
      if(!(XR.session||ch||Scene.dirty)){Prof.end();return}
      Scene.dirty=false;
      p0=Prof.now();
      BF.update();
      const G=Prof.gpu;if(G)G.start();
      if(Stereo.on&&!XR.session)Stereo.render(Renderer.r,Scene.scene,Cam.cam);
      else Renderer.r.render(Scene.scene,Cam.cam);
      if(G)G.stop();
      Prof.add(Prof.RENDER,p0);
      Prof.end()
    }
  };
  window.NEXUS={App,Scene,Renderer,Cam,XR,Stereo,Input,WM,BR,Hand,Settings,Storage,Perf,Diag,Game,Planets,Cinema,Launcher,Prof,Quality,PerfHud,HandFeat,HandContour,Pass,NHand};
  App.boot().catch(e=>Diag.fail('Başlatma hatası','Beklenmeyen bir hata oluştu.','Sayfayı yenile. ('+(e&&e.name)+')'));
