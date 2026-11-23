/* Stage 23 sınaması: Pencere çubuğu (Pill), El menüsü (HMenu) ve TR klavye düzeni.
   Gerçek kod index.html'den kesilip sahte THREE/canvas ile çalıştırılır:  node tools/winhand.test.js */
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'..','app','src','main','assets','index.html'),'utf8');
let fail=0;const ok=(c,m)=>{if(!c){fail++;console.log('HATA:',m)}};
const cut=(a,b)=>{const i=html.indexOf(a),j=html.indexOf(b,i);if(i<0||j<0)throw new Error('bulunamadı: '+a);return html.slice(i,j)};

/* ---- 1) Klavye düzeni ---- */
const kb=cut('    sym:false,\n    rowsL:[','    ensure(){\n      if(this.m)return;\n      this.m=WM.create({id:\'vkb\'');
const K=new Function('return({'+kb.replace(/,\s*$/,'')+'})')();
const flat=r=>r.flat().filter(k=>k[0].length===1).map(k=>k[0]).join('');
const L=K.rowsL,S=K.rowsS;
ok(L.length===5&&S.length===5,'5 satır');
for(const ch of 'ğüşıiöç')ok(flat(L).split(ch).length===2,'harf '+ch+' tam bir kez');
ok(flat(L).includes('qwertyuıopğü')&&flat(L).includes('asdfghjklşi'),'TR Q dizilimi');
for(const [n,R] of [['harf',L],['sembol',S]]){
  ok(R.some(r=>r.some(k=>k[1]==='ok'&&k[3]==='ok')),n+': Enter anahtarı (mavi)');
  ok(R.some(r=>r.some(k=>k[1]==='back')),n+': geri silme');
  ok(R.some(r=>r.some(k=>k[1]==='sym')),n+': ?123/ABC geçişi');
  ok(R.some(r=>r.some(k=>k[1]===' ')),n+': boşluk');
  const w=R.map(r=>r.reduce((a,k)=>a+k[2],0));console.log(n,'satır genişlikleri',w.join(' '));
  ok(Math.max(...w)<=12.6,n+': en geniş satır tuş boyunu daraltmıyor');
}
for(const ch of '@₺/:.-_()') ok((flat(L)+flat(S)).includes(ch),'tuş '+ch);
K.sym=false;ok(K.rows===L,'rows getter harf');K.sym=true;ok(K.rows===S,'rows getter sembol');
ok('i'.toLocaleUpperCase('tr')==='İ'&&'ı'.toLocaleUpperCase('tr')==='I','TR büyük harf i/ı');

/* ---- 2) Pill + HMenu (gerçek kod, sahte ortam) ---- */
const code=cut('  const Pill={','  /* ---------- Pencere yöneticisi (kavisli 360° paneller) ---------- */');
class V3{constructor(x=0,y=0,z=0){this.x=x;this.y=y;this.z=z}set(x,y,z){this.x=x;this.y=y;this.z=z;return this}copy(o){this.x=o.x;this.y=o.y;this.z=o.z;return this}addScaledVector(v,s){this.x+=v.x*s;this.y+=v.y*s;this.z+=v.z*s;return this}}
const ctx=()=>new Proxy({},{get:(t,k)=>k==='measureText'?(s=>({width:String(s).length*14})):k==='createLinearGradient'?(()=>({addColorStop(){}})):(k in t?t[k]:(()=>{})),set:(t,k,v)=>{t[k]=v;return true}});
const THREE={Vector3:V3,Vector2:class{set(x,y){this.x=x;this.y=y;return this}},
  Mesh:class{constructor(g,m){this.geometry=g;this.material=m;this.position=new V3();this.children=[];this.visible=true;this.userData={};this.looked=null}add(c){this.children.push(c)}remove(c){this.children=this.children.filter(x=>x!==c)}lookAt(v){this.looked=v}updateMatrixWorld(){}},
  BufferGeometry:class{dispose(){}},
  PlaneGeometry:class{constructor(w,h){this.w=w;this.h=h;this.attributes={uv:{count:4,a:[0,1,0,1],getX(i){return this.a[i]},setX(i,v){this.a[i]=v},needsUpdate:false}}}dispose(){}},
  CanvasTexture:class{constructor(){this.repeat={x:1}}dispose(){}},MeshBasicMaterial:class{constructor(o){Object.assign(this,o)}dispose(){}},
  Raycaster:class{constructor(){this.ray={origin:new V3(0,1.6,0),direction:new V3(0,0,-1)}}setFromCamera(){}},
  RepeatWrapping:1000,DoubleSide:2};
