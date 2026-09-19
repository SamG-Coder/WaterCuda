// One bounded island descriptor per world cell; empty cells cost only an AABB test.
// Origin holds integer cells, never a large floating-point world position.
struct Island {float x;float z;float radius;float peak;float seed;float c;float s;float aspect;};
__device__ Island describeIsland(int cx,int cz,const int* Origin){
 int gx=cx+Origin[0],gz=cz+Origin[1];unsigned int seed=(unsigned int)Origin[2];Island a;
 a.x=(float)cx*CELL+CELL*.5f+(hash2(gx,gz,seed+1)-0.5f)*600;
 a.z=(float)cz*CELL+CELL*.5f+(hash2(gx,gz,seed+2)-0.5f)*600;
 a.radius=1100+hash2(gx,gz,seed+3)*400;a.peak=180+hash2(gx,gz,seed+4)*260;
 a.seed=hash2(gx,gz,seed+5)*700;
 a.c=cosf(a.seed*.1f);a.s=sinf(a.seed*.1f);a.aspect=1/(.65f+.35f*fractf(a.seed));
 if(hash2(gx,gz,seed+6)<0.28f)a.peak=0;
 return a;
}
__device__ float islandHeight(float x,float z,Island a,float fp){
 if(a.peak==0)return -45;
 float px=(x-a.x)/a.radius,pz=(z-a.z)/a.radius;
 float u=(px*a.c+pz*a.s)*a.aspect,v=-px*a.s+pz*a.c;float r=sqrtf(u*u+v*v);
 if(r>=1)return -45;
 // Only the outer envelope scales with island radius. Interior landforms use
 // metres, so larger islands contain more hills instead of enlarged noise cells.
 float mx=x-a.x,mz=z-a.z;
 float broad=noise2(u*3.1f+a.seed,v*3.1f+a.seed);
 float coast=(noise2(mx/180+a.seed,mz/180)-.5f)*90/a.radius;
 float shape=sat(1-r+((broad-.5f)*.55f+coast)*smoothf(1,.6f,r));
 float warpX=(noise2(mx/650+a.seed,mz/650)-.5f)*150;
 float warpZ=(noise2(mx/650+31,mz/650+a.seed)-.5f)*150;
 float ridge=1-fabsf(noise2((mx+warpX)/310+a.seed,(mz+warpZ)/310)*2-1);
 float base=-45+powf(shape,1.7f)*(a.peak*(.48f+.52f*ridge)+45);
 // Inland relief is exactly zero here; avoid three unused noise evaluations.
 if(base<=2)return base;
 float detail=0,w1=weight(fp,1.0f/95),w2=weight(fp,1.0f/31),w3=weight(fp,1.0f/9);
 if(w1>0)detail+=(noise2((mx+warpX)/95+a.seed,(mz+warpZ)/95)-.5f)*40*w1;
 if(w2>0)detail+=(noise2(mx/31+a.seed,mz/31)-.5f)*13*w2;
 if(w3>0)detail+=(noise2(mx/9+a.seed,mz/9)-.5f)*3*w3;
 // Preserve the submerged shelf and beach; break up inland silhouettes and normals.
 return base+detail*smoothf(2,32,base);

}
__device__ float ground(float x,float z,const int* Origin,float fp){return islandHeight(x,z,describeIsland((int)floorf(x/CELL),(int)floorf(z/CELL),Origin),fp);}
__device__ float3 groundNormal(float3 p,const int* Origin,float fp){
 float e=fmaxf(.4f,fp*.7f);int cx=(int)floorf(p.x/CELL),cz=(int)floorf(p.z/CELL);
 float lx=p.x-(float)cx*CELL,lz=p.z-(float)cz*CELL;
 if(lx>=e&&lz>=e&&lx+e<CELL&&lz+e<CELL){
  // All four taps use one descriptor; keep the boundary fallback for large footprints.
  Island a=describeIsland(cx,cz,Origin);
  return norm3(make_float3(islandHeight(p.x-e,p.z,a,fp)-islandHeight(p.x+e,p.z,a,fp),2*e,islandHeight(p.x,p.z-e,a,fp)-islandHeight(p.x,p.z+e,a,fp)));
 }
 return norm3(make_float3(ground(p.x-e,p.z,Origin,fp)-ground(p.x+e,p.z,Origin,fp),2*e,ground(p.x,p.z-e,Origin,fp)-ground(p.x,p.z+e,Origin,fp)));
}
// DDA over cells, then bounded height-field stepping inside each island box.
// Fixed budgets bound GPU work. The draw distance is finite; the seeded world is not.
__device__ float traceLand(float3 ro,float3 rd,const int* Origin,float limit,float cone){
 float t=0.1f,raySlope=fabsf(rd.y)+3.8f*sqrtf(rd.x*rd.x+rd.z*rd.z);if(ro.y>500){if(rd.y>=-0.0001f)return -1;t=fmaxf(t,(500-ro.y)/rd.y);}
 for(int cell=0;cell<32;cell++){
  if(t>=limit)return -1;float3 p=ro+rd*t;
  if((p.y>500&&rd.y>=0)||(p.y< -46&&rd.y<=0))return -1;
  int cx=(int)floorf(p.x/CELL),cz=(int)floorf(p.z/CELL);
  float bx=(float)(cx+(rd.x>=0?1:0))*CELL,bz=(float)(cz+(rd.z>=0?1:0))*CELL;
  float tx=fabsf(rd.x)>0.000001f?(bx-p.x)/rd.x:1000000.0f;
  float tz=fabsf(rd.z)>0.000001f?(bz-p.z)/rd.z:1000000.0f;
  float end=fminf(limit,t+fmaxf(0.0f,fminf(tx,tz)));
  Island a=describeIsland(cx,cz,Origin);
  if(a.peak>0){float2 range=boxRay(ro,rd,make_float3(a.x-a.radius,-46,a.z-a.radius),make_float3(a.x+a.radius,a.peak+32,a.z+a.radius));
   float s=fmaxf(t,range.x),stop=fminf(end,range.y),previous=s;
   // The longest ray through a 3000 x 518 x 3000 m island box is under 4275 m.
   // A one-metre minimum step and 4352 iterations cover the entire box, including
   // rays nearly parallel to a hillside; never silently drop the rest of the island.
   for(int j=0;j<4352;j++){
    if(s>stop)break;float3 q=ro+rd*s;float fp=fmaxf(0.2f,s*cone);float gap=q.y-islandHeight(q.x,q.z,a,fp);
    if(gap<fmaxf(0.05f,fp*0.15f)){float lo=previous,hi=s;for(int k=0;k<7;k++){float mid=(lo+hi)*0.5f;float3 m=ro+rd*mid;if(m.y>islandHeight(m.x,m.z,a,fmaxf(0.2f,mid*cone)))lo=mid;else hi=mid;}return (lo+hi)*0.5f;}
    previous=s;s+=fmaxf(1.0f,gap/fmaxf(raySlope,.001f));
   }
  }
  t=end+0.04f;
 }
 return -1;
}
// World-metre triplanar detail: avoids stretched top-down noise on steep rock.
__device__ float surfaceNoise(float3 p,float3 n,float frequency){
 float3 w=make_float3(n.x*n.x,n.y*n.y,n.z*n.z);w=w/fmaxf(.001f,w.x+w.y+w.z);
 p=p*frequency;
 return noise2(p.y+17,p.z)*w.x+noise2(p.x,p.z+31)*w.y+noise2(p.x+53,p.y)*w.z;
}
__device__ float shoreWetness(float3 p,Island a,float fp){
 if(p.y<=0)return 1;if(p.y>=4.5f)return 0;
 float patches=.5f+(noise2((p.x-a.x)*.12f+a.seed,(p.z-a.z)*.12f)-.5f)*weight(fp,.12f);
 float dryingHeight=2.5f+(patches-.5f)*1.6f;
 return 1-smoothf(.15f,dryingHeight,p.y);
}
// Wet sand receives a broad dielectric highlight, rather than a water-like mirror.
__device__ float3 wetSandSheen(float3 diffuse,float3 p,float3 n,float3 rd,float3 sun,const int* Origin,float fp,float shadow){
 if(p.y>=4.5f||p.y< -4)return diffuse;
 Island a=describeIsland((int)floorf(p.x/CELL),(int)floorf(p.z/CELL),Origin);
 float wet=shoreWetness(p,a,fp)*smoothf(.65f,.95f,n.y);if(wet<=0)return diffuse;
 float nv=sat(-dot3(n,rd)),nl=sat(dot3(n,sun));float3 halfVector=norm3(sun-rd);
 float nh=sat(dot3(n,halfVector)),vh=sat(-dot3(rd,halfVector));
 float a2=.20f*.20f,den=nh*nh*(a2-1)+1,D=a2/(PI*den*den);
 float gv=2*nv/(nv+sqrtf(a2+(1-a2)*nv*nv)+.0001f),gl=2*nl/(nl+sqrtf(a2+(1-a2)*nl*nl)+.0001f);
 float directF=.02f+.98f*powf(1-vh,5),viewF=.02f+.98f*powf(1-nv,5);
 float3 rr=rd-n*(2*dot3(rd,n));float3 environment=skyEnvironment(norm3(make_float3(rr.x,.06f,rr.z)),sun);
 float specular=D*gv*gl*directF/(4*fmaxf(nv,.05f));
 return mix3(diffuse,environment,wet*viewF*.65f)+sunRadiance(sun)*(specular*wet*shadow*.75f);
}
__device__ float3 landColor(float3 p,float3 n,float3 sun,const int* Origin,float fp){
 Island a=describeIsland((int)floorf(p.x/CELL),(int)floorf(p.z/CELL),Origin);float u=p.x-a.x,v=p.z-a.z;
 float grain=0.5f+(noise2(u*0.19f,v*0.19f)-0.5f)*weight(fp,0.19f);
 float3 sand=make_float3(0.64f,0.57f,0.39f)*(0.9f+grain*0.2f);
 // Metre-sized vegetation patches, exposed stone and soil give the eye scale.
 float patches=.5f+(noise2(u/42+a.seed,v/42)-.5f)*weight(fp,1.0f/42);
 float scrub=.5f+(noise2(u/9+a.seed,v/9)-.5f)*weight(fp,1.0f/9);
 float foliage=.5f+(noise2(u*.65f,v*.65f)-.5f)*weight(fp,.65f);
 float3 green=mix3(make_float3(.026f,.058f,.019f),make_float3(.115f,.145f,.046f),patches)*(.72f+scrub*.38f+foliage*.18f);
 float stone=.5f+(noise2(u*.22f+p.y*.17f,v*.22f)-.5f)*weight(fp,.28f);
 float strata=noise2(p.y*.8f+noise2(u*.07f,v*.07f)*1.5f,u*.11f+v*.07f);strata=lerpf(.5f,strata,weight(fp,.8f));
 float3 rock=mix3(make_float3(.12f,.135f,.13f),make_float3(.33f,.31f,.26f),stone*.7f+strata*.3f);
 float beachEdge=3+(noise2(u/18+a.seed,v/18)-.5f)*3;
 float3 col=mix3(sand,green,smoothf(beachEdge,beachEdge+8,p.y));
 float exposure=(1-smoothf(.65f,.91f,n.y))*smoothf(7,25,p.y);
 exposure=fmaxf(exposure,smoothf(.62f,.82f,patches)*smoothf(55,150,p.y)*.55f);
 col=mix3(col,rock,exposure);

 // Sub-metre colour and bump detail is evaluated only while pixels resolve it.
 float3 local=make_float3(u,p.y,v);float small=0,fine=0,grit=0;
 float wSmall=weight(fp,2.5f),wFine=weight(fp,11),wGrit=weight(fp,47);
 if(wSmall>0)small=(surfaceNoise(local,n,2.5f)-.5f)*wSmall;
 if(wFine>0)fine=(surfaceNoise(local,n,11)-.5f)*wFine;
 if(wGrit>0)grit=(surfaceNoise(local,n,47)-.5f)*wGrit;
 float onLand=smoothf(beachEdge,beachEdge+8,p.y);
 col=col*(1+small*lerpf(.16f,.48f,onLand)+fine*.26f+grit*.17f);
 if(wSmall>0){
  float e=.035f,h=surfaceNoise(local,n,2.5f);
  float3 gradient=make_float3(surfaceNoise(local+make_float3(e,0,0),n,2.5f)-h,surfaceNoise(local+make_float3(0,e,0),n,2.5f)-h,surfaceNoise(local+make_float3(0,0,e),n,2.5f)-h)/e;
  gradient=gradient-n*dot3(gradient,n);
  n=norm3(n-gradient*(lerpf(.035f,.16f,exposure)*wSmall));
 }

 float wet=shoreWetness(p,a,fp);col=col*(1-wet*0.28f);
 float nl=sat(dot3(n,sun));float3 ambient=mix3(make_float3(.14f,.17f,.19f),make_float3(.22f,.26f,.28f),sat(n.y));
 return col*(ambient+sunRadiance(sun)*(nl*.30f));
}
__device__ float terrainShadow(float3 p,float3 sun,const int* Origin,float fp){
 float visibility=1,t=8;
 for(int i=0;i<6;i++){float3 q=p+sun*t;float gap=q.y-ground(q.x,q.z,Origin,fmaxf(fp,t*.03f));visibility=fminf(visibility,sat((gap+1)*5/t));if(visibility<.01f)break;t=t*2+8;}
 return .38f+.62f*visibility;
}
