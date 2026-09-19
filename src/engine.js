import {GpuRuntime} from '../vendor/cuda-webshader/runtime/runtime.js';
import {KernelLoader} from './kernel-loader.js';
export class Engine{
 async init(canvas,progress){
  this.errors=[];this.runtime=await GpuRuntime.create({onError:e=>{this.errors.push(String(e.message||e));this.onError?.(e);}});
  this.device=this.runtime.device;this.canvas=canvas;this.context=canvas.getContext('webgpu');
  this.loader=new KernelLoader(this.runtime,event=>{if(event.type==='done')console.info('[WaterCuda pipeline]',event.entry,event.timing);progress(event.entry+' · '+event.message);});
  this.kernels={};await Promise.all(['generateShrubAtlas','mipShrubAtlas','cacheShrubs','cacheOceanSpectrum','advanceOceanSpectrum','oceanFft','packOcean','oceanMip','tracePrimary','traceVegetation','reflectOcean','shadeOcean'].map(async name=>{this.kernels[name]=await this.loader.load(name);}));
  this.camera=this.runtime.createBuffer(64,{label:'Camera and ocean controls'});
  this.origin=this.runtime.createBuffer(16,{label:'Integer world origin and seed'});
  this.shrubs=this.runtime.createBuffer(715428*4,{label:'Shrub habitat and generated foliage atlas'});
  this.cacheShrubCall=this.kernels.cacheShrubs.bind({C:this.camera,Origin:this.origin,Shrubs:this.shrubs});this.lastShrubState=null;
  this.runtime.batch().dispatch(this.kernels.generateShrubAtlas.bind({Shrubs:this.shrubs}),[16,16,8]).submit();
  for(let level=1;level<8;level++)this.runtime.batch().dispatch(this.kernels.mipShrubAtlas.bind({Shrubs:this.shrubs},{level}),[Math.ceil((128>>level)/8),Math.ceil((128>>level)/8),8]).submit();
  this.waves=this.runtime.createBuffer(87381*4*4*4,{label:'Four spectral cascades with mipmaps'});
  this.spectrum=this.runtime.createBuffer(256*256*4*8,{label:'Fourier spectrum'});this.fftPing=this.runtime.createBuffer(256*256*4*8,{label:'FFT intermediate'});
  this.initialSpectrum=this.runtime.createBuffer(256*256*4*16,{label:'Cached Gaussian Fourier coefficients'});
  this.cacheSpectrumCall=this.kernels.cacheOceanSpectrum.bind({Origin:this.origin,Initial:this.initialSpectrum});
  this.oceanCalls=this.makeOceanCalls(this.camera,this.origin,this.waves,this.spectrum,this.fftPing,this.initialSpectrum);
  this.lastSpectrumSeed=null;this.lastOceanState=null;this.spectrumBuilds=0;this.oceanUpdates=0;
  this.frames=0;this.elapsedMs=0;this.pending=0;this.timings=null;this.timingBusy=false;
  if(this.device.features.has('timestamp-query')){this.queries=this.device.createQuerySet({type:'timestamp',count:10});this.queryResolve=this.device.createBuffer({size:256,usage:GPUBufferUsage.QUERY_RESOLVE|GPUBufferUsage.COPY_SRC});this.queryRead=this.device.createBuffer({size:80,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});}
  return this;
 }
 async resize(width,height){
  if(this.width===width&&this.height===height)return;await this.runtime.idle();
  for(const name of ['pixels','hit','surface','reflection'])if(this[name])this.runtime.destroyBuffer(this[name]);
  this.width=width;this.height=height;this.canvas.width=width;this.canvas.height=height;
  this.pixels=this.runtime.createBuffer(width*height*4,{label:'CUDA output'});
  this.hit=this.runtime.createBuffer(width*height*16,{label:'Primary visibility'});this.surface=this.runtime.createBuffer(width*height*16,{label:'Normals and depth'});
  this.reflection=this.runtime.createBuffer(width*height*16,{label:'Per-pixel reflections'});
  this.context.configure({device:this.device,format:'rgba8unorm',usage:GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT,alphaMode:'opaque'});
  const buffers={C:this.camera,Origin:this.origin,Shrubs:this.shrubs,Waves:this.waves,Hit:this.hit,Surface:this.surface,Reflection:this.reflection,Pixels:this.pixels};this.calls={};
  for(const name of ['tracePrimary','traceVegetation','reflectOcean','shadeOcean']){const kernel=this.kernels[name];this.calls[name]=kernel.bind(Object.fromEntries(kernel.artifact.metadata.bindings.map(b=>[b.name,buffers[b.name]])),{width,height});}
 }
 makeOceanCalls(camera,origin,waves,spectrum,ping,initial=null){return [
  [initial?this.kernels.advanceOceanSpectrum.bind({C:camera,Initial:initial,Spectrum:spectrum}):this.kernels.seedOcean.bind({C:camera,Origin:origin,Spectrum:spectrum}),[32,32,4]],
  [this.kernels.oceanFft.bind({Input:spectrum,Output:ping},{axis:0}),[256,4]],
  [this.kernels.oceanFft.bind({Input:ping,Output:spectrum},{axis:1}),[256,4]],
  [this.kernels.packOcean.bind({Spatial:spectrum,Waves:waves}),[32,32,4]],
  ...Array.from({length:8},(_,i)=>{const level=i+1,n=256>>level;return [this.kernels.oceanMip.bind({Waves:waves},{level}),[Math.ceil(n/8),Math.ceil(n/8),4]];})
 ];}
 frame(camera,origin){
  if(this.pending>=2)return false;
  const start=performance.now();this.runtime.write(this.camera,camera);this.runtime.write(this.origin,origin);
  const shrubState=[Math.floor(camera[0]/6),Math.floor(camera[2]/6),origin[0],origin[1],origin[2]];
  if(!this.lastShrubState||shrubState.some((v,i)=>v!==this.lastShrubState[i])){this.runtime.batch().dispatch(this.cacheShrubCall,[8,8]).submit();this.lastShrubState=shrubState;}
  const timed=!!this.queries&&!this.timingBusy&&this.frames%30===0;
  const stages=[['spectrum',[]],['tracePrimary',[Math.ceil(this.width/8),Math.ceil(this.height/8)]],['traceVegetation',[Math.ceil(this.width/8),Math.ceil(this.height/8)]],['reflectOcean',[Math.ceil(this.width/8),Math.ceil(this.height/8)]],['shadeOcean',[Math.ceil(this.width/8),Math.ceil(this.height/8)]]];
  let batch=this.runtime.batch(timed?{timestampWrites:{querySet:this.queries,beginningOfPassWriteIndex:0,endOfPassWriteIndex:1}}:{});
  for(let i=0;i<stages.length;i++){if(i&&timed){batch.submit();batch=this.runtime.batch({timestampWrites:{querySet:this.queries,beginningOfPassWriteIndex:i*2,endOfPassWriteIndex:i*2+1}});}const [name,groups]=stages[i];if(i===0){if(this.lastSpectrumSeed!==origin[2]){batch.dispatch(this.cacheSpectrumCall,[32,32,4]);this.lastSpectrumSeed=origin[2];this.spectrumBuilds++;}
    const state=[camera[5],camera[6],origin[2]];if(!this.lastOceanState||state.some((v,i)=>v!==this.lastOceanState[i])){for(const [call,g] of this.oceanCalls)batch.dispatch(call,g);this.lastOceanState=state;this.oceanUpdates++;}}else {batch.dispatch(this.calls[name],groups);}}
  batch.endPass();
  batch.encoder.copyBufferToTexture({buffer:this.pixels.gpuBuffer,bytesPerRow:this.width*4,rowsPerImage:this.height},{texture:this.context.getCurrentTexture()},[this.width,this.height]);
  if(timed){this.timingBusy=true;batch.encoder.resolveQuerySet(this.queries,0,10,this.queryResolve,0);batch.encoder.copyBufferToBuffer(this.queryResolve,0,this.queryRead,0,80);}
  batch.submit();this.pending++;this.frames++;
  this.runtime.idle().then(()=>{this.pending--;this.elapsedMs=performance.now()-start;}).catch(e=>{this.pending--;this.onError?.(e);});
  if(timed)this.readTimings();return true;
 }
 async readTimings(){try{await this.queryRead.mapAsync(GPUMapMode.READ);const values=new BigUint64Array(this.queryRead.getMappedRange());this.timings=['Waves','Visibility','Foliage','Reflections','Shading'].map((name,i)=>({name,ms:Number(values[i*2+1]-values[i*2])/1e6}));this.queryRead.unmap();this.gpuMs=this.timings.reduce((sum,t)=>sum+t.ms,0);}catch{this.timings=null;}finally{this.timingBusy=false;}}
 async readPixels(){
  await this.runtime.idle();const words=await this.runtime.read(this.pixels,Uint32Array);
  return new Uint8Array(words.buffer,words.byteOffset,words.byteLength);
 }
 async capture(){
  const bytes=await this.readPixels();
  const c=document.createElement('canvas');c.width=this.width;c.height=this.height;
  c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(bytes),this.width,this.height),0,0);
  return new Promise(resolve=>c.toBlob(resolve,'image/png'));
 }
 async validate(){
  const kernel=await this.loader.load('probeWorld');this.kernels.seedOcean??=await this.loader.load('seedOcean');const rt=this.runtime;
  const points=rt.createBuffer(64),origin=rt.createBuffer(16),result=rt.createBuffer(64),waves=rt.createBuffer(87381*4*4*4),camera=rt.createBuffer(64),spectrum=rt.createBuffer(256*256*4*8),ping=rt.createBuffer(256*256*4*8);
  const initial=rt.createBuffer(256*256*4*16),shrubPatch=rt.createBuffer(16388*4);
  const c=new Float32Array(16);c[5]=3;c[6]=1;rt.write(camera,c);
  const data=new Float32Array([2400,2400,.2,0,4799.9,1000,.2,0,2000,2000,.2,0,2400,2400,128,0]);
  const invocation=kernel.bind({Points:points,Origin:origin,Waves:waves,Result:result},{count:4}),prepare=this.makeOceanCalls(camera,origin,waves,spectrum,ping);
  const cacheCall=this.kernels.cacheOceanSpectrum.bind({Origin:origin,Initial:initial}),cachedPrepare=this.makeOceanCalls(camera,origin,waves,spectrum,ping,initial);
  const run=async (p,o,cached=false)=>{rt.write(points,p);rt.write(origin,new Int32Array([...o,0]));const batch=rt.batch();if(cached)batch.dispatch(cacheCall,[32,32,4]);for(const [call,g]of cached?cachedPrepare:prepare)batch.dispatch(call,g);batch.dispatch(invocation,[1]).submit();await rt.idle();return rt.read(result);};
  try{
   const a=await run(data,[0,0,42]),b=await run(data,[0,0,42]),cached=await run(data,[0,0,42],true);
   const shifted=data.slice();for(let i=0;i<4;i++){shifted[i*4]-=4800;shifted[i*4+1]+=4800;}
   const c=await run(shifted,[1,-1,42]);const remote=await run(data,[100000000,-100000000,42]);
   const other=await run(data,[0,0,12345]);
   const fixtureResponse=await fetch(new URL('../tests/ocean-reference.json',import.meta.url),{cache:'no-cache'});if(!fixtureResponse.ok)throw Error('Native ocean reference fixture is missing. Run npm run test:native.');
   const native=await fixtureResponse.json();
   const shrubCall=this.kernels.cacheShrubs.bind({C:camera,Origin:origin,Shrubs:shrubPatch});
   const floraC=new Float32Array(16);floraC[0]=2810;floraC[2]=1130;
   const patch=async(o)=>{rt.write(camera,floraC);rt.write(origin,new Int32Array(o));rt.batch().dispatch(shrubCall,[8,8]).submit();await rt.idle();return rt.read(shrubPatch);};
   const flora=await patch([0,0,884,0]);floraC[0]-=4800;floraC[2]+=4800;const floraShift=await patch([1,-1,884,0]);
   let floraOk=flora.every(Number.isFinite)&&floraShift.every(Number.isFinite),plants=0;
   for(let i=4;i<flora.length;i+=4){floraOk&&=Math.abs(flora[i+3]-floraShift[i+3])<.0001;if(flora[i+3]>0){plants++;floraOk&&=Math.abs(flora[i]-floraShift[i]-4800)<.01&&Math.abs(flora[i+1]-floraShift[i+1])<.01&&Math.abs(flora[i+2]-floraShift[i+2]+4800)<.01;}}
   const atlas=await rt.read(this.shrubs);let atlasOk=true;
   for(let tile=0;tile<8;tile++){
    const base=16388+tile*21845*4;let coverage=0;
    for(let i=0;i<16384;i++)coverage+=atlas[base+i*4+3];
    const average=atlas[base+21844*4+3];
    atlasOk&&=Number.isFinite(average)&&average>.08&&average<.8&&Math.abs(coverage/16384-average)<.00001;
    atlasOk&&=atlas[base+(127*128)*4+3]<.01;
   }
   const checks=[
    ['Deterministic CUDA generation',a.every((v,i)=>v===b[i])],
    ['Cached GPU spectrum matches eager GPU generation',a.every((v,i)=>Math.abs(v-cached[i])<.0001)],
    ['Terrain survives floating-origin rebasing',[0,4,8,12].every(i=>Math.abs(a[i]-c[i])<.005)],
    ['Ocean phase survives floating-origin rebasing',[1,2,5,6,9,10].every(i=>Math.abs(a[i]-c[i])<.003)],
    ['Remote integer coordinates remain finite',remote.every(Number.isFinite)],
    ['Different seeds change the islands',[0,4,8,12].some(i=>Math.abs(a[i]-other[i])>.1)],
    ['Filtered waves retain unresolved slope energy',a[15]>a[3]],
    ['GPU FFT matches independent CPU transform',a.every((v,i)=>Math.abs(v-native[i])<(i%4===0?.02:.005))],
    ['Seeded shrub cache survives rebasing',floraOk&&plants>10],
    ['Generated foliage atlas preserves coverage and transparent borders',atlasOk],
    ['No WebGPU validation errors',this.errors.length===0]
   ];return {checks,samples:Array.from(a),rebased:Array.from(c),adapter:rt.describe()};
  }finally{for(const b of [points,origin,result,waves,camera,spectrum,ping,initial,shrubPatch])rt.destroyBuffer(b);}
 }
}
