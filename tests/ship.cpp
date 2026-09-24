#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/ship.cu"
#include <chrono>
int main(int argc,char**argv){
 int O[4]={0,0,884,0};float C[32]={696,19,589,-.646f,-.08f,0,1,-.7f,.7f,1,0,1,1.5f,1,0,0};
 float3 sun=norm3(make_float3(-.7f,.65f,-.4f));int width=640,height=480,count[6]={0};
 std::vector<unsigned char> pixels(width*height*3);auto start=std::chrono::steady_clock::now();
 for(int y=0;y<height;y++)for(int x=0;x<width;x++){
  float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height);ShipHit h=traceShip(ro,rd,O,0,1000,1.05f/height,C);
  float3 c=sky(rd,sun)*.7f;
  if(h.part>0){count[(int)h.part]++;c=shipShade(ro+rd*h.t,make_float3(h.nx,h.ny,h.nz),rd,sun,h.part,h.t/height,O,0,C);}
  else if(rd.y<0)c=make_float3(.028f,.10f,.13f)*(1+.10f*sinf(rd.x*250+rd.z*80));
  c=make_float3(powf(sat(c.x),1/2.2f),powf(sat(c.y),1/2.2f),powf(sat(c.z),1/2.2f));
  int i=(y*width+x)*3;pixels[i]=(unsigned char)(c.x*255);pixels[i+1]=(unsigned char)(c.y*255);pixels[i+2]=(unsigned char)(c.z*255);
 }
 ShipHit farJib;farJib.t=100;farJib.part=0;farJib=shipJib(make_float3(10,12,60),make_float3(-1,0,0),0,farJib);if(farJib.part!=0)return 5;
 if(count[1]<500||count[2]<500||count[3]<10||count[4]<5)return 1;
 auto miss=traceShip(make_float3(0,50,0),make_float3(0,1,0),O,0,1000,.001f,C);if(miss.part!=0)return 2;
 float3 ro=make_float3(696,19,589),rd=norm3(make_float3(-46,-5,61));auto a=traceShip(ro,rd,O,0,1000,.001f,C);
 int R[4]={1,-1,884,0};auto b=traceShip(ro-make_float3(CELL,0,-CELL),rd,R,0,1000,.001f,C);if(fabs(a.t-b.t)>.002f||a.part!=b.part)return 3;
 C[14]=3;C[19]=1.2f;C[20]=.15f;C[21]=-.09f;float3 v=make_float3(2,7,-4),w=shipRotate(shipRotate(v,9,-1,C),9,1,C);if(dot3(v-w,v-w)>.000001f)return 4;
 for(int k=1;k<5;k++)std::cout<<"part "<<k<<": "<<count[k]<<" pixels\n";
 std::cout<<"Ship CPU render ms: "<<std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()<<"\n";
 if(argc>1){std::ofstream out(argv[1],std::ios::binary);out<<"P6\n"<<width<<" "<<height<<"\n255\n";out.write((char*)pixels.data(),pixels.size());}
}
