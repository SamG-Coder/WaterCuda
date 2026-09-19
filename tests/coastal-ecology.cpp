#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "../kernels/shrubs.cu"
#include "shrub-atlas.hpp"
#include "terrain-reference.hpp"
int main(){
 int count=0,hits=0,emerged=0;int o[4]={0,0,884,0},shift[4]={1,-1,884,0};
 Island island=describeIsland(0,0,o);
 float camera[16]={2810,12,1130};std::vector<float> patch(SHRUB_FLOATS);buildShrubAtlas(patch.data());
 blockDim={1,1,1};threadIdx={0,0,0};
 for(int z=0;z<64;z++)for(int x=0;x<64;x++){blockIdx={(unsigned)x,(unsigned)z,0};cacheShrubs(camera,o,patch.data());}
 // Mips preserve premultiplied coverage, holes stay transparent, far foliage persists.
 for(int tile=0;tile<8;tile++){
  double sum=0;for(int y=0;y<128;y++)for(int x=0;x<128;x++)sum+=patch[shrubTexel(tile,0,x,y)+3];
  float avg=patch[shrubTexel(tile,7,0,0)+3];if(avg<.08f||avg>.8f||fabs(sum/16384-avg)>1e-5)return 12;
  if(shrubTexture(0,1,tile,0,patch.data()).w>.01f)return 13;
 }
 if(shrubGroundBlend(65)!=0||shrubGroundBlend(125)!=1||shrubGroundBlend(10000)!=1)return 14;
 int persistent=0;
 for(int z=160;z<240;z++)for(int x=420;x<500;x++){
  Shrub s=describeShrub(x,z,o);if(s.size==0)continue;
  float3 base=make_float3(.5f,.5f,.5f),up=make_float3(0,1,0),sun=norm3(make_float3(1,1,1));
  float3 c=shrubGround(base,s.root,up,sun,o,patch.data(),.1f,1000);
  if(dot3(c-base,c-base)>.001f)persistent++;
 }
 if(persistent<10)return 15;
 Shrub card;card.root=make_float3(0,10,0);card.size=1;card.seed=.5f;
 // Transparent sky corner must not create a rectangular billboard silhouette.
 if(hitShrub(make_float3(.99f,11.7f,-3),make_float3(0,0,1),card,patch.data(),6,0,0,.001f).x<6)return 16;
 if(hitShrub(make_float3(0,11,-200),make_float3(0,0,1),card,patch.data(),250,0,0,.001f).x<250)return 17;
 for(float edge:{65.f,125.f})if(fabsf(shrubGroundBlend(edge+.01f)-shrubGroundBlend(edge-.01f))>.0001f)return 18;
 std::cout<<persistent<<" distant ground crowns remain beyond card/cache range; atlas coverage preserved\n";
 int cachedCount=0;
 for(int z=0;z<64;z++)for(int x=0;x<64;x++){
  int ix=(int)patch[0]+x,iz=(int)patch[1]+z;
  auto a=describeShrub(ix,iz,o),b=cachedShrub(ix,iz,o,patch.data());
  if(a.size!=b.size||a.root.x!=b.root.x||a.root.y!=b.root.y||a.root.z!=b.root.z)return 8;
  if(a.size>0){cachedCount++;float3 ro=a.root+make_float3(0,.8f,-3),rd=norm3(a.root+make_float3(0,.3f,0)-ro);
   float direct=hitShrub(ro,rd,a,patch.data(),6,3,1,.001f).x,traced=traceShrubs(ro,rd,o,patch.data(),6,3,1,.001f).x;
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
  auto hit=hitShrub(ro,rd,s,patch.data(),8,3,1,.001f);
  if(hit.x<8){hits++;if(hit.y<0||hit.y>1||hit.z<0||hit.z>1||hit.w<0||hit.w>=4)return 4;}
  auto shifted=hitShrub(ro+make_float3(-CELL,0,CELL),rd,r,patch.data(),8,3,1,.001f);
  if(fabsf(hit.x-shifted.x)>.03f){std::cerr<<"Ray mismatch "<<x<<" "<<z<<" "<<hit.x<<" "<<shifted.x<<"\n";return 5;}
  if(count==10)std::cout<<"Scrub preview seed 884 camera: "<<ro.x<<" "<<ro.y+1<<" "<<ro.z-6<<"\n";
 }
 float bestBar=-100;float3 barPoint=make_float3(0,0,0);int submergedBars=0;
 for(int z=0;z<250;z++)for(int x=0;x<250;x++){
  float mx=-island.radius+(float)x*island.radius/125,mz=-island.radius+(float)z*island.radius/125;
  float h=islandHeight(island.x+mx,island.z+mz,island,.2f);
  float old=referenceIslandHeight(island.x+mx,island.z+mz,island,.2f);
  if(old< -3&&h>old+2){submergedBars++;if(h>=-1.79f)return 11;if(h>bestBar){bestBar=h;barPoint=make_float3(island.x+mx,h,island.z+mz);}}
  float rebased=ground(island.x+mx-CELL,island.z+mz+CELL,shift,.2f);
  if(fabsf(h-rebased)>.025f)return 6;
  if(h>0&&h<2)emerged++;
 }
 if(count<100||hits<count*.75f||emerged<10||submergedBars<20||bestBar< -3||bestBar>=0)return 7;
 std::cout<<submergedBars<<" raised offshore bar samples; submerged bank at "<<barPoint.x<<" "<<barPoint.y<<" "<<barPoint.z<<"\n";
 std::cout<<count<<" seeded shrubs: habitat, bounds, rebasing; "<<hits<<" alpha-tested card hits and "<<emerged<<" low coastal samples\n";
 return 0;
}
