/* Replaced by the staging build with a versioned asset list. */
const version = '__OFFLINE_VERSION__';
const assets = /* OFFLINE_ASSETS */ [];
const cacheName = 'pharmacy-qa-pos-' + version;
const home = '/offline-pos/index.html';

self.addEventListener('install', event => {
 event.waitUntil((async () => {
  if (!assets.length) throw Error('offline_pos_not_built');
  const cache = await caches.open(cacheName);
  await cache.addAll(assets.map(path => new Request(path,{cache:'reload',redirect:'error'})));
 })());
});
self.addEventListener('activate', event => {
 event.waitUntil((async () => {
  for (const name of await caches.keys()) {
   if (name.startsWith('pharmacy-qa-pos-') && name !== cacheName) await caches.delete(name);
  }
  await self.clients.claim();
 })());
});
self.addEventListener('fetch', event => {
 const url = new URL(event.request.url);
 if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
 const path = event.request.mode === 'navigate' && ['/offline-pos/','/offline-pos/index.html'].includes(url.pathname)
  ? home : url.pathname;
 if (!assets.includes(path)) return;
 // Keep the cached HTML and its versioned assets together across deployments.
 event.respondWith(caches.open(cacheName).then(cache=>cache.match(path)).then(response=>response||fetch(event.request)));
});
