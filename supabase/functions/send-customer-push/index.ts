import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://taqi53056.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = req.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY") || "";
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY") || "";
  if (!supabaseUrl || !anonKey) return json({ error: "Push server configuration is incomplete" }, 503);
  if (!publicKey || !privateKey) return json({ error: "Push server keys are not configured" }, 503);

  const token = authorization.slice(7);
  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

  // Check the same database-side admin allow-list used by the app's RLS rules.
  const { data: isAdmin, error: adminCheckError } = await authClient.rpc("is_admin");
  if (adminCheckError) {
    console.error("Admin permission check failed", adminCheckError.message);
    return json({ error: "Admin permission check failed" }, 500);
  }
  if (isAdmin !== true) return json({ error: "Admin access required" }, 403);

  const admin = serviceKey ? createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }) : null;
  let input: { customer_id?: number; title?: string; message?: string };
  try { input = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const customerId = Number(input.customer_id);
  const title = String(input.title || "").slice(0, 120);
  const message = String(input.message || "").slice(0, 1200);
  if (!Number.isSafeInteger(customerId) || customerId < 1 || !title || !message) {
    return json({ error: "customer_id, title and message are required" }, 400);
  }

  // Read through the authenticated admin session so the database's admin RLS policy applies.
  const { data: customer, error: customerError } = await authClient
    .from("customers").select("id,is_active").eq("id", customerId).maybeSingle();
  if (customerError || !customer || customer.is_active !== true) {
    console.error("Push customer lookup failed", customerError?.message || "Active customer not found");
    return json({ error: "Active customer not found" }, 404);
  }

  const { data: subscriptions, error: subError } = await authClient
    .from("customer_push_subscriptions")
    .select("id,endpoint,p256dh,auth")
    .eq("customer_id", customerId)
    .eq("is_active", true);
  if (subError) {
    console.error("Push subscription lookup failed", subError.message);
    return json({ error: "Could not load subscriptions" }, 500);
  }
  if (!subscriptions?.length) return json({ sent: 0, expired: 0, total: 0, reason: "No active device subscription" });

  webpush.setVapidDetails(
    "https://taqi53056.github.io/mughals-pure-water/",
    publicKey,
    privateKey,
  );

  const payload = JSON.stringify({
    title,
    body: message,
    url: "https://taqi53056.github.io/mughals-pure-water/",
    tag: "mpw-" + customerId + "-" + Date.now(),
  });

  let sent = 0;
  let expired = 0;
  const failures: number[] = [];
  for (const sub of subscriptions) {
    try {
      await webpush.sendNotification({
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth },
      }, payload, { TTL: 86400, urgency: "high" });
      sent++;
    } catch (error) {
      const status = Number((error as { statusCode?: number })?.statusCode || 0);
      failures.push(status);
      console.error("Push delivery failed", status, String(error));
      if (status === 404 || status === 410) {
        if (admin) {
          const { error: deactivateError } = await admin.from("customer_push_subscriptions")
            .update({ is_active: false, updated_at: new Date().toISOString() })
            .eq("id", sub.id);
          if (deactivateError) console.error("Expired subscription cleanup failed", deactivateError.message);
        }
        expired++;
      }
    }
  }

  if (sent === 0) {
    return json({ sent, expired, total: subscriptions.length, failures, error: "Push delivery failed for all registered devices" }, 502);
  }
  return json({ sent, expired, total: subscriptions.length, failures });
});
