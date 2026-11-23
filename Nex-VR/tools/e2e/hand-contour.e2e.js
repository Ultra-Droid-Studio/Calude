#!/usr/bin/env node
/* Stage 74 — gerçek tarayıcı (Chromium + WebGL) uçtan uca doğrulama.
   Çalıştır:  THREE_JS=/yol/three.min.js node tools/e2e/hand-contour.e2e.js [çıktı_klasörü]
   (three.min.js r128 APK derlemesinde indirilir; burada yolu verilir. Playwright gerekir.)
   Denetlenenler:
     1. Uygulama açılıyor, VR masaüstüne giriliyor, WebGL çiziyor.
     2. Native biçimli sentetik el mesajları (K blokları + F,1) → iki el için parmak konturları çiziliyor;
        kontur siyah, parmak İÇİ boş (arka plan görünür), parmaklar ayrı halkalar.
     3. Tek parmak bükülünce yalnızca o parmağın konturu kısalıyor (bağımsız eklem hareketi).
     4. El mesajı kesilince kontur ~150 ms içinde kayboluyor (eski kontur ekranda kalmıyor).
     5. Performans monitörü açılıyor ve ölçüm satırlarını gösteriyor.
     6. Goril oyunu: NPC'ler oluşuyor, dolaşıyor; fizik/NPC süreleri ölçülüyor.
   Çıktı: ekran görüntüleri (PNG) ve özet. */
const http=require('http'),fs=require('fs'),path=require('path');
let chromium;try{({chromium}=require('playwright'))}catch(e){console.log('ATLANDI: playwright yok');process.exit(0)}
const THREE_JS=process.env.THREE_JS;
if(!THREE_JS||!fs.existsSync(THREE_JS)){console.log('ATLANDI: THREE_JS (three.min.js r128) yolu verilmedi');process.exit(0)}
const OUT=process.argv[2]||path.join(__dirname,'out');fs.mkdirSync(OUT,{recursive:true});
const ASSETS=path.join(__dirname,'../../app/src/main/assets');
const MIME={'.html':'text/html; charset=utf-8','.js':'text/javascript','.png':'image/png','.jpg':'image/jpeg','.glb':'model/gltf-binary'};
const srv=http.createServer((q,r)=>{
  const u=decodeURIComponent(q.url.split('?')[0]),f=u==='/three.min.js'?THREE_JS:path.join(ASSETS,u==='/'?'index.html':u);
  if(!f.startsWith(ASSETS)&&f!==THREE_JS){r.writeHead(403);return r.end()}
  fs.readFile(f,(e,b)=>{if(e){r.writeHead(404);return r.end()}r.writeHead(200,{'content-type':MIME[path.extname(f)]||'application/octet-stream'});r.end(b)})
});
let fails=0;const ok=(c,m,x)=>{console.log((c?'PASS ':'FAIL ')+m+(x!==undefined?'  ['+x+']':''));if(!c)fails++};

/* sentetik el (C++ testindeki ile aynı geometri): bilek (cx,cy), avuç boyu s, bükülmeler */
function makeHand(cx,cy,s,curl,aspect){
  const p=new Array(63).fill(0),set=(i,x,y,z)=>{p[i*3]=cx+x/aspect;p[i*3+1]=cy+y;p[i*3+2]=z};
  set(0,0,0,0);
  const bX=[.32,.22,0,-.2,-.38],bY=[-.28,-.95,-1,-.95,-.85],L=[[.32,.28,.24],[.45,.28,.22],[.5,.32,.24],[.46,.3,.22],[.36,.24,.2]];
  for(let f=0;f<5;f++){let x=bX[f]*s,y=bY[f]*s,z=0;const b=1+f*4;set(b,x,y,z);const dx=f===0?.7:0,dy=f===0?-.7:-1,th=curl[f]*(f===0?.55:1.25);let a=0;
    for(let j=0;j<3;j++){a+=th;x+=dx*Math.cos(a)*L[f][j]*s;y+=dy*Math.cos(a)*L[f][j]*s;z+=-Math.sin(a)*L[f][j]*s;set(b+1+j,x,y,z)}}
  return p}
