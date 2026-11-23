/* node tools/gorilla-npc.test.js — Stage 74 NPC sistemi: yol bulma, durum makinesi, engel/çarpışma, LOD, performans.
   Gerçek orman haritası ve gerçek fizik dünyası (gorilla-phys.js) kullanılır; görsel katman burada sınanmaz. */
const path=require('path'),A=path.join(__dirname,'../app/src/main/assets/');
const P=require(A+'gorilla-phys.js'),NPC=require(A+'gorilla-npc.js');
let fails=0;const ok=(c,m,x)=>{console.log((c?'PASS ':'FAIL ')+m+(x!==undefined?'  ['+x+']':''));if(!c)fails++};
const map=P.forestMap(1717),world=new P.World(map.colliders);
const solid=(x,z,r)=>{const h=world.query({x,y:.55,z},r,false);return !!(h&&!(h.collider&&h.collider.ground))};

// --- yol ızgarası ve A*
const M=new NPC.Manager(world,map,{count:6,seed:99}),nav=M.nav;
let walk=0;for(const v of nav.walk)walk+=v;
ok(walk>1500,'yürünebilir hücre sayısı makul',walk);
ok(!nav.ok(map.trees[0].x,map.trees[0].z),'ağaç gövdesi yürünemez');
ok(!nav.ok(0,0),'şenlik ateşi taşları yürünemez');
const t0=Date.now();let found=0,valid=true;
const R=(s=>()=>(s=(s*16807)%2147483647)/2147483647)(42);
for(let i=0;i<60;i++){
  const a=R()*6.28,b=R()*6.28,r1=4+R()*22,r2=4+R()*22,ax=Math.cos(a)*r1,az=Math.sin(a)*r1,bx=Math.cos(b)*r2,bz=Math.sin(b)*r2;
  if(!nav.ok(ax,az)||!nav.ok(bx,bz))continue;
  const p=nav.path(ax,az,bx,bz,20000);if(!p)continue;found++;
  let cx=ax,cz=az;for(const w of p){if(!nav.los(cx,cz,w.x,w.z))valid=false;cx=w.x;cz=w.z}
}
ok(found>20,'A* rastgele noktalar arasında yol buldu',found);
ok(valid,'yol parçaları engelden geçmiyor (görüş hattı)');
ok((Date.now()-t0)/Math.max(1,found)<15,'A* sorgusu hızlı',((Date.now()-t0)/Math.max(1,found)).toFixed(2)+' ms/yol');

// --- 90 sn dolaşma: oyuncu uzakta
ok(M.list.length===6,'6 NPC oluştu');
ok(M.list.every(n=>nav.ok(n.home.x,n.home.z)),'yuvalar yürünebilir');
const start=M.list.map(n=>[n.x,n.z]),states=new Set(),Pl={x:0,y:1,z:9.5,fx:0,fz:-1,hands:[]};
let maxIn=0,nan=false,out=false,minSep=9,totalMs=0,frames=0;
for(let f=0;f<90*60;f++){
  M.update(1/60,Pl);frames++;totalMs+=M.stats.ms||0;
  for(const n of M.list){states.add(n.st);if(!isFinite(n.x+n.z+n.yaw))nan=true;if(Math.hypot(n.x,n.z)>nav.R+.01)out=true;
    const h=world.query({x:n.x,y:.55,z:n.z},.2,false);if(h&&!(h.collider&&h.collider.ground))maxIn=Math.max(maxIn,h.depth)}
  for(let i=0;i<M.list.length;i++)for(let j=i+1;j<M.list.length;j++)minSep=Math.min(minSep,Math.hypot(M.list[i].x-M.list[j].x,M.list[i].z-M.list[j].z))
}
const moved=M.list.map((n,i)=>Math.hypot(n.x-start[i][0],n.z-start[i][1]));
ok(!nan,'NaN yok');ok(!out,'kanyon dışına çıkmadı');
ok(maxIn<.12,'gövde merkezi engellerin içine girmedi',maxIn.toFixed(3));
ok(minSep>.45,'NPC\'ler birbirinin içine girmedi (en yakın)',minSep.toFixed(2)+' m');
ok(M.list.filter((n,i)=>moved[i]>1.5).length>=4||M.stats.paths>12,'NPC\'ler dolaşıyor',moved.map(x=>x.toFixed(1)).join(','));
ok(M.stats.paths>10,'yol planlandı',M.stats.paths);
ok(states.has(NPC.ST.IDLE)&&states.has(NPC.ST.EXPLORE)&&(states.has(NPC.ST.TURN)||states.has(NPC.ST.RETURN)),'durumlar: '+[...states].map(s=>NPC.STN[s]).join(', '));

