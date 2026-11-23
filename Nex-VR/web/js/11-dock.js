'use strict';
  /* ---------- Dock: el yapımı görünüm ---------- */
  const DROT=[-1.6,1.2,-.8,1.7,-1.3,.9,-1.8];
  const DK={};
  let _gr=null;
  function grainPat(c){
    if(!_gr){
      const g=document.createElement('canvas');
      g.width=g.height=96;
      const x=g.getContext('2d');
      let sd=7;
      const rnd=()=>(sd=(sd*16807)%2147483647)/2147483647;
      for(let i=0;i<900;i++){
        x.fillStyle=rnd()<.5?'rgba(255,240,220,'+(.04+rnd()*.07)+')':'rgba(0,0,0,'+(.05+rnd()*.08)+')';
        x.fillRect(rnd()*96,rnd()*96,1+rnd()*1.4,1+rnd()*1.4)
      }
      for(let i=0;i<40;i++){
        const y=rnd()*96;
        x.strokeStyle='rgba(255,235,210,.035)';
        x.lineWidth=1;
        x.beginPath();
        x.moveTo(0,y);
        x.bezierCurveTo(30,y+rnd()*4-2,60,y+rnd()*4-2,96,y+rnd()*2-1);
        x.stroke()
      }
      _gr=g
    }
    return c.createPattern(_gr,'repeat')
  }
  function dockBg(c,W,H,a,foc){
    /* Quest 3 dock: koyu gri, yarı saydam hap; altında ayrı tutma çubuğu */
    const ph=Math.round(H*.70),y0=5;
    c.save();c.shadowColor='rgba(0,0,0,.26)';c.shadowBlur=20;c.shadowOffsetY=6;
    rr(c,3,y0,W-6,ph,ph/2);
    c.fillStyle='rgba(32,34,40,'+Math.min(.9,Math.max(.8,a))+')';c.fill();c.restore();
    rr(c,3,y0,W-6,ph,ph/2);c.lineWidth=1;
    c.strokeStyle=foc?'rgba(255,255,255,.16)':'rgba(255,255,255,.07)';c.stroke()
  }
  /* Hafif düzensiz, elle kesilmiş gibi yuvarlak kare */
  function pebble(c,cx,cy,r,seed){
    const N=72,n=3.2;
    c.beginPath();
    for(let i=0;i<N;i++){
      const t=i/N*Math.PI*2,ct=Math.cos(t),st=Math.sin(t);
      const w=1+.018*Math.sin(3*t+seed)+.012*Math.sin(5*t+seed*2.3);
      const x=cx+Math.sign(ct)*Math.pow(Math.abs(ct),2/n)*r*w,y=cy+Math.sign(st)*Math.pow(Math.abs(st),2/n)*r*w;
      i?c.lineTo(x,y):c.moveTo(x,y)
    }
    c.closePath()
  }
  /* Quest 3 uygulama ikonu: yuvarlatılmış kare, hafif gradyan, beyaz glif */
  const QPAL={lib:['#ffb347','#ff6a3c'],browser:['#b58cff','#3f7cf0'],settings:['#3ccb90','#1d9c7a'],camera:['#ff8fab','#e24a7c'],qcam:['#ff8fab','#e24a7c']};
  function qcol(id,col,n){
    const k=(id&&QPAL[id])||col||TC[n]||['#59b4ff','#2f5bff'];
    return Array.isArray(k)?k:[k,k]
  }
  function HTILE(c,n,cx,cy,s,rot,seed,lab,col,pkg,id,ik,im){
    const r=s*.27,h=s/2;
    c.save();
    c.translate(cx,cy);
    if(pkg){
      const im=AND.icon(pkg);
      c.save();c.shadowColor='rgba(0,0,0,.35)';c.shadowBlur=s*.16;c.shadowOffsetY=s*.05;
      rr(c,-h,-h,s,s,r);c.fillStyle='#2a2d33';c.fill();c.restore();
      c.save();rr(c,-h,-h,s,s,r);c.clip();
      if(im.complete&&im.naturalWidth)c.drawImage(im,-h,-h,s,s);
      else{c.fillStyle='#fff';c.font='700 '+Math.round(s*((lab||'').length>1?.34:.46))+'px system-ui';c.textAlign='center';c.fillText(lab||'?',0,s*((lab||'').length>1?.12:.16))}
      c.restore();c.restore();return
    }
    const k=qcol(id,col,n),g=c.createLinearGradient(0,-h,0,h);
    g.addColorStop(0,k[0]);g.addColorStop(1,k[1]);
    c.save();c.shadowColor='rgba(0,0,0,.2)';c.shadowBlur=s*.1;c.shadowOffsetY=s*.03;
    rr(c,-h,-h,s,s,r);c.fillStyle=g;c.fill();c.restore();
    c.save();rr(c,-h,-h,s,s,r);c.clip();
    IOSI.tile(c,{k:ik,col:k,lab:lab,ic:n,id:id,img:im},-h,-h,s,s);
    c.restore();
    c.restore()
  }
  let _bat=1;
  try{if(navigator.getBattery)navigator.getBattery().then(b=>{_bat=b.level;b.addEventListener('levelchange',()=>{_bat=b.level})})}catch(e){}
  const DQ={s:72,g:11,lead:506,sep:30,lib:76,tail:24};
  function dockPx(n){return DQ.lead+n*(DQ.s+DQ.g)+DQ.sep+DQ.lib+DQ.tail}
  function dockRender(c,W,H,B){
    const ph=Math.round(H*.70),y0=5,cy=y0+ph/2,k=ph/110,s=DQ.s*k,g=DQ.g*k,acc=ACC[Settings.v.acc];
    const apps=[['Kamera',()=>{Settings.v.pass=!Pass.bg;Settings.save();if(Settings.v.pass)Pass.enable();else Pass.disable()},Pass.on,'qcam','camera',null,null]].concat(Pins.get().map(id=>{
      const a=appInfo(id);
      return[a.l,()=>WM.spawn(id),WM.isOpen(id),a.ic||null,id,a,()=>Pins.toggle(id)]
    }));
    for(const q in DK)delete DK[q];
    const tot=(DQ.lead+apps.length*(DQ.s+DQ.g)+DQ.sep+DQ.lib+DQ.tail)*k,x0=Math.max(0,(W-tot)/2);
    let tip=null,x=x0+16*k;
    /* avatar */
    const ad=76*k,acx=x+ad/2;
    const av=B(x,cy-ad/2,ad,ad,'',()=>WM.spawn('settings'),false,null,'raw','Ayarlar');
    const ag=c.createLinearGradient(acx-ad/2,cy-ad/2,acx+ad/2,cy+ad/2);
    ag.addColorStop(0,'#7b88a0');ag.addColorStop(1,'#3d4658');
    c.beginPath();c.arc(acx,cy,ad/2,0,6.3);c.fillStyle=ag;c.fill();
    ICN(c,'user',acx,cy,17*k,'#fff');
    if(av)tip=['Ayarlar',acx];
    x+=ad+12*k;
    /* saat / wifi / pil kapsülü → hızlı ayarlar */
    const pw=226*k,pH=66*k;
    const sp=B(x,cy-pH/2,pw,pH,'',()=>QS.toggle(),false,null,'raw','Hızlı ayarlar');
    QS.cap={x:x,y:cy-pH/2,w:pw,h:pH,cx:x+pw/2};
    rr(c,x,cy-pH/2,pw,pH,pH/2);c.fillStyle=QS.open?'rgba(255,255,255,.24)':sp?'rgba(255,255,255,.13)':'rgba(255,255,255,.055)';c.fill();
    c.fillStyle='#f4f6f8';c.font='500 '+(28*k)+'px system-ui,sans-serif';c.textAlign='left';
    c.fillText(new Date().toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'}),x+20*k,cy+10*k);
    ICN(c,'wifi',x+136*k,cy+1*k,12*k,'#f4f6f8');
    const bx=x+168*k,by=cy-8*k;
    c.lineWidth=2*k;c.strokeStyle='#f4f6f8';rr(c,bx,by,30*k,16*k,4*k);c.stroke();
    c.fillStyle='#f4f6f8';rr(c,bx+3*k,by+3*k,Math.max(2,24*k*Math.min(1,_bat)),10*k,2*k);c.fill();
    c.fillRect(bx+31*k,by+5*k,3*k,6*k);
    if(sp)tip=['Hızlı ayarlar',x+pw/2];
    if(Settings.v.fps)txt(c,Perf.fps.toFixed(0)+' FPS',x0+22*k,H-9,12,'rgba(210,218,225,.75)',10);
    x+=pw+10*k;
    /* zil → tanı, halka → VR */
    const rb=(lab,fn,on,ic)=>{
      const d=64*k,cx=x+d/2,hv=B(x,cy-d/2,d,d,'',fn,false,null,'raw',lab);
      c.beginPath();c.arc(cx,cy,d/2,0,6.3);c.fillStyle=on?acc:hv?'rgba(255,255,255,.15)':'rgba(255,255,255,.055)';c.fill();
      ICN(c,ic,cx,cy,d*.27,'#fff');
      if(hv)tip=[lab,cx];
      x+=d+10*k
    };
    rb('Tanı',()=>WM.spawn('diag'),WM.isOpen('diag'),'bell');
    rb('VR',()=>Stereo.toggle(),Stereo.on||!!XR.session,'ring');
    /* uygulamalar */
    x=x0+DQ.lead*k;
    apps.forEach((a,i)=>{
      const hv=B(x,cy-s/2,s,s,'',a[1],false,null,'raw',a[0],a[6]);
      DK[a[4]]=[x+s/2,cy,s];
      HTILE(c,a[3],x+s/2,cy-(hv?4*k:0),s*(hv?1.08:1),0,i+1,a[5]&&a[5].lab,a[5]&&a[5].col,a[5]&&a[5].pkg,a[4],a[5]&&a[5].ik,a[5]&&a[5].img);
      if(hv)tip=[a[0],x+s/2];
      if(a[2]){
        c.beginPath();c.arc(x+s/2,cy+s/2+8*k,2.6*k,0,6.3);c.fillStyle='rgba(240,242,245,.85)';c.fill()
      }
      x+=s+g
    });
    /* ayırıcı + Library */
    c.beginPath();c.moveTo(x+DQ.sep*k/2-4*k,cy-23*k);c.lineTo(x+DQ.sep*k/2-4*k,cy+23*k);
    c.lineWidth=1.6*k;c.lineCap='round';c.strokeStyle='rgba(255,255,255,.16)';c.stroke();
    x+=DQ.sep*k;
    const ld=68*k,lcx=x+ld/2,lh=B(x,cy-ld/2,ld,ld,'',()=>Launcher.toggle(),false,null,'raw','Tüm uygulamalar');
    DK.lib=[lcx,cy,s];DK.launcher=[lcx,cy,s];
    c.beginPath();c.arc(lcx,cy,ld/2,0,6.3);c.fillStyle=Launcher.open?'#f1f2f5':lh?'rgba(255,255,255,.26)':'rgba(255,255,255,.12)';c.fill();
    ICN(c,'dots9',lcx,cy,ld*.27,Launcher.open?'#23252b':'#fff');
    if(lh)tip=['Tüm uygulamalar',lcx];
    /* dock'un altındaki tutma çubuğu */
    const hw=Math.min(110*k,W*.2),hh=Math.max(5*k,5),hx=(W-hw)/2,hy=H-12;
    rr(c,hx,hy,hw,hh,hh/2);c.fillStyle='rgba(236,239,243,.55)';c.fill();
    if(tip){
      c.font='500 '+(17*k)+'px system-ui,sans-serif';
      const tw=c.measureText(tip[0]).width+28*k,th=28*k,tx=clamp(tip[1],tw/2+6,W-tw/2-6),ty=y0+ph+3;
      c.save();c.shadowColor='rgba(0,0,0,.4)';c.shadowBlur=8;
      rr(c,tx-tw/2,ty,tw,th,th/2);c.fillStyle='rgba(24,26,31,.94)';c.fill();c.restore();
      c.fillStyle='#f1f3f5';c.textAlign='center';c.fillText(tip[0],tx,ty+th*.7);c.textAlign='left'
    }
  }
  /* ---------- Giriş ---------- */
