import test from 'node:test';
import assert from 'node:assert/strict';
import {flightVector,moveCamera,isEditing,toggleHelm} from '../src/flight.js';
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

test('ship accelerates smoothly, orbit is independent, steering turns gradually and release coasts',()=>{
 const c=new Float32Array(40),o=new Int32Array(4);c[14]=3;c[16]=c[18]=650;c[23]=100;c[4]=-.18;
 moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.ok(c[24]>0&&c[24]<1);assert.equal(c[17],0);
 for(let i=0;i<60;i++)moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.ok(c[24]>20);
 const heading=c[19];c[3]=2;c[4]=-.8;moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.equal(c[19],heading);assert.equal(c[25],0);assert.equal(c[23],100);
 c[34]=1;c[32]=1;c[33]=.3;moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.ok(c[19]>0&&c[19]<.02);assert.ok(c[25]>0&&c[25]<.03);
 const velocity=c[24];moveCamera(c,o,new Set(),1/60,25);assert.ok(c[24]>0&&c[24]<velocity);
});
test('underwater ship drag slows forward motion and V preserves parked ship while free flying',()=>{
 const a=new Float32Array(40),b=new Float32Array(40),oa=new Int32Array(4),ob=new Int32Array(4);for(const c of [a,b]){c[14]=3;c[16]=650;c[18]=650;c[23]=64;}a[17]=20;b[17]=-20;
 moveCamera(a,oa,new Set(['KeyW']),1,40);moveCamera(b,ob,new Set(['KeyW']),1,40);assert.ok(a[24]>b[24]*3);
 const ship=b.slice(16,19);toggleHelm(b);assert.equal(b[14],4);moveCamera(b,ob,new Set(['KeyW']),.1,40);assert.deepEqual(b.slice(16,19),ship);toggleHelm(b);assert.equal(b[14],3);
});

test('neutral W and tiny mouse noise do not create lift',()=>{
 for(const pitch of [0,.02,-.02]){const c=new Float32Array(40),o=new Int32Array(4);c[14]=3;c[16]=c[18]=650;c[23]=64;c[33]=pitch;for(let i=0;i<120;i++)moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.equal(c[17],0);assert.equal(c[25],0);}
});

test('released steering restores surface trim while W continues forward',()=>{
 const c=new Float32Array(40),o=new Int32Array(4);c[14]=3;c[23]=100;c[17]=-.5;c[25]=c[33]=-.6;c[24]=25;
 for(let i=0;i<180;i++){const depth=c[17];moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.ok(c[17]>=depth);}
 assert.ok(Math.abs(c[17])<.001);assert.ok(Math.abs(c[25])<.001);assert.equal(c[33],0);assert.ok(c[18]>60);
 c[34]=1;c[33]=-.6;for(let i=0;i<30;i++)moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.ok(c[17]<-1);
 c[34]=0;c[17]=-10;c[25]=c[33]=-.4;moveCamera(c,o,new Set(['KeyW']),1/60,25);assert.ok(c[17]<-10);
});
