'use strict';
  /* ---------- Çizim: şekiller ve özel ikonlar ---------- */
  function rr(c,x,y,w,h,r){
    c.beginPath();
    c.moveTo(x+r,y);
    c.arcTo(x+w,y,x+w,y+h,r);
    c.arcTo(x+w,y+h,x,y+h,r);
    c.arcTo(x,y+h,x,y,r);
    c.arcTo(x,y,x+w,y,r);
    c.closePath()
  }
  function txt(c,s,x,y,size,col,maxC,bold){
    c.font=(bold?'600 ':'')+size+'px system-ui,sans-serif';
    c.fillStyle=col||'#cfe0ff';
    c.textAlign='left';
    let n=0;
    String(s).split('\n').forEach(l=>{
      while(l.length>maxC){
        let k=l.lastIndexOf(' ',maxC);
        const sp=k>=maxC*.5;
        if(!sp)k=maxC;
        c.fillText(l.slice(0,k),x,y+n*size*1.35);
        l=l.slice(sp?k+1:k);
        n++
      }
      c.fillText(l,x,y+n*size*1.35);
      n++
      });
    return y+n*size*1.35
  }
  function card(c,x,y,w,h,r){
    rr(c,x,y,w,h,r||20);
    c.fillStyle='rgba(255,255,255,.05)';
    c.fill();
    c.lineWidth=1;
    c.strokeStyle='rgba(255,255,255,.09)';
    c.stroke()
  }
  function pl(c,pts,close){
    c.beginPath();
    pts.forEach((p,i)=>i?c.lineTo(p[0],p[1]):c.moveTo(p[0],p[1]));
    if(close)c.closePath();
    c.stroke()
  }
  const FL=(c,a)=>{
    c.save();
    c.globalAlpha=a==null?.3:a;
    c.fill();
    c.restore()
  };
  const PF=(c,pts,a)=>{
    c.beginPath();
    pts.forEach((p,i)=>i?c.lineTo(p[0],p[1]):c.moveTo(p[0],p[1]));
    c.closePath();
    FL(c,a);
    c.stroke()
  };
  const CI=(c,x,y,r,a)=>{
    c.beginPath();
    c.arc(x,y,r,0,6.3);
    if(a)FL(c,a);
    c.stroke()
  };
  const DOTF=(c,x,y,r)=>{
    c.beginPath();
    c.arc(x,y,r,0,6.3);
    c.fill()
  };
  const ICON={
    gorilla:c=>{c.beginPath();c.arc(0,-.2,.3,0,6.3);c.stroke();DOTF(c,-.11,-.24,.05);DOTF(c,.11,-.24,.05);pl(c,[[-.28,.05],[-.6,.5]]);pl(c,[[.28,.05],[.6,.5]]);CI(c,-.6,.52,.1);CI(c,.6,.52,.1)},
    saber:c=>{pl(c,[[-.5,.5],[.5,-.5]]);pl(c,[[-.65,.35],[-.35,.65]]);c.beginPath();c.arc(.5,-.5,.09,0,6.3);c.fill()},
    film:c=>{rr(c,-.6,-.45,1.2,.9,.12);c.stroke();pl(c,[[-.2,-.45],[-.2,.45]]);pl(c,[[.2,-.45],[.2,.45]])},
    close:c=>{
      pl(c,[[-.55,-.55],[.55,.55]]);
      pl(c,[[.55,-.55],[-.55,.55]])
    },
    max:c=>{
      rr(c,-.55,-.55,1.1,1.1,.14);
      c.stroke()
    },
    min:c=>pl(c,[[-.55,0],[.55,0]]),
    plus:c=>{
      pl(c,[[-.6,0],[.6,0]]);
      pl(c,[[0,-.6],[0,.6]])
    },
    minus:c=>pl(c,[[-.6,0],[.6,0]]),
    back:c=>pl(c,[[.3,-.6],[-.3,0],[.3,.6]]),
    fwd:c=>pl(c,[[-.3,-.6],[.3,0],[-.3,.6]]),
    reload:c=>{
      c.beginPath();
      c.arc(0,0,.6,.6,5.5);
      c.stroke();
      pl(c,[[.85,-.62],[.5,-.4],[.84,-.12]])
    },
    home:c=>{
      PF(c,[[-.8,0],[0,-.75],[.8,0],[.55,0],[.55,.7],[-.55,.7],[-.55,0]],.3)
    },
    lock:c=>{
      rr(c,-.55,-.1,1.1,.85,.15);
      FL(c,.35);
      c.stroke();
      c.beginPath();
      c.arc(0,-.1,.32,Math.PI,0);
      c.stroke()
    },
    globe:c=>{
      CI(c,0,0,.85,.25);
      c.beginPath();
      c.ellipse(0,0,.38,.85,0,0,6.3);
      c.stroke();
      pl(c,[[-.85,0],[.85,0]]);
      pl(c,[[-.7,-.42],[.7,-.42]]);
      pl(c,[[-.7,.42],[.7,.42]])
    },
    gear:c=>{
      c.beginPath();
      for(let k=0;k<8;k++){
        const b=k*Math.PI/4;
        [[-.3,.66],[-.16,.92],[.16,.92],[.3,.66]].forEach((p,j)=>{
          const x=Math.cos(b+p[0])*p[1],y=Math.sin(b+p[0])*p[1];
          (k||j)?c.lineTo(x,y):c.moveTo(x,y)
          })
      }
      c.closePath();
      FL(c,.3);
      c.stroke();
      CI(c,0,0,.27)
    },
    chart:c=>{
      [[-.62,.05],[-.15,-.6],[.32,-.25]].forEach(b=>{
        rr(c,b[0],b[1],.3,.78-b[1],.09);
        FL(c,.45);
        c.stroke()
        });
      pl(c,[[-.85,.88],[.85,.88]])
    },
    device:c=>{
      rr(c,-.48,-.88,.96,1.76,.2);
      FL(c,.3);
      c.stroke();
      pl(c,[[-.15,.62],[.15,.62]]);
      CI(c,0,-.3,.17)
    },
    cube:c=>{
      PF(c,[[0,-.9],[.78,-.45],[0,0],[-.78,-.45]],.55);
      PF(c,[[-.78,-.45],[0,0],[0,.9],[-.78,.45]],.15);
      PF(c,[[.78,-.45],[0,0],[0,.9],[.78,.45]],.3)
    },
    help:c=>{
      CI(c,0,0,.85,.25);
      c.beginPath();
      c.arc(0,-.2,.3,Math.PI,Math.PI*2.55);
      c.lineTo(0,.22);
      c.stroke();
      DOTF(c,0,.55,.08)
    },
    pulse:c=>{
      CI(c,0,0,.88,.2);
      pl(c,[[-.6,.05],[-.28,.05],[-.12,-.45],[.12,.5],[.28,.05],[.6,.05]])
    },
    hand:c=>{
      [[-.5,-.2,.9],[-.18,-.62,.9],[.14,-.82,.9],[.46,-.5,.9]].forEach(f=>{
        rr(c,f[0]-.13,f[1],.27,f[2]-f[1]-.1,.135);
        FL(c,.45);
        c.stroke()
        });
      rr(c,-.68,.05,1.36,.9,.34);
      FL(c,.45);
      c.stroke();
      c.save();
      c.translate(-.72,.35);
      c.rotate(.75);
      rr(c,-.14,-.55,.28,.8,.14);
      FL(c,.45);
      c.stroke();
      c.restore()
    },
    compass:c=>{
      CI(c,0,0,.88,.2);
      PF(c,[[0,-.6],[.22,0],[0,.6],[-.22,0]],.6);
      DOTF(c,0,0,.06)
    },
    vr:c=>{
      rr(c,-.92,-.45,1.84,.9,.3);
      FL(c,.3);
      c.stroke();
      CI(c,-.42,0,.22,.4);
      CI(c,.42,0,.22,.4);
      pl(c,[[-.12,.12],[0,.3],[.12,.12]])
    },
    layout:c=>{
      [[-.78,-.78,.7,.7],[.08,-.78,.7,.38],[-.78,.08,.7,.7],[.08,-.32,.7,1.1]].forEach(p=>{
        rr(c,p[0],p[1],p[2],p[3],.13);
        FL(c,.3);
        c.stroke()
        })
    },
    reset:c=>{
      c.beginPath();
      c.arc(0,0,.62,.5,5.4);
      c.stroke();
      pl(c,[[-.1,-.95],[.35,-.62],[-.1,-.3]])
    },
    image:c=>{
      rr(c,-.85,-.7,1.7,1.4,.18);
      FL(c,.25);
      c.stroke();
      CI(c,-.4,-.22,.16,.6);
      pl(c,[[-.85,.5],[-.2,-.05],[.15,.3],[.45,.08],[.85,.42]])
    },
    monitor:c=>{
      rr(c,-.88,-.68,1.76,1.15,.14);
      FL(c,.3);
      c.stroke();
      pl(c,[[-.3,.82],[.3,.82]]);
      pl(c,[[0,.47],[0,.82]])
    },
    sliders:c=>{
      [[-.5,-.3],[0,.3],[.5,-.1]].forEach(s=>{
        pl(c,[[-.85,s[0]],[.85,s[0]]]);
        CI(c,s[1],s[0],.19,.9)
        })
    },
    shield:c=>{
      PF(c,[[0,-.92],[.72,-.58],[.66,.2],[0,.92],[-.66,.2],[-.72,-.58]],.3);
      pl(c,[[-.28,0],[-.05,.25],[.32,-.2]])
    },
    eye:c=>{
      c.beginPath();
      c.moveTo(-.9,0);
      c.quadraticCurveTo(0,-.8,.9,0);
      c.quadraticCurveTo(0,.8,-.9,0);
      c.stroke();
      CI(c,0,0,.25,.6)
    },
    ext:c=>{
      pl(c,[[.1,-.8],[.8,-.8],[.8,-.1]]);
      pl(c,[[.8,-.8],[-.1,.1]]);
      pl(c,[[.55,.3],[.55,.8],[-.8,.8],[-.8,-.55],[-.3,-.55]])
    },
    grid:c=>{
      [[-.8,-.8],[.1,-.8],[-.8,.1],[.1,.1]].forEach(p=>{
        rr(c,p[0],p[1],.7,.7,.16);
        FL(c,.5);
        c.stroke()
        })
    },
    dots:c=>{
      [-.6,0,.6].forEach(x=>{
        c.beginPath();
        c.arc(x,0,.14,0,6.3);
        c.fill()
        })
    },
    user:c=>{
      CI(c,0,-.3,.34,.6);
      c.beginPath();
      c.arc(0,.95,.68,Math.PI,0);
      FL(c,.6);
      c.stroke()
    },
    launch:c=>{[-.6,0,.6].forEach(y=>[-.6,0,.6].forEach(x=>DOTF(c,x,y,.17)))},
    pin:c=>{
      CI(c,0,-.3,.42,.9);
      pl(c,[[0,.1],[0,.9]])
    },
    folder:c=>PF(c,[[-.85,-.55],[-.3,-.55],[-.1,-.3],[.85,-.3],[.85,.65],[-.85,.65]],.3)
  };
  const ICON_TR={close:'Kapat',min:'Küçült',dots:'Büyüt veya eski boyuta döndür',minus:'Paneli küçült',plus:'Paneli büyüt',back:'Geri',fwd:'İleri',reload:'Yenile',home:'Ana sayfa',ext:'Yeni sekmede aç',eye:'Göster',reset:'Sıfırla',folder:'Dosya',launch:'Tüm uygulamalar',pin:'Sabitli'};
  const TC={grid:['#9aa3ff','#5560e8'],globe:['#59b4ff','#2f5bff'],gear:['#a4afd0','#4d587e'],chart:['#4be59a','#12998a'],device:['#c58bff','#6a3fd8'],cube:['#ffb34a','#ff5a3c'],help:['#34e6d6','#1a7fd8'],pulse:['#ff7aa0','#d8284f'],image:['#ff8fb4','#b04bff'],monitor:['#6fd0ff','#3a6bff'],sliders:['#ffc15e','#ff7a3c'],shield:['#7ee8a6','#1aa089'],launch:['#b88cff','#5a4be8']};
  function TILE(c,n,x,y,s){
    const k=TC[n]||['#59b4ff','#2f5bff'],g=c.createLinearGradient(x,y,x+s,y+s);
    g.addColorStop(0,k[0]);
    g.addColorStop(1,k[1]);
    c.save();
    c.shadowColor='rgba(0,0,0,.5)';
    c.shadowBlur=s*.22;
    c.shadowOffsetY=s*.07;
    rr(c,x,y,s,s,s*.3);
    c.fillStyle=g;
    c.fill();
    c.restore();
    c.save();
    rr(c,x,y,s,s,s*.3);
    c.clip();
    const h=c.createLinearGradient(0,y,0,y+s*.6);
    h.addColorStop(0,'rgba(255,255,255,.16)');
    h.addColorStop(1,'rgba(255,255,255,0)');
    c.fillStyle=h;
    c.fillRect(x,y,s,s*.6);
    c.restore();
    rr(c,x+.5,y+.5,s-1,s-1,s*.3);
    c.lineWidth=1.2;
    c.strokeStyle='rgba(255,255,255,.35)';
    c.stroke();
    ICN(c,n,x+s/2,y+s/2,s*.3,'#fff')
  }
  function ICN(c,n,x,y,s,col){
    if(!ICON[n])return;
    c.save();
    c.translate(x,y);
    c.scale(s,s);
    c.lineWidth=.13;
    c.lineCap='round';
    c.lineJoin='round';
    c.strokeStyle=col;
    c.fillStyle=col;
    ICON[n](c);
    c.restore()
  }

  /* Quest 3 tarzı ek ikonlar */
  Object.assign(ICON,{
    bell:c=>{c.beginPath();c.moveTo(-.55,.32);c.bezierCurveTo(-.3,.2,-.36,-.12,-.36,-.26);c.bezierCurveTo(-.36,-.66,.36,-.66,.36,-.26);c.bezierCurveTo(.36,-.12,.3,.2,.55,.32);c.closePath();c.fill();c.beginPath();c.arc(0,.52,.17,0,3.2);c.fill()},
    wifi:c=>{c.lineWidth=.17;[.34,.66,.98].forEach(r=>{c.beginPath();c.arc(0,.5,r,-2.3,-.84);c.stroke()});c.beginPath();c.arc(0,.5,.1,0,6.3);c.fill()},
    chev:c=>{c.lineWidth=.2;pl(c,[[-.5,-.2],[0,.3],[.5,-.2]])},
    chevup:c=>{c.lineWidth=.2;pl(c,[[-.5,.2],[0,-.3],[.5,.2]])},
    chevdown:c=>{c.lineWidth=.2;pl(c,[[-.5,-.2],[0,.3],[.5,-.2]])},
    expand:c=>{c.lineWidth=.13;pl(c,[[-.6,-.18],[-.6,-.6],[-.18,-.6]]);pl(c,[[.6,-.18],[.6,-.6],[.18,-.6]]);pl(c,[[-.6,.18],[-.6,.6],[-.18,.6]]);pl(c,[[.6,.18],[.6,.6],[.18,.6]])},
    qcam:c=>{c.lineWidth=.15;rr(c,-.66,-.36,1.32,.92,.2);c.stroke();c.beginPath();c.arc(0,.1,.3,0,6.3);c.stroke();c.fillRect(-.28,-.56,.56,.15)},
    qleaf:c=>{c.beginPath();c.moveTo(-.78,.74);c.bezierCurveTo(-1.02,-.3,-.1,-.98,.92,-.92);c.bezierCurveTo(.84,-.1,.12,.92,-.78,.74);c.closePath();c.fill()},
    dots9:c=>{for(let i=-1;i<=1;i++)for(let j=-1;j<=1;j++){c.beginPath();c.arc(i*.46,j*.46,.13,0,6.3);c.fill()}},
    search:c=>{c.lineWidth=.17;c.beginPath();c.arc(-.1,-.1,.46,0,6.3);c.stroke();pl(c,[[.24,.24],[.62,.62]])},
    qmic:c=>{rr(c,-.2,-.62,.4,.8,.2);c.fill();c.lineWidth=.14;c.beginPath();c.arc(0,-.05,.42,.2,Math.PI-.2);c.stroke();pl(c,[[0,.37],[0,.66]])},
    qbook:c=>{c.lineWidth=.14;c.beginPath();c.moveTo(-.4,-.6);c.lineTo(.4,-.6);c.lineTo(.4,.6);c.lineTo(0,.28);c.lineTo(-.4,.6);c.closePath();c.stroke()},
    qbookf:c=>{c.beginPath();c.moveTo(-.4,-.6);c.lineTo(.4,-.6);c.lineTo(.4,.6);c.lineTo(0,.28);c.lineTo(-.4,.6);c.closePath();c.fill()},
    vdots:c=>{for(const y of [-.46,0,.46]){c.beginPath();c.arc(0,y,.12,0,6.3);c.fill()}},
    ring:c=>{c.lineWidth=.14;c.save();c.setLineDash([.18,.2]);c.beginPath();c.arc(0,0,.62,0,6.3);c.stroke();c.restore();c.beginPath();c.arc(0,0,.12,0,6.3);c.fill()}
  });
  function curveZ(u,x){if(!u.curved)return 0;const Rc=u.R*1.9;return Rc-Math.sqrt(Math.max(1,Rc*Rc-x*x))}
  /* Chrome çubuğu yardımcıları (UPSIDEvr WindowChrome.kt'den): Google "G", kilit, yıldız, küçük kutucuk simgeleri */
  function drawGK(c,cx,cy,r){
    c.save();c.lineWidth=r*.42;c.lineCap='butt';const d=Math.PI/180;
    [['#ea4335',200,115],['#fbbc05',135,66],['#34a853',45,91],['#4285f4',0,46]].forEach(a=>{c.strokeStyle=a[0];c.beginPath();c.arc(cx,cy,r,a[1]*d,(a[1]+a[2])*d);c.stroke()});
    c.beginPath();c.moveTo(cx,cy);c.lineTo(cx+r+c.lineWidth/2,cy);c.stroke();c.restore()
  }
  function drawLockK(c,cx,cy,col){
    c.save();c.strokeStyle=col;c.fillStyle=col;c.lineWidth=2.4;c.beginPath();c.arc(cx,cy-4,5,Math.PI,0);c.stroke();
    rr(c,cx-7.5,cy-2,15,11.5,2.5);c.fill();c.restore()
  }
  function starK(c,cx,cy,o,i,col,fill){
    c.save();c.beginPath();
    for(let k=0;k<10;k++){const r=k%2?i:o,a=(-90+k*36)*Math.PI/180;k?c.lineTo(cx+r*Math.cos(a),cy+r*Math.sin(a)):c.moveTo(cx+r*Math.cos(a),cy+r*Math.sin(a))}
    c.closePath();c.lineJoin='round';c.lineWidth=2.4;c.strokeStyle=col;c.fillStyle=col;if(fill)c.fill();else c.stroke();c.restore()
  }
  function iconK(c,n,x,y,col){
    c.save();c.translate(x,y);c.strokeStyle=c.fillStyle=col;c.lineWidth=2.4;c.lineCap='round';c.lineJoin='round';
    if(n==='clock'){c.beginPath();c.arc(0,0,11,0,6.3);c.stroke();c.beginPath();c.moveTo(0,-6);c.lineTo(0,1);c.lineTo(5,4);c.stroke()}
    else if(n==='star'){c.restore();starK(c,x,y,12,5.4,col,false);return}
    else if(n==='hist'){c.beginPath();c.arc(1,0,10,-2.6,4.3);c.stroke();c.beginPath();c.moveTo(-10,-5);c.lineTo(-10,2);c.lineTo(-3,1);c.stroke();c.beginPath();c.moveTo(1,-5);c.lineTo(1,1);c.lineTo(5,4);c.stroke()}
    else if(n==='gearK'){c.beginPath();c.arc(0,0,4,0,6.3);c.stroke();for(let k=0;k<8;k++){const a=k*Math.PI/4;c.beginPath();c.moveTo(Math.cos(a)*8,Math.sin(a)*8);c.lineTo(Math.cos(a)*12,Math.sin(a)*12);c.stroke()}c.beginPath();c.arc(0,0,8,0,6.3);c.stroke()}
    c.restore()
  }
  /* Quest 3 pencere düğmesi: yuvarlak, üzerine gelince dolgu */
  function qbtn(c,B,cx,cy,ic,fn,nm,on){
    const r=22,hv=B(cx-r,cy-r,r*2,r*2,'',fn,false,null,'raw',nm);
    if(hv||on){c.beginPath();c.arc(cx,cy,r,0,6.3);c.fillStyle=hv?(ic==='close'?'rgba(238,76,88,.92)':'rgba(255,255,255,.17)'):'rgba(255,255,255,.12)';c.fill()}
    ICN(c,ic,cx,cy,12,'#f3f7f8');return hv
  }
  function rayCyl(ray,R){
    const o=ray.origin,d=ray.direction,a=d.x*d.x+d.z*d.z;
    if(a<1e-6)return null;
    const b=2*(o.x*d.x+o.z*d.z),cc=o.x*o.x+o.z*o.z-R*R,D=b*b-4*a*cc;
    if(D<0)return null;
    const t=(-b+Math.sqrt(D))/(2*a);
    return t>0?o.clone().addScaledVector(d,t):null
  }
  const DOT={ok:'#3ddc84',wn:'#ff9a2e',no:'#ff4d5e',na:'#6b7899'};
  function drawGroups(c,gs,x,y0,colW,rh,maxY,cols){
    let cx=x,y=y0,col=0;
    gs.forEach(g=>{
      const need=(g.r.length+1)*rh+8;
      if(y+need>maxY&&col<cols-1){
        col++;
        cx=x+col*(colW+24);
        y=y0
      }
      txt(c,g.g,cx,y+rh*.7,20,ACC[Settings.v.acc],30,true);
      y+=rh;
      g.r.forEach(r=>{
        c.fillStyle=DOT[r[2]];
        c.beginPath();
        c.arc(cx+8,y+rh*.45,5,0,6.3);
        c.fill();
        txt(c,r[0],cx+26,y+rh*.65,20,'#a9b6d3',30);
        c.textAlign='right';
        c.fillStyle='#fff';
        c.font='20px system-ui';
        c.fillText(String(r[1]).slice(0,26),cx+colW,y+rh*.65);
        c.textAlign='left';
        y+=rh
        });
      y+=8
      })
  }
