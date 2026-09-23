// Conservative interval bounds for the unchanged procedural terrain, including
// every filtered detail level. Nine world cells, 512 squared leaves, min/max mips.
#define TERRAIN_BASE 5114536
#define TERRAIN_TEXELS 349525
#define TERRAIN_FLOATS 6291454
__device__ float2 terrainMul(float2 a,float2 b){
 float aa=a.x*b.x,ab=a.x*b.y,ba=a.y*b.x,bb=a.y*b.y;
 return make_float2(fminf(fminf(aa,ab),fminf(ba,bb)),fmaxf(fmaxf(aa,ab),fmaxf(ba,bb)));
}
__device__ float2 terrainNoiseBound(float x,float z,float dx,float dz){
 // Value noise is bilinear in monotonic cubic coordinates inside each lattice
 // square. Rectangle extrema therefore occur at corners or lattice crossings.
 if(dx>=1||dz>=1)return make_float2(0,1);
 float left=x-dx,right=x+dx,bottom=z-dz,top=z+dz,low=1,high=0;
 int nx=2+(int)fmaxf(0,floorf(right)-ceilf(left)+1),nz=2+(int)fmaxf(0,floorf(top)-ceilf(bottom)+1);
 for(int j=0;j<nz;j++)for(int i=0;i<nx;i++){
  float xx=i==0?left:(i==1?right:ceilf(left)+(float)(i-2));
  float zz=j==0?bottom:(j==1?top:ceilf(bottom)+(float)(j-2));
  float n=noise2(xx,zz);low=fminf(low,n);high=fmaxf(high,n);
 }
 return make_float2(sat(low-.00002f),sat(high+.00002f));
}
__device__ float2 terrainBounds(float x,float z,float half,Island a){
 if(a.peak==0)return make_float2(-45.01f,-44.99f);
 float mx=x-a.x,mz=z-a.z;
 float u=(mx*a.c+mz*a.s)*a.aspect/a.radius,v=(-mx*a.s+mz*a.c)/a.radius;
 float dv=half*(fabsf(a.c)+fabsf(a.s))/a.radius,du=dv*a.aspect;
 float ulo=fmaxf(0,fabsf(u)-du),vlo=fmaxf(0,fabsf(v)-dv);
 float rlo=sqrtf(ulo*ulo+vlo*vlo),rhi=sqrtf((fabsf(u)+du)*(fabsf(u)+du)+(fabsf(v)+dv)*(fabsf(v)+dv));
 if(rlo>=1.00001f)return make_float2(-45.01f,-44.99f);
 float2 broad=terrainNoiseBound(u*3.1f+a.seed,v*3.1f+a.seed,du*3.1f,dv*3.1f);
 float2 coast=terrainNoiseBound(mx/180+a.seed,mz/180,half/180,half/180);
 float2 perturb=make_float2((broad.x-.5f)*.55f+(coast.x-.5f)*90/a.radius,(broad.y-.5f)*.55f+(coast.y-.5f)*90/a.radius);
 float2 taper=make_float2(smoothf(1,.6f,rhi),smoothf(1,.6f,rlo)),bump=terrainMul(perturb,taper);
 float2 shape=make_float2(sat(1-rhi+bump.x),sat(1-rlo+bump.y));
 float2 wx=terrainNoiseBound(mx/650+a.seed,mz/650,half/650,half/650),wz=terrainNoiseBound(mx/650+31,mz/650+a.seed,half/650,half/650);
 wx=make_float2((wx.x-.5f)*150,(wx.y-.5f)*150);wz=make_float2((wz.x-.5f)*150,(wz.y-.5f)*150);
 float xx=mx+(wx.x+wx.y)*.5f,zz=mz+(wz.x+wz.y)*.5f,ex=half+(wx.y-wx.x)*.5f,ez=half+(wz.y-wz.x)*.5f;
 float2 nr=terrainNoiseBound(xx/310+a.seed,zz/310,ex/310,ez/310);
 float rmin=1-fmaxf(fabsf(nr.x*2-1),fabsf(nr.y*2-1));
 float rmax=nr.x<=.5f&&nr.y>=.5f?1:1-fminf(fabsf(nr.x*2-1),fabsf(nr.y*2-1));
 float low=-45+powf(shape.x,1.7f)*(a.peak*(.48f+.52f*rmin)+45);
 float high=-45+powf(shape.y,1.7f)*(a.peak*(.48f+.52f*rmax)+45);
 float lower=low,upper=high;
 // Deposition is nonnegative and cannot exceed -1.8 m. Dunes add <=3.2 m.
 if(high>=-26&&low<=22){upper=fmaxf(upper,-1.8f);if(high>0)upper+=3.2f;}
 if(high>2){
  float2 d1=terrainNoiseBound(xx/95+a.seed,zz/95,ex/95,ez/95),d2=terrainNoiseBound(mx/31+a.seed,mz/31,half/31,half/31),d3=terrainNoiseBound(mx/9+a.seed,mz/9,half/9,half/9);
  float dl=fminf(0,(d1.x-.5f)*40)+fminf(0,(d2.x-.5f)*13)+fminf(0,(d3.x-.5f)*3);
  float dh=fmaxf(0,(d1.y-.5f)*40)+fmaxf(0,(d2.y-.5f)*13)+fmaxf(0,(d3.y-.5f)*3);
  float inland=smoothf(2,32,high);lower+=dl*inland;upper+=dh*inland;
 }
 if(rhi>=1)lower=fminf(lower,-45);
 return make_float2(lower-.08f,upper+.08f);
}
__device__ int terrainMipOffset(int level){int n=512>>level;return (262144-n*n)*4/3;}
__global__ void cacheTerrain(const int* Origin,float* Terrain){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),z=(int)(blockIdx.y*blockDim.y+threadIdx.y),tile=(int)blockIdx.z;
 if(x>=512||z>=512||tile>=9)return;
 int cx=tile%3-1,cz=tile/3-1;Island a=describeIsland(cx,cz,Origin);
 float spacing=CELL/512;float2 bound=terrainBounds((float)cx*CELL+((float)x+.5f)*spacing,(float)cz*CELL+((float)z+.5f)*spacing,spacing*.5f,a);
 int b=TERRAIN_BASE+4+(tile*TERRAIN_TEXELS+z*512+x)*2;Terrain[b]=bound.x;Terrain[b+1]=bound.y;
 if(x==0&&z==0&&tile==0){Terrain[TERRAIN_BASE+0]=1;Terrain[TERRAIN_BASE+1]=0;Terrain[TERRAIN_BASE+2]=0;Terrain[TERRAIN_BASE+3]=0;}
}
__global__ void mipTerrain(float* Terrain,int level){
 int n=512>>level,x=(int)(blockIdx.x*blockDim.x+threadIdx.x),z=(int)(blockIdx.y*blockDim.y+threadIdx.y),tile=(int)blockIdx.z;
 if(x>=n||z>=n||tile>=9)return;
 int b=TERRAIN_BASE+4+(tile*TERRAIN_TEXELS+terrainMipOffset(level)+z*n+x)*2;
 int a=TERRAIN_BASE+4+(tile*TERRAIN_TEXELS+terrainMipOffset(level-1)+(z*2)*(n*2)+x*2)*2;
 Terrain[b]=fminf(fminf(Terrain[a],Terrain[a+2]),fminf(Terrain[a+n*4],Terrain[a+n*4+2]));
 Terrain[b+1]=fmaxf(fmaxf(Terrain[a+1],Terrain[a+3]),fmaxf(Terrain[a+n*4+1],Terrain[a+n*4+3]));
}
__device__ float traceLandCached(float3 ro,float3 rd,const int* Origin,float limit,float cone,const float* Terrain){
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
    if(s>stop)break;float3 q=ro+rd*s;float fp=fmaxf(0.2f,s*cone);
    // Only skip intervals proved above the maximum possible terrain, for ALL LODs.
    float next=s;
    if(Terrain[TERRAIN_BASE+0]>.5f&&cx>=-1&&cx<=1&&cz>=-1&&cz<=1){
     int tile=(cz+1)*3+cx+1;
     for(int level=0;level<=8;level++){
      int n=512>>level;float size=CELL/(float)n;
      int ix=(int)clampf(floorf((q.x-(float)cx*CELL)/size),0,(float)n-1),iz=(int)clampf(floorf((q.z-(float)cz*CELL)/size),0,(float)n-1);
      int b=TERRAIN_BASE+4+(tile*TERRAIN_TEXELS+terrainMipOffset(level)+iz*n+ix)*2;
      float ceiling=Terrain[b+1]+fmaxf(.05f,fmaxf(.2f,stop*cone)*.15f);
      if(q.y<=ceiling)break;
      float ex=(float)cx*CELL+((float)ix+(rd.x>=0?1:0))*size,ez=(float)cz*CELL+((float)iz+(rd.z>=0?1:0))*size;
      float dx=fabsf(rd.x)>.000001f?(ex-q.x)/rd.x:1000000,dz=fabsf(rd.z)>.000001f?(ez-q.z)/rd.z:1000000;
      float exit=fminf(stop,s+fmaxf(0,fminf(dx,dz)));
      if(rd.y<0)exit=fminf(exit,s+(q.y-ceiling)/(-rd.y));
      if(exit<=next+.01f)break;next=exit;
     }
    }
    if(next>s){previous=next;s=next+.001f;continue;}
    float gap=q.y-islandHeight(q.x,q.z,a,fp);
    if(gap<fmaxf(0.05f,fp*0.15f)){float lo=previous,hi=s;for(int k=0;k<7;k++){float mid=(lo+hi)*0.5f;float3 m=ro+rd*mid;if(m.y>islandHeight(m.x,m.z,a,fmaxf(0.2f,mid*cone)))lo=mid;else hi=mid;}return (lo+hi)*0.5f;}
    previous=s;s+=fmaxf(1.0f,gap/fmaxf(raySlope,.001f));
   }
  }
  t=end+0.04f;
 }
 return -1;
}
