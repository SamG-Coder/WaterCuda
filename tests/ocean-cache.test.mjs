import test from 'node:test';
import assert from 'node:assert/strict';
import {Engine} from '../src/engine.js';

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
