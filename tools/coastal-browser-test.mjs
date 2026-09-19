// Optional development dependency: npm install --no-save --package-lock=false playwright@1.63.0
// Exercises the real CUDA→WGSL runtime. No WebGL renderer or fabricated GPU results.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const root=path.resolve(fileURLToPath(new URL('../',import.meta.url))),reports=path.join(root,'reports');
await fs.mkdir(reports,{recursive:true});
const prefix='/WaterCuda',mime={'.js':'text/javascript','.json':'application/json','.html':'text/html','.css':'text/css','.cu':'text/plain'};
const server=http.createServer(async(req,res)=>{try{
 const u=new URL(req.url,'http://localhost');if(!u.pathname.startsWith(prefix+'/')){res.writeHead(404).end();return;}
 let p=decodeURIComponent(u.pathname.slice(prefix.length));if(p.endsWith('/'))p+='index.html';
 const file=path.resolve(root,'.'+p);if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');res.setHeader('Cache-Control','no-store');res.end(await fs.readFile(file));
}catch{res.writeHead(404).end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser,page;const errors=[],tests=[],requests=[],diagnostics=[],software=process.env.CW_SOFTWARE_GPU!=='0';
try{
 const options={channel:'chromium',headless:true,args:software?['--no-sandbox','--enable-unsafe-webgpu','--use-angle=swiftshader','--use-webgpu-adapter=swiftshader']:[]};
 if(process.env.CHROMIUM_EXECUTABLE){options.executablePath=process.env.CHROMIUM_EXECUTABLE;delete options.channel;}
 browser=await chromium.launch(options);page=await browser.newPage({viewport:{width:768,height:512}});page.setDefaultTimeout(15000);
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{const text=m.text();if(text.startsWith('COASTAL_GPU ')||m.type()==='error'){diagnostics.push(text);console.log(text);}});
 page.on('request',req=>requests.push(req.url()));await page.route('https://**',r=>r.abort());
 // This only observes native API calls in the regression page; production modules
 // and driver validation remain unchanged. A timeout must identify its kernel.
 await page.addInitScript(()=>{
  if(!globalThis.GPUDevice)return;
  const original=GPUDevice.prototype.createComputePipelineAsync;
  GPUDevice.prototype.createComputePipelineAsync=function(descriptor){
   const begun=performance.now(),label=descriptor.label;console.log('COASTAL_GPU '+JSON.stringify({phase:'pipeline-start',label}));
   return original.call(this,descriptor).then(value=>{console.log('COASTAL_GPU '+JSON.stringify({phase:'pipeline-ready',label,ms:performance.now()-begun}));return value;},error=>{console.log('COASTAL_GPU '+JSON.stringify({phase:'pipeline-error',label,error:String(error)}));throw error;});
  };
 });
 await page.goto(`http://127.0.0.1:${server.address().port}${prefix}/?seed=884`);
 await page.selectOption('#quality','640');
 await page.waitForFunction(()=>document.body.dataset.ready==='true'||document.querySelector('#status')?.textContent.includes('Open in a recent'),null,{timeout:480000});
 assert.equal(await page.locator('body').getAttribute('data-ready'),'true',await page.locator('#status').textContent());
 await page.evaluate(async()=>{waterCuda.setRenderLoop(false);await waterCuda.engine.runtime.idle();});
 console.log('COASTAL_GPU Application produced its first frame');
 const gpu=await page.evaluate(()=>waterCuda.engine.validate());assert.ok(gpu.checks.every(([,pass])=>pass),JSON.stringify(gpu));tests.push('Independent CPU FFT/terrain fixture and cached/eager GPU equivalence');
 const kernels=await page.evaluate(()=>waterCuda.engine.loader.loaded.size);
 const render=async(name,look,view,time=3,clarity=null,caustics=1)=>{
  console.log('COASTAL_GPU Render '+name);
  const result=await page.evaluate(async({look,view,time,clarity,caustics})=>{
   const {engine,camera,origin,preset,setLook}=waterCuda;setLook(look);preset(view);camera[5]=time;if(clarity!==null)camera[12]=clarity;camera[13]=caustics;
   await engine.resize(640,360);
   if(!engine.frame(camera,origin))throw Error('Unexpected benchmark backpressure');await engine.runtime.idle();
   const pixels=await engine.runtime.read(engine.pixels,Uint8Array);let sum=0,opaque=true;const colors=new Set();for(let i=0;i<pixels.length;i+=4){sum+=pixels[i]+pixels[i+1]+pixels[i+2];opaque&&=pixels[i+3]===255;if(i%16===0)colors.add((pixels[i]<<16)|(pixels[i+1]<<8)|pixels[i+2]);}
   const png=await engine.capture(),url=await new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.readAsDataURL(png);});
   return {png:url.split(',')[1],sum,colors:colors.size,opaque,builds:engine.spectrumBuilds,updates:engine.oceanUpdates,errors:engine.errors};
  },{look,view,time,clarity,caustics});
  await fs.writeFile(path.join(reports,name+'.png'),Buffer.from(result.png,'base64'));delete result.png;
  assert.ok(result.opaque);assert.ok(result.colors>300,'Real CUDA output must contain a nonuniform visible scene');assert.ok(result.sum>100000);assert.deepEqual(result.errors,[]);return result;
 };
 const coast=await render('coastal-daylight','coastal','coast');
 const frozen=await render('coastal-frozen','coastal','coast');assert.equal(frozen.updates,coast.updates);assert.equal(frozen.sum,coast.sum);assert.equal(frozen.builds,coast.builds);tests.push('Paused ocean reuses FFT output exactly');
 const shore=await render('coastal-shallows','coastal','shore');assert.equal(shore.updates,coast.updates);tests.push('Fly-camera/view changes do not regenerate unchanged waves');
 const opaque=await render('coastal-low-clarity','coastal','shore',3,.4);assert.notEqual(opaque.sum,shore.sum);tests.push('Water clarity visibly changes attenuation, without pipeline recompilation');
 const withoutCaustics=await render('coastal-no-caustics','coastal','shore',3,1.5,0);assert.notEqual(withoutCaustics.sum,shore.sum);tests.push('Actual FFT slope caustics affect the shallow-water image');
 const golden=await render('coastal-golden-hour','golden','coast');assert.notEqual(golden.sum,coast.sum);assert.equal(golden.builds,coast.builds);
 const moving=await render('coastal-wave-motion','coastal','coast',4);assert.notEqual(moving.sum,coast.sum);tests.push('Changing time/wind evolves cached coefficients; changing lighting reuses pipelines');
 await page.evaluate(async()=>{waterCuda.origin[2]=42;waterCuda.engine.frame(waterCuda.camera,waterCuda.origin);await waterCuda.engine.runtime.idle();});
 assert.equal(await page.evaluate(()=>waterCuda.engine.spectrumBuilds),coast.builds+1);tests.push('Changing the world seed rebuilds its coefficients once');
 assert.equal(await page.evaluate(()=>waterCuda.engine.loader.loaded.size),kernels);
 assert.ok(!requests.some(u=>/three|\.glb|\.gltf|\.jpe?g|\.webp/i.test(u)),'No scene/model/image assets may be loaded');
 await page.screenshot({path:path.join(reports,'coastal-ui.png'),timeout:10000});
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(reports,'coastal-mobile-ui.png'),timeout:10000});
 assert.deepEqual(errors,[]);
 const report={passed:true,browser:browser.version(),softwareAdapterRequested:software,adapter:gpu.adapter,checks:gpu.checks,tests,images:{coast,shore,golden,moving},kernelCount:kernels,pageErrors:errors,diagnostics,notMeasured:['RTX 5080 frame rate','hardware cold compilation times','physical shoreline fluid simulation']};
 await fs.writeFile(path.join(reports,'coastal-browser.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
}catch(e){await page?.screenshot({path:path.join(reports,'coastal-failure.png'),timeout:5000}).catch(()=>{});await fs.writeFile(path.join(reports,'coastal-browser-failure.json'),JSON.stringify({error:e.stack,pageErrors:errors,tests,diagnostics,status:await page?.locator('#status').textContent({timeout:3000}).catch(()=>null)},null,2));throw e;}
finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
