#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "../kernels/terrain-cache.cu"
int main(){
 int samples=0;
 for(int seed:{0,42,884,12345}){int origin[4]={100000000,-100000000,seed,0};
  Island a=describeIsland(0,0,origin);
  int shifted[4]={origin[0]+1,origin[1]-1,seed,0};Island shiftedIsland=describeIsland(-1,1,shifted);
  for(int k=0;k<12000;k++){
   float size=CELL/512,x=floorf(hash2(k,0,91)*512)*size,z=floorf(hash2(k,1,91)*512)*size;
   auto b=terrainBounds(x+size*.5f,z+size*.5f,size*.5f,a);
   if(k<200){auto shiftedBound=terrainBounds(x+size*.5f-CELL,z+size*.5f+CELL,size*.5f,shiftedIsland);if(fabsf(b.x-shiftedBound.x)>.05f||fabsf(b.y-shiftedBound.y)>.05f){std::cerr<<"Bound rebase mismatch\n";return 5;}}
   for(int j=0;j<12;j++){
    float px=x+(j<4?(float)(j%2):hash2(k,j,92))*size,pz=z+(j<4?(float)(j/2):hash2(k,j,93))*size,fp=j==0?.2f:powf(2,(float)j-3);
    float h=islandHeight(px,pz,a,fp);
    if(h<b.x||h>b.y){std::cerr<<"Unsafe terrain bound seed="<<seed<<" height="<<h<<" interval="<<b.x<<","<<b.y<<"\n";return 1;}samples++;
   }
  }
 }
 int origin[4]={0,0,884,0};std::vector<float> cache(TERRAIN_BASE+TERRAIN_FLOATS);
 blockDim={1,1,1};threadIdx={0,0,0};
 for(int tile=0;tile<9;tile++)for(int z=0;z<512;z++)for(int x=0;x<512;x++){blockIdx={(unsigned)x,(unsigned)z,(unsigned)tile};cacheTerrain(origin,cache.data());}
 for(int level=1;level<=9;level++)for(int tile=0;tile<9;tile++)for(int z=0;z<(512>>level);z++)for(int x=0;x<(512>>level);x++){blockIdx={(unsigned)x,(unsigned)z,(unsigned)tile};mipTerrain(cache.data(),level);}
 float maxError=0;int hits=0,mismatches=0;
 for(int k=0;k<5000;k++){
  float3 ro=k<2500?make_float3(1850,25,1250):make_float3(hash2(k,0,73)*14400-4800,hash2(k,1,73)*450,hash2(k,2,73)*14400-4800);
  float3 rd=norm3(make_float3(hash2(k,3,73)*2-1,hash2(k,4,73)*1.4f-.8f,hash2(k,5,73)*2-1));
  float cone=.0002f+hash2(k,6,73)*.002f;
  float a=traceLand(ro,rd,origin,18000,cone),b=traceLandCached(ro,rd,origin,18000,cone,cache.data());
  if((a<0)!=(b<0)){mismatches++;continue;}
  // Keep depth shifts within the original traversal's one-metre minimum step.
  if(a>0){hits++;float error=fabsf(a-b);maxError=fmaxf(error,maxError);if(error>1.0f){std::cerr<<"Intersection moved beyond the original one-metre march step: "<<error<<"\n";return 2;}
   float3 hit=ro+rd*b;float fp=fmaxf(.2f,b*cone);Island island=describeIsland((int)floorf(hit.x/CELL),(int)floorf(hit.z/CELL),origin);
   float gap=hit.y-islandHeight(hit.x,hit.z,island,fp);
   if(ro.y>ground(ro.x,ro.z,origin,.2f)+.1f&&fabsf(gap)>fmaxf(.2f,fp*.15f+.1f)){std::cerr<<"Refined hit residual "<<gap<<"\n";return 4;}}
 }
 if(mismatches){std::cerr<<"Hit/miss differences: "<<mismatches<<"\n";return 3;}
 std::cout<<samples<<" conservative bounds samples; 5000 cached/reference rays, "<<hits<<" hits, maximum error "<<maxError<<" m\n";
}
