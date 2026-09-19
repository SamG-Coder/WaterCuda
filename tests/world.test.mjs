import test from 'node:test';
import assert from 'node:assert/strict';
import {rebase,parseSeed,renderSize} from '../src/world.js';
test('rebasing preserves world position across positive and negative boundaries',()=>{
 for(const [x,z] of [[4801,-1],[-4800,3600],[100000,-99999],[0,4799.5]]){
  const camera=new Float32Array([x,200,z]),origin=new Int32Array([1234,-999,42]);
  const before=[origin[0]*4800+camera[0],origin[1]*4800+camera[2]];
  rebase(camera,origin);
  assert.deepEqual([origin[0]*4800+camera[0],origin[1]*4800+camera[2]],before);
  assert.ok(camera[0]>=0&&camera[0]<4800&&camera[2]>=0&&camera[2]<4800);assert.equal(origin[2],42);
 }
});
test('rebasing at a distant origin does not lose local precision',()=>{
 const camera=new Float32Array([4800.25,5,-.25]),origin=new Int32Array([100000000,-100000000,42]);
 rebase(camera,origin);assert.equal(camera[0],.25);assert.equal(camera[2],4799.75);assert.equal(origin[0],100000001);assert.equal(origin[1],-100000001);
});
test('seed validation rejects fractions and out-of-range identity',()=>{
 assert.equal(parseSeed('42'),42);for(const value of [-1,1.5,NaN,Infinity,2147483648,'hello'])assert.throws(()=>parseSeed(value));
});
test('render targets always meet WebGPU copy alignment including portrait',()=>{
 for(const [vw,vh] of [[1920,1080],[390,844],[3440,1440],[200,300]])for(const target of [640,960,1280,1600]){
  const {width,height}=renderSize(vw,vh,target);assert.equal(width*4%256,0);assert.equal(height%8,0);assert.ok(width>=320&&height>=192);
 }
});
