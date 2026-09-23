import {cp,mkdir,readFile,writeFile,readdir} from 'node:fs/promises';import {execFileSync} from 'node:child_process';import {createHash} from 'node:crypto';import path from 'node:path';import {fileURLToPath} from 'node:url';
const repo=path.resolve(process.argv[2]||'');if(!process.argv[2])throw Error('Usage: node tools/sync-webshader.mjs PATH_TO_CLEAN_UPSTREAM_CHECKOUT');
const git=(...args)=>execFileSync('git',['-C',repo,...args],{encoding:'utf8'}).trim();
if(git('status','--porcelain'))throw Error('Upstream checkout must be clean.');
const url=git('remote','get-url','origin');if(url!=='https://github.com/SamG-Coder/cuda-webshader.git')throw Error('Unexpected upstream repository.');
const commit=git('rev-parse','HEAD'),target=fileURLToPath(new URL('../vendor/cuda-webshader/',import.meta.url));await mkdir(target,{recursive:true});
for(const part of ['compiler','runtime','wasm'])await cp(path.join(repo,'src',part),path.join(target,part),{recursive:true});
for(const file of ['LICENSE','THIRD_PARTY_NOTICES.md'])await cp(path.join(repo,file),path.join(target,file));
const hashes={};async function visit(part){for(const e of await readdir(path.join(target,part),{withFileTypes:true})){const relative=part+'/'+e.name;if(e.isDirectory())await visit(relative);else hashes[relative]=createHash('sha256').update((await readFile(path.join(target,relative),'utf8')).replaceAll('\r\n','\n')).digest('hex');}}
for(const part of ['compiler','runtime','wasm'])await visit(part);
await writeFile(path.join(target,'UPSTREAM.json'),JSON.stringify({repository:url,commit,normalization:'UTF-8 with LF line endings',files:hashes},null,2)+'\n');console.log('Vendored cuda-webshader '+commit);
