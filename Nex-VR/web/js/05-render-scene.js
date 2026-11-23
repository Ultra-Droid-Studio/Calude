'use strict';
  const Renderer={
    r:null,
    lost:false,
    scale:1,
    phone(){return Dev.phone&&Dev.android},
    init(){
      try{
        this.r=new THREE.WebGLRenderer({canvas:$('#c'),antialias:(Settings.v.gaa|0)===2?true:(Settings.v.gaa|0)===1?false:!Dev.mobLite,alpha:true,powerPreference:'high-performance',stencil:false,depth:true,preserveDrawingBuffer:false})
      }catch(e){
        return false
      }
      const r=this.r,c=$('#c');
      r.setClearColor(0x000000,0);
      r.xr.enabled=true;
      r.shadowMap.enabled=false; /* Tablet GPU budget: avoid costly shadow-map passes. */
      r.shadowMap.type=THREE.PCFSoftShadowMap;
      c.addEventListener('webglcontextlost',e=>{
        e.preventDefault();
        this.lost=true;
        Diag.toast('WebGL bağlamı kaybedildi; geri yükleniyor…','var(--warn)')
        });
      c.addEventListener('webglcontextrestored',()=>{
        this.lost=false;
        WM.panels.forEach(p=>{
          p.userData.tex.needsUpdate=true
          });
        Scene.sky.material.needsUpdate=true;
        WM.repaintAll();
        Diag.toast('WebGL geri yüklendi','var(--ok)')
        });
      this.resize();
      return true
    },
    resize(){
      const r=this.r;
      if(!r)return;
      const mobile=Dev.mobLite,phone=this.phone(),q=Settings.v.quality,stereo=Stereo.on&&!XR.session;
      /* Stage 64: Ayarlar → Grafik → Piksel bütçesi. 0 = otomatik (cihaz seviyesine göre), aksi hâlde kullanıcının çarpanı. */
      const um=+Settings.v.pxb||0;
      let cap;
      if(phone){
        /* Stage 61: telefonlarda piksel BÜTÇESİ (en az 1:1 CSS pikseli). Bütçe ekran boyutuna göre ölçeklenir. */
        const px=Math.max(1,innerWidth*innerHeight),budget=[.9e6,1.3e6,1.9e6][q]*(um||[.8,1,1.3][Dev.tier])*(stereo?1.2:1);
        cap=clamp(Math.sqrt(budget/px),um&&um<1?.35:1,um>1.3?3:2)
      }else if(um){
        cap=clamp((mobile?[[.7,.9,1.05],[.75,1,1.15],[1,1.25,1.5]][1][q]:[1,1.5,1.75][q])*um,.35,3)
      }else cap=mobile?[[.7,.9,1.05],[.75,1,1.15],[1,1.25,1.5]][Dev.tier][q]:[1,1.5,Math.min(1.75,Settings.v.dpr||1.5)][q];
      /* Telefonda ceza hafif: el takibi artık native (ağır iş ana iş parçacığında değil), VR'da göz başına yarım ekran zaten bölünür. */
      const hand=Hand&&Hand.on?(phone?.92:.78):1;
      const vr=stereo?(phone?clamp(Settings.v.vrScale||.85,.7,1):.72*clamp(Settings.v.vrScale||.85,.6,1)):1;
      const userCap=um?cap:(phone?Math.max(cap,Settings.v.dpr):Math.min(cap,Settings.v.dpr));
      const floor=um&&um<1?.3:(phone?(stereo?.9:.8):.55);
      r.setPixelRatio(Math.max(floor,Math.min(devicePixelRatio||1,userCap)*this.scale*(Settings.v.saver?.75:1)*hand*vr));
      Perf.hold=performance.now()+1600;
      r.setSize(innerWidth,innerHeight,false);
      Cam.cam.aspect=innerWidth/innerHeight*(Stereo.on?.5:1);
      Cam.cam.updateProjectionMatrix();
      Scene.dirty=true
    }
  };
  /* Stage 63: Android bellek baskısı (onTrimMemory). Çözünürlüğü düşürür ve otomatik yükseltmeyi bir süre kilitler. */
  window.__nxTrim=function(level){
    try{
      if(!Renderer.r)return;
      const to=level>=15?.7:.85;
      if(Renderer.scale>to){Renderer.scale=to;Renderer.resize()}
      Perf.lock=performance.now()+60000;Perf.lo=0;Perf.hi=0
    }catch(e){}
  };
  const Cam={
    cam:null,
    rig:null,
    yaw:0,
    pitch:0,
    zoom:0,
    gyro:false,
    g:{ok:false},
    gCnt:0,nCnt:0,src:'off',hz:0,vT:0,dead:false,
    /* Stage 66: hibrit mod (yerçekimi vektörü) + ölü bölge (0,10° girişte hareket, 0,03° altında dur) */
    hOk:false,hT:0,gx:0,gy:1,gz:0,
    dzMove:true,dzOn:Math.cos(.1*Math.PI/360),dzOff:Math.cos(.03*Math.PI/360),
    init(){
      this.cam=new THREE.PerspectiveCamera(70,innerWidth/innerHeight,.1,200);
      this.rig=new THREE.Group();
      this.rig.position.set(0,1.6,0);
      this.rig.add(this.cam);
      this.QM=new THREE.Quaternion(-Math.sqrt(.5),0,0,Math.sqrt(.5)); // ENU (z yukarı) -> three (y yukarı)
      this.nq=new THREE.Quaternion();this.nm=new THREE.Matrix4();this.qc=new THREE.Quaternion();
      this._q1=new THREE.Quaternion();this._e1=new THREE.Euler();this._up=new THREE.Vector3(0,1,0);this._q2=new THREE.Quaternion();this._e2=new THREE.Euler(0,0,0,'YXZ');
      this.nqOk=false;this.nqT=0;this.nCenter=true
    },
    reset(){
      this.yaw=0;
      this.pitch=0;
      this.zoom=0;
      this.nCenter=true;this.dzMove=true
    },
    update(dt){
      if(XR.session)return;
      if(Settings.v.auto&&!Input.look)this.yaw+=dt*.05;
      const now=performance.now();
      const nat=this.gyro&&this.nqOk&&now-this.nqT<600;
      const hyb=!nat&&this.gyro&&this.hOk&&now-this.hT<600;
      if(this.gyro&&(nat||hyb||this.g.ok)){
        let q,kk;
        if(nat){
          /* Yerel sensör: Euler açıları yerine doğrudan dönüş matrisi/quaternion (gimbal kilidi yok).
             Ekran döndürmesi Java tarafında uygulandı, burada tekrar uygulanmaz. */
          q=this._q1;q.copy(this.nq).premultiply(this.QM);
          if(this.nCenter){this._e1.setFromQuaternion(q,'YXZ');this.qc.setFromAxisAngle(this._up,-this._e1.y);this.nCenter=false}
          q.premultiply(this.qc);kk=45
        }else if(hyb){
          /* Stage 66 hibrit: eğim (pitch) ve yatış (roll) yerçekiminden, yön (yaw) dokunmayla.
             Bakış yönü = ekran normalinin tersi; yerçekimi ekran çerçevesinde (gx,gy,gz) normalize. */
          const pitch=Math.asin(clamp(-this.gz,-1,1));
          const w=clamp((.93-Math.abs(this.gz))/.1,0,1); // neredeyse dik yukarı/aşağı bakışta yatış belirsiz → sönümle
          const roll=w>0?Math.atan2(this.gx,this.gy)*w:0;
          this._e2.set(clamp(pitch,-1.5,1.5),this.yaw,roll,'YXZ');
          q=this._q2.setFromEuler(this._e2);kk=24
        }else{
          const d=Math.PI/180,rot=(screen.orientation&&screen.orientation.angle)||0;
          q=new THREE.Quaternion().setFromEuler(new THREE.Euler(this.g.b*d,this.g.a*d,-this.g.g*d,'YXZ'));
          q.multiply(this.QM);
          q.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0,0,1),-rot*d));kk=14
        }
        const k=1-Math.exp(-Math.min(dt,.1)*kk);
        /* Stage 66 ölü bölge (histerezis): fark 0,10°'yi aşınca hareket başlar, 0,03°'nin altına inince durur.
           Durunca quaternion değişmez → kare döngüsü sahneyi yeniden çizmez (GPU dinlenir, sensör gürültüsü çizdirmez). */
        const dot=Math.abs(this.cam.quaternion.dot(q));
        if(this.dzMove){if(dot>this.dzOff)this.dzMove=false}
        else if(dot<this.dzOn)this.dzMove=true;
        if(this.dzMove)this.cam.quaternion.slerp(q,k)
      }
      else this.cam.rotation.set(clamp(this.pitch,-Settings.v.pitch,Settings.v.pitch),this.yaw,0,'YXZ');
      this.cam.position.z=clamp(this.zoom,-1,2)
    },
    /* Stage 65: sensör gerçekten veri veriyor mu? (sanal/bozuk jiroskop, hiç olay göndermeyen WebView) */
    gyroLive(){
      return this.gyro&&((this.nqOk&&performance.now()-this.nqT<600)||this.g.ok)
    },
    /* Hibrit mod canlı mı (eğim sensörden; yön hâlâ dokunmayla)? */
    hybridLive(){
      return this.gyro&&this.hOk&&performance.now()-this.hT<600&&!(this.nqOk&&performance.now()-this.nqT<600)
    },
    statusText(){
      if(!this.gyro)return this.dead?'veri yok (kapatıldı)':(Dev.java&&Dev.sensor==='none'?'sensör yok':'kapalı');
      if(this.src==='verify')return 'doğrulanıyor…';
      if(this.src==='native')return (this.hOk?'hibrit (eğim sensörden, yön dokunmayla)':'yerel rotasyon')+' · '+this.hz+' Hz';
      if(this.src==='web')return 'web · '+this.hz+' Hz';
      return 'açık'
    },
    verify(D){
      clearTimeout(this.vT);
      const t0=performance.now();
      this.vT=setTimeout(()=>{
        this.vT=0;
        if(!this.gyro)return;
        const sec=Math.max(.5,(performance.now()-t0)/1000);
        const nOk=this.nativeGyro&&this.nCnt>=2,wOk=!!D&&this.gCnt>=1;
        if(nOk){
          /* Yerel sensör çalışıyor: aynı sensörü ikinci kez dinleyen web olayı gereksiz. */
          this.src='native';this.hz=Math.round(this.nCnt/sec);
          removeEventListener('deviceorientation',this.fn);
          this.g={ok:false};
          Diag.toast(this.hOk?'Jiroskop yok: hibrit mod (eğim sensörden, yönü parmakla çevir)':(this.hz<15?'Sensör yavaş ('+this.hz+' Hz); sanal sensör olabilir':'Hareket sensörü doğrulandı ('+this.hz+' Hz)'),this.hz<15||this.hOk?'var(--warn)':'var(--ok)',3500)
        }
        else if(wOk){
          /* Yerel sensör veri vermedi ama WebView olayı geliyor: web yoluna geç, yerel dinleyiciyi kapat. */
          this.src='web';this.hz=Math.round(this.gCnt/sec);
          if(this.nativeGyro){
            try{if(window.AndroidBridge&&NX_T&&AndroidBridge.nativeGyroStop)AndroidBridge.nativeGyroStop(NX_T)}catch(e){}
            this.nativeGyro=false;this.nqOk=false
          }
          Diag.toast('Hareket sensörü doğrulandı (web)','var(--ok)',3000)
        }
        else{
          /* Hiçbir yoldan veri yok: sensörü kapat, dokunmatik bakışa dön. */
          this.disableGyro();
          this.dead=true;
          Diag.toast('Hareket sensörü veri vermiyor (sanal ya da bozuk olabilir); dokunmatik bakışa dönüldü','var(--warn)',5000)
        }
        WM.repaintAll()
      },1800)
    },
    async enableGyro(){
      const D=window.DeviceOrientationEvent;
      let nativeAvailable=false;
      try{nativeAvailable=!!(window.AndroidBridge&&NX_T&&AndroidBridge.nativeGyroAvailable&&AndroidBridge.nativeGyroAvailable(NX_T))}catch(e){}
      this.dead=false;
      /* Stage 65 otomatik mod: Java sensör yok diyorsa WebView de veri veremez; hiç deneme. */
      if(Dev.java&&Dev.sensor==='none'&&!nativeAvailable){
        Diag.toast('Bu cihazda hareket sensörü yok; dokunmatik bakış kullanılıyor','var(--warn)');
        return
      }
      if(!D&&!nativeAvailable){
        Diag.toast('Bu cihazda yön sensörü bulunamadı; dokunmatik kullanın','var(--warn)');
        return
      }
      try{
        if(D&&typeof D.requestPermission==='function'&&await D.requestPermission()!=='granted'){
          Diag.toast('Sensör izni reddedildi','var(--err)');
          return
        }
      }
      catch(e){
        Diag.toast('Sensör izni alınamadı','var(--err)');
        return
      }
      this.fn=this.fn||(e=>{
        if(e.alpha!=null){this.g={a:e.alpha,b:e.beta,g:e.gamma,ok:true};this.gCnt++}
        });
      if(D)addEventListener('deviceorientation',this.fn);
      this.gyro=true;
      this.nqOk=false;this.nCenter=true;
      this.nativeGyro=false;
      this.g={ok:false};this.gCnt=0;this.nCnt=0;this.hz=0;this.src='verify';this.hOk=false;this.hT=0;this.dzMove=true;
      // Android WebView on some OEM builds exposes DeviceOrientationEvent but never
      // dispatches it. Use the native rotation-vector sensor as a fallback.
      try{
        if(nativeAvailable)this.nativeGyro=!!AndroidBridge.nativeGyroStart(NX_T)
      }catch(e){this.nativeGyro=false}
      WM.repaintAll();
      Diag.toast('Hareket sensörü doğrulanıyor…','var(--ok)',1600);
      this.verify(D)
    },
    disableGyro(){
      clearTimeout(this.vT);this.vT=0;
      removeEventListener('deviceorientation',this.fn);
      try{if(window.AndroidBridge&&NX_T&&AndroidBridge.nativeGyroStop)AndroidBridge.nativeGyroStop(NX_T)}catch(e){}
      this.nativeGyro=false;
      this.gyro=false;
      this.g.ok=false;
      this.nqOk=false;this.nCenter=true;
      this.src='off';this.hz=0;this.hOk=false;this.dzMove=true;
      WM.repaintAll()
    }
  };
  // Native Android SensorManager fallback. Values are supplied in degrees.
  window.__nxNativeOrientation=function(a,b,g){
    /* Eski Euler yolu: artık kullanılmıyor (gimbal kilidi ve çift ekran-döndürme titreme yapıyordu). */
  };
  /* Yeni yol: Android'in ekrana göre döndürülmüş 3x3 dönüş matrisi (satır sıralı, cihaz -> ENU dünya). */
  window.__nxNativeMatrix=function(a,b,c,d,e,f,g,h,i){
    if(!Cam.gyro||!Cam.nm)return;
    const v=[a,b,c,d,e,f,g,h,i];
    for(let n=0;n<9;n++)if(!Number.isFinite(v[n]))return;
    Cam.nm.set(a,b,c,0,d,e,f,0,g,h,i,0,0,0,0,1);
    Cam.nq.setFromRotationMatrix(Cam.nm);
    Cam.nqT=performance.now();Cam.nqOk=true;Cam.nCnt++
  };
  /* Stage 66 hibrit: Java ekran eksenlerine çevrilmiş (x sağ, y yukarı, z ekrandan dışarı) yerçekimi/ivme vektörü. */
  window.__nxNativeGrav=function(x,y,z){
    if(!Cam.gyro)return;
    if(!(Number.isFinite(x)&&Number.isFinite(y)&&Number.isFinite(z)))return;
    const m=Math.sqrt(x*x+y*y+z*z);if(m<1)return;
    Cam.gx=x/m;Cam.gy=y/m;Cam.gz=z/m;
    Cam.hT=performance.now();Cam.hOk=true;Cam.nCnt++
  };
  /* ---------- 3B sahne: yalnızca duvar kağıdı, zemin, halka ---------- */
  const Scene={
    dirty:true,
    scene:null,
    rc:null,
    sky:null,
    floor:null,
    ring:null,
    sun:null,
    count(){
      let n=0;
      this.scene.traverse(()=>n++);
      return n
    },
    grad(stops,w,h){
      const c=document.createElement('canvas');
      c.width=w;
      c.height=h;
      const x=c.getContext('2d'),g=x.createLinearGradient(0,0,0,h);
      stops.forEach(s=>g.addColorStop(s[0],s[1]));
      x.fillStyle=g;
      x.fillRect(0,0,w,h);
      return new THREE.CanvasTexture(c)
    },
    init(){
      const s=this.scene=new THREE.Scene();
      s.fog=new THREE.Fog(0x3a2f66,12,48);
      s.add(Cam.rig);
      this.rc=new THREE.Raycaster();
      this.sky=new THREE.Mesh(new THREE.SphereGeometry(90,48,32),new THREE.MeshBasicMaterial({side:THREE.BackSide,fog:false}));
      s.add(this.sky);
      const fc=document.createElement('canvas');
      fc.width=fc.height=256;
      const x=fc.getContext('2d'),g=x.createRadialGradient(128,128,0,128,128,128);
      g.addColorStop(0,'#1d2a5a');
      g.addColorStop(.5,'#0c1430');
      g.addColorStop(1,'#050914');
      x.fillStyle=g;
      x.fillRect(0,0,256,256);
      this.floor=new THREE.Mesh(new THREE.CircleGeometry(40,64),new THREE.MeshStandardMaterial({map:new THREE.CanvasTexture(fc),roughness:.95}));
      this.floor.rotation.x=-Math.PI/2;
      this.floor.visible=false;
      this.ring=new THREE.Mesh(new THREE.RingGeometry(3.1,3.16,96),new THREE.MeshBasicMaterial({color:0x2f7bff,transparent:true,opacity:.7,fog:false}));
      this.ring.rotation.x=-Math.PI/2;
      this.ring.visible=false;
      s.add(new THREE.HemisphereLight(0x9fbaff,0x1a1030,1));
      const sun=this.sun=new THREE.DirectionalLight(0xffe0c0,.7);
      sun.position.set(-2,9,6);
      const sc=sun.shadow.camera;
      sc.left=sc.bottom=-8;
      sc.right=sc.top=8;
      sc.far=25;
      s.add(sun)
    },
    setSky(t,f,flip){
      const m=this.sky.material;
      if(m.map)m.map.dispose();
      if(flip){
        t.wrapS=THREE.RepeatWrapping;
        t.repeat.x=-1
      }
      m.map=t;
      m.needsUpdate=true;
      this.dirty=true;
      this.scene.fog.color.set(f)
    },
    setWP(i){
      if(typeof Places!=='undefined'&&Places.on)Places.exit();
      const P=WALL[i]||WALL[0];
      let t;
      try{
        const cv=WallArt.make(P.id);
        WallArt.keep(P.id,cv);
        t=new THREE.CanvasTexture(cv)
      }catch(e){
        t=this.grad(P.s,4,256)
      }
      this.setSky(t,P.f)
    },
    loadWP(src,save){
      const im=new Image();
      im.onload=()=>{
        const c=document.createElement('canvas');
        c.width=2048;
        c.height=1024;
        c.getContext('2d').drawImage(im,0,0,2048,1024);
        this.setSky(new THREE.CanvasTexture(c),'#10162e',true);
        Settings.v.wp=-1;
        Settings.save();
        WM.repaintAll();
        if(save){
          try{
            localStorage.setItem('nexus.wp',c.toDataURL('image/jpeg',.7))
          }catch(e){
            Diag.toast('Duvar kağıdı bu oturumda kullanılacak (kaydedilemedi)','var(--warn)')
          }
        }
      };
      im.onerror=()=>Diag.toast('Görsel yüklenemedi','var(--err)');
      im.src=src
    },
    targets(){
      const L=WM.panels.filter(p=>p.visible);
      for(const p of L.slice()){const k=p.userData.pill;if(k&&k.visible&&!k.userData.dead&&!p.userData.anim)L.push(k)}
      if(HMenu.open&&HMenu.m)L.push(HMenu.m);
      return L
    },
    pick(ray){
      this.rc.ray.copy(ray);
      return this.rc.intersectObjects(this.targets(),false)[0]||null
    }
  };
