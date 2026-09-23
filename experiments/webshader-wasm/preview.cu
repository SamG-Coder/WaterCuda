// Small startup renderer. Both WGSL and WASM are generated from this kernel.
// World shape, camera, daylight, weather sky and land materials come from the
// production .cu files; expensive FFT waves/reflections/foliage wait for handover.
__global__ void previewWorld(const float* C,const int* Origin,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);
 if(x>=width||y>=height)return;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float water=rd.y<-.00001f?fmaxf(.01f,-ro.y/rd.y):FAR;
 float t=traceLand(ro,rd,Origin,fminf(FAR,water),1.05f/(float)height);
 float3 col=weatherSky(ro,rd,sun,C[5],C[15],Origin,1);
 if(t>0){
  float3 p=ro+rd*t;float fp=fmaxf(.5f,t*1.05f/(float)height);
  float3 n=groundNormal(p,Origin,fp);
  col=landColor(p,n,sun,Origin,fp);
  col=mix3(col,sky(rd,sun),1-expf(-t/13000));
 }else if(water<FAR){
  float3 p=ro+rd*water;
  float ripple=sinf(p.x*.10f+C[5])*.025f+cosf(p.z*.075f-C[5]*.8f)*.02f;
  float3 n=norm3(make_float3(ripple,1,ripple*.6f)),rr=rd-n*(2*dot3(rd,n));
  float f=waterFresnel(-dot3(n,rd));
  col=mix3(make_float3(.018f,.13f,.16f),skyEnvironment(rr,sun),f);
  col=col+sunRadiance(sun)*(waterSunLobe(n,rd,sun,.008f,C[6])*.3f);
 }
 Pixels[y*width+x]=pack(make_float3(linearToDisplay(col.x),linearToDisplay(col.y),linearToDisplay(col.z)));
}
