'use strict';
  /* ---------- Hızlı ayarlar: dock üstünde açılan cam menü (pencere değil) ---------- */
  const QS={
    m:null,open:false,tm:0,cap:null,lay:null,lw:0,lh:0,nz:null,PC:{},
    S:{vol:.5,bright:.6,wifi:false,bt:false,air:false,data:false,torch:false,rot:false,keep:true,playing:false},
    CARDS:[[20,22,460,486,70],[504,22,472,486,70],[20,545,220,227,58],[268,545,208,227,58],[20,812,456,213,60],[524,545,204,480,66],[772,545,204,480,66]],
    IC:{
      plane:'M21 16v-2l-8-5V3.5c0-.83-.67-1.5-1.5-1.5S10 2.67 10 3.5V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5l8 2.5z',
      wifi:'M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9zm8 8l3 3 3-3c-1.65-1.66-4.34-1.66-6 0zm-4-4l2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.14 9.14 8.87 9.14 5 13z',
      bt:'M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z',
      spk:'M3 9v6h4l5 5V4L7 9H3z',
      w1:'M16.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z',
      w2:'M14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z'
    },
    path(d){return this.PC[d]||(this.PC[d]=new Path2D(d))},
    hasBr(){return !!(window.AndroidBridge&&NX_T)},
    call(fn,...a){
      try{if(this.hasBr()&&typeof AndroidBridge[fn]==='function')return AndroidBridge[fn](...a,NX_T)}
      catch(e){try{Diag.log('QS '+fn+': '+e)}catch(_){}}
      return undefined
    },
    warn(t){try{Diag.toast(t,'var(--warn)')}catch(e){}},
    pull(){
      const r=this.call('sysState');
      if(typeof r!=='string')return;
      try{Object.assign(this.S,JSON.parse(r))}catch(e){}
    },
    fresh(){if(this.open&&this.m)WM.paint(this.m)},
    tick(){const o=JSON.stringify(this.S);this.pull();if(JSON.stringify(this.S)!==o)this.fresh()},
    ensure(){
      if(this.m)return;
      this.m=WM.create({id:'qsmenu',title:'Hızlı ayarlar',icon:'sliders',kbd:true,skin:'qs',cflat:true,curve:false,chrome:false,span:.3647,h:.645,R:1.7,y:1.3,ang:0,live:false,render:(c,W,H,B,u)=>this.render(c,W,H,B,u)});
      this.m.visible=false
    },
    toggle(){if(this.open)this.close();else this.show()},
    onCap(h){
      const c=this.cap,u=h.object.userData;
      if(!c)return false;
      const px=(1-h.uv.x)*u.cv.width,py=(1-h.uv.y)*u.cv.height;
      return px>=c.x&&px<=c.x+c.w&&py>=c.y&&py<=c.y+c.h
    },
    pos(){
      const d=WM.panels.find(p=>p.userData.dock),u=this.m.userData;
      if(d){
        const du=d.userData,gs=du.gs||1,dw=du.R*du.span*gs,cx=this.cap?this.cap.cx:du.cv.width/2,dx=(cx/du.cv.width-.5)*dw;
        u.ang=du.ang-Math.atan2(dx,du.R);
        const top=Math.atan2(1.6-(du.y+du.h*gs*.5),du.R);
        u.y=clamp(1.6-u.R*Math.tan(top)+u.h/2+.04,.9,2.6)
      }else{u.ang=0;u.y=1.3}
      WM.place(this.m)
    },
    show(){
      this.ensure();
      if(Launcher.open)Launcher.close();if(QS.open)QS.close();
      this.pull();this.pos();
      this.open=true;this.m.visible=true;WM.focus(this.m);WM.paint(this.m);
      clearInterval(this.tm);this.tm=setInterval(()=>this.tick(),1500);
      WM.panels.forEach(p=>p.userData.dock&&WM.paint(p));
      try{Diag.say('Hızlı ayarlar açıldı')}catch(e){}
    },
    close(){
      if(!this.open)return;
      this.open=false;clearInterval(this.tm);this.tm=0;
      if(this.m)this.m.visible=false;
      if(WM.focused===this.m)WM.focused=null;
      WM.repaintAll();WM.panels.forEach(p=>p.userData.dock&&WM.paint(p))
    },
    /* ---- eylemler ---- */
    act(k){
      const S=this.S;
      if(!this.hasBr()){this.warn('Bu özellik yalnızca Android uygulamasında çalışır');return}
      if(k==='wifi'||k==='bt'||k==='air'||k==='data'){
        if(this.call('openPanel',k)===true){try{Diag.toast('Android bu anahtarı uygulamadan değiştirmeye izin vermez; sistem paneli açıldı')}catch(e){}}
        else this.warn('Sistem ayarı açılamadı');
        return
      }
      if(k==='out'){if(this.call('openPanel','volume')!==true)this.warn('Ses çıkışı paneli açılamadı');return}
      if(k==='torch'){const on=!S.torch;if(this.call('setTorch',on)===true)S.torch=on;else this.warn('Fener kullanılamıyor (kamera meşgul olabilir)')}
      else if(k==='rot'){const on=!S.rot;if(this.call('setRotationLock',on)===true)S.rot=on}
      else if(k==='keep'){const on=!S.keep;if(this.call('setKeepOn',on)===true)S.keep=on}
      else if(k==='play'){this.call('mediaKey','play');S.playing=!S.playing;setTimeout(()=>{this.pull();this.fresh()},700)}
      else if(k==='next'||k==='prev'){this.call('mediaKey',k)}
      this.fresh()
    },
    lvl(k,v){
      const S=this.S;
      if(!this.hasBr()){this.warn('Bu özellik yalnızca Android uygulamasında çalışır');return}
      v=clamp(v,0,1);
      if(k==='vol'){S.vol=v;this.call('setVolume',v)}
      else{S.bright=Math.max(.02,v);this.call('setBrightness',S.bright)}
      this.fresh()
    },
    /* ---- cam katmanı (bir kez çizilip önbelleğe alınır) ---- */
    noise(){
      if(!this.nz){
        const n=document.createElement('canvas');n.width=n.height=96;
        const x=n.getContext('2d'),d=x.createImageData(96,96);let sd=11;
        for(let i=0;i<d.data.length;i+=4){sd=(sd*16807)%2147483647;const v=sd%255;d.data[i]=d.data[i+1]=d.data[i+2]=v;d.data[i+3]=255}
        x.putImageData(d,0,0);this.nz=n
      }
      return this.nz
    },
    layer(W,H){
      if(this.lay&&this.lw===W&&this.lh===H)return this.lay;
      const k=W/1000,g=document.createElement('canvas');g.width=W;g.height=H;
      const x=g.getContext('2d'),C=this.CARDS.map(a=>a.map(v=>v*k));
      /* 1) gölgeler */
      C.forEach(a=>{
        x.save();x.shadowColor='rgba(6,8,28,.55)';x.shadowBlur=42*k;x.shadowOffsetY=16*k;
        rr(x,a[0],a[1],a[2],a[3],a[4]);x.fillStyle='#06081c';x.fill();x.restore()
      });
      /* 2) iç kısmı sil → yalnızca dış gölge kalır */
      x.save();x.globalCompositeOperation='destination-out';
      C.forEach(a=>{rr(x,a[0],a[1],a[2],a[3],a[4]);x.fillStyle='#000';x.fill()});
      x.restore();
      /* 3) buzlu cam */
      const blob=(cx,cy,r,col)=>{const gr=x.createRadialGradient(cx,cy,0,cx,cy,r);gr.addColorStop(0,col);gr.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gr;x.fillRect(cx-r,cy-r,r*2,r*2)};
      C.forEach(a=>{
        const X=a[0],Y=a[1],w=a[2],h=a[3],r=a[4];
        x.save();rr(x,X,Y,w,h,r);x.clip();
        x.fillStyle='rgba(14,16,44,.46)';x.fillRect(X,Y,w,h);
        let gr=x.createLinearGradient(0,Y,0,Y+h);
        gr.addColorStop(0,'rgba(196,202,255,.20)');gr.addColorStop(.5,'rgba(120,126,210,.09)');gr.addColorStop(1,'rgba(70,76,150,.16)');
        x.fillStyle=gr;x.fillRect(X,Y,w,h);
        /* bulanık arka plan ışıkları (blur benzetimi) */
        blob(X+w*.18,Y+h*.08,Math.max(w,h)*.7,'rgba(150,120,255,.34)');
        blob(X+w*.92,Y+h*.96,Math.max(w,h)*.6,'rgba(70,120,255,.26)');
        gr=x.createLinearGradient(X,Y,X+w*.85,Y+h*.85);
        gr.addColorStop(0,'rgba(255,255,255,.22)');gr.addColorStop(.35,'rgba(255,255,255,.04)');gr.addColorStop(1,'rgba(255,255,255,0)');
        x.fillStyle=gr;x.fillRect(X,Y,w,h);
        x.globalCompositeOperation='overlay';x.globalAlpha=.2;
        x.fillStyle=x.createPattern(this.noise(),'repeat');x.fillRect(X,Y,w,h);
        x.restore();
        rr(x,X+1,Y+1,w-2,h-2,r-1);
        gr=x.createLinearGradient(X,Y,X+w,Y+h);
        gr.addColorStop(0,'rgba(255,255,255,.58)');gr.addColorStop(.5,'rgba(255,255,255,.10)');gr.addColorStop(1,'rgba(255,255,255,.30)');
        x.lineWidth=2*k;x.strokeStyle=gr;x.stroke()
      });
      this.lay=g;this.lw=W;this.lh=H;return g
    },
    /* ---- simgeler ---- */
    ico(c,d,cx,cy,sz,col){c.save();c.translate(cx-sz/2,cy-sz/2);c.scale(sz/24,sz/24);c.fillStyle=col;c.fill(this.path(d));c.restore()},
    gTower(c,cx,cy,sz,col){
      c.save();c.strokeStyle=col;c.fillStyle=col;c.lineCap='round';c.lineWidth=sz*.085;
      const dy=cy-sz*.2;
      c.beginPath();c.arc(cx,dy,sz*.075,0,6.3);c.fill();
      c.beginPath();c.moveTo(cx,dy+sz*.08);c.lineTo(cx,cy+sz*.44);c.stroke();
      [.2,.36].forEach(r=>{
        c.beginPath();c.arc(cx,dy,sz*r,-.8,.8);c.stroke();
        c.beginPath();c.arc(cx,dy,sz*r,Math.PI-.8,Math.PI+.8);c.stroke()
      });
      c.restore()
    },
    gLock(c,cx,cy,sz,col){
      c.save();c.strokeStyle=col;c.fillStyle=col;c.lineCap='round';c.lineJoin='round';c.lineWidth=sz*.075;
      const R=sz*.4,a0=.52,a1=6.02;
      c.beginPath();c.arc(cx,cy,R,a0,a1);c.stroke();
      const ex=cx+Math.cos(a1)*R,ey=cy+Math.sin(a1)*R,tx=-Math.sin(a1),ty=Math.cos(a1),nx=Math.cos(a1),ny=Math.sin(a1),q=sz*.12;
      c.beginPath();c.moveTo(ex+tx*q*1.2,ey+ty*q*1.2);c.lineTo(ex+nx*q,ey+ny*q);c.lineTo(ex-nx*q,ey-ny*q);c.closePath();c.fill();
      c.lineWidth=sz*.06;
      c.beginPath();c.arc(cx,cy-sz*.02,sz*.085,Math.PI,0);c.stroke();
      rr(c,cx-sz*.14,cy-sz*.02,sz*.28,sz*.22,sz*.04);c.fill();
      c.restore()
    },
    gTorch(c,cx,cy,sz,col,bg){
      c.save();c.fillStyle=col;
      rr(c,cx-sz*.2,cy-sz*.46,sz*.4,sz*.15,sz*.04);c.fill();
      c.beginPath();c.moveTo(cx-sz*.17,cy-sz*.32);c.lineTo(cx+sz*.17,cy-sz*.32);c.lineTo(cx+sz*.11,cy-sz*.18);c.lineTo(cx-sz*.11,cy-sz*.18);c.closePath();c.fill();
      rr(c,cx-sz*.11,cy-sz*.2,sz*.22,sz*.64,sz*.07);c.fill();
      c.fillStyle=bg;rr(c,cx-sz*.035,cy-sz*.04,sz*.07,sz*.17,sz*.035);c.fill();
      c.restore()
    },
    gSun(c,cx,cy,sz,col){
      c.save();c.strokeStyle=col;c.fillStyle=col;c.lineCap='round';c.lineWidth=sz*.07;
      c.beginPath();c.arc(cx,cy,sz*.16,0,6.3);c.fill();
      for(let i=0;i<8;i++){const a=i*Math.PI/4;c.beginPath();c.moveTo(cx+Math.cos(a)*sz*.27,cy+Math.sin(a)*sz*.27);c.lineTo(cx+Math.cos(a)*sz*.4,cy+Math.sin(a)*sz*.4);c.stroke()}
      c.restore()
    },
    gVol(c,cx,cy,sz,col,v){
      this.ico(c,this.IC.spk,cx,cy,sz,col);
      if(v>.02)this.ico(c,this.IC.w1,cx,cy,sz,col);
      if(v>.5)this.ico(c,this.IC.w2,cx,cy,sz,col)
    },
    gScreens(c,cx,cy,sz,col,bg){
      c.save();c.lineWidth=sz*.07;c.strokeStyle=col;c.lineJoin='round';
      rr(c,cx-sz*.1,cy-sz*.3,sz*.4,sz*.3,sz*.06);c.stroke();
      rr(c,cx-sz*.3,cy-sz*.08,sz*.4,sz*.3,sz*.06);c.fillStyle=bg;c.fill();c.stroke();
      c.restore()
    },
    gOut(c,cx,cy,sz,col){
      c.save();c.strokeStyle=col;c.fillStyle=col;c.lineCap='round';c.lineWidth=sz*.075;
      [.46,.3,.14].forEach(r=>{c.beginPath();c.arc(cx,cy+sz*.02,sz*r,Math.PI*1.1,Math.PI*1.9);c.stroke()});
      c.beginPath();c.moveTo(cx-sz*.24,cy+sz*.46);c.lineTo(cx+sz*.24,cy+sz*.46);c.lineTo(cx,cy+sz*.16);c.closePath();c.fill();
      c.restore()
    },
    /* ---- çizim ---- */
    render(c,W,H,B,u){
      const k=W/1000,S=this.S,TAU=Math.PI*2;
      c.drawImage(this.layer(W,H),0,0);
      const rrk=(x,y,w,h,r)=>rr(c,x*k,y*k,w*k,h*k,r*k);
      const el=(x,y,w,h,fn,nm,draw)=>{const hv=u.hov===u.btns.length;draw(hv);B(x*k,y*k,w*k,h*k,'',fn,false,null,'raw',nm)};
      const font=(wt,px)=>wt+' '+(px*k)+'px system-ui,sans-serif';
      /* -- bağlantı yuvarlakları -- */
      const circ=(cx,cy,on,col,nm,fn,gl)=>el(cx-79,cy-79,158,158,fn,nm,hv=>{
        const X=cx*k,Y=cy*k,r=79*k;
        c.save();c.shadowColor='rgba(0,0,0,.38)';c.shadowBlur=20*k;c.shadowOffsetY=7*k;
        c.beginPath();c.arc(X,Y,r,0,TAU);c.fillStyle=on?col:'rgba(118,120,158,.62)';c.fill();c.restore();
        const g=c.createLinearGradient(0,Y-r,0,Y+r);
        g.addColorStop(0,'rgba(255,255,255,.36)');g.addColorStop(.55,'rgba(255,255,255,.03)');g.addColorStop(1,'rgba(0,0,0,.18)');
        c.beginPath();c.arc(X,Y,r,0,TAU);c.fillStyle=g;c.fill();
        if(hv){c.fillStyle='rgba(255,255,255,.16)';c.fill()}
        c.lineWidth=2*k;c.strokeStyle='rgba(255,255,255,'+(hv?.75:.3)+')';c.stroke();
        gl(X,Y,r)
      });
      circ(152,160,S.air,'#ff6a3d','Uçak modu',()=>this.act('air'),(X,Y,r)=>{c.save();c.translate(X,Y);c.rotate(Math.PI/2);this.ico(c,this.IC.plane,0,0,r*1.05,'#fff');c.restore()});
      circ(353,160,S.data,'#34c759','Mobil veri',()=>this.act('data'),(X,Y,r)=>this.gTower(c,X,Y,r*1.05,'#fff'));
      circ(152,369,S.wifi,'#0a84ff','Wi-Fi',()=>this.act('wifi'),(X,Y,r)=>this.ico(c,this.IC.wifi,X,Y,r*1.15,'#fff'));
      circ(353,369,S.bt,'#ff9f0a','Bluetooth',()=>this.act('bt'),(X,Y,r)=>this.ico(c,this.IC.bt,X,Y,r*1.0,'#fff'));
      /* -- medya kartı -- */
      c.save();rrk(544,82,172,172,32);c.clip();
      const ag=c.createLinearGradient(544*k,82*k,716*k,254*k);
      ag.addColorStop(0,'#17104a');ag.addColorStop(.55,'#3a22b8');ag.addColorStop(1,'#10082e');
      c.fillStyle=ag;c.fillRect(544*k,82*k,172*k,172*k);
      c.lineWidth=14*k;c.lineCap='round';
      [['rgba(120,110,255,.55)',0],['rgba(90,150,255,.35)',26],['rgba(190,150,255,.30)',52]].forEach(a=>{
        c.strokeStyle=a[0];c.beginPath();c.moveTo(530*k,(150+a[1])*k);
        c.bezierCurveTo(600*k,(60+a[1])*k,650*k,(250+a[1])*k,730*k,(120+a[1])*k);c.stroke()
      });
      c.restore();
      rrk(544,82,172,172,32);c.lineWidth=1.5*k;c.strokeStyle='rgba(255,255,255,.22)';c.stroke();
      c.textAlign='left';
      c.fillStyle='#f4f5ff';c.font=font(500,34);c.fillText('Medya',744*k,196*k);
      c.fillStyle='#8f8aff';c.font=font(500,27);c.fillText(S.playing?'Çalıyor':'Duraklatıldı',744*k,240*k);
      el(878,52,76,76,()=>this.act('out'),'Ses çıkışı',hv=>{
        if(hv){c.beginPath();c.arc(916*k,90*k,36*k,0,TAU);c.fillStyle='rgba(255,255,255,.14)';c.fill()}
        this.gOut(c,916*k,88*k,52*k,'#eef0ff')
      });
      const dbl=(cx,cy,dir)=>{
        c.save();c.fillStyle='#fff';c.strokeStyle='#fff';c.lineWidth=5*k;c.lineJoin='round';
        [-15,15].forEach(o=>{
          const x=(cx+o)*k;
          c.beginPath();c.moveTo(x-dir*14*k,(cy-17)*k);c.lineTo(x+dir*14*k,cy*k);c.lineTo(x-dir*14*k,(cy+17)*k);c.closePath();c.fill();c.stroke()
        });
        c.restore()
      };
      const bgc=(cx,cy,hv)=>{if(hv){c.beginPath();c.arc(cx*k,cy*k,54*k,0,TAU);c.fillStyle='rgba(255,255,255,.13)';c.fill()}};
      el(556,350,108,100,()=>this.act('prev'),'Önceki',hv=>{bgc(610,400,hv);dbl(610,400,-1)});
      el(684,340,116,120,()=>this.act('play'),S.playing?'Duraklat':'Oynat',hv=>{
        bgc(742,400,hv);
        c.save();c.fillStyle='#fff';c.strokeStyle='#fff';c.lineWidth=6*k;c.lineJoin='round';
        if(S.playing){rrk(724,372,16,56,6);c.fill();rrk(746,372,16,56,6);c.fill()}
        else{c.beginPath();c.moveTo(722*k,370*k);c.lineTo(768*k,400*k);c.lineTo(722*k,430*k);c.closePath();c.fill();c.stroke()}
        c.restore()
      });
      el(820,350,108,100,()=>this.act('next'),'Sonraki',hv=>{bgc(874,400,hv);dbl(874,400,1)});
      /* -- dönme kilidi / fener -- */
      const tile=(x,y,w,h,r,on,hv)=>{
        if(on){const g=c.createLinearGradient(0,y*k,0,(y+h)*k);g.addColorStop(0,'rgba(252,252,255,.97)');g.addColorStop(1,'rgba(208,211,236,.95)');rrk(x,y,w,h,r);c.fillStyle=g;c.fill()}
        else if(hv){rrk(x,y,w,h,r);c.fillStyle='rgba(255,255,255,.10)';c.fill()}
      };
      el(20,545,220,227,()=>this.act('rot'),'Dönme kilidi',hv=>{tile(20,545,220,227,58,S.rot,hv);this.gLock(c,130*k,658*k,124*k,S.rot?'#e5352c':'#f4f5ff')});
      el(268,545,208,227,()=>this.act('torch'),'Fener',hv=>{
        tile(268,545,208,227,58,S.torch,hv);
        this.gTorch(c,372*k,658*k,132*k,S.torch?'#1b1e48':'#f4f5ff',S.torch?'#e3e5f6':'#2a2d62')
      });
      /* -- ekran zaman aşımı -- */
      el(20,812,456,213,()=>this.act('keep'),'Ekran zaman aşımı',hv=>{
        if(hv){rrk(20,812,456,213,60);c.fillStyle='rgba(255,255,255,.08)';c.fill()}
        c.beginPath();c.arc(115*k,918*k,65*k,0,TAU);c.fillStyle=S.keep?'rgba(120,140,255,.55)':'rgba(255,255,255,.14)';c.fill();
        c.lineWidth=1.5*k;c.strokeStyle='rgba(255,255,255,.28)';c.stroke();
        this.gScreens(c,115*k,918*k,76*k,'#f4f5ff',S.keep?'#5568d8':'#4a4d7c');
        c.textAlign='left';c.fillStyle='#f4f5ff';c.font=font(500,30);c.fillText('Ekranı açık tut',218*k,912*k);
        c.fillStyle=S.keep?'#9fb0ff':'rgba(230,232,250,.62)';c.font=font(500,26);c.fillText(S.keep?'Açık':'Kapalı',218*k,954*k)
      });
      /* -- kaydırıcılar (20 dilim: dokun/çimdikle seviye seç) -- */
      const slider=(x,y,w,h,r,val,nm,set,kind)=>{
        const N=20,top=y+h*(1-val);
        if(val>.004){
          c.save();rrk(x,y,w,h,r);c.clip();
          const g=c.createLinearGradient(0,top*k,0,(y+h)*k);
          g.addColorStop(0,'rgba(246,247,255,.97)');g.addColorStop(1,'rgba(206,210,240,.95)');
          c.fillStyle=g;c.fillRect(x*k,top*k,w*k,(y+h-top)*k);
          c.fillStyle='rgba(255,255,255,.95)';c.fillRect(x*k,top*k,w*k,2*k);
          c.restore()
        }
        const gy=y+h-88,col=top<gy-24?'#1c1f4a':'#f4f5ff';
        if(kind==='b')this.gSun(c,(x+w/2)*k,gy*k,76*k,col);
        else this.gVol(c,(x+w/2)*k,gy*k,76*k,col,val);
        for(let i=0;i<N;i++){
          const v=1-i/(N-1);
          B(x*k,(y+i*h/N)*k,w*k,(h/N)*k,'',()=>set(v),false,null,'raw',nm+' %'+Math.round(v*100))
        }
      };
      slider(524,545,204,480,66,S.bright,'Parlaklık',v=>this.lvl('bri',v),'b');
      slider(772,545,204,480,66,S.vol,'Ses',v=>this.lvl('vol',v),'v');
      c.textAlign='left'
    }
  };
  /* LOBBY:BEGIN */
  /* ---------- Başlatıcı sahnesi (açılış): Ana Menü · Ayarlar · Kalibrasyon · VR Ayarları · El Takibi · Hakkında · Çıkış ----------
     Boot bitince #load yerine bu sahne görünür. Başlat → App.enter(). El takibi burada da açılıp kapanır;
     eller açıkken Hand.arbitrate() bu sahneye yönlenir (çimdik = tıklama, imleç = üzerine gelme). */
  const Lobby={
    open:false,page:'home',el:null,go:null,built:false,hov:null,bat:null,exitAt:0,ck:0,raf:0,lt:0,pi:-1,busy:false,
    prev:[false,false],
    ACCN:['Mavi','Turkuaz','Mor','Turuncu'],
    PAL:[['#2f7bff','#8a5cff'],['#19d3c5','#2f7bff'],['#b06bff','#ff6bd6'],['#ff9a2e','#ff4d7a']],
    PROF:[
      {id:'cardboard',name:'Google Cardboard',eye:.064,fov:75,offset:0,scale:.85},
      {id:'vrbox',name:'VR Box',eye:.063,fov:78,offset:0,scale:.82},
      {id:'vrsensation',name:'VR Sensation',eye:.064,fov:78,offset:0,scale:.85},
      {id:'shinecon',name:'VR SHINECON',eye:.063,fov:80,offset:0,scale:.82},
      {id:'bobovr',name:'BOBOVR / Z4',eye:.064,fov:82,offset:0,scale:.85},
      {id:'destek',name:'DESTEK',eye:.063,fov:80,offset:0,scale:.82},
      {id:'merge',name:'Merge VR',eye:.064,fov:78,offset:0,scale:.85},
      {id:'generic',name:'Genel / özel gözlük',eye:.064,fov:75,offset:0,scale:.8}
    ],
    IC:{
      home:'<path d="M12 2.5 1.5 12H5v9h5.2v-6h3.6v6H19v-9h3.5z"/>',
      gear:'<path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z"/>',
      cal:'<circle cx="12" cy="12" r="7.2" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="2.3"/><path d="M12 1.5v5M12 17.5v5M1.5 12h5M17.5 12h5" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>',
      vr:'<path fill-rule="evenodd" d="M3.2 6.5h17.6A2.2 2.2 0 0 1 23 8.7v7.6a2.2 2.2 0 0 1-2.2 2.2h-4.6a2 2 0 0 1-1.7-1l-.7-1.2a1 1 0 0 0-.9-.5h-1.8a1 1 0 0 0-.9.5l-.7 1.2a2 2 0 0 1-1.7 1H3.2A2.2 2.2 0 0 1 1 16.3V8.7a2.2 2.2 0 0 1 2.2-2.2zM7.2 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm9.6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>',
      hand:'<path d="M8 22c-1.4 0-2.4-.6-3.2-1.8L1.4 15c-.5-.8-.3-1.7.5-2.1.7-.4 1.5-.2 2 .4L6 15V4.8a1.5 1.5 0 0 1 3 0V11h.5V3.3a1.5 1.5 0 0 1 3 0V11h.5V4.3a1.5 1.5 0 0 1 3 0V11h.5V7.3a1.5 1.5 0 0 1 3 0V16c0 3.3-2.2 6-5.5 6z"/>',
      info:'<circle cx="12" cy="12" r="10.5"/><path d="M12 11v6M12 7.2v.2" stroke="#0b1030" stroke-width="2.6" stroke-linecap="round" fill="none"/>',
      exit:'<path d="M10 3.5H5.5A2 2 0 0 0 3.5 5.5v13a2 2 0 0 0 2 2H10" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><path d="M15.5 7.5 20.5 12l-5 4.5M20 12H9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
      bars:'<path d="M3.5 21v-9.5h4.4V21zM9.8 21V3h4.4v18zM16.1 21v-6.5h4.4V21z"/>',
      bolt:'<path d="M13.5 1.5 4.5 13.5h6L9.5 22.5l9-12h-6z"/>',
      pal:'<path d="M12 2.5a9.5 9.5 0 0 0 0 19c1.2 0 1.9-.9 1.9-1.8 0-.5-.2-.9-.5-1.3-.3-.4-.5-.7-.5-1.2 0-1 .8-1.8 1.8-1.8h2.1a5 5 0 0 0 5-5c0-4.3-4.3-7.9-9.8-7.9z"/><circle cx="7.3" cy="11.5" r="1.4" fill="#0b1030"/><circle cx="10.2" cy="7.3" r="1.4" fill="#0b1030"/><circle cx="14.8" cy="7.3" r="1.4" fill="#0b1030"/><circle cx="17.5" cy="11.2" r="1.4" fill="#0b1030"/>',
      play:'<path d="M7 4.5v15l13-7.5z"/>',
      star:'<path d="m12 2 3.1 6.6 7.2.9-5.3 5 1.4 7.1L12 17.9 5.6 21.6 7 14.5 1.7 9.5l7.2-.9z"/>'
    },
    ic(n,c){return '<svg viewBox="0 0 24 24" aria-hidden="true"'+(c?' class="'+c+'"':'')+'>'+this.IC[n]+'</svg>'},
    /* kalın beyaz hat çizgili VR gözlüğü (logo + büyük simge) */
    vrBig(w){return '<svg viewBox="0 0 140 80" fill="none" stroke="#fff" stroke-width="9" stroke-linejoin="round" stroke-linecap="round" aria-hidden="true"><path d="M17 36c0-15 6-24 22-24h62c16 0 22 9 22 24v10c0 14-8 22-20 22h-9c-7 0-11-3-14-8-2-3-4-4-7-4s-5 1-7 4c-3 5-7 8-14 8h-9c-12 0-26-8-26-22z"/></svg>'},
    h(tag,cls,txt){const e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e},
    btn(txt,fn,cls){const b=this.h('button','bt'+(cls?' '+cls:''),txt);b.type='button';b.dataset.a='f';b._f=fn;return b},
    sw(on,fn,label){const b=this.h('button','sw'+(on?' on':''));b.type='button';b.setAttribute('role','switch');b.setAttribute('aria-checked',on?'true':'false');if(label)b.setAttribute('aria-label',label);b.dataset.a='f';b._f=fn;b.appendChild(this.h('i'));return b},
    rb(txt,fn,label){const b=this.h('button','rb',txt);b.type='button';b.setAttribute('aria-label',label);b.dataset.a='f';b._f=fn;return b},
    stp(val,dec,inc,name){const w=this.h('div','stp');w.append(this.rb('−',dec,name+' azalt'),this.h('span','n',val),this.rb('+',inc,name+' artır'));return w},
    row(label,ctrl,sub){const r=this.h('div','lr'),l=this.h('div');l.appendChild(document.createTextNode(label));if(sub)l.appendChild(this.h('small',null,sub));r.append(l);if(ctrl)r.append(ctrl);return r},
    /* ---- yardımcılar ---- */
    set(k,v){Settings.v[k]=v;Settings.save();try{Settings.apply()}catch(e){}},
    num(k,d,lo,hi,st,dec){const v=Settings.v;let x=(+v[k]);if(!isFinite(x))x=(DEF[k]!=null?DEF[k]:lo);x=clamp(Math.round((x+d*st)*1000)/1000,lo,hi);this.set(k,Math.round(x*1000)/1000);this.render()},
    toast(t,c){try{Diag.toast(t,c)}catch(e){}},
    theme(){
      const a=clamp(Settings.v.acc|0,0,3),p=this.PAL[a];
      this.el.style.setProperty('--l1',p[0]);this.el.style.setProperty('--l2',p[1])
    },
    fit(){
      const s=Math.min(innerWidth/1672,innerHeight/941);
      this.stage.style.transform='translate(-50%,-50%) scale('+s.toFixed(4)+')'
    },
    /* ---- görseller: gece odası + dağ/göl manzarası ---- */
    rng(seed){let r=seed;return()=>(r=(r*16807)%2147483647)/2147483647},
    bgSVG(){
      const R=this.rng(7);let st='';
      for(let i=0;i<150;i++){const x=450+R()*840,y=100+R()*86;st+='<circle cx="'+x.toFixed(1)+'" cy="'+y.toFixed(1)+'" r="'+(.5+R()*1.3).toFixed(1)+'" fill="#fff" opacity="'+(.3+R()*.7).toFixed(2)+'"/>'}
      for(let i=0;i<110;i++){const x=1450+R()*222,y=45+R()*300;st+='<circle cx="'+x.toFixed(1)+'" cy="'+y.toFixed(1)+'" r="'+(.5+R()*1.4).toFixed(1)+'" fill="#fff" opacity="'+(.3+R()*.7).toFixed(2)+'"/>'}
      const leaf=(x,y,r,rot,c)=>'<ellipse cx="'+x+'" cy="'+y+'" rx="'+r*.28+'" ry="'+r+'" transform="rotate('+rot+' '+x+' '+y+')" fill="'+c+'"/>';
      let pl='';
      [[40,330,70,-35],[70,300,80,-8],[30,270,60,28],[95,345,60,18],[20,230,55,-50],[60,250,66,10]].forEach(p=>pl+=leaf(p[0],p[1],p[2],p[3],'#0d2a2e'));
      [[1640,350,70,32],[1615,320,78,6],[1655,290,62,-28],[1600,370,56,-14],[1660,240,60,45]].forEach(p=>pl+=leaf(p[0],p[1],p[2],p[3],'#0c2a33'));
      return '<svg id="lbg" viewBox="0 0 1672 941" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs>'
        +'<linearGradient id="yw" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#070a1d"/><stop offset=".55" stop-color="#0c112e"/><stop offset="1" stop-color="#252b69"/></linearGradient>'
        +'<linearGradient id="ys" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a1038"/><stop offset="1" stop-color="#26307f"/></linearGradient>'
        +'<radialGradient id="yf" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#5a58d8" stop-opacity=".55"/><stop offset="1" stop-color="#5a58d8" stop-opacity="0"/></radialGradient>'
        +'<filter id="yb" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"/></filter><filter id="yb2"><feGaussianBlur stdDeviation="14"/></filter></defs>'
        +'<rect width="1672" height="941" fill="url(#yw)"/>'
        +'<rect x="0" y="120" width="86" height="380" fill="#c9bfc8" opacity=".45" filter="url(#yb2)"/>'
        +'<rect x="0" y="540" width="86" height="120" fill="#8d98b8" opacity=".35" filter="url(#yb2)"/>'
        +'<rect x="440" y="96" width="850" height="100" fill="url(#ys)"/><path d="M440 96h850v100H440z" fill="none" stroke="#050818" stroke-width="5"/><path d="M628 96v100M1134 96v100M1146 96v100" stroke="#050818" stroke-width="5"/>'
        +'<rect x="1440" y="40" width="232" height="320" fill="url(#ys)"/><path d="M1440 40v320M1440 150h232M1440 260h232" stroke="#050818" stroke-width="5"/>'
        +st+pl
        +'<path d="M150 -4C260 40 400 78 525 98" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" opacity=".95"/><path d="M150 -4C260 40 400 78 525 98" fill="none" stroke="#bcd0ff" stroke-width="22" stroke-linecap="round" opacity=".35" filter="url(#yb)"/>'
        +'<path d="M1690 22C1600 40 1450 90 1350 140" fill="none" stroke="#9cc0ff" stroke-width="6" stroke-linecap="round"/><path d="M1690 22C1600 40 1450 90 1350 140" fill="none" stroke="#4f86ff" stroke-width="20" stroke-linecap="round" opacity=".45" filter="url(#yb)"/>'
        +'<ellipse cx="836" cy="860" rx="720" ry="150" fill="url(#yf)"/>'
        +'</svg>'
    },
    heroSVG(){
      const R=this.rng(23);let s='';
      for(let i=0;i<230;i++){const y=R()*R()*300,x=R()*822;s+='<circle cx="'+x.toFixed(1)+'" cy="'+y.toFixed(1)+'" r="'+(.4+R()*1.2).toFixed(1)+'" fill="#fff" opacity="'+(.25+R()*.75).toFixed(2)+'"/>'}
      let tr='';
      const pine=(x,y,h,c)=>'<path d="M'+x+' '+(y-h)+'l'+h*.2+' '+h*.32+'h-'+h*.08+'l'+h*.17+' '+h*.3+'h-'+h*.1+'l'+h*.2+' '+h*.38+'H'+(x-h*.35)+'l'+h*.2+'-'+h*.38+'h-'+h*.1+'l'+h*.17+'-'+h*.3+'h-'+h*.08+'z" fill="'+c+'"/>';
      for(let i=0;i<16;i++)tr+=pine(8+i*20+R()*12,520+R()*10,70+R()*60,'#06061c');
      for(let i=0;i<14;i++)tr+=pine(690+i*18+R()*10,525+R()*8,60+R()*60,'#06061c');
      let lt='';for(let i=0;i<14;i++){lt+='<circle cx="'+(30+R()*190).toFixed(0)+'" cy="'+(300+R()*18).toFixed(0)+'" r="1.6" fill="#ffd89a" opacity=".85"/>';lt+='<circle cx="'+(560+R()*240).toFixed(0)+'" cy="'+(302+R()*14).toFixed(0)+'" r="1.6" fill="#ffd89a" opacity=".8"/>'}
      const mt='0,310 0,92 26,60 50,84 66,76 96,128 124,120 168,176 214,196 262,236 318,262 380,282 450,300 520,288 580,262 640,226 690,186 718,160 742,136 770,158 800,186 822,200 822,310';
      const mt2='0,310 0,200 70,215 140,240 210,262 300,286 380,298 470,304 560,296 650,280 730,262 822,250 822,310';
      return '<svg viewBox="0 0 822 545" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs>'
        +'<linearGradient id="zs" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#060838"/><stop offset=".42" stop-color="#1d1782"/><stop offset=".72" stop-color="#4c3bc0"/><stop offset="1" stop-color="#6d57dd"/></linearGradient>'
        +'<linearGradient id="zl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5646c4"/><stop offset=".45" stop-color="#2a2a8c"/><stop offset="1" stop-color="#0c0f3a"/></linearGradient>'
        +'<linearGradient id="zm" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7b6ad8"/><stop offset=".55" stop-color="#3a2f97"/><stop offset="1" stop-color="#26206f"/></linearGradient>'
        +'<linearGradient id="zn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#241d78"/><stop offset="1" stop-color="#150f4a"/></linearGradient>'
        +'<linearGradient id="zv" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#050619" stop-opacity="0"/><stop offset=".55" stop-color="#050619" stop-opacity="0"/><stop offset="1" stop-color="#050619" stop-opacity=".62"/></linearGradient>'
        +'<filter id="zb"><feGaussianBlur stdDeviation="9"/></filter><filter id="zb2"><feGaussianBlur stdDeviation="2.4"/></filter></defs>'
        +'<rect width="822" height="310" fill="url(#zs)"/>'
        +'<ellipse cx="500" cy="120" rx="360" ry="46" transform="rotate(-24 500 120)" fill="#9aa6ff" opacity=".2" filter="url(#zb)"/>'
        +s
        +'<polygon points="'+mt+'" fill="url(#zm)"/>'
        +'<polygon points="0,92 26,60 50,84 66,76 52,110 40,96 24,118 10,100" fill="#e9eaff" opacity=".85"/><polygon points="690,186 718,160 742,136 770,158 758,176 742,168 728,184 712,176" fill="#e3e4ff" opacity=".8"/>'
        +'<polygon points="'+mt2+'" fill="url(#zn)"/>'
        +'<rect y="300" width="822" height="245" fill="url(#zl)"/>'
        +'<g opacity=".62" transform="translate(0 600) scale(1 -1)" filter="url(#zb2)"><polygon points="'+mt+'" fill="#6a58cf"/></g>'
        +'<rect y="300" width="822" height="3" fill="#8d7cf0" opacity=".5"/>'
        +lt+tr
        +'<rect width="822" height="545" fill="url(#zv)"/></svg>'
    },
    /* ---- iskelet ---- */
    build(){
      const el=this.el=document.createElement('div');
      el.id='lobby';el.setAttribute('role','dialog');el.setAttribute('aria-label','Nex VR başlatıcı');
      el.innerHTML=this.bgSVG()
      +'<div id="lstage">'
      +'<svg id="lglass" viewBox="0 0 1672 941" aria-hidden="true"><defs><linearGradient id="yg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#262d6e" stop-opacity=".82"/><stop offset="1" stop-color="#141a4c" stop-opacity=".86"/></linearGradient><filter id="yf2" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="9"/></filter></defs>'
      +'<path d="M100 126C420 178 1230 178 1568 136Q1604 134 1604 172L1600 756Q1598 776 1568 773C1230 722 420 722 105 777Q76 781 76 750L88 160Q88 128 100 126Z" fill="#6f86ff" opacity=".28" filter="url(#yf2)"/>'
      +'<path d="M100 126C420 178 1230 178 1568 136Q1604 134 1604 172L1600 756Q1598 776 1568 773C1230 722 420 722 105 777Q76 781 76 750L88 160Q88 128 100 126Z" fill="url(#yg)" stroke="rgba(150,170,255,.45)" stroke-width="2.5"/></svg>'
      +'<aside id="lside"><div class="llogo" data-a="home" role="button" aria-label="Ana menü">'+this.vrBig()+'<b>Nex VR</b><small>v1.0.0</small></div><nav id="lnav" aria-label="Ana menü"></nav></aside>'
      +'<section id="lmain"><div id="lart">'+this.heroSVG()+'</div><div id="lbody"></div></section>'
      +'<aside id="lright">'
      +'<div id="lstat"><div id="lbat"><div class="bar"><i id="lbi" style="width:80%"></i></div><span id="lbt">%87</span></div>'
      +'<svg id="lwf" viewBox="0 0 24 20" aria-label="Ağ"><path d="M1.5 6.8a15 15 0 0 1 21 0M5 10.6a10 10 0 0 1 14 0M8.4 14.2a5.2 5.2 0 0 1 7.2 0"/><circle cx="12" cy="17.6" r="1.7"/></svg>'
      +'<button id="lgear" type="button" data-a="settings" aria-label="Ayarlar">'+this.ic('gear')+'</button></div>'
      +'<div class="lc" id="linfo"><h3>'+this.ic('info')+'Uygulama Bilgisi</h3>'
      +'<div class="ir"><span>Sürüm</span><b>v1.0.0</b></div><div class="ir"><span>Geliştirici</span><b>Emir Pro</b></div><div class="ir"><span>Platform</span><b>Android</b></div>'
      +'<p>En iyi VR deneyimi için tasarlanmıştır.</p>'+this.ic('star','st')+'</div>'
      +'<div class="lc" id="lvrs" data-a="vrchk" role="button" aria-label="VR durumunu yenile"><h3>'+this.ic('bars')+'VR Durumu</h3>'
      +'<div class="bd"><div class="ck"><svg viewBox="0 0 24 24"><path d="m5.5 12.5 4.3 4.3 8.7-9.6"/></svg></div><div class="tt"><b id="lvt">VR Cihazı Bağlı Değil</b><small id="lvs">Lütfen VR cihazınızı takın.</small></div>'
      +'<svg class="gl" viewBox="0 0 140 80" fill="none" stroke="#dfe6ff" stroke-width="8" stroke-linejoin="round"><path d="M17 36c0-15 6-24 22-24h62c16 0 22 9 22 24v10c0 14-8 22-20 22h-9c-7 0-11-3-14-8-2-3-4-4-7-4s-5 1-7 4c-3 5-7 8-14 8h-9c-12 0-26-8-26-22z"/></svg></div></div>'
      +'<div class="lc" id="lquick"><h3>'+this.ic('bolt')+'Hızlı Erişim</h3><div class="tl">'
      +'<button class="qt" type="button" data-a="calib">'+this.ic('cal')+'Kalibrasyon</button>'
      +'<button class="qt" type="button" data-a="vrset">'+this.ic('gear')+'VR Ayarları</button>'
      +'<button class="qt" type="button" data-a="tema">'+this.ic('pal')+'Tema</button></div></div>'
      +'</aside>'
      +'<div id="lhl"></div><div id="lhr"></div>'
      +'<div id="lhint"><svg viewBox="0 0 140 80" aria-hidden="true"><path d="M17 36c0-15 6-24 22-24h62c16 0 22 9 22 24v10c0 14-8 22-20 22h-9c-7 0-11-3-14-8-2-3-4-4-7-4s-5 1-7 4c-3 5-7 8-14 8h-9c-12 0-26-8-26-22z"/></svg><span>En iyi deneyim için VR gözlüğünüzü takın ve Başlat’a basın.</span></div>'
      +'</div>';
      document.body.appendChild(el);
      this.stage=el.querySelector('#lstage');this.nav=el.querySelector('#lnav');this.main=el.querySelector('#lmain');this.body=el.querySelector('#lbody');
      el.addEventListener('click',e=>{
        const b=e.target.closest&&e.target.closest('[data-a]');
        if(!b||!el.contains(b))return;
        e.stopPropagation();
        const f=b._f||this.A[b.dataset.a];
        if(f)f.call(this,b)
      });
      this.built=true
    },
    A:{
      home(){this.page='home';this.render()},
      settings(){this.page='settings';this.render()},
      calib(){this.page='calib';this.render()},
      vrset(){this.page='vr';this.render()},
      about(){this.page='about';this.render()},
      tema(){const a=((Settings.v.acc|0)+1)%4;this.set('acc',a);this.theme();this.render();this.toast('Tema: '+this.ACCN[a],'var(--ok)')},
      vrchk(){
        this.vrText('kontrol ediliyor…');
        XR.ok=false;this.status();this.toast('VR hazır — Stereo/Cardboard modu kullanılıyor','var(--ok)')
      },
      start(){this.start()},
      exit(){this.exit()}
    },
    /* ---- sol menü ---- */
    renderNav(){
      const n=this.nav;n.textContent='';
      const items=[['home','Ana Menü','home'],['settings','Ayarlar','gear'],['calib','Kalibrasyon','cal'],['vr','VR Ayarları','vr'],['hand','El Takibi','hand'],['about','Hakkında','info'],['exit','Çıkış','exit']];
      items.forEach(it=>{
        const b=this.h('button','lni');b.type='button';b.dataset.a='f';
        b.innerHTML=this.ic(it[2])+'<span>'+it[1]+'</span>';
        if(it[0]===this.page)b.classList.add('cur'),b.setAttribute('aria-current','page');
        if(it[0]==='hand'){
          const on=!!Hand.on,sp=this.h('span','sw'+(on?' on':''));
          sp.appendChild(this.h('i'));b.setAttribute('role','switch');b.setAttribute('aria-checked',on?'true':'false');
          b.appendChild(sp);
          b.id='lhandrow';b._f=()=>this.toggleHand()
        }else if(it[0]==='exit'){
          if(this.exitAt&&Date.now()-this.exitAt<3200){b.querySelector('span').textContent='Emin misin? Tekrar bas'}
          b._f=()=>this.exit()
        }else b._f=()=>{this.page=it[0];this.render()};
        n.appendChild(b)
      })
    },
    toggleHand(){
      if(this.busy)return;
      this.busy=true;
      const done=()=>{this.busy=false;this.renderNav();if(this.page==='calib'||this.page==='about')this.renderMain()};
      let p;
      try{p=Hand.on?(Hand.stop(),null):Hand.start()}catch(e){this.toast('El takibi başlatılamadı','var(--err)')}
      Promise.resolve(p).then(done,done);
      this.renderNav()
    },
    exit(){
      if(!this.exitAt||Date.now()-this.exitAt>3200){
        this.exitAt=Date.now();this.renderNav();
        this.toast('Çıkmak için 3 sn içinde tekrar bas','var(--warn)');
        setTimeout(()=>{if(this.open)this.renderNav()},3300);
        return
      }
      this.exitAt=0;
      let ok=false;
      try{if(window.AndroidBridge&&NX_T&&typeof AndroidBridge.exitApp==='function')ok=AndroidBridge.exitApp(NX_T)}catch(e){}
      if(!ok){try{window.close()}catch(e){}this.toast('Uygulamayı sistem tuşlarıyla kapatabilirsin','var(--warn)');this.renderNav()}
    },
    start(){
      if(!this.open)return;
      const f=this.go;this.go=null;
      this.hide();
      f&&f()
    },
    /* ---- orta kart ---- */
    renderMain(){
      const b=this.body,pg=this.page;
      b.textContent='';this.main.classList.toggle('dim',pg!=='home');
      if(pg==='home'){
        const d=this.h('div','hero');
        d.innerHTML='<div class="hv-ic">'+this.vrBig()+'</div><h1>Nex VR</h1><p class="q">“Sanal gerçekliğe adım atın!”</p><p class="d">VR dünyasının kapılarını aralayın. Bu uygulama ile<br>favori VR deneyimlerinize kolayca başlayabilirsiniz.</p>'
          +'<button class="go" type="button" data-a="start" aria-label="Başlat">'+this.ic('play')+'<span>Başlat</span><svg class="ch" viewBox="0 0 24 24" aria-hidden="true"><path d="m8.5 4 8 8-8 8"/></svg></button>';
        b.appendChild(d);return
      }
      const w=this.h('div','pg'),hd=this.h('div','pgh'),bk=this.h('button','bk');
      bk.type='button';bk.dataset.a='f';bk._f=()=>{this.page='home';this.render()};bk.setAttribute('aria-label','Ana menüye dön');
      bk.innerHTML='<svg viewBox="0 0 24 24"><path d="M15 4 7 12l8 8"/></svg>';
      const T={settings:['Ayarlar','Genel tercihler'],calib:['Kalibrasyon','Bakış ve el takibi'],vr:['VR Ayarları','Gözlük profili ve görüntü'],about:['Hakkında','Nex VR']}[pg];
      hd.append(bk,this.h('h2',null,T[0]),this.h('p',null,T[1]));w.appendChild(hd);
      const v=Settings.v;
      if(pg==='settings'){
        const swr=this.h('div','sws');
        ACC.forEach((c,i)=>{const s=this.h('button',(v.acc|0)===i?'cur':'');s.type='button';s.style.background=c;s.style.color=c;s.setAttribute('aria-label',this.ACCN[i]);s.dataset.a='f';s._f=()=>{this.set('acc',i);this.theme();this.render()};swr.appendChild(s)});
        w.appendChild(this.row('Vurgu rengi',swr));
        const T2=(k,label,sub,after)=>w.appendChild(this.row(label,this.sw(!!v[k],()=>{this.set(k,!v[k]);if(after)after(!v[k]);this.render()},label),sub));
        T2('reduce','Hareketi azalt','Animasyonları kapatır');
        T2('awake','Ekranı açık tut','VR içinde ekran kararmasın');
        T2('pass','Kamera geçişi','Gerçek ortam arka planda görünür');
        T2('saver','Düşük güç modu','Kare hızını sınırlar');
        T2('shz','Android uygulamaları VR penceresinde','Shizuku gerekir; kapalıyken normal ekranda açılır');
        T2('fps','FPS sayacı');
        T2('hdraw','El çizimi','Elin ekranda görünmesi',on=>{if(!on)try{Hand.clr()}catch(e){}});
        T2('pdbg','Performans monitörü','FPS, CPU/GPU süreleri, el gecikmesi, güven, RAM, darboğaz')
      }else if(pg==='calib'){
        w.appendChild(this.row('Bakış yönünü sıfırla',this.btn('Sıfırla',()=>{try{Cam.reset()}catch(e){}this.toast('Bakış yönü sıfırlandı','var(--ok)')}),'Ön tarafı şu an baktığın yön yap'));
        w.appendChild(this.row('Hareket sensörü',this.sw(!!Cam.gyro,()=>{const p=Cam.gyro?Cam.disableGyro():Cam.enableGyro();Promise.resolve(p).then(()=>this.render(),()=>this.render());this.render()},'Hareket sensörü'),'Kafa dönüşünü telefon sensöründen al'));
        w.appendChild(this.row('El takibi',this.sw(!!Hand.on,()=>this.toggleHand(),'El takibi')));
        w.appendChild(this.row('Kamera',this.stp(v.hcam==='user'?'Ön':'Arka',()=>this.camFlip(),()=>this.camFlip(),'Kamera')));
        w.appendChild(this.row('Çimdik hassasiyeti',this.stp((v.hclk||3)+' / 5',()=>this.num('hclk',-1,1,5,1),()=>this.num('hclk',1,1,5,1),'Çimdik hassasiyeti')));
        {const HV=['kontur','ikisi','kumanda'],HVN=['Parmak konturu','Kontur + kumanda','Kumanda'],hi=Math.max(0,HV.indexOf(Hand.view()));
          const hv=k=>{this.set('hview',HV[k]);try{Hand.hide3D();Hand.draw()}catch(e){}this.render()};
          w.appendChild(this.row('El görünümü',this.stp(HVN[hi],()=>hv((hi+2)%3),()=>hv((hi+1)%3),'El görünümü'),'İçi boş siyah parmak konturları ya da kumanda modeli'))}
        w.appendChild(this.row('El yumuşatma',this.stp((v.hsm||3)+' / 5',()=>{this.num('hsm',-1,1,5,1);if(Hand.on)try{Hand.initF()}catch(e){}},()=>{this.num('hsm',1,1,5,1);if(Hand.on)try{Hand.initF()}catch(e){}},'El yumuşatma')));
        const t=this.h('div','tst');t.id='lhs';t.append(this.h('i'),this.h('span',null,'Çimdik testi: önce el takibini aç'));
        w.appendChild(this.row('Canlı test',t))
      }else if(pg==='vr'){
        let pi=this.pi>=0?this.pi:Math.max(0,this.PROF.findIndex(p=>p.id===(v.vrProfile||'cardboard')));
        this.pi=pi;const P=this.PROF;
        w.appendChild(this.row('Gözlük profili',this.stp(P[pi].name,()=>{this.pi=(pi+P.length-1)%P.length;this.render()},()=>{this.pi=(pi+1)%P.length;this.render()},'Gözlük profili')));
        w.appendChild(this.row('Seçili profili uygula',this.btn('Uygula',()=>{const p=P[this.pi];Settings.v.vrProfile=p.id;Settings.v.vrEyeSep=p.eye;Settings.v.vrFov=p.fov;Settings.v.vrOffsetY=p.offset;Settings.v.vrScale=p.scale;Settings.save();this.pi=-1;this.render();this.toast(p.name+' profili uygulandı','var(--ok)')}),'Başlangıç değerleri, gözle ince ayar yap'));
        w.appendChild(this.row('Gözler arası mesafe',this.stp(Math.round((v.vrEyeSep||.064)*1000)+' mm',()=>this.num('vrEyeSep',-1,.052,.075,.001,1),()=>this.num('vrEyeSep',1,.052,.075,.001,1),'Gözler arası mesafe')));
        w.appendChild(this.row('VR görüş açısı',this.stp((v.vrFov||75)+'°',()=>this.num('vrFov',-1,60,100,2),()=>this.num('vrFov',1,60,100,2),'VR görüş açısı')));
        w.appendChild(this.row('Dikey görüntü hizası',this.stp(Math.round((v.vrOffsetY||0)*1000)+' mm',()=>this.num('vrOffsetY',-1,-.03,.03,.005,1),()=>this.num('vrOffsetY',1,-.03,.03,.005,1),'Dikey hiza')));
        w.appendChild(this.row('VR performans ölçeği',this.stp(Math.round((v.vrScale||.85)*100)+'%',()=>this.num('vrScale',-1,.6,1,.05,1),()=>this.num('vrScale',1,.6,1,.05,1),'VR ölçeği')))
      }else if(pg==='about'){
        const kv=(a,b)=>w.appendChild(this.row(a,this.h('span','v',b)));
        kv('Uygulama','Nex VR');kv('Sürüm','v1.0.0');kv('Geliştirici','Emir Pro');kv('Platform','Android');
        kv('Motor','Three.js · Stereo (Cardboard) · MediaPipe');
        kv('VR modu','Stereo/Cardboard');kv('El takibi',Hand.on?'Açık':'Kapalı');
        w.appendChild(this.h('div','lr tx','Tarayıcı içinde çalışan uzamsal masaüstü. Başlat’a bastığında VR masaüstü açılır.'))
      }
      b.appendChild(w)
    },
    camFlip(){
      Settings.v.hcam=Settings.v.hcam==='user'?'environment':'user';Settings.save();
      try{Hand.on?Hand.restart():Pass.refresh()}catch(e){}
      this.render()
    },
    render(){this.theme();this.renderNav();this.renderMain()},
    /* ---- durum çubuğu ---- */
    vrText(t){const e=this.el.querySelector('#lvs');if(e)e.textContent=t},
    status(){
      if(!this.built)return;
      const q=s=>this.el.querySelector(s);
      if(navigator.getBattery&&!this.bat&&!this.batAsked){
        this.batAsked=true;
        navigator.getBattery().then(b=>{this.bat=b;b.addEventListener('levelchange',()=>this.status());b.addEventListener('chargingchange',()=>this.status());this.status()}).catch(()=>{})
      }
      const bt=q('#lbat');
      if(this.bat){
        const p=Math.round(this.bat.level*100);
        bt.style.display='';q('#lbt').textContent='%'+p;
        const i=q('#lbi');i.style.width=Math.max(8,p)+'%';i.style.background=p<=20&&!this.bat.charging?'#ff4d5e':'#3ddc84'
      }else bt.style.display='none';
      q('#lwf').classList.toggle('off',navigator.onLine===false);
      const ok=!!XR.ok;
      q('#lvt').textContent=ok?'VR Cihazı Hazır':'VR Cihazı Bağlı Değil';
      q('#lvs').textContent=ok?'Başlat’a basarak VR’a geç.':'Lütfen VR cihazınızı takın.'
    },
    /* ---- el takibi → sahne ---- */
    setHov(b){
      if(this.hov===b)return;
      if(this.hov)this.hov.classList.remove('hv');
      this.hov=b;
      if(b)b.classList.add('hv')
    },
    press(b){
      b.classList.add('pz');
      setTimeout(()=>b.classList.remove('pz'),160);
      b.click()
    },
    hands(S){
      const W=innerWidth,H=innerHeight;let any=null;
      for(const s of S){
        const i=s.id;
        if(!s.on||!s.d){this.prev[i]=false;continue}
        const x=s.dsx*W,y=s.dsy*H,t=document.elementFromPoint(x,y),b=t&&t.closest?t.closest('#lobby [data-a]'):null;
        if(b&&(!any||s.pr))any=b;
        if(s.pr&&!this.prev[i]&&b&&performance.now()-this.ck>380){this.ck=performance.now();this.press(b)}
        this.prev[i]=s.pr
      }
      this.setHov(any)
    },
    loop(){
      if(!this.open){this.raf=0;return}
      this.raf=requestAnimationFrame(()=>this.loop());
      const t=performance.now();
      if(Hand.on){try{Hand.tick(t)}catch(e){}}
      if(t-this.lt<160)return;
      this.lt=t;
      const S=Hand.slots||[],live=Hand.on&&S.some(s=>s.on&&s.d);
      if(!live){this.setHov(null);this.prev[0]=this.prev[1]=false}
      const hs=this.el.querySelector('#lhs');
      if(hs){
        const pin=Hand.on&&S.some(s=>s.on&&s.pr),has=Hand.on&&S.some(s=>s.on);
        hs.className='tst'+(pin?' pinch':has?' hand':'');
        hs.lastChild.textContent=!Hand.on?'Çimdik testi: önce el takibini aç':pin?'Çimdik algılandı':has?'El algılandı — parmaklarını birleştir':'El aranıyor…'
      }
      const hr=this.el.querySelector('#lhandrow');
      if(hr&&!this.busy){const sw=hr.querySelector('.sw');if(sw&&sw.classList.contains('on')!==!!Hand.on){sw.classList.toggle('on',!!Hand.on);sw.setAttribute('aria-checked',Hand.on?'true':'false')}}
    },
    show(go){
      if(!this.built)this.build();
      this.go=go;this.open=true;this.page='home';this.exitAt=0;this.pi=-1;
      const ld=$('#load');if(ld)ld.style.display='none';
      this.el.classList.add('on');
      this.theme();this.fit();this.render();this.status();
      this._rs=this._rs||(()=>this.fit());
      addEventListener('resize',this._rs);
      if(!this.raf)this.loop();
      try{Diag.say('Nex VR başlatıcı. Başlat düğmesine basarak VR masaüstünü aç.')}catch(e){}
    },
    hide(){
      this.open=false;
      if(this.el)this.el.classList.remove('on');
      removeEventListener('resize',this._rs||(()=>{}));
      cancelAnimationFrame(this.raf);this.raf=0;
      this.setHov(null);this.prev[0]=this.prev[1]=false
    }
  };
