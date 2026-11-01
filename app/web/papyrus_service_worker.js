'use strict';

// The release packager stamps this worker and lists only public application assets.
const prefix = 'papyrus-offline-';
const applicationRevision = 'unprepared';
let activeCache;
let assets;

async function metadata() {
  if (activeCache && assets) return;
  activeCache = prefix + applicationRevision;
  const cache = await caches.open(activeCache);
  const manifest = await (await cache.match('offline-manifest.json')).json();
  assets = new Set(manifest.assets.map(path => new URL(path, self.registration.scope).pathname));
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const response = await fetch('offline-manifest.json', {cache: 'no-store'});
    if (!response.ok) throw new Error('Offline application manifest is unavailable.');
    const manifest = await response.json();
    if (manifest.revision !== applicationRevision) throw new Error('Application update changed during download.');
    const name = prefix + manifest.revision;
    const cache = await caches.open(name);
    try {
      // Limit concurrent requests for large reader runtimes and fonts.
      for (let offset = 0; offset < manifest.assets.length; offset += 8) {
        await cache.addAll(manifest.assets.slice(offset, offset + 8).map(url => new Request(url, {cache: 'reload'})));
      }
      await cache.put('offline-manifest.json', new Response(JSON.stringify(manifest)));
      activeCache = name;
      assets = new Set(manifest.assets.map(path => new URL(path, self.registration.scope).pathname));
    } catch (error) {
      await caches.delete(name);
      throw error;
    }
  })());
});

self.addEventListener('message', event => {
  if (event.data !== 'activate-update') return;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    if (windows.length > 1) {
      event.ports[0]?.postMessage('other-tabs');
      return;
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    await metadata();
    for (const name of await caches.keys()) {
      if (name.startsWith(prefix) && name !== activeCache) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (url.pathname === new URL('release.json', self.registration.scope).pathname) return;
  // Never cache authenticated endpoints or user media.
  if (url.pathname.includes('/v1/') || url.pathname.includes('/api/')) return;
  event.respondWith((async () => {
    try {
      await metadata();
      const cache = await caches.open(activeCache);
      if (request.mode === 'navigate') {
        return await cache.match(new URL('index.html', self.registration.scope)) || fetch(request);
      }
      if (assets.has(url.pathname)) {
        return await cache.match(new URL(url.pathname, self.location.origin)) || fetch(request);
      }
    } catch (_) {
      // Storage eviction must not prevent the application loading online again.
    }
    return fetch(request);
  })());
});
