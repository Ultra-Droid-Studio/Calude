/* EnvSky (index.html) sınaması: çizim komutları sahte 2B bağlamda kaydedilir. node tools/envsky.test.js */
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'..','app','src','main','assets','index.html'),'utf8');
const a=html.indexOf('const EnvSky={'),b=html.indexOf('/* ---------- Sinema modu');
if(a<0||b<0)throw new Error('EnvSky bulunamadı');
const EnvSky=new Function(html.slice(a,b)+';return EnvSky')();
let fail=0;const ok=(c,m)=>{if(!c){fail++;console.log('HATA:',m)}};
const rgba=/^rgba\((\d+),(\d+),(\d+),([\d.e-]+)\)$/;
for(const id of EnvSky.IDS.concat(['bilinmeyen'])){
  const W=2048,H=1024,log={rect:0,arc:0,stops:0,full:false,bad:0};
  const grad=()=>({addColorStop(o,c){log.stops++;const m=rgba.exec(c);if(!(o>=0&&o<=1)||!m||+m[1]>255||+m[2]>255||+m[3]>255||+m[4]<0||+m[4]>1)log.bad++}});
  const x={createLinearGradient:grad,createRadialGradient:grad,beginPath(){},fill(){},
    fillRect(px,py,w,h){log.rect++;if(px===0&&py===0&&w===W&&h===H)log.full=true},
    arc(px,py,r){log.arc++;if(!(px>=0&&px<=W&&py>=0&&py<=H&&r>0))log.bad++}};
  EnvSky.draw(id,x,W,H);
  ok(log.bad===0,id+': geçersiz renk/koordinat '+log.bad);ok(log.rect>=1,id+': hiç dolgu yok');
  const stars={night:900+2,space:1600}[id]||0;
  if(stars)ok(log.arc>=stars,id+': yıldız sayısı '+log.arc);
  if(id==='space')ok(log.full,'uzay: tam ekran dolgu yok');
  console.log(id.padEnd(10),'dolgu',log.rect,'daire',log.arc,'renk durağı',log.stops)
}
console.log(fail?fail+' HATA':'TÜM KONTROLLER GEÇTİ');process.exit(fail?1:0)
