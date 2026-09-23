import test from 'node:test';
import assert from 'node:assert/strict';
import {Engine} from '../src/engine.js';
import {SEA_LOOKS,applySeaLook} from '../src/sea-looks.js';

test('pixel export reads supported 32-bit words and preserves every RGBA byte',async()=>{
 const e=new Engine();e.pixels={};let idle=false;
 e.runtime={idle:async()=>{idle=true;},read:async(buffer,Type)=>{
  assert.equal(idle,true);assert.equal(buffer,e.pixels);assert.equal(Type,Uint32Array);
  return new Uint32Array([0xff332211,0xffccbbaa]);
 }};
 assert.deepEqual([...await e.readPixels()],[17,34,51,255,170,187,204,255]);
});

function fakeEngine(){
 const e=new Engine(),dispatches=[];
 const encoder={copyBufferToTexture(){}};
 e.runtime={write(){},idle:()=>Promise.resolve(),batch:()=>({encoder,dispatch(call){dispatches.push(call);return this;},endPass(){return this;},submit(){return this;}})};
 Object.assign(e,{context:{getCurrentTexture:()=>({})},pixels:{gpuBuffer:{}},pending:0,frames:0,width:64,height:32,cacheReefCall:'reef',lastReefState:null,cacheShrubCall:'shrubs',lastShrubState:null,cacheSpectrumCall:'cache',oceanCalls:[['advance',[]],['fft',[]]],calls:{tracePrimary:'trace',traceVegetation:'foliage',reflectOcean:'reflect',shadeOcean:'shade'},lastSpectrumSeed:null,lastOceanState:null,spectrumBuilds:0,oceanUpdates:0});
 return {e,dispatches};
}
test('seed coefficients cache once; camera motion and rebasing never reseed the ocean',async()=>{
 const {e,dispatches}=fakeEngine(),c=new Float32Array(16),o=new Int32Array([0,0,42,0]);c[5]=3;c[6]=1;
 e.frame(c,o);await e.runtime.idle();assert.deepEqual(dispatches,['shrubs','cache','advance','fft','trace','foliage','reflect','shade']);
 dispatches.length=0;c[0]+=50;o[0]=100000000;o[1]=-100000000;e.frame(c,o);await e.runtime.idle();
 assert.deepEqual(dispatches,['shrubs','trace','foliage','reflect','shade']);assert.equal(e.spectrumBuilds,1);assert.equal(e.oceanUpdates,1);
 c[5]=4;e.frame(c,o);await e.runtime.idle();assert.equal(e.spectrumBuilds,1);assert.equal(e.oceanUpdates,2);
 c[6]=2;e.frame(c,o);await e.runtime.idle();assert.equal(e.spectrumBuilds,1);assert.equal(e.oceanUpdates,3);
 o[2]=884;e.frame(c,o);await e.runtime.idle();assert.equal(e.spectrumBuilds,2);assert.equal(e.oceanUpdates,4);
});
test('backpressure does not mark a skipped spectrum or frame as generated',()=>{
 const {e,dispatches}=fakeEngine();e.pending=2;
 assert.equal(e.frame(new Float32Array(16),new Int32Array([0,0,42,0])),false);
 assert.equal(e.lastSpectrumSeed,null);assert.equal(e.frames,0);assert.deepEqual(dispatches,[]);
});

test('shrub habitat cache updates for patch, seed or origin changes, not wind or wave time',async()=>{
 const {e,dispatches}=fakeEngine(),c=new Float32Array(16),o=new Int32Array([0,0,884,0]);
 const frame=async()=>{dispatches.length=0;e.frame(c,o);await e.runtime.idle();return dispatches.includes('shrubs');};
 assert.equal(await frame(),true);c[5]=8;c[6]=2;c[0]=5;
 assert.equal(await frame(),false);c[0]=6;assert.equal(await frame(),true);
 o[0]=1;assert.equal(await frame(),true);o[2]=42;assert.equal(await frame(),true);
});
test('sea looks change only appearance uniforms and preserve camera/time/world controls',()=>{
 for(const name of Object.keys(SEA_LOOKS)){
  const camera=Float32Array.from({length:16},(_,i)=>i+.25),before=camera.slice();applySeaLook(camera,name);
  for(const i of [0,1,2,3,4,5,9,10,13,14,15])assert.equal(camera[i],before[i]);
  assert.ok(camera[6]>=.25&&camera[6]<=2.5);assert.ok(camera[12]>=.35&&camera[12]<=2.5);
 }
 assert.throws(()=>applySeaLook(new Float32Array(16),'missing'));
 assert.throws(()=>applySeaLook(new Float32Array(3),'coastal'));
});

test('reef cache follows underwater world patches, independent of wave time and lighting',async()=>{
 const {e,dispatches}=fakeEngine(),c=new Float32Array(16),o=new Int32Array([0,0,884,0]);
 const frame=async()=>{dispatches.length=0;e.frame(c,o);await e.runtime.idle();return dispatches.includes('reef');};
 assert.equal(await frame(),false);c[1]=-8;assert.equal(await frame(),true);
 c[5]=30;c[6]=2;c[8]=.4;c[0]=11;assert.equal(await frame(),false);
 c[0]=12;assert.equal(await frame(),true);o[2]=42;assert.equal(await frame(),true);
 o[0]=1;assert.equal(await frame(),true);c[1]=10;c[0]=120;assert.equal(await frame(),false);
 c[1]=-5;assert.equal(await frame(),true);
});

test('changing weather while paused updates wave metadata without rebuilding seed coefficients',async()=>{
 const {e,dispatches}=fakeEngine(),c=new Float32Array(16),o=new Int32Array([0,0,884,0]);
 e.frame(c,o);await e.runtime.idle();dispatches.length=0;c[15]=4;e.frame(c,o);await e.runtime.idle();
 assert.ok(dispatches.includes('advance'));assert.ok(!dispatches.includes('cache'));assert.equal(e.spectrumBuilds,1);
});
