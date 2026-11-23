'use strict';
  /* ---------- Klavye erişilebilirliği: Tab / Shift+Tab / Enter / Boşluk ---------- */
  const KB={
    p:null,
    i:-1,
    step(d){
      const L=WM.panels.filter(p=>p.visible);
      if(!L.length)return;
      let pi=L.indexOf(this.p),i=this.i+d;
      if(pi<0){
        pi=d>0?0:L.length-1;
        i=d>0?0:L[pi].userData.btns.length-1
      }
      else{
        const n=L[pi].userData.btns.length;
        if(i<0||i>=n){
          pi=(pi+d+L.length)%L.length;
          i=d>0?0:L[pi].userData.btns.length-1
        }
      }
      this.clear();
      this.p=L[pi];
      this.i=i;
      const u=this.p.userData;
      u.hov=i;
      WM.focus(this.p);
      WM.paint(this.p);
      const b=u.btns[i];
      Diag.say((u.title||'Dock')+': '+((b&&b.n)||'düğme'))
    },
    clear(){
      const o=this.p;
      if(o){
        o.userData.hov=-1;
        if(Pill.ok(o))WM.paint(o)
      }
    },
    press(alt){
      const o=this.p;
      if(!o||!o.visible)return false;
      const b=o.userData.btns[this.i];
      if(!b)return false;
      (alt&&b.lp?b.lp:b.fn)(o);
      return true
    }
  };
  /* ---------- Simülatör içi klavye: eller tuşun üstünde ~1 sn bekleyince basar (parmak birleştirme basmaz) ---------- */
  const KBD={
    m:null,open:false,text:'',title:'',cb:null,shift:false,dw:null,pt:0,dock:null,wired:false,live_:null,liveEnd:null,
    sym:false,
    rowsL:[
      '1234567890'.split('').map(k=>[k,k,1]).concat([['⌫','back',1.6,'act']]),
      'qwertyuıopğü'.split('').map(k=>[k,k,1]),
      'asdfghjklşi'.split('').map(k=>[k,k,1]),
      [['⇧','shift',1.5,'act']].concat('zxcvbnmöç'.split('').map(k=>[k,k,1]),[['.','.',1],[',',',',1]]),
      [['İptal','cancel',1.4,'act'],['?123','sym',1.4,'act'],['/','/',1],['@','@',1],['Boşluk',' ',3.8],['.com','.com',1.5],['↵','ok',2,'ok']]
    ],
    rowsS:[
      '!@#₺%&*()='.split('').map(k=>[k,k,1]).concat([['⌫','back',1.6,'act']]),
      '~^+-_/\\|<>{}'.split('').map(k=>[k,k,1]),
      ':;"\'?,.[]€$'.split('').map(k=>[k,k,1]),
      [['ABC','sym',1.5,'act']].concat('`´§°²³¿¡¬'.split('').map(k=>[k,k,1]),[['.','.',1],[',',',',1]]),
      [['İptal','cancel',1.4,'act'],['ABC','sym',1.4,'act'],['/','/',1],['@','@',1],['Boşluk',' ',3.8],['.com','.com',1.5],['↵','ok',2,'ok']]
    ],
    get rows(){return this.sym?this.rowsS:this.rowsL},
    ensure(){
      if(this.m)return;
      this.m=WM.create({id:'vkb',title:'Klavye',icon:'globe',kbd:true,skin:'kb',cflat:true,tilt:.73,chrome:false,span:.85,h:.2656,R:.8,y:.88,ang:0,live:true,render:(c,W,H,B)=>this.render(c,W,H,B)});
      this.m.visible=false;
      if(!this.wired){
        this.wired=true;
        addEventListener('keydown',e=>{
          if(!this.open||e.ctrlKey||e.altKey||e.metaKey)return;
          let k=null;
          if(e.key==='Enter')k='ok';
          else if(e.key==='Escape')k='cancel';
          else if(e.key==='Backspace')k='back';
          else if(e.key.length===1)k=e.key;
          else if(this.live_){
            const LK={ArrowUp:19,ArrowDown:20,ArrowLeft:21,ArrowRight:22,Tab:61,Delete:112,PageUp:92,PageDown:93,Home:122,End:123};
            if(LK[e.key]){e.preventDefault();e.stopImmediatePropagation();this.live_('key',LK[e.key]);return}
          }
          if(k===null)return;
          e.preventDefault();
          e.stopImmediatePropagation();
          this.press(k,true)
        },true)
      }
    },
    ask(title,init,cb){
      Launcher.close();
      this.ensure();
      if(this.open)this.close(null);
      this.title=title;
      this.text=init||'';
      this.cb=cb;
      this.shift=false;
      this.sym=false;
      this.dw=null;
      /* Quest 3: klavye dock'un hemen altında, ~80 cm önde, göze doğru eğik durur. */
      const dir=new THREE.Vector3(),eye=new THREE.Vector3();
      Cam.cam.getWorldDirection(dir);
      Cam.cam.getWorldPosition(eye);
      let fx=dir.x,fz=dir.z;const fl=Math.hypot(fx,fz);
      if(fl<.25){fx=-Math.sin(Cam.yaw);fz=-Math.cos(Cam.yaw)}else{fx/=fl;fz/=fl}
      const u=this.m.userData;
      u.ang=Math.atan2(-fx,-fz);
      u.fx=eye.x;u.fz=eye.z;
      u.y=eye.y-.72;
      WM.place(this.m);
      this.dock=WM.panels.find(p=>p.userData.id==='dock')||null;
      this.m.visible=true;
      this.open=true;
      WM.focus(this.m);
      WM.paint(this.m);
      Diag.toast('Aşağı bak: başparmak + işaret parmağını birleştirerek tuşa bas','var(--ok)',3000)
    },
    /* Stage 57: canlı klavye — her tuş hemen sink('text'|'key', değer) ile gider; Enter/Sil de gönderilir, pencere
       açık kalır. 'Kapat' ya da Esc kapatır. sink false dönerse (hedef yok) klavye kendini kapatır. */
    live(title,sink,onClose){
      this.ask(title,'',null);
      this.live_=sink;this.liveEnd=onClose||null
    },
    close(v){
      const cb=this.cb;
      this.cb=null;
      const le=this.liveEnd;
      this.live_=null;this.liveEnd=null;
      if(le){try{le()}catch(e){}}
      this.open=false;
      this.dw=null;
      if(this.m)this.m.visible=false;
      if(this.dock)this.dock.visible=true;
      WM.repaintAll();
      if(cb)cb(v)
    },
    press(v){
      if(this.live_){
        /* canlı mod: tuşlar uygulamaya akar; alandaki yazı yalnızca son yazılanların önizlemesidir */
        if(v==='shift'){this.shift=!this.shift}
        else if(v==='sym'){this.sym=!this.sym;this.shift=false}
        else if(v==='cancel'){this.close(null);return}
        else if(v==='back'){this.text=Array.from(this.text).slice(0,-1).join('');this.live_('key',67)}
        else if(v==='ok'){this.text='';this.live_('key',66)}
        else{
          const ch=this.shift&&v.length===1?v.toLocaleUpperCase('tr'):v;
          this.shift=false;
          this.text=Array.from(this.text+ch).slice(-48).join('');
          this.live_('text',ch)
        }
        if(this.open&&this.m)WM.paint(this.m);
        return
      }
      if(v==='back')this.text=Array.from(this.text).slice(0,-1).join('');
      else if(v==='shift')this.shift=!this.shift;
      else if(v==='sym'){this.sym=!this.sym;this.shift=false}
      else if(v==='cancel'){this.close(null);return}
      else if(v==='ok'){this.close(this.text);return}
      else{
        this.text+=this.shift&&v.length===1?v.toLocaleUpperCase('tr'):v;
        this.shift=false
      }
      if(this.m)WM.paint(this.m)
    },
    dwell(o,bi){
      const now=performance.now();
      if(!this.open||!o||o!==this.m||bi<0){
        if(this.dw){
          this.dw=null;
          if(this.open&&this.m)WM.paint(this.m)
        }
        return
      }
      if(!this.dw||this.dw.b!==bi)this.dw={b:bi,t0:now,p:0};
      const p=Math.min(1,(now-this.dw.t0)/(Settings.v.dwell||1000));
      if(p>=1){
        const b=o.userData.btns[bi];
        this.dw={b:bi,t0:now,p:0};
        if(b)b.fn(o);
        if(this.open)WM.paint(o)
      }else{
        this.dw.p=p;
        if(now-this.pt>50){
          this.pt=now;
          WM.paint(o)
        }
      }
    },
    render(c,W,H,B){
      const ins=Math.max(16,H*.065),gap=Math.max(6,H*.026),fh=H*.14;
      const fx=ins,fy=ins,fw=W-ins*2;
      rr(c,fx,fy,fw,fh,16);
      c.fillStyle='rgba(255,255,255,.07)';
      c.fill();
      c.lineWidth=1;
      c.strokeStyle='rgba(255,255,255,.18)';
      c.stroke();
      c.textAlign='left';
      c.font='500 '+(fh*.26)+'px system-ui,sans-serif';
      c.fillStyle='rgba(205,215,222,.62)';
      c.fillText(this.title,fx+18,fy+fh*.34);
      c.font='500 '+(fh*.42)+'px system-ui,sans-serif';
      let tx=this.text;
      const mw=fw-36;
      while(tx.length>1&&c.measureText(tx+'▏').width>mw)tx=tx.slice(1);
      c.fillStyle='#f4f7f8';
      c.fillText(tx+((Date.now()%1000)<600?'▏':''),fx+18,fy+fh*.84);
      const top=fy+fh+gap,kh=(H-ins-top-gap*4)/5,aw=W-ins*2;
      const unit=Math.min(...this.rows.map(r=>(aw-gap*(r.length-1))/r.reduce((a,k)=>a+k[2],0)));
      this.rows.forEach((row,ri)=>{
        const tw=row.reduce((a,k)=>a+k[2],0)*unit+gap*(row.length-1);
        let x=(W-tw)/2;
        const y=top+ri*(kh+gap);
        row.forEach(k=>{
          const w=k[2]*unit,act=k[3],lab=(this.live_&&k[1]==='cancel')?'Kapat':k[1]==='shift'||act?k[0]:this.shift&&k[0].length===1?k[0].toLocaleUpperCase('tr'):k[0];
          const hv=B(x,y,w,kh,'',()=>this.press(k[1]),false,null,'raw',k[0]);
          const on=k[1]==='shift'&&this.shift,isOk=act==='ok';
          rr(c,x,y,w,kh,14);
          c.fillStyle=isOk?(hv?'rgba(70,138,255,.98)':'rgba(23,105,255,.93)'):on?'rgba(255,255,255,.34)':hv?'rgba(255,255,255,.27)':act?'rgba(255,255,255,.07)':'rgba(255,255,255,.12)';
          c.fill();
          c.lineWidth=1.2;c.strokeStyle=isOk?'rgba(170,205,255,.55)':'rgba(255,255,255,.15)';c.stroke();
          if(hv&&this.dw&&this.dw.p>0){
            c.save();
            rr(c,x,y,w,kh,14);
            c.clip();
            c.fillStyle='rgba(25,211,197,.7)';
            c.fillRect(x,y,w*this.dw.p,kh);
            c.restore()
          }
          c.fillStyle='#f3f6f7';
          c.textAlign='center';
          if(isOk){
            const ax=x+w/2,ay=y+kh/2;
            c.save();c.lineWidth=3.2;c.lineCap='round';c.lineJoin='round';c.strokeStyle='#fff';
            c.beginPath();c.moveTo(ax+14,ay-11);c.lineTo(ax+14,ay+3);c.lineTo(ax-14,ay+3);c.moveTo(ax-6,ay-5);c.lineTo(ax-14,ay+3);c.lineTo(ax-6,ay+11);c.stroke();
            c.restore()
          }else{
            c.font='500 '+(kh*(lab.length>2?.32:.46))+'px system-ui,sans-serif';
            c.fillText(lab,x+w/2,y+kh*(lab.length>2?.62:.66))
          }
          x+=w+gap
        })
      });
      c.textAlign='left'
    }
  };
  /* ---------- VR: ekranı ikiye bölen yan yana stereo görünüm (karton/telefon gözlüğü) ---------- */
  const Stereo={
    on:false,sc:null,fs:false,gyro0:false,mk:null,prevFov:null,
    applyProfile(){
      if(!this.sc)this.sc=new THREE.StereoCamera();
      const v=Settings.v;
      this.sc.eyeSep=clamp(+v.vrEyeSep||.064,.052,.075);
      if(Cam.cam){Cam.cam.fov=clamp(+v.vrFov||75,60,100);Cam.cam.updateProjectionMatrix()}
      Renderer.resize();Scene.dirty=true
    },
    mask(on){
      let c=this.mk;
      if(!on){if(c)c.style.display='none';return}
      if(!c){c=this.mk=document.createElement('canvas');c.style.cssText='position:fixed;inset:0;width:100%;height:100%;z-index:44;pointer-events:none';document.body.appendChild(c);addEventListener('resize',()=>{if(this.on)this.mask(true)})}
      c.style.display='block';
      const W=innerWidth,H=innerHeight,d=Math.min(devicePixelRatio||1,2);c.width=Math.round(W*d);c.height=Math.round(H*d);
      const x=c.getContext('2d');x.setTransform(d,0,0,d,0,0);x.globalCompositeOperation='source-over';x.fillStyle='#000';x.fillRect(0,0,W,H);
      x.globalCompositeOperation='destination-out';x.fillStyle='#000';
      const w=W/2,mt=H*.04,r=Math.min(w,H)*.16;
      try{x.filter='blur(1.2px)'}catch(e){}
      [[w*.02,w*.988],[w+w*.012,W-w*.02]].forEach(a=>{
        const l=a[0],rt=a[1],t=mt,b=H-mt;
        x.beginPath();x.moveTo(l+r,t);x.arcTo(rt,t,rt,b,r);x.arcTo(rt,b,l,b,r);x.arcTo(l,b,l,t,r);x.arcTo(l,t,rt,t,r);x.closePath();x.fill()
      });
      try{x.filter='none'}catch(e){}
      x.globalCompositeOperation='source-over';x.fillStyle='rgba(150,155,165,.55)';x.fillRect(W/2-1,0,2,H)
    },
    async toggle(){
      if(this.on)this.stop();
      else await this.start()
    },
    async start(){
      if(this.on)return;
      if(XR.session)XR.session.end();
      this.on=true;
      this.sc=this.sc||new THREE.StereoCamera();
      this.prevFov=Cam.cam.fov;
      this.applyProfile();
      Cam.cam.focus=2.9;
      document.body.classList.add('stereo');
      this.mask(true);
      Renderer.resize();
      WM.repaintAll();
      Diag.toast('VR: telefonu gözlüğe tak. Çıkmak için VR düğmesine tekrar bas (Esc de çıkar)','var(--ok)',4000);
      this.gyro0=Cam.gyro;
      try{
        if(!Cam.gyro&&!Cam.dead)await Cam.enableGyro()
      }catch(e){}
      try{
        if(!document.fullscreenElement){
          await document.documentElement.requestFullscreen();
          this.fs=true
        }
      }catch(e){}
      try{
        await screen.orientation.lock('landscape')
      }catch(e){}
      try{
        Sys.awake(true)
      }catch(e){}
      Scene.dirty=true;
      NHand.migrate()
    },
    stop(){
      if(!this.on)return;
      this.on=false;
      document.body.classList.remove('stereo');
      this.mask(false);
      Cam.cam.focus=10;
      if(this.prevFov!==null){Cam.cam.fov=this.prevFov;Cam.cam.updateProjectionMatrix();this.prevFov=null;}
      const r=Renderer.r;
      if(r){
        r.setScissorTest(false);
        r.setViewport(0,0,innerWidth,innerHeight)
      }
      Renderer.resize();
      try{
        if(!this.gyro0&&Cam.gyro)Cam.disableGyro()
      }catch(e){}
      try{
        if(this.fs&&document.fullscreenElement)document.exitFullscreen()
      }catch(e){}
      this.fs=false;
      try{
        screen.orientation.unlock()
      }catch(e){}
      try{
        if(!Settings.v.awake)Sys.awake(false)
      }catch(e){}
      WM.repaintAll();
      Scene.dirty=true;
      NHand.migrate()
    },
    render(r,scene,cam){
      const W=innerWidth,H=innerHeight,w2=Math.floor(W/2);
      Cam.rig.updateMatrixWorld(true);
      cam.updateMatrixWorld(true);
      this.sc.update(cam);
      const vy=clamp(+Settings.v.vrOffsetY||0,-.03,.03);
      if(vy){this.sc.cameraL.position.y+=vy;this.sc.cameraR.position.y+=vy;this.sc.cameraL.updateMatrixWorld(true);this.sc.cameraR.updateMatrixWorld(true)}
      r.setScissorTest(true);
      r.setScissor(0,0,W,H);
      r.setViewport(0,0,W,H);
      r.clear();
      r.setScissor(0,0,w2,H);
      r.setViewport(0,0,w2,H);
      r.render(scene,this.sc.cameraL);
      r.setScissor(w2,0,W-w2,H);
      r.setViewport(w2,0,W-w2,H);
      r.render(scene,this.sc.cameraR);
      r.setScissorTest(false);
      r.setViewport(0,0,W,H)
    }
  };
  const Input={
    drag:null,
    hold:null,
    dw:null,
    dwDone:null,
    dwT:0,
    look:false,
    pid:null,
    hp:null,
    xrc:null,
    gazeTarget:null,
    gazeSince:0,
    gazeFired:false,
    gazeDragTarget:null,
    gazeDragSince:0,
    gazeReleaseArmed:false,
    gazeRay(){
      Cam.rig.updateMatrixWorld(true);Cam.cam.updateMatrixWorld(true);
      const origin=new THREE.Vector3();Cam.cam.getWorldPosition(origin);
      const direction=new THREE.Vector3(0,0,-1).applyQuaternion(Cam.cam.getWorldQuaternion(new THREE.Quaternion())).normalize();
      return new THREE.Ray(origin,direction)
    },
    gazeTick(now){
      const ui=$('#gaze-ui'),active=!Hand.on&&!XR.session;
      if(!active){if(ui)ui.style.display='none';document.body.classList.remove('gaze-active');this.gazeTarget=null;this.gazeSince=0;this.gazeFired=false;this.gazeDragTarget=null;this.gazeReleaseArmed=false;return}
      if(ui)ui.style.display='block';document.body.classList.add('gaze-active');
      const ray=this.gazeRay();
      if(this.drag&&this.drag.gaze){this.move(ray);const h=Scene.pick(ray),o=h&&h.object,u=o&&o.userData;
        const header=!!((o===this.drag.o&&u.chrome&&((1-h.uv.y)*u.cv.height)<BAR)||(u.pillOf&&u.pillOf===this.drag.o));
        if(header){if(!this.gazeReleaseArmed){this.gazeReleaseArmed=true;this.gazeDragSince=now}else if(now-this.gazeDragSince>1800){this.drag=null;this.gazeReleaseArmed=false;this.gazeTarget=null;this.gazeFired=false;return}}
        else {this.gazeReleaseArmed=false;this.gazeDragSince=now}
        return
      }
      const h=Scene.pick(ray),o=h&&h.object,u=o&&o.userData;
      let bi=-1,px=0,py=0;
      if(h){px=(1-h.uv.x)*u.cv.width;py=(1-h.uv.y)*u.cv.height;for(let j=u.btns.length-1;j>=0;j--){const b=u.btns[j];if(px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h){bi=j;break}}}
      this.hover(ray,'gaze');
      const key=o?(u.id||'panel')+':'+(bi>=0?bi+':'+((u.btns[bi].x)|0)+','+((u.btns[bi].y)|0):((u.chrome&&py<BAR)||u.pillOf)?'header':'surface'):null;
      const left=$('#gaze-left'),right=$('#gaze-right');
      [left,right].forEach(el=>{if(el){el.classList.toggle('active',!!key);const ring=el.querySelector('.gaze-ring');if(ring)ring.style.transform='rotate('+Math.min(360,((now-this.gazeSince)/1800)*360)+'deg)'}});
      if(!key){this.gazeTarget=null;this.gazeSince=0;this.gazeFired=false;return}
      if(key!==this.gazeTarget){this.gazeTarget=key;this.gazeSince=now;this.gazeFired=false;return}
      if(this.gazeFired)return;
      const isWin7=!!(u&&u.id==='win7simu'&&u.web);
      const wait=isWin7?3000:((u&&((u.chrome&&py<BAR)||u.pillOf)&&bi<0)?1900:Math.max(1000,Math.min(2000,(Settings.v.hdw||1.5)*1000)));
      if(now-this.gazeSince<wait)return;
      this.gazeFired=true;
      if(u&&((u.chrome&&py<BAR)||u.pillOf)&&bi<0){
        const T=u.pillOf||o,tu=T.userData,pnt=rayCyl(ray,tu.R);if(pnt){WM.focus(T);this.drag={o:T,oa:tu.ang-Math.atan2(-pnt.x,-pnt.z),oy:tu.y-pnt.y,gaze:true};this.gazeDragTarget=o;this.gazeReleaseArmed=false;this.gazeDragSince=now}
      }else if(h&&bi>=0){
        // Existing canvas-backed controls are the authoritative action targets.
        const b=u.btns[bi];if(b&&typeof b.fn==='function'){b.fn(o);if(Pill.ok(o))WM.paint(o);if(b.fn.rep){this.gazeFired=false;this.gazeSince=now-Math.max(0,wait-650)}}
      }else if(h&&((u&&u.web)||(u&&u.id==='browser'))){
        // Stereo mode hides native overlays; route panel-local gaze coordinates
        // directly to the backing WebView. Flat mode targets the visible overlay.
        try{
          if(window.AndroidBridge&&NX_T){
            const r=(u.id==='browser'?BR.rect:u.rect);
            if(r&&r.w>0&&r.h>0){
              const id=u.id==='browser'?'nexus-browser':'webapp-'+String(u.id).slice(4);
              const lx=clamp((px-r.x)/r.w,0,1),ly=clamp((py-r.y)/r.h,0,1);
              if(isWin7)AndroidBridge.gazeDoubleTapInView(id,lx,ly,NX_T);
              else AndroidBridge.gazeInteractInView(id,lx,ly,NX_T);
            }
          }
        }catch(e){Diag.log('Gaze WebView interaction failed: '+e)}
      }
    },
    down(ray,src){
      const h=Scene.pick(ray);
      if(!h){
        if(Launcher.open)Launcher.close();if(QS.open)QS.close();
        return false
      }
      const o=h.object,u=o.userData;
      if(Launcher.open&&o!==Launcher.m&&!u.dock)Launcher.close();
      if(QS.open&&o!==QS.m&&!(u.dock&&QS.onCap(h)))QS.close();
      if(!u.handMenu)WM.focus(u.pillOf||o);
      if(u.kbd&&u.id==='vkb'&&src==='hand'){
        const kx=(1-h.uv.x)*u.cv.width,ky=(1-h.uv.y)*u.cv.height;
        const kb=u.btns.slice().reverse().find(b=>kx>=b.x&&kx<=b.x+b.w&&ky>=b.y&&ky<=b.y+b.h);
        KBD.dw=null;
        if(kb){kb.fn(o);if(KBD.open&&WM.panels.includes(o))WM.paint(o)}
        return true
      }
      const px=(1-h.uv.x)*u.cv.width,py=(1-h.uv.y)*u.cv.height;
      if(this.wtBegin(h,o,u,px,py,src))return true;
      if(src==='hand'){
        this.dwellClear();
        const hb=u.btns.slice().reverse().find(b=>b.lp&&px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h);
        if(hb){
          const hd={o,key:(hb.x|0)+','+(hb.y|0),fn:null,lp:hb.lp,fired:false};
          hd.tm=setTimeout(()=>{
            if(this.hold===hd&&!hd.fired){
              hd.fired=true;
              hd.lp(o)
            }
          },1100);
          this.hold=hd;
          return true
        }
        const cb=u.btns.slice().reverse().find(b=>!b.lp&&typeof b.fn==='function'&&px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h);
        if(cb){
          /* Çimdik = tıkla (bırakınca çalışır); aynı düğmede bekleme sayacı ikinci kez tetiklemesin */
          this.dwDone=u.btns.lastIndexOf(cb)+':'+(cb.x|0)+','+(cb.y|0);
          this.hold={o,key:(cb.x|0)+','+(cb.y|0),fn:cb.fn,lp:null,fired:false,tm:0,pc:true};
          return true
        }
        if(u.chrome){
          const p=rayCyl(ray,u.R);
          if(p)this.drag={o,oa:u.ang-Math.atan2(-p.x,-p.z),oy:u.y-p.y}
        }
        if(u.pillOf){const pu=u.pillOf.userData,p=rayCyl(ray,pu.R);if(p)this.drag={o:u.pillOf,oa:pu.ang-Math.atan2(-p.x,-p.z),oy:pu.y-p.y}}
        return true
      }
      for(const b of u.btns.slice().reverse())if(px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h){
        if(b.lp){
          const hd={o,key:(b.x|0)+','+(b.y|0),fn:b.fn,lp:b.lp,fired:false};
          hd.tm=setTimeout(()=>{
            if(this.hold===hd&&!hd.fired){
              hd.fired=true;
              hd.lp(o)
            }
          },src==='hand'?1100:550);
          this.hold=hd;
          return true
        }
        b.fn(o);
        return true
      }
      // Dock: only its bottom grip initiates dragging, leaving app icons clickable.
      if(u.dock&&py>=u.cv.height-28){
        const p=rayCyl(ray,u.R);
        if(p)this.drag={o,oa:u.ang-Math.atan2(-p.x,-p.z),oy:u.y-p.y};
        return true
      }
      if(u.chrome&&py<BAR){
        const p=rayCyl(ray,u.R);
        if(p)this.drag={o,oa:u.ang-Math.atan2(-p.x,-p.z),oy:u.y-p.y}
      }
      if(u.pillOf){const pu=u.pillOf.userData,p=rayCyl(ray,pu.R);if(p)this.drag={o:u.pillOf,oa:pu.ang-Math.atan2(-p.x,-p.z),oy:pu.y-p.y}}
      return true
    },
    /* ---- Web panelleri (Win7 dahil): çimdik = gerçek dokunma akışı (bas / sürükle / bırak) ---- */
    wt:null,
    wtRect(u){if(u.id==='browser')return(BR.show&&!BR.menu&&BR.rect)?BR.rect:null;return u.web&&u.rect?u.rect:null},
    wtBegin(h,o,u,px,py,src){
      if(!window.AndroidBridge||!NX_T||!AndroidBridge.touchView||(!u.web&&u.id!=='browser'))return false;
      const r=this.wtRect(u);
      if(!r||!(r.w>0&&r.h>0)||px<r.x||py<r.y||px>r.x+r.w||py>r.y+r.h)return false;
      if(u.btns.some(b=>px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h))return false;
      const id=BF.webId(u),lx=clamp((px-r.x)/r.w,0,1),ly=clamp((py-r.y)/r.h,0,1);
      this.wt={o,id,r,px,py,lx,ly,moved:false,src,mt:0};
      BF.act();
      try{AndroidBridge.touchView(id,0,lx,ly,NX_T)}catch(e){this.wt=null;return false}
      return true
    },
    dwellClear(skip){
      const d=this.dw;
      this.dw=null;
      if(d&&!skip&&WM.panels.includes(d.o))WM.paint(d.o)
    },
    dwell(o,bi){
      const now=performance.now(),b=o&&bi>=0?o.userData.btns[bi]:null;
      if(!b||o.userData.anim){
        this.dwDone=null;
        this.dwellClear();
        return
      }
      const key=bi+':'+(b.x|0)+','+(b.y|0);
      if(this.dwDone&&this.dwDone!==key)this.dwDone=null;
      if(this.dwDone===key)return;
      if(!this.dw||this.dw.o!==o||this.dw.key!==key){
        this.dwellClear();
        this.dw={o,key,i:bi,t0:now,p:0}
      }
      const d=this.dw,p=Math.min(1,(now-d.t0)/((Settings.v.hdw||2)*1000));
      if(p>=1){
        this.dwDone=key;
        this.dw=null;
        b.fn(o);
        if(Pill.ok(o))WM.paint(o)
      }else{
        d.p=p;
        if(now-(this.dwT||0)>50){
          this.dwT=now;
          WM.paint(o)
        }
      }
    },
    btnKey(ray){
      const h=Scene.pick(ray);
      if(!h)return null;
      const o=h.object,u=o.userData,px=(1-h.uv.x)*u.cv.width,py=(1-h.uv.y)*u.cv.height;
      for(const b of u.btns.slice().reverse())if(px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h)return{o,key:(b.x|0)+','+(b.y|0)};
      return null
    },
    move(ray){
      const wt=this.wt;
      if(wt){
        const h=Scene.pick(ray);
        if(h&&h.object===wt.o){
          const u=wt.o.userData,px=(1-h.uv.x)*u.cv.width,py=(1-h.uv.y)*u.cv.height;
          if(!wt.moved&&Math.hypot(px-wt.px,py-wt.py)>12)wt.moved=true; /* titreme payı: küçük kaymalar tıklamayı bozmasın */
          if(wt.moved){
            const now=performance.now();
            if(now-wt.mt>=16){
              wt.mt=now;wt.lx=clamp((px-wt.r.x)/wt.r.w,0,1);wt.ly=clamp((py-wt.r.y)/wt.r.h,0,1);BF.act();
              try{AndroidBridge.touchView(wt.id,1,wt.lx,wt.ly,NX_T)}catch(e){}
            }
          }
        }
        return
      }
      const hd=this.hold;
      if(hd&&!hd.fired){
        const t=this.btnKey(ray);
        if(!t||t.o!==hd.o||t.key!==hd.key){
          clearTimeout(hd.tm);
          this.hold=null
        }
      }
      const d=this.drag;
      if(!d)return;
      const u=d.o.userData,p=rayCyl(ray,u.R);
      if(!p)return;
      u.ang=Math.atan2(-p.x,-p.z)+d.oa;
      u.y=clamp(p.y+d.oy,.5,3.4);
      WM.place(d.o)
    },
    up(cancel){
      const wt=this.wt;
      if(wt){
        this.wt=null;this.xrc=null;BF.act();
        try{AndroidBridge.touchView(wt.id,cancel?3:2,wt.lx,wt.ly,NX_T)}catch(e){}
        return
      }
      const hd=this.hold;
      this.hold=null;
      if(hd){
        clearTimeout(hd.tm);
        if(!hd.fired&&!cancel&&hd.fn){hd.fn(hd.o);if(hd.pc&&Pill.ok(hd.o))WM.paint(hd.o)}
      }
      this.drag=null;
      this.xrc=null
    },
    hover(ray,src){
      const h=Scene.pick(ray),o=h?h.object:null;
      let bi=-1;
      if(o){
        const u=o.userData,px=(1-h.uv.x)*u.cv.width,py=(1-h.uv.y)*u.cv.height;
        for(let j=u.btns.length-1;j>=0;j--){
          const b=u.btns[j];
          if(px>=b.x&&px<=b.x+b.w&&py>=b.y&&py<=b.y+b.h){
            bi=j;
            break
          }
        }
      }
      if(this.hp&&this.hp!==o&&this.hp.userData.hov!==-1){
        this.hp.userData.hov=-1;
        WM.paint(this.hp)
      }
      if(o&&o.userData.hov!==bi){
        o.userData.hov=bi;
        WM.paint(o)
      }
      this.hp=o;
      if(src==='hand'){
        if(o&&o.userData.id==='vkb')KBD.dwell(o,bi);
        else{
          KBD.dwell(null,-1);
          this.dwell(o,bi)
        }
      }
      {const cs=bi>=0?'pointer':'default',cc=this.cc||(this.cc=$('#c'));if(this.cur!==cs){this.cur=cs;cc.style.cursor=cs}}
    },
    init(){
      const c=$('#c'),ray=e=>{
        let nx=e.clientX/innerWidth;
        if(Stereo.on)nx=(nx*2)%1;
        Scene.rc.setFromCamera(new THREE.Vector2(nx*2-1,-e.clientY/innerHeight*2+1),Cam.cam);
        return Scene.rc.ray
      };
      const keys=this.keys={};
      let lx=0,ly=0;
      c.addEventListener('pointerdown',e=>{
        c.setPointerCapture(e.pointerId);
        this.pid=e.pointerId;
        lx=e.clientX;
        ly=e.clientY;
        this.look=!this.down(ray(e))
        });
      c.addEventListener('pointermove',e=>{
        if(this.pid!==e.pointerId){
          if(e.buttons===0&&e.pointerType==='mouse')this.hover(ray(e));
          return
        }
        const dx=e.clientX-lx,dy=e.clientY-ly;
        lx=e.clientX;
        ly=e.clientY;
        if(this.drag||this.hold||this.wt)this.move(ray(e));
        else if(this.look){
          const k=.004*Settings.v.sens;
          if(Cam.hybridLive())Cam.yaw-=dx*k; /* hibrit: eğim sensörden, yalnız yön dokunmayla */
          else if(!Cam.gyroLive()){
            Cam.yaw-=dx*k;
            Cam.pitch=clamp(Cam.pitch-dy*k*(Settings.v.inv?-1:1),-1.5,1.5)
          }
        }
        });
      const up=e=>{
        if(this.pid===e.pointerId){
          this.pid=null;
          this.look=false;
          this.up(e.type==='pointercancel')
        }
      };
      c.addEventListener('pointerup',up);
      c.addEventListener('pointercancel',up);
      c.addEventListener('wheel',e=>{
        e.preventDefault();
        Cam.zoom+=e.deltaY*.002
        },{passive:false});
      addEventListener('keydown',e=>{
        keys[e.key.toLowerCase()]=true;
        if(e.key==='Escape'){
          if(QS.open)QS.close();
          else if(Launcher.open&&!KBD.open)Launcher.close();
          else if(XR.session)XR.session.end();
          else if(Stereo.on)Stereo.stop()
        }
        });
      addEventListener('keyup',e=>keys[e.key.toLowerCase()]=false);
      addEventListener('keydown',e=>{
        if(!App.entered||e.ctrlKey||e.altKey||e.metaKey)return;
        const t=e.target;
        if(t&&t!==document.body&&t.id!=='c')return;
        if(e.key==='Tab'){
          e.preventDefault();
          KB.step(e.shiftKey?-1:1)
        }else if((e.key==='Enter'||e.key===' ')&&KB.p){
          if(KB.press(e.shiftKey))e.preventDefault()
        }
        });
      $('#wpf').addEventListener('change',e=>{
        const f=e.target.files[0];
        if(!f)return;
        const u=URL.createObjectURL(f);
        Scene.loadWP(u,true);
        setTimeout(()=>URL.revokeObjectURL(u),10000);
        e.target.value=''
        })
    },
    tick(dt){
      const k=this.keys,s=1.6*dt;
      if(k.a||k.arrowleft)Cam.yaw+=s;
      if(k.d||k.arrowright)Cam.yaw-=s;
      if(k.w||k.arrowup)Cam.pitch=Math.min(1.5,Cam.pitch+s);
      if(k.s||k.arrowdown)Cam.pitch=Math.max(-1.5,Cam.pitch-s);
      if(this.drag&&this.xrc)this.move(XR.ray(this.xrc));
      this.gazeTick(performance.now())
    }
  };
  /* ---------- WebXR (kaldırıldı — aşağıdaki nesne artık yalnızca eski çağrı noktalarını (XR.session,
     XR.ray, vb.) kırmamak için duruyor; gerçek bir navigator.xr oturumu hiçbir zaman açılmıyor,
     VR her zaman Stereo/Cardboard modülü üzerinden sağlanıyor) ---------- */
  const XR={
    support:'kontrol ediliyor',
    session:null,
    ctrls:[],
    ok:false,
    ray(c){
      const r=new THREE.Ray();
      r.origin.setFromMatrixPosition(c.matrixWorld);
      r.direction.set(0,0,-1).transformDirection(c.matrixWorld);
      return r
    },
    async check(){
      /* WebXR kaldırıldı: artık navigator.xr hiç sorgulanmıyor, oturum hiç istenmiyor.
         VR her zaman Stereo (Cardboard) modülüyle sağlanıyor. */
      this.support='WebXR devre dışı (Stereo/Cardboard modu kullanılıyor)';
      return false
    },
    async toggle(){
      /* Artık bu yoldan gerçek bir WebXR oturumu açılmıyor; VR düğmesi zaten Stereo.toggle()'ı çağırıyor. */
      Diag.toast('VR, Cardboard/Stereo modunda çalışır','var(--ok)')
    },
    setup(){
      if(this.ctrls.length)return;
      for(let i=0;i<2;i++){
        const c=Renderer.r.xr.getController(i);
        c.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(),new THREE.Vector3(0,0,-5)]),new THREE.LineBasicMaterial({color:0x19d3c5})));
        c.addEventListener('selectstart',()=>{
          Input.look=false;
          Input.down(this.ray(c));
          if(Input.drag)Input.xrc=c
          });
        c.addEventListener('selectend',()=>Input.up());
        Scene.scene.add(c);
        this.ctrls.push(c)
      }
    },
    onEnd(){
      this.session=null;
      Pass.apply();
      Input.up();
      Cam.rig.position.set(0,1.6,0);
      Renderer.resize();
      WM.repaintAll();
      Diag.toast('VR oturumu sona erdi')
    }
  };
