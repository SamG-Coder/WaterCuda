import {CheckerboardResolve} from './checkerboard-resolve.js';
export {ThreadedProgram} from '../../vendor/cuda-webshader/wasm/runtime.js';
// Same dispatch sequence and caches as the production Engine. Every computation
// is a generated .cu kernel; this class only owns buffers and schedules work.
export class WasmWorld{
 constructor(program,width=160,height=90,progress=()=>{}){
  this.p=program;this.width=width;this.height=height;this.progress=progress;this.times={};this.phase=0;this.resolve=new CheckerboardResolve();this.capacity=Math.max(width*height,320*640);
  const sizes={C:160,Origin:16,Shrubs:11405990*4,Waves:(87381*4*4+65584)*4,Spectrum:256*256*4*8,Ping:256*256*4*8,Initial:256*256*4*16,Hit:width*height*16,Surface:width*height*16,Reflection:width*height*16,Pixels:width*height*4};
  for(const name of ['Hit','Surface','Reflection','Pixels'])sizes[name]=this.capacity*(name==='Pixels'?4:16);
  this.b=Object.fromEntries(Object.entries(sizes).map(([n,s])=>[n,program.alloc(s)]));
 }
 resize(width,height){if(!Number.isInteger(width)||!Number.isInteger(height)||width<1||height<1||width*height>1920*1080)throw Error('Invalid CPU render size');
  if(width*height>this.capacity){
   this.capacity=Math.min(1920*1080,Math.max(width*height,this.capacity*2));
   for(const name of ['Hit','Surface','Reflection','Pixels']){const old=this.b[name];this.b[name]=this.p.alloc(this.capacity*(name==='Pixels'?4:16));this.p.module._free(old.ptr);this.p.buffers.splice(this.p.buffers.indexOf(old),1);}
  }
  this.width=width;this.height=height;}
 run(name,groups,values={}){const t=performance.now();this.p.dispatch(name,groups,{...this.b,...values,width:this.width,height:this.height});this.times[name]=(this.times[name]||0)+performance.now()-t;}
 frame(input,Origin,checkerboard=false){
  const C=new Float32Array(40);C.set(input);
  const signature=[this.width,this.height,...Origin.slice(0,3),C[14],C[15]].join();
  const moved=this.previousView&&[0,1,2,3,4,16,17,18,19,20,21,22].some(i=>Math.abs(C[i]-this.previousView[i])>.00001);this.previousView=C.slice();
  const reset=this.historySignature!==signature;this.historySignature=signature;
  C[27]=checkerboard&&!reset?1+this.phase:0;
  const start=performance.now();this.times={};this.p.write(this.b.C,C);this.p.write(this.b.Origin,Origin);
  if(!this.atlas){this.progress('Generating foliage atlas');this.run('generateShrubAtlas',[16,16,8]);for(let level=1;level<8;level++)this.run('mipShrubAtlas',[Math.ceil((128>>level)/8),Math.ceil((128>>level)/8),8],{level});this.atlas=true;}
  const terrain=Array.from(Origin.slice(0,3)).join();
  if(terrain!==this.terrain){this.progress('Building terrain bounds');this.run('cacheTerrain',[64,64,9],{Terrain:this.b.Shrubs});for(let level=1;level<=9;level++)this.run('mipTerrain',[Math.ceil((512>>level)/8),Math.ceil((512>>level)/8),9],{Terrain:this.b.Shrubs,level});this.terrain=terrain;}
  const shrubs=[Math.floor(C[0]/6),Math.floor(C[2]/6),...Origin.slice(0,3)].join();if(shrubs!==this.shrubs){this.run('cacheShrubs',[8,8,1]);this.shrubs=shrubs;}
  const reef=[Math.floor(C[0]/12),Math.floor(C[2]/12),...Origin.slice(0,3)].join();if(((C[1]<0&&C[14]<.5)||(C[1]<8&&C[14]>=3))&&reef!==this.reef){this.progress('Building underwater reef');this.run('cacheReef',[128,128,1]);this.reef=reef;}
  if(this.seed!==Origin[2]){this.run('cacheOceanSpectrum',[32,32,4]);this.seed=Origin[2];}
  const ocean=[C[5],C[6],Origin[2],C[15]].join();if(ocean!==this.ocean){
   this.run('advanceOceanSpectrum',[32,32,4]);this.run('oceanFft',[256,4,1],{Input:this.b.Spectrum,Output:this.b.Ping,axis:0});this.run('oceanFft',[256,4,1],{Input:this.b.Ping,Output:this.b.Spectrum,axis:1});
   this.run('packOcean',[32,32,4],{Spatial:this.b.Spectrum});for(let level=1;level<=8;level++)this.run('oceanMip',[Math.ceil((256>>level)/8),Math.ceil((256>>level)/8),4],{level});this.ocean=ocean;
  }
  this.run('updateShip',[1,1,1]);if(C[14]>=3)this.run('stepShipWater',[16,16,1]);
  for(const k of ['tracePrimary','traceVegetation','reflectOcean','shadeOcean']){this.progress(k);
   if(k==='shadeOcean'&&checkerboard&&!reset){const a=this.p.module.HEAPF32,base=this.b.Reflection.ptr/4;for(let y=0;y<this.height;y++)for(let x=0;x<this.width;x++)if(((x+y)&1)!==this.phase)a[base+(y*this.width+x)*4+3]=-1;}
   this.run(k,[Math.ceil(this.width/8),Math.ceil(this.height/8),1]);}
  let resolved;
  if(checkerboard){
   const before=performance.now(),heap=this.p.module.HEAPU8.buffer,length=this.width*this.height*4;
   resolved=this.resolve.resolve(new Uint8Array(heap,this.b.Pixels.ptr,length),new Float32Array(heap,this.b.Hit.ptr,length),new Float32Array(heap,this.b.Surface.ptr,length),this.width,this.height,this.phase,{reset,moved,camera:new Float32Array(this.p.read(this.b.C).buffer)});
   this.times.checkerboardResolve=performance.now()-before;
  }
  const phase=this.phase;this.phase^=1;
  return {checkerboard,phase,historyReset:reset,shipPose:C[14]>=3?Array.from(new Float32Array(this.p.read(this.b.C).buffer)):null,pixels:resolved||this.p.read({...this.b.Pixels,bytes:this.width*this.height*4}),ms:performance.now()-start,timings:{...this.times},groups:this.p.groups()};
 }
}
