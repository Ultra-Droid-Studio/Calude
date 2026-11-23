'use strict';
  /* ---------- Stage 74: el özellikleri (parmak bükülmesi, çimdik, avuç yönü, hız, güven) ----------
     Native yolda bu değerler C++'ta (app/src/main/cpp/hand_kinematics.cpp) hesaplanır ve mesajın "K" bloğuyla gelir.
     Worker (tarayıcı MediaPipe) yolunda ya da native kitaplık yüklenemediğinde AYNI formüller burada JS ile hesaplanır,
     böylece üst katmanlar (kontur, goril oyunu, jestler) iki yolda da aynı veriyi görür.
     Dizi düzeni (25 sayı): 0 güven, 1 avuç boyu, 2..6 bükülme (başparmak→serçe, 0 düz..1 bükük),
     7..10 çimdik (başparmak ucu→işaret/orta/yüzük/serçe ucu ÷ avuç boyu), 11..14 komşu parmak açıklığı (rad),
     15..17 avuç normali, 18..21 el dönüşü (kuaterniyon x,y,z,w), 22..24 hız (avuç/sn x,y; boyut değişimi 1/sn). */
  const HandFeat={
    F:{VALID:1,REJ:2,REACQ:4,FIST:8,OPEN:16,PINCH:32,FAR:64,PARTIAL:128,RIGHT:256},
    N:25,
    CH:[[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16],[17,18,19,20]],
    /* "K,yuva,bayrak,25 sayı" → {slot,flags,k:Float32Array(25)} (bozuksa null) */
    parseK(seg){
      const f=seg.split(',');
      if(f.length<3+this.N)return null;
      const k=new Float32Array(this.N);
      for(let i=0;i<this.N;i++){const v=+f[3+i];k[i]=Number.isFinite(v)?v:0}
      return{slot:f[1]|0,flags:f[2]|0,k}
    },
    _v:new Float64Array(30),
    /* lm: 21 {x,y,z}; a: en-boy oranı (x ve z ölçeği); out: Float32Array(25). Dönen: bayraklar. C++ ile aynı formüller. */
    compute(lm,a,score,right,out,prevPinch){
      const P=(i,o)=>{const p=lm[i];o[0]=p.x*a;o[1]=p.y;o[2]=(p.z||0)*a;return o};
      const A=[0,0,0],B=[0,0,0],C=[0,0,0],D=[0,0,0],E=[0,0,0],W=[0,0,0];
      const sub=(u,v,o)=>{o[0]=u[0]-v[0];o[1]=u[1]-v[1];o[2]=u[2]-v[2];return o};
      const ang=(u,v)=>{const lu=Math.hypot(u[0],u[1],u[2]),lv=Math.hypot(v[0],v[1],v[2]);if(lu<1e-9||lv<1e-9)return 0;return Math.acos(clamp((u[0]*v[0]+u[1]*v[1]+u[2]*v[2])/(lu*lv),-1,1))};
      const u1=[0,0,0],u2=[0,0,0];
      const s1=Math.hypot((lm[9].x-lm[0].x)*a,lm[9].y-lm[0].y),s2=Math.hypot((lm[5].x-lm[17].x)*a,lm[5].y-lm[17].y)*1.15,size=Math.max(s1,s2),inv=size>1e-6?1/size:0;
      out[1]=size;
      P(0,W);
      for(let f=0;f<5;f++){
        const c=this.CH[f];P(c[0],A);P(c[1],B);P(c[2],C);P(c[3],D);
        let sum=ang(sub(B,A,u1),sub(C,B,u2))+ang(sub(C,B,u1),sub(D,C,u2));
        if(f===0){sum+=.5*ang(sub(A,W,u1),sub(B,A,u2));out[2]=clamp((sum-.25)/1.6,0,1)}
        else{sum+=ang(sub(A,W,u1),sub(B,A,u2));out[2+f]=clamp((sum-.35)/3.6,0,1)}
      }
      P(4,E);
      for(let f=1;f<5;f++){P(this.CH[f][3],D);out[6+f]=Math.hypot(D[0]-E[0],D[1]-E[1],D[2]-E[2])*inv}
      for(let f=0;f<4;f++){
        P(this.CH[f][3],D);P(this.CH[f][f===0?1:0],A);sub(D,A,u1);
        P(this.CH[f+1][3],D);P(this.CH[f+1][0],A);sub(D,A,u2);
        out[11+f]=ang(u1,u2)
      }
      /* avuç çerçevesi */
      P(5,A);P(9,B);P(17,C);
      const y=sub(B,W,[0,0,0]),yl=Math.hypot(y[0],y[1],y[2])||1;y[0]/=yl;y[1]/=yl;y[2]/=yl;
      const x=sub(A,C,[0,0,0]),xd=x[0]*y[0]+x[1]*y[1]+x[2]*y[2];x[0]-=y[0]*xd;x[1]-=y[1]*xd;x[2]-=y[2]*xd;
      const xl=Math.hypot(x[0],x[1],x[2])||1;x[0]/=xl;x[1]/=xl;x[2]/=xl;
      const z=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]],sg=right?-1:1;
      out[15]=z[0]*sg;out[16]=z[1]*sg;out[17]=z[2]*sg;
      const m00=x[0],m01=y[0],m02=z[0],m10=x[1],m11=y[1],m12=z[1],m20=x[2],m21=y[2],m22=z[2],tr=m00+m11+m22;
      let qx,qy,qz,qw;
      if(tr>0){const S=Math.sqrt(tr+1)*2;qw=.25*S;qx=(m21-m12)/S;qy=(m02-m20)/S;qz=(m10-m01)/S}
      else if(m00>m11&&m00>m22){const S=Math.sqrt(1+m00-m11-m22)*2;qw=(m21-m12)/S;qx=.25*S;qy=(m01+m10)/S;qz=(m02+m20)/S}
      else if(m11>m22){const S=Math.sqrt(1+m11-m00-m22)*2;qw=(m02-m20)/S;qx=(m01+m10)/S;qy=.25*S;qz=(m12+m21)/S}
      else{const S=Math.sqrt(1+m22-m00-m11)*2;qw=(m10-m01)/S;qx=(m02+m20)/S;qy=(m12+m21)/S;qz=.25*S}
      out[18]=qx||0;out[19]=qy||0;out[20]=qz||0;out[21]=Number.isFinite(qw)?qw:1;
      /* güven: skor × kadraj içinde olma × boyut */
      let outside=0;
      for(let i=0;i<21;i++){const p=lm[i];if(p.x<-.02||p.x>1.02||p.y<-.02||p.y>1.02)outside++}
      let fl=this.F.VALID|(right?this.F.RIGHT:0),conf=clamp(score,0,1)*(1-.6*outside/21);
      if(outside)fl|=this.F.PARTIAL;
      if(size<.06){fl|=this.F.FAR;conf*=clamp(size/.06,0,1)}
      out[0]=conf;
      const c4=(out[3]+out[4]+out[5]+out[6])/4,pd=out[7];
      if(c4>.62)fl|=this.F.FIST;
      if(c4<.22&&out[2]<.5)fl|=this.F.OPEN;
      if(prevPinch?pd<.46:pd<.34)fl|=this.F.PINCH;
      return fl
    },
    /* Bir el yuvasının özellikleri → s.kv (25 sayı) ve s.kf (bayraklar). Native K bu ölçüme aitse doğrudan o kullanılır;
       değilse süzülmüş landmark'lardan JS ile hesaplanır (ölçüm başına en çok bir kez). */
    of(s,aspect){
      if(!s||!s.on||!s.hasT)return null;
      if(s.kin&&s.kinAt===s.lastSeen){s.kv=s.kin;return s}
      if(s.featAt===s.lastSeen&&s.kv)return s;
      const out=s.kjs||(s.kjs=new Float32Array(this.N)),q=s.q,raw=s.raw;
      const lm=s._flm||(s._flm=Array.from({length:21},()=>({x:0,y:0,z:0})));
      for(let i=0;i<21;i++){lm[i].x=q[i].x;lm[i].y=q[i].y;lm[i].z=raw&&raw[i]?(raw[i].z||0):0}
      s.kf=this.compute(lm,aspect||4/3,s.score==null?1:s.score,s.label==='Right',out,s.kf?(s.kf&this.F.PINCH):0);
      s.kv=out;s.featAt=s.lastSeen;
      return s
    }
  };
