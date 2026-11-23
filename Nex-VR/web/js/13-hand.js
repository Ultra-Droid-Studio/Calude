'use strict';
  /* One Euro filtresi (Casiez ve ark.): durgunken titreme yok, hızlı harekette gecikme yok.
     k: değeri "el boyu" birimine çeviren çarpan (1/el boyu). Hız el boyuna göre ölçülür; böylece el kameraya
     yakın da olsa uzak da olsa aynı ayar aynı davranır. (Eski sürümde beta, 0-1 aralığındaki koordinatlara göre
     çok küçüktü: süzgeç hızlı harekete hiç uyum sağlamıyor, sabit ~90 ms gecikme veriyordu.)
     Sağlamlık: sayı olmayan girdi durumu bozmaz, aynı/eski zaman damgası yok sayılır, >250 ms boşlukta el yeniden
     bulunmuş sayılır ve süzgeç yeni konuma oturur. */
  class OE{
    constructor(mc,b,dc,dz){
      this.mc=Math.max(.05,mc);
      this.b=b;
      this.dc=dc||1;
      this.dz=dz>0?dz:0; /* Stage 62: ölçüm gürültüsünün türevi kesme frekansını şişirmesin: hız bu eşiğin altında sayılmaz */
      this.x=null;
      this.dx=0;
      this.t=0
    }
    a(c,dt){
      const r=6.283185307179586*c*dt;
      return r/(r+1)
    }
    f(v,t,k){
      if(!Number.isFinite(v))return this.x===null?v:this.x;
      if(this.x===null){this.x=v;this.t=Number.isFinite(t)?t:0;this.dx=0;return v}
      if(!Number.isFinite(t))return this.x;
      const dt=(t-this.t)/1000;
      if(!(dt>=.004))return this.x;
      if(dt>.25){this.x=v;this.t=t;this.dx=0;return v}
      const raw=((k>0&&Number.isFinite(k))?k:1)*(v-this.x)/dt;
      this.dx+=this.a(this.dc,dt)*(raw-this.dx);
      this.x+=this.a(this.mc+this.b*(this.dz>0?Math.max(0,Math.abs(this.dx)-this.dz):Math.abs(this.dx)),dt)*(v-this.x);
      this.t=t;
      return this.x
    }
    reset(){
      this.x=null;
      this.dx=0;
      this.t=0
    }
  }
  /* ---------- Kamera tabanlı el takibi (MediaPipe Hand Landmarker) ---------- */
  /* MediaPipe CPU/GPU delegate seçimini kütüphaneye bırakır; iki el için numHands: 2. */
  const HandCache={
    name:'nexus-hand-v4-mediapipe',
    ok:false,
    native:window.fetch.bind(window),
    async fetch(url,init){
      const res=await this.native(url,init);
      if(res&&res.ok&&this.onprog){
        try{
          const tot=+res.headers.get('content-length')||0,rd=res.clone().body.getReader(),nm=url.split('/').pop().split('?')[0];
          let n=0;
          (async()=>{
            for(;;){
              const r=await rd.read();
              if(r.done)break;
              n+=r.value.length;
              this.onprog(nm+' indiriliyor: '+(n/1048576).toFixed(1)+(tot?' / '+(tot/1048576).toFixed(1):'')+' MB')
            }
          })().catch(()=>{})
        }catch(e){}
      }
      return res
    },
    async clear(){
      try{
        if(window.caches)await caches.delete(this.name)
      }catch(e){}
    }
  };
  /* ---------- Kamera arka planı (passthrough): arka plan kürenin yerine kamera görüntüsü; paneller ve dock havada durur ---------- */
  /* Stage 38: kamera mümkün olan en yüksek kare hızında (en çok 60) açılır; gerçek hız okunur ve çıkarım aralığı buna göre ayarlanır. */
  const CamFps={
    cur:30,hi:false,
    rate(){return {ideal:60,max:60}},
    read(track){
      try{const f=track&&track.getSettings&&track.getSettings().frameRate;if(f>0)this.cur=Math.round(f)}catch(e){}
      return this.cur
    },
    floor(){return clamp(Math.round(850/this.cur),10,30)}
  };
  /* ---------- Stage 44: Native kamera + MediaPipe (Android) ----------
     Kamera ve MediaPipe Android tarafında (CameraX + HandLandmarker GPU) çalışır; sonuçlar bir MessagePort ile gelir.
     Kamera arka planı WebView'in ARKASINDAKİ native önizlemedir (sayfa saydamlaşır). Native yol açılamazsa
     (model yok, izin yok, GPU+CPU başarısız, VR-stereo modu) eski Worker + getUserMedia yolu aynen kullanılır. */
  const NHand={
    ok:false,dead:false,port:null,pend:null,q:Promise.resolve(),delegate:'',camFps:0,camSize:'',
    avail(){
      if(!this.ok){try{this.ok=!!(NX_T&&window.AndroidBridge&&AndroidBridge.nativeCamAvailable&&AndroidBridge.nativeCamAvailable(NX_T))}catch(e){this.ok=false}}
      return this.ok
    },
    usable(){return !this.dead&&this.avail()&&!Stereo.on&&!XR.session},
    bind(p){
      if(this.port){try{this.port.onmessage=null;this.port.close()}catch(e){}}
      this.port=p;p.onmessage=ev=>this.msg(ev.data)
    },
    msg(s){
      if(typeof s!=='string')return;
      if(s.charCodeAt(0)===82){
        /* Stage 45: ack — native tarafta yolda en çok 2 sonuç kalır; JS takılırsa eskiler birikmez, yalnızca en yenisi gelir. */
        const pt=this.port;if(pt){try{pt.postMessage('a')}catch(e){}}
        if(Hand.on&&Hand.native)Hand.onNative(s);return}
      const a=s.split('|');
      if(a[0]!=='S')return;
      if(a[1]==='ready'||a[1]==='err'){
        const p=this.pend;
        if(p){this.pend=null;clearTimeout(p.to);if(a[1]==='ready')p.res(a[2]||'');else p.rej(new Error(a.slice(2).join('|')||'native kamera hatası'))}
        else if(a[1]==='err'&&Hand.on&&Hand.native)Hand.nativeFailed(a.slice(2).join('|'))
      }else if(a[1]==='fps'){this.camFps=+a[2]||0;this.camSize=a[3]||''}
    },
    opts(w){
      const l=!!Hand.lite;
      return {fac:Settings.v.hcam||'environment',prev:w.prev,hand:w.hand,hands:Settings.v.hone?1:2,q:clamp(Settings.v.hcq|0,0,2),lite:l,det:l?.45:.42,pres:l?.45:.42,trk:l?.4:.4}
    },
    send(o){
      return new Promise((res,rej)=>{
        const p=this.pend={res,rej,to:setTimeout(()=>{if(this.pend===p){this.pend=null;rej(new Error('native kamera zaman aşımı'))}},15000)};
        try{AndroidBridge.nativeCamStart(NX_T,JSON.stringify(o))}catch(e){clearTimeout(p.to);this.pend=null;rej(e)}
      })
    },
    /* İstenen duruma (arka plan / el) göre native kamerayı yapılandırır; istekler sıraya girer. */
    sync(){
      const run=()=>{
        const w={prev:!!Pass.bg,hand:!!(Hand.on||Hand.booting)};
        if(!w.prev&&!w.hand){this.stopNative();Pass.nat=false;Pass.apply();return Promise.resolve('off')}
        return this.send(this.opts(w))
      };
      return this.q=this.q.catch(()=>{}).then(run)
    },
    stopNative(){try{AndroidBridge.nativeCamStop(NX_T)}catch(e){}},
    fail(e){
      this.dead=true;this.stopNative();
      Pass.nat=false;document.documentElement.classList.remove('npass');
      try{Diag.toast('Native kamera kullanılamadı, eski yönteme geçildi: '+((e&&e.message)||e),'var(--warn)',6000)}catch(_){}
      if(Hand.on&&Hand.native){Hand.native=false;setTimeout(()=>{try{Hand.restart()}catch(_){}},0)}
    },
    /* VR-stereo açılıp kapanınca (stereo native önizlemeyle yapılamaz) doğru yola geç. */
    migrate(){
      try{
        const u=this.usable();
        if(Hand.on){if(!!Hand.native!==u)Hand.restart()}
        else if(Pass.bg&&!!Pass.nat!==u){Pass.on=false;Pass.enable()}
      }catch(e){}
    }
  };
  addEventListener('message',e=>{if(NX_T&&e.data==='nxport:'+NX_T&&e.ports&&e.ports[0])NHand.bind(e.ports[0])});
  const Pass={
    stream:null,fac:null,bg:false,hand:false,on:false,pending:null,nat:false,
    vids(){
      return[$('#pass'),$('#pass2')]
    },
    toNative(){
      if(this.stream){try{this.stream.getTracks().forEach(t=>t.stop())}catch(e){}this.stream=null;this.fac=null}
      this.vids().forEach(v=>{v.srcObject=null});
      this.nat=true;if(this.bg)this.on=true;
      this.apply()
    },
    live(){
      if(this.nat)return true;
      return !!this.stream&&this.stream.getVideoTracks().some(t=>t.readyState==='live')
    },
    async acquire(fac){
      if(this.nat){NHand.stopNative();this.nat=false;document.documentElement.classList.remove('npass')}
      if(this.pending)await this.pending.catch(()=>{});
      if(this.live()&&this.fac===fac)return this.stream;
      this.pending=(async()=>{
        if(this.stream)this.stream.getTracks().forEach(t=>t.stop());
        this.stream=null;
        const gum=f=>navigator.mediaDevices.getUserMedia({video:{facingMode:f,width:{ideal:320,max:480},height:{ideal:240,max:360},frameRate:CamFps.rate()},audio:false});
        let st=null;
        CamFps.hi=false;
        /* Stage 38b: 320x240'ta birçok telefon yalnızca 30 fps modu sunar; 60 fps modları genelde 640x480 ve üstündedir.
           frameRate.min:50 sert kısıt olduğu için ya gerçekten >=50 fps veren bir mod seçilir ya da hata verip eski yola düşer. */
        /* Stage 40: Kamera kalitesi (Settings.v.hcq): 0 = 640x480, 1 = 1280x720, 2 = 1920x1080.
           Yalnızca görüntünün (arka plan/önizleme) netliğini etkiler; MediaPipe'a giden kare her zaman 320 px'e küçültülür,
           yani el takibi hızı değişmez. Yüksek profil >=50 fps vermezse >=30 fps, o da olmazsa bir alt profil denenir. */
        const RES=[[640,480],[1280,720],[1920,1080]],q=clamp(Settings.v.hcq|0,0,2);
        const ladder=[];
        for(let k=q;k>=0;k--){ladder.push([RES[k],50]);if(k>0)ladder.push([RES[k],30])}
        for(const [[rw,rh],mf] of ladder){
          for(const fm of (fac==='environment'?[{exact:'environment'},{ideal:fac}]:[{ideal:fac}])){
            try{
              const s2=await navigator.mediaDevices.getUserMedia({video:{facingMode:fm,width:{ideal:rw,max:rw*(rw<1000?2:1)},height:{ideal:rh,max:rh*(rw<1000?1.5:1)},frameRate:{min:mf,ideal:60,max:60}},audio:false});
              if(CamFps.read(s2.getVideoTracks()[0])>=mf){st=s2;CamFps.hi=true;break}
              s2.getTracks().forEach(t=>t.stop())
            }catch(e){}
          }
          if(st)break
        }
        if(!st)try{
          st=await gum(fac==='environment'?{exact:'environment'}:{ideal:fac})
        }catch(e){
          if(e&&/Overconstrained|NotFound|ConstraintNotSatisfied/.test(e.name))st=await gum({ideal:fac});
          else throw e
        }
        this.stream=st;
        this.fac=fac;
        return st
      })();
      try{
        return await this.pending
      }finally{
        this.pending=null
      }
    },
    attach(){
      let mir=true;
      try{
        mir=this.stream.getVideoTracks()[0].getSettings().facingMode!=='environment'
      }catch(e){}
      this.vids().forEach(v=>{
        v.srcObject=this.stream;
        v.style.transform=mir?'scaleX(-1)':'none';
        v.play().catch(()=>{})
      });
      this.on=true;
      this.apply();
      let f='';
      try{
        f=this.stream.getVideoTracks()[0].getSettings().facingMode||''
      }catch(e){}
      const nm=f==='environment'?'Arka kamera':f==='user'?'Ön kamera':'Kamera';
      if(this.fac==='environment'&&f==='user')Diag.toast('Ön kamera açıldı: bu cihazda arka kamera seçilemedi','var(--warn)',5000);
      else Diag.toast(nm+' açıldı','var(--ok)',2000)
    },
    apply(){
      if(Scene.sky)Scene.sky.visible=!(this.on&&!XR.session);
      document.body.classList.toggle('pass',this.on);
      document.documentElement.classList.toggle('npass',!!(this.on&&this.nat));
      WM.repaintAll();
      Scene.dirty=true
    },
    async enable(){
      this.bg=true;
      if(NHand.usable()){
        try{
          await NHand.sync();
          if(!this.bg){NHand.sync().catch(()=>{});return}
          this.toNative();
          Diag.toast('Kamera açıldı (native)','var(--ok)',2000);
          return
        }catch(e){NHand.fail(e)}
      }
      if(!navigator.mediaDevices||!navigator.mediaDevices.getUserMedia){
        this.bg=false;
        Diag.toast('Kamera API’si yok (HTTPS/localhost gerekir); duvar kağıdı kullanılıyor','var(--warn)',5000);
        return
      }
      try{
        await this.acquire(Settings.v.hcam||'environment')
      }catch(e){
        this.bg=false;
        this.on=false;
        this.apply();
        Diag.toast('Kamera açılamadı ('+((e&&e.name)||'hata')+'); duvar kağıdı kullanılıyor. Dock’taki Kamera düğmesiyle tekrar dene','var(--warn)',7000);
        return
      }
      if(!this.bg){
        this.release();
        return
      }
      this.attach()
    },
    disable(){
      this.bg=false;
      this.on=false;
      if(this.nat)NHand.sync().catch(()=>{});
      this.vids().forEach(v=>{
        v.srcObject=null
      });
      this.apply();
      this.release()
    },
    release(){
      if(this.bg||this.hand||!this.stream)return;
      this.stream.getTracks().forEach(t=>t.stop());
      this.stream=null;
      this.fac=null
    },
    refresh(){
      if(this.bg)this.enable()
    },
    suspend(){
      if(this.nat)return;
      if(this.stream)this.stream.getTracks().forEach(t=>t.stop());
      this.stream=null;
      this.fac=null
    },
    check(){
      if(!this.bg)return;
      if(!this.live())this.enable();
      else this.vids().forEach(v=>v.play().catch(()=>{}))
    }
  };
  /* Quest kontrolcü modeli (Stage 72, GERÇEK 3B): el/parmak/eklem YOK. Three.js ile düşük poligonlu (≈10 mesh) kontrolcü kurulur;
     geometri ve malzemeler tüm slotlarda paylaşılır, kontrolcü kameranın çocuğudur (stereo/VR'da iki göze de otomatik girer).
     Kontrolcü bilek konumunda durur ve imlecin baktığı noktaya doğru döner (ışın = kontrolcünün baktığı yön). */
  const _NO=new Float64Array(2);
  let _c3g=null,_c3m=null,_c3t=null;
  function nexC3Geo(T){
    if(_c3g)return _c3g;
    const ray=new T.CylinderGeometry(.0013,.0013,1,6);ray.rotateX(Math.PI/2);ray.translate(0,0,.5);
    return _c3g={
      handle:new T.CylinderGeometry(.0185,.0145,.105,16),pommel:new T.SphereGeometry(.0145,12,8),
      head:new T.SphereGeometry(.03,18,12),plate:new T.CylinderGeometry(.025,.025,.004,24),
      stickB:new T.CylinderGeometry(.0065,.0075,.005,12),stickC:new T.SphereGeometry(.0075,12,6),
      btn:new T.CylinderGeometry(.0042,.0042,.003,12),ring:new T.TorusGeometry(.043,.0085,10,32),
      trig:new T.SphereGeometry(.012,12,8),ray:ray,dot:new T.CircleGeometry(1,24)}
  }
  function nexC3Mat(T){
    return _c3m||(_c3m={
      white:new T.MeshPhongMaterial({color:0xf3f4f7,emissive:0x2a2c31,shininess:55,specular:0x888c96}),
      dark:new T.MeshPhongMaterial({color:0x17181b,emissive:0x060607,shininess:80,specular:0x555a66}),
      ray:new T.MeshBasicMaterial({color:0xffffff,transparent:true,opacity:.6,depthWrite:false}),
      dot:new T.MeshBasicMaterial({color:0xffffff,transparent:true,depthTest:false,depthWrite:false}),
      halo:new T.MeshBasicMaterial({color:0x000000,transparent:true,opacity:.45,depthTest:false,depthWrite:false})})
  }
  /* Bir slot için kontrolcü + ışın + nokta kurar; hepsi parent'a (kamera) eklenir. */
  function nexCtrl3D(T,parent){
    const G=nexC3Geo(T),M=nexC3Mat(T),g=new T.Group();
    const m=(geo,mat,x,y,z)=>{const o=new T.Mesh(geo,mat);o.position.set(x,y,z);o.matrixAutoUpdate=true;return o};
    const handle=m(G.handle,M.white,0,-.046,.022);handle.rotation.x=-.45;g.add(handle);
    g.add(m(G.pommel,M.white,0,-.0933,.0448));
    const head=m(G.head,M.white,0,.004,0);head.scale.set(1.1,.75,1.25);g.add(head);
    const plate=m(G.plate,M.dark,0,.025,.0045);plate.rotation.x=.55;g.add(plate);
    plate.add(m(G.stickB,M.dark,.011,.0045,-.003));
    const cap=m(G.stickC,M.dark,.011,.0085,-.003);cap.scale.y=.5;plate.add(cap);
    plate.add(m(G.btn,M.dark,-.014,.0035,-.011));
    plate.add(m(G.btn,M.dark,-.009,.0035,.006));
    const ring=m(G.ring,M.white,0,.0354,-.0125);ring.rotation.x=-1.02;g.add(ring);
    const trigMat=M.white.clone(),trig=m(G.trig,trigMat,0,-.014,-.016);trig.scale.set(.7,1.1,.55);g.add(trig);
    g.visible=false;parent.add(g);
    const ray=new T.Mesh(G.ray,M.ray);ray.visible=false;ray.frustumCulled=false;parent.add(ray);
    const dotMat=M.dot.clone(),dot=new T.Mesh(G.dot,dotMat),halo=new T.Mesh(G.dot,M.halo);
    halo.scale.setScalar(1.45);halo.renderOrder=999;dot.renderOrder=1000;dot.add(halo);
    dot.visible=false;parent.add(dot);
    return{g,ray,dot,dotMat,trig,trigMat,pin:null,vis:false}
  }
  /* Kontrolcüyü kamera uzayında yerleştirir ve imlece çevirir.
     o: nx,ny = bilek NDC; sr = avuç boyu/ekran yüksekliği; cx,cy = imleç NDC; dist = pencerenin uzaklığı (0 = yok);
     cursor = nokta/ışın görünsün mü; pinch; right. */
  function nexCtrl3DPlace(T,c,cam,o){
    const e=cam.projectionMatrix.elements,k=_c3t||(_c3t={p:new T.Vector3(),t:new T.Vector3(),f:new T.Vector3(),d:new T.Vector3(),
      q:new T.Quaternion(),r:new T.Quaternion(),zb:new T.Vector3(0,0,-1),zf:new T.Vector3(0,0,1)});
    const d=Math.min(.8,Math.max(.45,.12/Math.max(o.sr,.04))),D=o.dist||1.8,sc=1.25;
    k.p.set(o.nx*d/e[0],o.ny*d/e[5],-d);
    k.t.set(o.cx*D/e[0],o.cy*D/e[5],-D);
    k.f.copy(k.t).sub(k.p).normalize();
    k.q.setFromUnitVectors(k.zb,k.f);
    k.r.setFromAxisAngle(k.zb,o.right?-.25:.25);k.q.multiply(k.r);
    c.g.position.copy(k.p);c.g.quaternion.copy(k.q);c.g.scale.set(o.right?sc:-sc,sc,sc);c.g.visible=true;c.vis=true;
    if(c.pin!==o.pinch){
      c.pin=o.pinch;c.trig.position.z=o.pinch?-.011:-.016;
      c.trigMat.emissive.setHex(o.pinch?0x19d3c5:0x2a2c31);c.dotMat.color.setHex(o.pinch?0x19d3c5:0xffffff)
    }
    if(o.cursor){
      k.d.copy(k.f).multiplyScalar(.07*sc).add(k.p);            /* ışının çıktığı uç */
      c.ray.position.copy(k.d);
      k.f.copy(k.t).sub(k.d);const L=k.f.length()||1;k.f.multiplyScalar(1/L);
      c.ray.scale.z=L;c.ray.quaternion.setFromUnitVectors(k.zf,k.f);c.ray.visible=true;
      c.dot.position.copy(k.t);c.dot.scale.setScalar(.011*D);c.dot.visible=true
    }else{c.ray.visible=false;c.dot.visible=false}
  }
  function nexCtrl3DHide(c){c.g.visible=false;c.ray.visible=false;c.dot.visible=false;c.vis=false}
    const Hand={
    on:false,
    lm:null,
    hitRC:null,
    stream:null,
    pinch:false,
    resizeGesture:null,
    last:0,
    status:'kapalı',
    sx:.5,
    sy:.5,
    mirror:true,
    /* Sol/sağ kontrolcü modeli ters görünüyorsa true yap (kamera/ayna durumuna göre MediaPipe etiketi değişebilir). */
    ctrlFlip:false,
    spaceHold:false,
    lookHold:false,
    lookX:0, lookY:0,
    /* Stage 72: el/iskelet yok; Three.js'te yalnızca kontrolcü modeli (c3) çizilir. */
    c3:[],
    hide3D(){
      let ch=false;
      for(const c of this.c3)if(c&&c.vis){nexCtrl3DHide(c);ch=true}
      if(ch)Scene.dirty=true
    },
    async start(){
      if(this.on||this.booting)return;
      if(!navigator.mediaDevices||!navigator.mediaDevices.getUserMedia){
        this.status='kamera API yok';
        Diag.toast('Kamera API\'si yok (HTTPS/localhost gerekir)','var(--err)');
        return
      }
      if(XR.session){
        Diag.toast('El takibi VR dışında çalışır','var(--warn)');
        return
      }
      if(!this.asked&&!confirm('El takibi arka kamerayı (yoksa mevcut kamerayı) yalnızca bu cihazda el konumunu bulmak için kullanır; görüntü kaydedilmez veya gönderilmez. Kütüphane ve model internetten (jsDelivr, Google) indirilir. Kamerayı açmak istiyor musun?'))return;
      this.asked=true;
      /* Stage 71: bir defalık — eski ayardan kalan 'El çizimi kapalı' değeri eli görünmez yapıyordu. */
      if(!Settings.v.hdraw2){Settings.v.hdraw=true;Settings.v.hdraw2=true;try{Settings.save()}catch(e){}}
      /* Stage 44: önce native yol (kamera + MediaPipe Android tarafında). Olmazsa aşağıdaki eski yol çalışır. */
      if(NHand.usable()){
        this.booting=true;this.status='Native el takibi hazırlanıyor…';
        try{
          const d=await NHand.sync();
          if(!this.booting)return;
          this.booting=false;this.native=true;NHand.delegate=d||'';
          this.mirror=(Settings.v.hcam||'environment')!=='environment';
          Pass.hand=true;Pass.toNative();
          this.initF();this.q2=null;this.q2t=0;
          this.hitRC=this.hitRC||new THREE.Raycaster();
          this.workerReady=true;this.on=true;
          this.frameSeenAt=performance.now();this.vt=-1;this.recovering=false;this.sw=0;this.infN=0;this.sToast=0;
          const hv=$('#hv');if(hv)hv.style.display='none';
          Renderer.resize();
          this.status='Native iki el takibi açık ('+(NHand.delegate||'?')+')';
          WM.repaintAll();
          Diag.toast('Native el takibi etkin ('+(NHand.delegate||'?')+')','var(--ok)');
          return
        }catch(e){
          this.booting=false;this.native=false;
          NHand.fail(e)
        }
      }
      this.status='kamera izni bekleniyor';
      try{
        this.stream=await Pass.acquire(Settings.v.hcam||'environment');
        /* Enforce a modest camera workload on mobile; inference needs landmarks, not HD video. */
        try{const track=this.stream.getVideoTracks()[0];if(!CamFps.hi&&track&&track.applyConstraints)await track.applyConstraints({width:{ideal:this.lite?320:480,max:this.lite?480:640},height:{ideal:this.lite?240:360,max:this.lite?360:480},frameRate:CamFps.rate()})}catch(e){}
        try{CamFps.read(this.stream.getVideoTracks()[0]);Diag.toast('Kamera '+CamFps.cur+' FPS','var(--ok)',2500)}catch(e){}
        Pass.hand=true;
        try{this.stream.getVideoTracks().forEach(tr=>tr.addEventListener('ended',()=>{if(this.on)this.recoverCamera()},{once:true}))}catch(e){}
      }
      catch(e){
        this.status='kamera izni reddedildi';
        Diag.toast('Kamera izni reddedildi veya kamera yok','var(--err)');
        return
      }
      const v=$('#hvid');
      v.srcObject=this.stream;
      try{
        this.mirror=this.stream.getVideoTracks()[0].getSettings().facingMode!=='environment'
      }catch(e){
        this.mirror=true
      }
      v.style.transform=this.mirror?'scaleX(-1)':'none';
      await v.play().catch(()=>{});
      $('#hv').style.display=Settings.v.hprev?'block':'none';
      const st=t=>{
        const msg=/indir|deneniyor|sunucu|çalışma\/model|kitaplık|wasm|hand_landmarker/i.test(String(t))?'Canlı el takibi hazırlanıyor…':String(t);
        this.status=msg;
        const e=$('#hstat');
        if(e)e.textContent=msg
      };
      st('Canlı el takibi hazırlanıyor…');
      try{
        if(!MPLocal.files){const saved=await MPdb.get('files');if(saved&&saved.length){try{await applyLocalFiles(saved)}catch(e){}}}
        if(!MPLocal.files){try{await loadBundledMediaPipe(st)}catch(e){}}
        if(!MPLocal.files){try{await probeMediaPipeHosts(st)}catch(e){}try{await autoDownloadMediaPipe(st)}catch(e){}}
        await this.startWorker(st);
      }catch(e){
        this.workerReady=false;
        if(this.worker){this.worker.terminate();this.worker=null}
        this.stop();this.status='El takip motoru yüklenemedi';
        const msg=(e&&e.message)||String(e);
        Diag.toast('El takibi başlatılamadı: '+msg,'var(--err)',18000);
        const stat=$('#hstat');if(stat)stat.textContent='Yükleme hatası: '+msg;
        return
      }
      this.initF();
      this.q2=null;this.q2t=0;
      this.hitRC=this.hitRC||new THREE.Raycaster();
      /* Mobile-first camera profile: 320x240 and 20fps cap reduce heat and battery use. */
      if(this.lite||MPLocal.delegate==='CPU'){let tr=null;try{tr=this.stream.getVideoTracks()[0];if(!CamFps.hi&&tr&&tr.applyConstraints)await tr.applyConstraints({width:{ideal:320,max:480},height:{ideal:240,max:360},frameRate:CamFps.rate()})}catch(e){}try{CamFps.read(tr)}catch(e){}}
      /* Worker kendi içinde tek ısınma döngüsünü yapar; UI thread modeli çalıştırmaz. */
      this.on=true;
      this.frameSeenAt=performance.now();this.vt=-1;this.recovering=false;
      this.setPreview();
      this.vfc();
      Renderer.resize();
      this.status='Canlı iki el takibi açık';
      WM.repaintAll();
      Diag.toast('Canlı iki el takibi etkin','var(--ok)')
    },
    /* Native sonuç: R|yaş_ms|çıkarım_ms|elSayısı|Etiket,skor,x,y,z,... (el başına bir blok). */
    onNative(s){
      const a=s.split('|'),n=+a[3]||0,now=performance.now(),lms=[],hds=[];
      for(let i=0;i<n;i++){
        const b=a[4+i];if(!b)continue;
        const f=b.split(','),pts=[];
        for(let k=2;k+2<f.length;k+=3)pts.push({x:+f[k],y:+f[k+1],z:+f[k+2]});
        if(pts.length<21)continue;
        lms.push(pts);hds.push([{categoryName:f[0],score:+f[1]}])
      }
      let age=Math.min(250,Math.max(0,+a[1]||0));const inf=Math.max(0,+a[2]||0);
      let t0=now-age;
      /* Stage 45: yakalama zamanı (T) ve gönderim anı (P) native saatindedir (elapsedRealtime, ms). Saat farkı
         o=min(alış−P) ile bulunur (aktarım gecikmesinin en küçüğü ≈ 0 kabul edilir); yakalama = T + o.
         Böylece zaman damgası UI/kuyruk gecikme dalgalanmasıyla titremez, yaş da aktarım süresini kapsar. */
      const tc=a[4+n],pc=a[5+n];
      if(tc&&pc&&tc.charCodeAt(0)===84&&pc.charCodeAt(0)===80){
        const cap=+tc.slice(2),post=+pc.slice(2);
        if(cap>0&&post>0){
          const d=now-post;let o=this.nOff;
          if(o===undefined||!(d-o<2000))o=d;
          else if(d<o)o=d;
          else o+=(d-o)*.002;
          this.nOff=o;
          const tcj=cap+o;
          if(tcj<=now+1&&now-tcj<=400){
            t0=Math.max(tcj,now-250);
            if(this.nT0&&t0<=this.nT0&&this.nT0-t0<100)t0=this.nT0+.25;
            this.nT0=t0;age=Math.max(0,now-t0)
          }
        }
      }
      this.ema+=((inf-this.ema)*.25);
      this.infN=(this.infN||0)+1;
      if(!this.sw)this.sw=now;
      if(now-this.sw>=2000){
        const d=(now-this.sw)/1000;
        this.sInf=Math.round(this.infN/d);this.infN=0;this.sw=now;
        const txt='native '+(NHand.delegate||'')+' · kamera '+(NHand.camFps||'?')+' fps '+(NHand.camSize||'')+' · sonuç '+this.sInf+'/sn · gecikme '+Math.round(age)+' ms · çıkarım '+Math.round(this.ema)+' ms';
        this.statTxt=txt;
        const el=$('#hstat');if(el)el.textContent=(this.status||'')+' · '+txt;
        if(!this.sToast){this.sToast=1;try{Diag.toast(txt,'var(--ok)',7000)}catch(e){}}
      }
      this.ingest({landmarks:lms,handedness:hds},t0,now)
    },
    nativeFailed(msg){
      Diag.toast('Native el takibi durdu: '+msg,'var(--warn)',5000);
      NHand.fail(new Error(msg))
    },
    async startWorker(onStatus){
      if(typeof Worker==='undefined')throw new Error('Bu WebView Web Worker desteklemiyor');
      if(typeof createImageBitmap!=='function')throw new Error('Bu WebView ImageBitmap aktarımını desteklemiyor; el takibi için WebView güncellenmeli');
      const workerUrl=new URL('mediapipe-worker.js',document.baseURI).href;
      const w=new Worker(workerUrl);
      this.worker=w;this.workerReady=false;this.inflight=0;
      const ready=new Promise((resolve,reject)=>{
        const timeout=setTimeout(()=>reject(new Error('MediaPipe Worker zaman aşımına uğradı')),90000);
        w.onmessage=e=>{
          const m=e.data||{};
          if(m.type==='status'){onStatus(m.message||'MediaPipe Worker hazırlanıyor…');return}
          if(m.type==='ready'){
            clearTimeout(timeout);this.workerReady=true;
            MPLocal.delegate=m.delegate||'GPU';
            resolve(true);return
          }
          if(m.type==='init-error'){clearTimeout(timeout);reject(new Error(m.message||'Worker başlatılamadı'));return}
          if(m.type==='result'){
            this.inflight=Math.max(0,this.inflight-1);
            if(!this.on)return;
            const now=performance.now(),duration=Math.max(0,Number(m.duration)||0);
            this.ema+=((duration-this.ema)*.25);
            this.infN=(this.infN||0)+1;
            if(!this.sw)this.sw=now;
            if(now-this.sw>=2000){
              const d=(now-this.sw)/1000,vv=$('#hvid');
              this.sCam=Math.round((this.camN||0)/d);this.sInf=Math.round(this.infN/d);this.camN=0;this.infN=0;this.sw=now;
              const txt='kamera '+CamFps.cur+' fps (ölçülen '+this.sCam+') · '+(vv&&vv.videoWidth?vv.videoWidth+'x'+vv.videoHeight:'?')+' · çıkarım '+this.sInf+'/sn · '+Math.round(this.ema)+' ms';
              this.statTxt=txt;
              const el=$('#hstat');if(el)el.textContent=(this.status||'')+' · '+txt;
              if(!this.sToast){this.sToast=1;try{Diag.toast(txt,'var(--ok)',7000)}catch(e){}}
            }
            if(this.lite){
              if(this.ema>35)this.iv=80;
              else if(this.ema>25)this.iv=66;
              else this.iv=clamp(this.ema*1.4,CamFps.floor(),55);
            }else{
              if(this.ema>35)this.iv=50;
              else this.iv=clamp(this.ema*1.2,CamFps.floor(),36);
            }
            this.ingest(m.result||{landmarks:[],handedness:[]},Number(m.timestamp)||now,now);
            if(this.fast()&&this.on&&!document.hidden){try{this.tick(performance.now(),true)}catch(e){}}
          }else if(m.type==='frame-error'||m.type==='dropped'){
            this.inflight=Math.max(0,this.inflight-1);
            if(m.type==='dropped'&&this.fast()&&this.on&&!document.hidden){try{this.tick(performance.now(),true)}catch(e){}}
          }
        };
        w.onerror=e=>{clearTimeout(timeout);reject(new Error('MediaPipe Worker hatası: '+(e.message||'bilinmeyen hata')))}
      });
      const localFiles=[];
      if(MPLocal.files){
        for(const f of MPLocal.files){
          localFiles.push({name:f.name,buffer:await f.arrayBuffer()});
        }
      }
      w.postMessage({
        type:'init',bases:MP_BASES.slice(),modelUrl:MEDIAPIPE_HAND_MODEL,
        files:localFiles,
        options:{
          runningMode:'VIDEO',numHands:Settings.v.hone?1:2,
          minHandDetectionConfidence:this.lite?.45:.42,
          minHandPresenceConfidence:this.lite?.45:.42,
          minTrackingConfidence:this.lite?.4:.4
        }
      },localFiles.map(f=>f.buffer));
      await ready;
    },
    stop(){
      const wasNative=this.native;
      this.on=false;this.native=false;this.booting=false;
      try{BR.up()}catch(e){}
      try{const vv=$('#hvid');if(this.rv&&vv&&vv.cancelVideoFrameCallback)vv.cancelVideoFrameCallback(this.rv)}catch(e){}
      this.rv=0;
      this.hasT=false;this.extra=null;
      if(Renderer.r)Renderer.resize();
      this.stream=null;
      Pass.hand=false;
      Pass.release();
      if(wasNative)NHand.sync().catch(()=>{});
      $('#hvid').srcObject=null;
      $('#hv').style.display='none';
      this.spaceHold=false;
      this.workerReady=false;this.inflight=0;
      if(this.worker){try{this.worker.postMessage({type:'close'})}catch(e){}try{this.worker.terminate()}catch(e){}}
      this.worker=null;
      this.hide3D();
      this.lost();
      this.status='kapalı';
      WM.repaintAll()
    },
    restart(){
      this.stop();
      this.start()
    },
    /* Yeni kamera karesi geldiğinde çıkarım zamanlamasını güncelle.
       El filtreleme/etkileşim adımı yalnızca ana render döngüsünde çalışır. */
    vfc(){
      const v=$('#hvid');
      if(!v||!v.requestVideoFrameCallback)return;
      try{if(this.rv&&v.cancelVideoFrameCallback)v.cancelVideoFrameCallback(this.rv)}catch(e){}
      const cb=()=>{
        if(!this.on||!this.workerReady){this.rv=0;return}
        this.camN=(this.camN||0)+1;try{this.tick(performance.now(),true)}catch(e){}
        this.rv=v.requestVideoFrameCallback(cb)
      };
      this.rv=v.requestVideoFrameCallback(cb)
    },
    pv(){
      if(this.on)$('#hv').style.display=Settings.v.hprev?'block':'none'
    },
    clr(){
      this.hide3D();
      const h=$('#hd');
      if(h)h.getContext('2d').clearRect(0,0,h.width,h.height);
      this.dr.length=0;
      this.bp=[];
      this.lastBlur=0;
      const b=$('#hb');
      if(b)b.style.display='none'
    },
    /* Hafif eklem modeli: iki el aynı landmark verisiyle çizilir; gölge, doku ve pahalı Path2D yok. */
    geo(X,Y){
      return {s:Math.max(12,Math.hypot(X[0]-X[9],Y[0]-Y[9]))}
    },
    /* Elin arkasını bulanıklaştır: sadece el boyutundaki kutuya backdrop-filter uygulanır, el şekliyle kırpılır. */
    fxBlur:false,
    blur(){
      if(!this.fxBlur){const b0=$('#hb');if(b0&&b0.style.display!=='none')b0.style.display='none';return}
      const now=performance.now();
      if(this.lastBlur&&now-this.lastBlur<100)return;
      this.lastBlur=now;
      const b=$('#hb');
      if(!b)return;
      if(!this.bp||!this.bp.length){b.style.display='none';return}
      let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
      this.bp.forEach(pl=>pl.forEach(q=>{if(q[0]<x0)x0=q[0];if(q[0]>x1)x1=q[0];if(q[1]<y0)y0=q[1];if(q[1]>y1)y1=q[1]}));
      x0=Math.max(0,Math.floor(x0-4));y0=Math.max(0,Math.floor(y0-4));x1=Math.min(innerWidth,Math.ceil(x1+4));y1=Math.min(innerHeight,Math.ceil(y1+4));
      if(x1<=x0||y1<=y0){b.style.display='none';return}
      let d='';
      this.bp.forEach(pl=>{pl.forEach((q,i)=>{d+=(i?'L':'M')+(q[0]-x0).toFixed(1)+' '+(q[1]-y0).toFixed(1)});d+='Z'});
      const st=b.style;
      st.display='block';st.left=x0+'px';st.top=y0+'px';st.width=(x1-x0)+'px';st.height=(y1-y0)+'px';
      const cp='path(nonzero,"'+d+'")';
      st.clipPath=cp;st.webkitClipPath=cp
    },
    /* ===================== ÇİFT EL: ana el yok, iki el eşit =====================
       Her el kendi "slot"unda (filtre, yumuşatma, çimdik durumu) yaşar. Sahipli işlemler (pencere sürükleme,
       uzun basma, etrafa bakma) aynı anda yalnızca bir elde olabilir; böylece çakışma olmaz.
       Klavye tuşları her iki elle aynı anda basılabilir. İki el aynı pencerede çimdikleyince büyütme/küçültme olur. */
    mcut(){
      return [3,2.2,1.6,1.1,.8][clamp((Settings.v.hsm||3)-1,0,4)]
    },
    /* Anında mod: ileri tahmin yok, ara değerleme yok, çıkarım kare aralığı sınırı yok. */
    fast(){return Settings.v.hfast!==false},
    mkSlot(id){
      const fa=this.fast(),mc=fa?3:this.mcut(),bt=fa?9:1.2;
      return{id,on:false,d:null,label:'',miss:0,missAt:0,lastSeen:0,raw:null,cx:.5,cy:.5,x:.5,y:.5,hit:null,
        sx:.5,sy:.5,psx:.5,psy:.5,pst:0,vx:0,vy:0,ox:0,oy:0,dsx:.5,dsy:.5,
        q:Array.from({length:21},()=>({x:0,y:0})),dq:[],hasT:false,
        fx:fa?new OE(1.4,10,2,.8):new OE(mc,bt),fy:fa?new OE(1.4,10,2,.8):new OE(mc,bt),lf:Array.from({length:42},()=>fa?new OE(1.4,10,2,.8):new OE(mc*1.9,bt)),
        /* Her kare yeniden ayrılmasın diye çizim için önceden ayrılmış (preallocated) diziler. */
        _X:new Float64Array(21),_Y:new Float64Array(21),_cur:[0,0],
        lvx:new Float64Array(21),lvy:new Float64Array(21),evx:0,evy:0,
        pr:false,lh:[],pa:null,mode:'',lookX:0,lookY:0}
    },
    slotClear(s){
      s.on=false;s.d=null;s.miss=0;s.missAt=0;s.lastSeen=0;s.hasT=false;s.dq=[];s.pr=false;s.lh=[];s.pa=null;s.mode='';
      s.vx=0;s.vy=0;s.ox=0;s.oy=0;s.pst=0;s.label='';s.evx=0;s.evy=0;s.lvx.fill(0);s.lvy.fill(0);
      s.fx.reset();s.fy.reset();s.lf.forEach(f=>f.reset())
    },
    /* Elin sahip olduğu işlemi bitir (bırakma / el kaybı). 'key' ve 'skip' kalıcı durum bırakmaz. */
    endAct(s){
      if(s.mode==='ui'){
        if(this.uiOwner===s.id)this.uiOwner=-1;
        Input.up()
      }else if(s.mode==='look'){
        if(this.lookOwner===s.id){this.lookOwner=-1;this.setPreview()}
      }
      s.mode=''
    },
    slotRelease(s){
      this.endAct(s);
      const z=this.resizeGesture;
      if(z&&z.ids.indexOf(s.id)>=0)this.resizeGesture=null;
      this.slotClear(s)
    },
    setPreview(){
      const p=$('#hv');
      if(!p)return;
      p.style.display=(!this.on||Game.on||(window.Gorilla&&Gorilla.on)||Stereo.on||XR.session||this.lookOwner!==-1)?'none':(Settings.v.hprev?'block':'none')
    },
    rayOf(s){
      const rc=Scene.rc;
      rc.setFromCamera((this.pv2||(this.pv2=new THREE.Vector2())).set(s.dsx*2-1,-(s.dsy*2-1)),Cam.cam);
      return rc.ray
    },
    hoverEnd(){
      if(this.hv===-1)return;
      this.hv=-1;
      KBD.dwell(null,-1);
      Input.dwDone=null;
      Input.dwellClear()
    },
    /* Bu karede çizilecek alanı (stereo ise iki yarı için) bir sonraki karede silinmek üzere kaydet. */
    mark(X,Y,s,ox,wm){
      let a=1e9,b=1e9,c=-1e9,d=-1e9;
      for(let i=0;i<X.length;i++){if(X[i]<a)a=X[i];if(X[i]>c)c=X[i];if(Y[i]<b)b=Y[i];if(Y[i]>d)d=Y[i]}
      const pd=Math.max(130,s*3.6),w=c-a+2*pd,hh=d-b+2*pd;
      this.dr.push([a-pd+ox,b-pd,w,hh]);
      if(wm)this.dr.push([a-pd+ox+wm,b-pd,w,hh])
    },
    /* Her render karesinde: bakış birikimini akıcı biçimde uygula + eli/imleci hedefe kaydır. */
    step(t){
      const dt=Math.min(.05,Math.max(.001,(t-(this.st||t))/1000));
      this.st=t;
      const L=this.lacc;
      if(L.yaw||L.pitch){
        const a=1-Math.exp(-dt/.035),dy=L.yaw*a,dp=L.pitch*a;
        L.yaw-=dy;L.pitch-=dp;
        if(Math.abs(L.yaw)<2e-5)L.yaw=0;
        if(Math.abs(L.pitch)<2e-5)L.pitch=0;
        /* Sınır, Cam.update'in kullandığı sınırla aynı: aksi halde gizli aşım yönü değiştirirken "takılma" yapıyordu. */
        const lim=Settings.v.pitch||1.2;
        Cam.yaw+=dy;
        Cam.pitch=clamp(Cam.pitch+dp,-lim,lim)
      }
      this.glide(t,false)
    },
    glide(t,force){
      const act=this.slots.filter(s=>s.on&&s.hasT);
      if(!act.length)return;
      if(this.fast()){
        /* Turbo mod (Stage 43): ölçüm gecikmesi (yakalama + çıkarım + aktarım) kadar ileri tahmin yapılır, böylece el
           gerçek konumunda görünür; görünen konum her render karesinde 10-11 ms'lik çok kısa bir süzgeçle hedefe
           yaklaşır, bu yüzden yeni ölçüm gelince ZIPLAMAZ ama hissedilir gecikme de eklenmez. */
        const now=performance.now(),dt=Math.min(.05,Math.max(.001,(now-(this.fgt||now))/1000));
        if(!force&&dt<.0035)return;
        this.fgt=now;
        let far=0;
        for(const s of act){
          const pin=s.pr,g=pin?(s.mode==='ui'?.5:0):1,age=now-s.pst;
          /* 90 ms'ye kadar tam tahmin (ölçüm yaşı bu aralıkta testere dişi yapmaz); yeni veri yoksa (el kaybı) 180 ms'de sıfıra iner. */
          const ag=pin?age:age+9,ah=(ag<=90?Math.max(0,ag):Math.max(0,180-ag))/1000*g,
            a=1-Math.exp(-dt/(pin?.007:.018));
          for(let i=0;i<21;i++){
            const o=s.dq[i],q=s.q[i];
            let wx=s.lvx[i],wy=s.lvy[i];const sp=Math.hypot(wx,wy),w=clamp((sp-.04)/.1,0,1);
            const dx=q.x+clamp(wx*w*ah,-.12,.12)-o.x,dy=q.y+clamp(wy*w*ah,-.12,.12)-o.y;
            o.x+=dx*a;o.y+=dy*a;far+=Math.abs(dx)+Math.abs(dy)
          }
          const ex=s.sx+clamp(s.evx*ah,-.12,.12)-s.dsx,ey=s.sy+clamp(s.evy*ah,-.12,.12)-s.dsy;
          s.dsx+=ex*a;s.dsy+=ey*a;far+=Math.abs(ex)+Math.abs(ey);s.ox=0;s.oy=0
        }
        this.pt=t;this.gt=t;
        /* Stage 45: native sonuç ana iş parçacığında kuyruğa girip hemen çizdirilirdi; render karesi zaten hemen ardından
           çiziyor. İkinci çizimi atla (ana iş parçacığı yükü yarıya iner), bir sonraki karede çizilmesini işaretle. */
        if(force&&this.native){this.nd=true;return}
        if(!force&&far<.00025&&!this.nd)return;
        this.nd=false;
        this.draw();
        if(!force&&!this.resizeGesture&&this.lookOwner===-1&&this.uiOwner!==-1){
          const s=this.slots[this.uiOwner];
          if(s&&s.on&&s.mode==='ui')Input.move(this.rayOf(s))
        }
        return
      }
      if(!force&&t-this.gt<14)return;
      const dt=Math.min(.08,Math.max(.001,(t-this.pt)/1000));
      this.pt=t;this.gt=t;
      const now=performance.now(),lead=this.lead/1000,mir=this.mirror?-1:1;
      let far=0;
      for(const s of act){
        const pin=s.pr,since=now-s.pst;
        if(since>70){s.vx*=.85;s.vy*=.85}
        /* Gecikmeyi gizlemek için hızla küçük bir ileri tahmin (çimdikteyken kapalı: tıklama kaymasın).
           Ayrıca son gerçek algılamadan bu yana geçen süre kadar da aynı yönde tahmine devam edilir:
           aksi halde iki kamera/çıkarım karesi arasında el konumu donuk kalır, yeni veri gelince
           aniden zıplar — hızlı hareket ettiğinde hissedilen "tekleme" tam olarak buydu. */
        /* Stage 38c: akıcı modda ileri tahmin kapalı; el, ölçümler arası süreye göre uzun bir zaman sabitiyle
           yeni hedefe süzülür (ara değerleme). Hız dalgalanması ve aşım olmaz; bedeli ~20-40 ms gecikme. */
        const smo=Settings.v.hsmo===true;
        const extra=(pin||smo)?0:clamp(since,0,90)/1000*.5,
          tx=(pin||smo)?0:clamp(s.vx*(lead+extra),-.07,.07),ty=(pin||smo)?0:clamp(s.vy*(lead+extra),-.07,.07),ka=1-Math.exp(-dt/.03);
        s.ox+=(tx-s.ox)*ka;s.oy+=(ty-s.oy)*ka;
        const a=1-Math.exp(-dt/(pin?(smo?.012:.008):(smo?clamp((this.resDt||40)*.6,20,55)/1000:.013)));
        for(let i=0;i<21;i++){
          const o=s.dq[i],g=s.q[i],dx=g.x+mir*s.ox-o.x,dy=g.y+s.oy-o.y;
          o.x+=dx*a;o.y+=dy*a;far+=Math.abs(dx)+Math.abs(dy)
        }
        const ex=s.sx+s.ox-s.dsx,ey=s.sy+s.oy-s.dsy;
        s.dsx+=ex*a;s.dsy+=ey*a;far+=Math.abs(ex)+Math.abs(ey)
      }
      if(!force&&far<.0004)return;
      this.draw();
      if(!force&&!this.resizeGesture&&this.lookOwner===-1&&this.uiOwner!==-1){
        const s=this.slots[this.uiOwner];
        if(s&&s.on&&s.mode==='ui')Input.move(this.rayOf(s))
      }
    },
    draw(){
      if(!Settings.v.hdraw||Game.on||(window.Gorilla&&Gorilla.on)){
        this.clr();
        return
      }
      const cam=Cam.cam;
      if(!cam||typeof THREE==='undefined')return;
      const H=innerHeight,W=innerWidth,Wm=(Stereo.on&&!XR.session)?W/2:W,mir=this.mirror;
      let any=false;
      for(const s of this.slots){
        const c=this.c3[s.id]||(this.c3[s.id]=nexCtrl3D(THREE,cam));
        if(!s.on||!s.hasT){if(c.vis){nexCtrl3DHide(c);any=true}continue}
        const p=s.dq,a=p[0],b=p[9],ax=mir?1-a.x:a.x,bx=mir?1-b.x:b.x,
          mx=(ax+bx)*.5,my=(a.y+b.y)*.5,sr=Math.hypot((ax-bx)*Wm,(a.y-b.y)*H)/H,
          hov=!!(s.hit||s.mode==='ui');
        nexCtrl3DPlace(THREE,c,cam,{nx:mx*2-1,ny:-(my*2-1),sr:sr,cx:s.dsx*2-1,cy:-(s.dsy*2-1),
          dist:s.hit?s.hit.distance:0,cursor:hov,pinch:!!s.pr,right:(s.label==='Right')!==!!this.ctrlFlip});
        any=true
      }
      if(any)Scene.dirty=true
    },
    lost(){
      KBD.dwell(null,-1);
      Input.dwDone=null;
      Input.dwellClear();
      (this.slots||[]).forEach(s=>{if(s.on)this.slotRelease(s)});
      this.resizeGesture=null;this.hv=-1;this.uiOwner=-1;this.lookOwner=-1;this.lastResizeBuild=0;
      this.setPreview();
      this.clr();
      this.hide3D()
    },
    /* Tab S6 Lite: keep synchronous inference from monopolizing every render frame. */
    /* Stage 63: eskiden tüm Android'lerde açıktı (güçlü telefon/tablet de 320x240'a düşüyordu). Şimdi yalnızca düşük/orta seviyede. */
    /* Stage 64: Ayarlar → Grafik → El takibi profili (0 otomatik, 1 hafif 320×240, 2 standart 480×360). */
    get lite(){const g=Settings.v.ghand|0;return g===1?true:g===2?false:!!Dev.mobLite},
    iv:50, // Mobile starts at 20 inference FPS; rendering remains independent and smooth.
    ema:12,
    pt:0,gt:0,st:0,gm:0,had:false,lead:16,
    slots:[],uiOwner:-1,lookOwner:-1,hv:-1,lacc:{yaw:0,pitch:0},pv2:null,
    rv:0,dr:[],worker:null,workerReady:false,inflight:0,workerSentAt:0,workerSeq:0,workerStartedAt:0,
    vt:-1,frameSeenAt:0,recovering:false,
    canvas2d:null,
    initF(){
      const hc=$('#hd');
      this.canvas2d=hc?hc.getContext('2d',{alpha:true}):null;
      if(hc)hc.style.opacity=this.fast()?'.88':'';
      if(this.slots.length)this.lost();
      this.slots=[this.mkSlot(0),this.mkSlot(1)];
      this.uiOwner=-1;this.lookOwner=-1;this.hv=-1;this.resizeGesture=null;
      this.lacc={yaw:0,pitch:0};this.gm=0;this.had=false;this.iv=this.lite?50:33;this.ema=this.lite?22:12;this.dr=[];this.bp=[]
    },
    resetF(){
      this.slots.forEach(s=>{s.fx.reset();s.fy.reset();s.lf.forEach(f=>f.reset())})
    },
    async recoverCamera(){
      if(this.recovering||!this.on)return;
      this.recovering=true;
      this.status='Kamera bağlantısı yenileniyor…';
      const stat=$('#hstat');if(stat)stat.textContent=this.status;
      try{
        // Force a fresh camera stream; a frozen-but-still-live track cannot be recovered by reusing it.
        if(Pass.stream){try{Pass.stream.getTracks().forEach(tr=>tr.stop())}catch(e){}}
        Pass.stream=null;Pass.fac=null;
        const st=await Pass.acquire(Settings.v.hcam||'environment');
        if(!this.on){st.getTracks().forEach(tr=>tr.stop());return}
        this.stream=st;
        try{st.getVideoTracks().forEach(tr=>tr.addEventListener('ended',()=>{if(this.on)this.recoverCamera()},{once:true}))}catch(e){}
        const v=$('#hvid');v.srcObject=st;
        try{this.mirror=st.getVideoTracks()[0].getSettings().facingMode!=='environment'}catch(e){this.mirror=true}
        v.style.transform=this.mirror?'scaleX(-1)':'none';
        await v.play();
        this.vt=-1;this.frameSeenAt=performance.now();this.last=0;
        this.slots.forEach(s=>{if(s.on){s.missAt=0;s.miss=0}});
        this.status='Canlı iki el takibi açık';if(stat)stat.textContent=this.status;
      }catch(e){this.status='Kamera bekleniyor';if(stat)stat.textContent=this.status}
      finally{this.recovering=false}
    },
    tick(t,videoFrame=false){
      if(!this.on||!this.workerReady)return;
      /* Video callback ve render döngüsü aynı anda gelebilir. step() yalnızca
         render döngüsünde çalışmalı; aksi hâlde filtre/raycast/çizim iki kez yapılır. */
      if(!videoFrame)this.step(t);
      if(this.native)return;
      if(document.hidden)return;
      if(Cinema.on&&Cinema.playing&&t-this.last<110)return;
      const v=$('#hvid');
      if(v.readyState<2||v.currentTime===this.vt){
        if(!this.frameSeenAt)this.frameSeenAt=t;
        if(t-this.frameSeenAt>1800)this.recoverCamera();
        return
      }
      this.vt=v.currentTime;this.frameSeenAt=t;
      if(t-this.last<(this.fast()?(this.gm>25?24:0):this.iv))return;
      if(Stereo.on&&!XR.session)this.iv=Math.max(this.iv,40);
      this.vt=v.currentTime;this.last=t;
      /* Turbo modda en çok 2 kare yoldadır: Worker her zaman en tazesini işler (eskiyi atar), boşta beklemez.
         Worker'dan yanıt gelmezse (1.5 sn) sayaç sıfırlanır; böylece takılı kalmaz. */
      if(this.inflight>0&&performance.now()-this.workerSentAt>1500)this.inflight=0;
      if(this.inflight>=(this.fast()?2:1))return;
      this.inflight++;
      const t0=performance.now(),seq=++this.workerSeq;
      this.workerStartedAt=t0;this.workerSentAt=t0;
      const vw=v.videoWidth||0,vh=v.videoHeight||0;
      const rso=vw>400?{resizeWidth:320,resizeHeight:Math.max(2,Math.round(vh*320/vw)),resizeQuality:'low'}:undefined;
      createImageBitmap(v,rso).then(bitmap=>{
        if(!this.on||!this.worker||!this.workerReady){bitmap.close();this.inflight=Math.max(0,this.inflight-1);return}
        try{this.worker.postMessage({type:'frame',bitmap,timestamp:t0,seq},[bitmap])}
        catch(e){try{bitmap.close()}catch(_){}this.inflight=Math.max(0,this.inflight-1)}
      }).catch(()=>{this.inflight=Math.max(0,this.inflight-1)});
    },
    /* Tespitleri slotlara eşle (süreklilikle), süz, sonra çakışmasız etkileşime dağıt. */
    ingest(r,t0,t){
      {const nt=performance.now();if(this.lastIng){const d=nt-this.lastIng;if(d<400)this.resDt=this.resDt?this.resDt*.8+d*.2:d}this.lastIng=nt}
      const lm=r.landmarks||[],hd=r.handedness||r.handednesses||[],dets=[];
      for(let i=0;i<Math.min(2,lm.length);i++){
        const raw=lm[i];
        if(!Array.isArray(raw)||raw.length<21)continue;
        const h=hd[i]&&hd[i][0];
        if((h?h.score:1)<.12)continue;
        dets.push({raw,label:(h&&h.categoryName)||'',cx:(raw[0].x+raw[9].x)/2,cy:(raw[0].y+raw[9].y)/2})
      }
      const S=this.slots;
      S.forEach(s=>{s.d=null});
      const pairs=[];
      dets.forEach((d,di)=>S.forEach(s=>{
        if(s.on)pairs.push([Math.hypot(d.cx-s.cx,d.cy-s.cy)+(d.label&&s.label&&d.label!==s.label?.25:0),di,s])
      }));
      pairs.sort((a,b)=>a[0]-b[0]);
      const ud=new Set(),us=new Set();
      for(const p of pairs){
        if(p[0]>.6||ud.has(p[1])||us.has(p[2].id))continue;
        ud.add(p[1]);us.add(p[2].id);p[2].d=dets[p[1]]
      }
      dets.forEach((d,di)=>{
        if(ud.has(di))return;
        let f=S.find(s=>!s.on&&!us.has(s.id));
        if(!f){
          // A newly visible hand can be far from its last position after occlusion.
          // Reassign the oldest currently-missing slot instead of dropping the hand.
          f=S.filter(s=>s.on&&!s.d&&!us.has(s.id)).sort((a,b)=>(a.lastSeen||0)-(b.lastSeen||0))[0];
          if(f)this.slotRelease(f);
        }
        if(!f)return;
        ud.add(di);us.add(f.id);f.d=d;f.on=true
      });
      const panels=WM.panels.filter(m=>m.visible);
      let released=false;
      for(const s of S){
        if(!s.on)continue;
        if(s.d){s.miss=0;s.missAt=0;this.upd(s,s.d,t0,panels)}
        else{
          s.miss++;
          if(!s.missAt)s.missAt=t;
          // Keep the last tracked hand visible through short MediaPipe dropouts.
          // Six missed inference frames was too aggressive on mobile cameras.
          if(s.lastSeen&&t-s.lastSeen>520){this.slotRelease(s);released=true}
        }
      }
      const n=S.filter(s=>s.on&&s.d).length;
      if(!n){
        this.gm++;
        this.iv=this.lite?(this.gm>25?110:55):(this.gm>25?70:36);
        if(!S.some(s=>s.on)){
          if(this.had){this.had=false;this.lost()}
          this.status='açık, el yok'
        }else if(released)this.draw();
        return
      }
      this.gm=0;this.had=true;
      this.iv=this.lite?clamp(this.ema*1.4,CamFps.floor(),66):clamp(this.ema*1.15,CamFps.floor(),40);
      /* Bakarken algılamayı biraz seyrelt: render karelerine nefes alanı kalsın, akıcılık artsın. */
      if(this.lookOwner!==-1)this.iv=Math.min(45,Math.max(this.iv,this.ema*1.8));
      this.lead=clamp((this.ema*.7+8)*.4,4,13); /* süzgeç gecikmesi azaldığı için öne tahmin de azaltıldı; yoksa hızlı hamlede imleç hedefi aşıyordu */
      this.status=n===2?'açık, iki el algılandı':'açık, el algılandı';
      this.glide(t,true);
      this.arbitrate()
    },
    /* Tek elin yeni ölçümü: çimdik, imleç, süzgeçler, hız. */
    upd(s,d,t0,panels){
      const raw=d.raw;
      s.raw=raw;s.miss=0;s.missAt=0;s.lastSeen=t0;
      if(d.label)s.label=d.label;
      s.cx=(raw[0].x+raw[9].x)/2;s.cy=(raw[0].y+raw[9].y)/2;
      const dist=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
      const size=Math.max(dist(raw[0],raw[9]),dist(raw[5],raw[17])*1.15)||.1;
      const pd=dist(raw[4],raw[8])/size,T=.18+.04*(Settings.v.hclk||3);
      const pr=pd<(s.pr?T*1.15:T);
      const midx=(raw[4].x+raw[8].x)/2,midy=(raw[4].y+raw[8].y)/2;
      let px,py;
      if(!pr){
        px=raw[8].x;py=raw[8].y;
        s.lh.push({x:px,y:py});
        if(s.lh.length>3)s.lh.shift();
        s.pa=null
      }else{
        /* Tıklama sabitleme: parmaklar kapanırken imleç kaymasın. */
        if(!s.pa){const a0=s.lh.length?s.lh[0]:{x:midx,y:midy};s.pa={ox:a0.x,oy:a0.y,mx:midx,my:midy}}
        px=s.pa.ox+(midx-s.pa.mx);py=s.pa.oy+(midy-s.pa.my)
      }
      s.pr=pr;
      const x=this.mirror?1-px:px,y=py;
      s.x=x;s.y=y;
      const rc=this.hitRC,pv=this.pv2||(this.pv2=new THREE.Vector2());
      rc.setFromCamera(pv.set(x*2-1,-(y*2-1)),Cam.cam);
      s.hit=rc.intersectObjects(panels,false)[0]||null;
      const ik=1/clamp(size,.05,.6); /* süzgeç hızı el boyuna göre ölçer */
      /* Stage 43: her eklemin süzgeçli hızı (ekran/sn) — glide() hızlı modda gecikmeyi telafi etmek için kullanır. */
      const dtv=s.pst?(t0-s.pst)/1000:0,okv=dtv>=.004&&dtv<.25;
      for(let i=0;i<21;i++){
        const q=s.q[i],ox=q.x,oy=q.y;
        q.x=s.lf[i*2].f(raw[i].x,t0,ik);
        q.y=s.lf[i*2+1].f(raw[i].y,t0,ik);
        if(okv){s.lvx[i]+=((q.x-ox)/dtv-s.lvx[i])*.6;s.lvy[i]+=((q.y-oy)/dtv-s.lvy[i])*.6}
        else{s.lvx[i]=0;s.lvy[i]=0}
      }
      const nx=s.fx.f(x,t0,ik),ny=s.fy.f(y,t0,ik);
      if(s.pst){
        const dt=Math.max(.004,(t0-s.pst)/1000);
        s.vx+=((nx-s.psx)/dt-s.vx)*.55;
        s.vy+=((ny-s.psy)/dt-s.vy)*.55
      }else{s.vx=0;s.vy=0}
      /* Duran elde titreşim tahmine dönüşmesin: düşük hızlarda tahmin ağırlığı 0'a iner. */
      {const sp=Math.hypot(s.vx,s.vy),w=clamp((sp-.04)/.1,0,1);s.evx=s.vx*w;s.evy=s.vy*w}
      s.psx=nx;s.psy=ny;s.pst=t0;s.sx=nx;s.sy=ny;
      if(!s.hasT){s.dq=s.q.map(p=>({x:p.x,y:p.y}));s.dsx=nx;s.dsy=ny;s.hasT=true}
    },
    lookStep(s){
      const dx=s.sx-s.lookX,dy=s.sy-s.lookY;
      s.lookX=s.sx;s.lookY=s.sy;
      /* Doğrudan kameraya yazmak yerine biriktir; step() her karede akıcı biçimde uygular. */
      this.lacc.yaw-=dx*4.0;
      this.lacc.pitch+=dy*3.2
    },
    arbitrate(){
      if(Lobby.open){Lobby.hands(this.slots);return} /* açılış sahnesi: eller başlatıcıyı yönetir */
      if(window.Gorilla&&Gorilla.ownsHands&&Gorilla.ownsHands())return; /* Goril oyunu açıkken kamera elleri oyuna aittir */
      HMenu.scan(this.slots,performance.now());
      const S=this.slots,vr=Stereo.on||!!XR.session,A=S[0],B=S[1];
      /* İki el aynı pencerede çimdikliyorsa: büyüt/küçült (klavye ve dock hariç, orada iki elle yazılır). */
      if(A.on&&B.on&&A.d&&B.d&&A.pr&&B.pr&&A.hit&&B.hit&&A.hit.object===B.hit.object&&A.mode!=='look'&&B.mode!=='look'&&!A.hit.object.userData.kbd&&!A.hit.object.userData.dock&&!A.hit.object.userData.fixedDesk){
        const panel=A.hit.object,dist=Math.max(.025,Math.hypot(A.x-B.x,A.y-B.y)),z=this.resizeGesture;
        if(!z||z.panel!==panel){
          this.resizeGesture={panel,dist,sf:panel.userData.sf,ids:[A.id,B.id]};
          this.endAct(A);this.endAct(B)
        }else{
          panel.userData.max=false;
          panel.userData.sf=clamp(z.sf*(dist/z.dist),.5,1.6);
          const nb=performance.now();
          if(!this.lastResizeBuild||nb-this.lastResizeBuild>32){WM.build(panel);this.lastResizeBuild=nb}
        }
        A.mode='rz';B.mode='rz';
        this.hoverEnd();
        return
      }
      if(this.resizeGesture)this.resizeGesture=null;
      for(const s of S){
        if(!s.on||!s.d)continue;
        /* Büyütmeden çıkan el, çimdiği bırakmadan yeni işlem başlatmaz (istemsiz tıklama/sürükleme olmasın). */
        if(s.mode==='rz')s.mode=s.pr?'skip':'';
        if(!s.pr){
          if(s.mode)this.endAct(s);
          continue
        }
        if(s.mode==='ui'){Input.move(this.rayOf(s));continue}
        if(s.mode==='look'){this.lookStep(s);continue}
        if(s.mode)continue;
        /* Yeni çimdik: kime ne ait? */
        const ray=this.rayOf(s),h=Scene.pick(ray),u=h&&h.object.userData;
        if(u&&u.kbd&&u.id==='vkb'){
          Input.down(ray,'hand');
          s.mode='key'
        }else if(!h&&!vr){
          if(this.uiOwner===-1&&this.lookOwner===-1){
            this.lookOwner=s.id;s.mode='look';s.lookX=s.sx;s.lookY=s.sy;
            this.setPreview()
          }else s.mode='skip'
        }else if(this.uiOwner===-1&&this.lookOwner===-1){
          this.uiOwner=s.id;s.mode='ui';
          Input.down(ray,'hand')
        }else s.mode='skip'
      }
      /* Üzerine gelme / bekleyerek tıklama: aynı anda tek elde (boşta olan, tercihen bir pencerenin üzerindeki el). */
      if(this.lookOwner!==-1){this.hoverEnd();return}
      const el=S.filter(s=>s.on&&s.d&&s.mode===''&&!HMenu.holds(s)),wh=el.filter(s=>s.hit),pool=wh.length?wh:el,pk=pool.find(s=>s.id===this.hv)||pool[0]||null,id=pk?pk.id:-1;
      if(id!==this.hv){this.hoverEnd();this.hv=id}
      if(pk)Input.hover(this.rayOf(pk),'hand')
    }
  };
