export async function registerServiceWorker({
  scriptUrl = "./service-worker.js",
  scope = "./"
} = {}) {
  if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) {
    return null;
  }
  return navigator.serviceWorker.register(scriptUrl, { scope });
}
