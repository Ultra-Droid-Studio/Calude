'use strict';
  const Cinema={
    room:(()=>{try{const v=parseInt(localStorage.getItem('nexus.cinRoom'),10);return v>=0&&v<8&&v!==1&&v!==2?v:0}catch(e){return 0}})(),rg:null,rgLoading:false,mg:null,mgLoading:false,eg:null,ec:{},ecl:{},
    ROOMS:[{n:'Salon',R:7,y:2.9,W:5.4,eye:1.15},{n:'Roblox evi',R:4.59,y:1.8,W:2.7,eye:1.24},
      {n:'Minecraft dünyası',R:3.9,y:1.9,W:2.6,eye:1.7},
      {n:'Gün batımı',R:3.9,y:1.45,W:3.4,eye:1.15,env:'sunset'},{n:'Gece',R:3.9,y:1.45,W:3.4,eye:1.15,env:'night'},
      {n:'Uzay',R:3.9,y:1.45,W:3.4,eye:1.15,env:'space'},{n:'Stüdyo',R:3.9,y:1.45,W:3.4,eye:1.15,env:'studio'},
      {n:'Brawl arena',R:3.9,y:1.45,W:3.4,eye:1.15,env:'brawl',img:'brawl.jpg',yaw:70}],
    on:false,built:false,busy:false,g:null,v:null,scr:null,playing:false,name:'',url:null,prev:null,dust:null,dockShown:null,videoCanvas:null,videoCtx:null,
    toggle(){this.on?this.exit():this.enter()},
    enter(){
      if(this.on||this.busy)return;
      if(Places.on)Places.exit();
      if(Game.on)Game.exit();if(Planets.on)Planets.exit();if(window.Gorilla&&Gorilla.on)Gorilla.exit();
      this.busy=true;
      if(Launcher.open)Launcher.close();if(QS.open)QS.close();
      const go=()=>{try{this.build();this.show()}catch(e){Diag.toast('Sinema açılamadı','var(--err)')}this.busy=false};
      if(XR.session){go();return}
      const sub=$('#isub'),b=$('#istart'),old=[Intro.TXT,sub.textContent,b.textContent];
      Intro.TXT='SİNEMA KEYFİNE HAZIR OLUN';
      sub.textContent='Sinema salonu hazırlanıyor…';
      b.textContent='BAŞLA';
      setTimeout(()=>{try{this.build()}catch(e){}},40);
      Intro.run(()=>{Intro.TXT=old[0];sub.textContent=old[1];b.textContent=old[2];go()})
    },
    tx(w,h,f,rx,ry){
      const c=document.createElement('canvas');
      c.width=w;c.height=h;
      f(c.getContext('2d'),w,h);
      const t=new THREE.CanvasTexture(c);
      if(rx){t.wrapS=t.wrapT=THREE.RepeatWrapping;t.repeat.set(rx,ry)}
      return t
    },
    build(){
      if(this.built)return;
      this.built=true;
      const T=this.tx.bind(this),g=this.g=new THREE.Group(),D=THREE.DoubleSide;
      const M=(m,o)=>new THREE.MeshBasicMaterial(Object.assign(m&&m.isTexture?{map:m}:{color:m},o||{}));
      const add=(geo,mat,x,y,z,rx,ry)=>{const m=new THREE.Mesh(geo,mat);m.position.set(x,y,z);if(rx)m.rotation.x=rx;if(ry)m.rotation.y=ry;g.add(m);return m};
      const P=(w,h)=>new THREE.PlaneGeometry(w,h),Bx=(w,h,d)=>new THREE.BoxGeometry(w,h,d);
      const cc={},carpet=r=>cc[r]||(cc[r]=carpet0(r)),carpet0=r=>T(256,256,(c,w,h)=>{c.fillStyle='#4a0c1a';c.fillRect(0,0,w,h);c.strokeStyle='rgba(214,170,90,.22)';c.lineWidth=2;for(let i=-4;i<=8;i++){c.beginPath();c.moveTo(i*32,0);c.lineTo(i*32+h,h);c.moveTo(i*32+h,0);c.lineTo(i*32,h);c.stroke()}for(let i=0;i<500;i++){c.fillStyle='rgba(0,0,0,'+Math.random()*.25+')';c.fillRect(Math.random()*w,Math.random()*h,2,2)}},r,r);
      const wc={},wall=(rx,ry)=>wc[rx+'_'+ry]||(wc[rx+'_'+ry]=wall0(rx,ry)),wall0=(rx,ry)=>T(256,256,(c,w,h)=>{const q=c.createLinearGradient(0,0,0,h);q.addColorStop(0,'#2a0b14');q.addColorStop(.5,'#3b1320');q.addColorStop(1,'#220910');c.fillStyle=q;c.fillRect(0,0,w,h);for(let x=0;x<w;x+=32){c.fillStyle='rgba(0,0,0,.35)';c.fillRect(x,0,3,h);c.fillStyle='rgba(255,200,150,.06)';c.fillRect(x+3,0,2,h)}c.fillStyle='#b8893a';c.fillRect(0,h-10,w,5);c.fillRect(0,4,w,3)},rx,ry);
      const curt=T(256,256,(c,w,h)=>{for(let x=0;x<w;x++){const s=Math.sin(x/w*Math.PI*2*8);c.fillStyle='rgb('+(120+55*s|0)+','+(10+8*s|0)+','+(28+12*s|0)+')';c.fillRect(x,0,1,h)}const q=c.createLinearGradient(0,0,0,h);q.addColorStop(0,'rgba(0,0,0,.45)');q.addColorStop(.35,'rgba(0,0,0,0)');q.addColorStop(1,'rgba(0,0,0,.5)');c.fillStyle=q;c.fillRect(0,0,w,h)},5,1);
      const ceil=T(256,256,(c,w,h)=>{c.fillStyle='#14090d';c.fillRect(0,0,w,h);c.strokeStyle='#2b1319';c.lineWidth=4;c.strokeRect(2,2,w-4,h-4);c.fillStyle='rgba(255,220,170,.5)';for(let i=0;i<4;i++)c.fillRect(w/2-2+(i%2?18:-18),h/2-2+(i<2?-18:18),3,3)},9,9);
      const glow=T(128,128,(c,w,h)=>{const q=c.createRadialGradient(64,64,0,64,64,64);q.addColorStop(0,'rgba(255,190,110,.9)');q.addColorStop(1,'rgba(255,150,60,0)');c.fillStyle=q;c.fillRect(0,0,w,h)});
      const seatT=T(64,64,(c,w,h)=>{const q=c.createLinearGradient(0,0,0,h);q.addColorStop(0,'#a3182f');q.addColorStop(1,'#5e0a19');c.fillStyle=q;c.fillRect(0,0,w,h);c.strokeStyle='rgba(0,0,0,.35)';c.lineWidth=2;c.strokeRect(5,5,w-10,h-10)});
      const X0=-8,X1=8,Z0=-10,Z1=8,Y0=-1.2,Y1=5.6,hr=i=>i*.18;
      add(P(18,6.8),M(wall(9,1.5),{side:D}),X0,2.2,-1,0,Math.PI/2);
      add(P(18,6.8),M(wall(9,1.5),{side:D}),X1,2.2,-1,0,-Math.PI/2);
      add(P(16,6.8),M(wall(8,1.5),{side:D}),0,2.2,Z1,0,Math.PI);
      add(P(16,6.8),M(curt,{side:D}),0,2.2,Z0);
      add(P(16,18),M(ceil,{side:D}),0,Y1,-1,Math.PI/2);
      add(P(16,6),M(carpet(6),{side:D}),0,hr(-4),-7.5,-Math.PI/2);
      add(Bx(15.6,.9,4.2),M(0x2b1a12),0,hr(-4)+.2,-8,0,0).position.y=hr(-4)-.25;
      const sn=[],seatPos=[],led=[];
      for(let i=-4;i<=6;i++){
        const z=i*1.1,h=hr(i);
        add(Bx(15.6,h-Y0,1.1),M(carpet(3)),0,(h+Y0)/2,z);
        led.push([-3.4,h+.02,z-.5],[3.4,h+.02,z-.5]);
        for(let k=-12;k<=12;k++){const x=k*.6,ax=Math.abs(x);if(ax>3.2&&ax<4.4)continue;seatPos.push([x,h,z])}
      }
      /* Yumuşak koltuk: küp->küre karışımı (yumuşak kenar), tepe ışığına göre köşe renkleriyle gölgelendirilir.
         Dört parça tek geometride birleştirilir: tek InstancedMesh = tek çizim çağrısı. */
      const n=seatPos.length,o=new THREE.Object3D(),sBase=new THREE.Color(0x9b1b32),sDark=new THREE.Color(0x2a1a1e),LD=new THREE.Vector3(-.2,.8,-.55).normalize();
      const piece=(w,hh,d,k,t,col,px,py,pz,rx)=>{
        const bg=new THREE.BoxGeometry(2,2,2,k,k,k),pa=bg.attributes.position,nn=pa.count,cl=new Float32Array(nn*3),v=new THREE.Vector3(),s=new THREE.Vector3(),m=new THREE.Matrix4().makeRotationX(rx||0);
        for(let i=0;i<nn;i++){
          v.fromBufferAttribute(pa,i);s.copy(v).normalize();
          v.multiplyScalar(1-t).addScaledVector(s,t*1.15);
          let sh=.42+.62*Math.max(0,s.dot(LD));if(s.y<-.35)sh*=.6;
          cl[i*3]=col.r*sh;cl[i*3+1]=col.g*sh;cl[i*3+2]=col.b*sh;
          v.set(v.x*w/2,v.y*hh/2,v.z*d/2).applyMatrix4(m);
          pa.setXYZ(i,v.x+px,v.y+py,v.z+pz)
        }
        bg.setAttribute('color',new THREE.BufferAttribute(cl,3));
        return bg
      };
      const parts=[piece(.52,.2,.5,4,.55,sBase,0,.3,0),piece(.52,.78,.14,4,.5,sBase,0,.68,.3,-.14),piece(.07,.36,.46,2,.5,sBase,.29,.34,.02),piece(.14,.26,.14,1,0,sDark,0,.13,0)];
      let vc=0,ic=0;parts.forEach(q=>{vc+=q.attributes.position.count;ic+=q.index.count});
      const gp=new Float32Array(vc*3),gc=new Float32Array(vc*3),gi=new Uint16Array(ic);
      let vo=0,io=0;
      parts.forEach(q=>{gp.set(q.attributes.position.array,vo*3);gc.set(q.attributes.color.array,vo*3);for(let i=0;i<q.index.count;i++)gi[io+i]=q.index.array[i]+vo;vo+=q.attributes.position.count;io+=q.index.count;q.dispose()});
      const sg=new THREE.BufferGeometry();sg.setAttribute('position',new THREE.BufferAttribute(gp,3));sg.setAttribute('color',new THREE.BufferAttribute(gc,3));sg.setIndex(new THREE.BufferAttribute(gi,1));
      const sb=new THREE.InstancedMesh(sg,new THREE.MeshBasicMaterial({vertexColors:true}),n);
      seatPos.forEach((s,i)=>{o.position.set(s[0],s[1],s[2]);o.updateMatrix();sb.setMatrixAt(i,o.matrix)});
      sb.frustumCulled=false;g.add(sb);
      const lm=new THREE.InstancedMesh(Bx(.1,.03,.3),M(0xffb050),led.length);
      led.forEach((p,i)=>{o.position.set(p[0],p[1],p[2]);o.updateMatrix();lm.setMatrixAt(i,o.matrix)});lm.frustumCulled=false;g.add(lm);
      add(Bx(14,.04,.05),M(0xffb050),0,hr(-4)+.3,-6.0);
      /* Gerçek perde: siyah maskeleme çerçevesi + beyaz yüzey (yüzey cinscreen panelinde çizilir) + hafif ışık yayılımı */
      add(P(6.5,3.9),M(0x050506),0,2.9,-7.78);
      const gw=T(128,128,(c,w,h)=>{const q=c.createRadialGradient(64,64,0,64,64,64);q.addColorStop(0,'rgba(235,242,255,.9)');q.addColorStop(1,'rgba(235,242,255,0)');c.fillStyle=q;c.fillRect(0,0,w,h)});
      const gs=this.glowS=new THREE.Sprite(new THREE.SpriteMaterial({map:gw,blending:THREE.AdditiveBlending,transparent:true,depthWrite:false,opacity:.16}));gs.scale.set(9,5.4,1);gs.position.set(0,2.9,-6.4);g.add(gs);
      add(P(16,1.3),M(T(256,64,(c,w,h)=>{c.fillStyle='#5d0b19';c.fillRect(0,0,w,h);c.fillStyle='#7a1124';for(let x=0;x<w;x+=32){c.beginPath();c.arc(x+16,h*.55,16,0,Math.PI);c.fill()}c.fillStyle='#c9a24a';c.fillRect(0,h-6,w,4)},8,1),{side:D}),0,4.95,Z0+.05);
      add(P(4,.5),M(T(512,64,(c,w,h)=>{c.fillStyle='#1a0a0f';c.fillRect(0,0,w,h);c.strokeStyle='#c9a24a';c.lineWidth=3;c.strokeRect(3,3,w-6,h-6);c.fillStyle='#e8c46a';c.font='700 34px system-ui';c.textAlign='center';c.fillText('NEX VR SİNEMA',w/2,h/2+12)})),0,5.1,Z0+.08);
      [-5.4,5.4].forEach(x=>{add(Bx(.9,1.9,.5),M(0x15151a),x,0,-9.6);add(P(.7,1.5),M(T(32,32,(c,w,h)=>{c.fillStyle='#050507';c.fillRect(0,0,w,h);c.fillStyle='#222';for(let a=2;a<w;a+=4)for(let b=2;b<h;b+=4)c.fillRect(a,b,2,2)})),x,0,-9.34)});
      for(let z=-8;z<=7;z+=2.5)[X0,X1].forEach(x=>{const s=x<0?1:-1;add(Bx(.1,.5,.26),M(0xffd9a0),x+s*.06,2.6,z);const sp=new THREE.Sprite(new THREE.SpriteMaterial({map:glow,blending:THREE.AdditiveBlending,transparent:true,depthWrite:false,opacity:.7}));sp.scale.set(1.8,2.6,1);sp.position.set(x+s*.4,2.6,z);g.add(sp)});
      [X0+.1,X1-.1].forEach(x=>add(Bx(.08,.08,18),M(0xff9a48),x,5.3,-1));
      [-6,-3,0,3,6].forEach(x=>add(Bx(.12,.04,17),M(0x6b5a48),x,Y1-.03,-1));
      [-6.5,6.5].forEach(x=>{add(Bx(1.5,2.5,.1),M(0x120709),x,hr(6)+1.25,Z1-.05);add(P(1.0,.3),M(T(128,40,(c,w,h)=>{c.fillStyle='#062c14';c.fillRect(0,0,w,h);c.fillStyle='#3dff8a';c.font='700 24px system-ui';c.textAlign='center';c.fillText('ÇIKIŞ',w/2,h/2+8)})),x,hr(6)+2.9,Z1-.06,0,Math.PI)});
      add(P(1.3,.5),M(0x050304),0,3.7,Z1-.04,0,Math.PI);
      const sp=new THREE.Sprite(new THREE.SpriteMaterial({map:glow,blending:THREE.AdditiveBlending,transparent:true,depthWrite:false,opacity:.8}));sp.scale.set(1.2,.8,1);sp.position.set(0,3.7,Z1-.3);g.add(sp);
      add(new THREE.CylinderGeometry(.06,1.7,14.5,20,1,true),M(0xcfe0ff,{transparent:true,opacity:.035,blending:THREE.AdditiveBlending,depthWrite:false,side:D}),0,3.5,.5,Math.PI/2);
      const N=180,pa=new Float32Array(N*3);
      for(let i=0;i<N;i++){pa[i*3]=(Math.random()-.5)*8;pa[i*3+1]=.5+Math.random()*4;pa[i*3+2]=-6+Math.random()*13}
      const pg=new THREE.BufferGeometry();pg.setAttribute('position',new THREE.BufferAttribute(pa,3));
      this.dust=new THREE.Points(pg,new THREE.PointsMaterial({size:.04,color:0xffe9c4,transparent:true,opacity:.5,blending:THREE.AdditiveBlending,depthWrite:false}));
      this.dust.frustumCulled=false;g.add(this.dust);
      g.visible=false;Scene.scene.add(g);
      const v=this.v=document.createElement('video');
      v.playsInline=true;v.setAttribute('playsinline','');v.preload='auto';v.disableRemotePlayback=true;v.autoplay=false;
      v.controls=false;v.loop=false;v.muted=false;v.volume=1;
      const rp=()=>{const pl=!v.paused&&!v.ended;this.playing=pl;this.paint();if(this.vm){this.fit();this.vm.visible=pl}Scene.dirty=true};
      ['play','playing','pause','ended','loadedmetadata','loadeddata','canplay','seeked','volumechange'].forEach(e=>v.addEventListener(e,rp));
      v.addEventListener('error',()=>{this.playing=false;this.paint();Diag.toast('Video açılamadı. Tablette MP4 (H.264 + AAC) deneyin.','var(--err)',5000)});
      v.addEventListener('loadedmetadata',()=>{this.fit();this.paint()});
      const startPlayback=()=>v.play().then(()=>{this.playing=true;this.paint();Scene.dirty=true}).catch(()=>{this.paint();Diag.toast('Oynatma engellendi veya video biçimi desteklenmiyor. Oynat düğmesine dokun.','var(--warn)',4500)});
      $('#cinf').onchange=e=>{
        const f=e.target.files&&e.target.files[0];
        e.target.value='';
        if(!f)return;
        if(this.url)URL.revokeObjectURL(this.url);
        this.playing=false;v.pause();v.removeAttribute('src');v.load();
        this.url=URL.createObjectURL(f);
        this.name=f.name;v.src=this.url;v.load();
        const onReady=()=>{v.removeEventListener('loadedmetadata',onReady);this.fit();this.paint();startPlayback()};
        v.addEventListener('loadedmetadata',onReady);
        v.addEventListener('loadeddata',()=>{if(v.readyState>=2){this.paint();Scene.dirty=true}},{once:true});
      }
    },
    show(){
      const p=this.prev={vis:WM.panels.map(m=>[m,m.visible]),y:Cam.rig.position.y,sky:Scene.sky.visible,fl:Scene.floor.visible,rg:Scene.ring.visible,fog:[Scene.scene.fog.near,Scene.scene.fog.far]};
      Scene.sky.visible=Scene.floor.visible=Scene.ring.visible=false;
      Scene.scene.fog.near=60;Scene.scene.fog.far=120;
      Cam.rig.position.y=1.15;Cam.reset();
      if(!this.scr){
        this.scr=WM.create({id:'cinscreen',title:'Sinema',chrome:false,span:.714,h:1.287,R:7,y:2.9,ang:0,cflat:true,curve:false,live:false,render:(c,W,H,B)=>this.render(c,W,H,B)});
        const u=this.scr.userData,r=u.cv.height/u.cv.width;
        u.cv.width=1920;u.cv.height=Math.round(1920*r);u.tex.dispose();
        // Cap the WebGL upload size for high-resolution files on tablets; audio remains on the video element.
        const vv=this.v;
        const vt=this.vt=new THREE.VideoTexture(vv);
        vt.minFilter=vt.magFilter=THREE.LinearFilter;vt.generateMipmaps=false;
        vt.update=()=>{}; /* her render karesinde otomatik yükleme yok; yalnızca yeni video karesinde */
        this.vm=new THREE.Mesh(new THREE.PlaneGeometry(1,1),new THREE.MeshBasicMaterial({map:vt,side:THREE.DoubleSide,fog:false,toneMapped:false}));
        this.vm.visible=false;Scene.scene.add(this.vm);
        const updateVideoTexture=()=>{
          if(vv.readyState>=2){vt.needsUpdate=true;Scene.dirty=true}
          if(vv.requestVideoFrameCallback)vv.requestVideoFrameCallback(updateVideoTexture);
        };
        if(vv.requestVideoFrameCallback)vv.requestVideoFrameCallback(updateVideoTexture);
      }
      this.fit();
      this.dk=WM.panels.find(m=>m.userData.id==='dock');
      if(this.dk){this.dk.material.depthTest=false;this.dk.renderOrder=999}
      this.on=true;this.playing=false;this.dockShown=null;this.applyRoom();
      this.tick();Scene.dirty=true;WM.repaintAll();
      Diag.toast('Sinema: perdeye dokunarak video seç','var(--ok)',3200)
    },
    exit(){
      if(!this.on)return;
      this.v.pause();this.on=false;this.g.visible=false;if(this.rg)this.rg.visible=false;if(this.mg)this.mg.visible=false;
      if(this.eg){this.eg.visible=false;if(this.eg.material.map)this.eg.material.map.dispose()}
      const p=this.prev;
      if(p){p.vis.forEach(a=>a[0].visible=a[1]);Cam.rig.position.y=p.y;Scene.sky.visible=p.sky;Scene.floor.visible=p.fl;Scene.ring.visible=p.rg;Scene.scene.fog.near=p.fog[0];Scene.scene.fog.far=p.fog[1]}
      if(this.scr)this.scr.visible=false;
      if(this.vm)this.vm.visible=false;
      if(this.dk){this.dk.material.depthTest=true;this.dk.renderOrder=0}
      Scene.dirty=true;WM.repaintAll()
    },
    paint(){if(this.scr)WM.paint(this.scr)},
    /* Oda: 0 = sinema salonu, 1 = Roblox evi, 2 = Minecraft dünyası (ikisi de perde şömine/portre yerinde kalır). Yüklenene kadar salon görünür. */
    nextRoom(){let n=(this.room+1)%this.ROOMS.length;while(n===1||n===2)n=(n+1)%this.ROOMS.length;this.setRoom(n)}, /* 1 = Roblox, 2 = Minecraft artık Sinema odası değil: Places (mekân) olarak açılır */
    setRoom(i){
      this.room=i;try{localStorage.setItem('nexus.cinRoom',String(i))}catch(e){}
      if(this.on)this.applyRoom();
      if(this.scr)WM.paint(this.scr);Scene.dirty=true
    },
    loadPano(R){
      if(this.ecl[R.env])return;
      this.ecl[R.env]=1;Diag.toast(R.n+' yükleniyor…','var(--ok)',2000);
      const im=new Image();
      im.onload=()=>{
        const t=new THREE.Texture(im);t.minFilter=t.magFilter=THREE.LinearFilter;t.generateMipmaps=false;t.needsUpdate=true;
        this.ec[R.env]=t;if(this.on)this.applyRoom()
      };
      im.onerror=()=>{this.ecl[R.env]=0;Diag.toast(R.n+' yüklenemedi','var(--err)',4000);if(this.room===this.ROOMS.indexOf(R))this.room=0;if(this.on)this.applyRoom()};
      im.src=R.img
    },
    loadRoblox(){
      if(this.rg||this.rgLoading)return;
      this.rgLoading=true;Diag.toast('Roblox evi yükleniyor…','var(--ok)',2500);
      GLBRoom.load('roblox_house.glb').then(g=>{
        const S=.225,rg=this.rg=new THREE.Group();
        g.scale.setScalar(S);g.position.set(-11*S,-23*S,17*S); /* oturma noktası (11,23,-17) başlangıca gelir; perde -z yönünde */
        rg.add(g);
        rg.add(new THREE.AmbientLight(0xffffff,.85));
        const dl=new THREE.DirectionalLight(0xffffff,.55);dl.position.set(.3,1,.5);rg.add(dl);
        const sky=new THREE.Mesh(new THREE.SphereGeometry(90,16,10),new THREE.MeshBasicMaterial({color:0x8cbff2,side:THREE.BackSide,fog:false,depthWrite:false}));
        sky.renderOrder=-1;sky.frustumCulled=false;rg.add(sky);
        rg.visible=false;Scene.scene.add(rg);this.rgLoading=false;
        if(this.on)this.applyRoom();if(Places.on)Places.refresh();Scene.dirty=true
      }).catch(e=>{
        this.rgLoading=false;this.room=0;
        Diag.toast('Roblox evi yüklenemedi','var(--err)',4000);
        if(Places.on&&Places.kind==='roblox')Places.exit();
        if(this.on)this.applyRoom()
      })
    },
    loadMinecraft(){
      if(this.mg||this.mgLoading)return;
      this.mgLoading=true;
      try{
        const mg=this.mg=MCWorld.build();
        mg.visible=false;Scene.scene.add(mg);this.mgLoading=false;
        if(this.on)this.applyRoom();if(Places.on)Places.refresh();Scene.dirty=true
      }catch(e){
        this.mgLoading=false;this.room=0;
        Diag.toast('Minecraft dünyası yüklenemedi','var(--err)',4000);
        if(Places.on&&Places.kind==='minecraft')Places.exit();
        if(this.on)this.applyRoom()
      }
    },
    applyRoom(){
      const R0=this.ROOMS[this.room];
      if(this.room===1&&!this.rg)this.loadRoblox();
      if(this.room===2&&!this.mg)this.loadMinecraft();
      if(R0.img&&!this.ec[R0.env])this.loadPano(R0);
      /* Yüklenmesi süren oda hazır olana kadar salon görünür */
      const eff=(this.room===1&&!this.rg)||(this.room===2&&!this.mg)||(R0.img&&!this.ec[R0.env])?0:this.room,R=this.ROOMS[eff],u=this.scr&&this.scr.userData;
      this.g.visible=eff===0;
      if(this.rg)this.rg.visible=eff===1;
      if(this.mg)this.mg.visible=eff===2;
      if(R.env){
        let t=this.ec[R.env];
        if(!t&&!R.img){const cv=document.createElement('canvas');cv.width=2048;cv.height=1024;EnvSky.draw(R.env,cv.getContext('2d'),2048,1024);t=this.ec[R.env]=new THREE.CanvasTexture(cv);t.minFilter=t.magFilter=THREE.LinearFilter;t.generateMipmaps=false}
        if(!this.eg){
          const m=this.eg=new THREE.Mesh(new THREE.SphereGeometry(90,32,16),new THREE.MeshBasicMaterial({map:t,side:THREE.BackSide,fog:false,depthWrite:false}));
          m.renderOrder=-1;m.frustumCulled=false;Scene.scene.add(m)
        }
        /* scale.x=-1: resim içeriden aynalanmadan görünür; ortası (u=.5) bakılan yöne gelir, yaw ile sola döner */
        this.eg.scale.x=-1;this.eg.rotation.y=-Math.PI/2+(R.yaw||0)*Math.PI/180;
        const o=this.eg.material.map;
        if(o&&o!==t)o.dispose(); /* eski ortamın GPU kopyası bırakılır */
        this.eg.material.map=t;this.eg.visible=true
      }else if(this.eg)this.eg.visible=false;
      if(u){
        const ps=clamp(Settings.v.pscale||1,.7,1.3),r=u.cv.height/u.cv.width;
        u.R=R.R;u.y=R.y;u.base.span=R.W/(R.R*1.08*ps);u.base.h=(R.W*9/16)/(1.08*ps*R.R/3.2);
        WM.build(this.scr);
        u.cv.width=1920;u.cv.height=Math.round(1920*r);u.tex.dispose();
        this.fit();WM.paint(this.scr)
      }
      Cam.rig.position.y=R.eye;Scene.dirty=true
    },
    fit(){
      if(!this.scr||!this.vm)return;
      const u=this.scr.userData,v=this.v,vw=v.videoWidth||16,vh=v.videoHeight||9,s=Math.min(u.R*u.span/vw,u.h/vh);
      this.vm.scale.set(vw*s,vh*s,1);
      this.vm.position.set(0,u.y,-u.R+.02)
    },
    pick(){
      if(XR.session){Diag.toast('VR içinde dosya seçilemez','var(--warn)');return}
      $('#cinf').click()
    },
    seek(d){const v=this.v;if(v.src)v.currentTime=clamp(v.currentTime+d,0,v.duration||0)},
    fmt(s){s=Math.max(0,s|0);return((s/60)|0)+':'+('0'+(s%60)).slice(-2)},
    render(c,W,H,B){
      const v=this.v,has=!!(v&&v.src&&v.videoWidth&&v.readyState>=2);
      if(has&&!v.paused&&!v.ended){c.clearRect(0,0,W,H);c.textAlign='center';B(0,0,W,H,'',()=>v.pause(),false,null,'raw','Durdur');c.textAlign='left';return}
      if(has){c.fillStyle='#000';c.fillRect(0,0,W,H)}else{const q=c.createRadialGradient(W/2,H*.46,H*.1,W/2,H*.5,W*.62);q.addColorStop(0,'#fbfcfd');q.addColorStop(.7,'#e6e9ed');q.addColorStop(1,'#c4cad2');c.fillStyle=q;c.fillRect(0,0,W,H)}
      if(has){const s=Math.min(W/v.videoWidth,H/v.videoHeight),w=v.videoWidth*s,h=v.videoHeight*s;c.drawImage(v,(W-w)/2,(H-h)/2,w,h)}
      c.textAlign='center';
      if(has&&!v.paused&&!v.ended){B(0,0,W,H,'',()=>v.pause(),false,null,'raw','Durdur');c.textAlign='left';return}
      if(!v.src){
        c.fillStyle='#7a5a12';c.font='700 64px system-ui';c.fillText('NEX VR SİNEMA',W/2,H/2-30);
        c.fillStyle='#4b5563';c.font='34px system-ui';c.fillText('Video seçmek için perdeye dokun',W/2,H/2+36);
        B(0,0,W,H,'',()=>this.pick(),false,null,'raw','Video seç');B(W/2-210,H-150,420,76,'Oda: '+this.ROOMS[this.room].n,()=>this.nextRoom(),false,null,'pill');c.textAlign='left';return
      }
      c.fillStyle='rgba(0,0,0,.5)';c.fillRect(0,0,W,H);
      c.fillStyle='rgba(255,255,255,.92)';c.beginPath();c.moveTo(W/2-45,H/2-70);c.lineTo(W/2+75,H/2);c.lineTo(W/2-45,H/2+70);c.fill();
      B(W/2-110,H/2-110,220,220,'',()=>v.play().then(()=>{this.playing=true;this.paint();Scene.dirty=true}).catch(()=>{this.paint();Diag.toast('Bu video biçimi desteklenmiyor olabilir. MP4 H.264/AAC deneyin.','var(--warn)',4500)}),false,null,'raw','Oynat');
      c.fillStyle='#fff';c.font='34px system-ui';c.fillText(this.name.slice(0,60),W/2,90);
      const by=H-170,bw=W-240;
      c.fillStyle='rgba(255,255,255,.25)';c.fillRect(120,by,bw,10);
      c.fillStyle='#19d3c5';c.fillRect(120,by,bw*clamp(v.currentTime/(v.duration||1),0,1),10);
      c.fillStyle='#d6e3ff';c.font='28px system-ui';c.fillText(this.fmt(v.currentTime)+' / '+this.fmt(v.duration||0),W/2,by-20);
      const w=300,gap=30,x0=(W-(w*5+gap*4))/2,y=H-120;
      [['-10 sn',()=>this.seek(-10)],['Video değiştir',()=>this.pick()],['+10 sn',()=>this.seek(10)],['Oda: '+this.ROOMS[this.room].n,()=>this.nextRoom()],['Salondan çık',()=>this.exit()]].forEach((a,i)=>B(x0+i*(w+gap),y,w,76,a[0],a[1],false,null,'pill'));
      c.textAlign='left'
    },
    tick(){
      if(!this.on)return;
      const pl=this.playing;
      if(this.glowS)this.glowS.visible=!pl;
      if(pl&&this.vt&&!this.v.requestVideoFrameCallback)this.vt.needsUpdate=true;
      WM.panels.forEach(m=>{const id=m.userData.id;m.visible=id==='cinscreen'||(id==='dock'&&!pl)});
      if(this.dockShown!==!pl){this.dockShown=!pl;const d=WM.panels.find(m=>m.userData.id==='dock');d&&WM.paint(d)}
      const a=this.dust.geometry.attributes.position,t=performance.now()/4000;
      if(!pl)for(let i=0;i<a.count;i++){a.array[i*3+1]+=Math.sin(t+i)*.0015+.0006;a.array[i*3]+=Math.cos(t*.7+i)*.0008;if(a.array[i*3+1]>4.6)a.array[i*3+1]=.5}
      a.needsUpdate=true;Scene.dirty=true
    }
  };
  /* ---------- Mekânlar: Roblox evi / Minecraft dünyası. Sinema DEĞİL: normal pencereler (tarayıcı, ayarlar, uygulamalar) açılır, yalnızca arka plan 3D dünyaya dönüşür. ---------- */
  const Places={
    on:false,kind:null,prev:null,
    DEF:{roblox:{n:'Roblox evi',eye:1.24},minecraft:{n:'Minecraft dünyası',eye:1.7}},
    grp(k){return k==='roblox'?Cinema.rg:Cinema.mg},
    toggle(k){this.on&&this.kind===k?this.exit():this.enter(k)},
    enter(k){
      const d=this.DEF[k];if(!d)return;
      if(Cinema.on)Cinema.exit();if(Game.on)Game.exit();if(Planets.on)Planets.exit();if(window.Gorilla&&Gorilla.on)Gorilla.exit();
      if(Launcher.open)Launcher.close();if(QS.open)QS.close();
      if(!this.on){
        this.prev={y:Cam.rig.position.y,sky:Scene.sky.visible,fl:Scene.floor.visible,rg:Scene.ring.visible,fog:[Scene.scene.fog.near,Scene.scene.fog.far]};
        this.on=true
      }
      this.kind=k;
      const ready=!!this.grp(k);
      if(!ready){if(k==='roblox')Cinema.loadRoblox();else Cinema.loadMinecraft()}
      Diag.toast(d.n+(ready?' açıldı':' yükleniyor…'),'var(--ok)',2500);
      this.refresh();WM.repaintAll()
    },
    /* Dünya hazırsa göster (varsayılan gökyüzü/zemin gizlenir); hazır değilse normal ortam kalır */
    refresh(){
      if(!this.on||!this.prev)return;
      const g=this.grp(this.kind),rd=!!g,p=this.prev,d=this.DEF[this.kind];
      if(Cinema.rg)Cinema.rg.visible=rd&&this.kind==='roblox';
      if(Cinema.mg)Cinema.mg.visible=rd&&this.kind==='minecraft';
      Scene.sky.visible=rd?false:p.sky;Scene.floor.visible=rd?false:p.fl;Scene.ring.visible=rd?false:p.rg;
      Scene.scene.fog.near=rd?60:p.fog[0];Scene.scene.fog.far=rd?120:p.fog[1];
      Cam.rig.position.y=rd?d.eye:p.y;
      Scene.dirty=true
    },
    exit(){
      if(!this.on)return;
      const p=this.prev;this.on=false;this.kind=null;this.prev=null;
      if(Cinema.rg&&!Cinema.on)Cinema.rg.visible=false;
      if(Cinema.mg&&!Cinema.on)Cinema.mg.visible=false;
      if(p){Cam.rig.position.y=p.y;Scene.sky.visible=p.sky;Scene.floor.visible=p.fl;Scene.ring.visible=p.rg;Scene.scene.fog.near=p.fog[0];Scene.scene.fog.far=p.fog[1]}
      Scene.dirty=true;WM.repaintAll()
    }
  };
  /* ---------- Neon Kılıç: ışın kılıcıyla küp kesme oyunu ---------- */
  const Game={
    on:false,st:'menu',g:null,mp:null,prev:null,objs:[],deb:[],bl:{},src:{},last:0,dockShown:null,flash:0,
    best:(()=>{try{return+localStorage.getItem('nexus.saberBest')||0}catch(e){return 0}})(),
    S:{score:0,combo:0,maxCombo:0,cut:0,missed:0,avoided:0,time:0,tempo:1,maxTempo:1,spawn:0,n:0},
    C:{b:0x2f7bff,r:0xff2f4d},
    toggle(){this.on?this.exit():this.enter()},
    snd(f,d,t,v){
      try{
        const A=this.ac||(this.ac=new(window.AudioContext||window.webkitAudioContext)()),o=A.createOscillator(),g=A.createGain();
        o.type=t||'sine';o.frequency.value=f;
        g.gain.setValueAtTime(v||.12,A.currentTime);
        g.gain.exponentialRampToValueAtTime(.001,A.currentTime+d);
        o.connect(g);g.connect(A.destination);o.start();o.stop(A.currentTime+d)
      }catch(e){}
    },
    build(){
      if(this.g)return;
      this._a=new THREE.Vector3();this._w=new THREE.Vector3();this._d=new THREE.Vector3();this._u=new THREE.Vector3(0,1,0);
      const g=this.g=new THREE.Group(),M=(c,o)=>new THREE.MeshBasicMaterial(Object.assign({color:c},o||{}));
      const grid=this.grid=new THREE.GridHelper(80,80,0x8a4cff,0x2c1666);grid.position.set(0,0,-30);g.add(grid);
      [[-1.9,0xb04cff],[1.9,0x19d3c5]].forEach(a=>{const m=new THREE.Mesh(new THREE.BoxGeometry(.06,.03,80),M(a[1]));m.position.set(a[0],.02,-30);g.add(m)});
      this.rings=[];
      for(let i=0;i<8;i++){const r=new THREE.Mesh(new THREE.TorusGeometry(3.6,.035,6,48),M(i%2?0x7a3cff:0x19d3c5));r.position.set(0,1.6,-i*5);g.add(r);this.rings.push(r)}
      const N=420,pa=new Float32Array(N*3);
      for(let i=0;i<N;i++){const a=Math.random()*6.283,r=14+Math.random()*30;pa[i*3]=Math.cos(a)*r;pa[i*3+1]=Math.random()*18;pa[i*3+2]=-8-Math.random()*40}
      const pg=new THREE.BufferGeometry();pg.setAttribute('position',new THREE.BufferAttribute(pa,3));
      const st=new THREE.Points(pg,new THREE.PointsMaterial({size:.12,color:0xcfdcff,fog:false}));st.frustumCulled=false;g.add(st);
      this.geo={cube:new THREE.BoxGeometry(.42,.42,.42),bomb:new THREE.IcosahedronGeometry(.24,1),deb:new THREE.BoxGeometry(.12,.12,.12),bl:new THREE.CylinderGeometry(1,1,1,8)};
      this.mat={b:M(this.C.b),r:M(this.C.r),k:M(0x0b0b10),w:M(0xffffff),rw:M(0xff2020,{wireframe:true}),o:M(0xff8a2a)};
      this.edge=new THREE.EdgesGeometry(this.geo.cube);
      g.visible=false;Scene.scene.add(g);
      addEventListener('pointermove',e=>{this.mp={x:e.clientX/innerWidth,y:e.clientY/innerHeight,t:performance.now()}});
      this.fl=document.createElement('div');
      this.fl.style.cssText='position:fixed;inset:0;background:#ff1030;opacity:0;pointer-events:none;z-index:5';
      document.body.appendChild(this.fl)
    },
    enter(forceWithoutHands=false){
      if(this.on)return;
      if(!Hand.on&&!forceWithoutHands){
        let box=document.getElementById('nexus-hand-game-confirm');
        if(box)box.remove();
        box=document.createElement('div');box.id='nexus-hand-game-confirm';
        box.style.cssText='position:fixed;inset:0;z-index:100000;display:flex;align-items:center;justify-content:center;padding:20px;background:rgba(3,5,15,.78);backdrop-filter:blur(8px);font-family:system-ui,sans-serif';
        box.innerHTML='<div style="width:min(440px,100%);box-sizing:border-box;padding:24px;border:1px solid rgba(110,160,255,.45);border-radius:20px;background:linear-gradient(145deg,#111a31,#090d1a);color:#fff;box-shadow:0 18px 70px #0009"><div style="font-size:22px;font-weight:800;margin-bottom:10px">El takibi kapalı</div><div style="font-size:15px;line-height:1.55;color:#cbd6f2;margin-bottom:22px">Işın kılıcı oyununu el hareketlerinle oynamak için El Takibi’ni açman gerekiyor. İstersen el takibi olmadan dokunmatik kontrollerle de devam edebilirsin.</div><div style="display:flex;gap:10px;flex-wrap:wrap;justify-content:flex-end"><button id="nexus-hand-game-exit" style="padding:12px 18px;border:1px solid #59647e;border-radius:12px;background:#1b2438;color:#fff;font-weight:700">Çık</button><button id="nexus-hand-game-continue" style="padding:12px 18px;border:0;border-radius:12px;background:#19d3c5;color:#07111c;font-weight:800">Devam et</button></div></div>';
        document.body.appendChild(box);
        box.querySelector('#nexus-hand-game-exit').onclick=()=>box.remove();
        box.querySelector('#nexus-hand-game-continue').onclick=()=>{box.remove();this.enter(true)};
        return;
      }
      if(Cinema.on)Cinema.exit();if(Places.on)Places.exit();if(Planets.on)Planets.exit();if(window.Gorilla&&Gorilla.on)Gorilla.exit();
      if(Launcher.open)Launcher.close();if(QS.open)QS.close();
      this.build();Cam.reset();
      this.prev={vis:WM.panels.map(m=>[m,m.visible]),sky:Scene.sky.visible,fl:Scene.floor.visible,rg:Scene.ring.visible,fog:[Scene.scene.fog.near,Scene.scene.fog.far,Scene.scene.fog.color.clone()]};
      Scene.sky.visible=Scene.floor.visible=Scene.ring.visible=false;
      Scene.scene.fog.near=10;Scene.scene.fog.far=34;Scene.scene.fog.color.set(0x05010f);
      if(!this.menu){
        this.menu=WM.create({id:'gmenu',title:'Neon Kılıç',chrome:false,span:.7,h:1.43,R:2.9,y:1.7,ang:0,live:false,render:(c,W,H,B)=>this.rMenu(c,W,H,B)});
        this.hud=WM.create({id:'ghud',title:'Skor',chrome:false,span:.34,h:.33,R:5,y:3.05,ang:0,live:true,render:(c,W,H)=>this.rHud(c,W,H)})
      }
      this.g.visible=true;this.on=true;Hand.clr();Hand.setPreview();this.st='menu';this.dockShown=null;this.last=performance.now();
      this.tick();Scene.dirty=true;WM.repaintAll();
      Diag.toast(Hand.on?'El takibi açık: kılıçların parmak uçların':'El takibi kapalı: fare/parmakla oynayabilirsin','var(--ok)',3200)
    },
    exit(){
      if(!this.on)return;
      this.clear();this.on=false;Hand.setPreview();this.g.visible=false;this.fl.style.opacity=0;
      Object.values(this.bl).forEach(b=>b.visible=false);
      const p=this.prev;
      if(p){p.vis.forEach(a=>a[0].visible=a[1]);Scene.sky.visible=p.sky;Scene.floor.visible=p.fl;Scene.ring.visible=p.rg;Scene.scene.fog.near=p.fog[0];Scene.scene.fog.far=p.fog[1];Scene.scene.fog.color.copy(p.fog[2])}
      if(this.menu)this.menu.visible=false;if(this.hud)this.hud.visible=false;
      Scene.dirty=true;WM.repaintAll()
    },
    clear(){
      this.objs.forEach(o=>this.g.remove(o.m));this.objs=[];
      this.deb.forEach(d=>this.g.remove(d.m));this.deb=[]
    },
    start(){
      this.clear();
      Object.assign(this.S,{score:0,combo:0,maxCombo:0,cut:0,missed:0,avoided:0,time:0,tempo:1.25,maxTempo:1.25,spawn:1.2,n:0});
      this.st='play';this.dockShown=null;this.snd(660,.15,'triangle');this.tick();
      try{this.ac&&this.ac.resume&&this.ac.resume()}catch(e){}
    },
    over(){
      this.st='over';
      this.flash=1;this.snd(70,.7,'sawtooth',.3);
      if(this.S.score>this.best){this.best=this.S.score;try{localStorage.setItem('nexus.saberBest',this.best)}catch(e){}}
      this.objs.forEach(o=>this.g.remove(o.m));this.objs=[];
      this.dockShown=null;WM.paint(this.menu);Diag.say('Oyun bitti. Skor '+this.S.score)
    },
    spawnObj(){
      const S=this.S,aspect=Cam.cam.aspect||1.6,k=clamp(aspect/1.6,.45,1),xs=[-1,-.35,.35,1],ys=[1.0,1.5,2.0];
      const bomb=S.n>3&&Math.random()<.13+Math.min(S.tempo-1,3)*.035,col=Math.random()<.5?'b':'r';
      let m;
      if(bomb){m=new THREE.Mesh(this.geo.bomb,this.mat.k);m.add(new THREE.Mesh(this.geo.bomb,this.mat.rw).translateX(0));m.children[0].scale.setScalar(1.18)}
      else{m=new THREE.Mesh(this.geo.cube,this.mat[col]);m.add(new THREE.LineSegments(this.edge,this.mat.w))}
      m.position.set(xs[Math.random()*4|0]*k,ys[Math.random()*3|0],-17);
      m.rotation.set(Math.random()*3,Math.random()*3,Math.random()*3);
      this.g.add(m);this.objs.push({m,bomb,col,sp:(Math.random()-.5)*2});S.n++
    },
    burst(p,mat,n,sp){
      for(let i=0;i<n;i++){
        const m=new THREE.Mesh(this.geo.deb,mat);m.position.copy(p);
        this.g.add(m);
        this.deb.push({m,v:new THREE.Vector3((Math.random()-.5)*sp,(Math.random()-.2)*sp,(Math.random()-.3)*sp),t:0})
      }
    },
    sources(){
      const out=[],rc=Scene.rc;
      Hand.slots.forEach(s=>{if(s.on&&s.hasT){const lx=clamp(s.vx*.06,-.07,.07),ly=clamp(s.vy*.06,-.07,.07);rc.setFromCamera(new THREE.Vector2((s.sx+lx)*2-1,-((s.sy+ly)*2-1)),Cam.cam);out.push({id:'h'+s.id,d:rc.ray.direction.clone()})}});

      if(!out.length&&this.mp&&performance.now()-this.mp.t<4000){
        rc.setFromCamera(new THREE.Vector2(this.mp.x*2-1,-(this.mp.y*2-1)),Cam.cam);
        out.push({id:'m',d:rc.ray.direction.clone()})
      }
      return out
    },
    sd(p,a,b){
      const ab=this._a.copy(b).sub(a),w=this._w.copy(p).sub(a),L=ab.lengthSq(),u=L>1e-8?clamp(w.dot(ab)/L,0,1):0;
      return w.sub(ab.multiplyScalar(u)).length()
    },
    cyl(m,A,B,r){
      const d=this._d.copy(B).sub(A),l=d.length()||1e-4;
      m.position.copy(A).add(B).multiplyScalar(.5);
      m.quaternion.setFromUnitVectors(this._u,d.multiplyScalar(1/l));
      m.scale.set(r,l,r)
    },
    blade(id,i){
      let b=this.bl[id];
      if(!b){
        const col=i%2?this.C.r:this.C.b,ad=o=>new THREE.MeshBasicMaterial(Object.assign({color:col,transparent:true,blending:THREE.AdditiveBlending,depthWrite:false,fog:false},o)),
          cy=m=>new THREE.Mesh(this.geo.bl,m),u={};
        b=this.bl[id]=new THREE.Group();b.userData=u;
        u.gl2=cy(ad({opacity:.15}));u.gl1=cy(ad({opacity:.4}));
        u.co=cy(new THREE.MeshBasicMaterial({color:0xffffff,fog:false}));
        u.hl=cy(new THREE.MeshBasicMaterial({color:0x1b1b26,fog:false}));
        u.gd=cy(new THREE.MeshBasicMaterial({color:0x9aa0b8,fog:false}));
        u.rg=cy(ad({opacity:.9}));
        u.cap=new THREE.Mesh(new THREE.SphereGeometry(1,10,8),ad({opacity:.9}));
        const N=9,tg=new THREE.BufferGeometry();
        tg.setAttribute('position',new THREE.BufferAttribute(new Float32Array(N*6),3));
        tg.setAttribute('color',new THREE.BufferAttribute(new Float32Array(N*6),3));
        const ix=[];for(let k=0;k<N-1;k++){const a=k*2;ix.push(a,a+1,a+2,a+1,a+3,a+2)}
        tg.setIndex(ix);
        u.tr=new THREE.Mesh(tg,new THREE.MeshBasicMaterial({vertexColors:true,transparent:true,blending:THREE.AdditiveBlending,depthWrite:false,side:THREE.DoubleSide,fog:false}));
        u.tr.frustumCulled=false;u.hist=[];u.N=N;u.c=new THREE.Color(col);
        b.add(u.gl2,u.gl1,u.co,u.hl,u.gd,u.rg,u.cap,u.tr);this.g.add(b)
      }
      return b
    },
    pose(id,i,d,O){
      const b=this.blade(id,i),u=b.userData,T=O.clone().addScaledVector(d,2.7),H=O.clone().addScaledVector(d,.85);
      H.y-=.42;
      const bd=T.clone().sub(H).normalize(),H0=H.clone().addScaledVector(bd,.26);
      b.visible=true;
      this.cyl(u.hl,H.clone().addScaledVector(bd,-.1),H0,.034);
      this.cyl(u.gd,H0.clone().addScaledVector(bd,-.02),H0,.085);
      this.cyl(u.rg,H0,H0.clone().addScaledVector(bd,.02),.1);
      this.cyl(u.co,H0,T,.017);this.cyl(u.gl1,H0,T,.045);this.cyl(u.gl2,H0,T,.1);
      u.cap.position.copy(T);u.cap.scale.setScalar(.05);
      u.hist.unshift([H0,T]);if(u.hist.length>u.N)u.hist.pop();
      const pa=u.tr.geometry.attributes.position,ca=u.tr.geometry.attributes.color;
      for(let k=0;k<u.N;k++){
        const h=u.hist[Math.min(k,u.hist.length-1)],f=k?(1-k/u.N)*.5:0;
        pa.setXYZ(k*2,h[0].x,h[0].y,h[0].z);pa.setXYZ(k*2+1,h[1].x,h[1].y,h[1].z);
        ca.setXYZ(k*2,u.c.r*f,u.c.g*f,u.c.b*f);ca.setXYZ(k*2+1,u.c.r*f,u.c.g*f,u.c.b*f)
      }
      pa.needsUpdate=ca.needsUpdate=true;
      return[H0,T]
    },
    tick(){
      if(!this.on)return;
      const now=performance.now(),dt=Math.min(.05,Math.max(.001,(now-this.last)/1000));this.last=now;
      const S=this.S,play=this.st==='play',sp=play?4.8*Math.pow(S.tempo,.85):2;
      WM.panels.forEach(m=>{const id=m.userData.id;m.visible=id==='gmenu'?!play:id==='ghud'?play:false});
      if(this.dockShown!==!play){this.dockShown=!play;const d=WM.panels.find(m=>m.userData.id==='dock');d&&WM.paint(d)}
      this.grid.position.z=-30+((this.go=(this.go||0)+sp*dt)%1);
      this.rings.forEach(r=>{r.position.z+=sp*dt;if(r.position.z>4)r.position.z-=40});
      if(this.flash>0){this.flash=Math.max(0,this.flash-dt*1.8);this.fl.style.opacity=this.flash*.55}
      this.deb=this.deb.filter(d=>{d.t+=dt;d.v.y-=4*dt;d.m.position.addScaledVector(d.v,dt);d.m.scale.setScalar(Math.max(.01,1-d.t/.7));if(d.t>.7){this.g.remove(d.m);return false}return true});
      const O=Cam.cam.getWorldPosition(new THREE.Vector3()),srcs=this.sources(),used={};
      srcs.forEach((s,i)=>{
        const p=this.pose(s.id,i,s.d,O),q=this.src[s.id];used[s.id]=1;
        this.src[s.id]={H:p[0],T:p[1],pH:q?q.H:p[0],pT:q?q.T:p[1]}
      });
      if(!srcs.length)[0,1].forEach(i=>{used['d'+i]=1;this.pose('d'+i,i,new THREE.Vector3(i?.22:-.22,-.03+Math.sin(now/600+i*2)*.02,-1).normalize(),O)});
      Object.keys(this.bl).forEach(id=>{if(!used[id])this.bl[id].visible=false});
      if(play){
        S.time+=dt;S.tempo=1.25+Math.min(S.time/25,3.5);S.maxTempo=Math.max(S.maxTempo,S.tempo);
        S.spawn-=dt;
        if(S.spawn<=0){this.spawnObj();S.spawn=Math.max(.22,.85/Math.pow(S.tempo,.9))*(.8+Math.random()*.4)}
        const V=new THREE.Vector3(),A=new THREE.Vector3(),P0=new THREE.Vector3(),P1=new THREE.Vector3();
        for(let i=this.objs.length-1;i>=0&&this.st==='play';i--){
          const o=this.objs[i],m=o.m;
          m.position.z+=sp*dt;m.rotation.x+=dt*o.sp;m.rotation.y+=dt*.8;
          if(o.bomb)m.children[0].scale.setScalar(1.18+Math.sin(now/120)*.06);
          V.copy(m.position).sub(O);
          const t=V.dot(Cam.cam.getWorldDirection(A));
          if(t<.9&&m.position.z>-1.2||m.position.z>.2){
            this.g.remove(m);this.objs.splice(i,1);
            if(o.bomb)S.avoided++;else{S.missed++;S.combo=0}
            continue
          }
          if(t>3.1)continue;
          for(const s of srcs){
            const q=this.src[s.id];
            let md=9;
            for(let k=0;k<=3;k++){P0.lerpVectors(q.pH,q.H,k/3);P1.lerpVectors(q.pT,q.T,k/3);md=Math.min(md,this.sd(m.position,P0,P1))}
            const sp=q.T.distanceTo(q.pT)/dt;
            if(md<(o.bomb?.3:.29)&&(o.bomb||sp>.4)){
              this.objs.splice(i,1);this.g.remove(m);
              if(o.bomb){this.burst(m.position,this.mat.o,18,5);this.over()}
              else{
                S.cut++;S.combo++;S.maxCombo=Math.max(S.maxCombo,S.combo);
                S.score+=100*(1+Math.min(4,Math.floor(S.combo/10)));
                this.burst(m.position,this.mat[o.col],7,3);this.snd(480+Math.min(S.combo,30)*14,.12,'triangle')
              }
              break
            }
          }
        }
      }
      Scene.dirty=true
    },
    fmt(s){s=s|0;return((s/60)|0)+':'+('0'+(s%60)).slice(-2)},
    rHud(c,W,H){
      const S=this.S;
      rr(c,2,2,W-4,H-4,26);c.fillStyle='rgba(8,4,24,.7)';c.fill();c.lineWidth=3;c.strokeStyle='#7a3cff';c.stroke();
      c.textAlign='center';c.fillStyle='#9aa7c7';c.font='600 26px system-ui';
      c.fillText('SKOR',W*.2,52);c.fillText('KOMBO',W*.5,52);c.fillText('TEMPO',W*.8,52);
      c.fillStyle='#fff';c.font='800 78px system-ui';c.fillText(S.score,W*.2,H*.72);
      c.fillStyle=S.combo>=10?'#19d3c5':'#fff';c.fillText('x'+S.combo,W*.5,H*.72);
      c.fillStyle='#ffb04a';c.fillText(S.tempo.toFixed(1)+'x',W*.8,H*.72);
      c.textAlign='left'
    },
    rMenu(c,W,H,B){
      const S=this.S,ov=this.st==='over';
      rr(c,4,4,W-8,H-8,40);
      const q=c.createLinearGradient(0,0,0,H);q.addColorStop(0,'#16072f');q.addColorStop(1,'#050212');c.fillStyle=q;c.fill();
      c.lineWidth=4;c.strokeStyle=ov?'#ff2f4d':'#7a3cff';c.stroke();
      c.textAlign='center';c.shadowBlur=28;c.shadowColor=ov?'#ff2f4d':'#2f7bff';
      c.fillStyle='#fff';c.font='800 76px system-ui';c.fillText(ov?'OYUN BİTTİ':'NEON KILIÇ',W/2,110);c.shadowBlur=0;
      if(!ov){
        c.fillStyle='#2f7bff';c.fillRect(W/2-160,160,80,80);c.fillStyle='#ff2f4d';c.fillRect(W/2-40,160,80,80);
        c.fillStyle='#111';c.beginPath();c.arc(W/2+120,200,40,0,6.3);c.fill();c.strokeStyle='#ff2020';c.lineWidth=5;c.stroke();
        c.fillStyle='#d6e3ff';c.font='30px system-ui';
        c.fillText('Mavi ve kırmızı küpleri parmak ucunla kes.',W/2,H*.52);
        c.fillStyle='#ff6a7a';c.fillText('Bombalara dokunursan oyun biter!',W/2,H*.52+46);
        c.fillStyle='#9aa7c7';c.fillText('Tempo zamanla hızlanır.   Rekor: '+this.best,W/2,H*.52+100);
        B(W/2-200,H-170,400,96,'BAŞLAT',()=>this.start(),true,null,'pill','Oyunu başlat');
        B(W-270,H-96,230,60,'Çıkış',()=>this.exit(),false,null,'pill','Oyundan çık')
      }else{
        c.fillStyle='#ffb04a';c.font='800 110px system-ui';c.fillText(S.score,W/2,250);
        c.fillStyle='#9aa7c7';c.font='28px system-ui';c.fillText(S.score>=this.best&&S.score>0?'YENİ REKOR!':'SKOR',W/2,160);
        const acc=S.cut+S.missed?Math.round(S.cut*100/(S.cut+S.missed)):0;
        const rows=[['Kesilen küp',S.cut],['Kaçırılan küp',S.missed],['Kaçınılan bomba',S.avoided],['En yüksek kombo','x'+S.maxCombo],['Doğruluk','%'+acc],['Süre',this.fmt(S.time)],['Son tempo',S.maxTempo.toFixed(1)+'x'],['Rekor',this.best]];
        rows.forEach((r,i)=>{
          const x=W*(i%2?.54:.08),y=H*.5+Math.floor(i/2)*50;
          c.textAlign='left';c.fillStyle='#9aa7c7';c.font='28px system-ui';c.fillText(r[0],x,y);
          c.textAlign='right';c.fillStyle='#fff';c.font='700 30px system-ui';c.fillText(r[1],x+W*.38,y)
        });
        B(W/2-420,H-150,400,90,'TEKRAR OYNA',()=>this.start(),true,null,'pill','Tekrar oyna');
        B(W/2+20,H-150,400,90,'Çıkış',()=>this.exit(),false,null,'pill','Oyundan çık')
      }
      c.textAlign='left'
    }
  };

  /* ---------- Gezegen Şovu: Ay, Merkür, Venüs, Mars, Jüpiter, Satürn (prosedürel GLSL dokular) ---------- */
  const PGL={
    com:`
float h1(vec3 p){p=fract(p*.3183099+.1);p*=17.;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}
vec3 h3(vec3 p){p=vec3(dot(p,vec3(127.1,311.7,74.7)),dot(p,vec3(269.5,183.3,246.1)),dot(p,vec3(113.5,271.9,124.6)));return fract(sin(p)*43758.5453);}
float noise(vec3 x){vec3 i=floor(x),f=fract(x);f=f*f*(3.-2.*f);
return mix(mix(mix(h1(i),h1(i+vec3(1,0,0)),f.x),mix(h1(i+vec3(0,1,0)),h1(i+vec3(1,1,0)),f.x),f.y),mix(mix(h1(i+vec3(0,0,1)),h1(i+vec3(1,0,1)),f.x),mix(h1(i+vec3(0,1,1)),h1(i+vec3(1,1,1)),f.x),f.y),f.z);}
float fbm(vec3 p){float v=0.,a=.5;for(int i=0;i<5;i++){v+=a*noise(p);p=p*2.03+7.1;a*=.5;}return v;}
float crater(vec3 p,float sc){p*=sc;vec3 b=floor(p-.5);float h=0.;
for(int i=0;i<2;i++)for(int j=0;j<2;j++)for(int k=0;k<2;k++){
vec3 c=b+vec3(float(i),float(j),float(k));vec3 r=h3(c);vec3 ct=c+.25+.5*r;
float rad=.17+.2*h1(c+3.7);float d=length(p-ct)/rad;float pr=step(.4,h1(c+9.1));
float bowl=d<1.?-(1.-d*d)*.8:0.;float rim=exp(-pow((d-1.)*6.,2.))*.55;float ej=d>1.?.16*exp(-(d-1.)*3.5):0.;
h+=(bowl+rim+ej)*pr;}return h;}
float rd(float x){float B=smoothstep(.12,.2,x)*(1.-smoothstep(.52,.56,x));
float A=smoothstep(.6,.62,x)*(1.-smoothstep(.93,.96,x))*(1.-.9*exp(-pow((x-.88)*90.,2.)));
float C=.25*smoothstep(0.,.1,x)*(1.-smoothstep(.12,.2,x));
return clamp((B*.95+A*.72+C)*(.6+.4*noise(vec3(x*260.,2.,5.))),0.,1.);}
vec3 rotY(vec3 p,float a){float c=cos(a),s=sin(a);return vec3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);}`,
    vs:`varying vec3 vP,vN,vW;varying vec2 vL;
void main(){vP=normalize(position);vL=position.xy;vN=normalize(mat3(modelMatrix)*position);vW=(modelMatrix*vec4(position,1.)).xyz;gl_Position=projectionMatrix*viewMatrix*vec4(vW,1.);}`,
    fs:`varying vec3 vP,vN,vW;
uniform float uT,uRot,uAk,uR,uBk,uSoft;uniform vec3 uS,uSo,uAtm,uC,uRn;
float HT(vec3 q){
#if T==1||T==2
return crater(q,4.)*.9+crater(q,11.)*.5+crater(q,29.)*.22;
#elif T==4
return crater(q,5.)*.35+fbm(q*3.)*.4;
#else
return 0.;
#endif
}
void main(){
vec3 n=normalize(vN),V=normalize(cameraPosition-vW),p0=normalize(vP);vec3 q=rotY(p0,uRot);vec3 alb=vec3(.5);
float ndl=dot(n,uS);float lat=q.y;float ph=atan(q.z,q.x);
#if T==1||T==2||T==4
float h0=HT(q);vec3 Ls=uSo-p0*dot(uSo,p0);Ls=normalize(Ls+1e-5);float dh=HT(q+rotY(Ls,uRot)*.015)-h0;ndl-=dh*uBk;
#endif
#if T==1
float m=smoothstep(.5,.58,fbm(q*1.6+3.));alb=mix(vec3(.66,.64,.61),vec3(.27,.28,.31),m*.9);alb*=.85+.3*fbm(q*14.);alb+=clamp(h0,0.,.6)*.12;alb*=1.-clamp(-h0,0.,1.)*.15;
#elif T==2
alb=vec3(.43,.40,.37)*(.8+.4*fbm(q*5.));alb+=clamp(h0,0.,.6)*.12;alb*=1.-clamp(-h0,0.,1.)*.2;
#elif T==3
vec3 s=rotY(q,uT*.03);float f1=fbm(s*vec3(2.,5.,2.)+vec3(0.,uT*.01,0.));float f2=fbm(s*vec3(4.,9.,4.)+f1*2.5);
alb=mix(vec3(.93,.80,.52),vec3(.98,.93,.76),f2);alb*=.86+.25*smoothstep(.4,.7,fbm(s*vec3(3.,12.,3.)+f1*3.));
#elif T==4
alb=mix(vec3(.55,.26,.13),vec3(.78,.46,.26),fbm(q*3.+1.));alb=mix(alb,vec3(.2,.12,.09),smoothstep(.55,.62,fbm(q*1.5+9.))*.8);
alb*=.8+.4*fbm(q*18.);alb*=1.+clamp(h0,0.,.5)*.15;
float v=smoothstep(.025,0.,abs(lat+.07+.04*sin(ph*5.)))*smoothstep(1.,.2,abs(ph-.8));alb=mix(alb,vec3(.28,.14,.09),v*.7);
alb=mix(alb,vec3(.95,.95,.97),smoothstep(.86+.04*fbm(q*6.),.93,abs(lat)));
#elif T==5
float flow=uT*.02*(1.+.5*sin(lat*13.));float p2=ph+flow;float cl=sqrt(max(1.-lat*lat,0.));vec3 s=vec3(cos(p2)*cl,lat,sin(p2)*cl);
float tb=fbm(s*vec3(4.,1.5,4.)+vec3(0.,0.,uT*.005));float band=.5+.5*sin(lat*15.+(tb-.5)*2.6);float b2=.5+.5*sin(lat*33.+tb*3.);
vec3 cr=vec3(.9,.82,.68);alb=mix(cr,vec3(.74,.55,.38),smoothstep(.25,.75,band));alb=mix(alb,vec3(.55,.34,.24),smoothstep(.65,.95,b2)*.5*(1.-band));
alb*=.9+.2*fbm(s*vec3(12.,40.,12.));
float dp=mod(ph-.9+3.14159,6.28318)-3.14159;vec2 e=vec2(dp*cl/.35,(lat+.3)/.13);float r=length(e);
float sw=fbm(vec3(atan(e.y,e.x)*1.2+r*3.-uT*.25,r*3.,1.));
alb=mix(alb,mix(vec3(.72,.28,.18),vec3(.88,.55,.4),sw),smoothstep(1.,.55,r)*.9);
alb=mix(alb,cr*1.05,smoothstep(1.35,1.05,r)*smoothstep(.95,1.15,r)*.5);
#else
float tb=fbm(q*vec3(3.,1.,3.));alb=mix(vec3(.88,.78,.58),vec3(.72,.6,.42),.5+.5*sin(lat*24.+(tb-.5)*1.5));
alb*=.95+.1*fbm(q*vec3(8.,30.,8.));alb=mix(alb,vec3(.55,.6,.62),smoothstep(.8,.95,abs(lat))*.45);
vec3 P=vW-uC;float dn=dot(uS,uRn);float tt=-dot(P,uRn)/(abs(dn)<1e-3?1e-3:dn);vec3 hit=P+uS*tt;float rr=length(hit)/uR;
if(tt>0.&&rr>1.24&&rr<2.28)alb*=1.-.85*rd((rr-1.24)/1.04);
#endif
float lit=smoothstep(-uSoft*.4,uSoft,ndl);
vec3 col=alb*lit*1.15+alb*.012;
float f=pow(1.-max(dot(n,V),0.),3.);col+=uAtm*f*uAk*smoothstep(-.3,.5,ndl)*.8;
gl_FragColor=vec4(col,1.);}`,
    ring:`varying vec3 vW;varying vec2 vL;uniform vec3 uS,uC;uniform float uR;
void main(){float rn=(length(vL)/uR-1.24)/1.04;if(rn<0.||rn>1.)discard;float d=rd(rn);
vec3 P=vW-uC;float t=dot(P,uS);float d2=dot(P,P)-t*t;float sh=t<0.?smoothstep(uR*.98,uR*1.02,sqrt(max(d2,0.))):1.;
vec3 col=mix(vec3(.55,.48,.38),vec3(.86,.78,.64),d)*(.06+.94*sh);gl_FragColor=vec4(col,d*.92);}`,
    atm:`varying vec3 vN,vW;uniform vec3 uS,uAtm;uniform float uAk;
void main(){vec3 n=normalize(vN),V=normalize(cameraPosition-vW);float d=dot(n,V);float i=pow(clamp(-d,0.,1.),3.);
gl_FragColor=vec4(uAtm*i*uAk*1.6*smoothstep(-.4,.5,dot(n,uS)),1.);}`
  };