// --- oyuncu algılama ve tepki
const n0=M.list.find(n=>n.curious);
n0.st=NPC.ST.IDLE;n0.t=5;n0.seen=false;n0.yaw=0;      // -Z'ye bakıyor
const P2={x:n0.x,y:1,z:n0.z-4,fx:0,fz:1,hands:[]};
let det=false,inter=false,ev=[];
for(let f=0;f<240;f++){M.update(1/60,P2);if(n0.st===NPC.ST.DETECT)det=true;if(n0.st===NPC.ST.INTERACT)inter=true;ev=ev.concat(n0.events.splice(0))}
ok(det,'önündeki oyuncuyu gördü (DETECT)');ok(inter,'meraklı NPC etkileşime geçti (INTERACT)');ok(ev.includes('see'),'görme olayı (ses için)');
const dd=Math.hypot(n0.x-P2.x,n0.z-P2.z);ok(dd<3.2&&dd>1.0,'oyuncuya yaklaştı ama içine girmedi',dd.toFixed(2)+' m');
const Ms=new NPC.Manager(world,map,{count:6,seed:99}),n1=Ms.list.find(n=>!n.curious);   /* taze yönetici: kanyon duvarına sıkışmış bir NPC kaçamaz */
if(n1){n1.st=NPC.ST.IDLE;n1.t=5;n1.seen=false;n1.yaw=0;const P3={x:n1.x,y:1,z:n1.z-3,fx:0,fz:1,hands:[]},d0=3;
  for(let f=0;f<300;f++)Ms.update(1/60,P3);ok(Math.hypot(n1.x-P3.x,n1.z-P3.z)>d0,'ürkek NPC uzaklaştı',Math.hypot(n1.x-P3.x,n1.z-P3.z).toFixed(2)+' m')}
// el ile dokunuş → tepki zıplaması
const n2=M.list[2];n2.react=0;const P4={x:n2.x+3,y:1,z:n2.z,fx:-1,fz:0,hands:[{valid:true,x:n2.x+.2,y:.8,z:n2.z,vx:3,vy:0,vz:0}]};
M.update(1/60,P4);ok(n2.react>0&&n2.events.includes('tag'),'elle dokunulan NPC tepki verdi');
let maxY=0;for(let f=0;f<60;f++){P4.hands=[];M.update(1/60,P4);maxY=Math.max(maxY,n2.y)}ok(maxY>.15&&n2.y===0,'tepki zıplaması yere indi',maxY.toFixed(2));

// --- LOD: uzaktaki NPC'ler seyrek güncellenir
const M2=new NPC.Manager(world,map,{count:6,seed:5});
const far={x:0,y:1,z:-30,fx:0,fz:-1,hands:[]};let upd=0,skip=0;
for(let f=0;f<120;f++){M2.update(1/60,far);upd+=M2.stats.updated;skip+=M2.stats.skipped}
ok(skip>upd,'uzak/görüş dışı NPC\'ler kare atlıyor (LOD)',upd+' güncelleme / '+skip+' atlama');

// --- oyuncu-NPC çarpışması
const n3=M.list[3],body={x:n3.x+.2,y:1,z:n3.z},vel={x:-2,y:0,z:0};
ok(M.collidePlayer(body,vel,.3)&&Math.hypot(body.x-n3.x,body.z-n3.z)>.5&&vel.x>=0,'oyuncu NPC\'nin içinden geçemiyor, içeri doğru hızı silindi');

ok(totalMs/frames<1,'6 NPC kare başına ortalama süre',(totalMs/frames).toFixed(3)+' ms');
console.log(fails?('\n'+fails+' BAŞARISIZ'):'\nTÜM NPC TESTLERİ GEÇTİ');process.exit(fails?1:0);
