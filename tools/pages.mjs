import {cp,mkdir,writeFile,access} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const site=path.join(root,'artifacts/pages');
await access(path.join(root,'generated/manifest.json'));
await mkdir(site,{recursive:true});
for(const item of ['index.html','style.css','src','kernels','generated','vendor','docs','LICENSE'])
 await cp(path.join(root,item),path.join(site,item),{recursive:true});
await mkdir(path.join(site,'tests'),{recursive:true});
await cp(path.join(root,'tests/ocean-reference.json'),path.join(site,'tests/ocean-reference.json'));
await writeFile(path.join(site,'.nojekyll'),'');
console.log('GitHub Pages artifact: '+site);
