import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {UNITS,SPECS} from '../../src/kernel-specs.js';
import {compileCheckerboard} from './checkerboard-build.mjs';
const source=(await Promise.all(UNITS.map(n=>readFile(new URL('../../kernels/'+n+'.cu',import.meta.url),'utf8')))).join('\n');
const kernels=await compileCheckerboard(source,SPECS,{outDir:fileURLToPath(new URL('./generated/',import.meta.url))});
console.log('WebShader generated shared-memory WASM for all '+kernels.length+' production kernels, including cooperative FFT.');
