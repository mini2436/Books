'use strict';

const CACHE_PREFIX = 'qingyue-app-shell-';
const CACHE_NAME = `${CACHE_PREFIX}v1`;
const APP_ROOT_URL = new URL('./', self.registration.scope).toString();

const REQUIRED_APP_SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'version.json',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/fonts/MiSans-Regular.ttf',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
];

const OPTIONAL_APP_SHELL = [
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
  'assets/NOTICES',
  'assets/assets/fonts/SourceHanSerifSC-Regular.otf',
  'assets/assets/fonts/LXGWWenKai-Regular.ttf',
  'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'assets/shaders/ink_sparkle.frag',
  'assets/shaders/stretch_effect.frag',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(REQUIRED_APP_SHELL.map((path) => cacheAsset(cache, path)));
      await Promise.allSettled(
        OPTIONAL_APP_SHELL.map((path) => cacheAsset(cache, path)),
      );
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const cacheNames = await caches.keys();
      await Promise.all(
        cacheNames
          .filter(
            (name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME,
          )
          .map((name) => caches.delete(name)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('range')) return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstNavigation(request));
    return;
  }

  if (isAppShellAsset(url)) {
    event.respondWith(networkFirstAsset(request));
  }
});

async function cacheAsset(cache, relativePath) {
  const url = new URL(relativePath, self.registration.scope);
  const response = await fetch(url, {cache: 'reload'});
  if (!response.ok) {
    throw new Error(`Unable to cache ${url.pathname}: HTTP ${response.status}`);
  }
  await cache.put(url, response);
}

async function networkFirstNavigation(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetchWithTimeout(request);
    if (response.ok) {
      await cache.put(APP_ROOT_URL, response.clone());
    }
    return response;
  } catch (_) {
    return (
      (await cache.match(APP_ROOT_URL)) ||
      (await cache.match(new URL('index.html', self.registration.scope))) ||
      Response.error()
    );
  }
}

async function networkFirstAsset(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetchWithTimeout(request);
    if (response.ok) await cache.put(request, response.clone());
    return response;
  } catch (_) {
    return (await cache.match(request)) || Response.error();
  }
}

async function fetchWithTimeout(request) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3500);
  try {
    return await fetch(request, {signal: controller.signal});
  } finally {
    clearTimeout(timeout);
  }
}

function isAppShellAsset(url) {
  const scopePath = new URL(self.registration.scope).pathname;
  if (!url.pathname.startsWith(scopePath)) return false;
  const relativePath = url.pathname.slice(scopePath.length);
  return (
    relativePath.startsWith('assets/') ||
    relativePath.startsWith('canvaskit/') ||
    relativePath.startsWith('icons/') ||
    [
      'favicon.png',
      'flutter_bootstrap.js',
      'flutter.js',
      'main.dart.js',
      'manifest.json',
      'version.json',
    ].includes(relativePath)
  );
}