global.document={createElement:()=>({width:0,height:0,getContext:()=>ctx()})};
const log=[];
const env={THREE,Settings:{v:{pill:true,hmenu:true,hmflip:false,hcam:'environment',acc:0}},XR:{session:null},
  Input:{dw:null,dwDone:null,dwellClear(){}},Diag:{toast:(m)=>log.push('toast:'+m)},
  WM:{panels:[],focused:null,toggleMax:m=>log.push('max'),minimize:(m,a)=>log.push('min'),close:m=>log.push('close'),spawn:id=>log.push('spawn:'+id),paint(){}},
  BR:{ask:()=>log.push('BR.ask')},Scene:{dirty:false,scene:{add(){}}},Cam:{cam:{getWorldPosition:v=>v.set(0,1.6,0)},reset:()=>log.push('reset')},
  Launcher:{toggle:()=>log.push('lib')},Cinema:{},Hand:{mirror:false},
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),ACC:['#2f7bff','#19d3c5','#b06bff','#ff9a2e'],rr(){},ICN(){},curveZ:()=>0};
const names=Object.keys(env);
const {Pill,HMenu}=new Function(...names,code+';return{Pill,HMenu}')(...names.map(n=>env[n]));
const mk=(o)=>{const m=new THREE.Mesh(new THREE.BufferGeometry(),{});m.userData=Object.assign({chrome:true,cflat:true,R:2.9,span:.5,h:1.4,title:'Tarayıcı',btns:[]},o);return m};

// Pill oluşturma ve boyut
const w=mk({});Pill.sync(w);const pm=w.userData.pill;
ok(!!pm&&w.children.includes(pm),'pill pencerenin çocuğu');
ok(pm.userData.btns.length===4,'4 düğme (klavye, büyüt, küçült, kapat) = '+pm.userData.btns.length);
ok(pm.userData.pillOf===w&&pm.userData.R===2.9,'pillOf/R');
const pw=2.9*.5;ok(pm.geometry.w<=pw+1e-9&&pm.geometry.w>=pw*.45,'genişlik pencereye orantılı '+pm.geometry.w.toFixed(3));
ok(pm.position.y<-1.4/2,'pill pencerenin ALTINDA y='+pm.position.y.toFixed(3));
ok(Math.abs(pm.position.z+2.9)<.1,'pill pencere düzleminde z='+pm.position.z.toFixed(3));
const bt=pm.userData.btns,cx=b=>b.x+b.w/2;
ok(cx(bt[0])<cx(bt[1])&&cx(bt[1])<cx(bt[2])&&cx(bt[2])<cx(bt[3]),'sıra: klavye < büyüt < küçült < kapat');
ok(bt.every(b=>b.x>=0&&b.x+b.w<=Pill.CW&&b.y>=0&&b.y+b.h<=Pill.CH),'düğmeler tuval içinde');
bt[3].fn();bt[2].fn();bt[1].fn();ok(log.join()==='close,min,max','düğme eylemleri '+log.join());
log.length=0;bt[0].fn();ok(log.join()==='toast:Bu pencerede yazı alanı yok','klavye: yazı alanı olmayan pencere uyarısı');
log.length=0;w.userData.id='browser';bt[0].fn();ok(log.join()==='BR.ask','klavye: tarayıcıda adres istemi');
log.length=0;env.XR.session={};bt[0].fn();ok(/VR içinde/.test(log.join()),'klavye: VR içinde uyarı');env.XR.session=null;
// Başlık kırpma (uzun başlık) hata vermesin
w.userData.title='Çok uzun bir pencere başlığı '.repeat(6);Pill.paint(pm,true);ok(true,'');
// Yeniden senkron ve kaldırma
const g1=pm.geometry;Pill.sync(w);ok(w.userData.pill===pm&&pm.geometry!==g1,'yeniden sync aynı mesh, yeni geometri');
Pill.dispose(w);ok(!w.userData.pill&&!w.children.length&&pm.userData.dead,'dispose');
ok(!Pill.ok(pm),'ölü pill ok() false');
// want(): dock/kbd/fixedDesk/chrome:false ve ayar kapalı
for(const o of [{dock:true},{kbd:true},{fixedDesk:true},{chrome:false},{cflat:false}]){const x=mk(o);Pill.sync(x);ok(!x.userData.pill,'pill yok: '+JSON.stringify(o))}
env.Settings.v.pill=false;{const x=mk({});Pill.sync(x);ok(!x.userData.pill,'ayar kapalıyken pill yok')}env.Settings.v.pill=true;

// HMenu: avuç yönü ve açık el (sentetik landmark)
const hand=(open)=>{const r=[];for(let i=0;i<21;i++)r.push({x:.5,y:.6,z:0});
  r[0]={x:.5,y:.8,z:0};r[5]={x:.44,y:.6,z:0};r[9]={x:.5,y:.58,z:0};r[13]={x:.56,y:.6,z:0};r[17]={x:.62,y:.63,z:0};
  [[6,8],[10,12],[14,16],[18,20]].forEach(([p,t],i)=>{const bx=[.44,.5,.56,.62][i];r[p]={x:bx,y:open?.45:.62,z:0};r[t]={x:bx,y:open?.3:.7,z:0}});
  return r};
