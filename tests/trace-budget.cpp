#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "trace-reference.hpp"
int main(){
 // New trip count is derived from the ray span, not a lower-quality march budget.
 int count=0;
 for(int seed:{0,42,884,12345}){int o[4]={0,0,seed,0};
  for(int i=0;i<500;i++){
   float3 ro=make_float3(hash2(i,0,31)*9600-2400,hash2(i,1,31)*650,hash2(i,2,31)*9600-2400);
   float3 rd=norm3(make_float3(hash2(i,3,31)*2-1,hash2(i,4,31)*1.2f-.7f,hash2(i,5,31)*2-1));
   float limit=10+hash2(i,6,31)*(FAR-10),cone=.0001f+hash2(i,7,31)*.01f;
   float a=traceLand(ro,rd,o,limit,cone),b=referenceTraceLand(ro,rd,o,limit,cone);
   if(a!=b){std::cerr<<"Traversal changed: seed "<<seed<<" ray "<<i<<" old "<<b<<" new "<<a<<"\n";return 49;}count++;
  }
 }
 std::cout<<count<<" dynamic-bound terrain rays exactly match the original traversal\n";
 return 0;
}
