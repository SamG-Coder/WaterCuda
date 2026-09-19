import fs from 'node:fs/promises';import {createHash} from 'node:crypto';
import {compile} from '../vendor/cuda-webshader/compiler/compiler.js';import {UNITS,SPECS,compilerOptions} from '../src/kernel-specs.js';
const root=new URL('../',import.meta.url),stage=new URL('.build-generated/',root);
async function compilerStamp(dir){const names=(await fs.readdir(dir,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name));const parts=[];for(const n of names){const path=new URL(n.name+(n.isDirectory()?'/':''),dir);if(n.isDirectory())parts.push(...await compilerStamp(path));else if(n.name.endsWith('.js'))parts.push(n.name+'\0'+await fs.readFile(path,'utf8'));}return parts;}
const stamp=createHash('sha256').update((await compilerStamp(new URL('vendor/cuda-webshader/compiler/',root))).join('\0')).digest('hex');
await fs.writeFile(new URL('src/compiler-stamp.js',root),`// Auto-generated compiler implementation fingerprint.\nexport const COMPILER_STAMP=${JSON.stringify(stamp)};\n`);
const texts=Object.fromEntries(await Promise.all(UNITS.map(async n=>[n,await fs.readFile(new URL('kernels/'+n+'.cu',root),'utf8')])));await fs.rm(stage,{recursive:true,force:true});await fs.mkdir(stage,{recursive:true});
const manifest=[],failures=[];
for(const spec of SPECS){try{
 const source=spec.dependencies.map(n=>texts[n]).join('\n'),hash=createHash('sha256').update(stamp+'|specialize|'+spec.entry+'|'+spec.workgroupSize.join(',')+'|'+source).digest('hex');
 const artifact=compile(source,compilerOptions(spec));if(artifact.metadata.bindings.length>8)throw Error('Storage-buffer budget exceeded');if(artifact.metadata.workgroupStorageBytes>16384)throw Error('Shared-memory budget exceeded');
 const {ast,kernel,...portable}=artifact;portable.stratumHash=hash;portable.compilerStamp=stamp;
 await fs.writeFile(new URL(spec.entry+'.json',stage),JSON.stringify(portable));await fs.writeFile(new URL(spec.entry+'.wgsl',stage),artifact.wgsl);manifest.push({...spec,hash,bindings:artifact.metadata.bindings.map(b=>b.name)});
 console.log(`OK ${spec.entry} | ${artifact.metadata.bindings.length} buffers | ${artifact.wgsl.length} WGSL bytes`);
}catch(e){failures.push(spec.entry);console.error('FAILED '+spec.entry+': '+(e.stack||e));}}
if(failures.length){await fs.rm(stage,{recursive:true,force:true});throw Error('Compile failed, previous shaders retained: '+failures.join(', '));}
await fs.writeFile(new URL('manifest.json',stage),JSON.stringify(manifest,null,2));await fs.rm(new URL('generated/',root),{recursive:true,force:true});await fs.rename(stage,new URL('generated/',root));
await fs.writeFile(new URL('Water.cu',root),'// Generated combined CUDA. Infinite seeded archipelago and filtered ocean.\n'+UNITS.map(n=>'\n// ==== '+n+' ====\n'+texts[n]).join('\n'));