PGL.tvs=`varying vec3 vWp,vNg;varying vec2 vXZ;uniform float uT;
float cr2(vec2 x,float sc){return crater(vec3(x,.5/sc),sc);}
float HG(vec2 x){float h;
#if S==1||S==2
h=cr2(x,.004)*35.+cr2(x,.012)*5.+cr2(x,.05)*1.2+fbm(vec3(x*.01,2.))*6.;
#elif S==3
h=fbm(vec3(x*.003,3.))*22.+fbm(vec3(x*.012,2.))*4.;
#elif S==4
h=fbm(vec3(x*.006,1.))*40.+fbm(vec3(x*.03,4.))*3.+cr2(x,.008)*6.+cr2(x,.04)*.8;
#else
h=(fbm(vec3(x*.008+vec2(uT*.3,0.),uT*.02))-.35)*18.;
#endif
return h*(.12+.88*smoothstep(4.,45.,length(x)));}
void main(){vec2 x=position.xz;float e=max(1.5,length(x)*.03),h0=HG(x),hx=HG(x+vec2(e,0.)),hz=HG(x+vec2(0.,e));
vNg=normalize(vec3(h0-hx,e,h0-hz));vXZ=x;vec4 w=modelMatrix*vec4(x.x,h0,x.y,1.);vWp=w.xyz;gl_Position=projectionMatrix*viewMatrix*w;}`;
PGL.tfs=`varying vec3 vWp,vNg;varying vec2 vXZ;uniform vec3 uSun,uSunC,uAmb,uHaze,uC1,uC2;uniform float uFog,uT,uFI;uniform vec3 uFD;
float dn(vec2 x){return noise(vec3(x*1.7,0.))*.6+noise(vec3(x*5.3,1.))*.3+noise(vec3(x*17.,2.))*.1;}
void main(){vec2 x=vXZ;vec3 n=normalize(vNg);float dist=length(cameraPosition-vWp);float k=1./(1.+dist*.08);
float d0=dn(x);vec2 g=vec2(dn(x+vec2(.15,0.))-d0,dn(x+vec2(0.,.15))-d0)*k*8.;n=normalize(n+vec3(-g.x,0.,-g.y));
float rk=smoothstep(.66,.72,noise(vec3(x*1.3,3.)));vec3 alb;
#if S==1
alb=vec3(.58,.57,.55)*(.75+.5*fbm(vec3(x*.4,1.)))*(.85+.3*d0);alb=mix(alb,vec3(.3)*(.8+d0*.4),rk*.7);
#elif S==2
alb=vec3(.4,.37,.34)*(.75+.5*fbm(vec3(x*.4,1.)))*(.85+.3*d0);alb=mix(alb,vec3(.22)*(.8+d0*.4),rk*.7);
#elif S==3
alb=mix(vec3(.28,.19,.13),vec3(.5,.34,.2),fbm(vec3(x*.03,2.)));
alb=mix(alb,vec3(.18,.12,.09),smoothstep(.14,0.,abs(noise(vec3(x*.02,4.))-.5))*.35);alb*=.85+.3*d0;
#elif S==4
alb=mix(vec3(.55,.27,.14),vec3(.74,.45,.27),fbm(vec3(x*.05,2.)));
alb*=.9+.15*(.5+.5*sin(x.x*1.3+x.y*.6+fbm(vec3(x*.08,1.))*9.));alb=mix(alb,vec3(.17,.11,.09)*(.8+d0*.4),rk*.75);alb*=.8+.4*d0;
#else
float c1=fbm(vec3(x*.012,uT*.03));float c2=fbm(vec3(x*.035+c1*2.,uT*.05));alb=mix(uC1,uC2,smoothstep(.25,.75,c2))*(.5+.75*smoothstep(.2,.8,c1))*(.85+.3*d0);
#endif
vec3 col=alb*(max(dot(n,uSun),0.)*uSunC+uAmb*(.5+.5*n.y));
col+=vec3(1.,.8,.5)*uFI*alb*.9*(.5+.5*clamp(dot(n,normalize(uFD+vec3(0.,.3,0.))),0.,1.));col=mix(col,uHaze,1.-exp(-dist*uFog));gl_FragColor=vec4(col,1.);}`;
PGL.skv=`varying vec3 vD;void main(){vD=position;gl_Position=projectionMatrix*viewMatrix*(modelMatrix*vec4(position,1.));}`;
PGL.skf=`varying vec3 vD;uniform vec3 uHor,uZen,uSun,uSunC,uFD;uniform float uSunK,uCos,uStar,uT,uFI,uFS;
void main(){vec3 d=normalize(vD);float e=d.y;vec3 c=mix(uHor,uZen,pow(clamp(e,0.,1.),.45));float s=dot(d,uSun),dens=0.;
#if G
vec2 p=d.xz/(max(e,0.)+.09);vec2 w=vec2(uT*.02,0.);
float a1=fbm(vec3(p*.55+w,1.)),b1=fbm(vec3(p*1.4+a1*2.+w*1.7,3.)),a2=fbm(vec3((p+uSun.xz*.6)*.55+w,1.));
dens=smoothstep(.22,.55,a1*.65+b1*.45);float lit=clamp(.65+(a1-a2)*3.,.25,1.3);
vec3 cc=mix(vec3(.88,.4,.12),vec3(1.,.82,.34),smoothstep(.3,.75,b1))*lit;cc=mix(vec3(.3,.14,.07),cc,clamp(lit,0.,1.));
c=mix(c,cc,dens*.97*smoothstep(-.02,.12,e));
if(uFI>0.){vec3 L=uFD;float g=pow(max(dot(d,L),0.),6.);c+=vec3(1.,.82,.5)*uFI*(g*1.6*(.4+dens)+.18*dens);
float da=atan(d.x,d.z)-atan(L.x,L.z);da=atan(sin(da),cos(da));
float bx=da+(noise(vec3(e*28.,uFS,3.))-.5)*.14+(noise(vec3(e*90.,uFS,7.))-.5)*.03;
float vis=smoothstep(-.02,.02,e)*step(e,L.y+.02);
c+=vec3(.85,.9,1.)*smoothstep(.007,0.,abs(bx))*vis*uFI*1.8+vec3(1.,.8,.45)*smoothstep(.035,0.,abs(bx))*vis*.3*uFI;}
#endif
c+=uSunC*(pow(max(s,0.),24.)*uSunK*.35+pow(max(s,0.),400.)*uSunK)*(1.-dens*.75);c+=uSunC*smoothstep(uCos,uCos+.00006,s)*3.;
c+=vec3(step(.9975,h1(floor(d*240.)))*uStar*step(0.,e));gl_FragColor=vec4(c,1.);}`;
const PS=[
 {sf:'Yüzey: gri regolit, kraterler ve kaya parçaları; gökyüzü simsiyah, Güneş sert, gölgeler keskin',el:14,hor:[0,0,0],zen:[0,0,0],sc:[1.8,1.75,1.65],amb:[.015,.015,.02],haze:[0,0,0],fog:0,sunK:0,cos:.9998,star:.95,c1:[0,0,0],c2:[0,0,0]},
 {sf:'Yüzey: koyu gri-kahve, yoğun kraterler; Güneş 2,5 kat büyük görünür, gökyüzü siyah',el:18,hor:[0,0,0],zen:[0,0,0],sc:[2.2,2.1,1.9],amb:[.02,.018,.016],haze:[0,0,0],fog:0,sunK:0,cos:.9996,star:.95,c1:[0,0,0],c2:[0,0,0]},
 {sf:'Yüzey: ~465 °C bazalt ovalar ve sırtlar; kalın bulut altında turuncu loş ışık, Güneş görünmez',el:42,hor:[.95,.58,.26],zen:[.62,.36,.17],sc:[.55,.34,.18],amb:[.5,.3,.14],haze:[.9,.54,.26],fog:.012,sunK:.12,cos:1.1,star:0,c1:[0,0,0],c2:[0,0,0]},
 {sf:'Yüzey: pas rengi toz, bazalt kayalar, kum dalgaları; gökyüzü tozdan şeker rengi, Güneş küçük ve soluk',el:30,hor:[.82,.58,.43],zen:[.46,.33,.3],sc:[1.15,.98,.8],amb:[.22,.14,.1],haze:[.78,.55,.42],fog:.0035,sunK:.5,cos:.99992,star:0,c1:[0,0,0],c2:[0,0,0]},
 {sf:'Bulut denizi: her yer sarı-turuncu kabaran bulut, rüzgârla akıyor; ara sıra dev şimşekler çakıyor',el:12,hor:[.92,.6,.26],zen:[.72,.4,.15],sc:[1,.78,.4],amb:[.42,.28,.12],haze:[.92,.6,.26],fog:.006,sunK:.3,cos:1.1,star:0,c1:[.98,.74,.25],c2:[.86,.36,.1]},
 {sf:'Bulut denizi: sarıdan turuncuya sonsuz bulut yığınları; yukarıda şimşekler çakıyor',el:10,hor:[.93,.7,.32],zen:[.74,.46,.18],sc:[1,.82,.46],amb:[.42,.3,.14],haze:[.93,.68,.3],fog:.006,sunK:.3,cos:1.1,star:0,c1:[.98,.84,.42],c2:[.86,.48,.16]}
];
  const PL=[
    {n:'Ay',T:1,R:.85,tilt:1.5,spin:.02,bk:5,soft:.22,atm:null,info:['Çap 3.474 km · Yerçekimi 1,62 m/s² · Dünya\'ya 384.400 km','Yüzey sıcaklığı −173…+127 °C · Atmosfer: yok (ihmal edilebilir)','Krater ve deniz denen karanlık bazalt ovalar; gün yaklaşık 29,5 Dünya günü']},
    {n:'Merkür',T:2,R:.8,tilt:0,spin:.025,bk:5,soft:.22,atm:null,info:['Çap 4.879 km · Yerçekimi 3,70 m/s² · Güneş\'e 57,9 milyon km','Sıcaklık −180…+430 °C · Atmosfer: yok','Yıl 88 gün sürer; yüzey yoğun kraterli ve Ay\'a çok benzer']},
    {n:'Venüs',T:3,R:1.25,tilt:3,spin:-.02,bk:0,soft:.7,atm:[.98,.84,.52,1.5],info:['Çap 12.104 km · Yerçekimi 8,87 m/s² · Güneş\'e 108 milyon km','Yüzey ~465 °C · Atmosfer %96,5 CO₂, basınç ~92 bar','Gün 243 Dünya günü ve ters yönde döner; yüzey kalın bulutla gizli']},
    {n:'Mars',T:4,R:1,tilt:25,spin:.12,bk:2.5,soft:.3,atm:[.9,.55,.35,.6],info:['Çap 6.779 km · Yerçekimi 3,71 m/s² · Güneş\'e 228 milyon km','Sıcaklık −125…+20 °C · Çok ince CO₂ atmosfer (~0,6 kPa)','Gün 24 sa 37 dk; Valles Marineris kanyonu ve buz kutup başlıkları']},
    {n:'Jüpiter',T:5,R:2.4,tilt:3,spin:.3,bk:0,soft:.55,atm:[.65,.58,.5,.5],info:['Çap 139.820 km · Yerçekimi 24,79 m/s² · Güneş\'e 778 milyon km','Bulut üstü ~−110 °C · Atmosfer %90 H₂, %10 He','Gün 9 sa 56 dk; Büyük Kırmızı Leke ve 4 büyük uydu (Io, Europa, Ganymede, Callisto)']},
    {n:'Satürn',T:6,R:2,tilt:27,spin:.26,bk:0,soft:.55,atm:[.85,.75,.52,.4],info:['Çap 116.460 km · Yerçekimi 10,44 m/s² · Güneş\'e 1,43 milyar km','Bulut üstü ~−140 °C · Atmosfer H₂ ve He','Buzdan halkalar (Cassini Aralığı görünür); Titan uydusu']}
  ];
  const Planets={
    on:false,built:false,mode:'orbit',lp:null,fm:{},sk:{},g:null,cur:-1,grp:null,t:0,dist:70,tgt:6,mats:{},moons:[],st:'idle',last:0,prev:null,menu:null,
    S:null,
    toggle(){this.on?this.exit():this.enter()},
    pick(i){const t=performance.now(),l=this.lp;this.lp=[i,t];if(l&&l[0]===i&&t-l[1]<550){this.lp=null;this.land(i);return}this.select(i)},
    land(i){if(this.cur!==i||this.mode==='surf')this.select(i,true);else if(this.st==='fly')this.dist=this.tgt;
      this.mode='orbit';this.st='land';this.t=0;this.d0=this.dist;Diag.say(PL[i].n+' yüzeyine iniliyor')},
    sun3(S){const e=S.el*Math.PI/180;return new THREE.Vector3(-Math.cos(e)*.6,Math.sin(e),-Math.cos(e)*.8).normalize()},
    surfMat(i){if(this.fm[i])return this.fm[i];const S=PS[i],c=a=>new THREE.Vector3(a[0],a[1],a[2]);
      return this.fm[i]=new THREE.ShaderMaterial({defines:{S:PL[i].T},uniforms:{uT:{value:0},uFI:{value:0},uFD:{value:new THREE.Vector3(0,.3,-1)},uSun:{value:this.sun3(S)},uSunC:{value:c(S.sc)},uAmb:{value:c(S.amb)},uHaze:{value:c(S.haze)},uFog:{value:S.fog},uC1:{value:c(S.c1)},uC2:{value:c(S.c2)}},vertexShader:PGL.com+PGL.tvs,fragmentShader:PGL.com+PGL.tfs})},
    skyMat(i){if(this.sk[i])return this.sk[i];const S=PS[i],c=a=>new THREE.Vector3(a[0],a[1],a[2]);
      return this.sk[i]=new THREE.ShaderMaterial({defines:{G:PL[i].T>=5?1:0},uniforms:{uT:{value:0},uFI:{value:0},uFD:{value:new THREE.Vector3(0,.3,-1)},uFS:{value:1},uHor:{value:c(S.hor)},uZen:{value:c(S.zen)},uSun:{value:this.sun3(S)},uSunC:{value:c(S.sc).multiplyScalar(.6)},uSunK:{value:S.sunK},uCos:{value:S.cos},uStar:{value:S.star}},vertexShader:PGL.skv,fragmentShader:PGL.com+PGL.skf,side:THREE.BackSide,depthWrite:false})},
    enterSurf(){const i=this.cur,cp=Cam.cam.position;this.mode='surf';this.lt=-9;this.lw=2;this.grp.visible=false;this.stars.visible=this.lines.visible=false;
      this.terr.material=this.surfMat(i);this.sky.material=this.skyMat(i);this.terr.position.set(cp.x,cp.y-1.7,cp.z);this.sky.position.copy(cp);
      this.sg.visible=true;if(this.menu)WM.paint(this.menu)},
    build(){
      if(this.built)return;this.built=true;
      this.S=new THREE.Vector3(-.8,.25,.45).normalize();
      const g=this.g=new THREE.Group(),N=1800,pa=new Float32Array(N*3);
      for(let i=0;i<N;i++){const u=Math.random()*2-1,a=Math.random()*6.283,r=Math.sqrt(1-u*u);pa[i*3]=r*Math.cos(a)*120;pa[i*3+1]=u*120;pa[i*3+2]=r*Math.sin(a)*120}
      const sg=new THREE.BufferGeometry();sg.setAttribute('position',new THREE.BufferAttribute(pa,3));
      const st=this.stars=new THREE.Points(sg,new THREE.PointsMaterial({size:.45,color:0xdfe8ff,fog:false,sizeAttenuation:false}));st.frustumCulled=false;g.add(st);
      const M=240,la=new Float32Array(M*6);this.sx=[];
      for(let i=0;i<M;i++){const a=Math.random()*6.283,r=1.5+Math.random()*9;this.sx.push([Math.cos(a)*r,Math.sin(a)*r+1.8,-Math.random()*130])}
      const lg=new THREE.BufferGeometry();lg.setAttribute('position',new THREE.BufferAttribute(la,3));
      this.lines=new THREE.LineSegments(lg,new THREE.LineBasicMaterial({color:0xbfd4ff,transparent:true,opacity:0,fog:false}));this.lines.frustumCulled=false;g.add(this.lines);
      g.add(this.sun=new THREE.DirectionalLight(0xffffff,1.6));this.sun.position.copy(this.S).multiplyScalar(10);g.add(new THREE.AmbientLight(0xffffff,.05));
      g.visible=false;Scene.scene.add(g);
      const tg=new THREE.PlaneGeometry(2,2,170,170);tg.rotateX(-Math.PI/2);const tp=tg.attributes.position;
      for(let i=0;i<tp.count;i++){const a=tp.getX(i),b=tp.getZ(i);tp.setX(i,Math.sign(a)*a*a*380);tp.setZ(i,Math.sign(b)*b*b*380)}
      const SG=this.sg=new THREE.Group();this.terr=new THREE.Mesh(tg,new THREE.MeshBasicMaterial());this.terr.frustumCulled=false;
      this.sky=new THREE.Mesh(new THREE.SphereGeometry(330,32,16),new THREE.MeshBasicMaterial());this.sky.frustumCulled=false;this.sky.renderOrder=-1;
      SG.add(this.sky,this.terr);SG.visible=false;Scene.scene.add(SG);
      this.ov=document.createElement('div');this.ov.style.cssText='position:fixed;inset:0;background:#000;opacity:0;pointer-events:none;z-index:5';document.body.appendChild(this.ov)
    },
    mat(i){
      if(this.mats[i])return this.mats[i];const P=PL[i],a=P.atm||[0,0,0,0];
      const m=new THREE.ShaderMaterial({defines:{T:P.T},uniforms:{uT:{value:0},uRot:{value:0},uAk:{value:a[3]},uR:{value:P.R},uBk:{value:P.bk},uSoft:{value:P.soft},uS:{value:this.S},uSo:{value:this.S.clone()},uAtm:{value:new THREE.Vector3(a[0],a[1],a[2])},uC:{value:new THREE.Vector3()},uRn:{value:new THREE.Vector3(0,1,0)}},vertexShader:PGL.vs,fragmentShader:PGL.com+PGL.fs});
      return this.mats[i]=m
    },
    select(i,q){
      if(i===this.cur&&this.st!=='idle'&&this.mode!=='surf'&&!q)return;
      this.mode='orbit';this.sg.visible=false;this.ov.style.opacity=0;this.stars.visible=this.lines.visible=true;
      if(this.grp){this.g.remove(this.grp);this.grp.traverse(o=>{o.geometry&&o.geometry.dispose()})}
      const P=PL[i],G=new THREE.Group(),pm=this.mat(i);this.cur=i;this.moons=[];
      const pl=this.pl=new THREE.Mesh(new THREE.SphereGeometry(P.R,128,64),pm);G.add(pl);
      if(P.atm){const am=new THREE.ShaderMaterial({uniforms:{uS:{value:this.S},uAtm:{value:new THREE.Vector3(P.atm[0],P.atm[1],P.atm[2])},uAk:{value:P.atm[3]}},vertexShader:PGL.vs,fragmentShader:PGL.atm,side:THREE.BackSide,transparent:true,blending:THREE.AdditiveBlending,depthWrite:false});
        G.add(new THREE.Mesh(new THREE.SphereGeometry(P.R*1.11,64,32),am))}
      this.ring=null;
      if(P.T===6){
        const rm=new THREE.ShaderMaterial({uniforms:{uS:{value:this.S},uC:pm.uniforms.uC,uR:{value:P.R}},vertexShader:PGL.vs,fragmentShader:PGL.com+PGL.ring,side:THREE.DoubleSide,transparent:true,depthWrite:false});
        const rg=new THREE.Mesh(new THREE.RingGeometry(P.R*1.24,P.R*2.28,180,1),rm);rg.rotation.x=-Math.PI/2;G.add(rg)}
      const mk=(c,s,a,w,ph,inc)=>{const m=new THREE.Mesh(new THREE.SphereGeometry(s,24,16),new THREE.MeshLambertMaterial({color:c}));G.add(m);this.moons.push({m,a:a*P.R,w,ph,inc})};
      if(P.T===5){mk(0xe8d27a,.12,1.9,.9,0,.02);mk(0xe9e2d0,.1,2.4,.45,2,.03);mk(0x8e8272,.18,3,.22,4,.02);mk(0x4d453d,.16,3.8,.1,1,.04)}
      if(P.T===6)mk(0xd9a24a,.2,3.6,.12,1,.05);
      if(P.T===4){mk(0x6b625a,.05,1.5,.9,0,.02);mk(0x8a8078,.035,2,.4,3,.03)}
      G.rotation.z=P.tilt*Math.PI/180;this.g.add(G);this.grp=G;
      this.t=0;this.st='fly';this.zPrev=-this.dist;
      const k=clamp(1.6/((Cam.cam.aspect)||1.6),1,2.2);this.tgt=P.R*(P.T===6?5.2:3.7)*k;this.dist=q?this.tgt:75;if(q)this.st='idle';
      if(this.menu)WM.paint(this.menu);Diag.say(P.n+' yönüne gidiliyor')
    },
    enter(){
      if(this.on)return;
      if(Cinema.on)Cinema.exit();if(Places.on)Places.exit();if(Game.on)Game.exit();if(window.Gorilla&&Gorilla.on)Gorilla.exit();if(Launcher.open)Launcher.close();if(QS.open)QS.close();
      this.build();Cam.reset();
      this.prev={vis:WM.panels.map(m=>[m,m.visible]),sky:Scene.sky.visible,fl:Scene.floor.visible,rg:Scene.ring.visible,fog:[Scene.scene.fog.near,Scene.scene.fog.far],far:Cam.cam.far};
      Scene.sky.visible=Scene.floor.visible=Scene.ring.visible=false;Scene.scene.fog.near=1e4;Scene.scene.fog.far=2e4;
      Cam.cam.far=Math.max(Cam.cam.far,400);Cam.cam.updateProjectionMatrix();
      if(!this.menu)this.menu=WM.create({id:'pmenu',title:'Gezegenler',chrome:false,span:.68,h:.98,R:2.4,y:1.2,ang:-.22,live:false,render:(c,W,H,B)=>this.rMenu(c,W,H,B)});
      this.g.visible=true;this.on=true;this.last=performance.now();
      this.select(this.cur<0?3:this.cur);this.tick();Scene.dirty=true;WM.repaintAll()
    },
    exit(){
      if(!this.on)return;
      this.on=false;this.g.visible=false;this.sg.visible=false;this.ov.style.opacity=0;this.mode='orbit';const p=this.prev;
      if(p){p.vis.forEach(a=>a[0].visible=a[1]);Scene.sky.visible=p.sky;Scene.floor.visible=p.fl;Scene.ring.visible=p.rg;Scene.scene.fog.near=p.fog[0];Scene.scene.fog.far=p.fog[1];Cam.cam.far=p.far;Cam.cam.updateProjectionMatrix()}
      if(this.menu)this.menu.visible=false;Scene.dirty=true;WM.repaintAll()
    },
    tick(){
      if(!this.on)return;
      const now=performance.now(),dt=Math.min(.05,Math.max(.001,(now-this.last)/1000));this.last=now;this.t+=dt;
      WM.panels.forEach(m=>{const id=m.userData.id;m.visible=id==='pmenu'||id==='dock'});
      const P=PL[this.cur];let sp=0;
      if(this.st==='fly'){
        const k=Math.min(1,this.t/6),e=1-Math.pow(1-k,3),d=75*(1-e)+this.tgt*e;sp=Math.abs(this.dist-d)/dt;this.dist=d;
        if(k>=1)this.st='idle'
      }
      if(this.st==='land'){const k=Math.min(1,this.t/3),e=k*k*k;this.dist=this.d0*(1-e)+P.R*1.25*e;this.ov.style.opacity=clamp((this.t-2.2)/.8,0,1);if(k>=1){this.enterSurf();this.st='surf';this.t=0}}
      if(this.st==='surf'){this.ov.style.opacity=clamp(1-this.t/1.5,0,1);const tu=this.terr.material.uniforms,su=this.sky.material.uniforms;tu.uT.value=su.uT.value=this.t;this.sky.position.copy(Cam.cam.position);
        if(PL[this.cur].T>=5){
          if(this.t-this.lt>this.lw){this.lt=this.t;this.lw=1.5+Math.random()*4;const a=Math.random()*6.283,r=.15+Math.random()*.5;this.lv=new THREE.Vector3(Math.cos(a)*.94,r,Math.sin(a)*.94).normalize();this.ls=Math.random()*50}
          const g=this.t-this.lt,I=g<.6?Math.max(0,Math.exp(-g*6)*(.55+.45*Math.cos(g*55))):0;
          tu.uFI.value=su.uFI.value=I;if(this.lv){tu.uFD.value.copy(this.lv);su.uFD.value.copy(this.lv)}su.uFS.value=this.ls||1}Scene.dirty=true;return}
      const G=this.grp;G.position.set(0,2,-this.dist);
      const u=this.pl.material.uniforms;u.uT.value=this.t;u.uRot.value+=dt*P.spin;
      u.uC.value.copy(G.position);u.uRn.value.set(0,1,0).applyQuaternion(G.quaternion);
      u.uSo.value.copy(this.S).applyQuaternion(G.quaternion.clone().invert());
      this.moons.forEach(o=>{const a=o.ph+this.t*o.w;o.m.position.set(Math.cos(a)*o.a,Math.sin(a)*o.a*o.inc*3,Math.sin(a)*o.a)});
      const pa=this.lines.geometry.attributes.position,L=.4+sp*.06;
      this.sx.forEach((s,i)=>{s[2]+=sp*dt*1.4;if(s[2]>5)s[2]-=130;pa.setXYZ(i*2,s[0],s[1],s[2]);pa.setXYZ(i*2+1,s[0],s[1],s[2]-L)});
      pa.needsUpdate=true;this.lines.material.opacity=clamp(sp/30,0,.8);
      Scene.dirty=true
    },
    rMenu(c,W,H,B){
      const P=PL[Math.max(0,this.cur)];c.clearRect(0,0,W,H);
      c.fillStyle='rgba(8,14,30,.82)';c.fillRect(0,0,W,H);c.strokeStyle='rgba(120,170,255,.35)';c.lineWidth=2;c.strokeRect(1,1,W-2,H-2);
      c.textAlign='left';c.fillStyle='#fff';c.font='800 '+Math.round(H*.13)+'px system-ui';c.fillText(P.n.toUpperCase(),W*.03,H*.17);
      c.fillStyle='#b9c6e6';c.font=Math.round(H*.068)+'px system-ui';
      const L=P.info.slice();if(this.mode==='surf')L[2]=PS[this.cur].sf;
      L.forEach((s,i)=>c.fillText(s,W*.03,H*.3+i*H*.09));
      c.fillStyle='#19d3c5';c.fillText(this.mode==='surf'?'Yörünge düğmesiyle uzaya dön; başka gezegene iki kez tıklayıp oraya in':'İpucu: bir gezegene iki kez tıkla, yüzeyine ineyim',W*.03,H*.3+3*H*.09);
      const n=PL.length+2,g=W*.012,bw=(W-W*.06-g*(n-1))/n,bh=H*.2,y=H*.7;
      PL.forEach((p,i)=>B(W*.03+i*(bw+g),y,bw,bh,p.n,()=>this.pick(i),i===this.cur,null,'pill','Git: '+p.n+' (çift tık: yüzey)'));
      B(W*.03+(n-2)*(bw+g),y,bw,bh,'Yörünge',()=>this.select(this.cur),this.mode!=='surf',null,'pill','Yörüngeye dön');
      B(W*.03+(n-1)*(bw+g),y,bw,bh,'Çıkış',()=>this.exit(),false,null,'pill','Gezegen şovundan çık')
    }
  };
