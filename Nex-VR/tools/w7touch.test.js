/* Stage 26 — Win7 çözünürlük / ölçek / el dokunması testi.
   index.html'deki GERÇEK kaynak parçalarını çıkarıp sahte AndroidBridge ile çalıştırır. */
const fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
let fails=0;const ok=(c,m)=>{if(!c){fails++;console.log('FAIL:',m)}else console.log('ok  :',m)};
const cut=(a,b)=>{const i=html.indexOf(a);if(i<0)throw new Error('bulunamadı: '+a.slice(0,50));const j=html.indexOf(b,i);if(j<0)throw new Error('bitiş yok: '+b.slice(0,50));return html.slice(i,j)};

/* ---- kaynak parçaları ---- */
const wtSeg=cut('    wt:null,\n    wtRect(u)','    dwellClear(skip){');
const moveSeg=cut('    move(ray){\n      const wt=this.wt;','      const hd=this.hold;')+'}';
const upSeg=cut('    up(cancel){\n      const wt=this.wt;','      const hd=this.hold;')+'}';
const sizeSeg=cut('    w7size(){','    w7Apply(){');

const calls=[];
const ctx={
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),Math,
  NX_T:'tok',BR:{show:false,menu:false,rect:null},
  BF:{browserId:'nexus-browser',webId:u=>u.id==='browser'?'nexus-browser':'webapp-'+String(u.id).slice(4),act(){}},
  Settings:{v:{w7w:1280,w7q:1.25}},W7Desk:{W:2.8,H:1.2},
  AndroidBridge:{touchView:(id,a,x,y)=>calls.push([id,a,+x.toFixed(4),+y.toFixed(4)])},
  window:null,performance:{now:()=>ctx.__t},__t:1000,
  Scene:{pick:r=>r.hit||null},Scene2:null
};
ctx.window=ctx;vm.createContext(ctx);
vm.runInContext('const Input={'+wtSeg+'\n'+moveSeg+',\n'+upSeg+'};',ctx);
vm.runInContext('const W={'+sizeSeg+'};',ctx);

/* ---- 1) boyut hesabı ---- */
let z=vm.runInContext('W.w7size()',ctx);
ok(z.cw===1280&&z.w===1600&&z.h===686,'Win7 varsayılan: CSS 1280 → WebView 1600×686 (görüldü: '+z.w+'×'+z.h+')');
ctx.Settings.v.w7w=99999;z=vm.runInContext('W.w7size()',ctx);ok(z.cw===2240,'CSS genişliği üst sınırda kırpılır');
ctx.Settings.v.w7w=100;z=vm.runInContext('W.w7size()',ctx);ok(z.cw===800,'CSS genişliği alt sınırda kırpılır');

const applySeg=cut('    w7Apply(){','    virtualizeExact(');
const dels=[];Object.assign(ctx,{__dels:dels});
vm.runInContext('const A={virtualSizes:{delete:k=>__dels.push(k)},snapshotTimes:{delete:k=>__dels.push(k)},idleMs:0,webId:BF.webId,'+applySeg+'};A.w7Apply();',ctx);
ok(dels.every(k=>k==='webapp-simu')&&dels.length===2,'w7Apply doğru Win7 kimliğini sıfırlar (webapp-simu): '+dels.join(','));
/* ---- 2) çimdik → dokunma akışı ---- */
const mesh={userData:{id:'win7simu',web:{},cv:{width:1024,height:439},rect:{x:0,y:0,w:1024,h:439},btns:[]}};
const hitAt=(px,py)=>({object:mesh,uv:{x:1-px/1024,y:1-py/439}});
const run=s=>vm.runInContext(s,ctx);
ctx.__mesh=mesh;ctx.__hit=hitAt;
let r=run('Input.wtBegin(__hit(512,220),__mesh,__mesh.userData,512,220,"hand")');
ok(r===true,'web paneline çimdik dokunma başlatır');
ok(calls.length===1&&calls[0][1]===0&&Math.abs(calls[0][2]-.5)<.001&&Math.abs(calls[0][3]-.5)<.005,'DOWN merkezde (0.5,0.5): '+JSON.stringify(calls[0]));

calls.length=0;ctx.__t=1020;
run('Input.move({hit:__hit(515,222)})');
ok(calls.length===0,'küçük titreme (<12px) MOVE göndermez (tıklama bozulmaz)');
ctx.__t=1040;run('Input.move({hit:__hit(700,260)})');
ok(calls.length===1&&calls[0][1]===1&&calls[0][2]>.6,'büyük hareket MOVE gönderir (pencere sürükleme): '+JSON.stringify(calls[0]));
ctx.__t=1045;run('Input.move({hit:__hit(720,260)})');
ok(calls.length===1,'16 ms içinde ikinci MOVE kısılır (performans)');
ctx.__t=1070;run('Input.move({hit:__hit(720,300)})');
ok(calls.length===2,'sonraki karede MOVE devam eder');
run('Input.move({hit:null})');ok(calls.length===2,'ışın panelden çıkınca MOVE gönderilmez');
run('Input.up(false)');
const last=calls[calls.length-1];
ok(last[1]===2&&last[2]>.65,'bırakınca UP son konumda: '+JSON.stringify(last));
ok(run('Input.wt')===null,'oturum temizlenir');

/* iptal */
calls.length=0;run('Input.wtBegin(__hit(100,100),__mesh,__mesh.userData,100,100,"hand")');run('Input.up(true)');
ok(calls.length===2&&calls[1][1]===3,'iptal → ACTION_CANCEL (3)');

/* düğme üstünde başlamaz, alan dışında başlamaz */
mesh.userData.btns=[{x:0,y:0,w:200,h:50,fn(){}}];
r=run('Input.wtBegin(__hit(50,20),__mesh,__mesh.userData,50,20,"hand")');ok(r===false,'canvas düğmesi üstünde dokunma başlamaz');
mesh.userData.btns=[];mesh.userData.rect={x:0,y:60,w:1024,h:379};
r=run('Input.wtBegin(__hit(50,20),__mesh,__mesh.userData,50,20,"hand")');ok(r===false,'web alanı dışında (başlık) dokunma başlamaz');
ctx.AndroidBridge.touchView=undefined;
r=run('Input.wtBegin(__hit(50,100),__mesh,__mesh.userData,50,100,"hand")');ok(r===false,'köprü yoksa (eski APK) güvenle devre dışı');

/* ---- 3) çimdikle düz düğme tıklama + win7 URL + Java köprüsü varlığı ---- */
ok(/win7simu\.html\?vr=1/.test(html),'Win7 paneli ?vr=1 ile açılır');
ok(/AndroidBridge\.snap2\(id,cb,/.test(html),'canlı doku snap2 kullanır');
const java=fs.readFileSync(path.join(__dirname,'../app/src/main/java/com/nexus/vr/MainActivity.java'),'utf8');
['public boolean touchView(','public void snap2(','public boolean setViewScale(','void setNestedVirtual(','"/_snap/"'].forEach(k=>ok(java.includes(k.replace(/^"|"$/g,'')),'Java: '+k));
const sim=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/win7simu.html'),'utf8');
ok(sim.includes('w7-vr-js')&&sim.includes('window.__w7setW'),'win7simu.html: VR ölçek betiği var');
ok(sim.includes('D = dprf();'),'win7simu.html: köprü fiziksel/CSS oranını kullanır');
console.log(fails?('\n'+fails+' HATA'):'\nTÜM TESTLER GEÇTİ');process.exit(fails?1:0);
