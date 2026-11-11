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

const monthlyRetryMigration = await readFile(
  resolve(ROOT, "supabase/migrations/20261111133356_retry_monthly_billing_and_reports.sql"),
  "utf8"
);
if (!monthlyRetryMigration.includes("schedule => '55 18 * * *'") ||
    !monthlyRetryMigration.includes("schedule => '5 19 * * *'")) {
  throw new Error("Monthly billing and report cron jobs must retry daily");
}
if (!monthlyRetryMigration.includes("business_month_closings") ||
    !monthlyRetryMigration.includes("status = 'closed'")) {
  throw new Error("Monthly report retries must preserve a formally closed snapshot");
}
if (!monthlyRetryMigration.includes("v_report->>'has_activity'")) {
  throw new Error("Monthly report retries must not create empty zero-activity snapshots");
}
if (monthlyRetryMigration.includes("extract(day from v_today)>3")) {
  throw new Error("Monthly report retries must not stop after the first three days");
}

const customerBillNotificationMigration = await readFile(
  resolve(ROOT, "supabase/migrations/20261111133556_customer_bill_notification_retry.sql"),
  "utf8"
);
const monthlyBillLock = customerBillNotificationMigration.indexOf("pg_advisory_xact_lock");
const monthlyBillRead = customerBillNotificationMigration.indexOf("FROM public.customer_19l_deliveries");
if (monthlyBillLock < 0 || monthlyBillRead < 0 || monthlyBillLock > monthlyBillRead) {
  throw new Error("Monthly billing must lock the month before reading source rows");
}
if (!customerBillNotificationMigration.includes("customer_monthly_bills.current_due") ||
    !customerBillNotificationMigration.includes("IS DISTINCT FROM ROW")) {
  throw new Error("Monthly billing must reconcile existing bill rows without needless updates");
}
if (!customerBillNotificationMigration.includes("customer_notifications.message IS DISTINCT FROM EXCLUDED.message") ||
    customerBillNotificationMigration.includes("is_read = false")) {
  throw new Error("Monthly bill notifications must update content without resetting read state");
}

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
const billLockMigration = await readFile(
  resolve(ROOT, "supabase/migrations/20261111132842_serialize_customer_bill_recalculation.sql"),
  "utf8"
);
const billLockPosition = billLockMigration.indexOf("pg_advisory_xact_lock");
const billSourceReadPosition = billLockMigration.indexOf("FROM public.customer_19l_deliveries");
if (billLockPosition < 0 || billSourceReadPosition < 0 || billLockPosition > billSourceReadPosition) {
  failures.push("Customer bill recalculation must acquire the month advisory lock before reading delivery rows");
}
if (!billLockMigration.includes("SECURITY INVOKER") ||
    !billLockMigration.includes("auth.uid() IS NULL OR NOT public.is_admin()")) {
  failures.push("Customer bill recalculation must remain invoker-secured and explicitly admin-only");
}
if (!billLockMigration.includes("Future customer bills cannot be calculated.")) {
  failures.push("Customer bill recalculation must reject future billing months");
}
const appSource = await readFile(resolve(ROOT, "index.html"), "utf8");
if (!appSource.includes('id="bMonth" type="month" value="${today().slice(0,7)}" max="${today().slice(0,7)}"')) {
  failures.push("Customer bill month picker must prevent selecting future months");
}
if (!appSource.includes('monthInput>today().slice(0,7)') &&
    !appSource.includes('monthInput > today().slice(0,7)')) {
  failures.push("Customer bill save must reject future months even if typed manually");
}

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
    const logoResponse = await page.request.get("http://localhost:4173/logo.svg");
    if (!logoResponse.ok()) failures.push("Unified MPW logo did not load");
    if (!(await page.locator(".brand-logo").isVisible())) failures.push("Brand logo is not visible in the app header");
    const logoAlt = await page.locator(".brand-logo").getAttribute("alt");
    if (!logoAlt?.includes("MUGHAL'S PURE WATER")) failures.push("Brand logo accessible text is missing");

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

    for (const id of ["email", "password"]) {
      const field = page.locator("#" + id);
      if (!(await field.isVisible())) failures.push("Missing login field: " + id);
      if ((await field.getAttribute("required")) === null) failures.push("Login field is not required: " + id);
      if (!(await page.locator('label[for="' + id + '"]').count())) failures.push("Login field has no visible label: " + id);
    }
    await page.locator("#email").fill("customer@example.com");
    await page.locator('button[onclick="showPasswordReset()"]').click();
    await page.locator("#passwordResetForm").waitFor({ state: "visible" });
    if ((await page.locator("#resetEmail").inputValue()) !== "customer@example.com") {
      failures.push("Password reset did not reuse the entered login email");
    }
    if ((await page.locator("#resetEmail").getAttribute("required")) === null) failures.push("Password reset email is not required");
    const resetRequestResult = await page.evaluate(async () => {
      const originalDb = window.db;
      let request = null;
      try {
        window.db = {
          auth: {
            resetPasswordForEmail: async (email, options) => {
              request = { email, redirectTo: options?.redirectTo || null };
              return { error: null };
            }
          }
        };
        await sendPasswordResetLink();
      } finally {
        window.db = originalDb;
      }
      return {
        request,
        expectedRedirect: new URL("./", window.location.href).href,
        message: document.querySelector("#loginMsg").textContent
      };
    });
    if (resetRequestResult.request?.email !== "customer@example.com" ||
        resetRequestResult.request?.redirectTo !== resetRequestResult.expectedRedirect) {
      failures.push("Password reset request does not use the entered email and app-base redirect URL");
    }
    if (!resetRequestResult.message.includes("اگر اس ای میل سے اکاؤنٹ موجود ہے")) {
      failures.push("Password reset does not show the non-enumerating confirmation message");
    }
    await page.locator('#passwordResetForm button[onclick="showLogin()"]').click();
    await page.locator("#loginForm").waitFor({ state: "visible" });

    await page.locator('button[onclick="showSignup()"]').click();
    await page.locator("#signupForm").waitFor({ state: "visible" });
    for (const id of ["signupName", "signupMobile", "signupAddress", "signupEmail", "signupPassword"]) {
      const field = page.locator("#" + id);
      if (!(await field.isVisible())) failures.push("Missing signup field: " + id);
      if ((await field.getAttribute("required")) === null) failures.push("Signup field is not required: " + id);
      if (!(await page.locator('label[for="' + id + '"]').count())) failures.push("Signup field has no visible label: " + id);
    }
    const signupMobileResult = await page.evaluate(async () => {
      const cases = [
        ["03001234567", "03001234567"],
        ["+92 300-1234567", "03001234567"],
        ["923001234567", "03001234567"],
        ["3001234567", "03001234567"],
        ["not-a-number", null]
      ];
      const normalizedCases = cases.map(([input]) => normalizePkMobile(input));
      const originalDb = window.db;
      let signupPayload = null;
      let signupCalls = 0;
      let successMessage = "";
      try {
        window.db = {
          auth: {
            signUp: async payload => {
              signupCalls++;
              signupPayload = payload;
              return {
                data: { user: { id: "smoke-test-user", identities: [{}] }, session: { access_token: "smoke-test" } },
                error: null
              };
            },
            signOut: async () => ({ error: null })
          }
        };
        document.querySelector("#signupName").value = "Smoke Test";
        document.querySelector("#signupMobile").value = "+92 300-1234567";
        document.querySelector("#signupAddress").value = "Smoke Test Address";
        document.querySelector("#signupEmail").value = "smoke-test@example.invalid";
        document.querySelector("#signupPassword").value = "SmokeTest123";
        await signupCustomer();
        successMessage = document.querySelector("#loginMsg").textContent;
        document.querySelector("#signupMobile").value = "not-a-valid-mobile";
        await signupCustomer();
      } finally {
        window.db = originalDb;
      }
      return {
        expectedCases: cases.map(x => x[1]),
        normalizedCases,
        sentMobile: signupPayload?.options?.data?.mobile || null,
        successMessage,
        invalidMobileBlocked: signupCalls === 1,
        invalidMobileMessage: document.querySelector("#loginMsg").textContent
      };
    });
    if (JSON.stringify(signupMobileResult.normalizedCases) !== JSON.stringify(signupMobileResult.expectedCases)) {
      failures.push("Pakistani mobile normalization does not cover local and international formats");
    }
    if (signupMobileResult.sentMobile !== "03001234567") {
      failures.push("Customer signup did not send the normalized Pakistani mobile to Supabase");
    }
    if (!signupMobileResult.successMessage.includes("درخواست موصول ہوگئی ہے")) {
      failures.push("Mock customer signup did not complete the pending-approval confirmation path");
    }
    if (!signupMobileResult.invalidMobileBlocked ||
        !signupMobileResult.invalidMobileMessage.includes("موبائل نمبر درست درج کریں")) {
      failures.push("Invalid Pakistani mobile number was not blocked before Supabase signup");
    }
    await page.evaluate(async () => {
      history.replaceState(null, document.title, window.location.pathname + "#type=recovery");
      await window.restoreSavedSession();
    });
    await page.locator("#passwordResetCompleteForm").waitFor({ state: "visible" });
    if ((await page.locator("#newPassword").getAttribute("required")) === null ||
        (await page.locator("#confirmNewPassword").getAttribute("required")) === null) {
      failures.push("Password recovery completion fields are not required");
    }
    const recoveryValidationResult = await page.evaluate(async () => {
      const originalDb = window.db;
      let updateCalls = 0;
      try {
        window.db = { auth: { updateUser: async () => { updateCalls++; return { error: null }; } } };
        document.querySelector("#newPassword").value = "short";
        document.querySelector("#confirmNewPassword").value = "short";
        await completePasswordReset();
        const shortPasswordBlocked = updateCalls === 0;
        document.querySelector("#newPassword").value = "LongPassword123";
        document.querySelector("#confirmNewPassword").value = "DifferentPassword123";
        await completePasswordReset();
        return {
          shortPasswordBlocked,
          mismatchBlocked: updateCalls === 0,
          mismatchMessage: document.querySelector("#loginMsg").textContent
        };
      } finally {
        window.db = originalDb;
      }
    });
    if (!recoveryValidationResult.shortPasswordBlocked || !recoveryValidationResult.mismatchBlocked ||
        !recoveryValidationResult.mismatchMessage.includes("دونوں پاس ورڈ ایک جیسے")) {
      failures.push("Password recovery does not block short or mismatched passwords before updateUser");
    }

    const recoveryCompletionResult = await page.evaluate(async () => {
      const originalDb = window.db;
      let updatedPassword = null;
      let signedOut = false;
      try {
        window.db = {
          auth: {
            updateUser: async values => {
              updatedPassword = values?.password || null;
              return { error: null };
            },
            signOut: async () => {
              signedOut = true;
              return { error: null };
            }
          }
        };
        document.querySelector("#newPassword").value = "NewSmokePassword123";
        document.querySelector("#confirmNewPassword").value = "NewSmokePassword123";
        await completePasswordReset();
      } finally {
        window.db = originalDb;
      }
      return {
        updatedPassword,
        signedOut,
        hash: window.location.hash,
        message: document.querySelector("#loginMsg").textContent
      };
    });
    if (recoveryCompletionResult.updatedPassword !== "NewSmokePassword123" ||
        !recoveryCompletionResult.signedOut ||
        recoveryCompletionResult.hash.includes("type=recovery")) {
      failures.push("Password recovery does not update the password, sign out, and clear the recovery URL");
    }
    if (!recoveryCompletionResult.message.includes("پاس ورڈ تبدیل ہوگیا ہے")) {
      failures.push("Password recovery completion does not show success confirmation");
    }
    await page.locator("#loginForm").waitFor({ state: "visible" });

    const customerAuthRouting = await page.evaluate(async () => {
      const originalDb = window.db;
      const originals = {
        loadCustomerPanel: window.loadCustomerPanel,
        startAdminCustomerRealtime: window.startAdminCustomerRealtime,
        loadTodaySummary: window.loadTodaySummary,
        loadExecutiveDashboard: window.loadExecutiveDashboard,
        refreshAdminSignupNotice: window.refreshAdminSignupNotice
      };
      let signOutCount = 0;
      const queryResult = data => {
        const chain = {
          select() { return chain; },
          eq() { return chain; },
          maybeSingle: async () => ({ data, error: null })
        };
        return chain;
      };
      const resetPanels = () => {
        document.querySelector("#login").classList.remove("hidden");
        document.querySelector("#app").classList.add("hidden");
        document.querySelector("#adminPanel").classList.add("hidden");
        document.querySelector("#customerPanel").classList.add("hidden");
      };
      const runScenario = async (profile, customer) => {
        resetPanels();
        window.db = {
          auth: {
            getUser: async () => ({ data: { user: { id: "smoke-auth-user" } }, error: null }),
            signOut: async () => { signOutCount++; return { error: null }; }
          },
          from: table => queryResult(table === "profiles" ? profile : customer)
        };
        await loadApp();
        return {
          loginHidden: document.querySelector("#login").classList.contains("hidden"),
          adminVisible: !document.querySelector("#adminPanel").classList.contains("hidden"),
          customerVisible: !document.querySelector("#customerPanel").classList.contains("hidden"),
          message: document.querySelector("#loginMsg").textContent
        };
      };
      try {
        window.loadCustomerPanel = async () => {};
        window.startAdminCustomerRealtime = () => {};
        window.loadTodaySummary = async () => {};
        window.loadExecutiveDashboard = async () => {};
        window.refreshAdminSignupNotice = async () => {};
        const admin = await runScenario({ role: "admin", full_name: "Admin" }, null);
        const activeCustomer = await runScenario(
          { role: "customer", full_name: "Customer" },
          { id: 7, name: "Customer", is_active: true }
        );
        // RLS hides both the pending customer's profile and customer row.
        // The real client therefore receives null for both lookups.
        const pendingCustomer = await runScenario(null, null);
        const unlinkedUser = await runScenario(null, null);
        return { admin, activeCustomer, pendingCustomer, unlinkedUser, signOutCount };
      } finally {
        window.db = originalDb;
        window.loadCustomerPanel = originals.loadCustomerPanel;
        window.startAdminCustomerRealtime = originals.startAdminCustomerRealtime;
        window.loadTodaySummary = originals.loadTodaySummary;
        window.loadExecutiveDashboard = originals.loadExecutiveDashboard;
        window.refreshAdminSignupNotice = originals.refreshAdminSignupNotice;
      }
    });
    if (!customerAuthRouting.admin.loginHidden || !customerAuthRouting.admin.adminVisible ||
        customerAuthRouting.admin.customerVisible) {
      failures.push("Admin authentication does not route exclusively to the admin panel");
    }
    if (!customerAuthRouting.activeCustomer.loginHidden || !customerAuthRouting.activeCustomer.customerVisible ||
        customerAuthRouting.activeCustomer.adminVisible) {
      failures.push("Approved customer authentication does not route exclusively to the customer portal");
    }
    if (customerAuthRouting.pendingCustomer.loginHidden || customerAuthRouting.pendingCustomer.customerVisible ||
        customerAuthRouting.pendingCustomer.adminVisible ||
        !customerAuthRouting.pendingCustomer.message.includes("منتظم کی منظوری کا انتظار کریں")) {
      failures.push("RLS-hidden pending customer is not signed out and shown the approval-wait message");
    }
    if (customerAuthRouting.unlinkedUser.loginHidden || customerAuthRouting.unlinkedUser.adminVisible ||
        customerAuthRouting.unlinkedUser.customerVisible || customerAuthRouting.signOutCount < 2) {
      failures.push("Unlinked or unapproved authentication is not signed out and blocked");
    }

    const customerSignupRealtimeSafety = await page.evaluate(() => {
      const source = String(startAdminCustomerRealtime);
      return {
        usesSafeEventTable: source.includes('table:"customer_signup_events"'),
        avoidsSensitiveCustomerTable: !source.includes('table:"customers"')
      };
    });
    if (!customerSignupRealtimeSafety.usesSafeEventTable ||
        !customerSignupRealtimeSafety.avoidsSensitiveCustomerTable) {
      failures.push("Customer signup Realtime must subscribe only to the admin-only minimal event table");
    }

    const adminNavigation = await page.evaluate(async () => {
      const panel = document.querySelector("#adminPanel");
      const tiles = document.querySelector("#homeTiles");
      const dashboard = document.querySelector("#dashboard");
      const module = document.querySelector("#module");
      if (!panel || !tiles || !dashboard || !module || typeof window.openModule !== "function") {
        return { missing: true };
      }
      panel.classList.remove("hidden");
      tiles.classList.remove("hidden");
      dashboard.classList.remove("hidden");
      module.classList.add("hidden");
      await window.openModule("__layout_smoke_test__");
      const state = {
        missing: false,
        moduleOpen: panel.classList.contains("module-open"),
        moduleVisible: !module.classList.contains("hidden"),
        tileDisplay: getComputedStyle(tiles).display,
        tilePosition: getComputedStyle(tiles).position
      };
      panel.classList.remove("module-open");
      module.classList.add("hidden");
      dashboard.classList.remove("hidden");
      tiles.classList.remove("hidden");
      return state;
    });
    if (adminNavigation.missing || !adminNavigation.moduleOpen || !adminNavigation.moduleVisible) {
      failures.push("Admin module navigation state did not activate correctly");
    }
    if (viewport.width <= 699 && adminNavigation.tileDisplay !== "none") {
      failures.push("Mobile admin tile grid should hide while a module is open");
    }
    if (viewport.width >= 1100 &&
        (adminNavigation.tileDisplay === "none" || adminNavigation.tilePosition !== "sticky")) {
      failures.push("Desktop admin navigation rail should remain visible and sticky");
    }

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

    const deliveryConfirmation = await page.evaluate(() => ({
      warning: window.deliveryConfirmationSummary({ out: 120, diff: 2, caps: 3, capAmount: 30 }),
      normal: window.deliveryConfirmationSummary({ out: 10, diff: 0, caps: 0, capAmount: 0 })
    }));
    if (!deliveryConfirmation.warning.includes("بوتلوں کا فرق: 2") ||
        !deliveryConfirmation.warning.includes("خراب ڈھکن: 3") ||
        !deliveryConfirmation.warning.includes("ڈلیوری کی بڑی مقدار: 120")) {
      failures.push("19L delivery confirmation summary is missing important checks");
    }
    if (deliveryConfirmation.normal !== "") {
      failures.push("Normal 19L delivery should not trigger an extra confirmation");
    }

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
            order() { return chain; },
            limit() { return chain; },
            contains() { return chain; },
            update(values) { updates.push({ table, values }); return chain; },
            then(resolve, reject) { return Promise.resolve({ data: mockData[table] || [], error: null }).then(resolve, reject); }
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
      const specialAboveDefaultBlocked = updates.length === 0;
      document.querySelector("#psSpecial_1").value = "290";
      await window.saveProductSettings(1, "500ml");
      mockData.product_settings[0].default_rate = 300;
      mockData.product_settings[0].special_100_rate = 290;
      await window.salesModule();
      document.querySelector("#saleQty").value = "100";
      window.salePricePreview(true, false);
      const bulkPrice = document.querySelector("#saleUnitPrice").value;
      document.querySelector("#saleQty").value = "99";
      window.salePricePreview(true, false);
      const normalPrice = document.querySelector("#saleUnitPrice").value;
      document.querySelector("#saleType").value = "6L";
      window.salePricePreview(false, true);
      const sixLiterMinimumPrice = document.querySelector("#saleUnitPrice").value;
      const sixLiterDisabled = document.querySelector("#saleUnitPrice").disabled;
      const sixLiterMinAttribute = document.querySelector("#saleUnitPrice").min;
      document.querySelector("#saleUnitPrice").value = "60";
      window.salePricePreview(false, false);
      const sixLiterCustomPrice = document.querySelector("#saleUnitPrice").value;
      document.querySelector("#saleUnitPrice").value = "49";
      window.salePricePreview(false, false);
      const sixLiterBelowFloorReset = document.querySelector("#saleUnitPrice").value;
      return {
        rendered,
        belowFloorBlocked,
        specialAboveDefaultBlocked,
        saved: updates.length === 1 && updates[0].table === "product_settings",
        savedDefault: updates[0]?.values?.default_rate,
        savedSpecial: updates[0]?.values?.special_100_rate,
        bulkPrice,
        normalPrice,
        sixLiterMinimumPrice,
        sixLiterDisabled,
        sixLiterMinAttribute,
        sixLiterCustomPrice,
        sixLiterBelowFloorReset
      };
    });
    if (!settingsResult.rendered) failures.push("Admin settings price controls did not render");
    if (!settingsResult.belowFloorBlocked) failures.push("Admin settings allowed a carton price below Rs.280");
    if (!settingsResult.specialAboveDefaultBlocked) failures.push("Admin settings allowed a bulk special price above the default price");
    if (!settingsResult.saved || settingsResult.savedDefault !== 300 || settingsResult.savedSpecial !== 290) {
      failures.push("Admin settings did not save valid price changes correctly");
    }
    if (settingsResult.bulkPrice !== "290") failures.push("100+ carton special price was not applied");
    if (settingsResult.normalPrice !== "300") failures.push("Default carton price was not restored below 100 units");
    if (settingsResult.sixLiterMinimumPrice !== "55" || settingsResult.sixLiterDisabled ||
        settingsResult.sixLiterMinAttribute !== "55" || settingsResult.sixLiterCustomPrice !== "60" ||
        settingsResult.sixLiterBelowFloorReset !== "55") {
      failures.push("6L minimum and editable sale price rules are incorrect");
    }

    const labelResult = await page.evaluate(() => {
      const body = document.querySelector("#moduleBody");
      body.innerHTML = '<div><input id="rawPurchaseQty" type="number" placeholder="مقدار"></div>' +
        '<div><select id="tankEntryKind"><option>خریداری</option></select></div>' +
        '<div><input id="psDefault_3" type="number"></div>' +
        '<label><input id="labelTestCheckbox" type="checkbox"> چیک باکس</label>';
      if (typeof window.enhanceModuleControls !== "function") return { helper: false };
      window.enhanceModuleControls(body);
      window.enhanceModuleControls(body);
      const getLabel = id => body.querySelector('label[for="' + id + '"]')?.textContent?.trim() || "";
      return {
        helper: true,
        raw: getLabel("rawPurchaseQty"),
        tank: getLabel("tankEntryKind"),
        price: getLabel("psDefault_3"),
        rawLabelCount: body.querySelectorAll('label[for="rawPurchaseQty"]').length,
        tankLabelCount: body.querySelectorAll('label[for="tankEntryKind"]').length,
        checkboxWrapped: Boolean(body.querySelector("#labelTestCheckbox")?.closest("label"))
      };
    });
    if (!labelResult.helper) failures.push("Admin field-label helper is unavailable");
    if (!labelResult.raw.includes("مقدار")) failures.push("Raw-material quantity field label is missing");
    if (!labelResult.tank.includes("اندراج کی قسم")) failures.push("Tanker entry type label is missing");
    if (!labelResult.price.includes("معمول کی فی یونٹ قیمت")) failures.push("Dynamic product price label is missing");
    if (labelResult.rawLabelCount !== 1 || labelResult.tankLabelCount !== 1) failures.push("Admin field labels are duplicated");
    if (!labelResult.checkboxWrapped) failures.push("Existing checkbox label was changed unexpectedly");

    const feedbackResult = await page.evaluate(async () => {
      let nativeAlertCount = 0;
      const originalAlert = window.alert;
      window.alert = () => { nativeAlertCount++; };
      window.shareCustomerMessage("invalid", "test", "sms");
      window.shareCustomerTestWhatsApp(999999);
      window.shareCustomerTestSMS(999999);
      window.shareCurrentBill("sms");
      window.shareCurrentDelivery("sms");
      await window.installMughalApp();
      const result = {
        nativeAlertCount,
        moduleMessage: document.querySelector("#moduleMsg")?.textContent || "",
        toast: document.querySelector("#appToast")?.textContent || "",
        toastAccessible: document.querySelector("#appToast")?.getAttribute("aria-live") === "polite"
      };
      window.alert = originalAlert;
      return result;
    });
    if (feedbackResult.nativeAlertCount !== 0) failures.push("Business feedback still opens blocking native alerts");
    if (!feedbackResult.moduleMessage.includes("پہلے ڈلیوری محفوظ کریں")) failures.push("Delivery validation feedback is not shown in the app");
    if (!feedbackResult.toast.includes("Chrome مینو") && !feedbackResult.toast.includes("انسٹال")) failures.push("PWA install guidance toast is missing");
    if (!feedbackResult.toastAccessible) failures.push("PWA install toast is not announced accessibly");

    const customerStatusResult = await page.evaluate(() => {
      const body = document.querySelector("#moduleBody");
      body.innerHTML = '<input id="customerSearch"><div id="moduleTable"></div><div id="pendingCustomers"></div>';
      const previousCustomers = customerList;
      customerList = [
        { id: 901, name: "Pending Example", customer_code: "C901", mobile: "03000000001", is_active: false, approved_at: null },
        { id: 902, name: "Disabled Example", customer_code: "C902", mobile: "03000000002", is_active: false, approved_at: "2026-11-01T10:00:00Z" },
        { id: 903, name: "Active Example", customer_code: "C903", mobile: "03000000003", is_active: true, approved_at: "2026-11-02T10:00:00Z" }
      ];
      renderPendingCustomers();
      renderCustomers();
      const pendingRows = document.querySelectorAll("#pendingCustomers tr").length;
      const tableText = document.querySelector("#moduleTable")?.textContent || "";
      const pendingText = document.querySelector("#pendingCustomers")?.textContent || "";
      const result = {
        pendingRows,
        pendingOnly: pendingText.includes("Pending Example") && !pendingText.includes("Disabled Example"),
        pendingLabel: customerStatusLabel(customerList[0]),
        disabledLabel: customerStatusLabel(customerList[1]),
        activeLabel: customerStatusLabel(customerList[2]),
        approvalAction: tableText.includes("منظوری دیں"),
        reactivateAction: tableText.includes("دوبارہ فعال کریں"),
        deactivateAction: tableText.includes("غیر فعال کریں")
      };
      customerList = previousCustomers;
      return result;
    });
    if (customerStatusResult.pendingRows !== 2 || !customerStatusResult.pendingOnly) failures.push("Deactivated customers are incorrectly shown in the pending-approval list");
    if (customerStatusResult.pendingLabel !== "منظوری کے منتظر" ||
        customerStatusResult.disabledLabel !== "غیر فعال" ||
        customerStatusResult.activeLabel !== "فعال") {
      failures.push("Customer account status labels do not distinguish pending, disabled and active states");
    }
    if (!customerStatusResult.approvalAction || !customerStatusResult.reactivateAction || !customerStatusResult.deactivateAction) {
      failures.push("Customer access actions do not match the account approval state");
    }

    const capBalanceResult = await page.evaluate(async () => {
      const root = document.querySelector("#moduleBody");
      root.innerHTML = '<div id="rawStockBalance"></div><div id="moduleTable"></div>';
      const originalFetchAll = window.financeFetchAll;
      window.financeFetchAll = async (table) => {
        if (table === "raw_material_purchases") return [
          { record_type: "opening_stock", material_type: "cap_19l", purchase_date: "2026-11-10", quantity: 11, unit: "piece", total_amount: 11, supplier: null }
        ];
        if (table === "production") return [];
        if (table === "customer_19l_deliveries") return [
          { delivery_date: "2026-11-10", bottles_delivered: 10, successful_bottles: 8, damaged_caps: 1 }
        ];
        return [];
      };
      await loadRawMaterialPurchases();
      const text = document.querySelector("#rawStockBalance")?.textContent || "";
      window.financeFetchAll = originalFetchAll;
      return { text, hasZeroBalance: /19L ڈھکن[\s\S]*?باقی:\s*0 عدد/.test(text) };
    });
    if (!capBalanceResult.hasZeroBalance) failures.push("19L cap balance does not subtract all delivered bottles and damaged-cap replacements after opening date");

    const inactiveBillingResult = await page.evaluate(() => {
      const active = { is_active: true, approved_at: "2026-11-01T00:00:00Z" };
      const inactiveApproved = { is_active: false, approved_at: "2026-11-01T00:00:00Z" };
      const pending = { is_active: false, approved_at: null };
      return {
        activeBillable: isBillableCustomer(active),
        inactiveBillable: isBillableCustomer(inactiveApproved),
        pendingBillable: isBillableCustomer(pending),
        activeCanReceiveNotice: customerCanReceiveAppNotice(active),
        inactiveCanReceiveNotice: customerCanReceiveAppNotice(inactiveApproved),
        inactiveOptionLabel: customerOptions([inactiveApproved]).includes("غیر فعال (سابقہ حساب)")
      };
    });
    if (!inactiveBillingResult.activeBillable || !inactiveBillingResult.inactiveBillable || inactiveBillingResult.pendingBillable) {
      failures.push("Billing eligibility does not include active and previously approved customers while excluding pending signups");
    }
    if (!inactiveBillingResult.activeCanReceiveNotice || inactiveBillingResult.inactiveCanReceiveNotice) {
      failures.push("Inactive customers are not correctly excluded from automatic app notifications");
    }
    if (!inactiveBillingResult.inactiveOptionLabel) failures.push("Inactive customer billing option is not clearly labeled");

    const finishedOpeningResult = await page.evaluate(() => ({
      firstEntry: canUpdateFinishedOpeningStock(null, "2026-11-11"),
      sameDateCorrection: canUpdateFinishedOpeningStock({ id: 1, entry_date: "2026-11-11" }, "2026-11-11"),
      differentDateRejected: !canUpdateFinishedOpeningStock({ id: 1, entry_date: "2026-11-10" }, "2026-11-11")
    }));
    if (!finishedOpeningResult.firstEntry || !finishedOpeningResult.sameDateCorrection || !finishedOpeningResult.differentDateRejected) {
      failures.push("Finished-goods opening stock can be duplicated across different dates");
    }

    const workerStatusResult = await page.evaluate(() => {
      const active = { is_active: true };
      const inactive = { is_active: false };
      return {
        activeLabel: workerStatusLabel(active),
        inactiveLabel: workerStatusLabel(inactive),
        deactivateAction: workerStatusActionLabel(active),
        reactivateAction: workerStatusActionLabel(inactive),
        statusToggleAvailable: typeof toggleWorkerStatus === "function"
      };
    });
    if (workerStatusResult.activeLabel !== "فعال" ||
        workerStatusResult.inactiveLabel !== "غیر فعال" ||
        workerStatusResult.deactivateAction !== "غیر فعال کریں" ||
        workerStatusResult.reactivateAction !== "دوبارہ فعال کریں" ||
        !workerStatusResult.statusToggleAvailable) {
      failures.push("Worker active/inactive status controls are not wired correctly");
    }

    const financePaymentValidation = await page.evaluate(() => ({
      capitalRequiresMethod: !isValidFinanceEntryPaymentMethod("capital_in", ""),
      capitalAcceptsCash: isValidFinanceEntryPaymentMethod("capital_in", "نقد"),
      interestAcceptsBank: isValidFinanceEntryPaymentMethod("interest_income", "بینک"),
      ownerWithdrawalAcceptsCash: isValidFinanceEntryPaymentMethod("owner_withdrawal", "cash"),
      nonCashAdjustmentCanOmitMethod: isValidFinanceEntryPaymentMethod("depreciation_expense", ""),
      creditIsRejected: !isValidFinanceEntryPaymentMethod("loan_given", "ادھار")
    }));
    if (!financePaymentValidation.capitalRequiresMethod ||
        !financePaymentValidation.capitalAcceptsCash ||
        !financePaymentValidation.interestAcceptsBank ||
        !financePaymentValidation.ownerWithdrawalAcceptsCash ||
        !financePaymentValidation.nonCashAdjustmentCanOmitMethod ||
        !financePaymentValidation.creditIsRejected) {
      failures.push("Finance entries do not validate cash/bank methods consistently");
    }

    const serviceWorkerCacheResult = await page.evaluate(async () => {
      const response = await fetch("./SW.js", { cache: "no-store" });
      const source = await response.text();
      return {
        fetchAvailable: response.ok,
        shellOnly: source.includes("APP_SHELL_PATHS.has(url.pathname)"),
        queryExcluded: source.includes("isShellAsset && !url.search"),
        cacheCleanupScoped: source.includes('key.startsWith("mughals-pure-water-")'),
        notificationUsesAppBase: source.includes('new URL("./", self.location.href)'),
        notificationScopeChecked: source.includes("clientUrl.pathname.startsWith(appBase.pathname)"),
        oldBroadCacheRemoved: !source.includes("cache.put(request,copy)")
      };
    });
    if (!serviceWorkerCacheResult.fetchAvailable ||
        !serviceWorkerCacheResult.shellOnly ||
        !serviceWorkerCacheResult.queryExcluded ||
        !serviceWorkerCacheResult.cacheCleanupScoped ||
        !serviceWorkerCacheResult.notificationUsesAppBase ||
        !serviceWorkerCacheResult.notificationScopeChecked ||
        !serviceWorkerCacheResult.oldBroadCacheRemoved) {
      failures.push("Service worker cache is not restricted to static shell assets and this app's own cache namespace");
    }

    const ownerMonthDateRange = await page.evaluate(() => {
      const source = document.documentElement.innerHTML;
      const start = source.indexOf("async function loadOwnerWithdrawals()");
      const end = source.indexOf("\n}", start);
      const body = source.slice(start, end > start ? end : start + 1800);
      return {
        usesLocalMonthRange: body.includes("monthDateRange(month).end"),
        avoidsUtcDayShift: !body.includes("toISOString().slice(0,10)")
      };
    });
    if (!ownerMonthDateRange.usesLocalMonthRange || !ownerMonthDateRange.avoidsUtcDayShift) {
      failures.push("Owner withdrawal monthly history must use the app's local month range, not UTC ISO date conversion");
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