const n4=v=>(Math.round(v*1e4)/1e4).toFixed(4);
function msg(hands){
  let m='R|30.0|8.0|'+hands.length;
  hands.forEach(h=>{m+='|'+h.label+',0.950,'+h.p.map(n4).join(',')});
  hands.forEach((h,i)=>{const k=new Array(25).fill(0);k[0]=.95;k[1]=.2;for(let f=0;f<5;f++)k[2+f]=h.curl[f];m+='|K,'+i+','+(1|(h.label==='Right'?256:0))+','+k.map(v=>v.toFixed(3)).join(',')});
  return m+'|F,1'}

(async()=>{
  await new Promise(r=>srv.listen(0,'127.0.0.1',r));
  const url='http://127.0.0.1:'+srv.address().port+'/index.html';
  const br=await chromium.launch({args:['--use-gl=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
  const pg=await br.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
  const errs=[];pg.on('pageerror',e=>errs.push(String(e)));pg.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
  await pg.goto(url);
  await pg.waitForFunction(()=>window.NEXUS&&NEXUS.Renderer&&NEXUS.Renderer.r,null,{timeout:30000});
  await pg.waitForSelector('[data-a=start]',{timeout:15000});
  await pg.click('[data-a=start]');
  await pg.waitForFunction(()=>NEXUS.App.entered,null,{timeout:20000});
  await pg.waitForTimeout(1500);
  ok(true,'uygulama açıldı ve VR masaüstüne girildi');
  // Masaüstü pencereleri kontur testini kapatmasın: hepsini gizle (arka plan = duvar kâğıdı)
  await pg.evaluate(()=>{NEXUS.WM.panels.forEach(p=>p.visible=false);NEXUS.Settings.v.hdraw=true;NEXUS.Settings.v.hview='kontur';NEXUS.Settings.v.hmenu=false;document.getElementById('toast').style.display='none';NEXUS.Scene.dirty=true});
  await pg.waitForTimeout(300);
  const bg64=(await pg.screenshot({path:path.join(OUT,'0-masaustu.png')})).toString('base64');

  /* el takibini native modda "açık" duruma getir (kamera yok; mesajlar elle beslenir) */
  await pg.evaluate(()=>{const H=NEXUS.Hand;H.initF();H.on=true;H.native=true;H.workerReady=true;H.mirror=false;H.hitRC=new THREE.Raycaster()});
  const A=1280/720;
  const open=[0,0,0,0,0],R={label:'Right',p:makeHand(.62,.78,.3,open,A),curl:open},Lh={label:'Left',p:makeHand(.3,.8,.26,[0,0,0,0,0],A),curl:open};
  /* mesajlar sayfa içinde 30 Hz zamanlayıcıyla beslenir (native sonuç akışı gibi); ekran görüntüsü sırasında da akış sürer */
  const startFeed=async hands=>pg.evaluate(m=>{clearInterval(window.__feed);window.__feed=setInterval(()=>NEXUS.Hand.onNative(m),33)},msg(hands));
  const stopFeed=async()=>pg.evaluate(()=>clearInterval(window.__feed));
  const feed=async(hands,ms)=>{await startFeed(hands);await pg.waitForTimeout(ms)};
  await feed([R,Lh],700);
  const shot=async name=>{const b=await pg.screenshot({path:path.join(OUT,name)});return b.toString('base64')};
  const b64=await shot('1-iki-el-kontur.png');
  const st=await pg.evaluate(()=>{const C=NEXUS.HandContour;return{ok:C.ok,vis:C.m.map(x=>x.vis),a:C.m.map(x=>+x.a.toFixed(2)),kin:NEXUS.Hand.slots.map(s=>!!s.kin),nf:NEXUS.Hand.slots.map(s=>s.on)}});
  ok(st.ok&&st.vis[0]&&st.vis[1],'iki el için kontur görünür',JSON.stringify(st));
  ok(st.kin.every(Boolean),'K blokları (native özellikler) yuvalara işlendi');

  /* piksel analizi: parmak kenarı siyah, parmak içi boş (arka plan) */
  /* Görüntüler sayfada çözülür; her örnek noktada hem el görüntüsü hem el YOKKEN alınan arka plan okunur.
     İç boşluk = parmak ortasındaki piksel arka planla aynı (dolgu yok). Kontur = kenarda arka plandan çok koyu piksel. */
  const LUM=`const dec=async(b,W,H)=>{const img=new Image();img.src='data:image/png;base64,'+b;await img.decode();const c=document.createElement('canvas');c.width=W;c.height=H;const x=c.getContext('2d');x.drawImage(img,0,0);const d=x.getImageData(0,0,W,H).data;return (px,py)=>{px=Math.round(px);py=Math.round(py);const i=(py*W+px)*4;return .2126*d[i]+.7152*d[i+1]+.0722*d[i+2]}};`;
  const pix=await pg.evaluate(new Function('a',LUM+`return (async({b64,bg64,hands,W,H})=>{
    const lum=await dec(b64,W,H),bgl=await dec(bg64,W,H),res=[];
    for(const h of hands){
      const P=i=>[h.p[i*3]*W,h.p[i*3+1]*H],L=Math.hypot(P(9)[0]-P(0)[0],P(9)[1]-P(0)[1]);
      for(const [a,b,rk] of [[5,6,.103],[9,10,.105],[13,14,.099],[17,18,.088]]){
        const A=P(a),B=P(b),mx=(A[0]+B[0])/2,my=(A[1]+B[1])/2,dx=B[0]-A[0],dy=B[1]-A[1],l=Math.hypot(dx,dy),nx=-dy/l,ny=dx/l,r=rk*L;
        let edge=255,eb=0;for(let o=-4;o<=4;o++)for(const sg of [1,-1]){const ex=mx+sg*nx*(r+o),ey=my+sg*ny*(r+o),v=lum(ex,ey);if(v<edge){edge=v;eb=bgl(ex,ey)}}
        res.push({inner:Math.round(lum(mx,my)),innerBg:Math.round(bgl(mx,my)),edge:Math.round(edge),edgeBg:Math.round(eb)})
      }
    }
    return res})(a)`),{b64,bg64,hands:[R,Lh],W:1280,H:720});
  const darkEdges=pix.filter(p=>p.edge<p.edgeBg*.45&&p.edge<70).length,hollow=pix.filter(p=>Math.abs(p.inner-p.innerBg)<14).length;
  ok(darkEdges>=7,'parmak kenarlarında siyah kontur ('+darkEdges+'/8)',JSON.stringify(pix.map(p=>[p.edge,p.edgeBg])));
  ok(hollow>=7,'parmak içi boş: parmak ortasındaki piksel arka planla aynı ('+hollow+'/8)',JSON.stringify(pix.map(p=>[p.inner,p.innerBg])));

  /* tek parmak bükülmesi: işaret parmağı bükülünce ucu (8) bölgesinde kontur kalmamalı, orta parmak aynen durmalı */
  const R2={label:'Right',p:makeHand(.62,.78,.3,[0,1,0,0,0],A),curl:[0,1,0,0,0]};
  const tipOld=[R.p[8*3]*1280,R.p[8*3+1]*720],midTip=[R.p[12*3]*1280,R.p[12*3+1]*720];
  await feed([R2,Lh],500);
  const b64b=await shot('2-isaret-parmagi-bukuk.png');
  const chk=await pg.evaluate(new Function('a',LUM+`return (async({b64,bg64,pts,W,H})=>{const lum=await dec(b64,W,H),bgl=await dec(bg64,W,H);
    return pts.map(([px,py])=>{let m=0;for(let dy=-12;dy<=12;dy++)for(let dx=-12;dx<=12;dx++)m=Math.max(m,bgl(px+dx,py+dy)-lum(px+dx,py+dy));return Math.round(m)})})(a)`),{b64:b64b,bg64,pts:[tipOld,midTip],W:1280,H:720});
  ok(chk[0]<20&&chk[1]>60,'işaret parmağı bükülünce eski uç bölgesi boş, orta parmak ucu konturu duruyor (arka plandan en büyük koyulaşma)',JSON.stringify(chk));

  /* el kaybı: mesaj kesilince kontur söner */
  await stopFeed();
  const tLost=Date.now();let gone=false,ms=0;
  for(let i=0;i<40&&!gone;i++){await pg.waitForTimeout(25);gone=await pg.evaluate(()=>NEXUS.HandContour.m.every(x=>!x.vis||x.a<.03));ms=Date.now()-tLost}
  ok(gone&&ms<600,'el kaybolunca kontur söndü',ms+' ms');
  await shot('3-el-kayboldu.png');

  /* performans monitörü */
  await pg.evaluate(()=>{NEXUS.Settings.v.pdbg=true;NEXUS.Settings.apply()});
  await feed([R,Lh],1200);
  const hud=await pg.evaluate(()=>{const e=document.getElementById('nxhud');return e?e.textContent:''});
  ok(/FPS/.test(hud)&&/CPU kare/.test(hud)&&/El 2 güven/.test(hud)&&/darboğaz/.test(hud),'performans monitörü ölçümleri gösteriyor');
  console.log(hud.split('\n').map(l=>'   | '+l).join('\n'));
  await shot('4-performans-monitoru.png');
  const prof=await pg.evaluate(()=>{const P=NEXUS.Prof;return{frames:P.frames,cpu:+P.cpuAvg.toFixed(2),hand:+P.avg[P.HAND].toFixed(3),render:+P.avg[P.RENDER].toFixed(2),dt:+P.dtAvg.toFixed(1)}});
  ok(prof.frames>30&&prof.render>0,'kare profilleyici çalışıyor',JSON.stringify(prof));

  /* goril oyunu + NPC */
  await stopFeed();
  await pg.evaluate(()=>{const H=NEXUS.Hand;H.on=false;H.native=false;NEXUS.Settings.v.pdbg=true;window.Gorilla.enter();window.Gorilla.setState('play')});
  await pg.waitForTimeout(500);
  const n0=await pg.evaluate(()=>window.Gorilla.npc?window.Gorilla.npc.list.map(n=>[n.x,n.z]):null);
  ok(Array.isArray(n0)&&n0.length>=4,'goril dünyasında NPC\'ler oluştu',n0&&n0.length);
  await pg.waitForTimeout(6000);
  const n1=await pg.evaluate(()=>window.Gorilla.npc.list.map(n=>[n.x,n.z,n.st]));
  const moved=n1.filter((n,i)=>Math.hypot(n[0]-n0[i][0],n[1]-n0[i][1])>.3).length;
  ok(moved>=1,'NPC\'ler dolaşıyor (6 sn içinde hareket eden)',moved+'/'+n1.length);
  const gs=await pg.evaluate(()=>window.Gorilla.stats());ok(/fizik/.test(gs)&&/NPC/.test(gs),'goril fizik/NPC süreleri ölçülüyor',gs);
  // bir NPC'ye doğru bak ve ekran görüntüsü al
  await pg.evaluate(()=>{const G=window.Gorilla,b=G.sim.body,n=G.npc.list.reduce((a,c)=>Math.hypot(c.x-b.x,c.z-b.z)<Math.hypot(a.x-b.x,a.z-b.z)?c:a);
    b.x=n.x+Math.sin(0)*0;b.z=n.z+4;G.N.Cam.yaw=0;G.N.Cam.pitch=-.12});
  await pg.waitForTimeout(400);
  await shot('5-goril-npc.png');
  ok(!errs.filter(e=>!/favicon|net::|Failed to load resource|mediapipe|hand_landmarker/i.test(e)).length,'sayfa hatası yok',errs.slice(0,3).join(' | '));
  await br.close();srv.close();
  console.log(fails?('\n'+fails+' BAŞARISIZ'):'\nUÇTAN UCA TÜMÜ GEÇTİ');process.exit(fails?1:0)
})().catch(e=>{console.error('İSTİSNA',e);process.exit(1)});
