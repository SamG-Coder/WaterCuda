import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import create from './generated/world.mjs';import {ThreadedProgram,WasmWorld} from './threaded-runtime.js';
const abi=JSON.parse(await readFile(new URL('./generated/world.abi.json',import.meta.url),'utf8'));
const module=await create({wasmBinary:await readFile(new URL('./generated/world.wasm',import.meta.url))});
const threads=Number(process.argv[2]||4),p=new ThreadedProgram(module,abi,threads);
try{
 assert.equal(abi.kernels.length,19);assert.ok(abi.kernels.find(k=>k.entry==='oceanFft').cooperative);
 const Input=p.alloc(256*256*4*8),Output=p.alloc(Input.bytes),Back=p.alloc(Input.bytes),data=new Float32Array(Input.bytes/4);
 // An origin impulse has a constant 2D inverse transform, with a different
 // amplitude per layer. This exercises every FFT barrier and both axes.
 for(let layer=0;layer<4;layer++)data[layer*65536*2]=layer+1;
 p.write(Input,data);p.dispatch('oceanFft',[256,4,1],{Input,Output,axis:0});p.dispatch('oceanFft',[256,4,1],{Input:Output,Output:Back,axis:1});
 const fft=new Float32Array(p.read(Back).buffer);for(let layer=0;layer<4;layer++)for(let i=0;i<65536;i++){assert.ok(Math.abs(fft[(layer*65536+i)*2]-(layer+1))<1e-5);assert.ok(Math.abs(fft[(layer*65536+i)*2+1])<1e-5);}
 if(threads>1)assert.ok(p.groups().filter(n=>n>0).length>1,'FFT must actually execute on multiple workers');console.log('FFT barrier/2D impulse PASS; workgroups per thread:',p.groups());
 const world=new WasmWorld(p,64,36,s=>console.log('Stage:',s));const C=new Float32Array([1850,25,1250,.15,-.30,3,1,-.7,22,1,0,1,1.5,1,0,0]),Origin=new Int32Array([0,0,884,0]);
 let result=world.frame(C,Origin);console.log('Cold full pipeline:',result.ms.toFixed(1),'ms',result.timings);const first=result.pixels;
 assert.ok(new Set(new Uint32Array(first.buffer)).size>200);result=world.frame(C,Origin);assert.deepEqual(result.pixels,first);console.log('Cached full pipeline:',result.ms.toFixed(1),'ms');
 C[5]=4;assert.notDeepEqual(world.frame(C,Origin).pixels,first);
 const buffers=p.buffers.length;world.resize(160,90);result=world.frame(C,Origin);assert.equal(result.pixels.length,160*90*4);
 assert.equal(p.buffers.length,buffers);assert.equal(result.timings.cacheTerrain,undefined);assert.equal(result.timings.generateShrubAtlas,undefined);
 world.resize(64,36);C[5]=3;assert.deepEqual(world.frame(C,Origin).pixels,first);C[5]=4;
 assert.throws(()=>world.resize(10000,10000));console.log('Adaptive resize preserves caches, allocations and exact pixels PASS');
 // Run shared native fixture through generated probe kernel and compare outputs.
 const fixture=JSON.parse(await readFile(new URL('../../tests/ocean-reference.json',import.meta.url),'utf8'));
 const Points=p.alloc(64),Result=p.alloc(64),controls=C.slice(),fixtureOrigin=new Int32Array([0,0,42,0]);controls[5]=3;controls[15]=-1;
 p.write(Points,new Float32Array([2400,2400,.2,0,4799.9,1000,.2,0,2000,2000,.2,0,2400,2400,128,0]));
 p.write(world.b.C,controls);p.write(world.b.Origin,fixtureOrigin);
 world.run('seedOcean',[32,32,4]);world.run('oceanFft',[256,4,1],{Input:world.b.Spectrum,Output:world.b.Ping,axis:0});world.run('oceanFft',[256,4,1],{Input:world.b.Ping,Output:world.b.Spectrum,axis:1});world.run('packOcean',[32,32,4],{Spatial:world.b.Spectrum});for(let level=1;level<=8;level++)world.run('oceanMip',[Math.ceil((256>>level)/8),Math.ceil((256>>level)/8),4],{level});
 world.run('probeWorld',[1,1,1],{Points,Result,count:4});const measured=new Float32Array(p.read(Result).buffer);
 measured.forEach((v,i)=>assert.ok(Math.abs(v-fixture[i])<(i%4===0?.002:.0001),`Native fixture ${i}: ${v} vs ${fixture[i]}`));console.log('Independent native terrain/FFT fixture PASS');world.ocean=null;
 // Underwater and specimen modes exercise reef caching and coral/shrub tracing.
 C.set([4377,-7,2784,0,-.12]);result=world.frame(C,Origin);assert.ok(result.pixels.some(x=>x>0));assert.ok(result.timings.cacheReef>0);console.log('Underwater full pipeline:',result.ms.toFixed(1),'ms');
 C[14]=1;assert.notDeepEqual(world.frame(C,Origin).pixels,result.pixels);
 C.set([682,16,612,-.70,-.035]);C[14]=0;C[15]=1;result=world.frame(C,Origin);
 const shipHits=new Float32Array(p.read(world.b.Hit).buffer);let visibleShip=0;for(let i=1;i<64*36*4;i+=4)if(shipHits[i]===9)visibleShip++;assert.ok(visibleShip>50,'Ship must be visible through the full WASM pipeline');console.log('Procedural ship WASM hits:',visibleShip);
 const helm=new Float32Array(32);helm.set(C);helm[14]=3;helm.set([650,0,650,0,0,0,0,64],16);helm[3]=-.6;helm[4]=-.25;
 world.frame(helm,Origin);const afloat=new Float32Array(p.read(world.b.C).buffer);assert.ok(afloat[1]>20);assert.ok(Math.abs(afloat[22])<10);
 helm[17]=50;world.frame(helm,Origin);const air=new Float32Array(p.read(world.b.C).buffer);assert.equal(air[22],50);assert.ok(Math.abs(air[20])<1e-6);assert.ok(Math.abs(air[21])<1e-6);console.log('WASM helm buoyancy and flight PASS');
 console.log('PASS all 19 kernels compiled; FFT, full renderer determinism, animation, underwater reef and coral specimen executed.');
 p.dispose();process.exit(0);
}catch(e){console.error(e);p.dispose();process.exit(1);}
