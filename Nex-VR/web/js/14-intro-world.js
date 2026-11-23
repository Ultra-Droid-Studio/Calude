'use strict';
  /* ---------- Uygulama ---------- */
  const Sys={
    wl:null,
    async awake(on){
      try{
        if(on){
          if(!navigator.wakeLock){
            Diag.toast('Bu tarayıcı ekranı açık tutmayı desteklemiyor','var(--warn)');
            Settings.v.awake=false;
            Settings.save();
            WM.repaintAll();
            return
          }
          this.wl=await navigator.wakeLock.request('screen');
          this.wl.addEventListener('release',()=>{
            this.wl=null
            })
        }else if(this.wl){
          await this.wl.release();
          this.wl=null
        }
      }catch(e){
        Diag.toast('Ekran kilidi ayarlanamadı','var(--warn)')
      }
    },
    fs(){
      try{
        if(document.fullscreenElement)document.exitFullscreen();
        else document.documentElement.requestFullscreen().catch(()=>Diag.toast('Tam ekran açılamadı','var(--warn)'))
      }catch(e){
        Diag.toast('Tam ekran desteklenmiyor','var(--warn)')
      }
    }
  };
  let inVf=null;
  const inV=m=>{
    if(!inVf)inVf=(()=>{
      const fr=new THREE.Frustum(),pm=new THREE.Matrix4();
      return m=>{
        Cam.cam.updateMatrixWorld(true);
        Cam.cam.matrixWorldInverse.copy(Cam.cam.matrixWorld).invert();
        pm.multiplyMatrices(Cam.cam.projectionMatrix,Cam.cam.matrixWorldInverse);
        fr.setFromProjectionMatrix(pm);
        return fr.intersectsObject(m)
      }
      })();
    return inVf(m)
  };
  const Intro={
    TXT:'Nex VR’a hoş geldiniz',
    L:[],timers:[],parts:[],shake:0,raf:0,last:0,cb:null,fin:false,
    build(){
      const h=$('#ititle');
      h.textContent='';
      h.setAttribute('aria-label',this.TXT);
      this.L=[];
      const words=this.TXT.split(' ');
      words.forEach((w,wi)=>{
        const ws=document.createElement('span');
        ws.className='iw'+(wi===1?' ia':'');
        ws.setAttribute('aria-hidden','true');
        [...w].forEach(ch=>{
          const s=document.createElement('span');
          s.className='il';
          s.textContent=ch;
          ws.appendChild(s);
          this.L.push(s)
        });
        h.appendChild(ws);
        if(wi<words.length-1)h.appendChild(document.createTextNode(' '))
      })
    },
    size(){
      const c=$('#idust'),d=Math.min(2,devicePixelRatio||1);
      c.width=Math.round(innerWidth*d);
      c.height=Math.round(innerHeight*d);
      this.d=d
    },
    puff(el){
      const r=el.getBoundingClientRect(),n=12;
      for(let i=0;i<n;i++)this.parts.push({x:r.left+Math.random()*r.width,y:r.bottom-r.height*.15,vx:(Math.random()-.5)*120,vy:-10-Math.random()*80,r:1.5+Math.random()*3.5,t:0,m:.7+Math.random()*.8})
    },
    kick(){
      if(this.raf)return;
      this.last=performance.now();
      this.raf=requestAnimationFrame(t=>this.loop(t))
    },
    loop(t){
      const dt=Math.min(.05,(t-this.last)/1000||.016);
      this.last=t;
      const c=$('#idust'),g=c.getContext('2d'),sh=$('#ishake');
      g.setTransform(this.d,0,0,this.d,0,0);
      g.clearRect(0,0,innerWidth,innerHeight);
      if(this.shake>.3){
        sh.style.transform='translate('+((Math.random()-.5)*2*this.shake).toFixed(1)+'px,'+((Math.random()-.5)*2*this.shake).toFixed(1)+'px)';
        this.shake*=Math.pow(.0005,dt)
      }else{
        this.shake=0;
        sh.style.transform=''
      }
      const k=Math.pow(.25,dt);
      this.parts=this.parts.filter(p=>(p.t+=dt)<p.m);
      this.parts.forEach(p=>{
        p.vx*=k;
        p.vy=p.vy*k+14*dt;
        p.x+=p.vx*dt;
        p.y+=p.vy*dt;
        const a=(1-p.t/p.m);
        g.globalAlpha=a*.55;
        g.fillStyle='#cfdcff';
        g.beginPath();
        g.arc(p.x,p.y,p.r*(1+p.t/p.m),0,6.283);
        g.fill()
      });
      g.globalAlpha=1;
      if(this.parts.length||this.shake)this.raf=requestAnimationFrame(t2=>this.loop(t2));
      else this.raf=0
    },
    finish(){
      if(this.fin)return;
      this.fin=true;
      this.timers.forEach(clearTimeout);
      this.timers=[];
      this.L.forEach(l=>l.classList.add('on'));
      $('#isub').classList.add('on');
      Diag.say(this.TXT+' En iyi VR platformu');
      const b=$('#istart');
      this.timers.push(setTimeout(()=>{
        b.disabled=false;
        b.classList.add('on');
        b.focus()
      },Settings.v.reduce?0:700))
    },
    run(cb){
      this.cb=cb;
      this.fin=false;
      $('#load').style.display='none';
      const el=$('#intro'),b=$('#istart');
      el.style.display='block';
      b.disabled=true;
      b.classList.remove('on');
      $('#isub').classList.remove('on');
      this.build();
      this.size();
      this._rs=this._rs||(()=>this.size());
      addEventListener('resize',this._rs);
      el.onclick=e=>{
        if(e.target!==b)this.finish()
      };
      b.onclick=()=>{
        removeEventListener('resize',this._rs);
        this.timers.forEach(clearTimeout);
        cancelAnimationFrame(this.raf);
        this.raf=0;
        el.style.display='none';
        const f=this.cb;
        this.cb=null;
        f&&f()
      };
      if(Settings.v.reduce){
        this.finish();
        return
      }
      let i=0;
      const step=()=>{
        if(this.fin)return;
        const l=this.L[i++];
        l.classList.add('on');
        this.puff(l);
        this.shake=7;
        this.kick();
        if(i>=this.L.length){
          this.timers.push(setTimeout(()=>this.finish(),350));
          return
        }
        const gap=this.L[i].parentNode!==l.parentNode?220:90;
        this.timers.push(setTimeout(step,gap))
      };
      this.timers.push(setTimeout(step,350))
    }
  };
  /* ---------- Dock: sabitlenen uygulamalar ve tüm uygulamalar menüsü ---------- */
  /* ---------- GLB oda yükleyici (Roblox evi): küçük, bağımsız glTF 2.0 ikili (.glb) okuyucu ---------- */
  const GLBRoom={
    cache:null,busy:null,
    load(url){
      if(this.cache)return Promise.resolve(this.cache);
      if(this.busy)return this.busy;
      return this.busy=fetch(url).then(r=>{if(!r.ok)throw new Error('HTTP '+r.status);return r.arrayBuffer()})
        .then(b=>this.parse(b)).then(g=>{this.cache=g;this.busy=null;return g},e=>{this.busy=null;throw e})
    },
    parse(buf){
      const dv=new DataView(buf);
      if(dv.getUint32(0,true)!==0x46546C67)throw new Error('GLB değil');
      const jl=dv.getUint32(12,true),j=JSON.parse(new TextDecoder().decode(new Uint8Array(buf,20,jl))),bs=20+jl+8;
      const CT={5126:Float32Array,5125:Uint32Array,5123:Uint16Array,5121:Uint8Array},NC={SCALAR:1,VEC2:2,VEC3:3,VEC4:4};
      const rd={5126:'getFloat32',5125:'getUint32',5123:'getUint16',5121:'getUint8'};
      const acc=i=>{
        const a=j.accessors[i],bv=j.bufferViews[a.bufferView],n=NC[a.type],C=CT[a.componentType],es=C.BYTES_PER_ELEMENT,off=bs+(bv.byteOffset||0)+(a.byteOffset||0),st=bv.byteStride;
        if(!st||st===n*es)return new C(buf.slice(off,off+a.count*n*es));
        const o=new C(a.count*n),f=rd[a.componentType];
        for(let k=0;k<a.count;k++)for(let c=0;c<n;c++)o[k*n+c]=dv[f](off+k*st+c*es,true);
        return o
      };
      const imgs=(j.images||[]).map(im=>{
        const bv=j.bufferViews[im.bufferView],o=bs+(bv.byteOffset||0),u=URL.createObjectURL(new Blob([buf.slice(o,o+bv.byteLength)],{type:im.mimeType||'image/png'}));
        return new Promise(res=>{const i=new Image();i.onload=()=>{URL.revokeObjectURL(u);res(i)};i.onerror=()=>{URL.revokeObjectURL(u);res(null)};i.src=u})
      });
      return Promise.all(imgs).then(im=>{
        const tc={},tex=ti=>{
          if(tc[ti]!==undefined)return tc[ti];
          const src=j.textures[ti].source,img=im[src];
          if(!img)return tc[ti]=null;
          const t=new THREE.Texture(img),sm=(j.samplers||[])[j.textures[ti].sampler||0]||{};
          t.flipY=false;t.wrapS=sm.wrapS===33071?THREE.ClampToEdgeWrapping:THREE.RepeatWrapping;t.wrapT=sm.wrapT===33071?THREE.ClampToEdgeWrapping:THREE.RepeatWrapping;
          t.anisotropy=2;t.needsUpdate=true;return tc[ti]=t
        };
        const mats=(j.materials||[]).map(m=>{
          const p=m.pbrMetallicRoughness||{},f=p.baseColorFactor||[1,1,1,1],c=new THREE.Color(f[0],f[1],f[2]);
          if(c.convertLinearToSRGB)c.convertLinearToSRGB(); /* glTF renk çarpanları doğrusal, çıkış doğrudan sRGB */
          const o={color:c,side:m.doubleSided?THREE.DoubleSide:THREE.FrontSide};
          if(p.baseColorTexture){const t=tex(p.baseColorTexture.index);if(t)o.map=t}
          if(m.alphaMode==='BLEND'){o.transparent=true;o.opacity=f[3];o.depthWrite=false}
          else if(m.alphaMode==='MASK')o.alphaTest=m.alphaCutoff==null?.5:m.alphaCutoff;
          return new THREE.MeshLambertMaterial(o)
        });
        const prim=p=>{
          const g=new THREE.BufferGeometry(),A=p.attributes;
          g.setAttribute('position',new THREE.BufferAttribute(acc(A.POSITION),3));
          if(A.NORMAL!=null)g.setAttribute('normal',new THREE.BufferAttribute(acc(A.NORMAL),3));
          if(A.TEXCOORD_0!=null)g.setAttribute('uv',new THREE.BufferAttribute(acc(A.TEXCOORD_0),2));
          if(p.indices!=null){let ix=acc(p.indices);if(ix instanceof Uint32Array&&g.attributes.position.count<65536)ix=new Uint16Array(ix);g.setIndex(new THREE.BufferAttribute(ix,1))}
          if(A.NORMAL==null)g.computeVertexNormals();
          const m=mats[p.material==null?0:p.material]||new THREE.MeshLambertMaterial(),me=new THREE.Mesh(g,m);
          me.frustumCulled=false;if(m.transparent)me.renderOrder=1;return me
        };
        const mk=ni=>{
          const n=j.nodes[ni],o=new THREE.Group();
          if(n.matrix){o.matrix.fromArray(n.matrix);o.matrix.decompose(o.position,o.quaternion,o.scale)}
          else{if(n.translation)o.position.fromArray(n.translation);if(n.rotation)o.quaternion.fromArray(n.rotation);if(n.scale)o.scale.fromArray(n.scale)}
          if(n.mesh!=null)j.meshes[n.mesh].primitives.forEach(p=>o.add(prim(p)));
          (n.children||[]).forEach(c=>o.add(mk(c)));return o
        };
        const root=new THREE.Group();
        j.scenes[j.scene||0].nodes.forEach(n=>root.add(mk(n)));
        return root
      })
    }
  };
  /* ---------- Gökyüzü ortamları (PhoneXR'daki Environments.kt'den): dosya yok, canvas ile çizilir ---------- */
  const EnvSky={
    IDS:['sunset','night','space','studio'],
    draw(id,x,W,H){
      const rg=(c,a)=>'rgba('+c[0]+','+c[1]+','+c[2]+','+(a==null?1:a)+')';
      const sky=(lo,hi)=>{const q=x.createLinearGradient(0,0,0,H);q.addColorStop(0,rg(hi));q.addColorStop(1,rg(lo));x.fillStyle=q;x.fillRect(0,0,W,H)};
      const ground=c=>{const q=x.createLinearGradient(0,H*.55,0,H);q.addColorStop(0,rg(c));q.addColorStop(1,rg([c[0]>>1,c[1]>>1,c[2]>>1]));x.fillStyle=q;x.fillRect(0,H*.55,W,H-H*.55)};
      const sun=(px,py,r,c)=>{const q=x.createRadialGradient(px,py,0,px,py,r*4);q.addColorStop(0,rg(c));q.addColorStop(.25,rg(c));q.addColorStop(1,rg(c,0));x.fillStyle=q;x.beginPath();x.arc(px,py,r*4,0,6.2832);x.fill();x.fillStyle=rg(c);x.beginPath();x.arc(px,py,r,0,6.2832);x.fill()};
      const stars=(n,seed)=>{
        const rnd=(a=>()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296})(seed);
        for(let i=0;i<n;i++){ /* kutuplarda yığılmasın diye enlem küresel dağıtılır */
          const px=rnd()*W,py=Math.acos(1-2*rnd())/Math.PI*H,sz=.8+rnd()*1.8,al=(120+Math.floor(rnd()*135))/255;
          x.fillStyle='rgba(255,255,255,'+al.toFixed(3)+')';x.beginPath();x.arc(px,py,sz,0,6.2832);x.fill()
        }
      };
      if(id==='sunset'){sky([250,170,90],[68,40,92]);sun(W*.5,H*.52,H*.09,[255,226,170]);ground([38,26,44])}
      else if(id==='night'){sky([24,34,70],[6,8,20]);stars(900,7);sun(W*.32,H*.3,H*.045,[236,240,255]);ground([10,12,24])}
      else if(id==='space'){
        x.fillStyle=rg([3,3,8]);x.fillRect(0,0,W,H);
        const q=x.createRadialGradient(W*.62,H*.42,0,W*.62,H*.42,H*.5);
        q.addColorStop(0,rg([90,60,160],120/255));q.addColorStop(.5,rg([40,60,140],40/255));q.addColorStop(1,rg([40,60,140],0));
        x.fillStyle=q;x.fillRect(0,0,W,H);stars(1600,21)
      }else{sky([238,238,242],[176,178,186]);ground([150,152,160])}
    }
  };
  /* ---------- Sinema modu: yerel video + detaylı sinema salonu ---------- */
  /* ---------- Minecraft dünyası: tamamen koddan üretilen, dosyasız blok-dünya (piksel dokular, çimen, ağaçlar, köylü/domuz/zombi) ---------- */
  const MCTex={
    rnd(seed){let a=seed|0;return()=>{a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}},
    fill(x,ox,oy,w,h,cols,seed){const r=this.rnd(seed);for(let i=0;i<w;i++)for(let j=0;j<h;j++){x.fillStyle=cols[(r()*cols.length)|0];x.fillRect(ox+i,oy+j,1,1)}},
    tex(cv){const t=new THREE.CanvasTexture(cv);t.magFilter=t.minFilter=THREE.NearestFilter;t.generateMipmaps=false;t.needsUpdate=true;return t},
    atlasFace(geo,cols,map){
      const uv=geo.attributes.uv;
      for(let f=0;f<6;f++){
        const col=map[f],u0=col/cols,u1=(col+1)/cols;
        for(let i=0;i<4;i++){const idx=f*4+i,u=uv.getX(idx);uv.setX(idx,u0+u*(u1-u0))}
      }
      uv.needsUpdate=true
    },
    /* Gerçek Minecraft doku atlası (terrain.png, 16x16 kare ızgara). Yüklenene kadar prosedürel renkler görünür, yüklenince kareler atlastan çizilir. */
    AT:'minecraft/terrain.png',
    atlas:null,ready:false,subs:[],
    initAtlas(){
      if(this.atlas||typeof Image==='undefined')return;
      const im=this.atlas=new Image();
      im.onload=()=>{this.ready=true;this.subs.forEach(f=>f());this.subs.length=0;if(typeof Scene!=='undefined')Scene.dirty=true};
      im.src=this.AT
    },
    paintTile(x,c,r,dx,dy,tint){
      x.imageSmoothingEnabled=false;x.globalCompositeOperation='source-over';
      const tileW=this.atlas.width/16,tileH=this.atlas.height/16;
      x.drawImage(this.atlas,c*tileW,r*tileH,tileW,tileH,dx,dy,16,16);
      if(tint){x.globalCompositeOperation='multiply';x.fillStyle=tint;x.fillRect(dx,dy,16,16);x.globalCompositeOperation='source-over'}
    },
    withAtlas(t,paint){
      this.initAtlas();
      const run=()=>{paint();t.needsUpdate=true};
      if(this.ready)run();else if(this.atlas)this.subs.push(run)
    },
    grassAtlas(){
      /* 3 kare yan yana: 0 toprak (2,0), 1 çim yanı (3,0), 2 çim üstü (0,0, yeşil tonlu) */
      const cv=document.createElement('canvas');cv.width=48;cv.height=16;const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      this.fill(x,0,0,16,16,['#6b4a2b','#5e4024','#7a5632','#543a20'],11);
      this.fill(x,16,0,16,16,['#6b4a2b','#5e4024','#7a5632','#543a20'],12);
      this.fill(x,16,0,16,5,['#5c9c3e','#6fb24c','#4f8a34','#79c158'],13);
      this.fill(x,32,0,16,16,['#5c9c3e','#6fb24c','#4f8a34','#79c158','#8ccf63'],14);
      const t=this.tex(cv);
      this.withAtlas(t,()=>{this.paintTile(x,2,0,0,0);this.paintTile(x,3,0,16,0);this.paintTile(x,0,0,32,0,'#96e15a')});
      return t
    },
    grassTopOnly(){
      const cv=document.createElement('canvas');cv.width=16;cv.height=16;const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      this.fill(x,0,0,16,16,['#5c9c3e','#6fb24c','#4f8a34','#79c158','#8ccf63'],15);
      const t=this.tex(cv);t.wrapS=t.wrapT=THREE.RepeatWrapping;
      this.withAtlas(t,()=>this.paintTile(x,0,0,0,0,'#96e15a'));
      return t
    },
    woodAtlas(){
      /* 2 kare: 0 kabuk (4,1), 1 kesit (5,1) */
      const cv=document.createElement('canvas');cv.width=32;cv.height=16;const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      this.fill(x,0,0,16,16,['#6e4a28','#5c3c1f','#7d5631','#4e3419'],21);
      for(let i=0;i<16;i+=3){x.fillStyle='#4a3015';x.fillRect(i,0,1,16)}
      this.fill(x,16,0,16,16,['#8a6a3c','#7a5a30','#9c7a48'],22);
      x.strokeStyle='#5c3c1f';x.lineWidth=1;
      [3,6,9].forEach(r=>{x.beginPath();x.arc(24,8,r,0,6.3);x.stroke()});
      const t=this.tex(cv);
      this.withAtlas(t,()=>{this.paintTile(x,4,1,0,0);this.paintTile(x,5,1,16,0)});
      return t
    },
    leaf(){
      const cv=document.createElement('canvas');cv.width=16;cv.height=16;const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      this.fill(x,0,0,16,16,['#3f7d2c','#4f8e36','#5c9c3e','#2f6a20'],31);
      const t=this.tex(cv);
      this.withAtlas(t,()=>this.paintTile(x,5,3,0,0,'#a0ff5a')); /* opak yaprak karesi (5,3), yeşil tonlu */
      return t
    },
    skin(tones,seed,tile,tint){
      const cv=document.createElement('canvas');cv.width=16;cv.height=16;const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      this.fill(x,0,0,16,16,tones,seed);
      const t=this.tex(cv);
      if(tile)this.withAtlas(t,()=>this.paintTile(x,tile[0],tile[1],0,0,tint));
      return t
    },
    imageSkin(path){
      const cv=document.createElement('canvas');cv.width=64;cv.height=64;
      const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      x.fillStyle='#777';x.fillRect(0,0,64,64);
      const t=this.tex(cv),im=new Image();
      im.onload=()=>{x.clearRect(0,0,64,64);x.drawImage(im,0,0,64,64);t.needsUpdate=true;if(typeof Scene!=='undefined')Scene.dirty=true};
      im.onerror=()=>console.warn('Minecraft texture could not load:',path);
      im.src=path;return t
    },
    face(seed,draw){
      const cv=document.createElement('canvas');cv.width=16;cv.height=16;const x=cv.getContext('2d');x.imageSmoothingEnabled=false;
      draw(x);
      const t=this.tex(cv),m=new THREE.Mesh(new THREE.PlaneGeometry(.34,.2),new THREE.MeshBasicMaterial({map:t,transparent:true,depthWrite:false,fog:false}));
      m.rotation.y=Math.PI;return m
    }
  };
  const MCWorld={
    build(){
      const world=new THREE.Group(),dmy=new THREE.Object3D();
      /* --- gökyüzü, güneş, bulutlar --- */
      const sky=new THREE.Mesh(new THREE.SphereGeometry(90,16,10),new THREE.MeshBasicMaterial({color:0x7ec0f2,side:THREE.BackSide,fog:false,depthWrite:false}));
      sky.renderOrder=-1;sky.frustumCulled=false;world.add(sky);
      const sun=new THREE.Mesh(new THREE.SphereGeometry(2.2,10,8),new THREE.MeshBasicMaterial({color:0xfff1b0,fog:false}));
      sun.position.set(30,42,-18);world.add(sun);
      const cloudMat=new THREE.MeshBasicMaterial({color:0xffffff,fog:false}),cloudGeo=new THREE.BoxGeometry(3,.6,2);
      [[-10,16,-14],[8,17,-18],[-16,15,6],[14,16,10],[0,18,-24]].forEach(([cx,cy,cz])=>{
        const cl=new THREE.Group();
        for(let k=0;k<3;k++){const b=new THREE.Mesh(cloudGeo,cloudMat);b.position.set((k-1)*1.6,0,(k%2)*.6-.3);cl.add(b)}
        cl.position.set(cx,cy,cz);world.add(cl)
      });
      world.add(new THREE.AmbientLight(0xffffff,.78));
      const dl=new THREE.DirectionalLight(0xfff3d6,.8);dl.position.set(.4,1,.3);world.add(dl);
      /* --- çimenlik zemin: yakında gerçek bloklar (InstancedMesh), ufka kadar düz doku --- */
      const grassMat=new THREE.MeshLambertMaterial({map:MCTex.grassAtlas()}),
        grassGeo=new THREE.BoxGeometry(1,1,1);
      MCTex.atlasFace(grassGeo,3,[1,1,2,0,1,1]);
      const GN=16,gGrid=new THREE.InstancedMesh(grassGeo,grassMat,GN*GN);
      let gi=0;
      for(let i=0;i<GN;i++)for(let j=0;j<GN;j++){dmy.position.set(i-GN/2+.5,-.5,j-GN/2+.5);dmy.updateMatrix();gGrid.setMatrixAt(gi++,dmy.matrix)}
      gGrid.instanceMatrix.needsUpdate=true;world.add(gGrid);
      const farTex=MCTex.grassTopOnly();farTex.repeat.set(40,40);
      const farGeo=new THREE.PlaneGeometry(80,80);farGeo.rotateX(-Math.PI/2);
      const farPlane=new THREE.Mesh(farGeo,new THREE.MeshLambertMaterial({map:farTex}));farPlane.position.y=-.02;world.add(farPlane);
      /* --- ağaçlar: gövdeler + yapraklar tek InstancedMesh (tek çizim çağrısı) --- */
      const woodMat=new THREE.MeshLambertMaterial({map:MCTex.woodAtlas()}),leafMat=new THREE.MeshLambertMaterial({map:MCTex.leaf()});
      const trunkGeo=new THREE.BoxGeometry(.55,3,.55);MCTex.atlasFace(trunkGeo,2,[0,0,1,1,0,0]);
      const nT=9,TREE=[];
      for(let i=0;i<nT;i++){const a=i/nT*Math.PI*2+.3,r=6.4+(i%3)*1.1;TREE.push([Math.cos(a)*r,Math.sin(a)*r])}
      const trunks=new THREE.InstancedMesh(trunkGeo,woodMat,TREE.length);
      TREE.forEach(([tx,tz],i)=>{dmy.position.set(tx,1.5,tz);dmy.updateMatrix();trunks.setMatrixAt(i,dmy.matrix)});
      trunks.instanceMatrix.needsUpdate=true;world.add(trunks);
      const leafOff=[];
      [2.0,2.7].forEach(dy=>{for(let dx=-1;dx<=1;dx++)for(let dz=-1;dz<=1;dz++)leafOff.push([dx,dy,dz])});
      [[0,0],[1,0],[-1,0],[0,1],[0,-1]].forEach(([dx,dz])=>leafOff.push([dx,3.3,dz]));
      const leafGeo=new THREE.BoxGeometry(1,1,1),leaves=new THREE.InstancedMesh(leafGeo,leafMat,TREE.length*leafOff.length);
      let li=0;
      TREE.forEach(([tx,tz])=>{leafOff.forEach(([dx,dy,dz])=>{dmy.position.set(tx+dx,dy,tz+dz);dmy.updateMatrix();leaves.setMatrixAt(li++,dmy.matrix)})});
      leaves.instanceMatrix.needsUpdate=true;world.add(leaves);
      /* --- canlılar: köylü, domuz, zombi (blok gövdeler + alfa yüz dokusu) --- */
      const skinVillager=MCTex.imageSkin('minecraft/villager_head.png'),
        robeTex=MCTex.imageSkin('minecraft/villager_robe.png'),
        sashTex=MCTex.skin(['#7a4a2a','#6d3f22','#875332'],43,[4,1]),
        pigSkin=MCTex.imageSkin('minecraft/pig_skin.png'),
        zombieSkin=MCTex.imageSkin('minecraft/zombie_head.png'),
        zombieCloth=MCTex.imageSkin('minecraft/zombie_clothes.png');
      const villager=()=>{
        const g=new THREE.Group();
        const body=new THREE.Mesh(new THREE.BoxGeometry(.5,1.1,.32),new THREE.MeshLambertMaterial({map:robeTex}));body.position.y=.55;g.add(body);
        const sash=new THREE.Mesh(new THREE.BoxGeometry(.52,.18,.34),new THREE.MeshLambertMaterial({map:sashTex}));sash.position.y=.62;g.add(sash);
        const head=new THREE.Mesh(new THREE.BoxGeometry(.42,.42,.4),new THREE.MeshLambertMaterial({map:skinVillager}));head.position.y=1.32;g.add(head);
        const nose=new THREE.Mesh(new THREE.BoxGeometry(.12,.2,.22),new THREE.MeshLambertMaterial({map:skinVillager}));nose.position.set(0,1.3,-.29);g.add(nose);
        const armGeo=new THREE.BoxGeometry(.14,.68,.14),armMat=new THREE.MeshLambertMaterial({map:robeTex});
        const armL=new THREE.Mesh(armGeo,armMat);armL.position.set(-.32,.56,0);g.add(armL);
        const armR=new THREE.Mesh(armGeo,armMat);armR.position.set(.32,.56,0);g.add(armR);
        const face=MCTex.face(0,x=>{x.fillStyle='#1c1c1c';x.fillRect(3,6,2,2);x.fillRect(11,6,2,2)});
        face.position.set(0,1.37,-.205);g.add(face);
        return g
      };
      const pig=()=>{
        const g=new THREE.Group(),pm=new THREE.MeshLambertMaterial({map:pigSkin});
        const body=new THREE.Mesh(new THREE.BoxGeometry(.85,.5,.5),pm);body.position.y=.45;g.add(body);
        const legGeo=new THREE.BoxGeometry(.13,.28,.13);
        [[-.3,-.18],[-.3,.18],[.3,-.18],[.3,.18]].forEach(([lx,lz])=>{const l=new THREE.Mesh(legGeo,pm);l.position.set(lx,.14,lz);g.add(l)});
        const head=new THREE.Mesh(new THREE.BoxGeometry(.38,.36,.36),pm);head.position.set(0,.52,-.5);g.add(head);
        const snout=new THREE.Mesh(new THREE.BoxGeometry(.18,.14,.08),new THREE.MeshLambertMaterial({color:0xe396a6}));snout.position.set(0,.47,-.72);g.add(snout);
        const face=MCTex.face(0,x=>{x.fillStyle='#1c1c1c';x.fillRect(2,5,2,2);x.fillRect(12,5,2,2);x.fillStyle='#b05a6e';x.fillRect(5,10,6,3)});
        face.position.set(0,.55,-.69);g.add(face);
        return g
      };
      const zombie=()=>{
        const g=new THREE.Group(),legGeo=new THREE.BoxGeometry(.22,.75,.22),legMat=new THREE.MeshLambertMaterial({map:zombieCloth});
        const legL=new THREE.Mesh(legGeo,legMat);legL.position.set(-.12,.375,0);g.add(legL);
        const legR=new THREE.Mesh(legGeo,legMat);legR.position.set(.12,.375,0);g.add(legR);
        const body=new THREE.Mesh(new THREE.BoxGeometry(.5,.75,.28),new THREE.MeshLambertMaterial({map:zombieCloth}));body.position.y=1.125;g.add(body);
        const armGeo=new THREE.BoxGeometry(.18,.75,.18),armMat=new THREE.MeshLambertMaterial({map:zombieSkin});
        const armL=new THREE.Mesh(armGeo,armMat);armL.position.set(-.34,1.05,-.2);armL.rotation.x=-1.0;g.add(armL);
        const armR=new THREE.Mesh(armGeo,armMat);armR.position.set(.34,1.05,-.2);armR.rotation.x=-1.0;g.add(armR);
        const head=new THREE.Mesh(new THREE.BoxGeometry(.42,.42,.42),new THREE.MeshLambertMaterial({map:zombieSkin}));head.position.y=1.7;g.add(head);
        const face=MCTex.face(0,x=>{x.fillStyle='#0c0c0c';x.fillRect(3,5,3,3);x.fillRect(10,5,3,3);x.fillStyle='#160a0a';x.fillRect(5,10,6,2)});
        face.position.set(0,1.72,-.215);g.add(face);
        return g
      };
      [[-3.2,-2.0],[-2.0,-3.6],[-4.6,1.0]].forEach(([vx,vz])=>{const m=villager();m.position.set(vx,0,vz);m.lookAt(0,1.3,0);world.add(m)});
      [[2.6,-1.4],[3.6,.6],[1.6,2.8]].forEach(([px,pz],i)=>{const m=pig();m.position.set(px,0,pz);m.rotation.y=i*2.1;world.add(m)});
      [[-5.6,4.2],[5.4,-5.6]].forEach(([zx,zz])=>{const m=zombie();m.position.set(zx,0,zz);m.lookAt(0,1.6,0);world.add(m)});
      return world
    }
  };
