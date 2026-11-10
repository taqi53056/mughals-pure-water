const CACHE_NAME = "mughals-pure-water-v66-inventory-cost-fix";
const APP_SHELL = ["./", "./index.html", "./manifest.webmanifest", "./logo.svg"];
self.addEventListener("install", event => { event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL))); self.skipWaiting(); });
self.addEventListener("activate", event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))); self.clients.claim(); });
self.addEventListener("fetch", event => { const request=event.request; const url=new URL(request.url); if(request.method!=="GET"||url.origin!==self.location.origin)return; event.respondWith(fetch(request).then(response=>{if(response&&response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(request,copy));}return response;}).catch(()=>caches.match(request).then(cached=>cached||(request.mode==="navigate"?caches.match("./index.html"):undefined)))); });

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
  const target = new URL(event.notification.data?.url || "./", self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.location.origin)) {
        await client.focus();
        if ("navigate" in client) await client.navigate(target);
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});
