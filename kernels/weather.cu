// Moving world-space weather. All lattice periods divide the 4800 m origin cell.
// C[15]: 0 seeded climate, 1 clear, 2 overcast, 3 rain, 4 thunderstorm, -1 legacy/off.
__device__ float weatherNoise(float x,float z,int scale,const int* O,unsigned int salt){
 float u=x/(float)scale,v=z/(float)scale,fx=fractf(u),fz=fractf(v);
 unsigned int stride=4800u/(unsigned int)scale;
 unsigned int ix=(unsigned int)(int)floorf(u)+(unsigned int)O[0]*stride,iz=(unsigned int)(int)floorf(v)+(unsigned int)O[1]*stride;
 unsigned int seed=(unsigned int)O[2]+salt;fx=fx*fx*(3-2*fx);fz=fz*fz*(3-2*fz);
 return lerpf(lerpf(hash2((int)ix,(int)iz,seed),hash2((int)(ix+1u),(int)iz,seed),fx),lerpf(hash2((int)ix,(int)(iz+1u),seed),hash2((int)(ix+1u),(int)(iz+1u),seed),fx),fz);
}
__device__ float climatePressure(float x,float z,float time,const int* O){
 float phase=hash2(O[2],17,9021u)*2*PI;
 float dx=time*6+900*sinf(time/900+phase),dz=time*2.5f+800*cosf(time/1100+phase);
 float epoch=floorf(time/1200),blend=smoothf(0,1,fractf(time/1200));
 float a=weatherNoise(x-dx,z-dz,4800,O,9200u+(unsigned int)(int)epoch*17u);
 float b=weatherNoise(x-dx,z-dz,4800,O,9217u+(unsigned int)(int)epoch*17u);
 return lerpf(a,b,blend);
}
// cloud cover, rain, convection, accumulated wetness (finite history).
__device__ float4 weatherAt(float x,float z,float time,float mode,const int* O){
 if(mode<0)return make_float4(0,0,0,0);
 if(mode>.5f){if(mode<1.5f)return make_float4(.04f,0,0,0);if(mode<2.5f)return make_float4(.90f,0,0,.08f);if(mode<3.5f)return make_float4(.94f,.7f,.12f,.9f);return make_float4(1,1,1,1);}
 float pressure=climatePressure(x,z,time,O);
 float rain=smoothf(.51f,.78f,pressure),storm=smoothf(.73f,.92f,pressure);
 float past1=smoothf(.51f,.78f,climatePressure(x,z,time-45,O)),past2=smoothf(.51f,.78f,climatePressure(x,z,time-150,O));
 float past3=smoothf(.51f,.78f,climatePressure(x,z,time-420,O));
 float wet=sat(rain*.45f+past1*.30f+past2*.25f+past3*.20f);
 return make_float4(smoothf(.18f,.68f,pressure),rain,storm,wet);
}
__device__ float weatherWaveGain(float x,float z,float time,float mode,const int* O){
 if(mode<0)return 1;
 float p=mode>.5f?(mode<1.5f?.15f:(mode<2.5f?.46f:(mode<3.5f?.65f:.92f))):climatePressure(x,z,time-35,O);
 return .65f+smoothf(.18f,.90f,p)*1.15f;
}
__device__ float weatherFlash(float x,float z,float time,float storm,const int* O){
 if(storm<.15f)return 0;
 int gx=(int)floorf(x/CELL)+O[0],gz=(int)floorf(z/CELL)+O[1];
 float epoch=floorf(time/19),seed=hash2(gx,gz,(unsigned int)O[2]+(unsigned int)(int)epoch*31u+9811u);
 float age=fractf(time/19)*19-(2+seed*14);
 float flash=expf(-powf(age/.055f,2))+expf(-powf((age-.16f)/.035f,2))*.6f;
 return flash*storm;
}
__device__ float3 weatherSky(float3 ro,float3 rd,float3 sun,float time,float mode,const int* O,float disk){
 float3 color=skyRadiance(rd,sun,disk,.01f);if(mode<0)return color;
 float night=1-smoothf(-.18f,.02f,sun.y);
 if(rd.y>0&&night>0){
  // A fixed celestial field, seeded once by the world, covered by weather clouds.
  float u=atan2f(rd.z,rd.x)*600,v=atan2f(rd.y,sqrtf(fmaxf(0,1-rd.y*rd.y)))*600;
  int ix=(int)floorf(u),iy=(int)floorf(v);float star=hash2(ix,iy,(unsigned int)O[2]+12391u);
  float dx=fractf(u)-.5f,dy=fractf(v)-.5f;
  float points=star>.996f?expf(-(dx*dx+dy*dy)*65)*night*smoothf(0,.12f,rd.y):0;
  float3 moon=make_float3(-sun.x,-sun.y,-sun.z);
  float diskMoon=smoothf(.99990f,.99997f,dot3(rd,moon))*night;
  color=color+make_float3(.65f,.73f,.9f)*(points*.55f+diskMoon*.22f);
 }
 if(rd.y<=.015f)return color;
 // Three thin density layers approximate depth without a volume ray march.
 for(int layer=2;layer>=0;layer--){
  float height=1050+(float)layer*230,travel=(height-ro.y)/rd.y;
  if(travel<0)continue;travel=fminf(travel,65000);
  float3 p=ro+rd*travel;float4 w=weatherAt(p.x,p.z,time,mode,O);
  float broad=weatherNoise(p.x-time*6,p.z-time*2.5f,600,O,9401u+(unsigned int)layer);
  float fine=weatherNoise(p.x-time*7,p.z-time*3,150,O,9407u);
  float density=broad*.78f+fine*.22f;
  float alpha=smoothf(.82f-w.x*.60f,.98f-w.x*.58f,density)*smoothf(.015f,.1f,rd.y);
  float light=weatherNoise(p.x-time*6+sun.x*90,p.z-time*2.5f+sun.z*90,600,O,9401u+(unsigned int)layer);
  float edge=sat(.5f+(density-light)*5);
  float3 cloud=mix3(make_float3(.46f,.51f,.57f),make_float3(.065f,.085f,.12f),w.z*.7f+w.y*.25f);
  float twilight=(1-smoothf(.02f,.35f,sun.y))*smoothf(-.18f,.02f,sun.y);
  cloud=mix3(cloud,cloud*make_float3(1.15f,.62f,.38f),twilight*.55f);
  cloud=cloud*lerpf(.012f,1,smoothf(-.18f,.06f,sun.y));
  cloud=cloud+sunRadiance(sun)*(edge*.12f*(1-w.y*.75f));
  cloud=cloud+make_float3(.8f,.86f,1)*weatherFlash(p.x,p.z,time,w.z,O)*2;
  color=mix3(color,cloud,alpha);
 }
 return color;
}
// One seeded vertical/slanted rain column per 1.5 m cell. The same phase is used
// by airborne drops and surface impacts: y + 18*time crosses an 8 m period.
__device__ float4 rainColumn(int ix,int iz,const int* O){
 unsigned int gx=(unsigned int)ix+(unsigned int)O[0]*3200u,gz=(unsigned int)iz+(unsigned int)O[1]*3200u;
 unsigned int seed=(unsigned int)O[2]+9500u;
 return make_float4(((float)ix+hash2((int)gx,(int)gz,seed))*1.5f,((float)iz+hash2((int)gx,(int)gz,seed+1u))*1.5f,hash2((int)gx,(int)gz,seed+2u),hash2((int)gx,(int)gz,seed+3u));
}
__device__ float rainImpact(float3 p,float fp,float time,float rain,const int* O){
 if(rain<.02f||fp>.3f)return 0;
 float x=p.x+p.y*.08f,z=p.z+p.y*.025f;
 float4 col=rainColumn((int)floorf(x/1.5f),(int)floorf(z/1.5f),O);if(col.w>rain)return 0;
 float age=fractf((p.y+time*18)/8-col.z)*8/18;
 if(age>.28f)return 0;
 float dx=x-col.x,dz=z-col.y,r=sqrtf(dx*dx+dz*dz),radius=age*.38f;
 float ring=1-smoothf(.008f+fp*.3f,.02f+fp,fabsf(r-radius));
 return ring*(1-age/.28f)*weight(fp,4);
}
__device__ float rainVisibility(float3 ro,float3 rd,float limit,float cone,float time,float rain,const int* O){
 if(ro.y<0||rain<.02f)return 0;
 float3 a=make_float3(ro.x+ro.y*.08f,ro.y,ro.z+ro.y*.025f),d=make_float3(rd.x+rd.y*.08f,rd.y,rd.z+rd.y*.025f);
 int ix=(int)floorf(a.x/1.5f),iz=(int)floorf(a.z/1.5f),sx=d.x>=0?1:-1,sz=d.z>=0?1:-1;
 float tx=fabsf(d.x)>.000001f?(((float)ix+(sx>0?1:0))*1.5f-a.x)/d.x:100000;
 float tz=fabsf(d.z)>.000001f?(((float)iz+(sz>0?1:0))*1.5f-a.z)/d.z:100000;
 float dx=1.5f/fmaxf(.000001f,fabsf(d.x)),dz=1.5f/fmaxf(.000001f,fabsf(d.z));
 float start=0,alpha=0,stop=fminf(limit,30),horizontal=d.x*d.x+d.z*d.z;
 int budget=(int)fminf(64,ceilf(stop*(fabsf(d.x)+fabsf(d.z))/1.5f)+3);
 for(int k=0;k<budget;k++){
  if(start>=stop)break;float end=fminf(stop,fminf(tx,tz));float4 col=rainColumn(ix,iz,O);
  if(col.w<rain){
   float t=clampf(((col.x-a.x)*d.x+(col.y-a.z)*d.z)/fmaxf(.000001f,horizontal),start,end);
   float3 p=a+d*t;float radius=.0035f+cone*t*.65f,ex=p.x-col.x,ez=p.z-col.y;
   float nearColumn=1-smoothf(radius*.35f,radius,sqrtf(ex*ex+ez*ez));
   float phase=fractf((p.y+time*18)/8-col.z)*8;
   float streak=1-smoothf(.12f,.40f+cone*t,phase);
   alpha+=nearColumn*streak*(.28f/(1+t*.04f))*sqrtf(.0035f/radius);
  }
  if(tx<tz){start=tx;tx+=dx;ix+=sx;}else{start=tz;tz+=dz;iz+=sz;}
 }
 return sat(alpha);
}

