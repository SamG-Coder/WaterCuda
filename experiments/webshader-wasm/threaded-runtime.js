export {ThreadedProgram} from '../../vendor/cuda-webshader/wasm/runtime.js';
// Same dispatch sequence and caches as the production Engine. Every computation
// is a generated .cu kernel; this class only owns buffers and schedules work.
export class WasmWorld{
 constructor(program,width=160,height=90,progress=()=>{}){
  this.p=program;this.width=width;this.height=height;this.progress=progress;this.times={};this.capacity=Math.max(width*height,320*640);
  const sizes={C:160,Origin:16,Shrubs:11405990*4,Waves:(87381*4*4+65584)*4,Spectrum:256*256*4*8,Ping:256*256*4*8,Initial:256*256*4*16,Hit:width*height*16,Surface:width*height*16,Reflection:width*height*16,Pixels:width*height*4};
  for(const name of ['Hit','Surface','Reflection','Pixels'])sizes[name]=this.capacity*(name==='Pixels'?4:16);
  this.b=Object.fromEntries(Object.entries(sizes).map(([n,s])=>[n,program.alloc(s)]));
 }
 resize(width,height){if(!Number.isInteger(width)||!Number.isInteger(height)||width<1||height<1||width*height>this.capacity)throw Error('Invalid CPU render size');this.width=width;this.height=height;}
 run(name,groups,values={}){const t=performance.now();this.p.dispatch(name,groups,{...this.b,...values,width:this.width,height:this.height});this.times[name]=(this.times[name]||0)+performance.now()-t;}
 frame(C,Origin){
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
  for(const k of ['tracePrimary','traceVegetation','reflectOcean','shadeOcean']){this.progress(k);this.run(k,[Math.ceil(this.width/8),Math.ceil(this.height/8),1]);}
  return {shipPose:C[14]>=3?Array.from(new Float32Array(this.p.read(this.b.C).buffer)):null,pixels:this.p.read({...this.b.Pixels,bytes:this.width*this.height*4}),ms:performance.now()-start,timings:{...this.times},groups:this.p.groups()};
 }
}
