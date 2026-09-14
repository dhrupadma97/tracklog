// Custom bootstrap: load the app without installing a service worker.
//
// Flutter's default bootstrap registers flutter_service_worker.js, which keeps
// a copy of the app shell and main.dart.js in CacheStorage and answers from it
// before the network is consulted. For an app that is only useful online — every
// screen here reads Supabase — that buys nothing, and it cost a full day:
// deploys verified byte-identical on the server kept reaching the browser as
// the previous build, so shipped fixes looked like they had not worked and a
// login failure that had already been fixed kept reappearing. The no-cache
// headers in firebase.json govern the network fetch; they cannot govern what a
// worker has already stored. Ctrl+Shift+R does not help either, because the
// worker intercepts ahead of the HTTP cache.
//
// Dropping the worker gives up offline support the app never actually had, and
// makes what is deployed and what is running the same thing.
//
// The template tokens below are filled in by `flutter build web`.
{{flutter_js}}
{{flutter_build_config}}

// Evict any worker an earlier build installed, and the caches it is holding.
// Without this, a browser that already has one keeps being served the old
// shell and would never reach this file at all — so this runs for every client
// that manages to load it once, and then the problem is gone for good.
(function evictLegacyServiceWorker() {
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker
          .getRegistrations()
          .then(function (registrations) {
            registrations.forEach(function (r) { r.unregister(); });
          })
          .catch(function () { /* nothing to clean up */ });
    }
    if (window.caches && window.caches.keys) {
      window.caches
          .keys()
          .then(function (keys) {
            keys.forEach(function (k) { window.caches.delete(k); });
          })
          .catch(function () { /* nothing to clean up */ });
    }
  } catch (_) {
    // Never let cache cleanup stop the app from starting.
  }
})();

// No serviceWorkerSettings argument: the loader registers no worker.
_flutter.loader.load();
