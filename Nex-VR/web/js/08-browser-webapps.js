'use strict';
  /* ---------- Açık uygulama durumu: kapat/aç arasında hangi pencerelerin açık,
     küçültülmüş veya büyütülmüş olduğunu hatırlar ---------- */
  const AppState={
    save(){
      try{
        const open=WM.panels.filter(p=>p.userData&&!p.userData.dock&&!p.userData.kbd).map(p=>({id:p.userData.id,min:!!p.userData.min,max:!!p.userData.max}));
        localStorage.setItem('nexus.open',JSON.stringify(open))
      }catch(e){}
    },
    load(){
      try{
        const raw=localStorage.getItem('nexus.open');
        return raw==null?null:JSON.parse(raw)
      }catch(e){
        return null
      }
    }
  };
  /* ---------- Tarayıcı ---------- */
  const SITES=[['Vikipedi','https://tr.wikipedia.org','W','#e8eaf0','#111'],['OpenStreetMap','https://www.openstreetmap.org','O','#7ebc6f','#10300a'],['MDN','https://developer.mozilla.org','M','#83d0f2','#06283a'],['three.js','https://threejs.org','3','#f2f2f2','#111'],['Hava durumu','https://wttr.in','H','#3a8fd8','#fff'],['Commons','https://commons.wikimedia.org','C','#3a7bd5','#fff'],['Hacker News','https://news.ycombinator.com','Y','#ff6600','#fff'],['Gutenberg','https://www.gutenberg.org','G','#8a5a3c','#fff']];
  const BR={
    show:false,
    rect:null,
    hist:[],
    i:-1,
    tabs:[{hist:[],i:-1,show:false}],
    t:0,
    view:0,
    pg:0,
    menu:false,
    msg:'Bir siteye dokun: bu tarayıcının içinde açılır.',
    gz(){return !Hand.on&&!XR.session},
    scroll(direction){try{if(window.AndroidBridge&&NX_T)AndroidBridge.scrollViewBy('nexus-browser',direction,NX_T)}catch(e){Diag.log('Browser scroll failed: '+e)}},
    norm(raw){
      raw=(raw||'').trim();
      if(!raw)return null;
      if(/^[a-z][a-z0-9+.-]*:/i.test(raw)&&!/^https?:/i.test(raw))return{err:'Güvenlik nedeniyle yalnızca http/https kabul edilir.'};
      const safe=h=>{
        try{
          const u=new URL(h);
          if(u.protocol==='http:'){u.protocol='https:';if(u.port==='80')u.port=''}
          const n=u.hostname.toLowerCase();
          if(u.username||u.password)return{err:'Kullanıcı adı/şifre içeren adresler engellendi.'};
          if(n==='appassets.androidplatform.net'||n==='localhost'||n.endsWith('.localhost')||n.endsWith('.local')||n.endsWith('.internal')||n==='[::1]'||/^\[(fc|fd|fe80)/i.test(n)||/^(0|10|127)\.|^169\.254\.|^192\.168\.|^172\.(1[6-9]|2\d|3[01])\.|^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(n))return{err:'Yerel ve özel ağ adresleri güvenlik nedeniyle engellendi.'};
          return{url:u.href}
        }catch(e){
          return{err:'Geçersiz adres.'}
        }
      };
      if(/^https?:\/\//i.test(raw))return safe(raw);
      if(/^[^\s]+\.[a-z]{2,}(\/.*)?$/i.test(raw))return safe('https://'+raw);
      return{url:'https://www.google.com/search?q='+encodeURIComponent(raw)}
    },
    /* ---- Sekmeler: etkin sekmenin durumu BR.hist/i/show içinde, diğerleri BR.tabs içinde ---- */
    stash(){
      const k=this.tabs[this.t];
      if(!k)return;
      k.hist=this.hist;
      k.i=this.i;
      k.show=this.show
    },
    enter(k){
      const s=this.tabs[k];
      if(!s)return;
      this.t=k;
      this.hist=s.hist;
      this.i=s.i;
      this.show=false;
      this.menu=false;
      this.view=0;
      this.pg=0;
      BF.hide();
      if(s.show&&s.hist[s.i])this.go(s.hist[s.i],false);
      else this.up()
    },
    sw(k){
      if(k<0||k>=this.tabs.length||k===this.t)return;
      this.stash();
      this.enter(k)
    },
    newTab(){
      if(this.tabs.length>=5){Diag.toast('En fazla 5 sekme','var(--warn)');return}
      this.stash();
      this.tabs.push({hist:[],i:-1,show:false});
      this.enter(this.tabs.length-1)
    },
    closeTab(k){
      if(k<0||k>=this.tabs.length)return;
      if(this.tabs.length<2){
        this.hist=[];
        this.i=-1;
        this.tabs[0]={hist:this.hist,i:-1,show:false};
        this.home();
        return
      }
      this.stash();
      this.tabs.splice(k,1);
      if(k===this.t)this.enter(Math.min(k,this.tabs.length-1));
      else{
        if(k<this.t)this.t--;
        this.up()
      }
    },
    /* ---- Geçmiş ---- */
    addHist(u){
      const h=Settings.v.hist||(Settings.v.hist=[]);
      if(h[0]&&h[0].u===u)return;
      let t=u;
      try{t=new URL(u).hostname.replace(/^www\./,'')}catch(e){}
      h.unshift({u,t,ts:Date.now()});
      if(h.length>100)h.length=100;
      Settings.save()
    },
    clearHist(){
      Settings.v.hist=[];
      Settings.save();
      this.pg=0;
      this.up()
    },
    delHist(u){
      Settings.v.hist=(Settings.v.hist||[]).filter(x=>x.u!==u);
      Settings.save();
      this.up()
    },
    delBm(u){
      const bm=Settings.v.bm||(Settings.v.bm=[]),i=bm.indexOf(u);
      if(i>=0)bm.splice(i,1);
      Settings.save();
      this.up()
    },
    /* ---- Kısayollar (yeni sekme sayfası): varsayılanlar UPSIDEvr'den ---- */
    pins(){
      return Array.isArray(Settings.v.bpins)?Settings.v.bpins.filter(p=>p&&typeof p.u==='string'):[{u:'https://www.youtube.com/',t:'YouTube'},{u:'https://www.wikipedia.org/',t:'Wikipedia'},{u:'https://www.twitch.tv/',t:'Twitch'},{u:'https://github.com/',t:'GitHub'},{u:'https://moonrider.xyz/',t:'Moon Rider'}]
    },
    addPin(){
      KBD.ask('Kısayol adresi (örn. example.com)','',v=>{
        const t=(v||'').trim();
        if(!t||/\s/.test(t))return;
        const r=this.norm(t);
        if(!r||r.err){Diag.toast(r&&r.err?r.err:'Geçersiz adres','var(--warn)');return}
        let h=r.url;try{h=new URL(r.url).hostname.replace(/^www\./,'')}catch(e){}
        const list=this.pins().filter(p=>p.u!==r.url);
        list.push({u:r.url,t:h});
        Settings.v.bpins=list.slice(-12);
        Settings.save();
        this.up()
      })
    },
    delPin(u){
      Settings.v.bpins=this.pins().filter(p=>p.u!==u);
      Settings.save();
      this.up()
    },
    openView(v){
      this.menu=false;
      this.view=v;
      this.pg=0;
      if(this.show)this.home();
      else this.up()
    },
    /* ---- Reklam engelleyici + PC sürümü: yerel WebView'a iletilir (eski APK'da köprü yöntemi yoksa sessizce atlanır) ---- */
    native(){
      try{
        if(window.AndroidBridge&&NX_T){
          AndroidBridge.setDesktopMode('nexus-browser',!!Settings.v.desk,NX_T);
          AndroidBridge.setAdBlock(!!Settings.v.adb,NX_T)
        }
      }catch(e){Diag.log('Browser native flags failed: '+e)}
    },
    setDesk(on){
      Settings.v.desk=!!on;
      Settings.save();
      this.native();
      Diag.toast(on?'PC sürümü açık':'PC sürümü kapalı');
      if(this.show&&this.hist[this.i])this.go(this.hist[this.i],false);
      else this.up()
    },
    setAdb(on){
      Settings.v.adb=!!on;
      Settings.save();
      this.native();
      Diag.toast(on?'Reklam engelleyici açık':'Reklam engelleyici kapalı');
      if(this.show&&this.hist[this.i])this.go(this.hist[this.i],false);
      else this.up()
    },
    go(raw,push=true){
      const r=this.norm(raw);
      if(!r)return;
      if(r.err){
        this.msg=r.err;
        this.up();
        return
      }
      this.menu=false;
      this.view=0;
      if(push){
        this.hist=this.hist.slice(0,this.i+1);
        this.hist.push(r.url);
        this.i=this.hist.length-1;
        this.addHist(r.url)
      }
      if(XR.session){
        this.msg='VR içinde sayfa açılamaz; VR dışında yeni sekmede açılır.'
      }
      else{
        this.show=true;
        BF.load(r.url);
        this.msg='Açılıyor: '+r.url
      }
      this.up()
    },
    external(raw){
      const r=this.norm(raw);
      if(!r||r.err){if(r&&r.err){this.msg=r.err;this.up()}return}
      try{if(window.AndroidBridge&&typeof window.AndroidBridge.openExternal==='function'&&window.AndroidBridge.openExternal(r.url,NX_T)){return}}catch(e){}
      window.open(r.url,'_blank','noopener,noreferrer');
    },
    home(){
      this.show=false;
      this.menu=false;
      BF.hide();
      this.up()
    },
    step(d){
      const n=this.i+d;
      if(n>=0&&n<this.hist.length){
        this.i=n;
        this.go(this.hist[n],false)
      }
    },
    ask(){
      KBD.ask('Adres veya arama terimi',this.hist[this.i]||'',v=>{
        if(v)this.go(v)
      })
    },
    up(){
      WM.panels.forEach(p=>p.userData.id==='browser'&&WM.paint(p))
    }
  };
  setInterval(()=>{try{if(!BR.show&&BR.view===0&&!document.hidden)BR.up()}catch(e){}},30000);
  const AC=[['#ff8a5c','#e0457b'],['#59b4ff','#2f5bff'],['#4be59a','#12998a'],['#c58bff','#6a3fd8'],['#ffc15e','#ff7a3c'],['#34e6d6','#1a7fd8']];
  /* ---------- Stage 30: iOS tarzı ikon teması (UPSIDEvr IosIcons.kt'den uyarlandı; canvas ile çizilir) ----------
     Tam taşkın kare + yumuşak dikey gradyan + sol üstten gloss + gölgeli beyaz glif. Çizimi olmayan uygulamalar
     kendi renginde harf / glif karosu alır. Köşeleri çağıran yuvarlar (clip). */
  /* ---------- Site ikonu önbelleği: data: URI görüntüleri (tuvali kirletmez). Köşe pikseline bakıp tam taşkın ikon mu küçük favicon mu anlar. ---------- */
  const ICO={m:{},t:0,
    get(src){
      if(!src)return null;
      let e=this.m[src];
      if(!e){
        const im=new Image();
        e=this.m[src]={im,ok:false,full:false,bg:'#fff'};
        im.onload=()=>{
          try{
            const cv=document.createElement('canvas');cv.width=cv.height=16;
            const g=cv.getContext('2d');g.drawImage(im,0,0,16,16);
            const p=g.getImageData(0,0,1,1).data,q=g.getImageData(15,15,1,1).data;
            e.full=p[3]>240&&q[3]>240;e.bg='rgb('+p[0]+','+p[1]+','+p[2]+')'
          }catch(x){}
          e.ok=true;this.dirty()
        };
        im.onerror=()=>{e.bad=true};
        im.src=src
      }
      return e.ok?e:null
    },
    dirty(){clearTimeout(this.t);this.t=setTimeout(()=>WM.panels.forEach(m=>['dock','launcher','qsmenu','lib','store'].includes(m.userData.id)&&WM.paint(m)),60)}
  };
  const IOSI=(()=>{
    const S=256;
    let K=1;
    const sh=(c,on)=>{
      if(on){c.shadowColor='rgba(0,0,0,.31)';c.shadowBlur=7*K;c.shadowOffsetY=4*K}
      else{c.shadowColor='transparent';c.shadowBlur=0;c.shadowOffsetY=0}
    };
    const F=(c,col,s)=>{sh(c,s);c.fillStyle=col};
    const T=(c,col,w)=>{sh(c,0);c.strokeStyle=col;c.lineWidth=w;c.lineCap='round';c.lineJoin='round'};
    const circ=(c,x,y,r)=>{c.beginPath();c.arc(x,y,r,0,Math.PI*2)};
    const line=(c,x1,y1,x2,y2)=>{c.beginPath();c.moveTo(x1,y1);c.lineTo(x2,y2);c.stroke()};
    const poly=(c,p,r)=>{
      /* köşeleri r yarıçapla yuvarlatılmış çokgen (CornerPathEffect karşılığı) */
      const n=p.length;
      c.beginPath();
      c.moveTo((p[0][0]+p[n-1][0])/2,(p[0][1]+p[n-1][1])/2);
      for(let i=0;i<n;i++){const a=p[i],b=p[(i+1)%n];c.arcTo(a[0],a[1],(a[0]+b[0])/2,(a[1]+b[1])/2,r)}
      c.closePath()
    };
    const rg=a=>'rgb('+a[0]+','+a[1]+','+a[2]+')';
    const vert=(top,bot)=>(c,w,h)=>{
      const g=c.createLinearGradient(0,0,0,h);
      g.addColorStop(0,rg(top));g.addColorStop(1,rg(bot));
      c.fillStyle=g;c.fillRect(0,0,w,h)
    };
    const DR={
      /* App Store: üç çizgiden beyaz «A» */
      appstore:{bg:vert([32,196,255],[10,72,236]),gl:c=>{
        T(c,'#fff',22);
        line(c,S*.5,S*.2,S*.27,S*.72);line(c,S*.5,S*.2,S*.73,S*.72);
        line(c,S*.22,S*.58,S*.78,S*.58);line(c,S*.3,S*.8,S*.7,S*.8)
      }},
      /* Safari gibi pusula */
      browser:{bg:vert([104,204,255],[10,108,240]),gl:c=>{
        const cx=128,cy=128;
        circ(c,cx,cy,98);F(c,'#fff',1);c.fill();
        const g=c.createLinearGradient(cx,cy-88,cx,cy+88);
        g.addColorStop(0,'rgb(132,212,255)');g.addColorStop(1,'rgb(20,118,246)');
        circ(c,cx,cy,88);F(c,g,0);c.fill();
        for(let i=0;i<60;i++){
          const a=i*6*Math.PI/180,lg=i%5===0,inner=lg?70:77;
          T(c,'rgba(255,255,255,'+(lg?1:.67)+')',lg?3.2:1.6);
          line(c,cx+84*Math.cos(a),cy+84*Math.sin(a),cx+inner*Math.cos(a),cy+inner*Math.sin(a))
        }
        c.save();c.translate(cx,cy);c.rotate(Math.PI/4);c.translate(-cx,-cy);
        c.beginPath();c.moveTo(cx,cy-68);c.lineTo(cx+15,cy);c.lineTo(cx-15,cy);c.closePath();F(c,'#ff3b30',1);c.fill();
        c.beginPath();c.moveTo(cx,cy+68);c.lineTo(cx+15,cy);c.lineTo(cx-15,cy);c.closePath();F(c,'#fff',1);c.fill();
        c.restore();
        circ(c,cx,cy,6);F(c,'rgb(40,40,50)',0);c.fill()
      }},
      /* Instagram: sıcak gradyan üstünde kamera */
      instagram:{bg:(c,w,h)=>{
        const R=Math.max(w,h),g=c.createRadialGradient(w*.28,h*1.05,0,w*.28,h*1.05,R*1.3);
        g.addColorStop(0,'rgb(254,218,119)');g.addColorStop(.32,'rgb(250,126,30)');g.addColorStop(.62,'rgb(214,41,118)');g.addColorStop(1,'rgb(79,91,213)');
        c.fillStyle=g;c.fillRect(0,0,w,h)
      },gl:c=>{
        T(c,'#fff',14);
        rr(c,58,58,140,140,50);c.stroke();
        circ(c,128,128,34);c.stroke();
        circ(c,160,96,9);F(c,'#fff',0);c.fill()
      }},
      /* Discord: mor-mavi üstünde oyun kolu */
      discord:{bg:vert([124,142,255],[70,80,224]),gl:c=>{
        F(c,'#fff',1);
        rr(c,138,138,66,70,28);c.fill();
        rr(c,52,138,66,70,28);c.fill();
        rr(c,40,82,176,94,46);c.fill();
        F(c,'rgb(84,96,238)',0);
        rr(c,70,120,44,14,5);c.fill();
        rr(c,85,105,14,44,5);c.fill();
        circ(c,160,112,9);c.fill();
        circ(c,184,130,9);c.fill()
      }},
      /* Android robot başı */
      android:{bg:vert([112,232,142],[14,150,84]),gl:c=>{
        c.beginPath();c.moveTo(128,180);c.ellipse(128,180,84,84,0,Math.PI,Math.PI*2,false);c.closePath();F(c,'#fff',1);c.fill();
        T(c,'#fff',10);
        line(c,88,108,70,74);line(c,168,108,186,74);
        F(c,'rgb(14,150,84)',0);
        circ(c,104,148,9);c.fill();circ(c,152,148,9);c.fill()
      }},
      /* YouTube: kırmızı karo, beyaz çubuk, oynat üçgeni */
      youtube:{bg:vert([255,98,88],[214,20,20]),gl:c=>{
        rr(c,36,64,184,128,40);F(c,'#fff',1);c.fill();
        poly(c,[[108,94],[108,162],[170,128]],8);F(c,'rgb(226,36,30)',0);c.fill()
      }},
      /* GitHub: grafit üstünde beyaz kedi başı */
      github:{bg:vert([84,92,106],[28,32,40]),gl:c=>{
        F(c,'#fff',1);
        circ(c,128,136,70);c.fill();
        c.beginPath();c.moveTo(66,126);c.lineTo(70,56);c.lineTo(118,84);c.closePath();
        c.moveTo(190,126);c.lineTo(186,56);c.lineTo(138,84);c.closePath();c.fill();
        c.beginPath();c.moveTo(104,190);c.quadraticCurveTo(104,228,74,226);c.lineTo(88,208);c.closePath();c.fill();
        F(c,'rgb(36,41,52)',0);
        circ(c,106,130,9);c.fill();circ(c,150,130,9);c.fill();
        rr(c,116,150,24,8,4);c.fill()
      }},
      /* Spotify: yeşil disk, üç ses yayı */
      spotify:{bg:vert([64,224,120],[16,150,66]),gl:c=>{
        circ(c,128,128,92);F(c,'rgb(20,166,74)',1);c.fill();
        T(c,'#fff',15);
        for(let i=0;i<3;i++){
          const half=70-i*17,cy=112+i*28;
          c.beginPath();c.ellipse(128,cy,half,half*.55,0,200*Math.PI/180,340*Math.PI/180,false);c.stroke()
        }
      }},
      /* WhatsApp: konuşma balonu + ahize */
      whatsapp:{bg:vert([96,232,132],[18,160,80]),gl:c=>{
        F(c,'#fff',1);
        circ(c,128,122,84);c.fill();
        c.beginPath();c.moveTo(66,214);c.lineTo(76,160);c.lineTo(118,190);c.closePath();c.fill();
        c.beginPath();c.moveTo(94,92);c.quadraticCurveTo(86,122,112,150);c.quadraticCurveTo(140,176,168,166);
        c.lineTo(172,142);c.lineTo(150,134);c.lineTo(140,144);c.quadraticCurveTo(120,136,112,114);
        c.lineTo(122,104);c.lineTo(114,82);c.closePath();F(c,'rgb(24,170,84)',0);c.fill()
      }},
      /* SoundCloud: turuncu üstünde bulut ve ses çubukları */
      soundcloud:{bg:vert([255,160,64],[246,84,0]),gl:c=>{
        F(c,'#fff',1);
        circ(c,150,128,38);c.fill();circ(c,184,146,26);c.fill();
        rr(c,126,120,82,52,16);c.fill();
        T(c,'#fff',9);
        [18,30,42,34,24].forEach((hh,i)=>{const x=48+i*15;line(c,x,170-hh,x,170)})
      }},
      /* Vikipedi: slate üstünde meridyenli küre */
      wikipedia:{bg:vert([120,134,160],[46,56,80]),gl:c=>{
        const cx=128,cy=128;
        circ(c,cx,cy,88);F(c,'#fff',1);c.fill();
        T(c,'rgb(54,66,96)',7);
        circ(c,cx,cy,70);c.stroke();
        c.beginPath();c.ellipse(cx,cy,34,70,0,0,Math.PI*2);c.stroke();
        line(c,cx,cy-70,cx,cy+70);line(c,cx-70,cy,cx+70,cy);
        c.beginPath();c.ellipse(cx,cy,62,38,0,0,Math.PI,false);c.stroke();
        c.beginPath();c.ellipse(cx,cy,62,38,0,Math.PI,Math.PI*2,false);c.stroke()
      }}
    };
    /* Sistem uygulaması → çizim (kalanlar kendi renk + glifiyle iOS karosu olur) */
    const SYSK={browser:'browser',store:'appstore',device:'android'};
    const WEBK={youtube:'youtube',spotify:'spotify',discord:'discord',whatsapp:'whatsapp',github:'github',wikipedia:'wikipedia',instagram:'instagram',soundcloud:'soundcloud'};
    const HOSTK=[[/^(www\.|m\.)?youtube\.com$/,'youtube'],[/^youtu\.be$/,'youtube'],[/(^|\.)instagram\.com$/,'instagram'],[/(^|\.)spotify\.com$/,'spotify'],[/(^|\.)discord\.com$/,'discord'],[/(^|\.)github\.com$/,'github'],[/(^|\.)whatsapp\.com$/,'whatsapp'],[/(^|\.)soundcloud\.com$/,'soundcloud'],[/(^|\.)wikipedia\.org$/,'wikipedia']];
    function keyOf(a){
      if(!a)return null;
      if(a.st)return null;/* App Store'dan inenler: ilk açılışa kadar harf, sonra sitenin ikonu */
      if(a.cat)return WEBK[a.cat]||null;
      let h='';
      try{h=new URL(a.url||'').hostname.toLowerCase()}catch(e){return null}
      for(const q of HOSTK)if(q[0].test(h))return q[1];
      return null
    }
    function tile(c,sp,x,y,w,h){
      const sq=Math.min(w,h),im=sp.img&&ICO.get(sp.img),d=!im&&sp.k&&DR[sp.k];
      c.save();
      c.translate(x,y);
      K=sq/S;
      if(im){
        const pad=im.full?0:sq*.14;
        c.fillStyle=im.full?im.bg:'#fff';c.fillRect(0,0,w,h);
        c.drawImage(im.im,(w-sq)/2+pad,(h-sq)/2+pad,sq-2*pad,sq-2*pad)
      }else if(d){
        d.bg(c,w,h);
        c.save();c.translate((w-sq)/2,(h-sq)/2);c.scale(K,K);d.gl(c);c.restore()
      }else{
        const col=Array.isArray(sp.col)?sp.col:[sp.col||'#59b4ff',sp.col||'#2f5bff'],g=c.createLinearGradient(0,0,0,h);
        g.addColorStop(0,col[0]);g.addColorStop(1,col[1]);
        c.fillStyle=g;c.fillRect(0,0,w,h);
        c.save();
        c.shadowColor='rgba(0,0,0,.28)';c.shadowBlur=6*K;c.shadowOffsetY=3*K;
        if(sp.lab){
          const t=String(sp.lab);
          c.fillStyle='#fff';c.font='700 '+Math.round(sq*(t.length>1?.38:.5))+'px system-ui,sans-serif';
          c.textAlign='center';c.textBaseline='middle';c.fillText(t,w/2,h/2+sq*.035)
        }else ICN(c,sp.ic,w/2,h/2,sq*.3,'#fff');
        c.restore()
      }
      const gl=c.createRadialGradient(w*.3,0,0,w*.3,0,Math.max(w,h));
      gl.addColorStop(0,'rgba(255,255,255,.28)');gl.addColorStop(1,'rgba(255,255,255,0)');
      c.fillStyle=gl;c.fillRect(0,0,w,h);
      c.restore()
    }
    return{tile,keyOf,SYSK,DR}
  })();
  /* ---------- Web uygulaması kataloğu: hazır, tek dokunuşla eklenen siteler. Simgeler marka logosu değil; kendi renk ve harf işaretleri. ---------- */
  const CAT_GROUPS=['Medya','Google','Sohbet','Üretkenlik','Tasarım','Keşif'];
  const CATALOG=[
    {k:'youtube',n:'YouTube',u:'https://m.youtube.com',g:'Medya',gl:'Yt',c:['#ff6a5c','#d6213a']},
    {k:'ytmusic',n:'YouTube Music',u:'https://music.youtube.com',g:'Medya',gl:'Ym',c:['#ff8a5c','#c9264f']},
    {k:'spotify',n:'Spotify',u:'https://open.spotify.com',g:'Medya',gl:'S',c:['#4be59a','#12998a']},
    {k:'soundcloud',n:'SoundCloud',u:'https://soundcloud.com',g:'Medya',gl:'Sc',c:['#ffa040','#f65400']},
    {k:'gmaps',n:'Google Haritalar',u:'https://maps.google.com',g:'Google',gl:'H',c:['#59d98e','#2f7bff']},
    {k:'gdrive',n:'Google Drive',u:'https://drive.google.com',g:'Google',gl:'D',c:['#ffc15e','#2f9d6a']},
    {k:'gdocs',n:'Google Dokümanlar',u:'https://docs.google.com',g:'Google',gl:'Dk',c:['#59b4ff','#2f5bff']},
    {k:'gsheets',n:'Google E-Tablolar',u:'https://sheets.google.com',g:'Google',gl:'Et',c:['#4be59a','#12806a']},
    {k:'gcal',n:'Google Takvim',u:'https://calendar.google.com',g:'Google',gl:'T',c:['#6ea8ff','#3f56e0']},
    {k:'gmail',n:'Gmail',u:'https://mail.google.com',g:'Google',gl:'M',c:['#ff7a6a','#c93a52']},
    {k:'gphotos',n:'Google Fotoğraflar',u:'https://photos.google.com',g:'Google',gl:'F',c:['#ffc15e','#e0457b']},
    {k:'gkeep',n:'Google Keep',u:'https://keep.google.com',g:'Google',gl:'K',c:['#ffd75e','#e0a21a']},
    {k:'discord',n:'Discord',u:'https://discord.com/app',g:'Sohbet',gl:'Di',c:['#8f8bff','#4a47d8']},
    {k:'instagram',n:'Instagram',u:'https://www.instagram.com',g:'Sohbet',gl:'Ig',c:['#ff7a8a','#c9243e']},
    {k:'telegram',n:'Telegram',u:'https://web.telegram.org',g:'Sohbet',gl:'Tg',c:['#59c8ff','#2a84e0']},
    {k:'whatsapp',n:'WhatsApp',u:'https://web.whatsapp.com',g:'Sohbet',gl:'W',c:['#4be59a','#16996a']},
    {k:'reddit',n:'Reddit',u:'https://www.reddit.com',g:'Sohbet',gl:'R',c:['#ff9a5c','#e0502a']},
    {k:'github',n:'GitHub',u:'https://github.com',g:'Üretkenlik',gl:'Gh',c:['#8b95a8','#343a48']},
    {k:'notion',n:'Notion',u:'https://www.notion.so',g:'Üretkenlik',gl:'N',c:['#c9ced8','#5a6070']},
    {k:'figma',n:'Figma',u:'https://www.figma.com',g:'Tasarım',gl:'Fg',c:['#c58bff','#6a3fd8']},
    {k:'canva',n:'Canva',u:'https://www.canva.com',g:'Tasarım',gl:'C',c:['#34e6d6','#7a4fe8']},
    {k:'photopea',n:'Photopea',u:'https://www.photopea.com',g:'Tasarım',gl:'Pp',c:['#5fd6a8','#1a7fa8']},
    {k:'excalidraw',n:'Excalidraw',u:'https://excalidraw.com',g:'Tasarım',gl:'Ex',c:['#a9a6ff','#5a54d8']},
    {k:'pinterest',n:'Pinterest',u:'https://www.pinterest.com',g:'Keşif',gl:'P',c:['#ff7a8a','#c9243e']},
    {k:'wikipedia',n:'Vikipedi',u:'https://tr.wikipedia.org',g:'Keşif',gl:'V',c:['#d6dbe4','#6a7284']},
    {k:'archive',n:'Internet Archive',u:'https://archive.org',g:'Keşif',gl:'Ia',c:['#b8c4d6','#46556e']},
    {k:'lichess',n:'Lichess Satranç',u:'https://lichess.org',g:'Keşif',gl:'Li',c:['#ffc15e','#8a5a2a']},
    {k:'geforce',n:'GeForce NOW',u:'https://play.geforcenow.com',g:'Keşif',gl:'Gf',c:['#9be85e','#2f9a3a']},
    {k:'twitch',n:'Twitch',u:'https://m.twitch.tv',g:'Medya',gl:'Tw',c:['#b58cff','#6a3fd8']},
    {k:'vimeo',n:'Vimeo',u:'https://vimeo.com',g:'Medya',gl:'Vm',c:['#59d6ff','#1a8fd8']},
    {k:'xcom',n:'X',u:'https://x.com',g:'Sohbet',gl:'X',c:['#9aa3b0','#1d2128']},
    {k:'facebook',n:'Facebook',u:'https://m.facebook.com',g:'Sohbet',gl:'Fb',c:['#6ea8ff','#2a4fd8']},
    {k:'linkedin',n:'LinkedIn',u:'https://www.linkedin.com',g:'Sohbet',gl:'In',c:['#59b4ff','#1a64b8']},
    {k:'trello',n:'Trello',u:'https://trello.com',g:'Üretkenlik',gl:'Tr',c:['#6ec0ff','#2a6fe0']},
    {k:'gtranslate',n:'Google Çeviri',u:'https://translate.google.com',g:'Üretkenlik',gl:'Çv',c:['#7aa8ff','#3a56d8']},
    {k:'desmos',n:'Desmos Hesap Makinesi',u:'https://www.desmos.com/calculator',g:'Üretkenlik',gl:'Dm',c:['#7ee8a6','#1a9a5a']},
    {k:'pixlr',n:'Pixlr',u:'https://pixlr.com',g:'Tasarım',gl:'Px',c:['#ff9ad0','#7a4fe8']},
    {k:'gearth',n:'Google Earth',u:'https://earth.google.com/web',g:'Keşif',gl:'Er',c:['#59d6ff','#2f8a6a']},
    {k:'hn',n:'Hacker News',u:'https://news.ycombinator.com',g:'Keşif',gl:'Hn',c:['#ffb070','#e0602a']},
    {k:'duolingo',n:'Duolingo',u:'https://www.duolingo.com',g:'Keşif',gl:'Du',c:['#a8f06a','#3aa83a']}
  ];
  const CATK={};CATALOG.forEach(x=>CATK[x.k]=x);
  function ATILE(c,name,x,y,s,col,gl,key,ico){
    let h=0;
    for(const ch of name)h=(h*31+ch.charCodeAt(0))>>>0;
    const k=Array.isArray(col)?col:AC[h%AC.length],g=c.createLinearGradient(x,y,x,y+s);
    g.addColorStop(0,k[0]);
    g.addColorStop(1,k[1]);
    c.save();
    c.shadowColor='rgba(0,0,0,.5)';
    c.shadowBlur=s*.22;
    c.shadowOffsetY=s*.07;
    rr(c,x,y,s,s,s*.3);
    c.fillStyle=g;
    c.fill();
    c.restore();
    c.save();
    rr(c,x,y,s,s,s*.3);
    c.clip();
    IOSI.tile(c,{k:key,col:k,lab:gl||(name.trim()[0]||'?').toUpperCase(),img:ico},x,y,s,s);
    c.restore()
  }
  const WebApps={
    list:[],
    icoSeq:0,
    init(){
      try{
        this.list=JSON.parse(localStorage.getItem('nexus.apps')||'[]')
      }catch(e){
        this.list=[]
      }
      $('#waf').addEventListener('change',e=>{
        const f=e.target.files[0];
        e.target.value='';
        if(!f)return;
        if(f.size>4e6){
          Diag.toast('Dosya çok büyük (en fazla 4 MB)','var(--err)');
          return
        }
        const r=new FileReader();
        r.onload=()=>{
          const a=this.add({name:f.name.replace(/\.[^.]+$/,'')||'Uygulama',type:'html',html:String(r.result)});
          Diag.toast('Yüklendi: '+a.name,'var(--ok)');
          this.open(a.id)
        };
        r.onerror=()=>Diag.toast('Dosya okunamadı','var(--err)');
        r.readAsText(f)
        })
    },
    save(){
      try{
        localStorage.setItem('nexus.apps',JSON.stringify(this.list.filter(a=>!a.mem)));
        return true
      }catch(e){
        Diag.toast('Depolama dolu; uygulama yalnızca bu oturumda kalır','var(--warn)');
        return false
      }
    },
    ui(){
      WM.panels.forEach(p=>['lib','dock','launcher','qsmenu','store'].includes(p.userData.id)&&WM.paint(p))
    },
    add(a){
      do{a.id='w'+Date.now().toString(36)+Math.random().toString(36).slice(2,5)}while(this.list.some(x=>x.id===a.id));
      this.list.push(a);
      if(!this.save()){
        a.mem=true;
        this.save()
      }
      this.ui();
      return a
    },
    remove(id){
      const i=this.list.findIndex(a=>a.id===id);
      if(i<0)return;
      this.list.splice(i,1);
      this.save();
      const m=WM.panels.find(p=>p.userData.id==='app:'+id);
      if(m)WM.close(m);
      this.ui()
    },
    open(id){
      WM.spawn('app:'+id)
    },
    pick(){
      if(XR.session){
        Diag.toast('VR içinde dosya seçilemez','var(--warn)');
        return
      }
      $('#waf').click()
    },
    ask(){
      if(XR.session){
        Diag.toast('VR içinde metin girişi yok','var(--warn)');
        return
      }
      KBD.ask('Web uygulamasının adresi (https://...)','https://',raw0=>{
        const raw=(raw0||'').trim();
        if(!raw)return;
        const r=BR.norm(raw);
        if(!r||r.err||!/^https?:\/\/[^\s/]+\.[^\s/]+/i.test(r.url)||!/\./.test(raw)){
          Diag.toast('Geçerli bir adres gir','var(--err)');
          return
        }
        let host='';
        try{
          host=new URL(r.url).hostname.replace(/^www\./,'')
        }catch(e){}
        KBD.ask('Uygulama adı',host,n=>{
          const nm=((n||host)+'').trim()||host,a=this.add({name:nm,type:'url',url:r.url});
          Diag.toast('Eklendi: '+a.name,'var(--ok)');
          this.open(a.id)
        })
      })
    },
    /* Katalog: eklenmiş mi, ekle, kaldır */
    has(k){return this.list.find(a=>a.cat===k)||null},
    addCat(k,st){
      const it=CATK[k];
      if(!it)return null;
      const ex=this.has(k);
      if(ex)return ex;
      const a=this.add({name:it.n,type:'url',url:it.u,cat:k,col:it.c,gl:it.gl,st:st?1:0});
      if(st){Diag.toast('İndirildi: '+a.name+' · ilk açılışta sitenin ikonu alınır','var(--ok)',2600);return a}
      Diag.toast('Eklendi: '+a.name+' · Library\u2019de ve Uygulamalarım\u2019da','var(--ok)',2600);
      return a
    },
    act(k){
      const a=this.has(k);
      if(a)this.open(a.id);else this.addCat(k)
    },
    /* İlk açılışta sitenin ikonunu (apple-touch-icon / favicon) yerelden çek, uygulamanın ikonu yap */
    wantIcon(a){
      if(!a||a.type!=='url'||a.ico||!/^https:\/\//i.test(a.url||''))return;
      if(!a.st&&IOSI.keyOf(a))return;
      if(a.icoTried&&Date.now()-a.icoTried<864e5)return;
      if(!(window.AndroidBridge&&AndroidBridge.fetchIcon&&NX_T))return;
      a.icoTried=Date.now();
      const cb='__nxIco'+(++this.icoSeq),self=this;
      window[cb]=d=>{
        delete window[cb];
        if(typeof d==='string'&&/^data:image\/png;base64,[A-Za-z0-9+\/=]+$/.test(d)&&d.length<90000&&self.list.includes(a)){
          a.ico=d;ICO.get(d);self.save();self.ui()
        }else self.save()
      };
      try{if(!AndroidBridge.fetchIcon(a.url,cb,NX_T)){delete window[cb];a.icoTried=0}}catch(e){delete window[cb];a.icoTried=0}
    },
    def(id){
      const a=this.list.find(x=>x.id===id.slice(4));
      if(!a)return null;
      this.wantIcon(a);
      return{
        id,
        icon:'app',
        title:a.name,
        span:1.1,
        h:1.9,
        web:a,
        render(c,W,H,B,u){
          rr(c,16,16,W-32,H-32,12);
          c.fillStyle='#fff';
          c.fill();
          // Gömülü sayfayı açmayı engelleyen siteler için görünür harici tarayıcı kısayolu.
          if(a.type==='url'){
            rr(c,22,22,W-44,42,9); c.fillStyle='#edf1f8'; c.fill();
            c.fillStyle='#25334b'; c.font='600 16px system-ui'; c.textAlign='left';
            c.fillText('Web uygulaması',34,48);
            B(190,25,24,36,'',()=>BF.scrollId('webapp-'+String(u.id).slice(4),-1),false,'chevup','ghost','Web uygulamasını yukarı kaydır');
            B(218,25,24,36,'',()=>BF.scrollId('webapp-'+String(u.id).slice(4),1),false,'chevdown','ghost','Web uygulamasını aşağı kaydır');
            B(W-210,25,174,36,'Tarayıcıda aç',()=>BR.external(a.url),false,'ext','pill');
          }
          u.rect={x:16,y:a.type==='url'?70:16,w:W-32,h:a.type==='url'?H-86:H-32}
        }
      }
    }
  };
