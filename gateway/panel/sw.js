// TAGUATO-SEND Service Worker
const CACHE_NAME = 'taguato-v7';
const STATIC_ASSETS = [
  '/panel/',
  '/panel/index.html',
  '/panel/css/style.css',
  '/panel/js/api.js',
  '/panel/js/docs-data.js',
  '/panel/js/app.js',
  '/panel/img/logo.png',
  '/panel/manifest.json',
  '/favicon.ico',
];

const CORE_ASSETS = new Set([
  '/panel/',
  '/panel/index.html',
  '/panel/js/api.js',
  '/panel/js/app.js',
  '/panel/sw.js',
]);

// Install: cache static assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS);
    })
  );
  self.skipWaiting();
});

// Activate: clean old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      );
    })
  );
  self.clients.claim();
});

// Fetch: cache-first for static, network-only for API
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Network-only for API calls
  if (url.pathname.startsWith('/api/') ||
      url.pathname.startsWith('/admin/') ||
      url.pathname.startsWith('/instance/') ||
      url.pathname.startsWith('/message/')) {
    // Avoid HTTP cache (ETag/304) for dynamic API responses
    event.respondWith(fetch(new Request(event.request, { cache: 'no-store' })));
    return;
  }

  // Network-first for core app shell to avoid stale UI after upgrades
  if (CORE_ASSETS.has(url.pathname)) {
    event.respondWith(
      fetch(new Request(event.request, { cache: 'no-store' }))
        .then((response) => {
          if (response && response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Cache-first for static assets
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) {
        // Return cached, but also update in background
        fetch(event.request).then((response) => {
          if (response && response.status === 200) {
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(event.request, response);
            });
          }
        }).catch(() => {});
        return cached;
      }
      return fetch(event.request).then((response) => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, clone);
          });
        }
        return response;
      });
    })
  );
});
