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
// Sand deposition follows the existing depth contours in selected coastal sectors.
// It stays inside the island envelope and vanishes smoothly at both depth limits.
__device__ float coastalRelief(float base,float mx,float mz,Island a,float fp){
 if(base<=-26||base>=22)return 0;
 float along=mx*a.c+mz*a.s,cross=-mx*a.s+mz*a.c;
 float sector=smoothf(.40f,.66f,noise2(along/410+a.seed,cross/410+19));
 float bend=(noise2(along/155+a.seed,cross/230)-.5f)*5;
 float bar=expf(-powf((base+9.5f+bend)/3.2f,2));
 // Breaks in the deposited ridge leave channels into the shallow lagoon.
 float channel=smoothf(.30f,.52f,noise2(along/85+27,cross/180+a.seed));
 float spit=smoothf(.64f,.82f,noise2(along/310+71,cross/310+a.seed));
 float deposition=(32*bar*channel+spit*5*expf(-powf((base+2)/5,2)))*sector;
 // Submerged banks approach -1.8 metres; deposition cannot create dry land.
 float capacity=fmaxf(0,-1.8f-base);
 deposition=capacity*(1-expf(-deposition/fmaxf(.01f,capacity)));
 float dunes=0;
 if(base>0&&fp<12){float ridge=.5f+.5f*sinf(along*.075f+noise2(along/65,cross/65+a.seed)*4);
  dunes=3.2f*ridge*ridge*smoothf(0,4,base)*(1-smoothf(10,22,base))*sector*weight(fp,.075f);}
 return deposition*smoothf(-26,-18,base)*(1-smoothf(9,20,base))+dunes;
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
 float coastDetail=coastalRelief(base,mx,mz,a,fp);
 // Inland relief is exactly zero here; avoid three unused noise evaluations.
 if(base<=2)return base+coastDetail;
 float detail=0,w1=weight(fp,1.0f/95),w2=weight(fp,1.0f/31),w3=weight(fp,1.0f/9);
 if(w1>0)detail+=(noise2((mx+warpX)/95+a.seed,(mz+warpZ)/95)-.5f)*40*w1;
 if(w2>0)detail+=(noise2(mx/31+a.seed,mz/31)-.5f)*13*w2;
 if(w3>0)detail+=(noise2(mx/9+a.seed,mz/9)-.5f)*3*w3;
 // Preserve the submerged shelf and beach; break up inland silhouettes and normals.
 return base+detail*smoothf(2,32,base)+coastDetail;

}
// Continuous seeded ocean geography. Integer lattice IDs include the floating
// origin; coordinates never become large floats. Scales divide the 4800 m cell.
__device__ float bedNoise(float x,float z,int scale,const int* Origin,unsigned int salt){
 float u=x/(float)scale,v=z/(float)scale;int ix=(int)floorf(u),iz=(int)floorf(v);
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*(4800u/(unsigned int)scale);
 unsigned int gz=(unsigned int)iz+(unsigned int)Origin[1]*(4800u/(unsigned int)scale);
 float fx=fractf(u),fz=fractf(v);fx=fx*fx*(3-2*fx);fz=fz*fz*(3-2*fz);
 unsigned int seed=(unsigned int)Origin[2]+salt;
 return lerpf(lerpf(hash2((int)gx,(int)gz,seed),hash2((int)(gx+1u),(int)gz,seed),fx),lerpf(hash2((int)gx,(int)(gz+1u),seed),hash2((int)(gx+1u),(int)(gz+1u),seed),fx),fz);
}
__device__ float oceanFloor(float x,float z,const int* Origin,float fp){
 float basin=bedNoise(x,z,1200,Origin,1103u),ridge=1-fabsf(bedNoise(x,z,600,Origin,1104u)*2-1);
 float shelf=smoothf(.32f,.72f,basin);
 float height=-92+65*shelf+20*ridge*ridge*ridge;
 height+=(bedNoise(x,z,120,Origin,1105u)-.5f)*8*weight(fp,1.0f/120);
 height+=(bedNoise(x,z,24,Origin,1106u)-.5f)*1.3f*weight(fp,1.0f/24);
 return fminf(-5,height);
}
__device__ float seabedBase(float x,float z,const int* Origin,float fp){
 float island=islandHeight(x,z,describeIsland((int)floorf(x/CELL),(int)floorf(z/CELL),Origin),fp);
 if(island>=-18)return island;
 // Foundations blend into the continuous floor; empty cells have ocean terrain too.
 return lerpf(oceanFloor(x,z,Origin,fp),island,smoothf(-45,-18,island));
}
// Coral gardens span tens to hundreds of metres. They share a limestone
// framework, while two warped colony scales break up spacing and silhouettes.
// The grid is only a lookup address: it never becomes a visible planting pattern.
__device__ float4 coralLayer(float x,float z,float fp,const int* Origin,int scale,unsigned int salt,float group,float depth){
 int ix=(int)floorf(x/(float)scale),iz=(int)floorf(z/(float)scale);
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*(4800u/(unsigned int)scale);
 unsigned int gz=(unsigned int)iz+(unsigned int)Origin[1]*(4800u/(unsigned int)scale);
 unsigned int seed=(unsigned int)Origin[2]+salt;
 float chance=hash2((int)gx,(int)gz,seed);
 if(chance<.10f)return make_float4(0,0,0,0);
 float size=hash2((int)gx,(int)gz,seed+1u),variant=hash2((int)gx,(int)gz,seed+2u);
 float cx=((float)ix+.5f)*(float)scale+(variant-.5f)*(float)scale*.07f;
 float cz=((float)iz+.5f)*(float)scale+(hash2((int)gx,(int)gz,seed+3u)-.5f)*(float)scale*.07f;
 float radius=(float)scale*(.26f+.20f*size),dx=(x-cx)/radius,dz=(z-cz)/radius;
 float angle=chance*2*PI,ux=dx*cosf(angle)+dz*sinf(angle),uz=-dx*sinf(angle)+dz*cosf(angle);
 float r=sqrtf(ux*ux*(1+variant*.8f)+uz*uz);
 r+=(noise2(ux*3+chance*19,uz*3+chance*13)-.5f)*.22f*smoothf(0,.4f,r);
 float edge=1-smoothf(.72f,.98f,r);
 float cellEdge=fmaxf(fabsf(x/(float)scale-(float)ix-.5f),fabsf(z/(float)scale-(float)iz-.5f));edge*=1-smoothf(.43f,.5f,cellEdge);
 float style=floorf(fractf(group*.35f+variant)*4),palette=fractf(group*.27f+chance);
 if(smoothf(18,42,depth)>chance)style=variant<.7f?1:3;
 if(edge<=0)return make_float4(0,0,style,palette);
 float broad=fmaxf(0,1-r*r),height=0;
 float scaleHeight=(.35f+size*.75f)*((float)scale/12);
 if(style<1){ // Irregular massive / boulder heads, merged into the framework.
  float lobes=.72f+.28f*noise2(ux*4+chance*31,uz*4+chance*17);
  height=sqrtf(broad)*edge*lobes*scaleHeight;
 }else if(style<2){ // Broad, uneven table and foliose tiers.
  float skew=r+(noise2(ux*5+variant*13,uz*5)-.5f)*.13f;
  height=(.35f+.28f*(1-smoothf(.48f,.55f,skew))+.24f*(1-smoothf(.22f,.28f,skew)))*edge*scaleHeight;
 }else if(style<3){ // Seeded thickets: many unequal rounded branches.
  float fingers=0;int count=14+(int)(chance*12);
  for(int k=0;k<count;k++){
   float phase=angle+(float)k*2.399963f;
   float reach=.08f+.65f*hash2((int)gx+k,(int)gz,seed+16u);
   float fx=ux-cosf(phase)*reach,fz=uz-sinf(phase)*reach;
   float radius2=.004f+.009f*hash2((int)gx+k,(int)gz,seed+17u);
   float cap=sqrtf(fmaxf(0,1-(fx*fx+fz*fz)/radius2));
   fingers=fmaxf(fingers,cap*(.35f+hash2((int)gx+k,(int)gz,seed+18u)*.8f));
  }
  height=(.16f*broad+fingers*weight(fp,2))*edge*scaleHeight;
 }else{ // Encrusting / rubble growth with low folded lobes.
  float fold=.5f+.5f*sinf(r*19+variant*5+noise2(ux*3,uz*3)*3);
  height=(.18f+.30f*fold*weight(fp,1))*broad*edge*scaleHeight;
 }
 return make_float4(height,edge,style,palette);
}
// Payload: framework + colony relief, living cover, dominant growth form, colour.
__device__ float4 reefColony(float x,float z,float base,float fp,const int* Origin){
 float habitat=smoothf(3,8,-base)*(1-smoothf(30,55,-base));
 if(habitat<.001f)return make_float4(0,0,0,0);
 int ix=(int)floorf(x/120),iz=(int)floorf(z/120);
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*40u,gz=(unsigned int)iz+(unsigned int)Origin[1]*40u;
 unsigned int seed=(unsigned int)Origin[2]+1360u;
 float group=hash2((int)gx,(int)gz,seed),size=hash2((int)gx,(int)gz,seed+1u);
 if(group<.34f)return make_float4(0,0,0,0);
 float lx=x-(float)ix*120,lz=z-(float)iz*120;
 float cx=60+(hash2((int)gx,(int)gz,seed+2u)-.5f)*9,cz=60+(hash2((int)gx,(int)gz,seed+3u)-.5f)*9;
 float radius=24+size*28,dx=(lx-cx)/radius,dz=(lz-cz)/(radius*(.7f+.25f*group));
 float warp=(bedNoise(x,z,24,Origin,1364u)-.5f)*.35f;
 float r=sqrtf(dx*dx+dz*dz)+warp;
 // Regional seed noise leaves entire reef-free stretches, not tiny random holes.
 float province=smoothf(.34f,.56f,bedNoise(x,z,600,Origin,1370u));
 float mask=(1-smoothf(.60f,1,r))*habitat*province;
 mask*=smoothf(0,7,lx)*smoothf(0,7,lz)*(1-smoothf(113,120,lx))*(1-smoothf(113,120,lz));
 if(mask<.001f)return make_float4(0,0,0,0);
 // One large living reef outcrop, with uneven shoulders and secondary buttresses.
 float dome=powf(fmaxf(0,1-r*r),.8f);
 float foundation=(3+size*12)*dome*mask;
 foundation*=.80f+.30f*bedNoise(x,z,12,Origin,1365u);
 float wx=x+(bedNoise(x,z,12,Origin,1212u)-.5f)*5;
 float wz=z+(bedNoise(x,z,12,Origin,1213u)-.5f)*5;
 // Densely overlapping metre-scale colonies and sub-colonies carpet the mound.
 float4 large=coralLayer(wx,wz,fp,Origin,6,1230u,group,-base);
 float4 small=coralLayer(wx+.31f,wz-.71f,fp,Origin,1,1270u,group,-base);
 // Shallow water supports branching thickets; deeper zones favour low plates.
 float deep=smoothf(18,42,-base);
 float choose=large.y<.20f&&small.y>.3f?1:0;
 float colonies=(large.x*lerpf(4.0f,1.4f,deep)+small.x*lerpf(1.4f,.6f,deep))*mask*weight(fp,.3f);
 float height=fminf(foundation,fmaxf(0,-1.8f-base));
 float cover=smoothf(.08f,.35f,mask)*(.22f+.78f*smoothf(.03f,.45f,fmaxf(large.y,small.y)));
 float unresolved=smoothf(.4f,3,fp);
 return make_float4(height,lerpf(cover,mask*.85f,unresolved),lerpf(large.z,small.z,choose),lerpf(large.w,small.w,choose));
}
__device__ float ground(float x,float z,const int* Origin,float fp){
 float base=seabedBase(x,z,Origin,fp);if(base>=-2.5f||base<=-65)return base;
 return base+reefColony(x,z,base,fp,Origin).x;
}
__device__ float3 groundNormal(float3 p,const int* Origin,float fp){
 float e=fmaxf(.08f,fp*.7f);
 if(p.y<0)return norm3(make_float3(ground(p.x-e,p.z,Origin,fp)-ground(p.x+e,p.z,Origin,fp),2*e,ground(p.x,p.z-e,Origin,fp)-ground(p.x,p.z+e,Origin,fp)));
 e=fmaxf(.4f,e);int cx=(int)floorf(p.x/CELL),cz=(int)floorf(p.z/CELL);Island a=describeIsland(cx,cz,Origin);
 return norm3(make_float3(islandHeight(p.x-e,p.z,a,fp)-islandHeight(p.x+e,p.z,a,fp),2*e,islandHeight(p.x,p.z-e,a,fp)-islandHeight(p.x,p.z+e,a,fp)));
}
// Underwater visibility has a finite optical range, while the floor itself is
// generated at every world coordinate. No island AABB can cull the ocean floor.
__device__ float traceSeabed(float3 ro,float3 rd,const int* Origin,float limit,float cone){
 float t=.04f,previous=t,stop=fminf(limit,150);
 float horizontal=sqrtf(rd.x*rd.x+rd.z*rd.z);
 int budget=(int)fminf(4096,ceilf(stop/.025f)+2);
 for(int i=0;i<budget;i++){
  if(t>stop)return -1;float3 p=ro+rd*t;float fp=fmaxf(.03f,t*cone);
  float gap=p.y-ground(p.x,p.z,Origin,fp);
  if(gap<=0){float lo=previous,hi=t;for(int j=0;j<8;j++){float mid=(lo+hi)*.5f;float3 q=ro+rd*mid;if(q.y>ground(q.x,q.z,Origin,fmaxf(.03f,mid*cone)))lo=mid;else hi=mid;}return (lo+hi)*.5f;}
  if(p.y>8&&rd.y>=0)return -1;
  previous=t;float slope=gap>8?3:8;t+=fmaxf(.01f,(gap>8?gap-6:gap)/(fabsf(rd.y)+slope*horizontal+.001f));
 }
 return -1;
}
// DDA over cells, then bounded height-field stepping inside each island box.
// Fixed budgets bound GPU work. The draw distance is finite; the seeded world is not.
__device__ float traceLand(float3 ro,float3 rd,const int* Origin,float limit,float cone){
 float t=0.1f,raySlope=fabsf(rd.y)+3.8f*sqrtf(rd.x*rd.x+rd.z*rd.z);if(ro.y>500){if(rd.y>=-0.0001f)return -1;t=fmaxf(t,(500-ro.y)/rd.y);}
 // A segment crosses at most ceil(|dx|/CELL)+ceil(|dz|/CELL) boundaries.
 // Include the starting cell and rounding slack; keep the original 32-cell cap.
 // A runtime bound avoids unrolling the full island grammar for 32 cells.
 int cellBudget=(int)fminf(32,ceilf(limit*(fabsf(rd.x)+fabsf(rd.z))/CELL)+3);
 for(int cell=0;cell<cellBudget;cell++){
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
   // The per-ray span gives a tighter runtime trip count. One extra sample keeps
   // inclusive endpoints and float rounding safe; the minimum advance remains 1 m.
   // Keep the original 4352 hard cap, without asking drivers to optimize a fixed
   // multi-thousand-iteration loop containing the complete terrain grammar.
   int stepBudget=(int)fminf(4352.0f,fmaxf(0.0f,ceilf(stop-s)+2.0f));
   for(int j=0;j<stepBudget;j++){
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
