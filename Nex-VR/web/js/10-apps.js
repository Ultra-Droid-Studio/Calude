'use strict';
  /* ---------- Uygulamalar ---------- */
  const APPS={
  store:()=>STORE.def(),
  lib:()=>({
    id:'lib',
    icon:'grid',
    title:'Uygulamalar',
    span:1.1,
    h:1.5,
    render(c,W,H,B,u){
      const tab=u.tab==='cat'?'cat':'mine',y0=TB+10;
      /* üst sekmeler: Uygulamalarım / Katalog */
      [['mine','Uygulamalarım · '+WebApps.list.length,20,244],['cat','Katalog',274,160]].forEach(t=>{
        const on=tab===t[0],hv=B(t[2],y0+6,t[3],52,'',o=>{o.userData.tab=t[0];o.userData.pg=0;o.userData.cg=0},false,null,'raw',t[1]);
        rr(c,t[2],y0+6,t[3],52,26);
        c.fillStyle=on?'#eef1f2':hv?'rgba(255,255,255,.18)':'rgba(255,255,255,.08)';
        c.fill();
        c.fillStyle=on?'#1b1f22':'#e6ebee';
        c.font='600 21px system-ui,sans-serif';
        c.textAlign='center';
        c.fillText(t[1],t[2]+t[3]/2,y0+40);
        c.textAlign='left'
      });
      if(tab==='cat')return CATUI(c,W,H,B,u,y0);
      const L=WebApps.list,per=8,np=Math.max(1,Math.ceil(L.length/per)),pg=clamp(u.pg||0,0,np-1);
      B(W-454,y0+6,214,52,'HTML yükle',()=>WebApps.pick(),false,null,'pill');
      B(W-232,y0+6,212,52,'Adres ekle',()=>WebApps.ask(),false,null,'pill');
      if(np>1){
        B(W-568,y0+8,48,48,'',o=>{
          o.userData.pg=Math.max(0,pg-1);
          WM.paint(o)
          },false,'back','pill');
        B(W-516,y0+8,48,48,'',o=>{
          o.userData.pg=Math.min(np-1,pg+1);
          WM.paint(o)
          },false,'fwd','pill')
      }
      if(!L.length){
        card(c,20,y0+76,W-40,H-y0-96);
        txt(c,'Henüz uygulama yok.\nKatalog sekmesinden tek dokunuşla ekleyebilir, bir .html dosyası yükleyebilir ya da web adresi girebilirsin.\nEklediğin uygulama burada listelenir ve 3B sahnede açılır.',52,y0+150,22,'#aeb2bb',70);
        B(W/2-130,H-130,260,56,'Kataloğa göz at',o=>{o.userData.tab='cat';o.userData.pg=0},false,null,'pill');
        return
      }
      const cw=(W-40-3*14)/4,chh=(H-y0-76-20-14)/2;
      L.slice(pg*per,pg*per+per).forEach((a,k)=>{
        const x=20+(k%4)*(cw+14),y=y0+76+Math.floor(k/4)*(chh+14);
        B(x,y,cw,chh,'',()=>WebApps.open(a.id),false,null,'card',a.name);
        const ts=Math.min(74,chh*.46);
        ATILE(c,a.name,x+cw/2-ts/2,y+chh*.12,ts,a.col,a.gl,IOSI.keyOf(a),a.ico);
        c.fillStyle='#fff';
        c.font='600 20px system-ui';
        c.textAlign='center';
        c.fillText(a.name.length>16?a.name.slice(0,15)+'…':a.name,x+cw/2,y+chh*.12+ts+32);
        c.fillStyle='#aeb2bb';
        c.font='15px system-ui';
        c.fillText(a.type==='html'?'HTML dosyası':'Web adresi',x+cw/2,y+chh*.12+ts+56);
        c.textAlign='left';
        B(x+cw-42,y+8,34,34,'',()=>WebApps.remove(a.id),false,'close','pill',a.name+' sil')
        });
      if(np>1)txt(c,(pg+1)+' / '+np,W/2-24,H-10,16,'#aeb2bb',10)
    }
    }),
  browser:()=>({
    id:'browser',
    icon:'globe',
    title:'NEXUS Browser',
    span:1.1,
    h:1.9,
    render(c,W,H,B){
      const cur=BR.hist[BR.i],bm=Settings.v.bm||(Settings.v.bm=[]),hist=Settings.v.hist||[],marked=!!cur&&bm.indexOf(cur)>=0,acc=ACC[Settings.v.acc];
      const TH=56,TY=124,n=BR.tabs.length,tw=Math.min(230,(W-28-60)/n),tx0=14;
      const hostOf=u=>{try{return new URL(u).hostname.replace(/^www\./,'')}catch(e){return u}};
      const cut=(t,m)=>t.length>m?t.slice(0,m-1)+'…':t;
      /* Chrome görünümü (UPSIDEvr tarayıcı çubuğundan uyarlandı): gri sekme şeridi, beyaz etkin sekme, beyaz araç çubuğu, yuvarlak adres alanı */
      const K={strip:'#dee1e6',page:'#fff',omni:'#f1f3f4',ink:'#202124',soft:'#5f6368',dim:'#bdc1c6',line:'#dadce0',blue:'#1a73e8'};
      const gzB=BR.gz(),canBack=BR.i>0,canFwd=BR.i<BR.hist.length-1,cy0=(TH+TY)/2;
      c.fillStyle=K.strip;c.fillRect(0,0,W,TH);
      c.fillStyle=K.page;c.fillRect(0,TH,W,TY-TH);
      c.fillStyle=K.line;c.fillRect(0,TY-1,W,1);
      const tabTop=8,fl=10,cr=14;
      for(let k=0;k<n;k++){
        const x=tx0+k*tw,r=x+tw-5,act=k===BR.t,tb=BR.tabs[k];
        if(act){
          c.fillStyle=K.page;c.beginPath();
          c.moveTo(x-fl,TH+1);c.quadraticCurveTo(x,TH+1,x,TH-fl);c.lineTo(x,tabTop+cr);c.quadraticCurveTo(x,tabTop,x+cr,tabTop);
          c.lineTo(r-cr,tabTop);c.quadraticCurveTo(r,tabTop,r,tabTop+cr);c.lineTo(r,TH-fl);c.quadraticCurveTo(r,TH+1,r+fl,TH+1);c.closePath();c.fill()
        }else if(k+1!==BR.t&&k+1<n){
          c.fillStyle='rgba(95,99,104,.35)';c.fillRect(r+2,TH/2-9,1.5,18)
        }
        const u0=act?cur:tb.hist[tb.i],sh=act?BR.show:tb.show;
        const ttl=(sh&&u0)?hostOf(u0):'Yeni Sekme';
        const tm=Math.max(4,Math.floor((tw-66)/9.5));
        txt(c,cut(ttl,tm),x+18,38,17,act?K.ink:K.soft,tm+2);
        const cx=r-22,hvx=B(r-42,12,38,38,'',()=>BR.closeTab(k),false,null,'raw','Sekmeyi kapat');
        if(hvx){c.beginPath();c.arc(cx,32,13,0,6.3);c.fillStyle='rgba(0,0,0,.1)';c.fill()}
        c.strokeStyle=K.soft;c.lineWidth=2.2;c.lineCap='round';c.beginPath();c.moveTo(cx-5,27);c.lineTo(cx+5,37);c.moveTo(cx+5,27);c.lineTo(cx-5,37);c.stroke();
        if(!act)B(x,8,tw-52,TH-8,'',()=>BR.sw(k),false,null,'raw','Sekme: '+ttl)
      }
      if(n<5){
        const px=tx0+n*tw+24,hvp=B(px-19,13,38,38,'',()=>BR.newTab(),false,null,'raw','Yeni sekme');
        if(hvp){c.beginPath();c.arc(px,32,16,0,6.3);c.fillStyle='rgba(0,0,0,.1)';c.fill()}
        c.strokeStyle=K.soft;c.lineWidth=2.6;c.lineCap='round';c.beginPath();c.moveTo(px-8,32);c.lineTo(px+8,32);c.moveTo(px,24);c.lineTo(px,40);c.stroke()
      }
      /* Araç çubuğu: geri, ileri, yenile | adres alanı (G / kilit, ☆) | eklenti, profil, ⋮ */
      const tbtn=(cx,fn,nm,draw,ok)=>{
        const hv=ok!==false&&B(cx-21,cy0-21,42,42,'',fn,false,null,'raw',nm);
        if(hv){c.beginPath();c.arc(cx,cy0,20,0,6.3);c.fillStyle='rgba(0,0,0,.08)';c.fill()}
        c.strokeStyle=c.fillStyle=ok===false?K.dim:K.soft;c.lineWidth=3;c.lineCap='round';c.lineJoin='round';draw(cx);return hv
      };
      tbtn(40,()=>BR.step(-1),'Geri',x=>{c.beginPath();c.moveTo(x-10,cy0);c.lineTo(x+10,cy0);c.moveTo(x-10,cy0);c.lineTo(x-2,cy0-8);c.moveTo(x-10,cy0);c.lineTo(x-2,cy0+8);c.stroke()},canBack);
      tbtn(88,()=>BR.step(1),'İleri',x=>{c.beginPath();c.moveTo(x-10,cy0);c.lineTo(x+10,cy0);c.moveTo(x+10,cy0);c.lineTo(x+2,cy0-8);c.moveTo(x+10,cy0);c.lineTo(x+2,cy0+8);c.stroke()},canFwd);
      tbtn(136,()=>{if(BR.hist[BR.i])BR.go(BR.hist[BR.i],false)},'Yenile',x=>{
        c.beginPath();c.arc(x,cy0,9.5,.35,5.6);c.stroke();
        const a=5.6,ex=x+9.5*Math.cos(a),ey=cy0+9.5*Math.sin(a),tx=-Math.sin(a),ty=Math.cos(a),nx=Math.cos(a),ny=Math.sin(a);
        c.beginPath();c.moveTo(ex+tx*8,ey+ty*8);c.lineTo(ex-tx*2+nx*7,ey-ty*2+ny*7);c.lineTo(ex-tx*2-nx*7,ey-ty*2-ny*7);c.closePath();c.fill()
      },!!BR.hist[BR.i]);
      const OL=172,OR=W-176-(gzB?0:62),OY=TH+10,OH=TY-TH-20;
      rr(c,OL,OY,OR-OL,OH,OH/2);c.fillStyle=K.omni;c.fill();
      const hvA=B(OL,OY,OR-OL-58,OH,'',()=>BR.ask(),false,null,'raw','Adres çubuğu');
      if(hvA){rr(c,OL,OY,OR-OL,OH,OH/2);c.fillStyle='rgba(0,0,0,.035)';c.fill()}
      if(cur)drawLockK(c,OL+27,cy0,K.soft);else drawGK(c,OL+27,cy0,9);
      const aMax=Math.max(10,Math.floor((OR-OL-120)/9.4));
      if(cur)txt(c,cut(cur.replace(/^https?:\/\//,''),aMax),OL+52,cy0+7,18,K.ink,aMax+2);
      else txt(c,'Google üzerinde arayın veya bir URL yazın',OL+52,cy0+7,18,K.soft,80);
      const sx=OR-32,hvS=B(sx-24,OY,48,OH,'',()=>{
        if(!cur){Diag.toast('Önce bir site aç','var(--warn)');return}
        const i=bm.indexOf(cur);
        if(i>=0)bm.splice(i,1);else if(bm.length<200)bm.push(cur);else{Diag.toast('En fazla 200 yer imi','var(--warn)');return}
        Settings.save();BR.up()
      },false,null,'raw','Yer imi');
      if(hvS){c.beginPath();c.arc(sx,cy0,19,0,6.3);c.fillStyle='rgba(0,0,0,.07)';c.fill()}
      starK(c,sx,cy0,11,5,marked?K.blue:K.soft,marked);
      if(!gzB){
        B(OR+4,cy0-20,26,40,'',()=>BR.scroll(-1),false,'chevup','ghost','Sayfayı yukarı kaydır');
        B(OR+32,cy0-20,26,40,'',()=>BR.scroll(1),false,'chevdown','ghost','Sayfayı aşağı kaydır')
      }
      const ex0=W-148;
      const hvE=B(ex0-22,cy0-20,44,40,'',()=>Diag.toast('Eklentiler bu sürümde yok','var(--warn)'),false,null,'raw','Eklentiler');
      if(hvE){c.beginPath();c.arc(ex0,cy0,20,0,6.3);c.fillStyle='rgba(0,0,0,.07)';c.fill()}
      rr(c,ex0-13,cy0-9,26,18,4);c.fillStyle='#f4c817';c.fill();
      c.fillStyle='#3c3c3c';for(let i=-1;i<=1;i++){c.beginPath();c.arc(ex0+i*7,cy0,1.9,0,6.3);c.fill()}
      c.fillStyle=K.line;c.fillRect(W-118,cy0-10,1.5,20);
      const ax=W-84,hvP=B(ax-22,cy0-20,44,40,'',()=>Diag.toast('Profil: yerel (giriş yok)'),false,null,'raw','Profil');
      if(hvP){c.beginPath();c.arc(ax,cy0,20,0,6.3);c.fillStyle='rgba(0,0,0,.07)';c.fill()}
      c.save();c.beginPath();c.arc(ax,cy0,13,0,6.3);c.fillStyle='#78909c';c.fill();c.clip();
      c.fillStyle='#eceff1';c.beginPath();c.arc(ax,cy0-3.5,5,0,6.3);c.fill();c.beginPath();c.ellipse(ax,cy0+12,11,8,0,0,6.3);c.fill();c.restore();
      const hvM=B(W-58,cy0-20,48,40,'',()=>{BR.menu=!BR.menu;BR.up()},false,null,'raw','Menü');
      if(hvM||BR.menu){c.beginPath();c.arc(W-34,cy0,20,0,6.3);c.fillStyle=BR.menu?'rgba(26,115,232,.16)':'rgba(0,0,0,.08)';c.fill()}
      c.fillStyle=K.soft;for(let i=-1;i<=1;i++){c.beginPath();c.arc(W-34,cy0+i*8,2.5,0,6.3);c.fill()}
      /* İçerik: açık sayfa */
      if(BR.show&&cur){
        const gz=BR.gz(),G=gz?72:0,fh=40,ih=H-TY-fh-8;
        rr(c,8,TY+4,W-16-G,ih,12);c.fillStyle='#fff';c.fill();
        BR.rect={x:8,y:TY+4,w:W-16-G,h:ih};
        /* Bakış (gaze) modunda pencerenin sağında yukarı / aşağı ok: bakılı tutunca sayfa kayar (tekrarlı) */
        if(gz){
          const gx=W-8-G+8,gw=G-8,bh=Math.min(120,Math.floor((ih-28)/2)),cy=TY+4+Math.round(ih/2);
          rr(c,gx,TY+4,gw,ih,14);c.fillStyle='rgba(12,26,31,.55)';c.fill();
          const fu=()=>BR.scroll(-1),fd=()=>BR.scroll(1);fu.rep=true;fd.rep=true;
          B(gx+4,cy-bh-6,gw-8,bh,'',fu,false,'chevup','btn','Sayfayı yukarı kaydır');
          B(gx+4,cy+6,gw-8,bh,'',fd,false,'chevdown','btn','Sayfayı aşağı kaydır')
        }
        const flags=(Settings.v.desk?'PC sürümü · ':'')+(Settings.v.adb?'Reklam engelli · ':'');
        txt(c,flags+'Sayfa boş kalırsa site gömülmeye izin vermiyor olabilir.',22,H-14,16,'#ffb35c',70);
        B(W-250,H-38,226,32,'Tarayıcıda aç',()=>BR.external(cur),false,null,'pill')
      }
      else{
        BR.rect=null;
        /* Yeni sekme sayfası (UPSIDEvr browser/home.html'den uyarlandı): renkli NEXTvr yazısı, arama alanı, 4 kutucuk, kısayollar; Yer imleri / Geçmiş / Tercihler / Kısayol ekle pencereleri */
        const SOFT='#5f6368',INK='#1f1f1f',CHIP='#edf1fa',CHIP2='#e1e7f5',LN='#dfe1e5',BLU='#4285f4';
        c.save();rr(c,2,2,W-4,H-4,22);c.clip();c.fillStyle='#fff';c.fillRect(0,TY,W,H-TY);c.restore();
        const lg=['N','E','X','T','v','r'],lc=['#4285f4','#ea4335','#fbbc05','#4285f4','#34a853','#ea4335'];
        c.font='700 92px system-ui,sans-serif';c.textAlign='left';
        const lws=lg.map(ch=>c.measureText(ch).width),lt=lws.reduce((q,w)=>q+w,0);
        let lx=(W-lt)/2;lg.forEach((ch,i)=>{c.fillStyle=lc[i];c.fillText(ch,lx,TY+128);lx+=lws[i]});
        const sw=Math.min(W-80,740),sx0=(W-sw)/2,sy=TY+170,sh=60;
        c.save();c.shadowColor='rgba(32,33,36,.28)';c.shadowBlur=9;c.shadowOffsetY=1;rr(c,sx0,sy,sw,sh,30);c.fillStyle='#fff';c.fill();c.restore();
        rr(c,sx0,sy,sw,sh,30);c.lineWidth=1;c.strokeStyle=LN;c.stroke();
        const hvPl=B(sx0+8,sy+8,44,44,'',()=>BR.newTab(),false,null,'raw','Yeni sekme');
        if(hvPl){c.beginPath();c.arc(sx0+30,sy+30,21,0,6.3);c.fillStyle='#eee';c.fill()}
        c.strokeStyle='#1f1f1f';c.lineWidth=2.8;c.lineCap='round';c.beginPath();c.moveTo(sx0+21,sy+30);c.lineTo(sx0+39,sy+30);c.moveTo(sx0+30,sy+21);c.lineTo(sx0+30,sy+39);c.stroke();
        B(sx0+56,sy,sw-56-120,sh,'',()=>BR.ask(),false,null,'raw','Ara veya adres yaz');
        txt(c,'Ara veya adres yaz',sx0+66,sy+38,21,'#9aa0a6',40);
        const hvGo=B(sx0+sw-112,sy+8,100,44,'',()=>BR.ask(),false,null,'raw','Ara');
        rr(c,sx0+sw-112,sy+8,100,44,22);c.fillStyle=hvGo?'#e3e6e8':'#f1f3f4';c.fill();
        ICN(c,'search',sx0+sw-84,sy+30,10,INK);txt(c,'Ara',sx0+sw-64,sy+37,19,INK,10,true);
        /* kutucuklar */
        const cgap=12,cw=(sw-3*cgap)/4,chy=sy+sh+24,chh=66,d=new Date();
        const tm=d.toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'}),dt=d.toLocaleDateString('tr-TR',{weekday:'long',day:'numeric',month:'long'});
        const chips=[
          {t:tm,s:dt,ic:'clock'},
          {t:'Yer imleri',s:bm.length?bm.length+' kayıtlı':'Kayıtlı yok',ic:'star',fn:()=>BR.openView(1),nm:'Yer imleri'},
          {t:'Geçmiş',s:hist.length?hist.length+' son ziyaret':'Ziyaret yok',ic:'hist',fn:()=>BR.openView(2),nm:'Geçmiş'},
          {t:'Tercihler',s:'Reklam ve site',ic:'gearK',fn:()=>BR.openView(3),nm:'Tercihler'}
        ];
        chips.forEach((it,k)=>{
          const x=sx0+k*(cw+cgap),hv=it.fn?B(x,chy,cw,chh,'',it.fn,false,null,'raw',it.nm):false;
          rr(c,x,chy,cw,chh,16);c.fillStyle=hv?CHIP2:CHIP;c.fill();
          iconK(c,it.ic,x+28,chy+chh/2,'#444746');
          const mc=Math.max(6,Math.floor((cw-62)/9));
          txt(c,cut(it.t,mc),x+52,chy+28,17,INK,mc+2,true);
          txt(c,cut(it.s,mc+2),x+52,chy+50,14,SOFT,mc+4)
        });
        /* kısayollar */
        /* Bozuk/eski WebView yerel verilerinde kısayol alanları eksik olabilir.
           Çizim yolu hiçbir zaman undefined.length okumamalı; girdileri burada normalize et. */
        const rawPins=(BR&&typeof BR.pins==='function')?BR.pins():[];
        const pins=(Array.isArray(rawPins)?rawPins:[]).filter(p=>p&&typeof p==='object'&&typeof p.u==='string'&&p.u.trim()).map(p=>({
          u:p.u,
          t:typeof p.t==='string'&&p.t.trim()?p.t.trim():hostOf(p.u)
        }));
        const per=Math.max(3,Math.floor(sw/108)),pcw=sw/per,pty=chy+chh+36;
        const PC=['#4285f4','#ea4335','#f29900','#188038','#a142f4','#e8710a','#00796b','#c2185b'];
        const pcol=value=>{
          /* Defensive palette lookup: never read .length from a possibly
             missing palette or input. Keep a local fallback even if PC was
             overwritten by an old WebView/local script state. */
          const key=String(value==null?'':value);
          let hash=0;
          for(let i=0;i<key.length;i++)hash=(hash*31+key.charCodeAt(i))|0;
          const fallback=['#4285f4','#ea4335','#f29900','#188038','#a142f4','#e8710a','#00796b','#c2185b'];
          const palette=(typeof PC!=='undefined'&&Array.isArray(PC))?PC:fallback;
          const index=(hash>>>0)%8;
          return palette[index]||fallback[index];
        };
        pins.concat([null]).forEach((p,k)=>{
          const col=k%per,row=Math.floor(k/per),mx=sx0+col*pcw+pcw/2,ty=pty+row*128;
          const hv=B(mx-pcw/2+6,ty-4,pcw-12,120,'',p?()=>BR.go(p.u):()=>BR.openView(4),false,null,'raw',p?p.t:'Kısayol ekle');
          c.beginPath();c.arc(mx,ty+36,34,0,6.3);c.fillStyle=hv?CHIP2:CHIP;c.fill();
          if(!p){c.strokeStyle='#1f1f1f';c.lineWidth=3;c.lineCap='round';c.beginPath();c.moveTo(mx-11,ty+36);c.lineTo(mx+11,ty+36);c.moveTo(mx,ty+25);c.lineTo(mx,ty+47);c.stroke()}
          else{
            const h=hostOf(p.u);
            if(/(^|\.)youtube\.com$/.test(h)||h==='youtu.be'){rr(c,mx-19,ty+24,38,25,7);c.fillStyle='#ff0033';c.fill();c.fillStyle='#fff';c.beginPath();c.moveTo(mx-4,ty+30);c.lineTo(mx+8,ty+36.5);c.lineTo(mx-4,ty+43);c.closePath();c.fill()}
            else{c.font='700 30px system-ui,sans-serif';c.textAlign='center';c.fillStyle=pcol(h);c.fillText((p.t||h).charAt(0).toUpperCase(),mx,ty+47);c.textAlign='left'}
          }
          const nm=p?(p.t||hostOf(p.u)):'Kısayol ekle';
          c.font='16px system-ui,sans-serif';c.textAlign='center';c.fillStyle=INK;c.fillText(cut(nm,12),mx,ty+95);c.textAlign='left'
        });
        txt(c,BR.msg,28,H-18,17,'#c26a00',80);
        /* Pencereler (sheet): kapatmak için dışına dokun ya da × */
        if(BR.view>0){
          c.save();rr(c,2,2,W-4,H-4,22);c.clip();c.fillStyle='rgba(32,33,36,.5)';c.fillRect(0,TY,W,H-TY);c.restore();
          B(0,TY,W,H-TY,'',()=>BR.openView(0),false,null,'raw','Pencereyi kapat');
          const v=BR.view,shw=Math.min(W-60,740),shx=(W-shw)/2,shy=TY+36,RH=64;
          const isList=v===1||v===2,list=v===1?bm.map(u=>({u,t:hostOf(u)})):hist.map(x=>({u:x.u,t:x.t||hostOf(x.u)}));
          const per2=Math.max(3,Math.min(7,Math.floor((H-TY-36-70-64-64)/RH))),np=Math.max(1,Math.ceil(list.length/per2)),pg=clamp(BR.pg,0,np-1);BR.pg=pg;
          const shown=isList?list.slice(pg*per2,pg*per2+per2):[];
          const pl=BR.pins(),prMax=Math.max(1,Math.min(5,Math.floor((H-TY-36-64-72-36-30)/RH)));
          let shh=64+20;
          if(isList)shh+=Math.max(1,shown.length)*RH+(np>1?56:0)+(v===2&&list.length?RH:0);
          else if(v===3)shh+=3*72;
          else shh+=72+36+Math.max(1,Math.min(prMax,pl.length))*RH;
          c.save();c.shadowColor='rgba(0,0,0,.35)';c.shadowBlur=30;c.shadowOffsetY=10;rr(c,shx,shy,shw,shh,24);c.fillStyle='#fff';c.fill();c.restore();
          B(shx,shy,shw,shh,'',()=>{},false,null,'raw','Pencere');
          txt(c,v===1?'Yer imleri':v===2?'Son ziyaret edilenler':v===3?'Tercihler':'Kısayol ekle',shx+26,shy+44,24,INK,30,true);
          const hvX=B(shx+shw-64,shy+12,48,48,'',()=>BR.openView(0),false,null,'raw','Kapat');
          c.beginPath();c.arc(shx+shw-40,shy+36,21,0,6.3);c.fillStyle=hvX?CHIP2:CHIP;c.fill();
          c.strokeStyle='#1f1f1f';c.lineWidth=2.6;c.lineCap='round';c.beginPath();c.moveTo(shx+shw-48,shy+28);c.lineTo(shx+shw-32,shy+44);c.moveTo(shx+shw-32,shy+28);c.lineTo(shx+shw-48,shy+44);c.stroke();
          const sY=shy+64,small=(x,y,w,h,label,fn,nm,danger,fill)=>{
            const hv=B(x,y,w,h,'',fn,false,null,'raw',nm||label);
            rr(c,x,y,w,h,h/2);c.fillStyle=fill||(hv?CHIP2:CHIP);c.fill();
            c.font='600 17px system-ui,sans-serif';c.textAlign='center';c.fillStyle=fill?'#fff':danger?'#b3261e':INK;c.fillText(label,x+w/2,y+h/2+6);c.textAlign='left'
          };
          const swit=(x,y,on,fn,nm)=>{
            B(x,y,56,32,'',fn,false,null,'raw',nm);
            rr(c,x,y,56,32,16);c.fillStyle=on?BLU:'#c4c7c5';c.fill();
            c.beginPath();c.arc(x+(on?40:16),y+16,12,0,6.3);c.fillStyle='#fff';c.fill()
          };
          if(isList){
            if(!shown.length)txt(c,v===1?'Henüz yer imi yok. Bir sayfayı ☆ ile kaydedebilirsin.':'Henüz ziyaret yok. Bir site açınca burada görünür.',shx+26,sY+40,19,SOFT,70);
            shown.forEach((it,k)=>{
              const y=sY+k*RH,hv=B(shx+12,y,shw-24-(v===1?100:0),RH,'',()=>BR.go(it.u),false,null,'raw',it.t);
              if(hv){rr(c,shx+12,y+3,shw-24-(v===1?100:0),RH-6,12);c.fillStyle='rgba(0,0,0,.05)';c.fill()}
              if(k){c.fillStyle='#eceef2';c.fillRect(shx+26,y,shw-52,1)}
              txt(c,cut(it.t,44),shx+26,y+27,19,INK,50,true);
              txt(c,cut(it.u,70),shx+26,y+49,14,SOFT,80);
              if(v===1)small(shx+shw-104,y+13,80,38,'Sil',()=>BR.delBm(it.u),'Yer imini sil',true)
            });
            if(np>1){
              const py=sY+Math.max(1,shown.length)*RH+6;
              txt(c,(pg+1)+' / '+np,shx+26,py+30,18,SOFT,10);
              B(shx+shw-128,py,48,40,'',()=>{BR.pg=Math.max(0,pg-1);BR.up()},false,'back','pill','Önceki sayfa');
              B(shx+shw-76,py,48,40,'',()=>{BR.pg=Math.min(np-1,pg+1);BR.up()},false,'fwd','pill','Sonraki sayfa')
            }
            if(v===2&&list.length){
              const y=sY+Math.max(1,shown.length)*RH+(np>1?56:0);
              c.fillStyle='#eceef2';c.fillRect(shx+26,y,shw-52,1);
              txt(c,'Geçmişi temizle',shx+26,y+27,19,INK,30,true);txt(c,'Son ziyaretleri kaldır',shx+26,y+49,14,SOFT,40);
              small(shx+shw-124,y+13,100,38,'Temizle',()=>BR.clearHist(),'Geçmişi temizle',true)
            }
          }
          else if(v===3){
            const rows=[
              {t:'Masaüstü sitesi',d:'Siteleri bilgisayar görünümünde aç',sw:!!Settings.v.desk,fn:()=>BR.setDesk(!Settings.v.desk),nm:'Masaüstü sitesi anahtarı'},
              {t:'Reklam engelleme',d:'Bilinen reklam ve izleyicileri engelle',sw:!!Settings.v.adb,fn:()=>BR.setAdb(!Settings.v.adb),nm:'Reklam engelleme anahtarı'},
              {t:'Adres çubuğu',d:'Adres veya arama terimini VR klavyeyle gir',btn:'Aç',fn:()=>{BR.openView(0);BR.ask()},nm:'Adres çubuğunu aç'}
            ];
            rows.forEach((it,k)=>{
              const y=sY+k*72;
              if(k){c.fillStyle='#eceef2';c.fillRect(shx+26,y,shw-52,1)}
              txt(c,it.t,shx+26,y+32,19,INK,40,true);txt(c,it.d,shx+26,y+55,14,SOFT,70);
              if(it.btn)small(shx+shw-104,y+17,80,38,it.btn,it.fn,it.nm);
              else swit(shx+shw-84,y+20,it.sw,it.fn,it.nm)
            })
          }
          else{
            small(shx+shw-150,sY,126,46,'Adres gir',()=>BR.addPin(),'Kısayol adresi gir',false,BLU);
            txt(c,'Adres yazıp VR klavyeyle ekle (örn. example.com)',shx+26,sY+30,16,SOFT,60);
            txt(c,'Kayıtlı kısayollar',shx+26,sY+72+4,16,SOFT,30,true);
            if(!pl.length)txt(c,'Kısayol yok.',shx+26,sY+72+44,18,SOFT,30);
            pl.slice(0,prMax).forEach((p,k)=>{
              const y=sY+72+36+k*RH;
              if(k){c.fillStyle='#eceef2';c.fillRect(shx+26,y,shw-52,1)}
              txt(c,cut(p.t||hostOf(p.u),44),shx+26,y+27,19,INK,50,true);txt(c,cut(p.u,70),shx+26,y+49,14,SOFT,80);
              small(shx+shw-104,y+13,80,38,'Sil',()=>BR.delPin(p.u),'Kısayolu sil',true)
            })
          }
        }
      }
      /* Menü (en son çizilir: üstte kalır ve dışına dokunmak kapatır) */
      if(BR.menu){
        B(0,TH,W,H-TH,'',()=>{BR.menu=false;BR.up()},false,null,'raw','Menüyü kapat');
        const mw=340,rh2=54,mx=W-16-mw,my=TY-6;
        const items=[
          {l:'PC sürümü',sw:!!Settings.v.desk,fn:()=>BR.setDesk(!Settings.v.desk)},
          {l:'Reklam engelleyici',sw:!!Settings.v.adb,fn:()=>BR.setAdb(!Settings.v.adb)},
          {l:'Yer imleri',fn:()=>BR.openView(1)},
          {l:'Geçmiş',fn:()=>BR.openView(2)},
          {l:'Yeni sekme',fn:()=>BR.newTab()}
        ];
        if(BR.show&&cur)items.push({l:'Tarayıcıda aç',fn:()=>{BR.menu=false;BR.external(cur)}});
        rr(c,mx,my,mw,items.length*rh2+16,18);c.save();c.shadowColor='rgba(0,0,0,.3)';c.shadowBlur=18;c.shadowOffsetY=6;c.fillStyle='#fff';c.fill();c.restore();
        c.lineWidth=1.5;c.strokeStyle='#dadce0';c.stroke();
        items.forEach((it,k)=>{
          const y=my+8+k*rh2,hv=B(mx+8,y,mw-16,rh2-4,'',it.fn,false,null,'raw',it.l);
          if(hv){rr(c,mx+8,y,mw-16,rh2-4,14);c.fillStyle='rgba(0,0,0,.07)';c.fill()}
          txt(c,it.l,mx+26,y+33,19,'#202124',22);
          if(it.sw!==undefined){
            rr(c,mx+mw-84,y+11,54,28,14);c.fillStyle=it.sw?'#1a73e8':'#bdc1c6';c.fill();
            c.beginPath();c.arc(mx+mw-(it.sw?44:70),y+25,10,0,6.3);c.fillStyle='#fff';c.fill()
          }
        })
      }
    }
    }),
  settings:()=>({
    id:'settings',
    icon:'gear',
    title:'Ayarlar',
    span:1.1,
    h:2.45,
    render(c,W,H,B,u){
      const v=Settings.v,acc=ACC[v.acc],S=()=>{
        Settings.save();
        Settings.apply();
        if(Stereo&&Stereo.on)Stereo.applyProfile()
      };
      const tabs=[['Görünüm','image'],['Grafik','monitor'],['Kontrol','sliders'],['El takibi','hand'],['Sistem','device'],['Gizlilik','shield'],['Filtre','eye'],['Kamera','compass'],['Uygulamalar','grid'],['Veri','folder'],['VR ayarları','ring']];
      const TS=Math.min(66,(H-TB-28)/tabs.length);
      tabs.forEach((t,k)=>B(20,TB+14+k*TS,200,Math.min(58,TS-6),'',o=>{
        u.tab=k;
        WM.paint(o)
        },u.tab===k,null,'ghost',t[0]));
      tabs.forEach((t,k)=>{
        const cl=u.tab===k?'#16171a':'#d2d5db';
        ICN(c,t[1],48,TB+43+k*TS,12,cl);
        txt(c,t[0],74,TB+51+k*TS,22,cl,12,u.tab===k)
        });
      const x0=244,w=W-x0-20;
      let y=TB+14,i=0;
      const rowsCard=n=>{
        card(c,x0,y,w,n*60+8);
        y+=4;
        i=0
      };
      const row=l=>{
        const ry=y+i*60;
        if(i)c.fillStyle='rgba(255,255,255,.07)',c.fillRect(x0+20,ry,w-40,1);
        txt(c,l,x0+22,ry+38,22,'#fff',30);
        i++;
        return ry+8
      };
      const step=(l,val,a,b)=>{
        const ry=row(l);
        B(x0+w-290,ry,54,44,'',a,false,'minus','pill',l+' azalt');
        c.fillStyle='#fff';
        c.font='21px system-ui';
        c.textAlign='center';
        c.fillText(val,x0+w-175,ry+30);
        c.textAlign='left';
        B(x0+w-114,ry,54,44,'',b,false,'plus','pill',l+' artır')
      };
      const sw=(l,on,f)=>{
        const ry=row(l),sx=x0+w-120;
        B(sx,ry,84,44,'',f,false,null,'raw',l+(on?' açık':' kapalı'));
        rr(c,sx,ry,84,44,22);
        c.fillStyle=on?acc:'#3a3c42';
        c.fill();
        c.beginPath();
        c.arc(sx+(on?62:22),ry+22,17,0,6.3);
        c.fillStyle='#fff';
        c.fill()
      };
      const q=['Düşük','Orta','Yüksek'],caps=[0,30,60],ci=Math.max(0,caps.indexOf(v.fpscap));
      const lv=(k,d)=>()=>{
        v[k]=clamp(v[k]+d,1,5);
        S();
        if(k==='hsm'&&Hand.on)Hand.initF()
      };
      if(u.tab>=6){
        const ns=(k,l,mn,mx,st,f)=>{const prec=Math.max(2,((String(st).split('.')[1]||'').length));step(l,f?f(v[k]):String(v[k]),()=>{v[k]=clamp(+(v[k]-st).toFixed(prec),mn,mx);S()},()=>{v[k]=clamp(+(v[k]+st).toFixed(prec),mn,mx);S()})};
        const tg=(k,l)=>sw(l,!!v[k],()=>{v[k]=!v[k];S()});
        const act=(l,t,fn)=>{const ry=row(l);B(x0+w-250,ry,210,44,'',fn,false,null,'pill',l);c.fillStyle='#fff';c.font='20px system-ui';c.textAlign='center';c.fillText(t,x0+w-145,ry+30);c.textAlign='left'};
        if(u.tab===6){
          rowsCard(7);ns('fbr','Parlaklık',.5,1.5,.05,x=>Math.round(x*100)+'%');ns('fco','Kontrast',.5,1.8,.05,x=>Math.round(x*100)+'%');ns('fsa','Doygunluk',0,2,.1,x=>Math.round(x*100)+'%');ns('fhu','Renk tonu',-180,180,15,x=>x+'°');tg('fgr','Gri tonlama');tg('fse','Sepya');act('Filtreleri sıfırla','Sıfırla',()=>{Object.assign(v,{fbr:1,fco:1,fsa:1,fhu:0,fgr:false,fse:false});S()})
        }else if(u.tab===7){
          rowsCard(3);ns('fov','Görüş alanı (FOV)',50,110,5,x=>x+'°');ns('toastms','Bildirim süresi',1500,10000,500,x=>(x/1000)+' sn');tg('tbot','Bildirimler altta')
        }else if(u.tab===8){
          rowsCard(5);tg('h24','Saat: 24 saat biçimi');tg('ssec','Saatte saniyeyi göster');ns('cdec','Hesap makinesi ondalık',0,8,1);ns('nfs','Not yazı boyutu',16,32,2);ns('tmin','Varsayılan zamanlayıcı (dk)',1,60,1)
        }else if(u.tab===9){
          const dump=()=>JSON.stringify({s:v,notes:(()=>{try{return localStorage.getItem('nexus.notes')}catch(e){return null}})()});
          rowsCard(4);
          act('Ayarları panoya kopyala','Kopyala',()=>{try{navigator.clipboard.writeText(dump()).then(()=>Diag.toast('Ayarlar panoya kopyalandı','var(--ok)'),()=>Diag.toast('Pano erişimi reddedildi','var(--err)'))}catch(e){Diag.toast('Pano yok','var(--err)')}});
          act('Ayarları dosyaya indir','İndir',()=>{try{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([dump()],{type:'application/json'}));a.download='nexus-ayarlar.json';a.click();Diag.toast('Dosya indirildi','var(--ok)')}catch(e){Diag.toast('İndirilemedi','var(--err)')}});
          act('Ayarları içe aktar','Seç',()=>{if(XR.session)return Diag.toast('VR içinde dosya seçilemez','var(--warn)');const i=document.createElement('input');i.type='file';i.accept='.json';i.onchange=async()=>{try{const j=JSON.parse(await i.files[0].text());if(!j.s)throw 0;Object.assign(v,j.s);if(j.notes)try{localStorage.setItem('nexus.notes',j.notes)}catch(e){};Scene.setWP(v.wp);S();Diag.toast('Ayarlar yüklendi','var(--ok)')}catch(e){Diag.toast('Geçersiz ayar dosyası','var(--err)')}};i.click()});
          act('Tüm verileri sıfırla',u.rst&&Date.now()-u.rst<4000?'Emin misin?':'Sıfırla',()=>{if(u.rst&&Date.now()-u.rst<4000){Storage.clear();try{localStorage.removeItem('nexus.notes')}catch(e){}location.reload()}else{u.rst=Date.now();Diag.toast('Onaylamak için 4 sn içinde tekrar bas','var(--warn)');WM.repaintAll()}})
        }else if(u.tab===10){
          const profiles=[
            {id:'cardboard',name:'Google Cardboard',eye:.064,fov:75,offset:0,scale:.85},
            {id:'vrbox',name:'VR Box',eye:.063,fov:78,offset:0,scale:.82},
            {id:'vrsensation',name:'VR Sensation',eye:.064,fov:78,offset:0,scale:.85},
            {id:'shinecon',name:'VR SHINECON',eye:.063,fov:80,offset:0,scale:.82},
            {id:'bobovr',name:'BOBOVR / Z4',eye:.064,fov:82,offset:0,scale:.85},
            {id:'destek',name:'DESTEK',eye:.063,fov:80,offset:0,scale:.82},
            {id:'merge',name:'Merge VR',eye:.064,fov:78,offset:0,scale:.85},
            {id:'generic',name:'Genel / özel gözlük',eye:.064,fov:75,offset:0,scale:.8}
          ];
          let pi=Math.max(0,profiles.findIndex(p=>p.id===(u.vrProfileDraft||v.vrProfile||'cardboard')));
          const applyProfile=()=>{const p=profiles[pi];v.vrProfile=p.id;delete u.vrProfileDraft;v.vrEyeSep=p.eye;v.vrFov=p.fov;v.vrOffsetY=p.offset;v.vrScale=p.scale;S();WM.repaintAll();Diag.toast(p.name+' başlangıç profili uygulandı','var(--ok)')};
          rowsCard(7);
          const ry=row('Gözlük profili');
          B(x0+w-290,ry,48,44,'',()=>{pi=(pi+profiles.length-1)%profiles.length;u.vrProfileDraft=profiles[pi].id;WM.repaintAll()},false,'chevron-left','pill','Önceki gözlük profili');
          c.fillStyle='#fff';c.font='18px system-ui';c.textAlign='center';c.fillText(profiles[pi].name,x0+w-176,ry+29);c.textAlign='left';
          B(x0+w-90,ry,48,44,'',()=>{pi=(pi+1)%profiles.length;u.vrProfileDraft=profiles[pi].id;WM.repaintAll()},false,'chevron-right','pill','Sonraki gözlük profili');
          act('Profili uygula','Uygula',applyProfile);
          ns('vrEyeSep','Gözler arası mesafe',.052,.075,.001,x=>Math.round(x*1000)+' mm');
          ns('vrFov','VR görüş açısı',60,100,2,x=>x+'°');
          ns('vrOffsetY','Dikey görüntü hizası',-.03,.03,.005,x=>Math.round(x*1000)+' mm');
          ns('vrScale','VR performans ölçeği',.6,1,.05,x=>Math.round(x*100)+'%');
          act('VR kalibrasyon ipuçları','Göster',()=>Diag.toast('Gözlük takılıyken iki görüntü rahat birleşmeli; dikey merkez ve düz çizgileri kontrol et. Gerekirse mesafe ve hizayı ayarla.', 'var(--warn)',6000));
          txt(c,'Marka profilleri başlangıç değerleridir; aynı markanın modelleri ve telefon ekranları farklı olabilir. Değişiklikleri kaydetmek için profili uygula veya değerleri ayarla.',x0+22,y+430,16,'#9ba9c8',Math.max(10,w-44));
        }
      }else if(u.tab===0){
        const NC=4,RP=100,sw2=(w-44-(NC-1)*12)/NC,nr=Math.ceil((WALL.length+3)/NC),slot=k=>[x0+22+(k%NC)*(sw2+12),y+54+Math.floor(k/NC)*RP];
        card(c,x0,y,w,54+nr*RP+30);
        txt(c,'Duvar kağıdı',x0+22,y+38,24,'#fff',30,true);
        WALL.forEach((p,k)=>{
          const [sx,sy]=slot(k);
          B(sx,sy,sw2,64,'',()=>{
            v.wp=k;
            Scene.setWP(k);
            S()
            },false,null,'raw','Duvar kağıdı: '+p.n);
          const g=c.createLinearGradient(0,sy,0,sy+64);
          p.s.forEach(st=>g.addColorStop(st[0],st[1]));
          rr(c,sx,sy,sw2,64,14);
          c.fillStyle=g;
          c.fill();
          /* gerçek önizleme: VR dışında boş zamanda üretilir, VR içinde yalnızca hazır olanlar gösterilir */
          const th=XR.session?WallArt.cache[p.id]:WallArt.thumb(p.id,()=>WM.repaintAll());
          if(th){
            c.save();
            rr(c,sx,sy,sw2,64,14);
            c.clip();
            c.drawImage(th,sx,sy,sw2,64);
            c.restore()
          }
          if(v.wp===k){
            rr(c,sx,sy,sw2,64,14);
            c.lineWidth=4;
            c.strokeStyle='#fff';
            c.stroke()
          }
          txt(c,p.n,sx+2,sy+86,17,'#a9b6d3',16)
          });
        /* düz panorama değil: dokununca ilgili Sinema odası 3 boyutlu ortam olarak açılır */
        const SP3D=[
          {kind:'roblox',n:'Roblox evi (3D)',icon:'home',g:['#ff6b6b','#8a3ffc','#1a0f3c'],a:'Roblox evi, 3 boyutlu ortam'},
          {kind:'minecraft',n:'Minecraft (3D)',icon:'cube',g:['#8fd14f','#3f8f3a','#4a3015'],a:'Minecraft dünyası, 3 boyutlu ortam'}
        ];
        SP3D.forEach((sp,si)=>{
          const [sx,sy]=slot(WALL.length+si),active=Places.on&&Places.kind===sp.kind;
          B(sx,sy,sw2,64,'',()=>{
            Places.toggle(sp.kind);
            WM.repaintAll()
            },false,null,'raw','Mekân: '+sp.a);
          const g=c.createLinearGradient(0,sy,0,sy+64);
          g.addColorStop(0,sp.g[0]);g.addColorStop(.55,sp.g[1]);g.addColorStop(1,sp.g[2]);
          rr(c,sx,sy,sw2,64,14);
          c.fillStyle=g;
          c.fill();
          ICN(c,sp.icon,sx+sw2/2,sy+30,16,'#fff');
          if(active){
            rr(c,sx,sy,sw2,64,14);
            c.lineWidth=4;
            c.strokeStyle='#fff';
            c.stroke()
          }
          txt(c,sp.n,sx+2,sy+86,17,'#a9b6d3',16)
          });
        const [fx,fy]=slot(WALL.length+SP3D.length);
        B(fx,fy,sw2,64,'',()=>XR.session?Diag.toast('VR içinde dosya seçilemez','var(--warn)'):$('#wpf').click(),v.wp===-1,'folder','card','Duvar kağıdı: dosyadan seç');
        txt(c,'Dosyadan',fx+4,fy+86,17,'#a9b6d3',16);
        txt(c,'İpucu: "Roblox evi" ve "Minecraft" Sinema değil, ayrı 3D mekânlardır; pencereler normal açılır. Çıkmak için tekrar dokun veya bir duvar kağıdı seç.',x0+22,y+54+nr*RP+8,17,'#8a99bd',70);
        y+=54+nr*RP+46;
        rowsCard(4);
        {
          const ry=row('Vurgu rengi');
          ACC.forEach((a,k)=>{
            const cx=x0+w-60-(3-k)*56;
            B(cx-22,ry,44,44,'',()=>{
              v.acc=k;
              S()
              },false,null,'raw','Vurgu rengi '+(k+1));
            c.beginPath();
            c.arc(cx,ry+22,17,0,6.3);
            c.fillStyle=a;
            c.fill();
            if(v.acc===k){
              c.lineWidth=3;
              c.strokeStyle='#fff';
              c.beginPath();
              c.arc(cx,ry+22,22,0,6.3);
              c.stroke()
            }
            })
        }
        step('Panel saydamlığı',v.alpha.toFixed(2),()=>{
          v.alpha=Math.max(.4,+(v.alpha-.05).toFixed(2));
          S()
          },()=>{
          v.alpha=Math.min(1,+(v.alpha+.05).toFixed(2));
          S()
          });
        sw('Animasyonları azalt',v.reduce,()=>{
          v.reduce=!v.reduce;
          S()
          });
        sw('Pencere çubuğu (altta)',v.pill!==false,()=>{
          v.pill=v.pill===false;
          S();
          WM.panels.forEach(p=>{if(!p.userData.dock&&!p.userData.kbd)WM.build(p)})
          })
      }
      else if(u.tab===1){
        rowsCard(13);
        step('Grafik kalitesi',q[v.quality],()=>{
          v.quality=Math.max(0,v.quality-1);
          S()
          },()=>{
          v.quality=Math.min(2,v.quality+1);
          S()
          });
        step('Piksel oranı sınırı',v.dpr.toFixed(1),()=>{
          v.dpr=Math.max(1,v.dpr-.5);
          S()
          },()=>{
          v.dpr=Math.min(3,v.dpr+.5);
          S()
          });
        step('FPS sınırı',caps[ci]?String(caps[ci]):'Sınırsız',()=>{
          v.fpscap=caps[(ci+2)%3];
          S()
          },()=>{
          v.fpscap=caps[(ci+1)%3];
          S()
          });
        sw('Otomatik çözünürlük',v.autoq,()=>{
          v.autoq=!v.autoq;
          if(!v.autoq){
            Renderer.scale=1;
            Renderer.resize()
          }
          S()
          });
        sw('FPS göstergesi',v.fps,()=>{
          v.fps=!v.fps;
          S()
          });
        sw('GPU tarayıcı (video, deneysel)',v.gpu!==false,()=>{
          v.gpu=(v.gpu===false);
          S();
          BF.syncGpu();
          Diag.toast('Tarayıcıyı kapatıp yeniden açınca geçerli olur','var(--warn)')
          });
        /* Stage 64: elle ayarlanabilen performans seçenekleri (Otomatik = cihaz seviyesine göre) */
        {
          const HP=['Otomatik','Hafif','Standart'],hp=v.ghand|0;
          step('El takibi profili',HP[hp],()=>{v.ghand=(hp+2)%3;S();if(Hand.on)try{Hand.restart()}catch(e){}},()=>{v.ghand=(hp+1)%3;S();if(Hand.on)try{Hand.restart()}catch(e){}});
          const AAL=['Otomatik','Kapalı','Açık'],aa=v.gaa|0,aaMsg=()=>Diag.toast('Kenar yumuşatma uygulamayı yeniden başlatınca geçerli olur','var(--warn)',3200);
          step('Kenar yumuşatma',AAL[aa],()=>{v.gaa=(aa+2)%3;S();aaMsg()},()=>{v.gaa=(aa+1)%3;S();aaMsg()});
          const PXB=[0,.5,.75,1,1.25,1.5,2],pi=Math.max(0,PXB.indexOf(+v.pxb||0));
          step('Piksel bütçesi',PXB[pi]?'×'+PXB[pi]:'Otomatik',()=>{v.pxb=PXB[(pi+PXB.length-1)%PXB.length];S()},()=>{v.pxb=PXB[(pi+1)%PXB.length];S()});
          const HZL=[0].concat(Dev.hzs),hi=Math.max(0,HZL.indexOf(v.ghz|0));
          step('Yenileme hızı',HZL[hi]?HZL[hi]+' Hz':'Otomatik',()=>{v.ghz=HZL[(hi+HZL.length-1)%HZL.length];S()},()=>{v.ghz=HZL[(hi+1)%HZL.length];S()});
          const WL=[0,1,2,3,4,6,8,12],wi=Math.max(0,WL.indexOf(v.gwin|0));
          step('Android pencere sayısı',WL[wi]?String(WL[wi]):'Sınırsız',()=>{v.gwin=WL[(wi+WL.length-1)%WL.length];S()},()=>{v.gwin=WL[(wi+1)%WL.length];S()});
          /* Stage 68: pencerelerin ve dock'un bize uzaklığı (metre); açık pencerelere hemen uygulanır */
          step('Pencere uzaklığı',(v.wdist||2.9).toFixed(1)+' m',()=>{
            v.wdist=Math.max(1.2,+((v.wdist||2.9)-.2).toFixed(1));
            S();
            WM.applyDist()
            },()=>{
            v.wdist=Math.min(5,+((v.wdist||2.9)+.2).toFixed(1));
            S();
            WM.applyDist()
            });
          step('Dok uzaklığı',(v.ddist||1.8).toFixed(1)+' m',()=>{
            v.ddist=Math.max(.8,+((v.ddist||1.8)-.1).toFixed(1));
            S();
            WM.applyDist()
            },()=>{
            v.ddist=Math.min(3.2,+((v.ddist||1.8)+.1).toFixed(1));
            S();
            WM.applyDist()
            })
        }
      }
      else if(u.tab===2){
        rowsCard(5);
        step('Bakış hassasiyeti',v.sens.toFixed(1),()=>{
          v.sens=Math.max(.3,+(v.sens-.1).toFixed(1));
          S()
          },()=>{
          v.sens=Math.min(2,+(v.sens+.1).toFixed(1));
          S()
          });
        step('Dikey bakış sınırı',Math.round(v.pitch*57.3)+'°',()=>{
          v.pitch=Math.max(.5,+(v.pitch-.1).toFixed(1));
          S()
          },()=>{
          v.pitch=Math.min(1.5,+(v.pitch+.1).toFixed(1));
          S()
          });
        sw('Otomatik dönüş',v.auto,()=>{
          v.auto=!v.auto;
          S()
          });
        sw('Sensör kontrolü',Cam.gyro,()=>Cam.gyro?Cam.disableGyro():Cam.enableGyro());
        sw('Dikey bakışı ters çevir',v.inv,()=>{
          v.inv=!v.inv;
          S()
          })
      }
      else if(u.tab===3){
        rowsCard(14);
        sw('El takibi',Hand.on,()=>Hand.on?Hand.stop():Hand.start());
        step('Kamera',v.hcam==='user'?'Ön':'Arka',()=>{
          v.hcam=v.hcam==='user'?'environment':'user';
          S();
          Hand.on?Hand.restart():Pass.refresh()
          },()=>{
          v.hcam=v.hcam==='user'?'environment':'user';
          S();
          Hand.on?Hand.restart():Pass.refresh()
          });
        step('Çimdik hassasiyeti',v.hclk+' / 5',lv('hclk',-1),lv('hclk',1));
        step('Tıklama bekleme süresi',v.hdw+' sn',lv('hdw',-1),lv('hdw',1));
        step('Win7 arayüz boyutu',Math.round(128000/(v.w7w||1280))+' %',()=>{v.w7w=clamp((v.w7w||1280)+160,800,2240);S();BF.w7Apply()},()=>{v.w7w=clamp((v.w7w||1280)-160,800,2240);S();BF.w7Apply()});
        step('Win7 netlik',(v.w7q||1.25).toFixed(2)+'×',()=>{v.w7q=clamp(Math.round(((v.w7q||1.25)-.25)*100)/100,1,2);S();BF.w7Apply()},()=>{v.w7q=clamp(Math.round(((v.w7q||1.25)+.25)*100)/100,1,2);S();BF.w7Apply()});
        step('Kamera kalitesi',['Düşük 480p','Orta 720p','Yüksek 1080p'][clamp(v.hcq|0,0,2)],()=>{v.hcq=clamp((v.hcq|0)-1,0,2);S();if(Hand.on)try{Hand.restart()}catch(e){}},()=>{v.hcq=clamp((v.hcq|0)+1,0,2);S();if(Hand.on)try{Hand.restart()}catch(e){}});
        sw('El çizimi',v.hdraw,()=>{
          v.hdraw=!v.hdraw;
          S();
          if(!v.hdraw)Hand.clr()
          });
        sw('Turbo el (anında + gecikme telafisi)',v.hfast!==false,()=>{
          v.hfast=v.hfast===false;
          S();
          if(Hand.on)try{Hand.initF()}catch(e){}
          });
        sw('Akıcı el (ara değerleme)',v.hsmo===true,()=>{
          v.hsmo=!v.hsmo;
          S()
          });
        sw('Tek el modu (daha hızlı)',!!v.hone,()=>{
          v.hone=!v.hone;
          S();
          try{Diag.toast('El sayısı, el takibi kapatılıp açılınca değişir','var(--ok)',3500)}catch(e){}
          });
        sw('Kamera önizleme',v.hprev,()=>{
          v.hprev=!v.hprev;
          S();
          Hand.pv()
          });
        sw('El menüsü (avuç yüze)',v.hmenu!==false,()=>{
          v.hmenu=v.hmenu===false;
          S();
          if(v.hmenu===false)HMenu.close()
          });
        sw('Avuç yönünü ters çevir',!!v.hmflip,()=>{
          v.hmflip=!v.hmflip;
          S()
          })
      }
      else if(u.tab===4){
        rowsCard(7);
        sw('Kamera arka planı',v.pass,()=>{
          v.pass=!v.pass;
          S();
          if(v.pass)Pass.enable();
          else Pass.disable()
          });
        const camSw=()=>{
          v.hcam=v.hcam==='user'?'environment':'user';
          S();
          Hand.on?Hand.restart():Pass.refresh()
        };
        step('Kamera',v.hcam==='user'?'Ön':'Arka',camSw,camSw);
        sw('Tam ekran',!!document.fullscreenElement,()=>Sys.fs());
        sw('Ekranı açık tut',v.awake,()=>{
          v.awake=!v.awake;
          S();
          Sys.awake(v.awake)
          });
        sw('Enerji tasarrufu',v.saver,()=>{
          v.saver=!v.saver;
          S()
          });
        step('Panel boyutu',Math.round(v.pscale*100)+'%',()=>{
          v.pscale=Math.max(.7,+(v.pscale-.1).toFixed(1));
          S();
          WM.layout(v.layout,true)
          },()=>{
          v.pscale=Math.min(1.3,+(v.pscale+.1).toFixed(1));
          S();
          WM.layout(v.layout,true)
          });
        step('Panel düzeni',WM.names[v.layout],()=>WM.layout((v.layout+3)%4),()=>WM.layout((v.layout+1)%4))
      }
      else{
        card(c,x0,y,w,350);
        txt(c,'Verilerin',x0+22,y+40,24,'#fff',30,true);
        txt(c,'• Ayarlar ve eklediğin uygulamalar yalnızca bu cihazda saklanır.\n• Kamera, ancak "El takibi"ni açıp onay verirsen çalışır;\n  görüntü cihazdan çıkmaz.\n• Sensör, yalnızca düğmeye basınca ve izin verirsen kullanılır.\n• Özel duvar kağıdı bu cihazda saklanır.',x0+22,y+80,20,'#cfe0ff',64);
        B(x0+22,y+272,218,56,'Verileri temizle',()=>{
          Storage.clear();
          try{
            localStorage.removeItem('nexus.apps');
            localStorage.removeItem('nexus.open')
          }catch(e){}
          HandCache.clear();
          WebApps.list=[];
          Object.assign(v,DEF);
          Renderer.scale=1;
          Scene.setWP(0);
          Settings.apply();
          WM.layout(v.layout,true)
          });
        B(x0+22+230,y+272,218,56,'Ayarları kopyala',()=>{
          navigator.clipboard?navigator.clipboard.writeText(JSON.stringify(v)).then(()=>Diag.toast('Ayarlar kopyalandı','var(--ok)'),()=>Diag.toast('Kopyalanamadı','var(--err)')):Diag.toast('Pano API\'si yok','var(--err)')
          });
        B(x0+22+460,y+272,218,56,'Ayarları yükle',()=>{
          if(XR.session){
            Diag.toast('VR içinde metin girişi yok','var(--warn)');
            return
          }
          const t=prompt('Kopyaladığın ayar metnini yapıştır:');
          if(!t)return;
          try{
            const o=JSON.parse(t);
            Object.keys(DEF).forEach(k=>{
              if(k in o&&typeof o[k]===typeof DEF[k])v[k]=o[k]
              });
            if(v.wp===-1)v.wp=0;
            Renderer.scale=1;
            Scene.setWP(Math.max(0,v.wp));
            S();
            WM.layout(v.layout,true);
            Diag.toast('Ayarlar yüklendi','var(--ok)')
          }catch(e){
            Diag.toast('Geçersiz ayar metni','var(--err)')
          }
          })
      }
    }
    }),
  clock:()=>({id:'clock',icon:'pulse',title:'Saat',span:.6,h:1.2,live:true,
    render(c,W,H,B,u){
      const v=Settings.v,tab=u.tab||0,n=Date.now(),p2=x=>String(x).padStart(2,'0'),mmss=ms=>{const t=Math.floor(ms/1000);return p2(Math.floor(t/60))+':'+p2(t%60)};
      const bw=(W-40-16)/3;
      ['Saat','Kronometre','Zamanlayıcı'].forEach((t,k)=>{B(20+k*(bw+8),TB+14,bw,48,'',o=>{u.tab=k;WM.paint(o)},tab===k,null,'ghost',t);c.fillStyle=tab===k?'#16171a':'#d2d5db';c.font='19px system-ui';c.textAlign='center';c.fillText(t,20+k*(bw+8)+bw/2,TB+45)});
      card(c,20,TB+80,W-40,H-TB-100);
      const cx=W/2,bt=(x,y,w2,l,fn,on)=>{B(x,y,w2,52,'',fn,on,null,'pill',l);c.fillStyle='#fff';c.font='20px system-ui';c.textAlign='center';c.fillText(l,x+w2/2,y+34)};
      c.textAlign='center';c.fillStyle='#fff';
      const big=(t)=>{c.font='700 '+Math.min(110,W/(t.length*.62))+'px system-ui';c.fillText(t,cx,TB+230)};
      const by=TB+330,bb=(W-80)/2;
      if(tab===0){
        const d=new Date(),h=v.h24?d.getHours():(d.getHours()%12||12);
        big(p2(h)+':'+p2(d.getMinutes())+(v.ssec?':'+p2(d.getSeconds()):'')+(v.h24?'':(d.getHours()<12?' ÖÖ':' ÖS')));
        c.font='24px system-ui';c.fillStyle='#a9b6d3';c.fillText(d.toLocaleDateString('tr-TR',{weekday:'long',day:'numeric',month:'long',year:'numeric'}),cx,TB+290)
      }else if(tab===1){
        const s=u.sw=u.sw||{a:0,r:0,s:0},el=s.r?n-s.s+s.a:s.a;
        big(mmss(el)+'.'+Math.floor(el%1000/100));
        bt(30,by,bb,s.r?'Durdur':'Başlat',o=>{if(s.r){s.a+=Date.now()-s.s;s.r=0}else{s.s=Date.now();s.r=1}WM.paint(o)},s.r);
        bt(50+bb,by,bb,'Sıfırla',o=>{s.a=0;s.r=0;WM.paint(o)})
      }else{
        const t=u.tm=u.tm||{s:(v.tmin||5)*60,r:0,e:0},rem=t.r?Math.max(0,t.e-n):t.s*1000;
        if(t.r&&rem<=0){t.r=0;Diag.toast('⏰ Zamanlayıcı bitti','var(--ok)',8000);Diag.say('Zamanlayıcı bitti')}
        big(mmss(rem));
        bt(30,TB+270,bb,'− 1 dk',o=>{if(!t.r){t.s=Math.max(60,t.s-60);WM.paint(o)}});bt(50+bb,TB+270,bb,'+ 1 dk',o=>{if(!t.r){t.s+=60;WM.paint(o)}});
        bt(30,by+20,bb,t.r?'Durdur':'Başlat',o=>{if(t.r){t.s=Math.max(1,Math.round((t.e-Date.now())/1000));t.r=0}else{t.e=Date.now()+t.s*1000;t.r=1}WM.paint(o)},t.r);
        bt(50+bb,by+20,bb,'Sıfırla',o=>{t.r=0;t.s=(Settings.v.tmin||5)*60;WM.paint(o)})
      }
      c.textAlign='left'
    }}),
  calc:()=>({id:'calc',icon:'grid',title:'Hesap Makinesi',span:.5,h:1.15,
    render(c,W,H,B,u){
      u.d=u.d||'0';
      const dec=Settings.v.cdec,fm=x=>String(parseFloat((+x).toFixed(dec))),ex=(a,b,o)=>o==='+'?a+b:o==='−'?a-b:o==='×'?a*b:o==='÷'?(b===0?NaN:a/b):b;
      const press=(k,o)=>{
        if(u.err&&k!=='C')return;
        if(/\d/.test(k)){u.d=(u.nw||u.d==='0')?k:u.d+k;u.nw=0}
        else if(k==='.'){if(u.nw){u.d='0.';u.nw=0}else if(!u.d.includes('.'))u.d+='.'}
        else if(k==='C'){u.d='0';u.a=null;u.op=null;u.nw=0;u.err=0}
        else if(k==='⌫'){u.d=u.d.length>1&&!u.nw?u.d.slice(0,-1):'0';if(u.d==='-')u.d='0'}
        else if(k==='±'){u.d=u.d==='0'?'0':(u.d[0]==='-'?u.d.slice(1):'-'+u.d)}
        else if(k==='%'){u.d=fm(parseFloat(u.d)/100)}
        else{
          const b=parseFloat(u.d);
          if(u.op&&!u.nw){const r=ex(u.a,b,u.op);if(!isFinite(r)){u.d='Hata';u.err=1;u.a=null;u.op=null;WM.paint(o);return}u.a=r;u.d=fm(r)}else u.a=b;
          u.op=k==='='?null:k;u.nw=1
        }
        WM.paint(o)
      };
      card(c,20,TB+14,W-40,110);
      if(u.op&&u.a!=null)txt(c,fm(u.a)+' '+u.op,44,TB+50,20,'#a9b6d3',24);
      c.textAlign='right';c.fillStyle='#fff';c.font='700 '+Math.min(54,(W-80)/(Math.max(6,u.d.length)*.6))+'px system-ui';c.fillText(u.d,W-44,TB+104);c.textAlign='left';
      const K=['C','±','%','÷','7','8','9','×','4','5','6','−','1','2','3','+','0','.','⌫','='],gw=(W-40-3*10)/4,gy=TB+138,gh=Math.min(72,(H-gy-20-4*10)/5);
      K.forEach((k,i)=>{const x=20+(i%4)*(gw+10),y=gy+Math.floor(i/4)*(gh+10),op=/[÷×−+=]/.test(k);B(x,y,gw,gh,'',o=>press(k,o),op,null,'pill','Tuş '+k);c.fillStyle=op?'#16171a':'#fff';c.font='26px system-ui';c.textAlign='center';c.fillText(k,x+gw/2,y+gh/2+9)});
      c.textAlign='left'
    }}),
  notes:()=>({id:'notes',icon:'folder',title:'Notlar',span:.9,h:1.3,
    render(c,W,H,B,u){
      const K='nexus.notes';
      if(!u.L){try{u.L=JSON.parse(localStorage.getItem(K)||'[]')}catch(e){u.L=[]}u.i=0}
      const sv=()=>{try{localStorage.setItem(K,JSON.stringify(u.L))}catch(e){Diag.toast('Notlar kaydedilemedi','var(--warn)')}};
      const ask=(t,init,fn)=>XR.session?Diag.toast('VR içinde metin girişi yok','var(--warn)'):KBD.ask(t,init,fn);
      const lw=250;
      B(20,TB+14,lw,52,'',o=>ask('Yeni not','',t=>{t=(t||'').trim();if(t){u.L.unshift(t);u.i=0;sv();WM.paint(o)}}),false,null,'pill','Yeni not');
      c.fillStyle='#fff';c.font='20px system-ui';c.textAlign='center';c.fillText('+ Yeni not',20+lw/2,TB+48);c.textAlign='left';
      const rows=Math.max(1,Math.floor((H-TB-90)/56));
      u.L.slice(0,rows).forEach((t,k)=>{const y=TB+78+k*56;B(20,y,lw,50,'',o=>{u.i=k;WM.paint(o)},u.i===k,null,'ghost','Not '+(k+1));txt(c,t.replace(/\s+/g,' '),36,y+33,19,u.i===k?'#16171a':'#d2d5db',20)});
      const x0=20+lw+14,w=W-x0-20;card(c,x0,TB+14,w,H-TB-34);
      const t=u.L[u.i];
      if(!t){txt(c,'Not yok. “Yeni not” ile ekle.',x0+22,TB+60,22,'#a9b6d3',40);return}
      const fs=Settings.v.nfs,mc=Math.max(10,Math.floor((w-44)/(fs*.55))),words=t.split(/\s+/),lines=[];let cur='';
      words.forEach(wd=>{while(wd.length>mc){if(cur){lines.push(cur);cur=''}lines.push(wd.slice(0,mc));wd=wd.slice(mc)}if((cur+' '+wd).trim().length>mc){lines.push(cur);cur=wd}else cur=(cur+' '+wd).trim()});if(cur)lines.push(cur);
      const maxL=Math.floor((H-TB-34-110)/(fs*1.5));
      lines.slice(0,maxL).forEach((l,k)=>txt(c,l,x0+22,TB+56+k*fs*1.5,fs,'#fff',mc+4));
      const by=H-20-56,bw=(w-44-10)/2;
      B(x0+22,by,bw,48,'',o=>ask('Notu düzenle',t,n=>{n=(n||'').trim();if(n){u.L[u.i]=n;sv();WM.paint(o)}}),false,null,'pill','Düzenle');
      B(x0+32+bw,by,bw,48,'',o=>{u.L.splice(u.i,1);u.i=Math.max(0,Math.min(u.i,u.L.length-1));sv();WM.paint(o)},false,null,'pill','Sil');
      c.fillStyle='#fff';c.font='20px system-ui';c.textAlign='center';c.fillText('Düzenle',x0+22+bw/2,by+32);c.fillText('Sil',x0+32+bw+bw/2,by+32);c.textAlign='left'
    }}),
  tasks:()=>({id:'tasks',icon:'layout',title:'Görevler',span:.7,h:1.1,live:true,
    render(c,W,H,B,u){
      const L=WM.panels.filter(p=>p.userData&&p.userData.title),rows=Math.max(1,Math.floor((H-TB-80)/64));
      txt(c,L.length+' pencere açık',24,TB+44,22,'#a9b6d3',30);
      L.slice(0,rows).forEach((p,k)=>{
        const y=TB+62+k*64,me=p.userData===u;
        card(c,20,y,W-40,56);
        txt(c,p.userData.title+(p.visible?'':' (küçültülmüş)')+(me?' • bu pencere':''),40,y+36,21,'#fff',Math.floor((W-300)/12));
        B(W-200,y+6,80,44,'',()=>{p.visible?WM.focus(p):WM.spawn(p.userData.id)},false,null,'pill','Öne getir '+p.userData.title);
        B(W-110,y+6,80,44,'',()=>{if(!me)WM.close(p)},false,null,'pill','Kapat '+p.userData.title);
        c.fillStyle=me?'#6b7899':'#fff';c.font='18px system-ui';c.textAlign='center';c.fillText('Aç',W-160,y+34);c.fillText('Kapat',W-70,y+34);c.textAlign='left'
      })
    }}),
  perf:()=>({
    id:'perf',
    icon:'chart',
    title:'Performance Monitor',
    span:.6,
    h:1.2,
    live:true,
    render(c,W,H){
      card(c,20,TB+16,W-40,208);
      txt(c,'Kare hızı',44,TB+54,22,'#a9b6d3',20);
      txt(c,Perf.fps.toFixed(0),44,TB+128,84,'#fff',6,true);
      txt(c,'FPS',200,TB+128,26,'#a9b6d3',6);
      const hs=Perf.hist,gx=290,gy=TB+40,gw=W-gx-44,gh=150;
      c.strokeStyle=ACC[Settings.v.acc];
      c.lineWidth=3;
      c.lineJoin='round';
      if(hs.length>1){
        c.beginPath();
        hs.forEach((f,k)=>{
          const px=gx+k/59*gw,py=gy+gh-clamp(f/70,0,1)*gh;
          k?c.lineTo(px,py):c.moveTo(px,py)
          });
        c.stroke()
      }
      const st=[['Sahne nesnesi',Scene.count()],['Paneller',WM.panels.length],['Piksel oranı',Renderer.r.getPixelRatio().toFixed(2)],['Kalite',['Düşük','Orta','Yüksek'][Settings.v.quality]],['Çözünürlük',Math.round(Renderer.scale*100)+'%'],['Render',XR.session?'WebXR':'Önizleme'],['Cihaz',(Dev.phone?'Telefon':'Tablet')+' · seviye '+Dev.tier+' · '+Dev.hz+' Hz'+(Dev.ram?' · '+Dev.ram+' GB':'')],['Sensör',Cam.statusText()+(Dev.sensor?' ('+({rv:'rotasyon vektörü',am:'ivme+pusula',acc:'yalnız ivmeölçer',none:'yok'}[Dev.sensor]||Dev.sensor)+')':'')]];
      const cw=(W-40-14)/2;
      st.forEach((s,k)=>{
        const x=20+(k%2)*(cw+14),y=TB+240+Math.floor(k/2)*100;
        card(c,x,y,cw,86);
        txt(c,s[0],x+20,y+32,20,'#a9b6d3',22);
        txt(c,s[1],x+20,y+68,30,'#fff',14,true)
        })
    }
    }),
  device:()=>({
    id:'device',
    icon:'device',
    title:'Device Information',
    span:.75,
    h:1.35,
    live:true,
    render(c,W,H){
      card(c,20,TB+14,W-40,H-TB-34);
      drawGroups(c,Diag.groups(),44,TB+26,(W-40-48-24)/2,34,H-30,2)
    }
    }),
  diag:()=>({
    id:'diag',
    icon:'pulse',
    title:'Diagnostics',
    span:.95,
    h:1.5,
    live:true,
    render(c,W,H,B){
      card(c,20,TB+14,W-40,H-TB-110);
      drawGroups(c,Diag.groups(),44,TB+26,(W-40-48-24)/2,32,H-110,2);
      B(W-300,H-80,280,58,'Raporu kopyala',()=>{
        navigator.clipboard?navigator.clipboard.writeText(Diag.report()).then(()=>Diag.toast('Rapor kopyalandı'),()=>Diag.toast('Kopyalanamadı','var(--err)')):Diag.toast('Pano API\'si yok','var(--err)')
        },false,'folder')
    }
    }),
  scene:()=>({
    id:'scene',
    icon:'cube',
    title:'3D Scene Explorer',
    span:.75,
    h:1.35,
    live:true,
    render(c,W,H,B){
      txt(c,'Nesne: '+Scene.count()+'  •  Panel: '+WM.panels.length+'  •  Ölçek: '+Math.round(Renderer.scale*100)+'%',28,TB+40,21,'#a9b6d3',70);
      let y=TB+62;
      WM.panels.forEach(p=>{
        const u=p.userData;
        if(u.dock||u.kbd||y>H-80)return;
        card(c,20,y,W-40,66,16);
        rr(c,34,y+11,44,44,12);
        c.fillStyle=p.visible?ACC[Settings.v.acc]:'#2a3558';
        c.fill();
        ICN(c,u.icon,56,y+33,11,'#fff');
        txt(c,u.title+(p.visible?'':'  (küçültülmüş)'),92,y+42,23,'#fff',34);
        B(W-150,y+10,56,46,'',()=>{
          p.visible=true;
          u.min=false;
          if(u.id==='win7simu')W7Desk.show();
          WM.focus(p);
          u.ang=0;
          WM.place(p)
          },false,'eye','pill');
        B(W-86,y+10,56,46,'',()=>{
          u.sf=1;
          u.max=false;
          u.y=1.9;
          WM.build(p)
          },false,'reset','pill');
        y+=76
        })
    }
    }),
  help:()=>({
    id:'help',
    icon:'help',
    title:'Help Center',
    span:.8,
    h:1.45,
    render(c,W,H){
      const cw=(W-40-14)/2,sec=(x,y,w,h,t,L)=>{
        card(c,x,y,w,h);
        txt(c,t,x+22,y+40,24,'#fff',30,true);
        L.forEach((l,k)=>{
          c.fillStyle=ACC[Settings.v.acc];
          c.beginPath();
          c.arc(x+30,y+78+k*34,4,0,6.3);
          c.fill();
          txt(c,l,x+46,y+85+k*34,20,'#cfe0ff',34)
          })
      };
      sec(20,TB+14,cw,H-TB-34,'Bakış ve pencereler',['Boş alanı sürükle: 360° dön','Başlığı sürükle: paneli taşı','Çarpı: kapat, kare: büyüt','Çizgi: küçült (dock\'tan aç)','Artı / eksi: boyutu değiştir','Tekerlek: yakınlaş','W A S D / oklar: bak','Esc: VR\'dan çık','Tab / Shift+Tab: gez','Enter / Boşluk: seç']);
      sec(20+cw+14,TB+14,cw,(H-TB-34)/2-7,'El takibi',['El ikonu: arka kamera açılır','İşaret parmağı: imleç','Başparmak + işaret: tıkla','Eli kadrajdan çıkarınca bırakır']);
      sec(20+cw+14,TB+14+(H-TB-34)/2+7,cw,(H-TB-34)/2-7,'VR',['HTTPS veya localhost gerekir','Dock\'ta gözlük ikonuna bas','Kontrolcü ışını ile seç ve sürükle'])
    }
    }),
  win7simu:()=>({
    id:'win7simu', icon:'monitor', title:'Windows 7', span:W7Desk.W/W7Desk.R, h:W7Desk.H, R:W7Desk.R, y:W7Desk.Y, ang:0,
    fixedW:W7Desk.W, fixedH:W7Desk.H, deskY:W7Desk.Y,
    cflat:true, curve:false, fixedDesk:true, chrome:false, skin:'win',
    web:{type:'url',url:'https://appassets.androidplatform.net/win7simu.html?vr=1'},
    render(c,W,H,B,u){
      c.clearRect(0,0,W,H);
      c.fillStyle='#0878c9';c.fillRect(0,0,W,H);
      u.rect={x:0,y:0,w:W,h:H};
      txt(c,'Windows 7 yükleniyor…',W/2,H/2,25,'#ffffff',Math.min(W-20,300),true);
    }
  })};

  APPS.qs=()=>({id:'qs',icon:'sliders',title:'Hızlı ayarlar',span:.6,h:1.05,live:true,
    render(c,W,H,B){
      const T=[
        ['El takibi',()=>Hand.on?Hand.stop():Hand.start(),Hand.on,'hand'],
        ['Sensör',()=>Cam.gyro?Cam.disableGyro():Cam.enableGyro(),Cam.gyro,'compass'],
        ['VR',()=>Stereo.toggle(),Stereo.on||!!XR.session,'vr'],
        ['Kamera',()=>{Settings.v.pass=!Pass.bg;Settings.save();if(Settings.v.pass)Pass.enable();else Pass.disable()},Pass.on,'eye'],
        ['Düzen: '+WM.names[Settings.v.layout],()=>WM.layout((Settings.v.layout+1)%4),false,'layout'],
        ['Sıfırla',()=>{Cam.reset();WM.layout(Settings.v.layout,true)},false,'reset']
      ];
      const cols=3,pad=34,gap=20,tw=(W-pad*2-gap*2)/cols,th=(H-24-pad-gap)/2;
      T.forEach((q,i)=>{
        const x=pad+(i%cols)*(tw+gap),y=24+Math.floor(i/cols)*(th+gap);
        const hv=B(x,y,tw,th,'',()=>{q[1]();WM.repaintAll()},false,null,'raw',q[0]);
        rr(c,x,y,tw,th,26);
        c.fillStyle=q[2]?'#e8f0f1':hv?'rgba(255,255,255,.17)':'rgba(255,255,255,.09)';
        c.fill();
        ICN(c,q[3],x+tw/2,y+th*.4,th*.2,q[2]?'#17262a':'#f2f6f7');
        c.fillStyle=q[2]?'#17262a':'#e8eff0';
        c.font='500 19px system-ui,sans-serif';
        c.textAlign='center';
        c.fillText(q[0],x+tw/2,y+th*.82);
        c.textAlign='left'
      })
    }
  });
  /* ---------- Dock ---------- */
