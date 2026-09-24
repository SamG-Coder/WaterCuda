import {cp,mkdir,writeFile,access,readFile} from 'node:fs/promises';
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
for(const item of ['threaded-worker.js','threaded-runtime.js','checkerboard-resolve.js','history-projection.js','generated/world.mjs','generated/world.wasm','generated/world.abi.json'])
 await cp(path.join(root,wasm,item),path.join(site,wasm,item));
// Check the packaged import graph, not the source tree: a local-only dependency
// otherwise passes unit tests but prevents the published worker from starting.
const visited=new Set();
async function checkModule(file){
 if(visited.has(file))return;visited.add(file);
 const source=await readFile(file,'utf8');
 const imports=/(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s*)['"](\.[^'"]+)['"]/g;
 for(const [,specifier]of source.matchAll(imports)){
  const dependency=path.resolve(path.dirname(file),specifier);
  if(!dependency.startsWith(site+path.sep))throw Error('Packaged import escapes site: '+specifier);
  await checkModule(dependency);
 }
}
await checkModule(path.join(site,'src/startup.js'));
await checkModule(path.join(site,wasm,'threaded-worker.js'));
await writeFile(path.join(site,'.nojekyll'),'');
console.log('GitHub Pages artifact: '+site);
