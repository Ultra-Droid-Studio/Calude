class OE2{
  constructor(mc,b,dc,dz){this.mc=Math.max(.05,mc);this.b=b;this.dc=dc||1;this.dz=dz||0;this.x=null;this.dx=0;this.t=0}
  a(c,dt){const r=6.283185307179586*c*dt;return r/(r+1)}
  f(v,t,k){
    if(!Number.isFinite(v))return this.x===null?v:this.x;
    if(this.x===null){this.x=v;this.t=Number.isFinite(t)?t:0;this.dx=0;return v}
    if(!Number.isFinite(t))return this.x;
    const dt=(t-this.t)/1000;
    if(!(dt>=.004))return this.x;
    if(dt>.25){this.x=v;this.t=t;this.dx=0;return v}
    const raw=((k>0&&Number.isFinite(k))?k:1)*(v-this.x)/dt;
    this.dx+=this.a(this.dc,dt)*(raw-this.dx);
    const sp=Math.max(0,Math.abs(this.dx)-this.dz);
    this.x+=this.a(this.mc+this.b*sp,dt)*(v-this.x);
    this.t=t;return this.x}
}
module.exports=OE2;
