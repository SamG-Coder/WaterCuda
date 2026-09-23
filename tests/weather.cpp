#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/weather.cu"
int main(){
 float controls[16]={};controls[7]=-.7f;controls[8]=22;
 auto noon=sunDirection(controls);controls[8]=10;auto midnight=sunDirection(controls);
 if(noon.y<.8f||midnight.y>-.8f)return 20;
 auto daySky=skyRadiance(make_float3(0,1,0),noon,0,0),nightSky=skyRadiance(make_float3(0,1,0),midnight,0,0);
 if(nightSky.z>daySky.z*.1f||dot3(sunRadiance(midnight),sunRadiance(midnight))>1e-6f)return 21;
 controls[8]=33.99f;auto before=sunDirection(controls);controls[5]=1.2f;auto after=sunDirection(controls);
 if(dot3(before,after)<.999f||worldHour(controls)>.02f)return 22;
 controls[8]=.7f;auto manual=sunDirection(controls);controls[5]=900;
 if(dot3(manual-sunDirection(controls),manual-sunDirection(controls))>1e-8f)return 23;
 controls[8]=22;controls[5]=0;auto initial=sunDirection(controls);controls[5]=1440;
 if(dot3(initial,sunDirection(controls))<.99999f)return 24;
 std::cout<<"PASS solar clock: day/night radiance, midnight continuity, 24-minute period and manual override\n";
 float low=1,high=0,storm=0;int changed=0,lingering=0;float continuity=0;
 for(int i=0;i<800;i++){
  int o[4]={100000000,-100000000,884,0},shift[4]={100000001,-100000001,884,0},other[4]={100000000,-100000000,42,0};
  float x=hash2(i,0,7)*4800,z=hash2(i,1,7)*4800,time=i*11.3f;
  auto a=weatherAt(x,z,time,0,o),b=weatherAt(x-CELL,z+CELL,time,0,shift),c=weatherAt(x,z,time,0,other);
  if(!std::isfinite(a.x)||fabsf(a.x-b.x)>.001f||fabsf(a.y-b.y)>.001f||fabsf(a.w-b.w)>.001f)return 1;
  if(fabsf(a.y-c.y)>.1f)changed++;
  auto next=weatherAt(x,z,time+.02f,0,o);continuity=fmaxf(continuity,fabsf(next.y-a.y));
  low=fminf(low,a.y);high=fmaxf(high,a.y);storm=fmaxf(storm,a.z);if(a.w>a.y+.04f)lingering++;
  float ga=weatherWaveGain(x,z,time,0,o),gb=weatherWaveGain(x-CELL,z+CELL,time,0,shift);if(fabsf(ga-gb)>.001f||ga<.64f||ga>1.81f)return 2;
 }
 if(low>.01f||high<.7f||storm<.1f||changed<100||lingering<5||continuity>.005f)return 3;
 int o[4]={0,0,884,0};
 for(int epoch=-1;epoch<8;epoch++){
  float t=epoch*1200.f;auto a=weatherAt(2400,2400,t-.01f,0,o),b=weatherAt(2400,2400,t+.01f,0,o);
  if(fabsf(a.y-b.y)>.001f)return 4;
 }
 if(weatherWaveGain(0,0,0,4,o)<=weatherWaveGain(0,0,0,1,o))return 5;
 auto col=rainColumn(0,0,o);int shifted[4]={1,-1,884,0};auto rebased=rainColumn(-3200,3200,shifted);
 if(fabsf(col.x-rebased.x-CELL)>.001f||fabsf(col.y-rebased.y+CELL)>.001f||col.z!=rebased.z)return 6;
 float time=(col.z*8+.08f-4)/18+8.0f/18;
 float3 point=make_float3(col.x-4*.08f,4,col.y-4*.025f),ro=point-make_float3(0,0,1),rd=make_float3(0,0,1);
 float visible=rainVisibility(ro,rd,2,.001f,time,1,o);if(visible<=.01f)return 7;
 float3 impact=make_float3(col.x,0,col.y);float impactTime=col.z*8/18;
 if(rainImpact(impact,.001f,impactTime,1,o)<.5f||rainImpact(impact,.001f,impactTime,0,o)!=0)return 8;
 if(rainVisibility(make_float3(0,-1,0),rd,20,.001f,time,1,o)!=0)return 9;
 float flashes=0;for(int i=0;i<3800;i++)flashes=fmaxf(flashes,weatherFlash(2400,2400,i*.01f,1,o));if(flashes<.8f)return 10;
 for(int mode=0;mode<5;mode++)for(int i=0;i<24;i++){
  auto c=weatherSky(make_float3(1200,20,600),norm3(make_float3(i*.05f,.05f+i*.03f,1)),norm3(make_float3(1,.7f,0)),20,(float)mode,o,1);
  if(!std::isfinite(c.x)||!std::isfinite(c.y)||c.x<0||c.y<0)return 11;
 }
 std::cout<<"PASS weather: 800 remote/rebased sites, changing regional weather, epoch continuity "<<continuity<<", "<<lingering<<" lingering wet sites, shared drop/impact phase, dry/underwater exclusion, lightning and cloud finiteness\n";
}
