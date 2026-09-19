// Stateless six-metre vegetation cells. Canopies remain inside their own cells,
// so a ray visits only the cells it crosses; no world-sized instance list exists.
struct Shrub {float3 root;float size;float seed;};
__device__ Shrub describeShrub(int ix,int iz,const int* Origin){
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*800u;
 unsigned int gz=(unsigned int)iz+(unsigned int)Origin[1]*800u;
 unsigned int seed=(unsigned int)Origin[2]+971u;
 Shrub s;s.seed=hash2((int)gx,(int)gz,seed);s.size=0;
 int cx=(int)floorf((float)ix/800),cz=(int)floorf((float)iz/800);
 s.root=make_float3(((float)(ix-cx*800)+.5f)*6,0,((float)(iz-cz*800)+.5f)*6);
 if(s.seed<.42f)return s;
 s.root.x+=(hash2((int)gx,(int)gz,seed+1)-.5f)*2.4f;
 s.root.z+=(hash2((int)gx,(int)gz,seed+2)-.5f)*2.4f;
 int habitat[4]={Origin[0]+cx,Origin[1]+cz,Origin[2],0};
 Island a=describeIsland(0,0,habitat);
 s.root.y=islandHeight(s.root.x,s.root.z,a,.2f);
 float3 local=s.root;s.root.x+=(float)cx*CELL;s.root.z+=(float)cz*CELL;
 if(s.root.y<4.5f||s.root.y>155)return s;
 float dx=islandHeight(local.x-.4f,local.z,a,.5f)-islandHeight(local.x+.4f,local.z,a,.5f);
 float dz=islandHeight(local.x,local.z-.4f,a,.5f)-islandHeight(local.x,local.z+.4f,a,.5f);
 float ny=.8f/sqrtf(.64f+dx*dx+dz*dz);if(ny<.86f)return s;
 float patch=noise2((local.x-a.x)/38+a.seed,(local.z-a.z)/38);
 if(patch<.38f||s.seed<lerpf(.72f,.42f,smoothf(5,18,s.root.y)))return s;
 s.size=.75f+hash2((int)gx,(int)gz,seed+3)*.65f;
 return s;
}
// A bounded 64 KiB patch replaces habitat evaluation in every viewing ray.
__global__ void cacheShrubs(const float* C,const int* Origin,float* Shrubs){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),z=(int)(blockIdx.y*blockDim.y+threadIdx.y);
 if(x>=64||z>=64)return;
 int bx=(int)floorf(C[0]/6)-32,bz=(int)floorf(C[2]/6)-32;
 if(x==0&&z==0){Shrubs[0]=(float)bx;Shrubs[1]=(float)bz;Shrubs[2]=ground(C[0],C[2],Origin,1);Shrubs[3]=0;}
 Shrub s=describeShrub(bx+x,bz+z,Origin);int b=4+(z*64+x)*4;
 Shrubs[b]=s.root.x;Shrubs[b+1]=s.root.y;Shrubs[b+2]=s.root.z;Shrubs[b+3]=s.size;
}
__device__ Shrub cachedShrub(int ix,int iz,const int* Origin,const float* Shrubs){
 Shrub s;s.root=make_float3(0,0,0);s.size=0;s.seed=0;
 int x=ix-(int)Shrubs[0],z=iz-(int)Shrubs[1];if(x<0||z<0||x>=64||z>=64)return s;
 int b=4+(z*64+x)*4;s.root=make_float3(Shrubs[b],Shrubs[b+1],Shrubs[b+2]);s.size=Shrubs[b+3];
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*800u,gz=(unsigned int)iz+(unsigned int)Origin[1]*800u;
 s.seed=hash2((int)gx,(int)gz,(unsigned int)Origin[2]+971u);return s;
}
// Analytic ellipsoid intersection, with a true curved surface normal.
__device__ float4 shrubEllipsoid(float3 ro,float3 rd,float3 centre,float3 radii){
 float3 q=make_float3((ro.x-centre.x)/radii.x,(ro.y-centre.y)/radii.y,(ro.z-centre.z)/radii.z);
 float3 d=make_float3(rd.x/radii.x,rd.y/radii.y,rd.z/radii.z);
 float a=dot3(d,d),b=dot3(q,d),c=dot3(q,q)-1,disc=b*b-a*c;
 if(disc<0)return make_float4(-1,0,1,0);
 float t=(-b-sqrtf(disc))/a;if(t<.02f)t=(-b+sqrtf(disc))/a;
 float3 p=ro+rd*t-centre;
 float3 n=norm3(make_float3(p.x/(radii.x*radii.x),p.y/(radii.y*radii.y),p.z/(radii.z*radii.z)));
 return make_float4(t,n.x,n.y,n.z);
}
__device__ float3 shrubSprig(Shrub s,int k,float time,float wind){
 float phase=s.seed*31+(float)k*2.39996f;
 float radius=(.28f+.075f*(float)(k%4))*s.size;
 float sway=sinf(time*1.3f+s.seed*53+(float)k*.7f)*.055f*fminf(wind,2.5f);
 return s.root+make_float3(cosf(phase)*radius+sway,s.size*(.32f+.14f*(float)(k%5)),sinf(phase)*radius+sway*.35f);
}
__device__ float4 shrubOriented(float3 ro,float3 rd,float3 centre,float3 radii,float3 axis){
 float3 yy=norm3(axis),xx=norm3(cross3(yy,make_float3(0,0,1))),zz=cross3(xx,yy),q=ro-centre;
 float4 hit=shrubEllipsoid(make_float3(dot3(q,xx),dot3(q,yy),dot3(q,zz)),make_float3(dot3(rd,xx),dot3(rd,yy),dot3(rd,zz)),make_float3(0,0,0),radii);
 float3 n=xx*hit.y+yy*hit.z+zz*hit.w;
 return make_float4(hit.x,n.x,n.y,n.z);
}
// Hit=(distance,normal); leaf/wood identity is recomputed in shading from height.
// Leaf holes are geometric gaps, not a transparent billboard or image texture.
__device__ float4 hitShrub(float3 ro,float3 rd,Shrub s,float limit,float time,float wind,float cone){
 ro=ro-s.root;s.root=make_float3(0,0,0);
 float4 best=make_float4(limit,0,1,0);
 float3 trunk=s.root+make_float3(0,s.size*.18f,0);
 float4 stem=shrubEllipsoid(ro,rd,trunk,make_float3(.045f,s.size*.24f,.045f));
 if(stem.x>.02f&&stem.x<best.x)best=stem;
 float distance=sqrtf(dot3(s.root-ro,s.root-ro));
 float detail=1-smoothf(.035f,.13f,distance*cone);
 // Coarse canopies shrink out smoothly into the terrain coverage at 140..180 m.
 float fade=1-smoothf(140,180,distance);
 int sprigs=10+(int)(s.seed*4);
 for(int k=0;k<sprigs;k++){
  float3 centre=shrubSprig(s,k,time,wind);
  float3 branchAxis=centre-trunk;
  float4 branch=shrubOriented(ro,rd,(centre+trunk)*.5f,make_float3(.025f,sqrtf(dot3(branchAxis,branchAxis))*.55f,.025f),branchAxis);
  if(branch.x>.02f&&branch.x<best.x)best=branch;
  float3 radii=make_float3(.38f,.42f,.40f)*(s.size*fade);
  if(fade<=.001f)continue;
  float4 cluster=shrubEllipsoid(ro,rd,centre,radii);
  if(cluster.x<=.02f||cluster.x>=best.x)continue;
  if(detail<.05f){best=cluster;continue;}
  // Fine curved leaves per sprig, with runtime counts to avoid driver unrolling.
  int leaves=14+(int)(s.seed*5);
  for(int j=0;j<leaves;j++){
   float a=s.seed*81+(float)(j+k*6)*2.39996f;
   float3 offset=make_float3(cosf(a)*.18f,((float)j/(float)(leaves-1)-.5f)*.40f,sinf(a)*.18f)*s.size;
   float size=lerpf(.27f,.055f,detail)*s.size*fade;
   float3 leafRadii=make_float3(size,size*.30f,size*1.4f);
   float3 axis=make_float3(cosf(a)*.65f,.6f,sinf(a)*.65f);
   float4 leaf=shrubOriented(ro,rd,centre+offset,leafRadii,axis);
   if(leaf.x>.02f&&leaf.x<best.x)best=leaf;
  }
 }
 return best;
}
__device__ float4 traceShrubs(float3 ro,float3 rd,const int* Origin,const float* Shrubs,float limit,float time,float wind,float cone){
 float stop=fminf(limit,180),start=.02f;
 // Aerial/distant views use terrain coverage, avoiding a second full-world march.
 if(stop<=.02f||ro.y>165)return make_float4(limit,0,1,0);
 if(limit>220&&ro.y-Shrubs[2]>5)return make_float4(limit,0,1,0);
 if(limit<220)start=fmaxf(.02f,limit-8/fmaxf(.08f,fabsf(rd.y)));
 float4 best=make_float4(limit,0,1,0);
 int budget=(int)fminf(64,ceilf(stop*(fabsf(rd.x)+fabsf(rd.z))/6)+3);
 for(int cell=0;cell<budget;cell++){
  if(start>=stop||start>=best.x)break;
  float3 p=ro+rd*start;int ix=(int)floorf(p.x/6),iz=(int)floorf(p.z/6);
  float tx=fabsf(rd.x)>1e-6f?(((float)ix+(rd.x>=0?1:0))*6-p.x)/rd.x:1e9f;
  float tz=fabsf(rd.z)>1e-6f?(((float)iz+(rd.z>=0?1:0))*6-p.z)/rd.z:1e9f;
  float end=fminf(stop,start+fmaxf(0,fminf(tx,tz)));
  Shrub s=cachedShrub(ix,iz,Origin,Shrubs);
  if(s.size>0){float2 bounds=boxRay(ro,rd,s.root+make_float3(-1.65f,-.1f,-1.65f),s.root+make_float3(1.65f,2.4f,1.65f));
   if(bounds.y>=start&&bounds.x<=end&&bounds.x<best.x){float4 hit=hitShrub(ro,rd,s,best.x,time,wind,cone);if(hit.x<best.x)best=hit;}}
  start=end+.001f;
 }
 return best;
}
__device__ float shrubContact(float3 p,const int* Origin,const float* Shrubs,float fp){
 if(p.y<4||p.y>157||fp>1)return 1;
 Shrub s=cachedShrub((int)floorf(p.x/6),(int)floorf(p.z/6),Origin,Shrubs);
 if(s.size==0)return 1;
 float dx=p.x-s.root.x,dz=p.z-s.root.z;
 return 1-.38f*expf(-(dx*dx+dz*dz)/(s.size*s.size*.55f))*weight(fp,1);
}
__device__ float3 shrubColor(float3 p,float3 n,float3 rd,float3 sun,const int* Origin,const float* Shrubs,float fp){
 Shrub s=cachedShrub((int)floorf(p.x/6),(int)floorf(p.z/6),Origin,Shrubs);
 float height=(p.y-s.root.y)/fmaxf(.1f,s.size);
 float wood=1-smoothf(.13f,.28f,height);
 float vein=.5f+(noise2((p.x-s.root.x)*43,(p.z-s.root.z)*43)-.5f)*weight(fp,43);
 float3 leaf=mix3(make_float3(.045f,.095f,.026f),make_float3(.16f,.21f,.065f),s.seed)*(.88f+vein*.24f);
 float3 albedo=mix3(leaf,make_float3(.13f,.085f,.042f),wood);
 float diffuse=sat(dot3(n,sun)),back=powf(sat(dot3(rd,sun)),3)*(1-wood)*.34f;
 float occlusion=lerpf(.52f,1,smoothf(.25f,1.3f,height));
 return albedo*(make_float3(.19f,.24f,.27f)*occlusion+sunRadiance(sun)*(diffuse*.29f+back));
}
