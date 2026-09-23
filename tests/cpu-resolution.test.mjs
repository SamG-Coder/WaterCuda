import {test} from 'node:test';import assert from 'node:assert/strict';
import {CpuResolution} from '../src/cpu-resolution.js';
test('adaptive CPU resolution ignores warmup, respects frame budget and bounds',()=>{
 const r=new CpuResolution();for(let i=0;i<3;i++)r.observe(1000);assert.equal(r.width,128);
 for(let i=0;i<27;i++)r.observe(20);assert.equal(r.width,160);
 for(let i=0;i<30;i++)r.observe(45);assert.equal(r.width,160);
 for(let i=0;i<300;i++)r.observe(200);assert.equal(r.width,96);
 for(let i=0;i<500;i++)r.observe(5);assert.equal(r.width,320);
 assert.deepEqual(r.size(100,1000),{width:320,height:640});
});
