// Quantara-owned PWA service worker.
//
// Flutter's generated worker is intentionally replaced with this file in the
// distributable build. Keep exchange/API traffic outside this worker: only
// same-origin GET requests within the PWA scope are eligible for caching.

const CACHE_PREFIX = 'quantara-pwa-';
const CACHE_NAME = `${CACHE_PREFIX}v2`;
const APP_SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)),
  );
  // Do not call skipWaiting here. A new UI must not replace the active build
  // until the user explicitly accepts the update prompt in index.html.
});

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter(
              (key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME,
            )
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstNavigation(request));
    return;
  }

  event.respondWith(cacheFirstAsset(request));
});

async function networkFirstNavigation(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request);
    if (response.ok) {
      await cache.put(request, response.clone());
    }
    return response;
  } catch (_) {
    return (
      (await cache.match(request)) ||
      (await cache.match('index.html')) ||
      (await cache.match('./')) ||
      Response.error()
    );
  }
}

async function cacheFirstAsset(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    if (response.ok && response.type !== 'opaque') {
      await cache.put(request, response.clone());
    }
    return response;
  } catch (_) {
    return Response.error();
  }
}
