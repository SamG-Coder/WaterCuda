import test from 'node:test';
import assert from 'node:assert/strict';
import {Engine} from '../src/engine.js';
import {SEA_LOOKS,applySeaLook} from '../src/sea-looks.js';

function fakeEngine(){
 const e=new Engine(),dispatches=[];
 const encoder={copyBufferToTexture(){}};
 e.runtime={write(){},idle:()=>Promise.resolve(),batch:()=>({encoder,dispatch(call){dispatches.push(call);return this;},endPass(){return this;},submit(){return this;}})};
 Object.assign(e,{context:{getCurrentTexture:()=>({})},pixels:{gpuBuffer:{}},pending:0,frames:0,width:64,height:32,cacheSpectrumCall:'cache',oceanCalls:[['advance',[]],['fft',[]]],calls:{tracePrimary:'trace',reflectOcean:'reflect',shadeOcean:'shade'},lastSpectrumSeed:null,lastOceanState:null,spectrumBuilds:0,oceanUpdates:0});
 return {e,dispatches};
}
test('seed coefficients cache once; camera motion and rebasing never reseed the ocean',async()=>{
 const {e,dispatches}=fakeEngine(),c=new Float32Array(16),o=new Int32Array([0,0,42,0]);c[5]=3;c[6]=1;
 e.frame(c,o);await e.runtime.idle();assert.deepEqual(dispatches,['cache','advance','fft','trace','reflect','shade']);
 dispatches.length=0;c[0]+=50;o[0]=100000000;o[1]=-100000000;e.frame(c,o);await e.runtime.idle();
 assert.deepEqual(dispatches,['trace','reflect','shade']);assert.equal(e.spectrumBuilds,1);assert.equal(e.oceanUpdates,1);
 c[5]=4;e.frame(c,o);await e.runtime.idle();assert.equal(e.spectrumBuilds,1);assert.equal(e.oceanUpdates,2);
 c[6]=2;e.frame(c,o);await e.runtime.idle();assert.equal(e.spectrumBuilds,1);assert.equal(e.oceanUpdates,3);
 o[2]=884;e.frame(c,o);await e.runtime.idle();assert.equal(e.spectrumBuilds,2);assert.equal(e.oceanUpdates,4);
});
test('backpressure does not mark a skipped spectrum or frame as generated',()=>{
 const {e,dispatches}=fakeEngine();e.pending=2;
 assert.equal(e.frame(new Float32Array(16),new Int32Array([0,0,42,0])),false);
 assert.equal(e.lastSpectrumSeed,null);assert.equal(e.frames,0);assert.deepEqual(dispatches,[]);
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
