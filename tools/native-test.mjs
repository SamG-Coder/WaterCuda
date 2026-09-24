import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
const dir=path.resolve('artifacts');await fs.mkdir(dir,{recursive:true});
for(const name of ['native','trace-budget','terrain-cache','coastal-ecology','underwater','weather','ship']){
 const binary=path.join(dir,name+(process.platform==='win32'?'.exe':''));
 let result=spawnSync(process.env.CXX||'g++',['-std=c++17','-O2','tests/'+name+'.cpp','-o',binary],{stdio:'inherit'});
 if(result.error)throw Error('A C++17 compiler is needed for native geometry checks; set CXX.');
 if(result.status)process.exit(result.status);
 result=spawnSync(binary,[],{stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)process.exit(result.status??1);
}
