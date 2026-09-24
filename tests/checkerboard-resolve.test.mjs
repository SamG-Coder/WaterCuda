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
import {projectHistory} from '../experiments/webshader-wasm/history-projection.js';
test('history projection matches camera rays and one-pixel camera translation',()=>{
 const w=8,h=6,n=w*h,d=new Float32Array(n),m=new Float32Array(n).fill(1),v=new Uint8Array(n).fill(1),idx=new Int32Array(n),dist=new Float32Array(n),c=new Float32Array(40);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const sx=(x+.5-w/2)/h*1.05,sy=-(y+.5-h/2)/h*1.05;d[y*w+x]=10*Math.sqrt(1+sx*sx+sy*sy);}
 projectHistory(c,c,d,m,v,w,h,idx,dist);for(let i=0;i<n;i++)assert.equal(idx[i],i);
 const next=c.slice();next[0]=10*1.05/h;projectHistory(c,next,d,m,v,w,h,idx,dist);
 for(let y=0;y<h;y++)for(let x=0;x<w-1;x++)assert.equal(idx[y*w+x],y*w+x+1);
 m.fill(2);projectHistory(c,next,d,m,v,w,h,idx,dist);assert.ok(idx.every(i=>i===-1));
});
test('reprojection accepts matching static geometry and rejects disoccluded depths',()=>{
 const f=fixture(),r=new CheckerboardResolve(),camera=new Float32Array(40);for(let b=1;b<f.hit.length;b+=4)f.hit[b]=1;
 r.resolve(f.p,f.hit,f.n,f.w,f.h,0,{reset:true,camera});
 r.resolve(f.p,f.hit,f.n,f.w,f.h,1,{moved:true,camera});assert.ok(r.reprojected>0);
 for(let b=0;b<f.hit.length;b+=4)f.hit[b]=30;
 r.resolve(f.p,f.hit,f.n,f.w,f.h,0,{moved:true,camera});assert.equal(r.reprojected,0);
});
