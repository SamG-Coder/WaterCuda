import test from 'node:test';
import assert from 'node:assert/strict';
import {flightVector,moveCamera,isEditing} from '../src/flight.js';
test('forward flight follows both yaw and pitch',()=>{
 const v=flightVector(Math.PI/2,Math.PI/4,1,0,0);
 assert.ok(Math.abs(v[0]-Math.SQRT1_2)<1e-9);assert.ok(Math.abs(v[1]-Math.SQRT1_2)<1e-9);assert.ok(Math.abs(v[2])<1e-9);
 assert.ok(flightVector(0,-.5,1,0,0)[1]<0);
});
test('diagonal and combined vertical flight preserve the selected travel speed',()=>{
 for(const pitch of [-1,.0,1])for(const forward of [-1,0,1])for(const side of [-1,0,1])for(const up of [-1,0,1])assert.ok(Math.hypot(...flightVector(.7,pitch,forward,side,up))<=1+1e-10);
});
test('button focus allows flight but text and range inputs retain editing',()=>{
 assert.equal(isEditing({tagName:'BUTTON'}),false);assert.equal(isEditing({tagName:'CANVAS'}),false);
 for(const tagName of ['INPUT','TEXTAREA','SELECT'])assert.equal(isEditing({tagName}),true);
 assert.equal(isEditing({tagName:'DIV',isContentEditable:true}),true);
});
test('movement is stable across frame rates and origin boundaries',()=>{
 function fly(fps){const c=new Float32Array([4795,100,4795,.6,.3,0,1]),o=new Int32Array([0,0,42]);for(let i=0;i<fps;i++)moveCamera(c,o,new Set(['KeyW','KeyD']),1/fps,100);return [c[0]+o[0]*4800,c[1],c[2]+o[1]*4800];}
 const a=fly(30),b=fly(144);for(let i=0;i<3;i++)assert.ok(Math.abs(a[i]-b[i])<.025);
});
test('both shift keys boost and releasing keys stops immediately',()=>{
 const c=new Float32Array([0,100,0,0,0,0,1]),o=new Int32Array(4);moveCamera(c,o,new Set(['KeyW','ShiftRight']),1,10);assert.equal(c[2],50);
 const snapshot=Array.from(c);moveCamera(c,o,new Set(),1,10);assert.deepEqual(Array.from(c),snapshot);
});
