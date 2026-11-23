'use strict';
  const SYS=[['browser','Web','globe'],['settings','Ayarlar','gear'],['perf','FPS','chart'],['device','Cihaz','device'],['scene','Sahne','cube'],['help','Yardım','help'],['clock','Saat','pulse'],['calc','Hesap','grid'],['notes','Notlar','folder'],['tasks','Görevler','layout'],['diag','Tanı','pulse'],['lib','Uygulamalarım','grid'],['store','App Store','grid'],['cinema','Sinema','film'],['saber','Kılıç','saber'],['planets','Gezegenler','globe'],['gorilla','Goril','gorilla'],['win7pc','Windows 7 Simu','device']];
  const AND={list:[],by:{},im:{},t:0,
    init(){try{if(window.AndroidBridge){JSON.parse(AndroidBridge.getApps(NX_T)).forEach(x=>{if(x&&x.p&&!this.by[x.p]){this.by[x.p]=x;this.list.push(x)}});this.list.sort((a,b)=>a.n.localeCompare(b.n,'tr'))}}catch(e){}},
    icon(p){let i=this.im[p];if(!i){i=this.im[p]=new Image();i.onload=()=>this.dirty();i.src='/_icon/'+NX_T+'/'+encodeURIComponent(p)}return i},
    dirty(){clearTimeout(this.t);this.t=setTimeout(()=>WM.panels.forEach(m=>['dock','launcher'].includes(m.userData.id)&&WM.paint(m)),90)},
    launch(p){if(SHZ.tryOpen(p))return;this.real(p)},
    real(p){let ok=false;try{ok=AndroidBridge.launch(NX_T,p)}catch(e){}if(!ok)Diag.toast('Uygulama açılamadı','var(--warn)')}
  };
  AND.init();
  /* Stage 56 — Shizuku: Android uygulamasını VR penceresindeki sanal ekranda aç (görüntü: GPU yolu, girdi: touchView/gazeInteractInView/scrollViewBy) */
  const SHZ={
    st:{s:0,i:false},apps:new Map(),want:null,hint:0,
    refresh(){try{if(window.AndroidBridge&&AndroidBridge.shzStatus)this.st=JSON.parse(AndroidBridge.shzStatus(NX_T))}catch(e){}return this.st},
    on(){return Settings.v.shz!==false&&!!(window.AndroidBridge&&AndroidBridge.shzStatus&&AndroidBridge.shzOpen)},
    slug(p){return String(p).replace(/[^A-Za-z0-9_]/g,'-').slice(0,60)},
    /* true: istek işlendi (pencere açıldı ya da izin bekleniyor); false: çağıran normal ekranda açsın */
    tryOpen(p){
      if(!this.on())return false;
      const st=this.refresh();
      if(st.s===4){
        let can=false;try{can=!!AndroidBridge.shzCanOpen(p,NX_T)}catch(e){}
        if(!can)return false;
        const k=this.slug(p);this.apps.set(k,p);WM.spawn('shz:'+k);return true
      }
      if(st.s===1||st.s===3){this.want={p,t:Date.now()};try{AndroidBridge.shzRequest(NX_T)}catch(e){}Diag.toast(st.s===1?'Shizuku izni isteniyor: izin ver, uygulama kendiliğinden açılır':'Shizuku bağlanıyor, uygulama birazdan açılır','var(--warn)',3200);return true}
      /* Stage 69: Shizuku bağlı değil (çalışmıyor / izin reddedildi): uygulamayı normal ekranda AÇMA, sadece uyarı göster */
      Diag.toast(st.s===2?'Bu uygulamayı pencerede açmak istiyorsanız Shizuku ile bağlantısını kurun (Shizuku uygulamasından Nex VR\'ye izin verin).':'Bu uygulamayı pencerede açmak istiyorsanız Shizuku ile bağlantısını kurun.','var(--warn)',5000);
      return true
    },
    onState(s){
      this.st=s;
      /* Bağlantı durumu noktası güncellensin; servis kopunca açık klavye kapanmasın ama uyarı verilsin */
      try{WM.panels.forEach(p=>{if(p.userData.web&&p.userData.web.type==='shz')WM.paint(p)})}catch(e){}
      if(s.s!==4&&this.kbId){Diag.toast('Shizuku bağlantısı koptu, yeniden bağlanıyor…','var(--warn)',2600)}
      const w=this.want;
      if(w){
        if(Date.now()-w.t>30000||s.s===0||s.s===2)this.want=null;
        else if(s.s===4){this.want=null;this.tryOpen(w.p)}
      }
    },
    /* Stage 60: yönelim (yatay/dik) paket başına hatırlanır; dik modda dar ve uzun pencere (telefon düzeni). */
    ori:new Map(),
    isPort(pkg){return this.ori.get(pkg)==='port'},
    geom(port){return port?{span:.30,h:1.795,cvW:640}:{span:1.1,h:2.23,cvW:1024}},
    rotate(m){
      const u=m&&m.userData;if(!u||!u.web)return;
      const pkg=u.web.pkg,port=!this.isPort(pkg),g=this.geom(port);
      this.ori.set(pkg,port?'port':'land');
      u.cvW=g.cvW;u.base={span:g.span,h:g.h};u.sf=1;u.max=false;
      /* Yeni rect gelene kadar eski sanal ekran boyutu atılsın ki gpuSize yeniden hesaplansın */
      try{const id=BF.webId(u);if(id)BF.virtualSizes.delete(id)}catch(e){}
      WM.build(m);Diag.toast(port?'Dik mod':'Yatay mod','var(--ok,#3ddc84)',1400)
    },
    def(id){
      const pkg=this.apps.get(id.slice(4));if(!pkg)return null;
      const A=AND.by[pkg],name=A?A.n:pkg,port=this.isPort(pkg),g=this.geom(port);
      return{id,icon:'app',title:name,span:g.span,h:g.h,cvW:g.cvW,skin:'shz',chrome:false,web:{type:'shz',pkg,name},
        /* Pencere çubuğundaki Klavye düğmesi (Pill.kbd) bunu çağırır; this = panelin userData'sı */
        kbdFn(){SHZ.openKb(this)},
        render(c,W,H,B,u){
          /* Stage 67: web app pencereleri gibi — üstte ayrı bir çubuk/kapsül yok, uygulama
             alanı pencereyi tamamen kaplar. Döndürme/kaydırma/geri/gerçek-ekran artık pencere
             içinde küçük yüzen ikonlar; taşıma ve kapatma/küçültme/klavye alttaki pil'de. */
          const live=SHZ.st.s===4,pt=SHZ.isPort(pkg);
          const cx0=4,cy0=4,cw0=W-8,ch0=H-8;
          rr(c,cx0,cy0,cw0,ch0,16);c.fillStyle='#000';c.fill();
          c.lineWidth=1.2;c.strokeStyle='rgba(255,255,255,.10)';c.stroke();
          u.rect={x:cx0+2,y:cy0+2,w:cw0-4,h:ch0-4};
          /* Shizuku bağlantı noktası, sol üstte küçük */
          c.beginPath();c.arc(cx0+17,cy0+17,5,0,6.3);c.fillStyle=live?'#3ddc84':'#ffb020';c.fill();
          if(!live){c.font='500 12px system-ui';c.fillStyle='#ffcf70';c.textAlign='left';c.fillText('Shizuku bağlanıyor…',cx0+29,cy0+21)}
          /* Sağ üstte küçük yüzen ikon düğmeleri (bir çubuk değil, ayrı yuvarlak ikonlar) */
          const bw=36,by=cy0+7;let x=cx0+cw0-7-bw;
          const put=(fn,ic,nm)=>{B(x,by,bw,bw,'',fn,false,ic,'ghost',nm);x-=bw+6};
          put(m=>SHZ.toReal(m),'ext','Pencereyi kapat, uygulamayı gerçek ekranda aç');
          /* Stage 71: Dik/Yatay ve yukarı/aşağı kaydır düğmeleri alttaki pile (Pill.paint) taşındı */
          put(()=>SHZ.key(u),'back','Geri tuşu')
        }}
    },
    key(u){try{AndroidBridge.shzKey(BF.webId(u),4,NX_T)}catch(e){}},
    /* Stage 57 — klavye: tuşlar canlı olarak uygulamaya gider (KBD.live). kind: 'text' | 'key' */
    kbId:null,
    openKb(u){
      const id=BF.webId(u);
      if(!id||!window.AndroidBridge||!AndroidBridge.shzText){Diag.toast('Bu sürümde klavye yok','var(--warn)',2200);return}
      if(SHZ.st.s!==4&&SHZ.refresh().s!==4){Diag.toast('Shizuku bağlı değil, klavye şimdi çalışmaz','var(--warn)',2600);return}
      const nm=(u.web&&u.web.name)||'uygulama';
      KBD.live('Yazılan: '+nm+' (önce yazı alanına dokun)',(kind,v)=>this.send(id,kind,v),()=>{this.kbId=null});
      this.kbId=id /* live() içindeki ask() eski klavyeyi kapatırken kbId'yi sıfırlar: bu yüzden SONRA atanır */
    },
    send(id,kind,v){
      let r=-1;
      try{r=kind==='key'?(AndroidBridge.shzKey(id,v,NX_T)?1:-1):AndroidBridge.shzText(id,v,NX_T)}catch(e){}
      if(r<0){
        /* pencere kapanmış ya da servis yok */
        if(KBD.open&&this.kbId===id){KBD.close(null);Diag.toast('Uygulama penceresi kapalı, klavye kapatıldı','var(--warn)',2400)}
        return false
      }
      return true
    },
    /* Pencere kapanınca uygulama durdurulur (sanal ekranla kaybolmasın diye); gerçek ekranda açmadan önce biraz beklenir */
    toReal(m){const pkg=m&&m.userData&&m.userData.web&&m.userData.web.pkg;if(!pkg)return;WM.close(m);setTimeout(()=>AND.real(pkg),1300)},
    fail(m,msg){const pkg=m&&m.userData&&m.userData.web&&m.userData.web.pkg;if(!pkg||!WM.panels.includes(m))return;WM.close(m);Diag.toast(msg||'VR penceresinde açılamadı, normal ekranda açılıyor','var(--warn)',3200);setTimeout(()=>AND.real(pkg),600)},
    /* Java'dan gelen sabit neden sözcüğü → kullanıcı mesajı */
    why(w){return({front:'Uygulama başka ekranda açıktı, VR penceresine alınamadı: normal ekranda açılıyor',noframe:'Uygulama sanal ekranda görüntü vermedi: normal ekranda açılıyor',service:'Shizuku bağlantısı kurulamadı: normal ekranda açılıyor',error:'Uygulama sanal ekranda başlatılamadı: normal ekranda açılıyor'})[w]||null}
  };
  window.__nxShzState=s=>{try{SHZ.onState(s)}catch(e){}};
  window.__nxShzLaunched=(id,ok,why)=>{if(ok)return;try{const m=WM.panels.find(p=>p.userData.web&&p.userData.web.type==='shz'&&BF.webId(p.userData)===id);if(m)SHZ.fail(m,SHZ.why(why))}catch(e){}};
  const MAXPIN=40;
  function WCOL(name){
    let h=0;
    for(const ch of name)h=(h*31+ch.charCodeAt(0))>>>0;
    return AC[h%AC.length]
  }
  function appInfo(id){
    if(typeof id!=='string')return null;
    if(id.startsWith('app:')){
      const a=WebApps.list.find(x=>x.id===id.slice(4));
      return a?{id,l:a.name,web:true,ik:IOSI.keyOf(a),img:a.ico,col:Array.isArray(a.col)?a.col:WCOL(a.name),lab:a.gl||(a.name.trim()[0]||'?').toUpperCase()}:null
    }
    if(id.startsWith('and:')){const a=AND.by[id.slice(4)];return a?{id,l:a.n,pkg:a.p,lab:(a.n.trim()[0]||'?').toUpperCase(),col:WCOL(a.n)}:null}
    const x=SYS.find(q=>q[0]===id);
    return x?{id,l:x[1],ic:x[2],ik:IOSI.SYSK[id],lab:x[0]==='win7pc'?'7':undefined,col:x[0]==='win7pc'?'#2678d8':undefined}:null
  }
  const Pins={
    get(){
      const v=Array.isArray(Settings.v.pins)?Settings.v.pins:DEF.pins;
      return v.filter((id,i,a)=>a.indexOf(id)===i&&appInfo(id)).slice(0,MAXPIN)
    },
    has(id){
      return this.get().includes(id)
    },
    fit(){const d=WM.panels.find(p=>p.userData.dock);if(!d)return;const u=d.userData,sp=clamp(1.3*dockPx(this.get().length+1)/1024,1.3,4.2);if(Math.abs(u.base.span-sp)>.005){u.base.span=sp;WM.build(d)}},
    toggle(id){
      const a=appInfo(id),L=this.get(),i=L.indexOf(id);
      if(!a)return;
      if(i>=0){
        L.splice(i,1);
        Diag.toast('Dock’tan kaldırıldı: '+a.l,null,2200)
      }else{
        if(L.length>=MAXPIN){
          Diag.toast('Dock dolu (en fazla '+MAXPIN+' uygulama)','var(--warn)');
          return
        }
        L.push(id);
        Diag.toast('Dock’a sabitlendi: '+a.l,'var(--ok)',2200)
      }
      Settings.v.pins=L;
      Settings.save();
      this.fit();
      Diag.say(i>=0?a.l+' dock’tan kaldırıldı':a.l+' dock’a sabitlendi');
      WM.panels.forEach(p=>['dock','launcher'].includes(p.userData.id)&&WM.paint(p))
    }
  };
  const Launcher={
    m:null,open:false,pg:0,tab:0,flt:0,srt:0,q:'',big:false,
    rec(){try{return JSON.parse(localStorage.getItem('nexus.recent')||'[]')}catch(e){return[]}},
    note(id){try{const r=this.rec().filter(x=>x!==id);r.unshift(id);localStorage.setItem('nexus.recent',JSON.stringify(r.slice(0,60)))}catch(e){}},
    ensure(){
      if(this.m)return;
      this.m=WM.create({id:'launcher',title:'Library',icon:'grid',kbd:true,skin:'lib',cflat:true,curve:true,chrome:false,span:1.1,h:1.9,R:2.6,y:1.4,ang:0,live:false,render:(c,W,H,B)=>this.render(c,W,H,B)});
      this.m.visible=false
    },
    toggle(){if(this.open)this.close();else this.show()},
    pos(){
      const d=WM.panels.find(p=>p.userData.dock),u=this.m.userData;
      if(d){u.ang=d.userData.ang;const du=d.userData,top=Math.atan2(1.6-(du.y+du.h*(du.gs||1)*.5),du.R);u.y=clamp(1.6-u.R*Math.tan(top)+u.h/2+.05,1.0,2.6)}
      else u.y=1.4;
      WM.place(this.m)
    },
    show(keep){
      this.ensure();
      if(QS.open)QS.close();
      if(!keep){this.q='';this.pg=0}
      this.pos();this.open=true;this.m.visible=true;WM.focus(this.m);WM.paint(this.m);
      WM.panels.forEach(p=>p.userData.dock&&WM.paint(p));Diag.say('Library açıldı')
    },
    close(){
      if(!this.open)return;this.open=false;if(this.m)this.m.visible=false;
      if(WM.focused===this.m)WM.focused=null;WM.repaintAll();WM.panels.forEach(p=>p.userData.dock&&WM.paint(p))
    },
    items(){
      let all=SYS.map(x=>x[0]).concat(WebApps.list.map(a=>'app:'+a.id),AND.list.map(a=>'and:'+a.p));
      if(this.tab===1)all=all.filter(id=>id.startsWith('app:'));
      else if(this.flt===1)all=all.filter(id=>!id.startsWith('app:')&&!id.startsWith('and:'));
      else if(this.flt===2)all=all.filter(id=>id.startsWith('app:'));
      else if(this.flt===3)all=all.filter(id=>id.startsWith('and:'));
      const q=this.q.toLocaleLowerCase('tr');
      all=all.filter(id=>{const a=appInfo(id);return a&&(!q||a.l.toLocaleLowerCase('tr').includes(q))});
      if(this.srt===1)all.sort((x,y)=>appInfo(x).l.localeCompare(appInfo(y).l,'tr'));
      else{const r=this.rec(),ix=id=>{const i=r.indexOf(id);return i<0?9999:i};all=all.map((id,i)=>[id,i]).sort((x,y)=>ix(x[0])-ix(y[0])||x[1]-y[1]).map(x=>x[0])}
      return all
    },
    render(c,W,H,B){
      /* Stage 41: Quest "Library" görünümü: ortada başlık + arama, solda sade menü, 5 sütun kare ikon, sağda Filtre/Sırala */
      const acc=ACC[Settings.v.acc],cols=5,SB=212,gx=SB+30,ts=88,gapx=Math.max(14,Math.floor((W-gx-190-cols*ts)/(cols-1))),cw=ts+gapx,cell=ts+52,top=150;
      const all=this.items(),rows=Math.ceil(all.length/cols),vis=Math.max(1,Math.floor((H-top-8)/cell)),maxr=Math.max(0,rows-vis);
      this.pg=clamp(this.pg,0,maxr);
      const rep=()=>{if(this.m)WM.paint(this.m)};
      c.save();c.shadowColor='rgba(20,16,40,.4)';c.shadowBlur=8;c.shadowOffsetY=1;
      /* başlık + arama */
      c.fillStyle='rgba(244,242,250,.92)';c.font='400 25px system-ui,sans-serif';c.textAlign='center';c.fillText('Library',W/2,54);c.textAlign='left';
      const sw=220,sx=W/2-sw/2,sy=74;
      const shv=B(sx,sy,sw,40,'',()=>KBD.ask('Ara',this.q,v=>{if(v!==null){this.q=v.trim();this.pg=0}this.show(true)}),false,null,'raw','Ara');
      rr(c,sx,sy,sw,40,20);c.fillStyle=shv?'rgba(255,255,255,.15)':'rgba(255,255,255,0)';c.fill();
      ICN(c,'search',sx+30,sy+20,8,'#e9e7f0');
      c.fillStyle=this.q?'#f3f1f8':'rgba(233,231,240,.72)';c.font='500 16px system-ui,sans-serif';
      c.fillText(this.q?(this.q.length>16?this.q.slice(0,15)+'…':this.q):'Ara',sx+52,sy+26);
      /* sol menü */
      const nav=[
        ['grid','Tümü',()=>{this.tab=0;this.pg=0;rep()},this.tab===0],
        ['globe','Dünyalar',()=>{this.tab=1;this.pg=0;rep()},this.tab===1],
        ['plus','Katalog',()=>{this.close();WM.spawn('lib');const w=WM.panels.find(p=>p.userData.id==='lib');if(w){w.userData.tab='cat';w.userData.pg=0;w.userData.cg=0;WM.paint(w)}},false]
      ];
      nav.forEach((n,i)=>{
        const y=top+i*52,w=SB-36,hv=B(24,y,w,42,'',n[2],n[3],null,'raw',n[1]);
        if(n[3]||hv){rr(c,24,y,w,42,21);c.fillStyle=n[3]?'#e9e8ee':'rgba(255,255,255,.1)';c.fill()}
        const fg=n[3]?'#1d1c24':'rgba(238,236,244,.92)';
        ICN(c,n[0],48,y+21,9,fg);
        c.fillStyle=fg;c.font='500 16px system-ui,sans-serif';c.textAlign='left';c.fillText(n[1],70,y+27)
      });
      [['folder','HTML yükle',()=>{this.close();WebApps.pick()}],['plus','Adres ekle',()=>{this.close();WebApps.ask()}]].forEach((n,i)=>{
        const y=H-112+i*48,w=SB-36,hv=B(24,y,w,40,'',n[2],false,null,'raw',n[1]);
        if(hv){rr(c,24,y,w,40,20);c.fillStyle='rgba(255,255,255,.1)';c.fill()}
        ICN(c,n[0],48,y+20,8,'rgba(222,220,232,.8)');c.fillStyle='rgba(222,220,232,.8)';c.font='500 15px system-ui,sans-serif';c.fillText(n[1],70,y+25)
      });
      /* sağ: Filtre / Sırala */
      const fl=(y,lab,fn)=>{
        const x=W-182,hv=B(x,y,164,38,'',fn,false,null,'raw',lab);
        if(hv){rr(c,x,y,164,38,19);c.fillStyle='rgba(255,255,255,.1)';c.fill()}
        c.fillStyle='#ebe9f2';c.font='500 15px system-ui,sans-serif';c.textAlign='left';c.fillText(lab,x+14,y+25);
        ICN(c,'chev',x+148,y+19,6,'#ebe9f2')
      };
      fl(top+2,'Filtre: '+['Tümü','Sistem','Web','Android'][this.tab?2:this.flt],()=>{if(this.tab)return;this.flt=(this.flt+1)%4;this.pg=0;rep()});
      fl(top+48,'Sırala: '+['Son','A–Z'][this.srt],()=>{this.srt=1-this.srt;this.pg=0;rep()});
      /* ızgara: kare ikon + altında ad */
      c.save();rr(c,gx-14,top-10,cols*cw+4,H-top+8,18);c.clip();
      const first=this.pg*cols,rad=ts*.27;
      all.slice(first,first+(vis+1)*cols).forEach((id,i)=>{
        const a=appInfo(id);if(!a)return;
        const col=i%cols,row=Math.floor(i/cols),x=gx+col*cw,y=top+row*cell;
        const hv=B(x,y,ts,ts,'',()=>{this.note(id);this.close();WM.spawn(id)},false,null,'raw',a.l,()=>Pins.toggle(id));
        c.save();rr(c,x,y,ts,ts,rad);c.clip();
        if(a.pkg){
          const gr=c.createLinearGradient(x,y,x+ts,y+ts);gr.addColorStop(0,'#2e323a');gr.addColorStop(1,'#16181c');c.fillStyle=gr;c.fillRect(x,y,ts,ts);
          const im=AND.icon(a.pkg);
          if(im.complete&&im.naturalWidth)c.drawImage(im,x,y,ts,ts);
          else{c.fillStyle='#fff';c.font='700 '+Math.round(ts*.42)+'px system-ui';c.textAlign='center';c.fillText(a.lab||'?',x+ts/2,y+ts/2+ts*.15)}
        }else{
          IOSI.tile(c,{k:a.ik,col:qcol(a.id,a.col,a.ic),lab:a.lab,ic:a.ic,id:a.id,img:a.img},x,y,ts,ts)
        }
        if(hv){c.fillStyle='rgba(255,255,255,.12)';c.fillRect(x,y,ts,ts)}
        c.restore();
        if(hv){rr(c,x-3,y-3,ts+6,ts+6,rad+3);c.lineWidth=2.5;c.strokeStyle='rgba(255,255,255,.9)';c.stroke()}
        c.fillStyle='#efedf5';c.font='500 14px system-ui,sans-serif';c.textAlign='center';
        c.fillText(a.l.length>16?a.l.slice(0,15)+'…':a.l,x+ts/2,y+ts+24);c.textAlign='left';
        if(Pins.has(id)){c.beginPath();c.arc(x+ts-10,y+10,9,0,6.3);c.fillStyle=acc;c.fill();ICN(c,'pin',x+ts-10,y+10,4.5,'#fff')}
      });
      if(!all.length){c.fillStyle='rgba(230,228,238,.6)';c.font='500 17px system-ui,sans-serif';c.textAlign='center';c.fillText('Sonuç yok',gx+cols*cw/2,top+80);c.textAlign='left'}
      c.restore();
      if(maxr>0){
        if(this.pg>0)qbtn(c,B,W-120,H-40,'chevup',()=>{this.pg=Math.max(0,this.pg-1);rep()},'Yukarı',false);
        if(this.pg<maxr)qbtn(c,B,W-70,H-40,'chev',()=>{this.pg=Math.min(maxr,this.pg+1);rep()},'Aşağı',false)
      }
      c.textAlign='left';c.restore()
    }
  };
