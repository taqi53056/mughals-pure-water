const CACHE_NAME = "mughals-pure-water-v135-daily-pnl-empty-state";
const APP_SHELL = ["./", "./index.html", "./manifest.webmanifest", "./logo.svg"];
const APP_SHELL_PATHS = new Set(APP_SHELL.map(path => new URL(path, self.location.href).pathname));

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter(key => key.startsWith("mughals-pure-water-") && key !== CACHE_NAME)
        .map(key => caches.delete(key))
    );
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  const isNavigation = request.mode === "navigate";
  const isShellAsset = APP_SHELL_PATHS.has(url.pathname);
  if (!isNavigation && !isShellAsset) return;

  event.respondWith((async () => {
    try {
      const response = await fetch(request);
      // Never cache query-bearing URLs (including auth callback codes) or non-shell resources.
      if (response && response.ok && isShellAsset && !url.search) {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
      }
      return response;
    } catch {
      const cache = await caches.open(CACHE_NAME);
      return (await cache.match(request)) ||
        (isNavigation ? await cache.match("./index.html") : undefined);
    }
  })());
});

self.addEventListener("push", event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; }
  catch (_) { payload = { body: event.data ? event.data.text() : "" }; }
  const title = String(payload.title || "MUGHAL'S PURE WATER");
  const options = {
    body: String(payload.body || "آپ کے اکاؤنٹ میں نئی اطلاع موجود ہے۔"),
    icon: "./logo.svg",
    badge: "./logo.svg",
    tag: String(payload.tag || "mpw-customer-notification"),
    renotify: true,
    data: { url: String(payload.url || "./") },
    dir: "rtl",
    lang: "ur"
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const appBase = new URL("./", self.location.href);
  const requested = new URL(event.notification.data?.url || "./", appBase);
  const target = requested.origin === appBase.origin && requested.pathname.startsWith(appBase.pathname)
    ? requested.href
    : appBase.href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      const clientUrl = new URL(client.url);
      if (clientUrl.origin === appBase.origin && clientUrl.pathname.startsWith(appBase.pathname)) {
        await client.focus();
        if ("navigate" in client) await client.navigate(target);
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});
