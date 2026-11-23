'use strict';
  /* ---------- Duvar kağıtları (Aşama 46): dosyasız, canvas ile çizilen 360° panoramalar ---------- */
  const WallArt={
    IDS:['sunset','night','aurora','ocean','space','nebula','milkyway','planet','blackhole','neon','earth'],
    cache:{},q:[],qb:false,
    mk(w,h){const c=document.createElement('canvas');c.width=w;c.height=h;return c},
    make(id,W,H){W=W||2048;H=H||1024;const c=this.mk(W,H);this.draw(id,c.getContext('2d'),W,H);return c},
    /* Ayarlar küçük resimleri: ağır çizimi tek tek, boş zamanda yapar */
    thumb(id,done){
      if(this.cache[id])return this.cache[id];
      if(this.q.indexOf(id)<0){this.q.push(id);
        if(!this.qb){this.qb=true;const run=()=>{const n=this.q.shift();if(!n){this.qb=false;return}
          try{if(!this.cache[n])this.keep(n,this.make(n))}catch(e){this.cache[n]=this.mk(2,2)}
          if(done)done();setTimeout(run,90)};setTimeout(run,60)}}
      return null},
    keep(id,cv){const t=this.mk(256,102);t.getContext('2d').drawImage(cv,cv.width*.5625,cv.height*.2,cv.width*.375,cv.height*.3,0,0,256,102);this.cache[id]=t},
    draw(id,x,W,H){
      const hx=W*.75,hy=H/2,TAU=Math.PI*2,mk=this.mk;
      const rng=a=>()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296};
      const cl=(v,a,b)=>v<a?a:v>b?b:v;
      const sm=t=>t<=0?0:t>=1?1:t*t*(3-2*t),ss=(a,b,t)=>sm((t-a)/(b-a));
      const ramp=(st,t,o)=>{let i=0;while(i<st.length-2&&t>st[i+1][0])i++;const a=st[i],b=st[i+1],f=cl((t-a[0])/(b[0]-a[0]),0,1);o[0]=a[1][0]+(b[1][0]-a[1][0])*f;o[1]=a[1][1]+(b[1][1]-a[1][1])*f;o[2]=a[1][2]+(b[1][2]-a[1][2])*f;return o};
      const rgba=(c,a)=>'rgba('+(c[0]|0)+','+(c[1]|0)+','+(c[2]|0)+','+(a==null?1:a)+')';
      /* x yönünde kesintisiz (sarmalı) değer gürültüsü */
      const fbm=(nw,nh,fx,fy,oct,seed,gain)=>{const r=rng(seed),out=new Float32Array(nw*nh);let amp=1,tot=0;gain=gain||.5;
        for(let o=0;o<oct;o++){const cx=fx<<o,cy=fy<<o,g=new Float32Array(cx*(cy+1));for(let i=0;i<g.length;i++)g[i]=r();
          for(let y=0;y<nh;y++){const v=y/nh*cy,y0=v|0,ty=sm(v-y0);for(let xx=0;xx<nw;xx++){const u=xx/nw*cx,x0=u|0,tx=sm(u-x0),x1=(x0+1)%cx,a=g[y0*cx+x0],b=g[y0*cx+x1],c=g[(y0+1)*cx+x0],d=g[(y0+1)*cx+x1];
            out[y*nw+xx]+=amp*((a+(b-a)*tx)*(1-ty)+(c+(d-c)*tx)*ty)}}
          tot+=amp;amp*=gain}
        for(let i=0;i<out.length;i++)out[i]/=tot;return out};
      const samp=(F,nw,nh,u,v)=>{u=((u%1)+1)%1*nw;v=cl(v,0,.9999)*(nh-1);const x0=u|0,y0=v|0,x1=(x0+1)%nw,tx=u-x0,ty=v-y0,y1=Math.min(nh-1,y0+1);
        return(F[y0*nw+x0]*(1-tx)+F[y0*nw+x1]*tx)*(1-ty)+(F[y1*nw+x0]*(1-tx)+F[y1*nw+x1]*tx)*ty};
      /* düşük çözünürlüklü piksel geçişi → büyütülerek tuvale çizilir (bulutlar/nebulalar için) */
      const pass=(fn,f0,f1,nw)=>{nw=nw||512;const nh=nw>>1,y0=Math.round(f0*nh),y1=Math.round(f1*nh),c=mk(nw,y1-y0),g=c.getContext('2d'),im=g.createImageData(nw,y1-y0),d=im.data,o=[0,0,0];
        for(let y=y0;y<y1;y++)for(let xx=0;xx<nw;xx++){fn(xx,y,o,y*nw+xx,nw,nh);const i=((y-y0)*nw+xx)*4;d[i]=o[0];d[i+1]=o[1];d[i+2]=o[2];d[i+3]=255}
        g.putImageData(im,0,0);x.imageSmoothingEnabled=true;x.imageSmoothingQuality='high';x.drawImage(c,0,y0/nh*H,W,(y1-y0)/nh*H)};
      const glow=(cx,cy,r,c,a)=>{const g=x.createRadialGradient(cx,cy,0,cx,cy,r);g.addColorStop(0,rgba(c,a));g.addColorStop(.35,rgba(c,a*.4));g.addColorStop(1,rgba(c,0));x.fillStyle=g;x.fillRect(cx-r,cy-r,r*2,r*2)};
      const dirOf=(u,v)=>{const lo=u*TAU,la=(.5-v)*Math.PI,c=Math.cos(la);return[c*Math.cos(lo),Math.sin(la),c*Math.sin(lo)]};
      const stars=(n,seed,mask,mag)=>{const r=rng(seed);mag=mag||1;
        for(let i=0;i<n;i++){const px=r()*W,py=Math.acos(1-2*r())/Math.PI*H,m=mask?mask(px/W,py/H):1,b=Math.pow(r(),3.4),t=r();if(r()>m)continue;
          const lat=Math.cos((py/H-.5)*Math.PI),sz=(.45+b*1.7)*mag*W/2048,c=t<.18?[255,206,160]:t<.62?[255,255,255]:[180,205,255];
          x.fillStyle=rgba(c,.28+.72*b);x.beginPath();x.ellipse(px,py,sz/Math.max(.3,lat),sz,0,0,TAU);x.fill();
          if(b>.93){glow(px,py,sz*7,c,.35);const L=sz*(5+b*8);x.fillStyle=rgba(c,.3);x.fillRect(px-L,py-.5,L*2,1);x.fillRect(px-.5,py-L,1,L*2)}}};
      /* dağ/tepe silüeti: x yönünde kesintisiz */
      const ridge=(y0,amp,seed,c0,c1,sharp)=>{const r=rng(seed),F=[2,3,5,8,13,21,34,55,89],ph=F.map(()=>r()*TAU),rd=F.map(()=>r()<(sharp==null?.6:sharp));
        const h=px=>{let s=0,t=0;for(let k=0;k<F.length;k++){const a=Math.pow(F[k],-.92),w=Math.sin(TAU*F[k]*px/W+ph[k]);s+=a*(rd[k]?1-Math.abs(w):.5+.5*w);t+=a}return s/t};
        const g=x.createLinearGradient(0,y0-amp,0,y0+4);g.addColorStop(0,rgba(c0));g.addColorStop(1,rgba(c1));
        x.fillStyle=g;x.beginPath();x.moveTo(0,y0+6);for(let px=0;px<=W;px+=3)x.lineTo(px,y0-amp*Math.pow(h(px),1.5)*1.9+amp*.3);x.lineTo(W,y0+6);x.closePath();x.fill()};
      /* su yansıması: ufuk çizgisinden yukarıyı çevirerek aşağıya yazar */
      const lake=(a,dark,rip)=>{x.save();x.globalAlpha=a;x.translate(0,hy*2);x.scale(1,-1);x.drawImage(x.canvas,0,0,W,hy,0,0,W,hy);x.restore();
        const g=x.createLinearGradient(0,hy,0,H);g.addColorStop(0,rgba(dark,.08));g.addColorStop(1,rgba(dark,.9));x.fillStyle=g;x.fillRect(0,hy,W,hy);
        const r=rng(77);for(let i=0;i<rip;i++){const y=hy+Math.pow(r(),1.6)*hy,w=20+r()*160*(y-hy)/hy+10;x.fillStyle='rgba(255,255,255,'+(.015+r()*.05)+')';x.fillRect(r()*W,y,w,1+(y-hy)/hy*2.5)}};
      /* küre (gezegen/Dünya/ay): piksel piksel gölgelendirilir */
      const ball=(cx,cy,r,L,fn,rim,tilt)=>{const s=Math.ceil(r+4),n=s*2,c=mk(n,n),g=c.getContext('2d'),im=g.createImageData(n,n),d=im.data,o=[0,0,0],ln=Math.hypot(L[0],L[1],L[2]),lx=L[0]/ln,ly=L[1]/ln,lz=L[2]/ln,ct=Math.cos(tilt||0),st=Math.sin(tilt||0);
        for(let py=0;py<n;py++)for(let px=0;px<n;px++){const dx=(px+.5-s)/r,dy=(py+.5-s)/r,dd=Math.hypot(dx,dy),a=cl((1-dd)*r+.5,0,1);if(a<=0)continue;
          const nz=Math.sqrt(Math.max(0,1-dd*dd)),nx=dx,ny=-dy,ry=ny*ct-nx*st,rx=nx*ct+ny*st;fn(Math.atan2(rx,nz),Math.asin(cl(ry,-1,1)),o);
          const lam=Math.max(0,nx*lx+ny*ly+nz*lz),sh=.04+.96*ss(0,.5,lam),rm=Math.pow(1-nz,3)*(.2+lam),i=(py*n+px)*4;
          d[i]=o[0]*sh+rim[0]*rm;d[i+1]=o[1]*sh+rim[1]*rm;d[i+2]=o[2]*sh+rim[2]*rm;d[i+3]=a*255}
        g.putImageData(im,0,0);x.drawImage(c,cx-s,cy-s)};
      const nebula=(seed,pal,dens,dust)=>{const F=fbm(512,256,4,2,7,seed,.55),G=fbm(512,256,3,2,5,seed+9),Hh=fbm(512,256,6,3,5,seed+19),o2=[0,0,0];
        pass((xx,y,o,i)=>{const d=Math.pow(ss(dens[0],dens[1],F[i]),1.5),cv=G[i],dk=1-dust*ss(.5,.72,Hh[i]),t=Math.min(1,y/255);
          ramp(pal,cv,o2);const e=1+1.6*ss(.8,1,d)*ss(.45,.7,Hh[i]);
          o[0]=(3+o2[0]*d*e)*dk;o[1]=(3+o2[1]*d*e)*dk;o[2]=(7+o2[2]*d*e)*dk},0,1)};
      const mwBand=(n,u,v)=>{const dd=dirOf(u,v),b=Math.asin(cl(dd[0]*n[0]+dd[1]*n[1]+dd[2]*n[2],-1,1));return Math.exp(-b*b/.045)};
      const SC={
        sunset(){
          const F=fbm(512,256,5,3,6,11),sx=384,sy=106,sk=[[0,[12,14,50]],[.3,[48,34,108]],[.55,[150,62,128]],[.8,[255,118,88]],[1,[255,196,120]]],cc=[0,0,0];
          pass((xx,y,o,i)=>{ramp(sk,y/128,o);let dx=Math.abs(xx-sx);dx=Math.min(dx,512-dx);const dd=dx*dx+(y-sy)*(y-sy),g=Math.exp(-dd/1500),g2=Math.exp(-dd/60000);
            o[0]+=255*g*.8+90*g2;o[1]+=170*g*.8+40*g2;o[2]+=90*g*.7;
            const c=ss(.5,.72,F[i])*ss(8,70,y)*(y<128?1:0),lit=cl(g2*2.2+y/128*.5,0,1);cc[0]=60+195*lit;cc[1]=34+120*lit;cc[2]=92+20*lit-30*lit*lit;
            o[0]+=(cc[0]-o[0])*c*.85;o[1]+=(cc[1]-o[1])*c*.85;o[2]+=(cc[2]-o[2])*c*.85},0,.5);
          stars(500,5,(u,v)=>ss(.3,.04,v)*1.6);
          glow(hx,hy-44,280,[255,170,100],.55);x.fillStyle='#fff1d0';x.beginPath();x.arc(hx,hy-44,34,0,TAU);x.fill();glow(hx,hy-44,70,[255,230,180],.9);
          ridge(hy+2,70,3,[150,70,120],[255,150,110],.45);ridge(hy+2,52,8,[96,48,104],[200,100,100],.6);ridge(hy+2,34,14,[34,22,58],[70,36,80],.7);
          lake(.7,[30,16,44],240);
          for(let i=0;i<70;i++){const y=hy+4+i*i/70*3.4,w=(10+i*1.4)*(.5+Math.random()*.5);x.fillStyle='rgba(255,220,170,'+(.5-i/160).toFixed(2)+')';x.fillRect(hx-w/2+(Math.random()-.5)*20,y,w,1.4)}},
        night(){
          const F=fbm(512,256,5,3,6,31),n=[.3,.82,-.5],sk=[[0,[3,5,18]],[.5,[10,18,48]],[1,[34,52,104]]];
          pass((xx,y,o,i)=>{ramp(sk,y/128,o);const mw=mwBand(n,xx/512,y/256)*.55;o[0]+=60*mw;o[1]+=72*mw;o[2]+=110*mw;
            let dx=Math.abs(xx-384);dx=Math.min(dx,512-dx);const g=Math.exp((dx*dx+(y-60)*(y-60))/-2600),c=ss(.55,.74,F[i])*ss(10,80,y);
            o[0]+=80*g;o[1]+=100*g;o[2]+=140*g;const l=.25+g*1.4;o[0]+=(28+110*l-o[0])*c*.5;o[1]+=(38+130*l-o[1])*c*.5;o[2]+=(70+150*l-o[2])*c*.5},0,.5);
          stars(2400,9,(u,v)=>.45+.55*mwBand(n,u,v));glow(hx,hy*.5,230,[150,180,255],.55);
          x.fillStyle='#eef2fb';x.beginPath();x.arc(hx,hy*.5,42,0,TAU);x.fill();x.save();x.beginPath();x.arc(hx,hy*.5,42,0,TAU);x.clip();
          const r=rng(4);for(let i=0;i<16;i++){x.fillStyle='rgba(120,135,170,'+(.16+r()*.2)+')';x.beginPath();x.arc(hx-40+r()*80,hy*.5-40+r()*80,3+r()*11,0,TAU);x.fill()}
          const sg=x.createRadialGradient(hx-14,hy*.5-14,10,hx,hy*.5,52);sg.addColorStop(0,'rgba(0,0,0,0)');sg.addColorStop(1,'rgba(10,20,50,.55)');x.fillStyle=sg;x.fillRect(hx-50,hy*.5-50,100,100);x.restore();
          ridge(hy+2,80,21,[28,40,76],[10,16,36],.55);ridge(hy+2,44,6,[8,12,28],[5,8,18],.7);lake(.32,[2,4,12],260);
          for(let i=0;i<50;i++){x.fillStyle='rgba(220,230,255,'+(.4-i/140).toFixed(2)+')';x.fillRect(hx-(14+i*.8)*(.5+Math.random()*.5),hy+6+i*i/50*4.2,(14+i*.8),1.5)}},
        aurora(){
          const cc=[0,0,0],V=fbm(512,256,3,2,3,43),R=fbm(512,256,96,2,2,41,.5),ph=[.1,.55,.8],ac=[[0,[80,255,150]],[.3,[40,190,190]],[.7,[120,90,230]],[1,[200,70,200]]];
          pass((xx,y,o,i)=>{const t=y/128;o[0]=2+4*t;o[1]=6+16*t;o[2]=16+26*t;
            for(let k=0;k<3;k++){const yc=.66-.12*k+.07*Math.sin(TAU*(xx/512*(2+k)+ph[k]))+.035*Math.sin(TAU*(xx/512*(7+k*2)+ph[k]*3)),dy=yc-t,I=(dy>0?Math.exp(-dy*dy/.07):Math.exp(-dy*dy/.0035))*(.45+.8*ss(.28,.82,R[y*512+(xx+k*83)%512]));
              ramp(ac,cl(dy/.5,0,1),cc);const s=I*(k?.4:.75)*(.25+1.2*ss(.35,.7,V[y*512+(xx+k*150)%512]));o[0]+=cc[0]*s;o[1]+=cc[1]*s;o[2]+=cc[2]*s}},0,.5);
          stars(1600,12,(u,v)=>.9);
          const r=rng(8);x.fillStyle='#03090c';for(let px=-10;px<W;px+=6+r()*14){const h=34+r()*r()*110,w=h*.26;for(let k=0;k<4;k++){const yy=hy+6-h*(1-k*.2)*.55*k/3-h*.0,ww=w*(1-k*.22),hh=h*.5;x.beginPath();x.moveTo(px-ww,hy+6-h*.22*k+hh*.0);x.lineTo(px,hy+6-h*.22*k-hh*.9);x.lineTo(px+ww,hy+6-h*.22*k);x.closePath();x.fill()}x.fillRect(px-1.5,hy,3,8)}
          x.fillRect(0,hy,W,6);lake(.7,[2,8,12],200)},
        ocean(){
          const F=fbm(512,256,7,4,6,51),sx=384,sy=44,sk=[[0,[34,100,196]],[.6,[104,170,232]],[1,[214,238,252]]];
          pass((xx,y,o,i)=>{ramp(sk,y/128,o);let dx=Math.abs(xx-sx);dx=Math.min(dx,512-dx);const dd=dx*dx+(y-sy)*(y-sy),g=Math.exp(-dd/2000),g2=Math.exp(-dd/40000);
            o[0]+=200*g+40*g2;o[1]+=190*g+36*g2;o[2]+=150*g+20*g2;const c=ss(.55,.7,F[i])*ss(0,30,y)*(1-g2*.55)*.92,sh=cl(.98-(F[Math.min(i+512*5,F.length-1)]-F[i])*9,.8,1);
            o[0]+=(250*sh-o[0])*c;o[1]+=(252*sh-o[1])*c;o[2]+=(255*sh+6-o[2])*c},0,.5);
          const W2=fbm(512,256,12,96,3,52),W3=fbm(512,256,6,40,4,53);
          pass((xx,y,o,i)=>{const t=(y-128)/128;ramp([[0,[96,172,204]],[.3,[22,112,160]],[1,[4,36,78]]],t,o);let dx=Math.abs(xx-sx);dx=Math.min(dx,512-dx);
            const w=ss(.6,.84,W2[i])*(.4+.6*t)+ss(.55,.8,W3[i])*.12,gl=Math.exp(-dx*dx/(40+t*900))*ss(.5,.8,W2[i])*(1-t*.45)*1.5;
            o[0]+=60*w+255*gl;o[1]+=90*w+230*gl;o[2]+=110*w+170*gl},.5,1);
          glow(hx,hy*.47,300,[255,240,200],.5);glow(hx,hy*.47,60,[255,255,240],1);ridge(hy+1,9,2,[120,170,190],[190,220,232],.3)},
        space(){
          nebula(61,[[0,[30,70,200]],[.5,[140,60,190]],[1,[40,170,190]]],[.3,.68],.5);
          const r=rng(3),gx=hx,gy=H*.4,ca=Math.cos(-.45),sa=Math.sin(-.45),S=W*.13;x.globalCompositeOperation='lighter';
          glow(gx,gy,S*1.8,[170,150,255],.25);
          for(let i=0;i<34000;i++){const p=Math.pow(r(),.8),arm=(r()<.5?0:Math.PI),a=arm+1.9*Math.log(1+p*4)+(r()-.5)*(.25+.9*p)*(.6+r()),rr=p*S,px=Math.cos(a)*rr,py=Math.sin(a)*rr*.42,X=gx+px*ca-py*sa,Y=gy+px*sa+py*ca,w=1-p;
            x.fillStyle=rgba(p<.3?[255,224,180]:p<.7?[170,200,255]:[200,150,255],.08+.4*w*r());x.fillRect(X,Y,1.2+r()*1.3,1.2+r()*1.1)}
          glow(gx,gy,S*.45,[255,226,180],.95);x.globalCompositeOperation='source-over';stars(2600,23,null,1.1)},
        nebula(){
          nebula(77,[[0,[255,120,40]],[.45,[240,50,140]],[.8,[70,60,200]],[1,[40,190,210]]],[.38,.74],.7);
          const r=rng(5);x.globalCompositeOperation='lighter';for(let i=0;i<46;i++){const a=r()*TAU,d=Math.pow(r(),1.4)*W*.045;glow(hx+Math.cos(a)*d,H*.42+Math.sin(a)*d*.7,10+r()*16,[200,225,255],.8)}
          glow(hx,H*.42,260,[255,150,120],.35);x.globalCompositeOperation='source-over';stars(2200,31,null,1.1)},
        milkyway(){
          const n0=[.86,.2,.42],nl=Math.hypot(n0[0],n0[1],n0[2]),n=[n0[0]/nl,n0[1]/nl,n0[2]/nl],F=fbm(512,256,10,5,6,71),G=fbm(512,256,24,12,4,72),Dn=fbm(512,256,6,3,5,73),c0=dirOf(.7,.34),pr=c0[0]*n[0]+c0[1]*n[1]+c0[2]*n[2],c1=[c0[0]-pr*n[0],c0[1]-pr*n[1],c0[2]-pr*n[2]],cn=Math.hypot(c1[0],c1[1],c1[2]),core=[c1[0]/cn,c1[1]/cn,c1[2]/cn];
          pass((xx,y,o,i)=>{const u=xx/512,v=y/256,dd=dirOf(u,v),b=Math.asin(cl(dd[0]*n[0]+dd[1]*n[1]+dd[2]*n[2],-1,1)),D=Math.exp(-b*b/.045),C=Math.exp(-(1-(dd[0]*core[0]+dd[1]*core[1]+dd[2]*core[2]))*3.6),
              dust=1-.85*ss(.48,.66,Dn[i])*D,gr=(.5+G[i])*(.5+F[i]),I=D*(.3+.8*C)*dust*gr*.9,ag=Math.exp(-Math.pow((y-128)/26,2))*.5*(y<128?1:0);
            o[0]=3+I*(150+110*C)+ag*10;o[1]=5+I*(140+60*C)+ag*38;o[2]=12+I*(160-20*C)+ag*26;const s=ss(0,128,y);o[0]+=(4-o[0]*.2)*0;if(y>=128){o[0]=2;o[1]=3;o[2]=5}},0,1);
          stars(4200,81,(u,v)=>.22+.78*mwBand(n,u,v),.85);
          ridge(hy+2,60,2,[18,22,30],[6,8,12],.5);ridge(hy+2,32,9,[8,10,14],[3,4,6],.7);
          const g=x.createLinearGradient(0,hy,0,H);g.addColorStop(0,'#05070a');g.addColorStop(1,'#010203');x.fillStyle=g;x.fillRect(0,hy,W,hy)},
        planet(){
          nebula(91,[[0,[40,70,190]],[.6,[110,60,180]],[1,[30,140,160]]],[.5,.85],.4);stars(2600,92,null,1);
          const cx=hx,cy=H*.4,R=W*.062,ang=-.32,F=fbm(1024,512,4,2,6,95),pal=[[0,[120,86,60]],[.3,[205,165,110]],[.6,[232,206,150]],[1,[170,120,80]]],c2=[0,0,0];
          glow(cx,cy,R*3.4,[200,170,255],.16);
          const rings=(front)=>{x.save();x.translate(cx,cy);x.rotate(ang);x.scale(1,.26);x.lineCap='butt';
            for(let k=0;k<44;k++){const rr=R*(1.38+k*.0205),gp=(k>26&&k<30)?.12:1,a=(.12+.55*Math.abs(Math.sin(k*1.7)))*gp*(k>40?.5:1);x.strokeStyle=rgba(k%3?[222,200,160]:[190,160,120],a);x.lineWidth=R*.021;x.beginPath();if(front)x.arc(0,0,rr,0,Math.PI);else x.arc(0,0,rr,Math.PI,TAU);x.stroke()}x.restore()};
          rings(false);
          ball(cx,cy,R,[-.7,.5,.55],(lo,la,o)=>{const n=samp(F,1024,512,lo/TAU,.5-la/Math.PI),t=Math.sin(la*11+(n-.5)*5)*.5+.5;ramp(pal,t,o);const sp=Math.exp(-(Math.pow((lo-.9)*2.4,2)+Math.pow((la+.38)*5,2)));o[0]+=(170-o[0])*sp*.7;o[1]+=(90-o[1])*sp*.7;o[2]+=(60-o[2])*sp*.7},[255,210,150],-ang*.6);
          x.save();x.translate(cx,cy);x.rotate(ang);x.scale(1,.26);x.save();x.beginPath();x.rect(-R*3,0,R*6,R*3);x.clip();rings(false);x.restore();x.restore();
          x.save();x.translate(cx,cy);x.rotate(ang);x.scale(1,.26);for(let k=0;k<44;k++){const rr=R*(1.38+k*.0205),gp=(k>26&&k<30)?.12:1,a=(.12+.55*Math.abs(Math.sin(k*1.7)))*gp*(k>40?.5:1);x.strokeStyle=rgba(k%3?[222,200,160]:[190,160,120],a);x.lineWidth=R*.021;x.beginPath();x.arc(0,0,rr,0,Math.PI);x.stroke()}x.restore();
          const M=fbm(256,128,4,2,5,96);ball(cx-R*2.8,cy-R*.9,R*.17,[-.7,.5,.55],(lo,la,o)=>{const n=samp(M,256,128,lo/TAU,.5-la/Math.PI);o[0]=o[1]=o[2]=120+n*110},[200,200,220]);
          ball(cx+R*2.4,cy+R*1.35,R*.09,[-.7,.5,.55],(lo,la,o)=>{o[0]=205;o[1]=170;o[2]=140},[255,230,200])},
        blackhole(){
          nebula(101,[[0,[120,30,60]],[.6,[70,40,150]],[1,[30,70,130]]],[.52,.86],.5);stars(2800,102,null,1);
          const cx=hx,cy=H*.47,R=W*.042;glow(cx,cy,R*9,[255,120,50],.3);
          const disk=(front)=>{x.save();x.beginPath();x.rect(0,front?cy:0,W,front?H:cy);x.clip();x.translate(cx,cy);x.scale(1,.15);
            const g=x.createRadialGradient(0,0,R*1.05,0,0,R*4.6);g.addColorStop(0,'rgba(255,252,240,0)');g.addColorStop(.21,'rgba(255,252,240,0)');g.addColorStop(.23,'rgba(255,252,240,1)');g.addColorStop(.32,'rgba(255,208,120,.95)');g.addColorStop(.5,'rgba(240,120,40,.8)');g.addColorStop(.75,'rgba(150,40,20,.4)');g.addColorStop(1,'rgba(90,10,10,0)');
            x.fillStyle=g;x.beginPath();x.arc(0,0,R*4.6,0,TAU);x.fill();x.restore()};
          x.globalCompositeOperation='lighter';disk(false);x.globalCompositeOperation='source-over';
          x.fillStyle='#000';x.beginPath();x.arc(cx,cy,R,0,TAU);x.fill();
          const h=x.createRadialGradient(cx,cy,R*.98,cx,cy,R*1.5);h.addColorStop(0,'rgba(255,236,190,0)');h.addColorStop(.64,'rgba(255,236,190,0)');h.addColorStop(.66,'rgba(255,236,190,1)');h.addColorStop(.74,'rgba(255,170,80,.8)');h.addColorStop(.4,'rgba(200,80,30,.22)');h.addColorStop(1,'rgba(150,40,10,0)');
          x.globalCompositeOperation='lighter';x.fillStyle=h;x.beginPath();x.arc(cx,cy,R*1.5,0,TAU);x.fill();
          disk(true);x.globalCompositeOperation='source-over'},
        neon(){
          const NW=1024,sk=[[0,[8,2,36]],[.45,[66,10,104]],[.8,[210,30,124]],[1,[255,128,70]]];
          pass((xx,y,o)=>{ramp(sk,y/256,o)},0,.5,NW);stars(500,2,(u,v)=>ss(.45,.1,v)*1.5);
          const sr=H*.115,sc=mk(Math.ceil(sr*2),Math.ceil(sr*2)),sg=sc.getContext('2d'),g=sg.createLinearGradient(0,0,0,sr*2);g.addColorStop(0,'#fff176');g.addColorStop(.5,'#ff5fa8');g.addColorStop(1,'#a02cff');
          glow(hx,hy-sr*.6,sr*3.4,[255,80,170],.5);sg.fillStyle=g;sg.beginPath();sg.arc(sr,sr,sr,0,TAU);sg.fill();
          for(let k=0;k<8;k++){const yy=sr+k*sr*.115*1.6+sr*.15,hh=sr*.02+k*sr*.0175;sg.clearRect(0,yy,sr*2,hh)}x.drawImage(sc,hx-sr,hy-sr*1.55);
          ridge(hy+1,58,7,[40,8,70],[110,20,120],.7);x.save();x.strokeStyle='rgba(0,240,255,.8)';x.lineWidth=2;x.shadowColor='#0ff';x.shadowBlur=10;x.restore();
          pass((xx,y,o,i,nw,nh)=>{const e=((y+.5)/nh-.5)*Math.PI,t=1/Math.tan(Math.max(e,.004)),az=(xx+.5)/nw*TAU,X=t*Math.cos(az)*1.6,Z=t*Math.sin(az)*1.6,gx=Math.abs((X/2)-Math.round(X/2))*2,gz=Math.abs((Z/2)-Math.round(Z/2))*2,w=.03+t*.02,
              lx=ss(w,0,gx),lz=ss(w,0,gz),f=Math.exp(-t/18)*ss(.35,2,t),hz=Math.exp(-e*14);
            o[0]=14+hz*230+f*(lx*40+lz*255)*.9;o[1]=2+hz*70+f*(lx*230+lz*50)*.9;o[2]=40+hz*110+f*(lx*255+lz*220)*.9},.5,1,NW)},
        earth(){
          const eg=x.createLinearGradient(0,0,0,H);eg.addColorStop(0,'#01020a');eg.addColorStop(.5,'#050a1e');eg.addColorStop(1,'#01020a');x.fillStyle=eg;x.fillRect(0,0,W,H);stars(3200,111,null,1);const cx=hx,cy=H*.42,R=W*.1,F=fbm(1024,512,4,2,7,115,.52),Hh=fbm(1024,512,5,3,5,116),Cc=fbm(1024,512,6,3,6,117,.55),oc=[0,0,0];
          glow(cx+R*.9,cy-R*.75,R*2.2,[255,200,140],.5);glow(cx,cy,R*1.7,[80,140,255],.3);
          ball(cx,cy,R,[.6,.3,.75],(lo,la,o)=>{const u=lo/TAU,v=.5-la/Math.PI,n=samp(F,1024,512,u,v),dr=samp(Hh,1024,512,u,v),c=ss(.58,.82,samp(Cc,1024,512,u,v))*.8,ic=ss(1.2,1.4,Math.abs(la));
            if(n>.52){const k=ss(.52,.7,n);ramp([[0,[44,110,46]],[.5,[96,136,56]],[1,[150,122,84]]],dr+k*.3,o);{const dz=ss(.5,.66,dr)*(1-ss(.25,.6,Math.abs(la)));o[0]+=46*dz;o[1]+=14*dz;o[2]-=10*dz}}else{ramp([[0,[26,92,160]],[1,[8,32,100]]],(.52-n)*6,o)}
            o[0]+=(240-o[0])*Math.max(c*.85,ic);o[1]+=(244-o[1])*Math.max(c*.85,ic);o[2]+=(250-o[2])*Math.max(c*.85,ic)},[90,150,255],.35);
          ball(cx-R*2.2,cy-R*.7,R*.2,[.75,.45,.5],(lo,la,o)=>{o[0]=o[1]=o[2]=150+samp(F,1024,512,lo/TAU,.5-la/Math.PI)*90},[200,200,210])}
      };
      x.fillStyle='#000';x.fillRect(0,0,W,H);(SC[id]||SC.night)()
    }
  };
  /* s: dosya yok/yedek gradyan (WallArt çizilemezse ve küçük resim hazır olana kadar), f: sis rengi. Sıra değişmez: Ayarlar'daki wp indeksi buna bağlı. */
  const WALL=[{id:'sunset',n:'Gün batımı',f:'#5a3a70',s:[[0,'#0b1b4a'],[.3,'#3a3a8c'],[.46,'#e9806e'],[.5,'#ffb38a'],[.56,'#3a2a5c'],[1,'#120d24']]},
    {id:'night',n:'Gece',f:'#0c1438',s:[[0,'#02040d'],[.4,'#0a1233'],[.5,'#1b2a62'],[.56,'#0a1030'],[1,'#02040d']]},
    {id:'aurora',n:'Aurora',f:'#071a22',s:[[0,'#031016'],[.3,'#0a3a3a'],[.45,'#2fb58a'],[.5,'#5a3a9a'],[.56,'#0a1830'],[1,'#030812']]},
    {id:'ocean',n:'Okyanus',f:'#6aa8d8',s:[[0,'#5fb0f0'],[.35,'#3a8fd8'],[.5,'#cdebff'],[.56,'#0f4a7a'],[1,'#062238']]},
    {id:'space',n:'Derin uzay',f:'#05050f',s:[[0,'#04030c'],[.5,'#1a1650'],[1,'#04030c']]},
    {id:'nebula',n:'Nebula',f:'#1a0c24',s:[[0,'#0a0412'],[.5,'#b0306e'],[1,'#10061c']]},
    {id:'milkyway',n:'Samanyolu',f:'#04060a',s:[[0,'#02030a'],[.45,'#6a5a58'],[.5,'#10161c'],[1,'#010203']]},
    {id:'planet',n:'Gezegen',f:'#080818',s:[[0,'#04030c'],[.5,'#cfa56a'],[1,'#04030c']]},
    {id:'blackhole',n:'Kara delik',f:'#0a0510',s:[[0,'#04020a'],[.5,'#f08a30'],[1,'#04020a']]},
    {id:'neon',n:'Neon',f:'#3a0a50',s:[[0,'#08022a'],[.45,'#c81e7c'],[.5,'#ff8046'],[.56,'#12002a'],[1,'#12002a']]},
    {id:'earth',n:'Dünya',f:'#03050f',s:[[0,'#01020a'],[.5,'#2a64b4'],[1,'#01020a']]}];
  const Storage={
    ok:true,
    mem:{},
    get(){
      try{
        return JSON.parse(localStorage.getItem('nexus.v3')||'{}')
      }catch(e){
        this.ok=false;
        return this.mem
      }
    },
    set(o){
      this.mem=o;
      try{
        localStorage.setItem('nexus.v3',JSON.stringify(o))
      }catch(e){
        this.ok=false
      }
    },
    clear(){
      this.mem={};
      try{
        localStorage.removeItem('nexus.v3');
        localStorage.removeItem('nexus.wp')
      }catch(e){}
    }
  };
  const DEF={ghand:0,gaa:0,pxb:0,ghz:0,gwin:0,quality:Dev.tier>=2?1:0,dpr:1,sens:1,alpha:.82,acc:0,pitch:1.2,fps:true,reduce:matchMedia('(prefers-reduced-motion:reduce)').matches,auto:false,layout:0,wp:0,fpscap:0,autoq:true,saver:false,inv:false,hcam:'environment',hsm:3,hclk:3,hdw:2,hdraw:true,hprev:false,hsmo:false,hfast:true,shz:true,hcq:0,hone:false,fbr:1,fco:1,fsa:1,fhu:0,fgr:false,fse:false,fov:75,vrProfile:'cardboard',vrEyeSep:.064,vrFov:75,vrOffsetY:0,vrScale:.85,toastms:3800,tbot:false,h24:true,ssec:true,cdec:4,nfs:22,tmin:5,awake:false,pass:true,pscale:1,wdist:2.9,ddist:1.8,pill:true,w7w:1280,w7q:1.25,hmenu:true,hmflip:false,pins:['browser','settings','win7pc','cinema','saber','perf','scene','help']};
  const Settings={
    v:Object.assign({},DEF,Storage.get()),
    save(){
      Storage.set(this.v)
    },
    apply(){
      const v=this.v;
      BAR=v.pill!==false?0:58;
      document.documentElement.style.setProperty('--pri',ACC[v.acc]);
      document.documentElement.classList.toggle('rm',!!v.reduce);
      try{
        const fl=(v.fbr!==1||v.fco!==1||v.fsa!==1||v.fhu||v.fgr||v.fse)?'brightness('+v.fbr+') contrast('+v.fco+') saturate('+v.fsa+') hue-rotate('+v.fhu+'deg)'+(v.fgr?' grayscale(1)':'')+(v.fse?' sepia(1)':''):'';
        document.querySelectorAll('#c,#pass,#pass2').forEach(e=>e.style.filter=fl);
        const tt=$('#toast');tt.style.top=v.tbot?'auto':'calc(12px + env(safe-area-inset-top))';tt.style.bottom=v.tbot?'90px':'auto';
        if(window.THREE&&Cam.cam&&Cam.cam.fov!==v.fov){Cam.cam.fov=v.fov;Cam.cam.updateProjectionMatrix();Scene.dirty=true}
      }catch(e){}
      /* Stage 64: yenileme hızı ve Android pencere sınırı Java'ya yalnızca değişince bildirilir. */
      try{
        if(window.AndroidBridge&&NX_T){
          if(this._hz!==(v.ghz|0)){this._hz=v.ghz|0;if(AndroidBridge.setRefreshRate)AndroidBridge.setRefreshRate(this._hz,NX_T)}
          if(this._gw!==(v.gwin|0)){this._gw=v.gwin|0;if(AndroidBridge.shzSetMaxWin)AndroidBridge.shzSetMaxWin(this._gw,NX_T)}
        }
      }catch(e){}
      if(Renderer.r){
        Renderer.resize();
        Scene.ring.material.color.set(ACC[v.acc]);
        WM.repaintAll()
      }
    }
  };
  if(Array.isArray(Settings.v.pins)){
    const _o=Settings.v.pins.filter(x=>x&&typeof x==='object'&&typeof x.u==='string');
    if(_o.length&&!Array.isArray(Settings.v.bpins))Settings.v.bpins=_o.slice(-12);
    Settings.v.pins=Settings.v.pins.filter(x=>typeof x==='string'&&x!=='pc'&&x!=='rpc')
  }
  if(Array.isArray(Settings.v.pins)&&!Settings.v.cinPin){Settings.v.pins.push('cinema');Settings.v.cinPin=1}
  if(Array.isArray(Settings.v.pins)&&!Settings.v.sabPin){Settings.v.pins.push('saber');Settings.v.sabPin=1}
  if(Array.isArray(Settings.v.pins)&&!Settings.v.plnPin){Settings.v.pins.push('planets');Settings.v.plnPin=1}
  if(Array.isArray(Settings.v.pins)&&!Settings.v.gorPin){Settings.v.pins.push('gorilla');Settings.v.gorPin=1}
  if(Array.isArray(Settings.v.pins)&&!Settings.v.stoPin){if(!Settings.v.pins.includes('store'))Settings.v.pins.splice(Math.min(1,Settings.v.pins.length),0,'store');Settings.v.stoPin=1}
  if(Array.isArray(Settings.v.pins)&&!Settings.v.w7Pin){Settings.v.pins.push('win7pc');Settings.v.w7Pin=1}
