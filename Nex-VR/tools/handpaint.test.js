/* El çizimi (Hand.paint) performans testi: index.html içindeki gerçek paint() fonksiyonunu
   çıkarıp sahte (mock) bir 2D canvas context ile çalıştırır, çizim çağrısı sayısını sayar.
   Çalıştır: node tools/handpaint.test.js
   NOT: bu sentetik bir Node denemesidir; gerçek cihazda kare hızı ölçümü ayrıca yapılmalıdır. */
const fs=require('fs'),path=require('path'),assert=require('assert');
const html=fs.readFileSync(path.join(__dirname,'..','app/src/main/assets/index.html'),'utf8');
const cut=(a,b)=>{const i=html.indexOf(a),j=html.indexOf(b,i);assert(i>=0&&j>i,'bulunamadı: '+a);return html.slice(i,j)};

let pass=0;const ok=(c,m)=>{assert(c,m);pass++};

/* --- kaynak kontrolü (Stage 72: el yok, gerçek 3B Quest kontrolcü) --- */
ok(/function nexCtrl3D\(T,parent\)/.test(html)&&/function nexCtrl3DPlace/.test(html),'3B kontrolcü kurucu ve yerleştirici var');
ok(!/function nexHandPath|function nexFinger|function nexCtrlBuild/.test(html),'el silueti ve 2B sprite kaldırıldı');
ok(!/fillText\(String\(count\)/.test(html),'parmak sayısı rozeti yok');
ok(/TorusGeometry/.test(html)&&/CylinderGeometry/.test(html),'halka ve sap 3B geometri olarak kurulmuş');
ok(/dot:new T\.MeshBasicMaterial\(\{color:0xffffff,transparent:true,depthTest:false/.test(html),'nokta pencerelerin önünde (depthTest kapalı) çiziliyor');
ok(/cursor:hov/.test(html)&&/hov=!!\(s\.hit\|\|s\.mode==='ui'\)/.test(html),'nokta/ışın yalnızca pencere/düğme üstündeyken görünür');
ok(/_X:new Float64Array\(21\),_Y:new Float64Array\(21\),_cur:\[0,0\]/.test(html),'slotlarda önceden ayrılmış diziler var');

/* --- fonksiyonel test: sahte (stub) THREE ile gerçek kodu çalıştır --- */
const helpers=cut('const _NO=new Float64Array(2);','const Hand={');
const mk=(n)=>function(){const o={};n&&n.split(',').forEach(k=>{o[k]=0});return o};
let meshCount=0,geoCount=0,matCount=0;
class V3{constructor(x=0,y=0,z=0){this.x=x;this.y=y;this.z=z}set(x,y,z){this.x=x;this.y=y;this.z=z;return this}copy(v){this.x=v.x;this.y=v.y;this.z=v.z;return this}
 sub(v){this.x-=v.x;this.y-=v.y;this.z-=v.z;return this}add(v){this.x+=v.x;this.y+=v.y;this.z+=v.z;return this}multiplyScalar(k){this.x*=k;this.y*=k;this.z*=k;return this}
 length(){return Math.hypot(this.x,this.y,this.z)}normalize(){const l=this.length()||1;return this.multiplyScalar(1/l)}setScalar(k){return this.set(k,k,k)}}
class Q{constructor(){this.x=0;this.y=0;this.z=0;this.w=1}copy(q){Object.assign(this,q);return this}setFromUnitVectors(){return this}setFromAxisAngle(){return this}multiply(){return this}}
class Obj{constructor(){this.position=new V3();this.scale=new V3(1,1,1);this.rotation={x:0,y:0,z:0};this.quaternion=new Q();this.children=[];this.visible=true;this.renderOrder=0}
 add(o){this.children.push(o);return this}}
class Mat{constructor(o){Object.assign(this,o);this.emissive={setHex(){}};this.color={setHex(){}};matCount++}clone(){return new Mat(this)}}
class Geo{constructor(){geoCount++}rotateX(){return this}translate(){return this}}
class Mesh extends Obj{constructor(g,m){super();this.geometry=g;this.material=m;meshCount++}}
const T={Group:Obj,Mesh,Vector3:V3,Quaternion:Q,MeshPhongMaterial:Mat,MeshBasicMaterial:Mat,
 CylinderGeometry:Geo,SphereGeometry:Geo,TorusGeometry:Geo,CircleGeometry:Geo};
const lib=new Function(helpers+'return{nexCtrl3D,nexCtrl3DPlace,nexCtrl3DHide}')();
const cam=new Obj();cam.projectionMatrix={elements:(()=>{const e=new Array(16).fill(0);e[0]=1.2;e[5]=2.1;return e})()};
const c1=lib.nexCtrl3D(T,cam),c2=lib.nexCtrl3D(T,cam);
ok(geoCount<=12,'geometriler iki kontrolcü arasında paylaşılıyor ('+geoCount+' geometri)');
ok(c1.g.children.length<=10,'bir kontrolcü ≤10 mesh ('+c1.g.children.length+')');
ok(cam.children.length===6,'kontrolcü+ışın+nokta kameraya eklendi');
lib.nexCtrl3DPlace(T,c1,cam,{nx:.1,ny:-.2,sr:.2,cx:0,cy:0,dist:0,cursor:false,pinch:false,right:true});
ok(c1.g.visible&&!c1.dot.visible&&!c1.ray.visible,'pencere yokken kontrolcü görünür, nokta ve ışın gizli');
ok(Math.abs(c1.g.position.z+.6)<1e-9,'kontrolcü kameranın önünde sabit derinlikte (z=-0.6)');
lib.nexCtrl3DPlace(T,c1,cam,{nx:0,ny:0,sr:.2,cx:.2,cy:.1,dist:2.5,cursor:true,pinch:true,right:false});
ok(c1.dot.visible&&c1.ray.visible,'pencere üstündeyken nokta ve ışın görünür');
ok(c1.g.scale.x<0,'sol kontrolcü ayna (negatif x ölçek)');
ok(Math.abs(c1.dot.scale.x-.011*2.5)<1e-9,'nokta uzaklıkla ölçeklenir (ekranda sabit boy)');
lib.nexCtrl3DHide(c1);
ok(!c1.g.visible&&!c1.ray.visible&&!c1.dot.visible,'el kaybolunca hepsi gizlenir');
console.log('3B kontrolcü testi: '+pass+' kontrol geçti');
