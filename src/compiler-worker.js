import {compile} from '../vendor/cuda-webshader/compiler/compiler.js';
import {compilerOptions} from './kernel-specs.js';
self.onmessage=event=>{const {id,source,spec}=event.data;try{const {ast,kernel,...artifact}=compile(source,compilerOptions(spec));self.postMessage({id,artifact});}catch(e){self.postMessage({id,error:String(e.stack||e)});}};
