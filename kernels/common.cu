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
// Shared radiometry: surface illumination, water highlights and the sky use the
// same elevation-dependent sunlight. Values are scene-linear until display encoding.
__device__ float3 sunRadiance(float3 sun){
 float air=1/fmaxf(.055f,sun.y),day=smoothf(-.04f,.04f,sun.y);
 return make_float3(2.8f*expf(-.025f*air),2.9f*expf(-.055f*air),3.05f*expf(-.12f*air))*day;
}
__device__ float cloudField(float u,float v,float fp){
 float warp=noise2(u*.31f+18,v*.31f-4);
 return .5f+(noise2(u+warp*.85f,v-warp*.6f)-.5f)*.57f*weight(fp,1)+(noise2(u*2.17f+31,v*2.17f)-.5f)*.28f*weight(fp,2.17f)+(noise2(u*5.1f,v*5.1f+9)-.5f)*.15f*weight(fp,5.1f);
}
// Analytic atmosphere and bounded procedural cloud layer, not a volumetric solver.
// The solar disk is EXCLUDED from the reflection environment: the GGX lobe accounts
// for the sun exactly once, avoiding the old double sun painted into the water.
__device__ float3 skyRadiance(float3 d,float3 sun,float includeDisk,float blur){
 float h=sat(d.y),mu=sat(dot3(d,sun)),warm=1-smoothf(.10f,.55f,sun.y);
 float3 horizon=mix3(make_float3(.46f,.64f,.79f),make_float3(.64f,.245f,.065f),warm*.82f);
 float3 zenith=mix3(make_float3(.040f,.145f,.33f),make_float3(.035f,.055f,.13f),warm*.65f);
 float3 c=mix3(horizon,zenith,powf(h,.40f));
 c=c+sunRadiance(sun)*(powf(mu,12)*(.027f+warm*.07f)+powf(mu,96)*.035f)*(1-h*.7f);
 float cloudAlpha=0;
 if(d.y>.025f){
  float u=d.x/(d.y+.19f)*2.8f+7,v=d.z/(d.y+.19f)*2.8f-4;
  float cfp=blur*2.8f/(d.y+.19f);float density=cloudField(u,v,cfp),macro=noise2(u*.28f+3,v*.28f);
  cloudAlpha=lerpf(.11f,smoothf(.59f,.80f,density+macro*.085f),weight(cfp,1))*smoothf(.025f,.16f,d.y);
  if(cloudAlpha>.001f){
   float towards=cloudField(u+sun.x*.22f,v+sun.z*.22f,cfp);
   float edge=sat(.56f+(density-towards)*3.8f),thickness=smoothf(.58f,.82f,density);
   float3 ambient=mix3(make_float3(.24f,.32f,.40f),make_float3(.18f,.20f,.29f),warm);
   float3 lit=ambient+sunRadiance(sun)*(.21f+edge*.11f);
   lit=lit*(1-thickness*.16f)+sunRadiance(sun)*(powf(mu,18)*.12f*(1-thickness));
   c=mix3(c,lit,cloudAlpha*.88f);
  }
 }
 float disk=smoothf(.999980f,.999991f,dot3(d,sun))*includeDisk;
 return c+sunRadiance(sun)*(disk*14*(1-cloudAlpha*.94f));
}
__device__ float3 sky(float3 d,float3 sun){return skyRadiance(d,sun,1,0);}
__device__ float3 skyEnvironment(float3 d,float3 sun){return skyRadiance(d,sun,0,0);}
__device__ float3 skyReflection(float3 d,float3 sun,float variance){return skyRadiance(d,sun,0,.018f+sqrtf(fmaxf(0,variance))*.35f);}
// Fresnel of an air/water dielectric interface (Schlick), shared by both paths.
__device__ float waterFresnel(float cosine){float m=1-sat(cosine),m2=m*m;return .0204f+.9796f*m2*m2*m;}
// This returns BRDF * N.L, with Smith visibility. Explicit horizon guards avoid
// illuminating back-facing water or producing infinities at grazing angles.
__device__ float waterSunLobe(float3 n,float3 rd,float3 sun,float variance,float wind){
 float nv=sat(-dot3(n,rd)),nl=sat(dot3(n,sun));if(nv<=0||nl<=0)return 0;
 float3 halfVector=norm3(sun-rd);float nh=sat(dot3(n,halfVector)),vh=sat(-dot3(rd,halfVector));
 float alpha=.024f+.012f*clampf(wind,.25f,2.5f);
 float a2=clampf(alpha*alpha+fmaxf(0,variance)*.5f+.0000216f,.0004f,.35f);
 float den=nh*nh*(a2-1)+1,D=a2/(PI*den*den);
 float gv=2*nv/(nv+sqrtf(a2+(1-a2)*nv*nv)),gl=2*nl/(nl+sqrtf(a2+(1-a2)*nl*nl));
 return D*gv*gl*waterFresnel(vh)/(4*fmaxf(nv,.001f));
}

// Analytic exponential-height haze: dense near sea level, clear at altitude.
// Integrate along the whole segment, including downward aerial views.
__device__ float hazeOpticalDepth(float fromHeight,float toHeight,float distance){
 float a=clampf(fromHeight,-100,12000)/350,b=clampf(toHeight,-100,12000)/350,d=b-a;
 float mean=fabsf(d)<.01f?expf(-(a+b)*.5f):(expf(-a)-expf(-b))/d;
 return fmaxf(0,distance)*(.000015f+.000085f*mean);
}
__device__ float3 aerialPerspective(float3 color,float3 ro,float3 rd,float distance,float3 sun){
 float transmission=expf(-hazeOpticalDepth(ro.y,ro.y+rd.y*distance,distance));
 float3 horizon=norm3(make_float3(rd.x,.012f,rd.z));
 float3 haze=skyEnvironment(horizon,sun);
 float forward=powf(sat(dot3(rd,sun)),8)*(1-smoothf(.15f,.8f,sun.y));
 haze=mix3(haze,make_float3(.95f,.70f,.43f),forward*.22f);
 float3 result=mix3(haze,color,transmission);
 // Match sky rays continuously as geometry reaches the finite query limit.
 if(distance>FAR*.8f)result=mix3(result,sky(rd,sun),smoothf(FAR*.8f,FAR,distance));
 return result;
}
__device__ float aces(float x){return sat(x*(2.51f*x+0.03f)/(x*(2.43f*x+0.59f)+0.14f));}
__device__ float linearToDisplay(float x){x=aces(x);return x<=.0031308f?12.92f*x:1.055f*powf(x,1/2.4f)-.055f;}
__device__ unsigned int pack(float3 c){return (unsigned int)(sat(c.x)*255.0f)|((unsigned int)(sat(c.y)*255.0f)<<8)|((unsigned int)(sat(c.z)*255.0f)<<16)|4278190080u;}
__device__ float3 cameraRay(const float* C,int x,int y,int width,int height){
 float3 f=make_float3(sinf(C[3])*cosf(C[4]),sinf(C[4]),cosf(C[3])*cosf(C[4]));
 float3 r=make_float3(cosf(C[3]),0,-sinf(C[3])),u=cross3(f,r);
 float sx=((float)x+0.5f-(float)width*0.5f)/(float)height*1.05f,sy=-((float)y+0.5f-(float)height*0.5f)/(float)height*1.05f;
 return norm3(f+r*sx+u*sy);
}
__device__ float3 sunDirection(const float* C){return norm3(make_float3(cosf(C[7]),C[8],sinf(C[7])));}
