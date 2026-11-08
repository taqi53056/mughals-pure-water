import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".webmanifest": "application/manifest+json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".css": "text/css; charset=utf-8"
};

const server = createServer(async (req, res) => {
  try {
    const pathname = new URL(req.url, "http://127.0.0.1").pathname;
    const relative = pathname === "/" ? "index.html" : decodeURIComponent(pathname.slice(1));
    const path = resolve(ROOT, relative);
    if (!path.startsWith(ROOT)) {
      res.writeHead(403).end("Forbidden");
      return;
    }
    const data = await readFile(path);
    res.writeHead(200, { "content-type": mime[extname(path)] || "application/octet-stream" });
    res.end(data);
  } catch {
    res.writeHead(404).end("Not found");
  }
});

await new Promise(resolveListen => server.listen(4173, "0.0.0.0", resolveListen));
const browser = await chromium.launch({ headless: true });
const failures = [];

try {
  for (const viewport of [{ width: 1365, height: 900 }, { width: 390, height: 844 }]) {
    const page = await browser.newPage({ viewport });
    page.on("pageerror", error => failures.push(`${viewport.width}px page error: ${error.message}`));

    // The test is intentionally a UI smoke test; no authentication or live data is used.
    await page.route("https://cdn.jsdelivr.net/**", route =>
      route.fulfill({
        status: 200,
        contentType: "application/javascript",
        body: "window.supabase = { createClient: () => ({}) };"
      })
    );

    await page.goto("http://localhost:4173/index.html", { waitUntil: "load" });
    await page.locator("#loginForm").waitFor({ state: "visible" });

    const state = await page.evaluate(() => ({
      title: document.title,
      direction: document.documentElement.dir,
      width: document.documentElement.scrollWidth,
      viewport: window.innerWidth,
      manifest: document.querySelector('link[rel="manifest"]')?.getAttribute("href")
    }));

    if (!state.title.includes("MUGHAL'S PURE WATER")) failures.push("Incorrect page title");
    if (state.direction !== "rtl") failures.push("Document direction is not RTL");
    if (state.width > state.viewport + 1) failures.push(`Horizontal overflow at ${viewport.width}px`);
    if (!state.manifest) failures.push("PWA manifest link is missing");
    const manifestResponse = await page.request.get("http://localhost:4173/manifest.webmanifest");
    if (!manifestResponse.ok()) failures.push("PWA manifest did not load");
    else {
      const manifest = await manifestResponse.json();
      if (!String(manifest.name || "").includes("MUGHAL'S PURE WATER")) failures.push("PWA manifest name is incorrect");
    }
    const serviceWorkerActive = await page.evaluate(async () => {
      if (!("serviceWorker" in navigator)) return false;
      const registration = await navigator.serviceWorker.ready;
      return Boolean(registration.active && new URL(registration.active.scriptURL).pathname.endsWith("/SW.js"));
    });
    if (!serviceWorkerActive) failures.push("PWA Service Worker did not activate");

    await page.locator('button[onclick="showSignup()"]').click();
    await page.locator("#signupForm").waitFor({ state: "visible" });
    for (const id of ["signupName", "signupMobile", "signupAddress", "signupEmail", "signupPassword"]) {
      if (!(await page.locator("#" + id).isVisible())) failures.push("Missing signup field: " + id);
    }
    await page.locator('button[onclick="showLogin()"]').click();
    await page.locator("#loginForm").waitFor({ state: "visible" });

    const deliveryMath = await page.evaluate(() => {
      const fixture = document.createElement("div");
      fixture.innerHTML = `
        <select id="dWorker">
          <option value="">No worker</option>
          <option value="2" data-owner="false" selected>Worker</option>
          <option value="1" data-owner="true">Owner</option>
        </select>
        <input id="dOut"><input id="dBack"><input id="dCaps">
        <b id="dSuccess"></b><b id="dDiff"></b><b id="dLabor"></b>
        <b id="dOwnerSaving"></b><b id="dCapAmount"></b><div id="dWarn"></div>
      `;
      document.body.appendChild(fixture);
      document.querySelector("#dOut").value = "12";
      document.querySelector("#dBack").value = "10";
      document.querySelector("#dCaps").value = "2";
      const worker = window.calcDelivery();
      document.querySelector("#dWorker").value = "1";
      const owner = window.calcDelivery();
      document.querySelector("#dBack").value = "13";
      const invalid = window.calcDelivery();
      fixture.remove();
      return { worker, owner, invalid };
    });
    if (deliveryMath.worker.success !== 10 || deliveryMath.worker.diff !== 2 ||
        deliveryMath.worker.labor !== 200 || deliveryMath.worker.capAmount !== 20) {
      failures.push("19L worker delivery calculation is incorrect");
    }
    if (deliveryMath.owner.labor !== 0 || deliveryMath.owner.ownerSaving !== 200) {
      failures.push("19L owner labor saving calculation is incorrect");
    }
    if (!deliveryMath.invalid.invalid) failures.push("19L returned-bottles validation is incorrect");

    const settingsResult = await page.evaluate(async () => {
      const mockData = {
        product_settings: [
          { id: 1, product_type: "500ml", unit_type: "carton", units_per_pack: 24, default_rate: 280, special_100_rate: 280, labor_per_unit: 10, is_active: true },
          { id: 2, product_type: "1.5L", unit_type: "carton", units_per_pack: 12, default_rate: 280, special_100_rate: 280, labor_per_unit: 10, is_active: true },
          { id: 3, product_type: "6L", unit_type: "bottle", units_per_pack: 18, default_rate: 55, special_100_rate: null, labor_per_unit: 0, is_active: true }
        ],
        profiles: [{ id: "admin-test", full_name: "Admin Test", role: "admin" }],
        workers: [{ id: 1, full_name: "Owner", is_active: true, is_owner: true }]
      };
      const updates = [];
      window.db = {
        from(table) {
          const chain = {
            select() { return chain; },
            eq() { return chain; },
            order() { return Promise.resolve({ data: mockData[table] || [], error: null }); },
            update(values) { updates.push({ table, values }); return chain; },
            then(resolve, reject) { return Promise.resolve({ error: null }).then(resolve, reject); }
          };
          return chain;
        }
      };
      window.confirm = () => true;
      await window.settingsModule();
      const rendered = Boolean(document.querySelector("#psDefault_1") && document.querySelector("#psSpecial_1"));
      document.querySelector("#psDefault_1").value = "279";
      await window.saveProductSettings(1, "500ml");
      const belowFloorBlocked = updates.length === 0;
      document.querySelector("#psDefault_1").value = "300";
      document.querySelector("#psSpecial_1").value = "310";
      await window.saveProductSettings(1, "500ml");
      return {
        rendered,
        belowFloorBlocked,
        saved: updates.length === 1 && updates[0].table === "product_settings",
        savedDefault: updates[0]?.values?.default_rate,
        savedSpecial: updates[0]?.values?.special_100_rate
      };
    });
    if (!settingsResult.rendered) failures.push("Admin settings price controls did not render");
    if (!settingsResult.belowFloorBlocked) failures.push("Admin settings allowed a carton price below Rs.280");
    if (!settingsResult.saved || settingsResult.savedDefault !== 300 || settingsResult.savedSpecial !== 310) {
      failures.push("Admin settings did not save valid price changes correctly");
    }

    await page.close();
  }
} finally {
  await browser.close();
  await new Promise(resolveClose => server.close(resolveClose));
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("PASS: desktop/mobile page load, RTL layout, title, PWA manifest link, signup form, and login navigation.");