const slot=(raw,label)=>({id:0,on:true,d:{},raw,label,pr:false,mode:''});
const sR=slot(hand(true),'Right'),sL=slot(hand(true),'Left');
ok(HMenu.openHand(sR)&&!HMenu.openHand(slot(hand(false),'Right')),'açık el / yumruk ayrımı');
const fR=HMenu.facing(sR),fL=HMenu.facing(sL);
ok(fR!==fL,'etiket (Right/Left) yüz yönünü tersler: R='+fR+' L='+fL);
env.Settings.v.hmflip=true;ok(HMenu.facing(sR)===!fR,'hmflip tersler');env.Settings.v.hmflip=false;
env.Settings.v.hcam='user';ok(typeof HMenu.facing(sR)==='boolean'&&typeof HMenu.facing(sL)==='boolean','ön kamera yolu çalışır (yön eşlemesi cihazda doğrulanmadı)');env.Settings.v.hcam='environment';
// Avucu yüze dönük olan etiketi bul ve tutma süresi testi
const good=fR?sR:sL;
let t=1000;HMenu.scan([good],t);ok(!HMenu.open,'hemen açılmaz');
HMenu.scan([good],t+300);ok(!HMenu.open,'300 ms: açılmaz');
HMenu.scan([good],t+700);ok(HMenu.open&&HMenu.m.visible,'~0,7 sn tutunca açılır');
ok(HMenu.m.looked&&HMenu.m.looked.y===1.6,'menü kameraya bakar');
ok(HMenu.holds(good),'tutan el tespit edilir');
ok(HMenu.m.userData.btns.length===6&&HMenu.m.userData.handMenu,'6 öğe');
const pr=HMenu.m.userData.btns;ok(pr.every(b=>b.x>=0&&b.x+b.w<=HMenu.CW&&b.y>=0&&b.y+b.h<=HMenu.CH),'öğeler tuval içinde');
// çimdikleyen / meşgul el açmaz
HMenu.close();ok(!HMenu.open,'close');
const busy=Object.assign({},good,{pr:true});HMenu.scan([busy],5000);HMenu.scan([busy],6000);ok(!HMenu.open,'çimdikleyen el açmaz');
const busy2=Object.assign({},good,{mode:'ui'});HMenu.scan([busy2],7000);HMenu.scan([busy2],8000);ok(!HMenu.open,'meşgul (ui) el açmaz');
env.Settings.v.hmenu=false;HMenu.scan([good],9000);HMenu.scan([good],10000);ok(!HMenu.open,'ayar kapalıyken açılmaz');env.Settings.v.hmenu=true;
// zaman aşımı: el kaybolunca ~1,5 sn sonra kapanır
HMenu.scan([good],20000);HMenu.scan([good],20700);ok(HMenu.open,'tekrar açıldı');
const realNow=performance.now.bind(performance);HMenu.seen=realNow()-2000;HMenu.tick();ok(!HMenu.open,'el kaybolunca kapanır');
// öğe eylemi menüyü kapatır
HMenu.scan([good],30000);HMenu.scan([good],30700);ok(HMenu.open,'açık');
HMenu.seen=realNow();log.length=0;HMenu.m.userData.btns[0].fn();ok(!HMenu.open&&log.join()==='lib','Kitaplık: menü kapanır + eylem '+log.join());
HMenu.show();log.length=0;HMenu.m.userData.btns[1].fn();ok(log.join()==='spawn:browser','Tarayıcı');
HMenu.show();log.length=0;HMenu.m.userData.btns[2].fn();ok(log.join()==='spawn:cinema','Sinema');
HMenu.show();log.length=0;HMenu.m.userData.btns[3].fn();ok(log.join()==='spawn:settings','Ayarlar');
HMenu.show();log.length=0;HMenu.m.userData.btns[4].fn();ok(log.join().startsWith('reset'),'Hizala');
// XR içinde çalışmaz
env.XR.session={};HMenu.show();HMenu.scan([good],40000);ok(!HMenu.open,'XR oturumunda kapanır');env.XR.session=null;

/* ---- 3) Entegrasyon noktaları index.html'de var mı ---- */
const must=['Pill.sync(m);','if(u.pill)Pill.paint(u.pill);','Pill.dispose(m);','HMenu.scan(this.slots','HMenu.tick();','!HMenu.holds(s)','if(HMenu.open&&HMenu.m)L.push(HMenu.m);',"BAR=v.pill!==false?0:58;",'let BAR=58;','u.pillOf||o'];
for(const k of must)ok(html.includes(k),'entegrasyon: '+k);
console.log(fail?('BAŞARISIZ: '+fail):'TÜM SINAMALAR GEÇTİ');process.exit(fail?1:0);
