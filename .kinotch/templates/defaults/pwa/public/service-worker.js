self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});
self.addEventListener("fetch", () => {
  // The Project decides its cache and offline policy. This default is a
  // pass-through registration boundary and does not cache Domain data.
});
