#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "../kernels/shrubs.cu"
#include "terrain-reference.hpp"
int main(){
 int count=0,hits=0,emerged=0;int o[4]={0,0,884,0},shift[4]={1,-1,884,0};
 Island island=describeIsland(0,0,o);
 float camera[16]={2810,12,1130};std::vector<float> patch(16388);
 blockDim={1,1,1};threadIdx={0,0,0};
 for(int z=0;z<64;z++)for(int x=0;x<64;x++){blockIdx={(unsigned)x,(unsigned)z,0};cacheShrubs(camera,o,patch.data());}
 int cachedCount=0;
 for(int z=0;z<64;z++)for(int x=0;x<64;x++){
  int ix=(int)patch[0]+x,iz=(int)patch[1]+z;
  auto a=describeShrub(ix,iz,o),b=cachedShrub(ix,iz,o,patch.data());
  if(a.size!=b.size||a.root.x!=b.root.x||a.root.y!=b.root.y||a.root.z!=b.root.z)return 8;
  if(a.size>0){cachedCount++;float3 ro=a.root+make_float3(0,.8f,-3),rd=norm3(a.root+make_float3(0,.3f,0)-ro);
   float direct=hitShrub(ro,rd,a,6,3,1,.001f).x,traced=traceShrubs(ro,rd,o,patch.data(),6,3,1,.001f).x;
   if(fabsf(direct-traced)>.02f)return 9;}
 }
 if(cachedCount<10)return 10;
 std::cout<<"4096 cached habitat entries match direct generation; "<<cachedCount<<" cell-traversed shrub rays passed\n";
 for(int z=0;z<800;z+=3)for(int x=0;x<800;x+=3){
  Shrub s=describeShrub(x,z,o),r=describeShrub(x-800,z+800,shift);
  if(s.seed!=r.seed||fabsf(s.size-r.size)>.00001f||fabsf(s.root.y-r.root.y)>.004f){std::cerr<<"Rebase mismatch "<<x<<" "<<z<<" sizes "<<s.size<<" "<<r.size<<" heights "<<s.root.y<<" "<<r.root.y<<"\n";return 1;}
  if(s.size==0)continue;
  if(s.root.y<4.5f||s.root.y>155||groundNormal(s.root,o,.5f).y<.858f)return 2;
  if(s.root.x-1.65f<x*6||s.root.x+1.65f>(x+1)*6||s.root.z-1.65f<z*6||s.root.z+1.65f>(z+1)*6)return 3;
  count++;
  float3 ro=s.root+make_float3(0,1,-4),rd=norm3(s.root+make_float3(0,.4f,0)-ro);
  auto hit=hitShrub(ro,rd,s,8,3,1,.001f);
  if(hit.x<8){hits++;float n=hit.y*hit.y+hit.z*hit.z+hit.w*hit.w;if(fabsf(n-1)>.001f)return 4;}
  auto shifted=hitShrub(ro+make_float3(-CELL,0,CELL),rd,r,8,3,1,.001f);
  if(fabsf(hit.x-shifted.x)>.03f){std::cerr<<"Ray mismatch "<<x<<" "<<z<<" "<<hit.x<<" "<<shifted.x<<"\n";return 5;}
  if(count==10)std::cout<<"Scrub preview seed 884 camera: "<<ro.x<<" "<<ro.y+1<<" "<<ro.z-6<<"\n";
 }
 float bestBar=0;float3 barPoint=make_float3(0,0,0);int submergedBars=0;
 for(int z=0;z<250;z++)for(int x=0;x<250;x++){
  float mx=-island.radius+(float)x*island.radius/125,mz=-island.radius+(float)z*island.radius/125;
  float h=islandHeight(island.x+mx,island.z+mz,island,.2f);
  float old=referenceIslandHeight(island.x+mx,island.z+mz,island,.2f);
  if(old< -3&&h>old+2){submergedBars++;if(h>bestBar){bestBar=h;barPoint=make_float3(island.x+mx,h,island.z+mz);}}
  float rebased=ground(island.x+mx-CELL,island.z+mz+CELL,shift,.2f);
  if(fabsf(h-rebased)>.025f)return 6;
  if(h>0&&h<2)emerged++;
 }
 if(count<100||hits<count*.95f||emerged<10||submergedBars<20||bestBar<=0)return 7;
 std::cout<<submergedBars<<" raised offshore bar samples; exposed bar at "<<barPoint.x<<" "<<barPoint.y<<" "<<barPoint.z<<"\n";
 std::cout<<count<<" seeded shrubs: habitat, bounds, rebasing; "<<hits<<" branch hits and "<<emerged<<" low coastal samples\n";
 return 0;
}
