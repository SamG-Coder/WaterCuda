// Frozen pre-optimization terrain evaluator (4dede01).
// Used to verify the shoreline early exit and descriptor reuse preserve geometry.
__device__ float referenceIslandHeight(float x,float z,Island a,float fp){
 if(a.peak==0)return -45;
 float px=(x-a.x)/a.radius,pz=(z-a.z)/a.radius;
 float u=(px*a.c+pz*a.s)*a.aspect,v=-px*a.s+pz*a.c;float r=sqrtf(u*u+v*v);
 if(r>=1)return -45;
 // Only the outer envelope scales with island radius. Interior landforms use
 // metres, so larger islands contain more hills instead of enlarged noise cells.
 float mx=x-a.x,mz=z-a.z;
 float broad=noise2(u*3.1f+a.seed,v*3.1f+a.seed);
 float coast=(noise2(mx/180+a.seed,mz/180)-.5f)*90/a.radius;
 float shape=sat(1-r+((broad-.5f)*.55f+coast)*smoothf(1,.6f,r));
 float warpX=(noise2(mx/650+a.seed,mz/650)-.5f)*150;
 float warpZ=(noise2(mx/650+31,mz/650+a.seed)-.5f)*150;
 float ridge=1-fabsf(noise2((mx+warpX)/310+a.seed,(mz+warpZ)/310)*2-1);
 float base=-45+powf(shape,1.7f)*(a.peak*(.48f+.52f*ridge)+45);
 float detail=0,w1=weight(fp,1.0f/95),w2=weight(fp,1.0f/31),w3=weight(fp,1.0f/9);
 if(w1>0)detail+=(noise2((mx+warpX)/95+a.seed,(mz+warpZ)/95)-.5f)*40*w1;
 if(w2>0)detail+=(noise2(mx/31+a.seed,mz/31)-.5f)*13*w2;
 if(w3>0)detail+=(noise2(mx/9+a.seed,mz/9)-.5f)*3*w3;
 // Preserve the submerged shelf and beach; break up inland silhouettes and normals.
 return base+detail*smoothf(2,32,base);

}
__device__ float referenceGround(float x,float z,const int* Origin,float fp){return referenceIslandHeight(x,z,describeIsland((int)floorf(x/CELL),(int)floorf(z/CELL),Origin),fp);}
__device__ float3 referenceGroundNormal(float3 p,const int* Origin,float fp){float e=fmaxf(0.4f,fp*0.7f);return norm3(make_float3(referenceGround(p.x-e,p.z,Origin,fp)-referenceGround(p.x+e,p.z,Origin,fp),2*e,referenceGround(p.x,p.z-e,Origin,fp)-referenceGround(p.x,p.z+e,Origin,fp)));}
