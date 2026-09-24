import {test} from 'node:test';import assert from 'node:assert/strict';
import {CpuResolution} from '../src/cpu-resolution.js';
test('adaptive CPU resolution ignores warmup, respects frame budget and bounds',()=>{
 const r=new CpuResolution();for(let i=0;i<3;i++)r.observe(1000);assert.equal(r.width,128);
 for(let i=0;i<27;i++)r.observe(40);assert.equal(r.width,160);
 for(let i=0;i<30;i++)r.observe(50);assert.equal(r.width,160);
 for(let i=0;i<300;i++)r.observe(200);assert.equal(r.width,96);
 for(let i=0;i<500;i++)r.observe(5);assert.ok(r.width>320);
 const size=r.size(100,1000);assert.equal(size.width,96);assert.equal(size.height,960);
 const wide=new CpuResolution();wide.size(1920,1080);for(let i=0;i<3000;i++)wide.observe(5);assert.equal(wide.width,1920);assert.ok(wide.size(1920,1080).width*wide.size(1920,1080).height<=1920*1080);
});
