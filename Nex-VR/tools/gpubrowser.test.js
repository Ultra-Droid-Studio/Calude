/* Stage 27 — GPU tarayıcı JS mantığı testi.
   index.html'deki GERÇEK BF nesnesini çıkarıp sahte AndroidBridge / Image / tuval ile çalıştırır. */
const fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
let fails=0;const ok=(c,m)=>{if(!c){fails++;console.log('FAIL:',m)}else console.log('ok  :',m)};
const cut=(a,b)=>{const i=html.indexOf(a);if(i<0)throw new Error('bulunamadı: '+a.slice(0,50));const j=html.indexOf(b,i);if(j<0)throw new Error('bitiş yok: '+b.slice(0,50));return html.slice(i,j)};
const bfSrc=cut('  const BF={','  window.__nxGpu=');

const calls=[],draws=[],imgs=[];
let gpuAnswer=true;
class FakeImage{constructor(){imgs.push(this)}decode(){return Promise.resolve()}}
const surface={getContext:()=>({save(){},beginPath(){},rect(){},clip(){},drawImage(i,x,y,w,h){draws.push([i,x,y,w,h])},restore(){}})};
const mesh={visible:true,userData:{id:'browser',cv:Object.assign({width:1024,height:640},surface),tex:{needsUpdate:false}}};
const ctx={
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),Math,Image:FakeImage,Promise,
  NX_T:'tok',Settings:{v:{desk:false}},Diag:{toast(){},log(){}},
  BR:{show:true,menu:false,rect:{x:8,y:60,w:1000,h:560},native(){}},
  Scene:{dirty:false},XR:{session:null},WM:{panels:[mesh],paint(){}},
  AndroidBridge:{
    create:(id,u,t)=>{calls.push(['create',id]);return true},
    navigate:(id,u)=>calls.push(['navigate',id,u]),
    isGpu:(id)=>gpuAnswer,setGpu:(on)=>calls.push(['setGpu',on]),
    gpuSize:(id,w,h,cw)=>calls.push(['gpuSize',id,w,h,cw]),
    prepareGazeView:(id,w,h)=>calls.push(['prepare',id,w,h]),
    setRect2:(id,x,y,w,h,vis)=>calls.push(['rect',id,vis]),
    snap:(id)=>calls.push(['snap',id]),snap2:(id)=>calls.push(['snap2',id])
  },
  performance:{now:()=>1000},window:null
};
ctx.window=ctx;vm.createContext(ctx);
vm.runInContext(bfSrc.replace('  const BF={','var BF={'),ctx);
const BF=()=>vm.runInContext('BF',ctx);
const sleep=()=>new Promise(r=>setTimeout(r,0));
const n=name=>calls.filter(c=>c[0]===name);
const clear=()=>{calls.length=0;draws.length=0;imgs.length=0};