__device__ float3 weatherBolt(float3 ro,float3 rd,float time,float storm,const int* O){
 float flash=weatherFlash(ro.x,ro.z,time,storm,O);if(flash<.01f)return make_float3(0,0,0);
 int ix=(int)floorf(ro.x/CELL),iz=(int)floorf(ro.z/CELL);float epoch=floorf(time/19);
 unsigned int seed=(unsigned int)O[2]+(unsigned int)(int)epoch*31u+9821u;
 float bx=((float)ix+.2f+hash2(ix+O[0],iz+O[1],seed)*.6f)*CELL;
 float bz=((float)iz+.2f+hash2(ix+O[0],iz+O[1],seed+1u)*.6f)*CELL;
 float3 a=make_float3(bx,1450,bz);float brightness=0;
 for(int k=0;k<7;k++){
  float3 b=make_float3(bx+(hash2(k,ix+O[0],seed+2u)-.5f)*100,1450-(float)(k+1)*180,bz+(hash2(k,iz+O[1],seed+3u)-.5f)*100);
  float3 ba=b-a,oa=ro-a;float br=dot3(ba,rd),bb=dot3(ba,ba),bo=dot3(ba,oa),rr=dot3(rd,oa);
  float u=clampf((bo-br*rr)/fmaxf(.001f,bb-br*br),0,1),t=dot3(a+ba*u-ro,rd);
  if(t>0){float3 delta=ro+rd*t-a-ba*u;float radius=1+t*.0006f;brightness+=expf(-dot3(delta,delta)/(radius*radius))*expf(-t/12000);}
  a=b;
 }
 return make_float3(.70f,.80f,1)*(brightness*flash*8);
}
