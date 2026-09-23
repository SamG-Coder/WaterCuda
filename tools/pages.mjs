import {cp,mkdir,writeFile,access} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const site=path.join(root,'artifacts/pages');
await access(path.join(root,'generated/manifest.json'));
await mkdir(site,{recursive:true});
for(const item of ['index.html','style.css','isolation-sw.js','src','kernels','generated','vendor','docs','LICENSE'])
 await cp(path.join(root,item),path.join(site,item),{recursive:true});
await mkdir(path.join(site,'tests'),{recursive:true});
await cp(path.join(root,'tests/ocean-reference.json'),path.join(site,'tests/ocean-reference.json'));
const wasm='experiments/webshader-wasm';
await mkdir(path.join(site,wasm,'generated'),{recursive:true});
for(const item of ['threaded-worker.js','threaded-runtime.js','generated/world.mjs','generated/world.wasm','generated/world.abi.json'])
 await cp(path.join(root,wasm,item),path.join(site,wasm,item));
await writeFile(path.join(site,'.nojekyll'),'');
console.log('GitHub Pages artifact: '+site);
