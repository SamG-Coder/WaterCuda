import {test} from 'node:test';
import assert from 'node:assert/strict';
import {CheckerboardResolve} from '../experiments/webshader-wasm/checkerboard-resolve.js';
function fixture(w=6,h=6){const p=new Uint8Array(w*h*4),hit=new Float32Array(p.length),n=new Float32Array(p.length);for(let b=0;b<p.length;b+=4){p.set([60,100,120,255],b);hit[b]=10;hit[b+1]=2;n[b+1]=1;}return {p,hit,n,w,h};}
test('resolve removes stale bright checkerboard water without modifying raw samples',()=>{
 const f=fixture(),r=new CheckerboardResolve();r.resolve(f.p,f.hit,f.n,f.w,f.h,0,{reset:true});
 for(let y=0;y<f.h;y++)for(let x=0;x<f.w;x++)if((x+y)&1)f.p.set([255,255,255,255],(y*f.w+x)*4);
 const raw=f.p.slice(),out=r.resolve(f.p,f.hit,f.n,f.w,f.h,0);
 assert.deepEqual(f.p,raw);for(let b=0;b<out.length;b+=4){assert.ok(out[b]<80);assert.equal(out[b+3],255);}
});
test('resolve preserves material edges and rejects history on motion and resize',()=>{
 const f=fixture(),r=new CheckerboardResolve();for(let y=0;y<f.h;y++)for(let x=3;x<f.w;x++){const b=(y*f.w+x)*4;f.p.set([210,170,100,255],b);f.hit[b+1]=1;f.hit[b]=1;}
 r.resolve(f.p,f.hit,f.n,f.w,f.h,0,{reset:true});const out=r.resolve(f.p,f.hit,f.n,f.w,f.h,1);
 assert.ok(out[(2*f.w+2)*4]<80);assert.ok(out[(2*f.w+3)*4]>190);
 f.p.fill(0);for(let b=3;b<f.p.length;b+=4)f.p[b]=255;const moved=r.resolve(f.p,f.hit,f.n,f.w,f.h,0,{moved:true});assert.equal(moved[0],0);
 const small=fixture(1,1);assert.deepEqual(r.resolve(small.p,small.hit,small.n,1,1,0),small.p);
});
