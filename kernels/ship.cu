// One inspectable hero ship. All geometry, cloth and materials live in CUDA.
// Smooth analytic surfaces avoid tessellation buffers; detail follows ray footprint.
struct ShipHit {float t;float nx;float ny;float nz;float part;};
__device__ float3 shipRoot(const int* O,float time,const float* C){if(C[14]>=3)return make_float3(C[16],C[22],C[18]);return make_float3(650-(float)O[0]*CELL,.22f*sinf(time*.72f),650-(float)O[1]*CELL);}
// Inverse rotations use reverse order so intersections and shading agree.
__device__ float3 shipRotate(float3 p,float time,float inverse,const float* C){
 float yaw=C[14]>=3?C[19]:0,roll=C[14]>=3?C[20]:.018f*sinf(time*.61f),pitch=C[14]>=3?C[21]:0;
 if(inverse>0){float c=cosf(yaw),s=sinf(yaw);p=make_float3(c*p.x-s*p.z,p.y,s*p.x+c*p.z);c=cosf(pitch);s=sinf(pitch);p=make_float3(p.x,c*p.y+s*p.z,-s*p.y+c*p.z);c=cosf(roll);s=sinf(roll);p=make_float3(c*p.x+s*p.y,-s*p.x+c*p.y,p.z);}
 else {float c=cosf(roll),s=sinf(roll);p=make_float3(c*p.x-s*p.y,s*p.x+c*p.y,p.z);c=cosf(pitch);s=sinf(pitch);p=make_float3(p.x,c*p.y-s*p.z,s*p.y+c*p.z);c=cosf(yaw);s=sinf(yaw);p=make_float3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);}
 return p;
}
__device__ float shipBox(float3 p,float3 b){
 float3 q=make_float3(fabsf(p.x)-b.x,fabsf(p.y)-b.y,fabsf(p.z)-b.z);
 float3 v=make_float3(fmaxf(q.x,0),fmaxf(q.y,0),fmaxf(q.z,0));
 return sqrtf(dot3(v,v))+fminf(fmaxf(q.x,fmaxf(q.y,q.z)),0);
}
__device__ float shipBeam(float z){
 float u=clampf((z+19)/40,0,1);return 6.15f*powf(fmaxf(.002f,sinf(PI*(.20f+.80f*u))),.65f)*(1-.28f*u);
}
__device__ float shipDeck(float z){return 2.7f+2.3f*powf(sat(fabsf(z)/20),3)+1.35f*smoothf(10,14,z);}
__device__ float shipBody(float3 p,float fp){
 float deck=shipDeck(p.z),beam=shipBeam(p.z),low=-3.3f+.10f*fabsf(p.z);
 float section=sat((p.y-low)/(deck-low));
 float width=beam*sqrtf(fmaxf(.01f,section));
 // Hollow bulwarks above a solid deck: a curved, pointed bow and deep keel.
 float hull=fmaxf(fabsf(p.x)-width,fmaxf(low-p.y,p.y-deck));
 hull=fmaxf(hull,fmaxf(-18.9f-p.z,p.z-20.9f));
 float wall=fmaxf(fabsf(fabsf(p.x)-beam)-.16f,fmaxf(deck-p.y,p.y-deck-.85f));
 wall=fmaxf(wall,fabsf(p.z-1)-19.1f);
 hull=fminf(hull,wall);
 // Gun ports cut into the side, not dark decals floating above the hull.
 if(fp<.3f&&fabsf(p.z)<12){float z=p.z-3.2f*floorf(p.z/3.2f+.5f);
  float port=shipBox(make_float3(fabsf(p.x)-beam*.91f,p.y-1.35f,z),make_float3(.9f,.43f,.48f));hull=fmaxf(hull,-port);}
 float cabin=shipBox(p-make_float3(0,5.5f,-13.7f),make_float3(4.2f,1.9f,4.6f));
 float roof=shipBox(p-make_float3(0,7.55f,-13.7f),make_float3(4.55f,.22f,4.9f));
 float upper=shipBox(p-make_float3(0,8.5f,-15.5f),make_float3(3.55f,1.05f,2.65f));upper=fmaxf(upper,(fabsf(p.x)+fabsf(p.z+15.5f)-5.6f)*.707f);
 cabin=fminf(cabin,upper);roof=fminf(roof,shipBox(p-make_float3(0,9.75f,-15.5f),make_float3(3.8f,.20f,2.95f)));
 float balcony=shipBox(p-make_float3(0,5.2f,-18.4f),make_float3(4.5f,.16f,1.1f));roof=fminf(roof,balcony);
 float hatch=shipBox(p-make_float3(0,3.02f,2.5f),make_float3(1.3f,.3f,1.8f));
 float d=fminf(hull,fminf(cabin,fminf(roof,hatch)));
 if(fp<.3f){
  // Paired deck stairs and rounded coopered barrels, clipped to local bounds.
  if(p.z> -10&&p.z< -5&&fabsf(p.x)>1.8f&&fabsf(p.x)<3.1f){float step=floorf((-p.z-5)*1.8f);float stair=shipBox(p-make_float3(p.x<0?-2.45f:2.45f,3.1f+step*.18f,p.z),make_float3(.55f,.18f,.3f));d=fminf(d,stair);}
  for(int barrel=0;barrel<4;barrel++){float3 q=p-make_float3(barrel<2?-2.7f:2.7f,3.6f,5+(float)(barrel%2)*1.15f);float radius=.42f+.09f*(1-sat(q.y*q.y*2));d=fminf(d,fmaxf(sqrtf(q.x*q.x+q.z*q.z)-radius,fabsf(q.y)-.64f));}
  float3 cap=p-make_float3(0,3.65f,10);d=fminf(d,fmaxf(sqrtf(cap.x*cap.x+cap.z*cap.z)-.55f,fabsf(cap.y)-.65f));
 }
 d=fminf(d,shipBox(p-make_float3(0,-.8f,-19.3f),make_float3(.16f,1.35f,.45f)));
 float gallery=shipBox(p-make_float3(0,4,-17.65f),make_float3(3.5f,.12f,.7f));
 d=fminf(d,gallery);
 float sternRail=fmaxf(fabsf(p.y-10.6f)-.075f,fabsf(shipBox(make_float3(p.x,0,p.z+15.5f),make_float3(3.7f,1,2.8f)))-.08f);
 d=fminf(d,sternRail);
 if(fp<.09f){float z=p.z-1.05f*floorf(p.z/1.05f+.5f);float fence=shipBox(make_float3(fabsf(p.x)-3.7f,p.y-10.25f,z),make_float3(.045f,.35f,.045f));d=fminf(d,fmaxf(fence,fabsf(p.z+15.5f)-2.8f));}
 // Rail caps remain at all LODs; close balusters use a repeated local cell.
 float rail=fmaxf(fabsf(fabsf(p.x)-beam)-.105f,fmaxf(fabsf(p.y-deck-1.22f)-.10f,fabsf(p.z-1)-18.8f));
 d=fminf(d,rail);
 if(fp<.09f){float z=p.z-1.3f*floorf(p.z/1.3f+.5f);float post=shipBox(make_float3(fabsf(p.x)-beam,p.y-deck-.98f,z),make_float3(.075f,.28f,.075f));d=fminf(d,fmaxf(post,fabsf(p.z-1)-18.5f));}
 // Raised beakhead platform and curved cheeks below the bowsprit.
 if(p.z>19&&p.z<29){float u=(p.z-19)/10,w=1.7f*(1-u)+.2f,y=4.5f+3.3f*u;
  float platform=fmaxf(fabsf(p.x)-w,fabsf(p.y-y)-.13f);d=fminf(d,platform);
  float cheek=fmaxf(fabsf(fabsf(p.x)-w*.8f)-.11f,fabsf(p.y-(y-1.2f*sinf(PI*u)))-.17f);d=fminf(d,cheek);
  float rim=fmaxf(fabsf(fabsf(p.x)-w)-.075f,fabsf(p.y-y-.7f)-.09f);d=fminf(d,rim);
 }
 return d*.55f;
}
__device__ ShipHit shipCylinder(float3 ro,float3 rd,float3 a,float3 b,float radius,float part,ShipHit hit){
 float3 ba=b-a,oa=ro-a;float bb=dot3(ba,ba),br=dot3(ba,rd),bo=dot3(ba,oa),rr=dot3(rd,oa);
 float aa=bb-br*br,ab=bb*rr-bo*br,cc=bb*dot3(oa,oa)-bo*bo-radius*radius*bb,disc=ab*ab-aa*cc;
 if(aa>.000001f&&disc>=0){float t=(-ab-sqrtf(disc))/aa,y=bo+t*br;
  if(t>.002f&&t<hit.t&&y>=0&&y<=bb){float3 n=norm3(oa+rd*t-ba*(y/bb));hit.t=t;hit.nx=n.x;hit.ny=n.y;hit.nz=n.z;hit.part=part;}}
 return hit;
}
__device__ float shipSailZ(float x,float y,float width,float height,float time,float seed){
 float u=x/width,v=y/height;return 1.8f*(1-u*u)*sinf(PI*sat(v))+.12f*sinf(x*1.7f+time*.8f+seed)*sinf(PI*sat(v));
}
__device__ ShipHit shipSail(float3 ro,float3 rd,float z,float top,float width,float height,float time,float seed,float part,ShipHit hit){
 float3 q=ro-make_float3(0,top-height,z);
 float2 bounds=boxRay(q,rd,make_float3(-width,0,-.3f),make_float3(width,height,2.2f));
 float t=fmaxf(.002f,bounds.x),end=fminf(hit.t,bounds.y);if(t>=end)return hit;
 for(int i=0;i<48;i++){
  float3 p=q+rd*t;float effective=width*(.86f+.14f*sat(p.y/height));
  float cloth=p.z-shipSailZ(p.x,p.y,width,height,time,seed);
  float d=fmaxf(fabsf(cloth)*.6f,fmaxf(fabsf(p.x)-effective,fmaxf(-p.y,p.y-height)));
  if(d<.018f){
   float e=.025f,dx=(shipSailZ(p.x+e,p.y,width,height,time,seed)-shipSailZ(p.x-e,p.y,width,height,time,seed))/(2*e);
   float dy=(shipSailZ(p.x,p.y+e,width,height,time,seed)-shipSailZ(p.x,p.y-e,width,height,time,seed))/(2*e);
   float3 n=norm3(make_float3(-dx,-dy,1));if(dot3(n,rd)>0)n=n*-1;
   hit.t=t;hit.nx=n.x;hit.ny=n.y;hit.nz=n.z;hit.part=part;return hit;
  }t+=fmaxf(.012f,d*.75f);if(t>end)break;
 }return hit;
}
__device__ ShipHit shipTriangle(float3 ro,float3 rd,float3 a,float3 b,float3 c,ShipHit hit){
 float3 e=b-a,f=c-a,h=cross3(rd,f);float det=dot3(e,h);if(fabsf(det)<.00001f)return hit;
 float3 s=ro-a;float u=dot3(s,h)/det;if(u<0||u>1)return hit;float3 q=cross3(s,e);float v=dot3(rd,q)/det;if(v<0||u+v>1)return hit;
 float t=dot3(f,q)/det;if(t>.002f&&t<hit.t){float3 n=norm3(cross3(e,f));if(dot3(n,rd)>0)n=n*-1;hit.t=t;hit.nx=n.x;hit.ny=n.y;hit.nz=n.z;hit.part=2;}return hit;
}
__device__ float shipJibX(float y,float z,float time){
 float v=sat((y-10.5f)/8.5f),lo=lerpf(13,11,v),hi=lerpf(27.0f,11,v),u=sat((z-lo)/fmaxf(.05f,hi-lo));
 return 1.25f*sinf(PI*u)*sinf(PI*v)+.08f*sinf(z*2+time)*sinf(PI*v);
}
__device__ ShipHit shipJib(float3 ro,float3 rd,float time,ShipHit hit){
 float2 bounds=boxRay(ro,rd,make_float3(-.2f,10.5f,11),make_float3(2.4f,19,27.0f));float t=fmaxf(.002f,bounds.x),end=fminf(hit.t,bounds.y);
 if(t>=end)return hit;
 for(int i=0;i<72;i++){float3 p=ro+rd*t;float v=sat((p.y-10.5f)/8.5f),lo=lerpf(13,11,v),hi=lerpf(27.0f,11,v);
  float d=fmaxf(fabsf(p.x-shipJibX(p.y,p.z,time))*.45f,fmaxf(lo-p.z,p.z-hi)*.6f);d=fmaxf(d,fmaxf(10.5f-p.y,p.y-19));
  if(d<.014f){float e=.02f;float3 n=norm3(make_float3(1,-(shipJibX(p.y+e,p.z,time)-shipJibX(p.y-e,p.z,time))/(2*e),-(shipJibX(p.y,p.z+e,time)-shipJibX(p.y,p.z-e,time))/(2*e)));if(dot3(n,rd)>0)n=n*-1;hit.t=t;hit.nx=n.x;hit.ny=n.y;hit.nz=n.z;hit.part=2;return hit;}
  t+=fmaxf(.009f,d);if(t>end)break;
 }return hit;
}
__device__ ShipHit traceShip(float3 worldRo,float3 worldRd,const int* O,float time,float limit,float cone,const float* C){
 ShipHit hit;hit.t=limit;hit.nx=0;hit.ny=1;hit.nz=0;hit.part=0;
 float3 ro=shipRotate(worldRo-shipRoot(O,time,C),time,1,C),rd=shipRotate(worldRd,time,1,C);
 float2 bounds=boxRay(ro,rd,make_float3(-12,-5,-22),make_float3(12,41,38));
 if(bounds.y<fmaxf(.002f,bounds.x)||bounds.x>limit)return hit;
 float fp=fmaxf(.002f,fmaxf(1,bounds.x)*cone);
 float rope=fmaxf(.045f,fp*.55f);
 float2 body=boxRay(ro,rd,make_float3(-7,-4,-21),make_float3(7,11.2f,30));
 float t=fmaxf(.002f,body.x),end=fminf(limit,body.y);
 if(t<end)for(int i=0;i<100;i++){
  float3 p=ro+rd*t;float d=shipBody(p,fp),epsilon=clampf(fp*.10f,.012f,.08f);
  if(d<epsilon){float e=.025f;float3 n=norm3(make_float3(shipBody(p+make_float3(e,0,0),fp)-shipBody(p-make_float3(e,0,0),fp),shipBody(p+make_float3(0,e,0),fp)-shipBody(p-make_float3(0,e,0),fp),shipBody(p+make_float3(0,0,e),fp)-shipBody(p-make_float3(0,0,e),fp)));
   hit.t=t;hit.nx=n.x;hit.ny=n.y;hit.nz=n.z;hit.part=1;break;}
  t+=fmaxf(.01f,d);if(t>end)break;
 }
 // Three independently bounded rigs. Thin secondary ropes are omitted when subpixel.
 for(int mast=0;mast<3;mast++){
  float z=(float)mast*11-11,top=mast==1?38:(mast==0?30:32);
  float2 rig=boxRay(ro,rd,make_float3(-11,3,z-7),make_float3(11,top+1,z+7));
  if(rig.y<fmaxf(.002f,rig.x)||rig.x>hit.t)continue;
  hit=shipCylinder(ro,rd,make_float3(0,3,z),make_float3(0,top,z),.32f,1,hit);
  for(int tier=0;tier<3;tier++){if(mast==0&&tier==2)continue;
   float y=top-4-(float)tier*8,w=(mast==0?3.7f:4.8f)+(float)tier*1.9f,h=6.2f;
   hit=shipCylinder(ro,rd,make_float3((-w-.3f)*.921061f,y,z+(w+.3f)*.389418f),make_float3((w+.3f)*.921061f,y,z-(w+.3f)*.389418f),.105f,1,hit);
   // Brace yards across the wind: the canvas has a full silhouette in a side view.
   float brace=.40f,cs=cosf(brace),sn=sinf(brace);float3 pr=ro-make_float3(0,0,z);
   pr=make_float3(cs*pr.x-sn*pr.z,pr.y,sn*pr.x+cs*pr.z);float3 dr=make_float3(cs*rd.x-sn*rd.z,rd.y,sn*rd.x+cs*rd.z);
   ShipHit cloth=shipSail(pr,dr,.15f,y,w,h,time,(float)mast*7+(float)tier,2,hit);
   if(cloth.t<hit.t){float nx=cs*cloth.nx+sn*cloth.nz,nz=-sn*cloth.nx+cs*cloth.nz;cloth.nx=nx;cloth.nz=nz;hit=cloth;}

  }
  for(int side=-1;side<=1;side+=2){
   hit=shipCylinder(ro,rd,make_float3((float)side*3.8f,4,z-3),make_float3(0,top-2,z),rope,3,hit);
   hit=shipCylinder(ro,rd,make_float3((float)side*3.8f,4,z+3),make_float3(0,top-2,z),rope,3,hit);
   if(fp<.18f)for(int shroud=1;shroud<4;shroud++){float dz=-3+1.5f*(float)shroud;hit=shipCylinder(ro,rd,make_float3((float)side*3.8f,4,z+dz),make_float3(0,top-2,z),rope,3,hit);}
   if(fp<.18f)for(int rung=1;rung<23;rung++){
    float v=(float)rung/24,y=lerpf(4,top-2,v),xx=(float)side*3.8f*(1-v),span=3*(1-v);
    hit=shipCylinder(ro,rd,make_float3(xx,y,z-span),make_float3(xx,y,z+span),fmaxf(.022f,fp*.55f),3,hit);
   }
  }
 }
 // Heavy, exposed stepped bowsprit and jibboom.
 hit=shipCylinder(ro,rd,make_float3(0,5.6f,14),make_float3(0,10.4f,28),.34f,1,hit);
 hit=shipCylinder(ro,rd,make_float3(0,9.8f,26),make_float3(0,12.5f,35),.19f,1,hit);
 hit=shipCylinder(ro,rd,make_float3(0,12.5f,35),make_float3(0,30,11),rope,3,hit);
 hit=shipCylinder(ro,rd,make_float3(0,1.2f,20),make_float3(0,10.4f,28),rope*1.2f,3,hit);
 for(int side=-1;side<=1;side+=2){hit=shipCylinder(ro,rd,make_float3((float)side*2.2f,5.5f,17),make_float3(0,12.5f,35),rope,3,hit);}
 for(int band=0;band<5;band++){float z=19+(float)band*1.5f,y=5.6f+(z-14)*4.8f/14;hit=shipCylinder(ro,rd,make_float3(0,y-.025f,z-.08f),make_float3(0,y+.025f,z+.08f),.39f,3,hit);}
 hit=shipCylinder(ro,rd,make_float3(0,36,0),make_float3(0,28,-11),rope,3,hit);
 // Open bowsprit and stays: no forward sheet or sprit topmast.
 // A dark pennant at the mainmast, with a procedural skull in the material.
 hit=shipSail(ro-make_float3(2.1f,0,0),rd,.15f,38.4f,2.0f,2.15f,time,7,4,hit);
 // Fighting tops and a carved golden figurehead beneath the projecting bow.
 for(int mast=0;mast<3;mast++){float z=(float)mast*11-11,y=mast==1?27.8f:(mast==0?21:22);
  hit=shipCylinder(ro,rd,make_float3(0,y-.15f,z),make_float3(0,y+.15f,z),1.1f,1,hit);
 }
 hit=shipCylinder(ro,rd,make_float3(0,5.2f,22),make_float3(0,7.3f,25),.38f,5,hit);
 hit=shipCylinder(ro,rd,make_float3(0,7.2f,25),make_float3(0,8.1f,25.3f),.48f,5,hit);
 for(int side=-1;side<=1;side+=2){hit=shipCylinder(ro,rd,make_float3(0,6.8f,24),make_float3((float)side*1.6f,7.6f,25.4f),.17f,5,hit);}

 if(fp<.22f)for(int side=-1;side<=1;side+=2)for(int gun=-3;gun<=3;gun++){
  float z=(float)gun*3.2f,beam=shipBeam(z);
  hit=shipCylinder(ro,rd,make_float3((float)side*(beam-.55f),1.35f,z),make_float3((float)side*(beam+.5f),1.35f,z),.18f,3,hit);
 }
 if(hit.part>0){float3 n=shipRotate(make_float3(hit.nx,hit.ny,hit.nz),time,-1,C);hit.nx=n.x;hit.ny=n.y;hit.nz=n.z;}
 return hit;
}
__device__ float3 shipShade(float3 world,float3 normal,float3 rd,float3 sun,float part,float fp,const int* O,float time,const float* C){
 float3 p=shipRotate(world-shipRoot(O,time,C),time,1,C),n=shipRotate(normal,time,1,C);
 float detail=weight(fp,4),grain=.87f+.13f*noise2(p.z*.75f,p.y*6+p.x*9)*detail;
 float seed=hash2(0,0,(unsigned int)O[2]+901u);
 float3 base=mix3(make_float3(.105f,.047f,.019f),make_float3(.18f,.077f,.026f),seed)*grain;
 if(part==1){
  float seam=1-smoothf(.025f,.07f,fabsf(fractf((n.y>.5f?p.x:p.y)*2.8f)-.5f));
  base=base*(1-.42f*seam*detail);
  if(n.y>.5f){float board=floorf(p.x*2.8f),joint=1-smoothf(.015f,.05f,fabsf(fractf(p.z*.17f+hash2((int)board,0,31u))-.5f));base=make_float3(.30f,.19f,.092f)*grain*(1-.38f*seam*detail)*(1-.25f*joint*detail);}
  if(p.y>3&&p.y<4.3f&&p.z>4.3f&&p.z<6.8f&&fabsf(p.x)>2.1f){base=make_float3(.23f,.105f,.035f)*grain;if(fabsf(p.y-3.2f)<.06f||fabsf(p.y-4)<.06f)base=make_float3(.04f,.045f,.04f);}
  if(p.y>shipDeck(p.z)&&p.y<11&&fabsf(n.y)<.5f)base=make_float3(.055f,.028f,.020f)*grain;
  if(p.z< -9&& (fabsf(p.y-7.55f)<.28f||fabsf(p.y-9.75f)<.25f))base=make_float3(.5f,.3f,.06f);
  float band=fabsf(p.y-2.3f);if(band<.13f||fabsf(p.y-shipDeck(p.z)-.82f)<.08f)base=make_float3(.43f,.29f,.08f);
  if(p.z< -9.4f&&((p.y>4.7f&&p.y<6.8f)||(p.y>8&&p.y<9.3f))){float cell=fractf((fabsf(n.z)>.5f?p.x:p.z)*.72f);base=make_float3(.46f,.30f,.07f);if(cell>.12f&&cell<.86f&&fabsf(p.y-5.05f)>.045f)base=make_float3(.022f,.07f,.078f);}
 }
 if(part==2){
  float stripe=fabsf(fractf(p.x*1.8f)-.5f),stitch=(1-smoothf(.02f,.055f,stripe))*detail;
  float wear=noise2(p.x*1.5f,p.y*1.2f);base=make_float3(.065f,.055f,.043f)*(.65f+.35f*wear)*(1-.25f*stitch);
 }
 if(part==2&&p.z>6&&p.y>5.7f&&p.y<12.1f){
  base=make_float3(.035f,.028f,.021f);float x=p.x/2.5f,y=(p.y-9.7f)/1.7f;
  float skull=sat((1-x*x-y*y)*10),eyes=smoothf(.14f,.24f,sqrtf((fabsf(x)-.38f)*(fabsf(x)-.38f)+(y-.05f)*(y-.05f)));
  float bones=1-smoothf(.08f,.15f,fminf(fabsf(y+1.1f-x*.5f),fabsf(y+1.1f+x*.5f)));base=mix3(base,make_float3(.72f,.63f,.43f),sat(skull*eyes+bones*sat(1.2f-fabsf(x))));
 }
 if(part==5)base=make_float3(.58f,.33f,.065f);
 if(part==3)base=make_float3(.025f,.022f,.016f);
 if(part==4){
  float x=(p.x-2.1f)/.8f,y=(p.y-37.3f)/.65f;
  float skull=sat((1-x*x-y*y)*12),eyes=smoothf(.16f,.25f,sqrtf((fabsf(x)-.38f)*(fabsf(x)-.38f)+(y-.05f)*(y-.05f)));
  float bones=1-smoothf(.10f,.18f,fminf(fabsf(y+.8f-x*.55f),fabsf(y+.8f+x*.55f)));
  base=mix3(make_float3(.018f,.015f,.012f),make_float3(.78f,.72f,.54f),sat(skull*eyes+bones*sat(1-fabsf(x))));
 }
 float occlusion=1;if(part==1){float3 localSun=shipRotate(sun,time,1,C);for(int i=1;i<=8;i++){float d=(float)i*.65f;if(shipBody(p+localSun*d+n*.08f,fp)<.02f){occlusion=.38f;break;}}}
 float diffuse=sat(dot3(normal,sun))*occlusion,ambient=.23f+.14f*sat(normal.y);
 float3 result=base*(make_float3(ambient*.78f,ambient*.89f,ambient)+sunRadiance(sun)*(diffuse*.42f));
 if(part==2)result=result+base*sunRadiance(sun)*(.10f*sat(-dot3(normal,sun)));
 return result;
}
