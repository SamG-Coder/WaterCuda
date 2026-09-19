import {GpuRuntime} from '../vendor/cuda-webshader/runtime/runtime.js';
import {KernelLoader} from './kernel-loader.js';
export class Engine{
 async init(canvas,progress){
  this.errors=[];this.runtime=await GpuRuntime.create({onError:e=>{this.errors.push(String(e.message||e));this.onError?.(e);}});
  this.device=this.runtime.device;this.canvas=canvas;this.context=canvas.getContext('webgpu');
  this.loader=new KernelLoader(this.runtime,event=>progress(event.message));
  this.kernels={};for(const name of ['cacheOceanSpectrum','advanceOceanSpectrum','oceanFft','packOcean','oceanMip','tracePrimary','reflectOcean','shadeOcean'])this.kernels[name]=await this.loader.load(name);
  this.camera=this.runtime.createBuffer(64,{label:'Camera and ocean controls'});
  this.origin=this.runtime.createBuffer(16,{label:'Integer world origin and seed'});
  this.waves=this.runtime.createBuffer(87381*4*4*4,{label:'Four spectral cascades with mipmaps'});
  this.spectrum=this.runtime.createBuffer(256*256*4*8,{label:'Fourier spectrum'});this.fftPing=this.runtime.createBuffer(256*256*4*8,{label:'FFT intermediate'});
  this.initialSpectrum=this.runtime.createBuffer(256*256*4*16,{label:'Cached Gaussian Fourier coefficients'});
  this.cacheSpectrumCall=this.kernels.cacheOceanSpectrum.bind({Origin:this.origin,Initial:this.initialSpectrum});
  this.oceanCalls=this.makeOceanCalls(this.camera,this.origin,this.waves,this.spectrum,this.fftPing,this.initialSpectrum);
  this.lastSpectrumSeed=null;this.lastOceanState=null;this.spectrumBuilds=0;this.oceanUpdates=0;
  this.frames=0;this.elapsedMs=0;this.pending=0;this.timings=null;this.timingBusy=false;
  if(this.device.features.has('timestamp-query')){this.queries=this.device.createQuerySet({type:'timestamp',count:8});this.queryResolve=this.device.createBuffer({size:256,usage:GPUBufferUsage.QUERY_RESOLVE|GPUBufferUsage.COPY_SRC});this.queryRead=this.device.createBuffer({size:64,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});}
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
  const buffers={C:this.camera,Origin:this.origin,Waves:this.waves,Hit:this.hit,Surface:this.surface,Reflection:this.reflection,Pixels:this.pixels};this.calls={};
  for(const name of ['tracePrimary','reflectOcean','shadeOcean']){const kernel=this.kernels[name];this.calls[name]=kernel.bind(Object.fromEntries(kernel.artifact.metadata.bindings.map(b=>[b.name,buffers[b.name]])),{width,height});}
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
  const timed=!!this.queries&&!this.timingBusy&&this.frames%30===0;
  const stages=[['spectrum',[]],['tracePrimary',[Math.ceil(this.width/8),Math.ceil(this.height/8)]],['reflectOcean',[Math.ceil(this.width/8),Math.ceil(this.height/8)]],['shadeOcean',[Math.ceil(this.width/8),Math.ceil(this.height/8)]]];
  let batch=this.runtime.batch(timed?{timestampWrites:{querySet:this.queries,beginningOfPassWriteIndex:0,endOfPassWriteIndex:1}}:{});
  for(let i=0;i<stages.length;i++){if(i&&timed){batch.submit();batch=this.runtime.batch({timestampWrites:{querySet:this.queries,beginningOfPassWriteIndex:i*2,endOfPassWriteIndex:i*2+1}});}const [name,groups]=stages[i];if(i===0){if(this.lastSpectrumSeed!==origin[2]){batch.dispatch(this.cacheSpectrumCall,[32,32,4]);this.lastSpectrumSeed=origin[2];this.spectrumBuilds++;}
    const state=[camera[5],camera[6],origin[2]];if(!this.lastOceanState||state.some((v,i)=>v!==this.lastOceanState[i])){for(const [call,g] of this.oceanCalls)batch.dispatch(call,g);this.lastOceanState=state;this.oceanUpdates++;}}else batch.dispatch(this.calls[name],groups);}
  batch.endPass();
  batch.encoder.copyBufferToTexture({buffer:this.pixels.gpuBuffer,bytesPerRow:this.width*4,rowsPerImage:this.height},{texture:this.context.getCurrentTexture()},[this.width,this.height]);
  if(timed){this.timingBusy=true;batch.encoder.resolveQuerySet(this.queries,0,8,this.queryResolve,0);batch.encoder.copyBufferToBuffer(this.queryResolve,0,this.queryRead,0,64);}
  batch.submit();this.pending++;this.frames++;
  this.runtime.idle().then(()=>{this.pending--;this.elapsedMs=performance.now()-start;}).catch(e=>{this.pending--;this.onError?.(e);});
  if(timed)this.readTimings();return true;
 }
 async readTimings(){try{await this.queryRead.mapAsync(GPUMapMode.READ);const values=new BigUint64Array(this.queryRead.getMappedRange());this.timings=['Waves','Visibility','Reflections','Shading'].map((name,i)=>({name,ms:Number(values[i*2+1]-values[i*2])/1e6}));this.queryRead.unmap();this.gpuMs=this.timings.reduce((sum,t)=>sum+t.ms,0);}catch{this.timings=null;}finally{this.timingBusy=false;}}
 async capture(){
  await this.runtime.idle();const bytes=await this.runtime.read(this.pixels,Uint8Array);
  const c=document.createElement('canvas');c.width=this.width;c.height=this.height;
  c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(bytes),this.width,this.height),0,0);
  return new Promise(resolve=>c.toBlob(resolve,'image/png'));
 }
 async validate(){
  const kernel=await this.loader.load('probeWorld');this.kernels.seedOcean??=await this.loader.load('seedOcean');const rt=this.runtime;
  const points=rt.createBuffer(64),origin=rt.createBuffer(16),result=rt.createBuffer(64),waves=rt.createBuffer(87381*4*4*4),camera=rt.createBuffer(64),spectrum=rt.createBuffer(256*256*4*8),ping=rt.createBuffer(256*256*4*8);
  const initial=rt.createBuffer(256*256*4*16);
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
   const checks=[
    ['Deterministic CUDA generation',a.every((v,i)=>v===b[i])],
    ['Cached GPU spectrum matches eager GPU generation',a.every((v,i)=>Math.abs(v-cached[i])<.0001)],
    ['Terrain survives floating-origin rebasing',[0,4,8,12].every(i=>Math.abs(a[i]-c[i])<.005)],
    ['Ocean phase survives floating-origin rebasing',[1,2,5,6,9,10].every(i=>Math.abs(a[i]-c[i])<.003)],
    ['Remote integer coordinates remain finite',remote.every(Number.isFinite)],
    ['Different seeds change the islands',[0,4,8,12].some(i=>Math.abs(a[i]-other[i])>.1)],
    ['Filtered waves retain unresolved slope energy',a[15]>a[3]],
    ['GPU FFT matches independent CPU transform',a.every((v,i)=>Math.abs(v-native[i])<(i%4===0?.02:.005))],
    ['No WebGPU validation errors',this.errors.length===0]
   ];return {checks,samples:Array.from(a),rebased:Array.from(c),adapter:rt.describe()};
  }finally{for(const b of [points,origin,result,waves,camera,spectrum,ping,initial])rt.destroyBuffer(b);}
 }
}
