// Install before importing the app so the first visit reloads before compilation.
async function isolate(){
 if(crossOriginIsolated || !isSecureContext || !('serviceWorker' in navigator))return;
 const key='watercuda-isolation-reload';
 try{
  const registration=await navigator.serviceWorker.register(new URL('../isolation-sw.js',import.meta.url),{updateViaCache:'none'});
  if(navigator.serviceWorker.controller || sessionStorage.getItem(key))return;
  await Promise.race([
   new Promise(resolve=>navigator.serviceWorker.addEventListener('controllerchange',resolve,{once:true})),
   new Promise(resolve=>setTimeout(resolve,4000))
  ]);
  if(navigator.serviceWorker.controller){sessionStorage.setItem(key,'1');location.reload();await new Promise(()=>{});}
 }catch(error){console.warn('WASM isolation unavailable; using WebGPU startup.',error);}
}
await isolate();
await import('./app.js');
