'use strict';
  const BF={
    ids:new Set(),
    virtualSizes:new Map(),
    snapshotCache:new Map(),
    snapshotBusy:new Set(),
    snapshotTimes:new Map(),
    snapshotSeq:0,
    browserId:'nexus-browser',
    /* Stage 27 GPU tarayıcı: kareler yerelden itilir (poll yok); gpu = GPU yoluna alınan kimlikler */
    gpu:new Set(),gpuBusy:new Set(),gpuSeq:new Map(),
    syncGpu(){try{if(window.AndroidBridge&&NX_T&&AndroidBridge.setGpu)AndroidBridge.setGpu(Settings.v.gpu!==false,NX_T)}catch(e){}},
    markGpu(id){try{if(AndroidBridge.isGpu&&AndroidBridge.isGpu(id,NX_T))this.gpu.add(id)}catch(e){}},
    gpuOff(id,gone){this.gpu.delete(id);this.gpuBusy.delete(id);this.gpuSeq.delete(id);this.virtualSizes.delete(id);if(gone){this.ids.delete(id);this.snapshotCache.delete(id);Diag.toast('Tarayıcı yeniden başlatılıyor','var(--warn)')}},
    gpuPanel(id){if(id===this.browserId)return WM.panels.find(p=>p.userData.id==='browser');return WM.panels.find(p=>p.userData.web&&this.webId(p.userData)===id)||null},
    gpuPaint(m){const u=m.userData;if(!m.visible||!WM.panels.includes(m))return;if(u.id==='browser'&&(!BR.show||BR.menu||!BR.rect))return;this.drawSnapshot(m);u.tex.needsUpdate=true;Scene.dirty=true},
    gpuFrame(id,seq){
      seq=+seq;if(!this.gpu.has(id)||!(seq>0))return;
      if(this.gpuBusy.has(id)){this.gpuSeq.set(id,seq);return}
      this.gpuBusy.add(id);
      const self=this,img=new Image();
      const fin=()=>{self.gpuBusy.delete(id);const n=self.gpuSeq.get(id);if(n&&n!==seq){self.gpuSeq.delete(id);self.gpuFrame(id,n)}};
      img.src='/_snap/'+NX_T+'/'+id+'?n='+seq;
      (img.decode?img.decode():new Promise((a,b)=>{img.onload=a;img.onerror=b})).then(()=>{
        if(self.gpu.has(id)){self.snapshotCache.set(id,{img,r:null});const m=self.gpuPanel(id);if(m)self.gpuPaint(m)}
        fin()
      },fin)
    },
    /* GPU sayfasının görüntü boyutu: panel içeriğinin ~1.25 katı (64 piksele yuvarlı), CSS genişliği tablet düzeni (PC sürümünde 1280) */
    gpuSize(id,r){
      if(!window.AndroidBridge||!NX_T||!AndroidBridge.gpuSize||!r||r.w<2||r.h<2)return;
      let w,h,cw;
      if(r.h>r.w*1.15){/* Stage 60: dik pencere (telefon düzeni, ~400 dp genişlik) */
        w=clamp(Math.round(r.w/64)*64,384,720);h=clamp(Math.round(w*r.h/r.w),640,1200);cw=Math.round(clamp(w/1.6,360,480))
      }else{
        w=clamp(Math.round(r.w/64)*64,640,1408);h=clamp(Math.round(w*r.h/r.w),360,900);cw=Settings.v.desk?1280:Math.round(clamp(w/1.5,520,1100))
      }
      const key=w+'x'+h+'@'+cw;if(this.virtualSizes.get(id)===key)return;this.virtualSizes.set(id,key);
      try{AndroidBridge.gpuSize(id,w,h,cw,NX_T)}catch(e){this.virtualSizes.delete(id)}
    },
    scrollId(id,direction){try{if(window.AndroidBridge&&NX_T&&id)AndroidBridge.scrollViewBy(id,direction,NX_T)}catch(e){Diag.log('WebView scroll failed: '+e)}},
    load(u){
      if(!window.AndroidBridge||!NX_T)return;
      const id=this.browserId;
      BR.native();
      try{if(!this.ids.has(id)){this.syncGpu();if(AndroidBridge.create(id,u,NX_T)){this.ids.add(id);this.markGpu(id)}}else AndroidBridge.navigate(id,u,NX_T)}catch(e){Diag.toast('Android WebView açılamadı','var(--err)')}
    },
    hideId(id){if(!this.gpu.has(id))this.snapshotCache.delete(id);this.virtualSizes.delete(id);this.snapshotTimes.delete(id);try{if(window.AndroidBridge&&NX_T)AndroidBridge.setRect2(id,0,0,2,2,false,0,0,0,0,NX_T)}catch(e){}},
    conceal(id){try{if(window.AndroidBridge&&NX_T)AndroidBridge.setRect2(id,0,0,2,2,false,0,0,0,0,NX_T)}catch(e){}},
    release(m){const id='webapp-'+m.userData.id.slice(4);try{if(window.AndroidBridge&&NX_T)AndroidBridge.destroy(id,NX_T)}catch(e){}this.ids.delete(id);this.snapshotCache.delete(id);this.virtualSizes.delete(id);this.snapshotBusy.delete(id);this.snapshotTimes.delete(id)},
    hide(){this.hideId(this.browserId);WM.panels.forEach(m=>{if(m.userData.web)this.hideId('webapp-'+m.userData.id.slice(4))})},
    get(m){const u=m.userData,a=u.web,id='webapp-'+u.id.slice(4);if(!window.AndroidBridge||!NX_T)return null;if(!this.ids.has(id)){
      /* Stage 56: Android uygulaması (Shizuku sanal ekranı). Kareler GPU yoluyla (__nxGpu) gelir; başarısızsa bir kez denenir ve normal ekrana düşülür. */
      /* Stage 57: servis bağlanırken ya da anlık hatada 4 kereye kadar (0,8 sn arayla) dener; sonra normal ekrana düşer. */
      if(a.type==='shz'){
        const now=Date.now();
        if(a.failed||(a.next&&now<a.next))return null;
        /* Stage 64: kullanıcı sınırı (Ayarlar → Grafik → Android pencere sayısı, 0 = sınırsız). */
        const lim=Settings.v.gwin|0;
        if(lim>0&&WM.panels.filter(p=>p!==m&&p.userData.web&&p.userData.web.type==='shz'&&this.ids.has('webapp-'+p.userData.id.slice(4))).length>=lim){a.failed=true;setTimeout(()=>SHZ.fail(m,'Android pencere sınırına ulaşıldı ('+lim+'), normal ekranda açılıyor. Sınır: Ayarlar → Grafik'),0);return null}
        let ok=false;try{const po=SHZ.isPort(a.pkg);ok=!!AndroidBridge.shzOpen(id,a.pkg,po?640:1280,po?1138:720,po?400:853,NX_T)}catch(e){}
        if(ok){this.ids.add(id);this.gpu.add(id);return id}
        a.n=(a.n||0)+1;
        const st=SHZ.refresh();
        if(a.n<4&&(st.s===3||st.s===4)){a.next=now+800;return null}
        a.failed=true;setTimeout(()=>SHZ.fail(m),0);return null
      }
      let ok=false;try{this.syncGpu();ok=a.type==='html'?AndroidBridge.createHtml(id,a.html||'',NX_T):AndroidBridge.create(id,a.url,NX_T)}catch(e){}if(ok){this.ids.add(id);this.markGpu(id)}else return null}return id},
    place(id,m,r){
      if(!id||!window.AndroidBridge||!NX_T)return false;
      const u=m.userData,W=u.cv.width,H=u.cv.height;m.updateMatrixWorld(true);Cam.cam.updateMatrixWorld(true);const P=[];
      for(const q of [[r.x,r.y],[r.x+r.w,r.y],[r.x+r.w,r.y+r.h],[r.x,r.y+r.h]]){let v;if(u.cflat){const xx=((q[0]/W)-.5)*u.R*u.span;v=new THREE.Vector3(xx,(.5-q[1]/H)*u.h,-u.R+curveZ(u,xx))}else{const th=Math.PI-u.span/2+(1-q[0]/W)*u.span;v=new THREE.Vector3(u.R*Math.sin(th),((1-q[1]/H)-.5)*u.h,u.R*Math.cos(th))}m.localToWorld(v);v.project(Cam.cam);if(v.z>1||v.z<-1){this.hideId(id);return false}P.push([(v.x+1)/2*innerWidth,(1-v.y)/2*innerHeight])}
      const xs=P.map(p=>p[0]),ys=P.map(p=>p[1]),dpr=window.devicePixelRatio||1;
      const left=Math.max(0,Math.floor(Math.min(...xs))),top=Math.max(0,Math.floor(Math.min(...ys))),right=Math.min(innerWidth,Math.ceil(Math.max(...xs))),bottom=Math.min(innerHeight,Math.ceil(Math.max(...ys)));
      if(right-left<3||bottom-top<3){this.hideId(id);return false}
      try{AndroidBridge.setRect2(id,Math.round(left*dpr),Math.round(top*dpr),Math.round((right-left)*dpr),Math.round((bottom-top)*dpr),true,0,0,Math.round((right-left)*dpr),Math.round((bottom-top)*dpr),NX_T);return true}catch(e){return false}
    },
    /* ---- Win7 canlı doku ---- */
    lastAct:0,idleMs:300,
    act(){this.lastAct=performance.now()},
    webId(u){return u.id==='browser'?this.browserId:'webapp-'+String(u.id).slice(4)},
    /* CSS genişliği (arayüz boyutu) ve netlik çarpanı: WebView fiziksel boyutu = CSS genişliği × netlik */
    w7size(){const cw=clamp(+Settings.v.w7w||1280,800,2240),q=clamp(+Settings.v.w7q||1.25,1,2),w=Math.round(cw*q),h=Math.round(w*W7Desk.H/W7Desk.W);return{cw,w,h}},
    w7Apply(){const id=this.webId({id:'win7simu'});this.virtualSizes.delete(id);this.snapshotTimes.delete(id);this.idleMs=300;Scene.dirty=true},
    virtualizeExact(id,w,h,cw){
      const key=w+'x'+h+'@'+cw;if(this.virtualSizes.get(id)===key)return;this.virtualSizes.set(id,key);
      try{AndroidBridge.prepareGazeView(id,w,h,NX_T);if(AndroidBridge.setViewScale)AndroidBridge.setViewScale(id,cw,NX_T)}catch(e){this.virtualSizes.delete(id)}
    },
    /* Win7 monitörü GPU yolundayken boyutlandırma: anlık görüntü API'si yerine doğrudan
       GPU sayfası boyutu (VirtualDisplay) ayarlanır; CSS genişliği yine Win7'nin kendi
       "arayüz boyutu" ayarından (w7size) gelir, tarayıcının kendi tahmini genişliğinden değil. */
    gpuSizeExact(id,w,h,cw){
      if(!window.AndroidBridge||!NX_T||!AndroidBridge.gpuSize)return;
      const key='g'+w+'x'+h+'@'+cw;if(this.virtualSizes.get(id)===key)return;this.virtualSizes.set(id,key);
      try{AndroidBridge.gpuSize(id,w,h,cw,NX_T)}catch(e){this.virtualSizes.delete(id)}
    },
    live(m,img){
      const u=m.userData;
      if(!u.liveTex){u.liveTex=true;u.tex.generateMipmaps=true;u.tex.minFilter=THREE.LinearMipmapLinearFilter;u.tex.anisotropy=4}
      u.liveImg=img;u.tex.image=img;u.tex.needsUpdate=true;Scene.dirty=true
    },
    virtualize(id,r){if(!id||!r||!window.AndroidBridge||!NX_T)return;if(this.gpu.has(id))return this.gpuSize(id,r);const dpr=Math.min(window.devicePixelRatio||1,1.0),w=Math.max(3,Math.min(960,Math.round(r.w*dpr))),h=Math.max(3,Math.min(600,Math.round(r.h*dpr))),key=w+'x'+h;if(this.virtualSizes.get(id)===key)return;this.virtualSizes.set(id,key);try{AndroidBridge.prepareGazeView(id,w,h,NX_T)}catch(e){this.virtualSizes.delete(id)}},
    requestSnapshot(id,m,r,now){
      if(!id||!r||r.w<2||r.h<2||!window.AndroidBridge||!NX_T||this.snapshotBusy.has(id))return;
      if(this.gpu.has(id))return;
      const u=m.userData,live=u.id==='win7simu'&&!!AndroidBridge.snap2;
      /* Etkileşim sırasında sık ve hafif, boştayken seyrek (ve değişmeyen karede yük bindirmeyen) yenileme */
      const act=now-this.lastAct<1200,gap=live?(act?60:this.idleMs):400;
      if(now-(this.snapshotTimes.get(id)||0)<gap)return;
      this.snapshotTimes.set(id,now);this.snapshotBusy.add(id);
      const cb='__nxSnap'+(++this.snapshotSeq),self=this;
      if(live){
        const z=this.w7size();
        window[cb]=function(n){
          delete window[cb];n=+n;
          if(n>0){
            self.idleMs=300;
            const img=new Image(),fail=()=>self.snapshotBusy.delete(id),done=()=>{self.snapshotBusy.delete(id);if(WM.panels.includes(m))self.live(m,img)};
            img.src='/_snap/'+NX_T+'/'+id+'?n='+n;
            (img.decode?img.decode():new Promise((a,b)=>{img.onload=a;img.onerror=b})).then(done,fail)
          }else{
            self.snapshotBusy.delete(id);
            if(n===0)self.idleMs=Math.min(1500,Math.round(self.idleMs*1.4))
          }
        };
        try{AndroidBridge.snap2(id,cb,act?Math.min(z.w,1280):z.w,act?62:80,NX_T)}catch(e){this.snapshotBusy.delete(id);delete window[cb]}
        return
      }
      window[cb]=function(data){try{if(data){const img=new Image();img.onload=()=>{self.snapshotCache.set(id,{img,r:{x:r.x,y:r.y,w:r.w,h:r.h}});self.snapshotBusy.delete(id);delete window[cb];if(m&&WM.panels.includes(m))WM.paint(m)};img.onerror=()=>{self.snapshotBusy.delete(id);delete window[cb]};img.src=data}else{self.snapshotBusy.delete(id);delete window[cb]}}catch(e){self.snapshotBusy.delete(id);try{delete window[cb]}catch(_){}}};
      try{AndroidBridge.snap(id,cb,NX_T)}catch(e){this.snapshotBusy.delete(id);delete window[cb]}
    },
    drawSnapshot(m){if(m.userData.id==='browser'&&BR.menu)return;const u=m.userData,id=u.id==='browser'?this.browserId:(u.web?'webapp-'+u.id.slice(4):null),snap=id&&this.snapshotCache.get(id);if(!snap)return;const r=u.id==='browser'?BR.rect:u.rect;if(!r||!r.w||!r.h)return;const c=u.cv.getContext('2d');c.save();c.beginPath();c.rect(Math.max(0,r.x),Math.max(0,r.y),Math.min(u.cv.width-r.x,r.w),Math.min(u.cv.height-r.y,r.h));c.clip();c.drawImage(snap.img,r.x,r.y,r.w,r.h);c.restore()},
    update(){
      const now=performance.now(),bm=WM.panels.find(p=>p.userData.id==='browser');
      if(bm&&BR.show&&BR.rect&&bm.visible&&!XR.session){this.virtualize(this.browserId,BR.rect);this.requestSnapshot(this.browserId,bm,BR.rect,now)}else this.hideId(this.browserId);
      WM.panels.forEach(m=>{const u=m.userData;if(!u.web)return;const id=this.get(m),r=u.rect;if(!id||!m.visible||!r||XR.session){if(id)this.hideId(id);return}if(u.id==='win7simu'){const z=this.w7size();if(this.gpu.has(id))this.gpuSizeExact(id,z.w,z.h,z.cw);else this.virtualizeExact(id,z.w,z.h,z.cw)}else this.virtualize(id,r);this.requestSnapshot(id,m,r,now)});
    }
  };
  window.__nxGpu=(id,n)=>{try{BF.gpuFrame(id,n)}catch(e){}};
  window.__nxGpuOff=(id,g)=>{try{BF.gpuOff(id,!!g)}catch(e){}};
  /* Katalog sekmesi: kategori çipleri + 4x2 ızgara, sayfalama, ekle / aç */
  function CATUI(c,W,H,B,u,y0){
    const cats=['Tümü'].concat(CAT_GROUPS),cg=clamp(u.cg||0,0,cats.length-1),acc=ACC[Settings.v.acc];
    const L=cg?CATALOG.filter(x=>x.g===CAT_GROUPS[cg-1]):CATALOG,per=8,np=Math.max(1,Math.ceil(L.length/per)),pg=clamp(u.pg||0,0,np-1);
        if(np>1){
      B(W-120,y0+8,48,48,'',o=>{o.userData.pg=Math.max(0,pg-1)},false,'back','pill','Önceki sayfa');
      B(W-68,y0+8,48,48,'',o=>{o.userData.pg=Math.min(np-1,pg+1)},false,'fwd','pill','Sonraki sayfa');
      txt(c,(pg+1)+' / '+np,W-206,y0+40,18,'#aeb2bb',10)
    }
    c.font='600 17px system-ui,sans-serif';
    let cx=20;const cy=y0+72,ch=42;
    cats.forEach((nm,i)=>{
      const w=Math.ceil(c.measureText(nm).width)+34,on=i===cg;
      const hv=B(cx,cy,w,ch,'',o=>{o.userData.cg=i;o.userData.pg=0},false,null,'raw',nm);
      rr(c,cx,cy,w,ch,ch/2);
      c.fillStyle=on?acc:hv?'rgba(255,255,255,.18)':'rgba(255,255,255,.08)';
      c.fill();
      c.fillStyle='#fff';
      c.font='600 17px system-ui,sans-serif';
      c.textAlign='center';
      c.fillText(nm,cx+w/2,cy+27);
      c.textAlign='left';
      cx+=w+10
    });
    const gy=cy+ch+14,cw=(W-40-3*14)/4,chh=(H-gy-20-12)/2;
    L.slice(pg*per,pg*per+per).forEach((it,k)=>{
      const x=20+(k%4)*(cw+14),y=gy+Math.floor(k/4)*(chh+14),have=!!WebApps.has(it.k);
      const hv=B(x,y,cw,chh,'',()=>WebApps.act(it.k),false,null,'raw',have?it.n+' · aç':it.n+' · ekle');
      rr(c,x,y,cw,chh,16);
      c.fillStyle=hv?'rgba(255,255,255,.14)':'rgba(255,255,255,.06)';
      c.fill();
      c.lineWidth=hv?2:1;
      c.strokeStyle=hv?'rgba(255,255,255,.55)':'rgba(255,255,255,.1)';
      c.stroke();
      const ts=Math.min(56,chh*.42),tx=x+cw/2-ts/2,ty=y+10;
      ATILE(c,it.n,tx,ty,ts,it.c,it.gl,IOSI.keyOf({cat:it.k}));
      c.fillStyle='#fff';
      c.font='600 19px system-ui,sans-serif';
      c.textAlign='center';
      const nm=it.n.length>17?it.n.slice(0,16)+'…':it.n;
      c.fillText(nm,x+cw/2,ty+ts+26);
      c.fillStyle=have?'#9ee7b8':acc;
      c.font='600 15px system-ui,sans-serif';
      c.fillText(have?'Eklendi · Aç':'+ Ekle',x+cw/2,y+chh-12);
      c.textAlign='left'
    })
  }
  /* ---------- App Store: sol menüde bölümler, Öne Çıkan vitrini, liste; «AL» → indir → ilk açılışta sitenin ikonu ---------- */
  const STORE={
    dl:{},t:0,q:'',DLMS:900,
    views:[['feat','Öne Çıkan','compass'],['all','Tümü','grid'],['Medya','Medya','film'],['Google','Google','globe'],['Sohbet','Sohbet','user'],['Üretkenlik','Üretkenlik','layout'],['Tasarım','Tasarım','image'],['Keşif','Keşif','search'],['mine','Yüklenenler','folder']],
    POP:['youtube','spotify','discord','whatsapp','instagram','telegram','github','figma'],
    host(u){try{return new URL(u).hostname.replace(/^(www|m)\./,'')}catch(e){return u}},
    win(){return WM.panels.find(p=>p.userData.id==='store')},
    repaint(){const m=this.win();if(m)WM.paint(m)},
    /* katalog öğesi → ortak model */
    item(it){const a=WebApps.has(it.k);return{k:it.k,n:it.n,g:it.g,c:it.c,gl:it.gl,sub:it.g+' · '+this.host(it.u),app:a,key:null,ico:a&&a.ico}},
    mine(){return WebApps.list.map(a=>{const ci=a.cat&&CATK[a.cat];return{k:a.cat||null,n:a.name,g:ci?ci.g:(a.type==='html'?'HTML dosyası':'Web adresi'),c:a.col,gl:a.gl,sub:(ci?ci.g+' · ':'')+(a.type==='url'?this.host(a.url):'HTML dosyası'),app:a,key:IOSI.keyOf(a),ico:a.ico}})},
    list(v){
      if(v==='mine')return this.mine();
      if(v==='q'){const q=this.q.toLocaleLowerCase('tr');return CATALOG.filter(x=>(x.n+' '+x.g+' '+x.u).toLocaleLowerCase('tr').includes(q)).map(x=>this.item(x))}
      return(v==='all'?CATALOG:CATALOG.filter(x=>x.g===v)).map(x=>this.item(x))
    },
    byKey(k){return this.item(CATK[k])},
    /* indirme: kısa ilerleme çubuğu, sonra kurulum */
    get(k){
      if(!CATK[k]||this.dl[k]!=null||WebApps.has(k))return;
      this.dl[k]=performance.now();
      this.tick()
    },
    tick(){
      if(this.t)return;
      const step=()=>{
        const now=performance.now();let any=false;
        Object.keys(this.dl).forEach(k=>{
          if(now-this.dl[k]>=this.DLMS){delete this.dl[k];WebApps.addCat(k,true)}else any=true
        });
        this.repaint();
        this.t=any?setTimeout(step,70):0
      };
      this.t=setTimeout(step,70)
    },
    search(){
      if(XR.session){Diag.toast('VR içinde metin girişi yok','var(--warn)');return}
      KBD.ask('Uygulama ara',this.q||'',v=>{
        const q=(v||'').trim(),m=this.win();
        if(!m)return;
        this.q=q;
        m.userData.sv=q?'q':'feat';m.userData.pg=0;
        WM.paint(m)
      })
    },
    cut(t,n){t=String(t);return t.length>n?t.slice(0,n-1)+'…':t},
    /* piksel genişliğine göre kısalt (geçerli c.font ile) */
    fit(c,t,mw){t=String(t);if(c.measureText(t).width<=mw)return t;while(t.length>1&&c.measureText(t+'…').width>mw)t=t.slice(0,-1);return t+'…'},
    tile(c,it,x,y,s){ATILE(c,it.n,x,y,s,it.c,it.gl,it.key,it.ico)},
    /* AL / AÇ / ilerleme düğmesi */
    btn(c,B,x,y,w,h,it,acc){
      const dl=it.k&&this.dl[it.k]!=null;
      c.textAlign='center';c.font='700 '+Math.round(h*.44)+'px system-ui,sans-serif';
      if(dl){
        const p=Math.min(1,(performance.now()-this.dl[it.k])/this.DLMS);
        B(x,y,w,h,'',()=>{},false,null,'raw','İndiriliyor: '+it.n);
        rr(c,x,y,w,h,h/2);c.fillStyle='rgba(255,255,255,.14)';c.fill();
        c.save();rr(c,x,y,w,h,h/2);c.clip();c.fillStyle=acc;c.fillRect(x,y,w*p,h);c.restore();
        c.fillStyle='#fff';c.fillText(Math.round(p*100)+'%',x+w/2,y+h*.68);c.textAlign='left';
        return
      }
      const have=!!it.app,hv=B(x,y,w,h,'',()=>{if(have)WebApps.open(it.app.id);else if(it.k)STORE.get(it.k)},false,null,'raw',(have?'Aç: ':'Al: ')+it.n);
      rr(c,x,y,w,h,h/2);
      c.fillStyle=have?(hv?'rgba(255,255,255,.3)':'rgba(255,255,255,.16)'):(hv?'#5aa6ff':acc);c.fill();
      c.fillStyle='#fff';c.fillText(have?'AÇ':'AL',x+w/2,y+h*.68);c.textAlign='left'
    },
    render(c,W,H,B,u){
      const acc=ACC[Settings.v.acc],sv=u.sv||'feat',y0=TB+10,SW=204,x0=SW+36,cw=W-x0-16;
      c.textAlign='left';
      /* ---- sol menü ---- */
      ATILE(c,'App Store',16,y0,46,['#20c4ff','#0a48ec'],'A','appstore');
      c.fillStyle='#fff';c.font='700 26px system-ui,sans-serif';c.fillText('App Store',72,y0+33);
      const sh=B(16,y0+60,SW,40,'',()=>STORE.search(),false,null,'raw','Uygulama ara');
      rr(c,16,y0+60,SW,40,20);c.fillStyle=sh?'rgba(255,255,255,.2)':'rgba(255,255,255,.09)';c.fill();
      ICN(c,'search',16+24,y0+80,9,'#aeb2bb');
      c.fillStyle='#aeb2bb';c.font='18px system-ui,sans-serif';c.fillText(this.q?this.cut(this.q,14):'Ara',16+44,y0+86);
      if(this.q)B(16+SW-38,y0+64,32,32,'',()=>{STORE.q='';u.sv='feat';u.pg=0},false,'close','pill','Aramayı temizle');
      const ny=y0+116,nh=Math.min(46,(H-ny-12)/this.views.length-4);
      this.views.forEach((v,i)=>{
        const y=ny+i*(nh+4),on=sv===v[0],n=v[0]==='mine'?WebApps.list.length:(v[0]==='feat'?0:this.list(v[0]).length);
        const hv=B(16,y,SW,nh,'',()=>{u.sv=v[0];u.pg=0},false,null,'raw',v[1]);
        rr(c,16,y,SW,nh,14);c.fillStyle=on?acc:hv?'rgba(255,255,255,.14)':'rgba(255,255,255,0)';c.fill();
        ICN(c,v[2],16+26,y+nh/2,Math.min(11,nh*.26),on?'#fff':'#c9d4e6');
        c.fillStyle=on?'#fff':'#e6ebee';c.font='600 18px system-ui,sans-serif';c.fillText(v[1],16+48,y+nh/2+6);
        if(n){c.fillStyle=on?'rgba(255,255,255,.85)':'#8a93a3';c.font='600 16px system-ui,sans-serif';c.textAlign='right';c.fillText(String(n),16+SW-14,y+nh/2+6);c.textAlign='left'}
      });
      /* ayırıcı */
      c.fillStyle='rgba(255,255,255,.09)';c.fillRect(SW+26,y0,1.5,H-y0-14);
      if(sv==='feat')return this.renderFeat(c,W,H,B,u,x0,cw,y0,acc);
      this.renderList(c,W,H,B,u,x0,cw,y0,acc,sv)
    },
    renderFeat(c,W,H,B,u,x0,cw,y0,acc){
      c.fillStyle='#fff';c.font='700 32px system-ui,sans-serif';c.fillText('Öne Çıkan',x0,y0+34);
      c.fillStyle='#aeb2bb';c.font='17px system-ui,sans-serif';c.fillText(CATALOG.length+' web uygulaması · ilk açılışta sitenin kendi ikonu uygulama ikonu olur',x0,y0+60);
      const hy=y0+76,hh=Math.min(170,H*.25),day=Math.floor(Date.now()/864e5),hi=this.item(CATALOG[day%CATALOG.length]);
      const g=c.createLinearGradient(x0,hy,x0+cw,hy+hh),col=Array.isArray(hi.c)?hi.c:['#59b4ff','#2f5bff'];
      g.addColorStop(0,col[0]);g.addColorStop(1,col[1]);
      rr(c,x0,hy,cw,hh,24);c.fillStyle=g;c.fill();
      c.save();rr(c,x0,hy,cw,hh,24);c.clip();
      const gl=c.createRadialGradient(x0+cw*.2,hy,0,x0+cw*.2,hy,cw*.8);gl.addColorStop(0,'rgba(255,255,255,.3)');gl.addColorStop(1,'rgba(255,255,255,0)');
      c.fillStyle=gl;c.fillRect(x0,hy,cw,hh);c.restore();
      const ts=Math.min(104,hh-40);
      this.tile(c,hi,x0+24,hy+(hh-ts)/2,ts);
      c.fillStyle='rgba(255,255,255,.85)';c.font='700 14px system-ui,sans-serif';c.fillText('BUGÜNÜN UYGULAMASI',x0+24+ts+22,hy+hh/2-ts*.36);
      c.fillStyle='#fff';c.font='700 32px system-ui,sans-serif';c.fillText(this.cut(hi.n,22),x0+24+ts+22,hy+hh/2+4);
      c.fillStyle='rgba(255,255,255,.85)';c.font='17px system-ui,sans-serif';c.fillText(hi.sub,x0+24+ts+22,hy+hh/2+32);
      this.btn(c,B,x0+cw-24-110,hy+hh-24-42,110,42,hi,'rgba(0,0,0,.35)');
      const rows=[['Popüler',this.POP.map(k=>this.byKey(k))],['Yeni eklenenler',CATALOG.slice(-4).reverse().map(x=>this.item(x))]];
      let y=hy+hh+14;
      const rh=(H-12-y-2*34)/2,per=4,gap=12,cwd=(cw-(per-1)*gap)/per;
      rows.forEach((r,ri)=>{
        c.fillStyle='#fff';c.font='700 24px system-ui,sans-serif';c.fillText(r[0],x0,y+24);
        if(ri===0){
          const page=u.pg||0;
          B(x0+cw-104,y-2,48,34,'',o=>{o.userData.pg=0},false,'back','pill','Önceki');
          B(x0+cw-52,y-2,48,34,'',o=>{o.userData.pg=1},false,'fwd','pill','Sonraki');
          r[1]=r[1].slice(page*4,page*4+4)
        }
        const cy=y+34;
        r[1].forEach((it,k)=>{
          const x=x0+k*(cwd+gap);
          rr(c,x,cy,cwd,rh,18);c.fillStyle='rgba(255,255,255,.06)';c.fill();
          c.lineWidth=1;c.strokeStyle='rgba(255,255,255,.09)';c.stroke();
          const t=Math.min(64,rh*.4);
          this.tile(c,it,x+cwd/2-t/2,cy+10,t);
          c.textAlign='center';c.fillStyle='#fff';c.font='600 18px system-ui,sans-serif';c.fillText(this.cut(it.n,15),x+cwd/2,cy+10+t+22);
          c.fillStyle='#8a93a3';c.font='14px system-ui,sans-serif';c.fillText(it.g,x+cwd/2,cy+10+t+41);c.textAlign='left';
          const bh=Math.min(34,rh-(10+t+52)-6);
          if(bh>=24)this.btn(c,B,x+cwd/2-45,cy+rh-bh-8,90,bh,it,acc)
        })
        y+=34+rh
      })
    },
    renderList(c,W,H,B,u,x0,cw,y0,acc,sv){
      const L=this.list(sv),vi=this.views.find(v=>v[0]===sv),title=sv==='q'?'“'+this.cut(this.q,18)+'”':(vi?vi[1]:'Tümü');
      c.fillStyle='#fff';c.font='700 32px system-ui,sans-serif';c.fillText(title,x0,y0+34);
      c.fillStyle='#aeb2bb';c.font='17px system-ui,sans-serif';
      c.fillText(sv==='mine'?WebApps.list.length+' uygulama yüklü':(sv==='q'?L.length+' sonuç':L.length+' uygulama'),x0,y0+60);
      const cols=2,per=10,np=Math.max(1,Math.ceil(L.length/per)),pg=clamp(u.pg||0,0,np-1);
      if(np>1){
        B(x0+cw-104,y0+8,48,40,'',o=>{o.userData.pg=Math.max(0,pg-1)},false,'back','pill','Önceki sayfa');
        B(x0+cw-52,y0+8,48,40,'',o=>{o.userData.pg=Math.min(np-1,pg+1)},false,'fwd','pill','Sonraki sayfa');
        c.fillStyle='#aeb2bb';c.font='16px system-ui,sans-serif';c.textAlign='right';c.fillText((pg+1)+' / '+np,x0+cw-114,y0+34);c.textAlign='left'
      }
      const ly=y0+76;
      if(!L.length){
        card(c,x0,ly,cw,H-ly-14);
        txt(c,sv==='mine'?'Henüz uygulama yüklemedin.\nSol menüden bir bölüme geç ve «AL» düğmesine dokun.':'Sonuç yok. Başka bir kelime dene.',x0+30,ly+70,22,'#aeb2bb',52);
        return
      }
      const gap=12,rw=(cw-gap)/cols,rows=Math.ceil(per/cols),rh=(H-ly-14-(rows-1)*gap)/rows;
      L.slice(pg*per,pg*per+per).forEach((it,k)=>{
        const x=x0+(k%cols)*(rw+gap),y=ly+Math.floor(k/cols)*(rh+gap);
        rr(c,x,y,rw,rh,18);c.fillStyle='rgba(255,255,255,.06)';c.fill();
        c.lineWidth=1;c.strokeStyle='rgba(255,255,255,.09)';c.stroke();
        const ts=Math.min(64,rh-24),bw=82;
        this.tile(c,it,x+14,y+(rh-ts)/2,ts);
        const tx=x+14+ts+14,mw=rw-(tx-x)-bw-14-10;
        c.fillStyle='#fff';c.font='600 20px system-ui,sans-serif';c.fillText(this.fit(c,it.n,mw),tx,y+rh/2-4);
        c.fillStyle='#8a93a3';c.font='14px system-ui,sans-serif';c.fillText(this.fit(c,it.sub,mw),tx,y+rh/2+19);
        const bh=Math.min(38,rh-16);
        if(sv==='mine'&&it.app){
          this.btn(c,B,x+rw-bw-14,y+8,bw,Math.min(36,rh/2-10),it,acc);
          B(x+rw-bw-14,y+rh-8-Math.min(36,rh/2-10),bw,Math.min(36,rh/2-10),'Sil',()=>WebApps.remove(it.app.id),false,null,'pill','Sil: '+it.n)
        }else this.btn(c,B,x+rw-bw-14,y+(rh-bh)/2,bw,bh,it,acc)
      })
    },
    def(){return{id:'store',icon:'grid',title:'App Store',span:1.2,h:2.6,render(c,W,H,B,u){STORE.render(c,W,H,B,u)}}}
  };
