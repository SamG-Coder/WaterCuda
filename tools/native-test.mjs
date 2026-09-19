import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
const dir=path.resolve('artifacts');await fs.mkdir(dir,{recursive:true});
const binary=path.join(dir,process.platform==='win32'?'native-test.exe':'native-test');
let result=spawnSync(process.env.CXX||'g++',['-std=c++17','-O2','tests/native.cpp','-o',binary],{stdio:'inherit'});
if(result.error)throw Error('A C++17 compiler is needed for native geometry checks; set CXX.');
if(result.status)process.exit(result.status);
result=spawnSync(binary,[],{stdio:'inherit'});process.exitCode=result.status??1;
