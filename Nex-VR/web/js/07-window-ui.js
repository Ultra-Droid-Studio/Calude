'use strict';
  /* ---------- Windows 7: gerçekçi ultrawide masaüstü seti (masa, monitör, klavye, mouse) ----------
     Klavye ve mouse yalnızca görsel maket: ışın testine kapalı, elle/fareyle etkileşim yok.
     Panel (Windows 7) tam olarak monitör ekranı kadardır: W x H, merkez Y, uzaklık R. */
  const W7Desk={group:null,
    W:2.8,H:1.2,R:2.62,Y:1.62,TOP:.84,S:2.4,
    mat(color,rough,metal,extra){return new THREE.MeshStandardMaterial(Object.assign({color:color,roughness:rough==null?.8:rough,metalness:metal||0},extra||{}))},
    mesh(geo,mat,x,y,z,parent){const m=new THREE.Mesh(geo,mat);m.position.set(x||0,y||0,z||0);if(parent)parent.add(m);return m},
    box(w,h,d,x,y,z,mat,parent){return this.mesh(new THREE.BoxGeometry(w,h,d),mat,x,y,z,parent)},
    rrShape(w,d,r){const s=new THREE.Shape(),x=-w/2,y=-d/2;s.moveTo(x+r,y);s.lineTo(x+w-r,y);s.quadraticCurveTo(x+w,y,x+w,y+r);s.lineTo(x+w,y+d-r);s.quadraticCurveTo(x+w,y+d,x+w-r,y+d);s.lineTo(x+r,y+d);s.quadraticCurveTo(x,y+d,x,y+d-r);s.lineTo(x,y+r);s.quadraticCurveTo(x,y,x+r,y);return s},
    /* Yuvarlak köşeli, kenarı pahlı plaka: altı y'de, yukarı doğru h kadar yükselir. */
    slab(w,d,h,r,bev,mat,x,y,z,parent){
      const g=new THREE.ExtrudeGeometry(this.rrShape(w-2*bev,d-2*bev,Math.max(.0001,r-bev)),{depth:Math.max(.0001,h-2*bev),bevelEnabled:bev>0,bevelThickness:bev,bevelSize:bev,bevelSegments:2,curveSegments:6});
      g.rotateX(-Math.PI/2);g.translate(0,bev,0);
      return this.mesh(g,mat,x,y,z,parent)
    },
    tube(pts,rad,mat,parent,seg){const c=new THREE.CatmullRomCurve3(pts.map(p=>new THREE.Vector3(p[0],p[1],p[2])));return this.mesh(new THREE.TubeGeometry(c,seg||24,rad,6,false),mat,0,0,0,parent)},
    woodTex(){
      const c=document.createElement('canvas');c.width=1024;c.height=512;const x=c.getContext('2d');
      x.fillStyle='#6a4330';x.fillRect(0,0,1024,512);
      for(let i=0;i<300;i++){
        const y=Math.random()*512,a=.05+Math.random()*.13;
        x.strokeStyle=Math.random()<.5?'rgba(32,16,8,'+a+')':'rgba(196,138,92,'+a*.8+')';
        x.lineWidth=.6+Math.random()*2.4;x.beginPath();x.moveTo(0,y);let yy=y;
        for(let px=0;px<=1024;px+=64){yy+=(Math.random()-.5)*5;x.lineTo(px,yy)}
        x.stroke()
      }
      const t=new THREE.CanvasTexture(c);t.anisotropy=4;return t
    },
    textTex(w,h,draw){const c=document.createElement('canvas');c.width=w;c.height=h;draw(c.getContext('2d'),w,h);const t=new THREE.CanvasTexture(c);t.minFilter=THREE.LinearFilter;t.generateMipmaps=false;t.anisotropy=4;return t},
    buildDesk(G){
      const top=this.TOP,wood=this.mat(0x7a4f36,.5),side=this.mat(0x5a3a28,.55),dark=this.mat(0x1b1e23,.55,.35);
      const topMat=new THREE.MeshStandardMaterial({map:this.woodTex(),roughness:.46,metalness:0});
      // Tabla: üst yüzde ahşap deseni, kenarlarda koyu bant.
      const slab=new THREE.Mesh(new THREE.BoxGeometry(3.1,.05,1.1),[side,side,topMat,side,side,side]);
      slab.position.set(0,top-.025,-2.45);G.add(slab);
      this.box(3.12,.012,1.12,0,top-.056,-2.45,wood,G);
      // Metal ayaklar ve ray.
      [[-1.45,-1.95],[1.45,-1.95],[-1.45,-2.95],[1.45,-2.95]].forEach(p=>this.box(.06,top-.06,.06,p[0],(top-.06)/2,p[1],dark,G));
      this.box(2.9,.05,.03,0,top-.14,-2.95,dark,G);
      this.box(.03,.05,1.0,-1.45,top-.14,-2.45,dark,G);
      this.box(.03,.05,1.0,1.45,top-.14,-2.45,dark,G);
      // Geniş mouse altlığı (dikişli kenar).
      this.slab(2.12,.52,.003,.035,.0008,this.mat(0x2b2f36,.95),-.05,top,-2.2,G);
      this.slab(2.1,.5,.0042,.033,.0008,this.mat(0x12151a,.97),-.05,top,-2.2,G)
    },
    buildMonitor(G){
      const sw=this.W,sh=this.H,cy=this.Y,R=this.R,t=.024,c=.05,fd=.03;
      const bez=this.mat(0x0f1216,.34,.25),shell=this.mat(0x15191e,.45,.2),metal=this.mat(0x6f7781,.35,.45);
      // Ekran camı (panelin arkasında), panel sw x sh ile birebir örtüşür.
      this.box(sw,sh,.004,0,cy,-R-.004,this.mat(0x02040a,.2),G);
      const fz=-R-fd/2+.002;
      this.box(sw+2*t,t,fd,0,cy+sh/2+t/2,fz,bez,G);
      this.box(sw+2*t,c,fd,0,cy-sh/2-c/2,fz,bez,G);
      this.box(t,sh,fd,-(sw/2+t/2),cy,fz,bez,G);
      this.box(t,sh,fd,(sw/2+t/2),cy,fz,bez,G);
      // Arka gövde ve kabarıklık.
      const W2=sw+2*t,H2=sh+t+c,cy2=cy+(t-c)/2;
      const back=this.slab(W2,H2,.05,.03,.008,shell,0,0,0,null);
      back.geometry.dispose();
      const bg=new THREE.ExtrudeGeometry(this.rrShape(W2-.016,H2-.016,.022),{depth:.034,bevelEnabled:true,bevelThickness:.008,bevelSize:.008,bevelSegments:2,curveSegments:6});
      G.add(this.mesh(bg,shell,0,cy2,-R-.012-.05,null));
      const bg2=new THREE.ExtrudeGeometry(this.rrShape(W2*.5,H2*.55,.05),{depth:.03,bevelEnabled:true,bevelThickness:.01,bevelSize:.01,bevelSegments:2,curveSegments:6});
      G.add(this.mesh(bg2,this.mat(0x1b2026,.5,.15),0,cy2,-R-.07-.04,null));
      // Altta marka yazısı ve güç ışığı.
      const lt=this.textTex(512,96,(x,w,h)=>{x.clearRect(0,0,w,h);x.fillStyle='#9aa4b2';x.font='600 54px Arial';x.textAlign='center';x.textBaseline='middle';x.fillText('N E X U S',w/2,h/2)});
      const lg=new THREE.Mesh(new THREE.PlaneGeometry(.34,.064),new THREE.MeshBasicMaterial({map:lt,transparent:true,depthWrite:false}));
      lg.position.set(0,cy-sh/2-c/2,-R+.0032);G.add(lg);
      this.box(.012,.005,.001,sw/2-.14,cy-sh/2-c/2,-R+.0032,new THREE.MeshBasicMaterial({color:0x4aa8ff}),G);
      // Ayak: boyun + geniş taban.
      const neckTop=cy-.18,neckBot=this.TOP+.016;
      this.box(.16,neckTop-neckBot,.04,0,(neckTop+neckBot)/2,-R-.15,metal,G);
      this.slab(1.0,.38,.018,.05,.006,metal,0,this.TOP,-R-.20,G)
    },
    capGeo(){
      const N=36,n=3.2,e=2/n,rings=[[1,0],[.97,.35],[.9,.7],[.84,.93],[.82,1],[.6,.965],[0,.945]],pos=[],idx=[];
      rings.forEach(r=>{
        if(r[0]===0){pos.push(0,r[1],0);return}
        for(let i=0;i<N;i++){
          const a=i/N*Math.PI*2,cs=Math.cos(a),sn=Math.sin(a);
          pos.push(Math.sign(cs)*Math.pow(Math.abs(cs),e)*.5*r[0],r[1],Math.sign(sn)*Math.pow(Math.abs(sn),e)*.5*r[0])
        }
      });
      for(let r=0;r<5;r++)for(let i=0;i<N;i++){
        const a=r*N+i,b=r*N+(i+1)%N,c=(r+1)*N+i,d=(r+1)*N+(i+1)%N;idx.push(a,c,b,b,c,d)
      }
      for(let i=0;i<N;i++)idx.push(5*N+i,6*N,5*N+(i+1)%N);
      const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));g.setIndex(idx);g.computeVertexNormals();return g
    },
    keyList(){
      const K=[],add=(l,x,y,w,h,m)=>K.push({l:l,x:x,y:y,w:w||1,h:h||1,mod:!!m});
      add('Esc',0,0,1,1,1);
      [['F1',2],['F2',3],['F3',4],['F4',5],['F5',6.5],['F6',7.5],['F7',8.5],['F8',9.5],['F9',11],['F10',12],['F11',13],['F12',14]].forEach(a=>add(a[0],a[1],0,1,1,1));
      ['PrtSc','ScrLk','Pause'].forEach((l,i)=>add(l,15.5+i,0,1,1,1));
      '`1234567890-='.split('').forEach((l,i)=>add(l,i,1.5));
      add('⌫',13,1.5,2,1,1);
      ['Ins','Home','PgUp'].forEach((l,i)=>add(l,15.5+i,1.5,1,1,1));
      ['Num','/','*','-'].forEach((l,i)=>add(l,19+i,1.5,1,1,1));
      add('Tab',0,2.5,1.5,1,1);
      'QWERTYUIOP[]'.split('').forEach((l,i)=>add(l,1.5+i,2.5));
      add('\\',13.5,2.5,1.5,1);
      ['Del','End','PgDn'].forEach((l,i)=>add(l,15.5+i,2.5,1,1,1));
      ['7','8','9'].forEach((l,i)=>add(l,19+i,2.5));
      add('+',22,2.5,1,2,1);
      add('Caps',0,3.5,1.75,1,1);
      "ASDFGHJKL;'".split('').forEach((l,i)=>add(l,1.75+i,3.5));
      add('Enter',12.75,3.5,2.25,1,1);
      ['4','5','6'].forEach((l,i)=>add(l,19+i,3.5));
      add('Shift',0,4.5,2.25,1,1);
      'ZXCVBNM,./'.split('').forEach((l,i)=>add(l,2.25+i,4.5));
      add('Shift',12.25,4.5,2.75,1,1);
      add('↑',16.5,4.5,1,1,1);
      ['1','2','3'].forEach((l,i)=>add(l,19+i,4.5));
      add('Enter',22,4.5,1,2,1);
      add('Ctrl',0,5.5,1.25,1,1);add('Win',1.25,5.5,1.25,1,1);add('Alt',2.5,5.5,1.25,1,1);
      add('',3.75,5.5,6.25,1);
      add('Alt',10,5.5,1.25,1,1);add('Win',11.25,5.5,1.25,1,1);add('Menu',12.5,5.5,1.25,1,1);add('Ctrl',13.75,5.5,1.25,1,1);
      add('←',15.5,5.5,1,1,1);add('↓',16.5,5.5,1,1,1);add('→',17.5,5.5,1,1,1);
      add('0',19,5.5,2,1);add('.',21,5.5,1,1);
      return K
    },
    /* Gerçek ölçülerde (metre) tam boy klavye; üst grup S kat büyütür. */
    buildKeyboard(){
      const g=new THREE.Group(),P=.01905,KW=23*P,KD=6.5*P,ox=-KW/2,oz=-KD/2;
      const rowY=[0,1.5,2.5,3.5,4.5,5.5],rh=[.0085,.0098,.0092,.0088,.0082,.0075],rt=[.10,.12,.09,.06,.03,0];
      const rowOf=y=>rowY.indexOf(y);
      const inner=new THREE.Group();inner.rotation.x=.06;g.add(inner);
      this.slab(.458,.150,.0125,.009,.003,this.mat(0x1d2127,.42,.3),0,0,0,inner);
      this.box(.446,.0016,.1345,0,.012,0,this.mat(0x07090c,.9),inner);
      const keys=this.keyList(),im=new THREE.InstancedMesh(this.capGeo(),this.mat(0xffffff,.5,.05),keys.length);
      const m4=new THREE.Matrix4(),q=new THREE.Quaternion(),eu=new THREE.Euler(),col=new THREE.Color(),v=new THREE.Vector3(),sc=new THREE.Vector3();
      keys.forEach((k,i)=>{
        const r=rowOf(k.y);
        q.setFromEuler(eu.set(rt[r],0,0));
        v.set(ox+(k.x+k.w/2)*P,.0128,oz+(k.y+k.h/2)*P);
        sc.set(k.w*P-.0014,rh[r],k.h*P-.0014);
        m4.compose(v,q,sc);im.setMatrixAt(i,m4);
        im.setColorAt(i,col.set(k.mod?0x434a56:0x2b3037))
      });
      im.instanceMatrix.needsUpdate=true;if(im.instanceColor)im.instanceColor.needsUpdate=true;
      inner.add(im);
      // Tuş yazıları: her sıra için ince, saydam bir levha.
      const TW=2048,TH=256,ppm=TW/KW,dep=TH/ppm;
      rowY.forEach((ry,r)=>{
        const list=keys.filter(k=>rowOf(k.y)===r&&k.l);
        const tex=this.textTex(TW,TH,(x,w,h)=>{
          x.clearRect(0,0,w,h);x.fillStyle='#e6ecf5';x.textAlign='center';x.textBaseline='middle';
          list.forEach(k=>{
            x.font='600 '+(k.l.length>3?25:k.l.length>1?30:46)+'px Arial';
            x.fillText(k.l,(k.x+k.w/2)*P*ppm,((k.y+k.h/2)-ry)*P*ppm)
          })
        });
        const pg=new THREE.PlaneGeometry(KW,dep);pg.rotateX(-Math.PI/2);
        const pm=new THREE.Mesh(pg,new THREE.MeshBasicMaterial({map:tex,transparent:true,depthWrite:false}));
        pm.position.set(0,.0128+rh[r]*.985+.0002,oz+ry*P+dep/2);pm.rotation.x=rt[r];inner.add(pm)
      });
      // Arka tarafa giden kablo.
      this.tube([[0,.006,-.075],[0,.004,-.1],[-.03,.003,-.16],[-.05,.003,-.28]],.0018,this.mat(0x101317,.8),g,20);
      return g
    },
    buildMouse(){
      const g=new THREE.Group(),L=.121,W=.066,H=.039,PI=Math.PI;
      const ef=a=>Math.pow(Math.max(.0001,Math.sin(PI*Math.min(.9999,Math.max(.0001,a)))),.32);
      const wf=a=>(W/2)*(.66+.34*Math.sin(PI*(.1+.78*a)))*ef(a);
      const hf=a=>H*(.30+.70*Math.pow(Math.max(0,Math.sin(PI*(.05+.8*a))),.8))*ef(a);
      const zf=a=>-L/2+a*L;
      const yAt=(a,b)=>hf(a)*Math.pow(Math.max(0,1-Math.pow(Math.abs(b),2.4)),1/2.4);
      const surf=(a0,a1,b0,b1,na,nb,k,lift)=>{
        const pos=[],idx=[];
        for(let i=0;i<=na;i++){const a=a0+(a1-a0)*i/na;
          for(let j=0;j<=nb;j++){const b=b0+(b1-b0)*j/nb;pos.push(wf(a)*b,yAt(a,b)*k+lift,zf(a))}}
        for(let i=0;i<na;i++)for(let j=0;j<nb;j++){
          const v00=i*(nb+1)+j,v01=v00+1,v10=v00+nb+1,v11=v10+1;idx.push(v00,v10,v01,v10,v11,v01)}
        const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));geo.setIndex(idx);geo.computeVertexNormals();return geo
      };
      const shellM=this.mat(0x1a1e24,.34,.1),btnM=this.mat(0x2a3039,.3,.1),rub=this.mat(0x0d1013,.85),side=this.mat(0x3b434e,.4,.1);
      this.mesh(surf(0,1,-1,1,44,44,1,0),shellM,0,0,0,g);
      // Sol / sağ tuşlar: gövdeden hafif yüksek, ortada tekerlek yuvası boşluğu.
      this.mesh(surf(.03,.43,-1,-.12,16,14,1.03,.0002),btnM,0,0,0,g);
      this.mesh(surf(.03,.43,.12,1,16,14,1.03,.0002),btnM,0,0,0,g);
      // Tuşların arkasındaki ince koyu ayrım çizgisi.
      const seam=[];for(let j=0;j<=24;j++){const b=-1+2*j/24;seam.push([wf(.43)*b,yAt(.43,b)*1.012,zf(.43)])}
      this.tube(seam,.0005,rub,g,24);
      // Tekerlek ve yuvası.
      const wa=.22,wy=hf(wa)*1.03;
      this.box(.0082,.003,.024,0,wy-.0018,zf(wa),rub,g);
      const wheel=new THREE.Mesh(new THREE.CylinderGeometry(.0085,.0085,.0058,20,1),new THREE.MeshStandardMaterial({color:0x14181d,roughness:.7,flatShading:true}));
      wheel.rotation.z=PI/2;wheel.position.set(0,wy-.0012,zf(wa));g.add(wheel);
      // DPI düğmesi.
      this.box(.007,.0014,.0045,0,hf(.34)*1.01+.0003,zf(.34),side,g);
      // Başparmak yan tuşları (sol yan).
      [.30,.40].forEach(a=>{const m=this.box(.0032,.0048,.0145,-wf(a)*.985,hf(a)*.45,zf(a),side,g);m.rotation.y=.04});
      // Avuç içinde ince ışıklı logo.
      const la=.78,dz=(hf(la+.01)-hf(la-.01))/(.02*L),logo=new THREE.CircleGeometry(.0062,20);logo.rotateX(-PI/2);
      const lm=new THREE.Mesh(logo,new THREE.MeshBasicMaterial({color:0x4aa8ff}));lm.position.set(0,hf(la)+.0003,zf(la));lm.rotation.x=Math.atan(-dz);g.add(lm);
      // Alt taban (kauçuk).
      const sp=[];for(let i=0;i<=24;i++){const a=i/24;sp.push([-wf(a),zf(a)])}for(let i=24;i>=0;i--){const a=i/24;sp.push([wf(a),zf(a)])}
      const sh=new THREE.Shape();sp.forEach((p,i)=>i?sh.lineTo(p[0],p[1]):sh.moveTo(p[0],p[1]));
      const bg=new THREE.ShapeGeometry(sh);bg.rotateX(PI/2);this.mesh(bg,rub,0,.0003,0,g);
      // Kablo: öne doğru (monitöre) uzanır.
      this.tube([[0,.0045,zf(0)+.002],[0,.003,zf(0)-.02],[.006,.0022,zf(0)-.07],[-.012,.0019,zf(0)-.15],[-.03,.0018,zf(0)-.26]],.0014,this.mat(0x101317,.8),g,30);
      return g
    },
    show(){
      if(this.group){this.group.visible=true;Scene.dirty=true;return}
      const G=this.group=new THREE.Group();
      this.buildDesk(G);this.buildMonitor(G);
      const peri=new THREE.Group();peri.scale.setScalar(this.S);peri.position.set(0,this.TOP+.0042,-2.2);G.add(peri);
      const kb=this.buildKeyboard();kb.position.set(-.117,0,0);peri.add(kb);
      const ms=this.buildMouse();ms.position.set(.30,0,0);ms.rotation.y=.07;peri.add(ms);
      // Klavye ve mouse yalnızca görsel: ışın testine kapalı, sabit.
      G.traverse(o=>{o.raycast=()=>{}});
      G.updateMatrixWorld(true);
      G.traverse(o=>{o.matrixAutoUpdate=false});
      Scene.scene.add(G);Scene.dirty=true
    },
    hide(){if(this.group){this.group.visible=false;Scene.dirty=true}},
    /* Masa yalnızca Win7 paneli açık ve görünürken görünür; sinema, ışın kılıcı, gezegenler gibi modlar paneli gizleyince masa da gizlenir. */
    sync(){
      if(!this.group)return;
      const m=WM.panels.find(p=>p.userData.id==='win7simu'),want=!!m&&m.visible&&!m.userData.min;
      if(this.group.visible!==want){this.group.visible=want;Scene.dirty=true}
    },
    dispose(){if(!this.group)return;Scene.scene.remove(this.group);this.group.traverse(o=>{if(o.geometry)o.geometry.dispose();if(o.material){if(o.material.map)o.material.map.dispose();o.material.dispose()}});this.group=null}
  };

  /* ---------- Stage 23: Pencere çubuğu (Quest/PhoneXR tarzı alt hap) ----------
     Her pencerenin altında yüzen koyu cam kapsül: başlık (tut-sürükle) + klavye, büyüt, küçült, kapat.
     Pencerenin çocuk mesh'idir; ışın seçme (Scene.targets) ve Input düğme/bekleme yolları aynen çalışır. */
  const Pill={
    CW:640,CH:96,
    ok(o){return !!o&&!!o.userData&&!o.userData.dead&&(WM.panels.includes(o)||!!o.userData.pillOf||!!o.userData.handMenu)},
    cw(u){return u.skin==='shz'?960:this.CW},
    want(m){const u=m.userData;return Settings.v.pill!==false&&(!!u.chrome||u.skin==='shz')&&!u.dock&&!u.kbd&&!u.fixedDesk&&!!u.cflat},
    sync(m){
      const u=m.userData;
      if(!this.want(m)){this.dispose(m);return}
      const gs=u.gs||1,pw=u.R*u.span*gs,ph=u.h*gs,cw=this.cw(u),wp=u.skin==='shz'?Math.min(pw,Math.max(pw*.7,u.R*.3)):Math.min(pw,Math.max(pw*.46,u.R*.2)),hp=wp*this.CH/cw;
      let pm=u.pill;
      if(!pm||u.pill.userData.dead){
        const cv=document.createElement('canvas');cv.width=cw;cv.height=this.CH;
        const tex=new THREE.CanvasTexture(cv);tex.wrapS=THREE.RepeatWrapping;tex.repeat.x=-1;tex.generateMipmaps=false;tex.minFilter=THREE.LinearFilter;
        pm=new THREE.Mesh(new THREE.BufferGeometry(),new THREE.MeshBasicMaterial({map:tex,transparent:true,side:THREE.DoubleSide,depthWrite:false}));
        pm.userData={panel:true,pillOf:m,btns:[],hov:-1,cv,tex,R:u.R,id:(u.id||'win')+':pill',chrome:false,key:'',dead:false};
        pm.castShadow=false;pm.renderOrder=3;
        m.add(pm);u.pill=pm
      }
      pm.userData.R=u.R;
      pm.geometry.dispose();
      const g=new THREE.PlaneGeometry(wp,hp),uv=g.attributes.uv;
      for(let i=0;i<uv.count;i++)uv.setX(i,1-uv.getX(i));
      uv.needsUpdate=true;pm.geometry=g;
      pm.position.set(0,-ph/2-hp*.7,-u.R+curveZ(u,0)+.02);
      pm.userData.key='';
      this.paint(pm,true)
    },
    dispose(m){
      const u=m.userData,pm=u.pill;
      if(!pm)return;
      pm.userData.dead=true;
      m.remove(pm);pm.geometry.dispose();pm.userData.tex.dispose();pm.material.dispose();
      u.pill=null
    },
    kbd(m){
      const u=m.userData;
      if(XR.session){Diag.toast('VR içinde metin girişi yok','var(--warn)');return}
      if(u.id==='browser'){BR.ask();return}
      if(typeof u.kbdFn==='function'){u.kbdFn();return}
      Diag.toast('Bu pencerede yazı alanı yok','var(--warn)',2200)
    },
    paint(pm,force){
      const pu=pm.userData;
      if(pu.dead)return;
      const m=pu.pillOf,u=m.userData,c=pu.cv.getContext('2d'),W=pu.cv.width,H=pu.cv.height;
      const foc=WM.focused===m,dw=(Input.dw&&Input.dw.o===pm)?Input.dw:null;
      const shz=u.skin==='shz',port=shz&&!!(u.web&&SHZ.isPort(u.web.pkg));
      const key=[u.title,foc,u.max,pu.hov,dw?dw.i+':'+Math.round(dw.p*24):'',Settings.v.acc,port].join('|');
      if(!force&&key===pu.key)return;
      pu.key=key;
      c.clearRect(0,0,W,H);
      c.save();c.shadowColor='rgba(0,0,0,.28)';c.shadowBlur=12;c.shadowOffsetY=3;
      rr(c,6,5,W-12,H-14,(H-14)/2);
      c.fillStyle='rgba(34,36,41,.86)';c.fill();c.restore();
      rr(c,6,5,W-12,H-14,(H-14)/2);
      c.lineWidth=1.2;c.strokeStyle=foc?'rgba(255,255,255,.18)':'rgba(255,255,255,.08)';c.stroke();
      /* Taşıma çubuğu: pilin tamamı sürüklenebilir, bu küçük tutamaç bunu görünür kılar */
      c.fillStyle='rgba(255,255,255,.3)';rr(c,W/2-26,11,52,5,2.5);c.fill();
      pu.btns=[];
      const r=27,cy=H/2-2,sp=r*2+10,items=[];
      /* Stage 71: Android (Shizuku) pencerelerinde pile Dik/Yatay + yukarı/aşağı kaydır düğmeleri (basılı tutunca tekrarlar) */
      if(shz){
        const up=()=>BF.scrollId(BF.webId(u),-1),dn=()=>BF.scrollId(BF.webId(u),1);
        up.rep=true;dn.rep=true;
        items.push(['rot',port?'Yatay moda geç':'Dik moda geç',()=>SHZ.rotate(m)],['chevup','Yukarı kaydır',up],['chevdown','Aşağı kaydır',dn])
      }
      items.push(['kbd','Klavye',()=>this.kbd(m)],['expand','Büyüt veya eski boyuta döndür',()=>WM.toggleMax(m)],['min','Küçült',()=>WM.minimize(m,true)],['close','Kapat',()=>WM.close(m)]);
      const x0=W-24-r-(items.length-1)*sp;
      items.forEach((it,k)=>{
        const cx=x0+k*sp,i=pu.btns.length;
        pu.btns.push({x:cx-r,y:cy-r,w:r*2,h:r*2,fn:it[2],n:it[1]});
        const hv=i===pu.hov,on=it[0]==='expand'&&u.max;
        c.beginPath();c.arc(cx,cy,r,0,6.3);
        c.fillStyle=hv?(it[0]==='close'?'rgba(238,76,88,.94)':'rgba(255,255,255,.2)'):on?'rgba(255,255,255,.14)':'rgba(255,255,255,.05)';
        c.fill();
        if(it[0]==='kbd'){
          c.save();c.lineWidth=2.4;c.strokeStyle='#f3f7f8';c.fillStyle='#f3f7f8';
          rr(c,cx-14,cy-9,28,18,4);c.stroke();
          for(let a=0;a<3;a++)for(let b=0;b<2;b++){c.beginPath();c.arc(cx-8+a*8,cy-3+b*7,1.5,0,6.3);c.fill()}
          c.restore()
        }else if(it[0]==='rot'){
          /* Dik/Yatay: geçilecek yönün dikdörtgeni + dönme oku */
          c.save();c.lineWidth=2.4;c.lineJoin='round';c.lineCap='round';c.strokeStyle='#f3f7f8';
          if(port)rr(c,cx-11,cy-7,22,14,3);else rr(c,cx-7,cy-11,14,22,3);
          c.stroke();
          c.beginPath();c.arc(cx,cy,19,-2.5,-0.9);c.stroke();
          const ax=cx+19*Math.cos(-0.9),ay=cy+19*Math.sin(-0.9);
          c.beginPath();c.moveTo(ax-8,ay-1);c.lineTo(ax,ay);c.lineTo(ax-1,ay+8);c.stroke();
          c.restore()
        }else ICN(c,it[0],cx,cy,12,'#f3f7f8');
        if(dw&&dw.i===i&&dw.p>0){
          c.save();c.lineWidth=4;c.lineCap='round';c.strokeStyle='#19d3c5';
          c.beginPath();c.arc(cx,cy,r+3,-Math.PI/2,-Math.PI/2+dw.p*Math.PI*2);c.stroke();c.restore()
        }
      });
      c.textAlign='left';c.font='600 29px system-ui,sans-serif';
      c.fillStyle=foc?'#f1f2f4':'rgba(205,210,218,.55)';
      let t=String(u.title||'');const mw=x0-r-34-26;
      while(t.length>1&&c.measureText(t).width>mw)t=t.slice(0,-1);
      if(t!==String(u.title||''))t=t.slice(0,-1)+'…';
      c.fillText(t,34,cy+10);
      pu.tex.needsUpdate=true;Scene.dirty=true
    }
  };

  /* ---------- Stage 23: El menüsü (avuç yüze dönükken elin üstünde açılır) ----------
     PhoneXR HandMenu mantığı: avuç yüze dönük + açık el ~0,6 sn → elin üstünde cam çubuk. Öbür elin işaret parmağı
     ile bekleme/çimdik seçer. Menü 3B bir paneldir (kameraya bakar); Scene.targets ile seçilebilir. */
  const HMenu={
    m:null,open:false,hand:-1,hold:0,seen:0,x:.5,y:.3,rc:null,v2:null,tv:null,
    CW:720,CH:470,
    items:[
      ['dots9','Kitaplık',()=>Launcher.toggle()],
      ['globe','Tarayıcı',()=>WM.spawn('browser')],
      ['film','Sinema',()=>WM.spawn('cinema')],
      ['gear','Ayarlar',()=>WM.spawn('settings')],
      ['reset','Hizala',()=>{Cam.reset();Scene.dirty=true;Diag.toast('Görünüm hizalandı','var(--ok)',1500)}],
      ['min','Küçült',()=>{WM.panels.filter(p=>p.visible&&p.userData.chrome&&!p.userData.dock&&!p.userData.kbd&&!p.userData.fixedDesk).forEach(p=>WM.minimize(p,true))}]
    ],
    holds(s){return this.open&&this.hand===s.id},
    ensure(){
      if(this.m)return;
      const cv=document.createElement('canvas');cv.width=this.CW;cv.height=this.CH;
      const tex=new THREE.CanvasTexture(cv);tex.wrapS=THREE.RepeatWrapping;tex.repeat.x=-1;tex.generateMipmaps=false;tex.minFilter=THREE.LinearFilter;
      const w=.44,g=new THREE.PlaneGeometry(w,w*this.CH/this.CW),uv=g.attributes.uv;
      for(let i=0;i<uv.count;i++)uv.setX(i,1-uv.getX(i));
      uv.needsUpdate=true;
      const m=new THREE.Mesh(g,new THREE.MeshBasicMaterial({map:tex,transparent:true,side:THREE.DoubleSide,depthTest:false}));
      m.renderOrder=60;m.visible=false;m.castShadow=false;m.frustumCulled=false;
      m.userData={panel:true,handMenu:true,btns:[],hov:-1,cv,tex,R:.8,id:'handmenu',chrome:false};
      Scene.scene.add(m);this.m=m;
      this.rc=new THREE.Raycaster();this.v2=new THREE.Vector2();this.tv=new THREE.Vector3()
    },
    facing(s){
      const r=s.raw,d=(a,b)=>Math.hypot(r[a].x-r[b].x,r[a].y-r[b].y);
      const ax=r[5].x-r[0].x,ay=r[5].y-r[0].y,bx=r[17].x-r[0].x,by=r[17].y-r[0].y,cross=ax*by-ay*bx,palm=Math.max(.02,d(5,17));
      const back=Settings.v.hcam!=='user',lab=String(s.label||'').toLowerCase();
      const physLeft=back?lab==='right':lab==='left';
      let pf=physLeft?cross<0:cross>0;
      if(!back)pf=!pf;
      if(Settings.v.hmflip)pf=!pf;
      return pf&&Math.abs(cross)>palm*palm*.15
    },
    openHand(s){
      const r=s.raw,d=(a,b)=>Math.hypot(r[a].x-r[b].x,r[a].y-r[b].y);
      return [[8,6],[12,10],[16,14],[20,18]].every(p=>d(0,p[0])>d(0,p[1])*1.12)
    },
    scan(S,now){
      if(Settings.v.hmenu===false||XR.session){if(this.open)this.close();return}
      let best=null;
      for(const s of S){
        if(!s.on||!s.d||!s.raw||s.raw.length<21||s.pr||s.mode!=='')continue;
        if(this.openHand(s)&&this.facing(s)){best=s;break}
      }
      if(!best){this.hold=0;return}
      this.seen=now;
      const r=best.raw,px=(r[0].x+r[5].x+r[9].x+r[17].x)/4,py=(r[0].y+r[5].y+r[9].y+r[17].y)/4,palm=Math.hypot(r[5].x-r[17].x,r[5].y-r[17].y);
      const sx=Hand.mirror?1-px:px,tx=clamp(sx,.18,.82),ty=clamp(py-palm*2.2-.12,.14,.84);
      if(!this.open){
        if(!this.hold)this.hold=now;
        else if(now-this.hold>600){this.hand=best.id;this.x=tx;this.y=ty;this.show()}
      }else if(this.hand===best.id){
        this.x+=(tx-this.x)*.35;this.y+=(ty-this.y)*.35
      }
    },
    show(){
      this.ensure();
      this.open=true;this.m.visible=true;this.m.userData.hov=-1;
      this.place();this.paint()
    },
    close(){
      this.hold=0;
      if(!this.open)return;
      this.open=false;
      if(this.m){this.m.visible=false;this.m.userData.hov=-1}
      Input.dwDone=null;Input.dwellClear(true);
      Scene.dirty=true
    },
    place(){
      if(!this.m)return;
      this.rc.setFromCamera(this.v2.set(this.x*2-1,-(this.y*2-1)),Cam.cam);
      const ray=this.rc.ray;
      this.m.position.copy(ray.origin).addScaledVector(ray.direction,.8);
      Cam.cam.getWorldPosition(this.tv);
      this.m.lookAt(this.tv);
      this.m.updateMatrixWorld(true);
      Scene.dirty=true
    },
    tick(){
      if(!this.open)return;
      if(performance.now()-this.seen>1500){this.close();return}
      this.place()
    },
    paint(){
      if(!this.m)return;
      const u=this.m.userData,c=u.cv.getContext('2d'),W=u.cv.width,H=u.cv.height,acc=ACC[Settings.v.acc];
      c.clearRect(0,0,W,H);
      c.save();c.shadowColor='rgba(0,0,0,.5)';c.shadowBlur=26;
      rr(c,16,16,W-32,H-32,90);
      const g=c.createLinearGradient(0,16,0,H-16);g.addColorStop(0,'rgba(43,48,56,.94)');g.addColorStop(1,'rgba(26,30,36,.95)');
      c.fillStyle=g;c.fill();c.restore();
      rr(c,16,16,W-32,H-32,90);c.lineWidth=2;c.strokeStyle='rgba(255,255,255,.2)';c.stroke();
      u.btns=[];
      const COLS=3,PAD=40,tw=(W-2*PAD)/COLS,th=(H-2*PAD)/2,dw=(Input.dw&&Input.dw.o===this.m)?Input.dw:null;
      this.items.forEach((it,i)=>{
        const x=PAD+(i%COLS)*tw+8,y=PAD+Math.floor(i/COLS)*th+8,w=tw-16,h=th-16,hv=i===u.hov;
        u.btns.push({x,y,w,h,fn:()=>{this.close();it[2]()},n:it[1]});
        rr(c,x,y,w,h,34);c.fillStyle=hv?acc:'rgba(255,255,255,.09)';c.fill();
        if(hv){rr(c,x-4,y-4,w+8,h+8,38);c.lineWidth=5;c.strokeStyle='#fff';c.stroke()}
        ICN(c,it[0],x+w/2,y+h*.36,28,'#fff');
        c.fillStyle='#fff';c.textAlign='center';c.font='600 25px system-ui,sans-serif';
        c.fillText(it[1],x+w/2,y+h-24);c.textAlign='left';
        if(dw&&dw.i===i&&dw.p>0){
          c.save();c.lineWidth=6;c.lineCap='round';c.strokeStyle='#19d3c5';
          c.beginPath();c.arc(x+w/2,y+h*.36,40,-Math.PI/2,-Math.PI/2+dw.p*Math.PI*2);c.stroke();c.restore()
        }
      });
      u.tex.needsUpdate=true;Scene.dirty=true
    }
  };
  /* ---------- Pencere yöneticisi (kavisli 360° paneller) ---------- */
  const WM={
    panels:[],
    focused:null,
    names:['Ön yay','360° halka','Yüzen','Minimal'],
    create(def){
      const customR=!!(def&&def.R!==undefined);
      const u=Object.assign({panel:true,sf:1,ang:0,y:1.9,R:2.9,btns:[],hov:-1,chrome:true,live:false,max:false,saved:null,tab:0},def);
      // Normal app windows use flat planes arranged around the user; dock/keyboard keep their own geometry.
      if(u.cflat===undefined)u.cflat=!u.kbd; // Dock and ordinary windows use flat planes; keyboard keeps its own geometry.
      u.base={span:u.span,h:u.h};
      /* Stage 68: Ayarlar → Grafik → Pencere/Dok uzaklığı (metre). Yalnızca kendi R'sini özel
         olarak belirtmeyen sıradan pencereler (tarayıcı, ayarlar, web/Android uygulama pencereleri…)
         ve dock bundan etkilenir; klavye, sinema ekranı, el menüsü gibi özel yerleşimler dokunulmaz. */
      if(u.dock)u.R=Settings.v.ddist||u.R;
      else if(!customR&&!u.kbd&&!u.fixedDesk){u.distAdj=true;u.R=Settings.v.wdist||u.R}
      const m=new THREE.Mesh(new THREE.BufferGeometry(),new THREE.MeshBasicMaterial({side:THREE.BackSide,transparent:true}));
      m.userData=u;
      m.castShadow=false;
      u.cv=document.createElement('canvas');
      u.tex=new THREE.CanvasTexture(u.cv);
      u.tex.wrapS=THREE.RepeatWrapping;
      u.tex.repeat.x=-1;
      u.tex.generateMipmaps=false;
      u.tex.minFilter=THREE.LinearFilter;
      m.material.map=u.tex;
      if(u.flat)m.material.side=THREE.DoubleSide;
      const stackOff=(!u.dock&&!u.kbd&&!u.fixedDesk)?this.panels.length*.004:0;
      u.R+=stackOff;
      if(u.distAdj)u.distOff=stackOff;
      Scene.scene.add(m);
      this.panels.push(m);
      this.build(m);
      return m
    },
    /* Stage 68: uzaklık ayarı değişince açık pencerelere/dock'a uygula (yeniden açmaya gerek yok). */
    applyDist(){
      const wd=clamp(+Settings.v.wdist||2.9,1.2,5),dd=clamp(+Settings.v.ddist||1.8,.8,3.2);
      Settings.v.wdist=wd;Settings.v.ddist=dd;
      this.panels.forEach(m=>{
        const u=m.userData;
        if(u.dock){u.R=dd;this.build(m)}
        else if(u.distAdj){u.R=wd+(u.distOff||0);this.build(m)}
      });
      Scene.dirty=true
    },
    build(m){
      const u=m.userData,fx=u.dock||u.kbd,ps=fx?1:clamp(Settings.v.pscale||1,.7,1.3);
      u.span=u.base.span*u.sf*ps*(fx?1:1.08);
      // Preserve each panel's own proportions. Special panels (score HUD, planet
      // selector, cinema screen, launcher) deliberately use different aspect ratios;
      // forcing every panel into one rectangle breaks their layouts.
      u.h=u.base.h*u.sf*ps*(fx?1:1.08*u.R/3.2);
      if(u.fixedDesk){u.sf=1;u.span=u.fixedW/u.R;u.h=u.fixedH}
      m.geometry.dispose();
      if(u.flat){
        /* Yatay klavye: kullanıcının hemen önünde, zemine paralel düz bir levha. uv.x ters çevrilir (tuş eşlemesi için). */
        const fw=u.fw||1.3,fh=fw*400/1024,g=new THREE.PlaneGeometry(fw,fh),uv=g.attributes.uv;
        for(let i=0;i<uv.count;i++)uv.setX(i,1-uv.getX(i));
        uv.needsUpdate=true;m.geometry=g;
        u.cv.width=1024;u.cv.height=400
      }else{
      if(u.cflat){const gs=u.gs||1,pw=u.R*u.span*gs,ph=u.h*gs,cv=u.curve===undefined?(!u.dock&&!u.kbd):u.curve,pg=new THREE.PlaneGeometry(pw,ph,cv?Math.max(8,Math.ceil(pw*8)):1,1),uv=pg.attributes.uv;for(let i=0;i<uv.count;i++)uv.setX(i,1-uv.getX(i));u.curved=!!cv;if(cv){const pp=pg.attributes.position;for(let i=0;i<pp.count;i++)pp.setZ(i,curveZ(u,pp.getX(i)))}if(u.tilt)pg.rotateX(-u.tilt);pg.translate(0,0,-u.R);m.geometry=pg;m.material.side=THREE.DoubleSide}else m.geometry=new THREE.CylinderGeometry(u.R,u.R,u.h,Math.max(8,Math.ceil(u.span*18)),1,true,Math.PI-u.span/2,u.span);
      u.cv.width=u.dock?Math.round(1024*u.span/1.3):(u.cvW||1024);
      u.cv.height=Math.round(u.cv.width*u.h/(u.R*u.span))
      }
      if(u.liveImg){u.liveImg=null;u.tex.image=u.cv}
      u.tex.dispose();
      Pill.sync(m);
      this.place(m);
      this.paint(m)
    },
    place(m){
      const u=m.userData;
      if(u.fixedDesk){u.ang=0;u.y=u.deskY}
      if(u.flat){
        m.rotation.order='YXZ';
        m.rotation.set(-Math.PI/2,u.ang,0);
        m.position.set(u.fx||0,u.y,u.fz||0)
      }else{
        m.rotation.y=u.ang;
        m.position.set(u.fx||0,u.y,u.fz||0)
      }
      Scene.dirty=true
    },
    paint(m){
      if(m.userData.pillOf){Pill.paint(m,true);return}
      if(m.userData.handMenu){HMenu.paint();return}
      /* Canlı doku (Win7): görüntü doğrudan WebView anlık görüntüsünden gelir; tuvali yeniden çizip yüklemeyiz. */
      if(m.userData.liveImg&&m.userData.fixedDesk){if(m.userData.pill)Pill.paint(m.userData.pill);Scene.dirty=true;return}
      const u=m.userData,c=u.cv.getContext('2d'),W=u.cv.width,H=u.cv.height,acc=ACC[Settings.v.acc],a=Settings.v.alpha,foc=m===this.focused;
      c.clearRect(0,0,W,H);
      if(u.dock)dockBg(c,W,H,a,foc);
      else if(u.skin!=='qs'&&u.skin!=='shz'){
        const sk=u.skin||'win',rad=u.fixedDesk?0:(sk==='kb'?30:sk==='lib'?64:28);
        rr(c,2,2,W-4,H-4,rad);
        if(sk==='lib'){c.fillStyle='rgba(0,0,0,0)'}
        else if(sk==='kb'){const g=c.createLinearGradient(0,0,0,H);g.addColorStop(0,'rgba(36,42,50,.6)');g.addColorStop(1,'rgba(12,15,19,.7)');c.fillStyle=g}
        else if(u.fixedDesk)c.fillStyle='#000';
        else{const g=c.createLinearGradient(0,0,0,H);g.addColorStop(0,'rgba(41,43,48,.975)');g.addColorStop(1,'rgba(33,35,40,.975)');c.fillStyle=g}
        if(sk!=='lib')c.fill();
        if(sk==='win'&&u.chrome){c.save();rr(c,2,2,W-4,H-4,rad);c.clip();c.fillStyle='rgba(0,0,0,.16)';c.fillRect(0,0,W,BAR);c.restore()}
        c.lineWidth=foc?2:1.2;
        c.strokeStyle=sk==='lib'?'rgba(255,255,255,.05)':foc?'rgba(255,255,255,.2)':'rgba(255,255,255,.07)';
        if(sk!=='lib')c.stroke()
      }
      u.btns=[];
      let oy=0;
      const B=(x,y,w,h,l,fn,on,ic,kind,nm,lp)=>{
        const i=u.btns.length;
        u.btns.push({x,y:y+oy,w,h,fn,lp,n:nm||l||ICON_TR[ic]||''});
        const hv=i===u.hov;
        if(hv&&KB.p===m&&KB.i===i){
          c.save();
          rr(c,x-3,y-3,w+6,h+6,Math.min(18,h/2+3));
          c.lineWidth=3;
          c.strokeStyle='#19d3c5';
          c.stroke();
          c.restore()
        }
        if(kind!=='raw'){
          rr(c,x,y,w,h,kind==='pill'?h/2:16);
          c.fillStyle=on?(kind==='ghost'?'rgba(245,246,248,.92)':acc):hv?(ic==='close'?'#ff4d5e':'rgba(255,255,255,.2)'):kind==='ghost'?'rgba(255,255,255,0)':'rgba(255,255,255,.08)';
          c.fill()
        }
        const col=on||hv?'#fff':'#d6e3ff';
        if(ic&&l){
          ICN(c,ic,x+w/2,y+h*.4,Math.min(w,h)*.24,col);
          c.fillStyle=col;
          c.font='15px system-ui';
          c.textAlign='center';
          c.fillText(l,x+w/2,y+h*.88)
        }
        else if(ic)ICN(c,ic,x+w/2,y+h/2,Math.min(w,h)*.27,col);
        else if(l){
          c.fillStyle=col;
          c.font='22px system-ui';
          c.textAlign='center';
          c.fillText(l,x+w/2,y+h/2+8)
        }
        c.textAlign='left';
        const dw=Input.dw;
        if(dw&&dw.o===m&&dw.i===i&&dw.p>0){
          c.save();
          c.lineWidth=4;
          c.lineCap='round';
          c.strokeStyle='#19d3c5';
          if(w>h*1.5){
            c.beginPath();
            c.moveTo(x+10,y+h-6);
            c.lineTo(x+10+(w-20)*dw.p,y+h-6);
            c.stroke()
          }else{
            c.beginPath();
            c.arc(x+w/2,y+h/2,Math.max(10,Math.min(w,h)/2-2),-Math.PI/2,-Math.PI/2+dw.p*Math.PI*2);
            c.stroke()
          }
          c.restore()
        }
        return hv
      };
      if(u.chrome){
        /* Quest 3: başlık üstte ortada, küçült ve kapat sağ üstte */
        const cy=BAR/2+2;
        if(BAR>0){
        c.fillStyle='#eaf1f2';
        c.font='500 19px system-ui,sans-serif';
        c.textAlign='center';
        c.fillText(u.title||'',W/2,cy+7);
        c.textAlign='left';
        qbtn(c,B,W-32,cy,'close',()=>this.close(m),'Kapat');
        qbtn(c,B,W-80,cy,'min',()=>this.minimize(m,true),'Küçült');
        qbtn(c,B,W-128,cy,'expand',()=>this.toggleMax(m),'Büyüt veya eski boyuta döndür',u.max);
        }
        const pr=u.rect,pb=BR.rect;
        c.save();
        c.translate(0,BAR);
        oy=BAR;
        u.render(c,W,H-BAR,B,u);
        c.restore();
        oy=0;
        if(u.rect&&u.rect!==pr)u.rect.y+=BAR;
        if(u.id==='browser'&&BR.rect&&BR.rect!==pb)BR.rect.y+=BAR
      }else u.render(c,W,H,B,u);
      if((u.web||u.id==='browser')&&typeof BF!=='undefined')BF.drawSnapshot(m);
      u.tex.needsUpdate=true;
      if(u.pill)Pill.paint(u.pill);
      Scene.dirty=true
    },
    repaintAll(){
      this.need=true;
      Scene.dirty=true
    },
    size(m,d){
      const u=m.userData;
      if(u.fixedDesk)return;
      u.max=false;
      u.sf=clamp(u.sf+d,.5,1.6);
      this.build(m)
    },
    toggleMax(m){
      const u=m.userData;
      if(u.fixedDesk)return;
      if(u.max){
        u.sf=u.saved;
        u.max=false
      }else{
        u.saved=u.sf;
        u.sf=1.6;
        u.max=true;
        u.ang=0;
        u.y=1.9
      }
      this.build(m);
      if(!u.dock)AppState.save()
    },
    minimize(m,anim){
      const u=m.userData;
      if(u.anim)return;
      u.min=true;
      if(u.id==='win7simu')W7Desk.hide();
      if(this.focused===m)this.focused=null;
      if(anim&&m.visible&&!Settings.v.reduce&&!XR.session&&this.genie(m,1)){
        this.repaintAll();
        if(!u.dock)AppState.save();
        return
      }
      m.visible=false;
      this.repaintAll();
      if(!u.dock)AppState.save()
    },
    /* macOS tarzı "cin" animasyonu: pencere alttan başlayarak dock'taki uygulama ikonuna doğru huni gibi süzülür.
       dir=1 küçült, dir=-1 geri aç. */
    tgt(m){
      const dk=this.panels.find(p=>p.userData.dock);
      if(!dk)return null;
      const d=dk.userData,u=m.userData,pos=DK[u.id]||DK.lib||[d.cv.width/2,d.cv.height/2,d.cv.height*.3];
      const W=d.cv.width,H=d.cv.height,th=Math.PI-d.span/2+(1-pos[0]/W)*d.span,v=new THREE.Vector3(d.R*Math.sin(th),((1-pos[1]/H)-.5)*d.h,d.R*Math.cos(th));
      dk.updateMatrixWorld(true);
      dk.localToWorld(v);
      m.updateMatrixWorld(true);
      m.worldToLocal(v);
      let a=Math.atan2(v.x,v.z);
      a+=2*Math.PI*Math.round((Math.PI-a)/(2*Math.PI));
      return{th:a,R:Math.hypot(v.x,v.z),y:v.y,ws:clamp((pos[2]/W*d.span)/u.span,.015,.5)}
    },
    genie(m,dir){
      const u=m.userData,T=this.tgt(m);
      // Performance mode: ordinary app monitors stay as lightweight flat 2D planes.
      // Skip the cylinder-based genie deformation for flat panels; normal visibility,
      // focus, positioning, rotation, touch, drag and hand-tracking remain unchanged.
      if(u.cflat)return false;
      if(!T)return false;
      m.geometry.dispose();
      m.geometry=new THREE.CylinderGeometry(u.R,u.R,u.h,Math.max(8,Math.ceil(u.span*18)),28,true,Math.PI-u.span/2,u.span);
      u.base0=Float32Array.from(m.geometry.attributes.position.array);
      u.tg=T;
      m.frustumCulled=false;
      u.anim={t0:performance.now(),dur:dir>0?640:560,dir,p:dir>0?0:1};
      this.deform(m,u.anim.p);
      Scene.dirty=true;
      return true
    },
    deform(m,p){
      const u=m.userData,pos=m.geometry.attributes.position,b=u.base0,T=u.tg,h=u.h,q=clamp((p-.12)/.88,0,1),dl=.6,PI=Math.PI;
      for(let i=0;i<pos.count;i++){
        const x=b[i*3],y=b[i*3+1],z=b[i*3+2];
        let th=Math.atan2(x,z);
        if(th<=0)th+=2*PI;
        const R=Math.hypot(x,z),v=(y+h/2)/h,e=clamp(q*(1+dl)-v*dl,0,1),ee=e*e*(3-2*e);
        const ws=1-(1-T.ws)*ee,tn=PI+(th-PI)*ws+(T.th-PI)*ee,Rn=R+(T.R-R)*ee,yn=y+(T.y-y)*ee;
        pos.setXYZ(i,Rn*Math.sin(tn),yn,Rn*Math.cos(tn))
      }
      pos.needsUpdate=true
    },
    tick(now){
      for(const m of this.panels.slice()){
        const u=m.userData,a=u.anim;
        if(u.pill)u.pill.visible=!a;
        if(!a)continue;
        const bad=!u.base0||m.geometry.attributes.position.array.length!==u.base0.length,t=clamp((now-a.t0)/a.dur,0,1);
        if(bad||t>=1){
          u.anim=null;
          u.base0=null;
          m.frustumCulled=true;
          if(a.dir>0){
            m.visible=false;
            if(this.focused===m)this.focused=null
          }
          this.build(m);
          this.repaintAll();
          Scene.dirty=true;
          continue
        }
        const pe=.5-.5*Math.cos(Math.PI*t),p=a.dir>0?pe:1-pe;
        a.p=p;
        this.deform(m,p);
        Scene.dirty=true
      }
    },
    close(m){
      m.userData.anim=null;
      Pill.dispose(m);
      m.visible=false;
      if(m.userData.fr){
        m.userData.fr.remove();
        m.userData.fr=null
      }
      if(this.focused===m)this.focused=null;
      if(m.userData.id==='win7simu')W7Desk.hide();
      // Native WebView overlays outlive their canvas panel unless explicitly released.
      // Tear down the app view (and, for Win7, its nested browser views) on close.
      if(m.userData.web)BF.release(m);
      this.panels.splice(this.panels.indexOf(m),1);
      m.geometry.dispose();
      m.userData.tex.dispose();
      m.material.dispose();
      Scene.scene.remove(m);
      this.repaintAll();
      if(!m.userData.dock)AppState.save()
    },
    focus(m){
      if(this.focused!==m){
        this.focused=m;
        this.repaintAll()
      }
    },
    spawn(id){
      // Windows 7 Simu is a normal in-world NEXUS panel, not a separate fullscreen Activity.
      if(id==='win7pc')id='win7simu';
      if(id==='cinema'){Cinema.toggle();return}
      if(id==='saber'){Game.toggle();return}
      if(id==='planets'){Planets.toggle();return}
      if(id==='gorilla'){if(window.Gorilla)Gorilla.toggle();else Diag.toast('Goril oyunu yüklenemedi','var(--err)');return}
      if(typeof id==='string'&&id.startsWith('and:')){AND.launch(id.slice(4));return}
      let m=this.panels.find(p=>p.userData.id===id);
      if(m){
        if(id==='win7simu'&&m.visible&&!m.userData.min&&!(m.userData.anim&&m.userData.anim.dir>0)){this.close(m);return}
        const wasMin=!m.visible&&!!m.userData.min,u=m.userData;
        if(u.anim&&u.anim.dir>0){
          u.anim=null;
          u.base0=null;
          m.frustumCulled=true;
          this.build(m)
        }
        m.visible=true;
        u.min=false;
        if(u.id==='win7simu')W7Desk.show();
        this.focus(m);
        this.paint(m);
        if(wasMin&&!u.dock&&!Settings.v.reduce&&!XR.session)this.genie(m,-1);
        if(!m.userData.dock)AppState.save();
        return
      }
      const d=id.startsWith('app:')?WebApps.def(id):id.startsWith('shz:')?SHZ.def(id):APPS[id]();
      if(!d)return;
      m=this.create(d);
      if(m.userData.id==='win7simu')W7Desk.show();
      this.layout(Settings.v.layout,true);
      this.focus(m);
      if(!m.userData.dock)AppState.save()
    },
    isOpen(id){
      if(id==='win7pc')id='win7simu';
      if(id==='cinema')return Cinema.on;
      if(id==='saber')return Game.on;
      if(id==='planets')return Planets.on;
      if(id==='gorilla')return !!(window.Gorilla&&Gorilla.on);
      if(typeof id==='string'&&id.startsWith('and:'))return false;
      const m=this.panels.find(p=>p.userData.id===id);
      return !!m&&m.visible&&!(m.userData.anim&&m.userData.anim.dir>0)
    },
    layout(i,quiet){
      Settings.v.layout=i;
      Settings.save();
      const L=this.panels.filter(p=>p.visible&&!p.userData.dock&&!p.userData.kbd&&!p.userData.fixedDesk),n=L.length;
      L.forEach((m,k)=>{
        const u=m.userData;
        u.y=1.9;
        u.sf=i===3?.7:u.max?1.6:(i===0?.72:1);
        if(i===0)u.ang=0;
        else if(i===1)u.ang=k*6.2832/n;
        else if(i===2){
          u.ang=(k-(n-1)/2)*1.4;
          u.y=1.9+((k%3)-1)*.45
        }else{
          u.ang=(k-(n-1)/2)*.81;
          u.y=1.5
        }
        this.build(m)
      });
      if(i===0){
        /* Quest 3 dizilimi: aynı yarıçapta, yan yana, küçük boşlukla; alt kenar dock'un hemen üstünde */
        const gap=.04,hw=L.map(m=>Math.atan(m.userData.span/2)),tot=hw.reduce((s,h)=>s+2*h,0)+gap*Math.max(0,n-1);
        let a0=-tot/2;
        L.forEach((m,k)=>{
          const u=m.userData;
          u.ang=-(a0+hw[k]);
          a0+=2*hw[k]+gap;
          u.y=clamp(.5+u.h/2,1.05,2.4);
          this.place(m)
        })
      }
      if(!quiet)Diag.toast('Düzen: '+this.names[i]);
      this.repaintAll()
    }
  };
