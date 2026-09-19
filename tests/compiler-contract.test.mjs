import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {SPECS} from '../src/kernel-specs.js';
import {COMPILER_STAMP} from '../src/compiler-stamp.js';
test('all portable kernels are source-hashed, specialised and inside baseline buffer budgets',async()=>{
 for(const s of SPECS){
  const source=(await Promise.all(s.dependencies.map(n=>fs.readFile(new URL('../kernels/'+n+'.cu',import.meta.url),'utf8')))).join('\n');
  const hash=createHash('sha256').update(COMPILER_STAMP+'|specialize|'+s.entry+'|'+s.workgroupSize.join(',')+'|'+source).digest('hex');
  const a=JSON.parse(await fs.readFile(new URL('../generated/'+s.entry+'.json',import.meta.url),'utf8'));
  assert.equal(a.stratumHash,hash,s.entry);assert.equal(a.compilerStamp,COMPILER_STAMP);
  assert.ok(a.metadata.bindings.length<=8,s.entry);assert.ok(a.metadata.workgroupStorageBytes<=16384,s.entry);
 }
});
test('every host module parses and all application DOM hooks exist',async()=>{
 const files=(await fs.readdir(new URL('../src/',import.meta.url))).filter(n=>n.endsWith('.js'));
 for(const file of files){const result=spawnSync(process.execPath,['--check',new URL('../src/'+file,import.meta.url).pathname],{encoding:'utf8'});assert.equal(result.status,0,file+': '+result.stderr);}
 const html=await fs.readFile(new URL('../index.html',import.meta.url),'utf8'),app=await fs.readFile(new URL('../src/app.js',import.meta.url),'utf8');
 const ids=new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]));
 for(const m of app.matchAll(/\$\('([^']+)'\)/g))assert.ok(ids.has(m[1]),'Missing DOM hook '+m[1]);
});
