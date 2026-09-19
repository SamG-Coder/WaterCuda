// Frozen c16326f visibility traversal: differential oracle for dynamic loop bounds.
__device__ float referenceTraceLand(float3 ro,float3 rd,const int* Origin,float limit,float cone){
 float t=0.1f,raySlope=fabsf(rd.y)+3.8f*sqrtf(rd.x*rd.x+rd.z*rd.z);if(ro.y>500){if(rd.y>=-0.0001f)return -1;t=fmaxf(t,(500-ro.y)/rd.y);}
 for(int cell=0;cell<32;cell++){
  if(t>=limit)return -1;float3 p=ro+rd*t;
  if((p.y>500&&rd.y>=0)||(p.y< -46&&rd.y<=0))return -1;
  int cx=(int)floorf(p.x/CELL),cz=(int)floorf(p.z/CELL);
  float bx=(float)(cx+(rd.x>=0?1:0))*CELL,bz=(float)(cz+(rd.z>=0?1:0))*CELL;
  float tx=fabsf(rd.x)>0.000001f?(bx-p.x)/rd.x:1000000.0f;
  float tz=fabsf(rd.z)>0.000001f?(bz-p.z)/rd.z:1000000.0f;
  float end=fminf(limit,t+fmaxf(0.0f,fminf(tx,tz)));
  Island a=describeIsland(cx,cz,Origin);
  if(a.peak>0){float2 range=boxRay(ro,rd,make_float3(a.x-a.radius,-46,a.z-a.radius),make_float3(a.x+a.radius,a.peak+32,a.z+a.radius));
   float s=fmaxf(t,range.x),stop=fminf(end,range.y),previous=s;
   // The longest ray through a 3000 x 518 x 3000 m island box is under 4275 m.
   // A one-metre minimum step and 4352 iterations cover the entire box, including
   // rays nearly parallel to a hillside; never silently drop the rest of the island.
   for(int j=0;j<4352;j++){
    if(s>stop)break;float3 q=ro+rd*s;float fp=fmaxf(0.2f,s*cone);float gap=q.y-islandHeight(q.x,q.z,a,fp);
    if(gap<fmaxf(0.05f,fp*0.15f)){float lo=previous,hi=s;for(int k=0;k<7;k++){float mid=(lo+hi)*0.5f;float3 m=ro+rd*mid;if(m.y>islandHeight(m.x,m.z,a,fmaxf(0.2f,mid*cone)))lo=mid;else hi=mid;}return (lo+hi)*0.5f;}
    previous=s;s+=fmaxf(1.0f,gap/fmaxf(raySlope,.001f));
   }
  }
  t=end+0.04f;
 }
 return -1;
}
