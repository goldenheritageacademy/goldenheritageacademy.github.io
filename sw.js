/* ============================================================================
   SERVICE WORKER — Golden Heritage Academy Portal PWA
   Caches app shell for offline support and fast loads.
   ============================================================================ */

const CACHE_NAME = 'gha-portal-v1';
const SHELL_ASSETS = [
  '/',
  '/index.html',
  '/assets/css/common.css',
  '/assets/js/config.js',
  '/assets/js/menu.js',
  '/assets/js/common.js',
  '/manifest.json'
];

// Install: pre-cache the app shell
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

// Activate: clean up old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch: network-first for API, cache-first for assets
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip cross-origin requests (Supabase API)
  if (url.origin !== location.origin) return;

  event.respondWith(
    caches.match(request).then(cached => {
      const networkFetch = fetch(request).then(response => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
        }
        return response;
      });
      return cached || networkFetch;
    })
  );
});