(async()=>{
  /* 1) açılış: GPU yoluna alınır / alınmazsa eski yol */
  BF().BR_=0;
  BF().load('https://example.com');
  ok(n('create').length===1&&BF().gpu.has('nexus-browser'),'tarayıcı GPU yoluna alındı (isGpu=true)');
  ok(n('setGpu').length===1&&n('setGpu')[0][1]===true,'oluşturmadan önce GPU ayarı yerele bildirildi (varsayılan açık)');
  clear();ctx.Settings.v.gpu=false;BF().syncGpu();ok(n('setGpu')[0][1]===false,'Ayarlar kapalıyken yerele false gider');
  ctx.Settings.v.gpu=undefined;

  /* 2) boyut: 64 katı, sınırlı, CSS genişliği, yinelenen çağrı yok, hazırlık (eski yol) çağrılmaz */
  clear();const r={x:8,y:60,w:1000,h:560};
  BF().virtualize('nexus-browser',r);
  const g=n('gpuSize')[0];
  ok(g&&g[2]%64===0&&g[2]>=640&&g[2]<=1600,'görüntü genişliği 64 katı ve sınırlı: '+(g&&g[2])+'×'+(g&&g[3]));
  ok(g&&g[4]>=520&&g[4]<=1100,'CSS genişliği tablet düzeni: '+(g&&g[4]));
  ok(n('prepare').length===0,'GPU sayfasında eski prepareGazeView çağrılmaz');
  BF().virtualize('nexus-browser',r);ok(n('gpuSize').length===1,'aynı boyutta tekrar çağrılmaz');
  BF().virtualize('nexus-browser',{x:8,y:60,w:600,h:400});ok(n('gpuSize').length===2,'boyut değişince yeniden bildirilir');
  ctx.Settings.v.desk=true;BF().virtualize('nexus-browser',{x:8,y:60,w:600,h:400});
  ok(n('gpuSize').length===3&&n('gpuSize')[2][4]===1280,'PC sürümünde CSS genişliği 1280');
  ctx.Settings.v.desk=false;
  const huge=(clear(),BF().virtualSizes.clear(),BF().virtualize('nexus-browser',{x:0,y:0,w:9000,h:4000}),n('gpuSize')[0]);
  ok(huge[2]<=1600&&huge[3]<=1000,'çok büyük panelde üst sınır: '+huge[2]+'×'+huge[3]);

  /* 3) anlık görüntü isteği GPU yolunda yapılmaz (kareler itilir) */
  clear();BF().requestSnapshot('nexus-browser',mesh,r,5000);
  ok(n('snap').length===0&&n('snap2').length===0,'GPU sayfasında poll/snap çağrısı yok');

  /* 4) kare gelişi: adres, çizim, birleştirme (en yeni kare kazanır) */
  clear();BF().gpuFrame('nexus-browser',5);
  ok(imgs.length===1&&imgs[0].src==='/_snap/tok/nexus-browser?n=5','kare /_snap/ adresinden istendi');
  BF().gpuFrame('nexus-browser',6);BF().gpuFrame('nexus-browser',7);BF().gpuFrame('nexus-browser',8);
  ok(imgs.length===1,'meşgulken ara kareler ayrı istenmez');
  await sleep();await sleep();await sleep();
  ok(imgs.length===2&&imgs[1].src.endsWith('?n=8'),'yalnızca en yeni kare (8) sonradan istendi: '+(imgs[1]&&imgs[1].src));
  ok(draws.length>=1&&mesh.userData.tex.needsUpdate===true,'kare panel dokusuna çizildi ve doku güncellendi');
  ok(ctx.Scene.dirty===true,'sahne yeniden çizime işaretlendi');
  ok(BF().snapshotCache.has('nexus-browser'),'son kare önbellekte (yeniden gösterimde boş kalmaz)');

  /* 5) geçersiz / yabancı kareler yok sayılır */
  clear();BF().gpuFrame('webapp-x',3);BF().gpuFrame('nexus-browser',0);BF().gpuFrame('nexus-browser','abc');
  ok(imgs.length===0,'GPU olmayan kimlik / geçersiz sıra numarası yok sayılır');

  /* 6) gizleme: önbellek korunur, yerel duraklatılır */
  clear();BF().hideId('nexus-browser');
  ok(BF().snapshotCache.has('nexus-browser'),'gizlenince son GPU karesi korunur');
  ok(n('rect').length===1&&n('rect')[0][2]===false,'gizlenince yerele görünmez bildirilir (duraklat)');
  ok(!BF().virtualSizes.has('nexus-browser'),'gizlenince boyut anahtarı sıfırlanır (görününce yeniden etkinleşir)');

  /* 7) panel paint koşulları */
  clear();mesh.userData.tex.needsUpdate=false;ctx.BR.menu=true;BF().gpuPaint(mesh);
  ok(draws.length===0&&!mesh.userData.tex.needsUpdate,'menü açıkken kare üstüne çizilmez');
  ctx.BR.menu=false;ctx.BR.show=false;BF().gpuPaint(mesh);ok(draws.length===0,'başlangıç sayfasında kare çizilmez');
  ctx.BR.show=true;mesh.visible=false;BF().gpuPaint(mesh);ok(draws.length===0,'panel gizliyken çizilmez');
  mesh.visible=true;BF().gpuPaint(mesh);ok(draws.length===1,'koşullar uygunken tek çizim');

  /* 8) GPU yolu kapanırsa eski yola düşer; WebView öldüyse yeniden oluşturulur */
  clear();BF().gpuOff('nexus-browser',false);
  ok(!BF().gpu.has('nexus-browser')&&BF().ids.has('nexus-browser'),'gpuOff(false): eski yola düştü, WebView kaydı duruyor');
  BF().virtualize('nexus-browser',r);ok(n('prepare').length===1&&n('gpuSize').length===0,'eski yolda prepareGazeView kullanılır');
  clear();BF().gpu.add('nexus-browser');BF().gpuOff('nexus-browser',true);
  ok(!BF().ids.has('nexus-browser')&&!BF().snapshotCache.has('nexus-browser'),'gpuOff(true): kayıt ve önbellek silindi');
  BF().load('https://example.org');ok(n('create').length===1,'WebView öldükten sonra yeniden oluşturulur');

  /* 9) eski yol (GPU yok): isGpu=false → tarayıcı ve web uygulamaları eskisi gibi */
  clear();BF().gpu.clear();BF().ids.clear();gpuAnswer=false;BF().load('https://example.com');
  ok(!BF().gpu.has('nexus-browser'),'isGpu=false iken GPU yoluna alınmaz');
  BF().virtualSizes.clear();BF().virtualize('webapp-oyun',r);
  ok(n('prepare').length===1&&n('prepare')[0][2]<=960&&n('prepare')[0][3]<=600,'web uygulaması eski sınırlarla (≤960×600) hazırlanır');
  BF().snapshotTimes.clear();BF().requestSnapshot('webapp-oyun',{userData:{id:'web-oyun'}},r,9000);
  ok(n('snap').length===1,'web uygulaması eski snap() yolunu kullanır');

  /* 10) kaynak güvenliği: Win7 yolu değişmedi */
  ok(/virtualizeExact\(id,w,h,cw\)\{/.test(html)&&/live=u\.id==='win7simu'&&!!AndroidBridge\.snap2/.test(html),'Win7 canlı doku kodu yerinde');
  /* 11) Stage 28: bakış okları + uyarlanır kare hızı */
  ok(/gz\(\)\{return !Hand\.on&&!XR\.session\}/.test(html),'BR.gz: yalnızca bakış modunda');
  ok(/'chevup','btn','Sayfayı yukarı kaydır'/.test(html)&&/'chevdown','btn','Sayfayı aşağı kaydır'/.test(html),'bakış modunda yan oklar var');
  ok(/fu\.rep=true;fd\.rep=true/.test(html)&&/b\.fn\.rep/.test(html),'oklar bakılı tutulunca tekrar eder');
  const gj=require('fs').readFileSync(__dirname+'/../app/src/main/java/com/nexus/vr/GpuPage.java','utf8');
  ok(/Q_MOTION/.test(gj)&&/Q_SETTLE/.test(gj)&&/settleTask/.test(gj)&&/avgCost/.test(gj),'GpuPage: hareket/keskin kalite + uyarlanır aralık');
  ok((gj.match(/\{/g)||[]).length===(gj.match(/\}/g)||[]).length,'GpuPage.java parantez dengesi');
  console.log(fails?('\n'+fails+' BAŞARISIZ'):'\nTüm kontroller geçti');process.exit(fails?1:0)
})();
