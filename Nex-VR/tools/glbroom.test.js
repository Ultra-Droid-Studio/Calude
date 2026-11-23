/* GLBRoom (index.html) sınaması: gerçek yükleyici kodu, sahte THREE ile çalıştırılır. node tools/glbroom.test.js */
const fs=require('fs'),path=require('path'),A=path.join(__dirname,'..','app','src','main','assets');
const html=fs.readFileSync(path.join(A,'index.html'),'utf8');
const a=html.indexOf('const GLBRoom={'),b=html.indexOf('/* ---------- Sinema modu');
if(a<0||b<0)throw new Error('GLBRoom bulunamadı');
const code=html.slice(a,b);
let fail=0;const ok=(c,m)=>{if(!c){fail++;console.log('HATA:',m)}};
class V{constructor(){this.x=0;this.y=0;this.z=0}fromArray(a){[this.x,this.y,this.z]=a;return this}}
class Q{constructor(){this.x=0;this.y=0;this.z=0;this.w=1}fromArray(a){[this.x,this.y,this.z,this.w]=a;return this}}
class Obj{constructor(){this.children=[];this.position=new V();this.quaternion=new Q();this.scale=new V();this.matrix={}}add(c){this.children.push(c);return this}}
const THREE={Group:Obj,Mesh:class extends Obj{constructor(g,m){super();this.geometry=g;this.material=m}},
  Color:class{constructor(r,g,b){this.r=r;this.g=g;this.b=b}convertLinearToSRGB(){const f=x=>x<.0031308?x*12.92:1.055*Math.pow(x,1/2.4)-.055;this.r=f(this.r);this.g=f(this.g);this.b=f(this.b)}},
  BufferGeometry:class{constructor(){this.attributes={};this.index=null}setAttribute(n,v){this.attributes[n]=v}setIndex(v){this.index=v}computeVertexNormals(){}},
  BufferAttribute:class{constructor(arr,n){this.array=arr;this.itemSize=n;this.count=arr.length/n}},
  Texture:class{constructor(i){this.image=i}},MeshLambertMaterial:class{constructor(o){Object.assign(this,o)}},
  DoubleSide:2,FrontSide:0,RepeatWrapping:1000,ClampToEdgeWrapping:1001};
global.Image=class{set src(u){setTimeout(()=>this.onload&&this.onload(),0)}};
const {GLBRoom}=new Function('THREE','fetch',code+';return{GLBRoom}')(THREE);
(async()=>{
  const buf=fs.readFileSync(path.join(A,'roblox_house.glb'));
  const ab=buf.buffer.slice(buf.byteOffset,buf.byteOffset+buf.byteLength);
  const root=await GLBRoom.parse(ab);
  const meshes=[];(function w(o,qs){const q=o.quaternion;qs=qs.concat([q]);if(o.geometry)meshes.push([o,qs]);o.children.forEach(c=>w(c,qs))})(root,[]);
  ok(meshes.length>90,'ilk mesh sayısı '+meshes.length);
  let verts=0,nan=0,badIdx=0,withUv=0,blend=0,map=0;
  const S=.225,P=[-11*S,-23*S,17*S];
  /* düğüm dönüşü: (0.7071,0,0,0.7071) = x ekseninde +90°: (x,y,z)->(x,-z,y) */
  const T=(x,y,z)=>[x*S+P[0],-z*S+P[1],y*S+P[2]];
  const pts=[];
  for(const [m,qs] of meshes){
    const p=m.geometry.attributes.position.array,n=p.length/3;verts+=n;
    for(let i=0;i<p.length;i++)if(!isFinite(p[i]))nan++;
    if(m.geometry.index){const ix=m.geometry.index.array;for(let i=0;i<ix.length;i++)if(ix[i]>=n){badIdx++;break}}
    if(m.geometry.attributes.uv)withUv++;if(m.material.transparent)blend++;if(m.material.map)map++;
    for(let i=0;i<p.length;i+=3)pts.push(T(p[i],p[i+1],p[i+2]));
  }
  ok(verts===67592,'köşe sayısı '+verts);ok(nan===0,'NaN '+nan);ok(badIdx===0,'geçersiz indeks '+badIdx);
  ok(withUv>0&&map>0,'doku/uv yok');ok(blend>0,'şeffaf malzeme yok');
  const bb=[1,1,1].map((_,k)=>[Math.min(...pts.map(p=>p[k])),Math.max(...pts.map(p=>p[k]))]);
  console.log('mesh',meshes.length,'köşe',verts,'doku-malzeme',map,'şeffaf',blend);
  console.log('sınırlar x',bb[0].map(v=>v.toFixed(1)),'y',bb[1].map(v=>v.toFixed(1)),'z',bb[2].map(v=>v.toFixed(1)));
  /* oturma noktası (0,0,0) ve perde (0,1.8,-4.59) bina içinde mi */
  ok(bb[0][0]<0&&bb[0][1]>0&&bb[2][0]<-4.59&&bb[2][1]>0,'oturma/perde bina sınırı dışında');
  /* dikey ışın (oturma noktasından aşağı/yukarı) üçgenlerle kesiştirilir: zemin ve tavan */
  const hits=[];
  for(const [m] of meshes){
    const p=m.geometry.attributes.position.array,ix=m.geometry.index?m.geometry.index.array:null,tn=(ix?ix.length:p.length/3)/3;
    for(let t=0;t<tn;t++){
      const v=[0,1,2].map(k=>{const i=ix?ix[t*3+k]:t*3+k;return T(p[i*3],p[i*3+1],p[i*3+2])});
      const [A_,B_,C_]=v,d=(B_[2]-C_[2])*(A_[0]-C_[0])+(C_[0]-B_[0])*(A_[2]-C_[2]);
      if(Math.abs(d)<1e-9)continue;
      const l1=((B_[2]-C_[2])*(0-C_[0])+(C_[0]-B_[0])*(0-C_[2]))/d,l2=((C_[2]-A_[2])*(0-C_[0])+(A_[0]-C_[0])*(0-C_[2]))/d,l3=1-l1-l2;
      if(l1<0||l2<0||l3<0)continue;
      hits.push(l1*A_[1]+l2*B_[1]+l3*C_[1]);
    }
  }
  const below=hits.filter(y=>y<1.0),above=hits.filter(y=>y>1.3);
  const floor=below.length?Math.max(...below):null,ceil=above.length?Math.min(...above):null;
  console.log('oturma noktasının altındaki zemin y =',floor&&floor.toFixed(2),'| üstündeki tavan y =',ceil&&ceil.toFixed(2));
  ok(floor!==null&&Math.abs(floor)<.1,'zemin y=0 değil');
  ok(ceil!==null&&ceil>2.5&&ceil<4.5,'tavan beklenen aralıkta değil');
  const wall=pts.filter(p=>Math.abs(p[0])<1.5&&Math.abs(p[1]-1.8)<.8&&Math.abs(p[2]+4.65)<.35).length;
  ok(wall>0,'perde konumunda yüzey yok');
  console.log(fail?fail+' HATA':'TÜM KONTROLLER GEÇTİ');process.exit(fail?1:0);
})().catch(e=>{console.log('İSTİSNA',e);process.exit(1)});
