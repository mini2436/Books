{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  const appBaseUrl = new URL('.', document.baseURI);
  const workerUrl = new URL('pwa_service_worker.js', appBaseUrl);
  navigator.serviceWorker
    .register(workerUrl, {scope: appBaseUrl.pathname})
    .catch((error) => console.warn('PWA service worker registration failed:', error));
}

_flutter.loader.load();
