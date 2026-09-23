#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/weather.cu"
#include "../kernels/terrain.cu"
#include "../kernels/shrubs.cu"
#include "../kernels/ocean.cu"
#include "../kernels/render.cu"
int main(){
 int styles[4]={},palettes[4]={},o[4]={0,0,884,0};float best=-1;float3 place={0,0,0};
 for(int z=0;z<1200;z++)for(int x=0;x<1200;x++){
  float px=x*4.f+1,pz=z*4.f+1,base=seabedBase(px,pz,o,.1f);auto reef=reefColony(px,pz,base,.1f,o);
  if(reef.y>.3f){styles[int(reef.z)]++;palettes[int(reef.w*4)]++;float score=reef.x*smoothf(14,18,-base)*(1-smoothf(24,30,-base));if(score>best&&base+reef.x< -6){float dx=seabedBase(px-1,pz,o,.1f)-seabedBase(px+1,pz,o,.1f),dz=seabedBase(px,pz-1,o,.1f)-seabedBase(px,pz+1,o,.1f);if(dx*dx+dz*dz<.02f){best=score;place={px,base+reef.x,pz};}}}
 }
 std::cout<<"Reef preview: "<<place.x<<" "<<place.y+3<<" "<<place.z-5<<" 0 -0.35; bed="<<place.y<<"\n";
 for(int i=0;i<4;i++){std::cout<<"Family "<<i<<": "<<styles[i]<<"; palette "<<palettes[i]<<"\n";if(styles[i]<10||palettes[i]<10)return 1;}
 float minBed=1000,maxBed=-1000;int changes=0;
 for(int remote:{0,100000000,-100000000})for(int i=0;i<300;i++){
  int a[4]={remote,-remote,884,0},b[4]={remote+1,-remote-1,884,0},other[4]={remote,-remote,12345,0};
  float x=hash2(i,1,141)*9600-2400,z=hash2(i,2,141)*9600-2400;
  float h=ground(x,z,a,.2f),rebased=ground(x-CELL,z+CELL,b,.2f);
  if(!std::isfinite(h)||fabsf(h-rebased)>.03f){std::cerr<<"Rebase "<<h<<" "<<rebased<<"\n";return 2;}
  if(fabsf(h-ground(x,z,other,.2f))>1)changes++;
  auto color=seabedAlbedo(make_float3(x,h,z),.2f,a),shift=seabedAlbedo(make_float3(x-CELL,h,z+CELL),.2f,b);
  if(!std::isfinite(color.x)||fabsf(color.x-shift.x)>.025f||fabsf(color.y-shift.y)>.025f)return 3;
 }
 for(int seed:{0,42,884,12345}){int origin[4]={0,0,seed,0};
  for(int i=0;i<600;i++){float z=i*17.25f;float left=ground(CELL-.001f,z,origin,.2f),right=ground(CELL+.001f,z,origin,.2f);
   if(fabsf(left-right)>.03f){std::cerr<<"Boundary seam seed="<<seed<<" z="<<z<<" left="<<left<<" right="<<right<<"\n";return 4;}minBed=fminf(minBed,left);maxBed=fmaxf(maxBed,left);}
 }
 if(maxBed-minBed<15||changes<600)return 5;
 // Depth response is tested at identical world sites, separately from bathymetry.
 int bare=0,rich=0;double shallow=0,deep=0;
 for(int z=0;z<100;z++)for(int x=0;x<100;x++){
  float px=x*24.f+3,pz=z*24.f+7;
  auto a=reefColony(px,pz,-12,.06f,o),b=reefColony(px,pz,-48,.06f,o);
  shallow+=a.y;deep+=b.y;if(a.y==0)bare++;if(a.y>.65f)rich++;
  if(reefColony(px,pz,-2,.06f,o).x!=0||reefColony(px,pz,-60,.06f,o).x!=0)return 8;
 }
 if(bare<5000||rich<50||deep>=shallow*.35)return 9;
 std::cout<<"Habitat: "<<bare<<"/10000 bare sites, "<<rich<<" dense sites; deep/shallow coverage "<<deep/shallow<<"\n";
 // Cache samples stay on the same world lattice when its window moves.
 std::vector<float> cache(SHRUB_FLOATS);float cam[16]={4377,-7,2784};
 blockDim={1,1,1};threadIdx={0,0,0};blockIdx={0,0,0};cacheReef(cam,o,cache.data());
 blockIdx={100,100,0};cacheReef(cam,o,cache.data());
 int cb=REEF_CACHE+4+(100*1024+100)*4;float cached[4];for(int k=0;k<4;k++)cached[k]=cache[cb+k];
 cam[0]+=12;blockIdx={0,0,0};cacheReef(cam,o,cache.data());blockIdx={68,100,0};cacheReef(cam,o,cache.data());
 int moved=REEF_CACHE+4+(100*1024+68)*4;for(int k=0;k<4;k++)if(fabsf(cached[k]-cache[moved+k])>1e-5f)return 10;
 // Solid plates have downward-facing undersides and open space below them.
 auto underside=coralEllipsoid(make_float3(.6f,.20f,.15f),make_float3(0,1,0),make_float3(0,.43f,0),make_float3(.75f,.055f,.68f),make_float4(10,0,0,0));
 if(underside.x>=10||underside.z>-.4f)return 11;
 auto gap=coralEllipsoid(make_float3(.65f,.2f,-2),make_float3(0,0,1),make_float3(0,.43f,0),make_float3(.75f,.055f,.68f),make_float4(10,0,0,0));
 if(gap.x!=10)return 12;
 auto capsule=coralBranch(make_float3(0,.5f,-2),make_float3(0,0,1),make_float3(0,0,0),make_float3(0,1,0),.1f,make_float4(10,0,0,0));
 if(fabsf(capsule.x-1.9f)>.001f||capsule.w>-.99f)return 13;
 std::fill(cache.begin()+CORAL_CACHE,cache.end(),0);
 auto empty=traceCorals(make_float3(cam[0],-5,cam[2]),norm3(make_float3(.3f,.1f,1)),cache.data(),32,.001f);
 if(empty.x!=32)return 14;
 std::cout<<"3D coral: plate underside, inter-tier gap, capsule intersection and empty traversal passed\n";
 // Actual silhouette coverage survives geometry reduction, and seeds alter shape.
 int counts[5]={};int different=0;float lods[5]={.002f,.02f,.04f,.08f,.2f};
 for(int level=0;level<5;level++)for(int y=0;y<18;y++)for(int x=0;x<28;x++){
  float3 ro=make_float3((x-13.5f)*.09f,y*.07f,-3),rd=make_float3(0,0,1);
  auto a=coralGeometry(ro,rd,0,.173f,10,lods[level]);
  auto b=coralGeometry(ro,rd,0,.397f,10,lods[level]);
  if(a.x<10)counts[level]++;if((a.x<10)!=(b.x<10))different++;
  if(!std::isfinite(a.x))return 15;
 }
 for(int level=0;level<5;level++)if(counts[level]<30||counts[level]<counts[0]*.25f)return 16;
 if(different<30)return 17;
 std::cout<<"Family LOD silhouette samples: "<<counts[0]<<", "<<counts[1]<<", "<<counts[2]<<", "<<counts[3]<<", "<<counts[4]<<"; seeded differences "<<different<<"\n";
 int hits=0;float worst=0;
 for(int i=0;i<80;i++){
  float3 ro=make_float3(place.x+(i%10)*.7f,place.y+3,place.z-6+(i/10)*.4f),rd=norm3(make_float3((i%7-3)*.15f,-.4f,1));
  float expected=-1;for(float t=.04f;t<50;t+=.015f){float3 p=ro+rd*t;if(p.y<ground(p.x,p.z,o,.03f)){expected=t;break;}}
  float actual=traceSeabed(ro,rd,o,50,0);if((actual<0)!=(expected<0))return 6;
  if(actual>0){hits++;if(fabsf(actual-expected)>.3f)std::cerr<<"ray "<<i<<" expected "<<expected<<" actual "<<actual<<"\n";worst=fmaxf(worst,fabsf(actual-expected));}
 }
 if(hits<50||worst>.3f){std::cerr<<"Underwater ray error "<<worst<<"\n";return 7;}
 std::cout<<"PASS: continuous floor across 2400 boundary samples; depth range "<<minBed<<".."<<maxBed<<"; remote seed/rebase stability; "<<hits<<" rays vs dense reference, error "<<worst<<" m\n";
}
