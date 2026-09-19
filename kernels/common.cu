// CUDA is the scene source. No authored meshes or image textures.
#define PI 3.14159265359f
#define CELL 4800.0f
#define FAR 18000.0f
__device__ float clampf(float x,float a,float b){return fminf(b,fmaxf(a,x));}
__device__ float sat(float x){return clampf(x,0.0f,1.0f);}
__device__ float lerpf(float a,float b,float t){return a+(b-a)*t;}
__device__ float fractf(float x){return x-floorf(x);}
__device__ float smoothf(float a,float b,float x){float t=sat((x-a)/(b-a));return t*t*(3.0f-2.0f*t);}
__device__ float dot3(float3 a,float3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
__device__ float3 norm3(float3 a){return a/sqrtf(fmaxf(dot3(a,a),0.0000001f));}
__device__ float3 cross3(float3 a,float3 b){return make_float3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);}
__device__ float3 mix3(float3 a,float3 b,float t){return a+(b-a)*t;}
__device__ unsigned int hashU(unsigned int x){x^=x>>16;x*=2146121005u;x^=x>>15;x*=2221713035u;x^=x>>16;return x;}
__device__ float hash2(int x,int z,unsigned int seed){return (float)(hashU((unsigned int)x*1973u+(unsigned int)z*9277u+seed*26699u)&16777215u)/16777216.0f;}
__device__ float noise2(float x,float z){int ix=(int)floorf(x),iz=(int)floorf(z);float fx=fractf(x),fz=fractf(z);fx=fx*fx*(3-2*fx);fz=fz*fz*(3-2*fz);return lerpf(lerpf(hash2(ix,iz,13),hash2(ix+1,iz,13),fx),lerpf(hash2(ix,iz+1,13),hash2(ix+1,iz+1,13),fx),fz);}
__device__ float weight(float fp,float frequency){return 1-smoothf(0.30f,1.0f,fp*frequency);}
__device__ float safeInv(float v){return 1.0f/(fabsf(v)<0.000001f?(v<0?-0.000001f:0.000001f):v);}
__device__ float2 boxRay(float3 ro,float3 rd,float3 lo,float3 hi){
 float3 a=make_float3((lo.x-ro.x)*safeInv(rd.x),(lo.y-ro.y)*safeInv(rd.y),(lo.z-ro.z)*safeInv(rd.z));
 float3 b=make_float3((hi.x-ro.x)*safeInv(rd.x),(hi.y-ro.y)*safeInv(rd.y),(hi.z-ro.z)*safeInv(rd.z));
 return make_float2(fmaxf(fmaxf(fminf(a.x,b.x),fminf(a.y,b.y)),fminf(a.z,b.z)),fminf(fminf(fmaxf(a.x,b.x),fmaxf(a.y,b.y)),fmaxf(a.z,b.z)));
}
__device__ float3 sky(float3 d,float3 sun){
 float h=sat(d.y);float3 c=mix3(make_float3(0.62f,0.77f,0.85f),make_float3(0.10f,0.32f,0.55f),powf(h,0.42f));
 float s=sat(dot3(d,sun));c=c+make_float3(1.0f,0.73f,0.40f)*(powf(s,28.0f)*0.23f+powf(s,1400.0f)*5.0f);
 float sunset=1-smoothf(0.08f,0.5f,sun.y);c=mix3(c,make_float3(0.84f,0.49f,0.31f),sunset*powf(1-h,4.0f)*0.5f);
 if(d.y>0.015f){float cx=d.x/d.y*1.8f,cz=d.z/d.y*1.8f;float cloud=noise2(cx*0.31f+6,cz*0.31f)*0.65f+noise2(cx*0.91f,cz*0.91f)*0.25f+noise2(cx*2.3f,cz*2.3f)*0.1f;c=mix3(c,make_float3(0.91f,0.94f,0.95f),smoothf(0.57f,0.77f,cloud)*smoothf(0.015f,0.12f,d.y)*0.7f);}
 return c;
}
__device__ float aces(float x){return sat(x*(2.51f*x+0.03f)/(x*(2.43f*x+0.59f)+0.14f));}
__device__ unsigned int pack(float3 c){return (unsigned int)(sat(c.x)*255.0f)|((unsigned int)(sat(c.y)*255.0f)<<8)|((unsigned int)(sat(c.z)*255.0f)<<16)|4278190080u;}
__device__ float3 cameraRay(const float* C,int x,int y,int width,int height){
 float3 f=make_float3(sinf(C[3])*cosf(C[4]),sinf(C[4]),cosf(C[3])*cosf(C[4]));
 float3 r=make_float3(cosf(C[3]),0,-sinf(C[3])),u=cross3(f,r);
 float sx=((float)x+0.5f-(float)width*0.5f)/(float)height*1.05f,sy=-((float)y+0.5f-(float)height*0.5f)/(float)height*1.05f;
 return norm3(f+r*sx+u*sy);
}
__device__ float3 sunDirection(const float* C){return norm3(make_float3(cosf(C[7]),C[8],sinf(C[7])));}
