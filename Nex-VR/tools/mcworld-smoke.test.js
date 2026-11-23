/* MCWorld (Minecraft dünyası) sınaması: sahte THREE + canvas ile build() hatasız çalışır mı, obje sayıları doğru mu. node tools/mcworld-smoke.test.js */
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'..','app','src','main','assets','index.html'),'utf8');
const a=html.indexOf('const MCTex={'),b=html.indexOf('const Cinema={');
if(a<0||b<0)throw new Error('MCTex/MCWorld bulunamadı');
let fail=0;const ok=(c,m)=>{if(!c){fail++;console.log('HATA:',m)}};

/* ---- sahte canvas 2D bağlamı (gerçek piksel üretimine gerek yok, sadece çağrıların patlamaması) ---- */
const mkCtx=()=>new Proxy({},{get(t,k){if(k in t)return t[k];
  return(...args)=>{if(args.some(v=>typeof v==='number'&&Number.isNaN(v)))throw new Error('geçersiz sayısal çağrı '+k+' '+args)}},
  set(t,k,v){t[k]=v;return true}});
global.document={createElement(tag){if(tag!=='canvas')throw new Error('beklenmeyen createElement: '+tag);
  return{width:0,height:0,getContext(){return mkCtx()}}}};

/* ---- sahte THREE: yalnızca MCWorld'ün kullandığı yüzey ---- */
class Vec3{constructor(){this.x=0;this.y=0;this.z=0}set(x,y,z){this.x=x;this.y=y;this.z=z;return this}}
class Obj3D{
  constructor(){this.position=new Vec3();this.rotation=new Vec3();this.scale=new Vec3();this.scale.set(1,1,1);this.children=[];this.matrix={}}
  add(o){this.children.push(o);return this}
  updateMatrix(){}
  lookAt(){}
}
class Mesh extends Obj3D{constructor(geo,mat){super();this.geometry=geo;this.material=mat}}
class InstancedMesh extends Obj3D{
  constructor(geo,mat,count){super();this.geometry=geo;this.material=mat;this.count=count;this.calls=0;this.instanceMatrix={needsUpdate:false}}
  setMatrixAt(i,m){if(i<0||i>=this.count)throw new Error('InstancedMesh index out of range: '+i+'/'+this.count);this.calls++}
}
const uvLen=24; /* BoxGeometry: 6 yüz * 4 köşe */
function boxGeo(){
  const data=new Array(uvLen).fill(0).map((_,i)=>i%2); /* 0/1 desenli sahte u değerleri */
  return{attributes:{uv:{getX(i){if(i<0||i>=uvLen)throw new Error('uv index out of range: '+i);return data[i]},setX(i,v){if(i<0||i>=uvLen)throw new Error('uv index out of range: '+i);data[i]=v}}},rotateX(){return this}}
}
const THREE={
  Group:Obj3D,Object3D:Obj3D,Mesh,InstancedMesh,
  BoxGeometry:function(){return boxGeo()},
  SphereGeometry:function(){return boxGeo()},
  PlaneGeometry:function(){return boxGeo()},
  CanvasTexture:function(cv){return{isTexture:true,image:cv,wrapS:0,wrapT:0,repeat:new Vec3(),magFilter:0,minFilter:0,generateMipmaps:true,needsUpdate:false}},
  MeshLambertMaterial:function(o){return{isMaterial:true,...o}},
  MeshBasicMaterial:function(o){return{isMaterial:true,...o}},
  DirectionalLight:function(){return new Obj3D()},
  AmbientLight:function(){return new Obj3D()},
  NearestFilter:1,RepeatWrapping:2,BackSide:3
};
global.THREE=THREE;
/* Stage 51: kullanıcı dokuları new Image() ile yüklenir; Node'da yok, yüklenmeyen sahte görüntü yeterli */
global.Image=function(){this.width=0;this.height=0;this.onload=null;this.onerror=null;Object.defineProperty(this,'src',{set(){}})};

const MCTex=new Function('THREE',html.slice(a,html.indexOf('const MCWorld=')).replace('const MCTex=','return MCTex=')+';return MCTex')(THREE);
const MCWorld=new Function('THREE','MCTex',html.slice(html.indexOf('const MCWorld='),b).replace('const MCWorld=','return MCWorld=')+';return MCWorld')(THREE,MCTex);

let world=null,err=null;
try{world=MCWorld.build()}catch(e){err=e}
ok(!err,'MCWorld.build() istisna fırlattı: '+(err&&(err.stack||err.message)));
if(world){
  ok(world instanceof Obj3D,'build() bir THREE.Group döndürmeli');
  const flat=[];
  (function walk(o){flat.push(o);o.children.forEach(walk)})(world);
  const instanced=flat.filter(o=>o instanceof InstancedMesh);
  ok(instanced.length===3,'3 InstancedMesh bekleniyordu (zemin, gövdeler, yapraklar): '+instanced.length);
  const grid=instanced.find(m=>m.count===256);
  ok(!!grid&&grid.calls===256,'çimen ızgarası 16x16=256 blok olmalı: '+(grid&&grid.calls));
  const trunks=instanced.find(m=>m.count===9);
  ok(!!trunks&&trunks.calls===9,'9 ağaç gövdesi olmalı: '+(trunks&&trunks.calls));
  const leaves=instanced.find(m=>m.count===9*23);
  ok(!!leaves&&leaves.calls===9*23,'9 ağaç * 23 yaprak bloğu olmalı: '+(leaves&&leaves.calls));
  const meshes=flat.filter(o=>o instanceof Mesh && !(o instanceof InstancedMesh));
  ok(meshes.length>0,'ek mesh (gökyüzü/güneş/bulut/canlı parçaları) üretilmeli');
}
console.log(fail?fail+' HATA':'TÜM KONTROLLER GEÇTİ');process.exit(fail?1:0)
