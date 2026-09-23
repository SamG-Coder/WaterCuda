// GitHub Pages cannot set COOP/COEP headers. This scope-local worker adds
// isolation to network responses; it deliberately does not cache application files.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
 const request=event.request;
 if(new URL(request.url).origin!==self.location.origin || (request.cache==='only-if-cached'&&request.mode!=='same-origin'))return;
 event.respondWith(fetch(request).then(response=>{
  if(response.status===0)return response;
  const headers=new Headers(response.headers);
  headers.set('Cross-Origin-Opener-Policy','same-origin');
  headers.set('Cross-Origin-Embedder-Policy','require-corp');
  return new Response(response.body,{status:response.status,statusText:response.statusText,headers});
 }));
});
