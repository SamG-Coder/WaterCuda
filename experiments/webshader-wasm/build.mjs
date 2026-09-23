import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {compileWasm} from './compiler/wasm.mjs';
const source=(await Promise.all(['../../kernels/common.cu','../../kernels/weather.cu','../../kernels/terrain.cu','./preview.cu'].map(p=>readFile(new URL(p,import.meta.url),'utf8')))).join('\n');
await compileWasm(source,{entry:'previewWorld',workgroupSize:[8,8,1],optimize:'specialize'},{outDir:fileURLToPath(new URL('./generated/',import.meta.url))});
console.log('WebShader generated WASM, WGSL and ABI from shared .cu source.');
