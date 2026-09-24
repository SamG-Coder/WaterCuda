import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WasmStartup,cpuWorkerCount} from '../src/wasm-startup.js';

test('CPU startup bounds in-flight frames, snapshots camera state, and releases threads on handover',async t=>{
 const messages=[];let worker,painted=0,frames=0;
 const previous=Object.fromEntries(['Worker','ImageData','innerWidth','innerHeight'].map(k=>[k,Object.getOwnPropertyDescriptor(globalThis,k)]));
 t.after(()=>{for(const [k,descriptor]of Object.entries(previous)){if(descriptor)Object.defineProperty(globalThis,k,descriptor);else delete globalThis[k];}});
 globalThis.innerWidth=1280;globalThis.innerHeight=720;
 globalThis.Worker=class{constructor(){worker=this;}postMessage(m){messages.push(m);}terminate(){this.stopped=true;}};
 globalThis.ImageData=class{constructor(data,w,h){this.data=data;this.width=w;this.height=h;}};
 const preview=new WasmStartup({getContext:()=>({putImageData:()=>painted++})},{onFrame:()=>frames++,onError:()=>assert.fail('unexpected error')});
 const camera=new Float32Array([1,2,3]),origin=new Int32Array([4,5,6]);
 preview.frame(camera,origin);assert.equal(messages.length,1,'do not submit before init');
 worker.onmessage({data:{type:'ready'}});preview.frame(camera,origin);preview.frame(camera,origin);
 assert.equal(messages.length,2,'only one frame in flight');camera[0]=9;assert.equal(messages[1].camera[0],1);
 worker.onmessage({data:{type:'frame',width:1,height:1,pixels:new Uint8Array(4).buffer,ms:10}});
 assert.equal(await preview.first,true);assert.equal(painted,1);assert.equal(frames,1);
 preview.frame(camera,origin);assert.equal(messages[2].camera[0],9,'latest controls feed next frame');
 preview.presenter={draw:()=>true,dispose:()=>{}};
 worker.onmessage({data:{type:'frame',width:1,height:1,pixels:new Uint8Array(4).buffer,ms:10}});
 assert.equal(painted,1,'active NIS must avoid redundant fallback painting');
 preview.stop();preview.frame(camera,origin);assert.equal(worker.stopped,true);assert.equal(messages.length,3);
 worker.onmessage({data:{type:'frame',width:1,height:1,pixels:new Uint8Array(4).buffer}});assert.equal(painted,1,'late CPU result cannot overwrite GPU');
});

test('CPU pool scales to eight workers while reserving two logical CPUs',()=>{
 assert.equal(cpuWorkerCount(32),8);assert.equal(cpuWorkerCount(10),8);assert.equal(cpuWorkerCount(8),6);assert.equal(cpuWorkerCount(4),2);assert.equal(cpuWorkerCount(2),1);assert.equal(cpuWorkerCount(undefined),2);
});
