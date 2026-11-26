import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import webpush from "npm:web-push@3.6.7";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

async function setPushResult(admin: ReturnType<typeof createClient>, notificationId: number, sent: boolean, errorMessage: string | null) {
  const { error: rpcError } = await admin.rpc("mark_customer_bill_push_result", {
    p_notification_id: notificationId,
    p_sent: sent,
    p_error: errorMessage,
  });
  if (!rpcError) return;

  console.error("Push result RPC failed; attempting direct status update", rpcError.message);
  const values = sent
    ? { push_sent_at: new Date().toISOString(), push_queue_eligible: false, push_error: null }
    : { push_error: String(errorMessage || "Push delivery failed").slice(0, 500) };
  const { error: updateError } = await admin
    .from("customer_notifications")
    .update(values)
    .eq("id", notificationId);
  if (updateError) throw new Error("Could not record push result: " + updateError.message);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const token = req.headers.get("x-internal-token") || "";
  if (!token) return json({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!supabaseUrl || !serviceKey) return json({ error: "Push server configuration is incomplete" }, 503);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: validToken, error: tokenError } = await admin.rpc(
    "verify_mpw_bill_push_cron_token",
    { p_token: token },
  );
  if (tokenError || validToken !== true) {
    console.error("Internal bill-push authentication failed", tokenError?.message || "Invalid token");
    return json({ error: "Unauthorized" }, 401);
  }

  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY") || "";
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY") || "";

  if (!publicKey || !privateKey) {
    console.error("VAPID keys are not configured for scheduled bill push");
    return json({ error: "Push server keys are not configured" }, 503);
  }
  try {
    webpush.setVapidDetails(
      "https://taqi53056.github.io/mughals-pure-water/",
      publicKey,
      privateKey,
    );
  } catch (error) {
    console.error("Scheduled bill-push VAPID configuration is invalid", String(error));
    return json({ error: "Push server keys are invalid" }, 503);
  }

  const { data: notifications, error: claimError } = await admin.rpc(
    "claim_pending_customer_bill_push",
    { p_limit: 50 },
  );
  if (claimError) {
    console.error("Pending bill-push claim failed", claimError.message);
    return json({ error: "Could not claim pending bill notifications" }, 500);
  }
  if (!notifications?.length) {
    return json({ processed: 0, sent: 0, failed: 0, skipped: 0, vapid_configured: true });
  }

  let sent = 0;
  let failed = 0;
  let skipped = 0;

  for (const notification of notifications || []) {
    const notificationId = Number(notification.notification_id);
    const customerId = Number(notification.customer_id);

    const { data: customer, error: customerError } = await admin
      .from("customers")
      .select("id,is_active")
      .eq("id", customerId)
      .maybeSingle();

    if (customerError || !customer || customer.is_active !== true) {
      await admin.from("customer_notifications")
        .update({ push_queue_eligible: false, push_error: "Customer is inactive or unavailable" })
        .eq("id", notificationId);
      skipped++;
      continue;
    }

    const { data: subscriptions, error: subError } = await admin
      .from("customer_push_subscriptions")
      .select("id,endpoint,p256dh,auth")
      .eq("customer_id", customerId)
      .eq("is_active", true);

    if (subError) {
      try {
        await setPushResult(admin, notificationId, false, "Subscription lookup failed: " + subError.message);
      } catch (error) {
        console.error("Could not record subscription lookup failure", String(error));
      }
      failed++;
      continue;
    }

    if (!subscriptions?.length) {
      try {
        await setPushResult(admin, notificationId, false, "No active device subscription");
      } catch (error) {
        console.error("Could not record missing subscription", String(error));
      }
      failed++;
      continue;
    }

    const payload = JSON.stringify({
      title: String(notification.title || "ماہانہ بل تیار ہے").slice(0, 120),
      body: String(notification.message || "").slice(0, 1200),
      url: "https://taqi53056.github.io/mughals-pure-water/",
      tag: "mpw-bill-" + customerId + "-" + notificationId,
    });

    let customerSent = 0;
    const failures: string[] = [];

    for (const sub of subscriptions) {
      try {
        await webpush.sendNotification({
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        }, payload, { TTL: 86400, urgency: "high" });
        customerSent++;
      } catch (error) {
        const status = Number((error as { statusCode?: number })?.statusCode || 0);
        failures.push(String(status || "network"));
        console.error("Scheduled bill push failed", notificationId, status, String(error));

        if (status === 404 || status === 410) {
          const { error: deactivateError } = await admin
            .from("customer_push_subscriptions")
            .update({ is_active: false, updated_at: new Date().toISOString() })
            .eq("id", sub.id);
          if (deactivateError) console.error("Expired subscription cleanup failed", deactivateError.message);
        }
      }
    }

    if (customerSent > 0) {
      try {
        await setPushResult(admin, notificationId, true, null);
        sent += customerSent;
      } catch (error) {
        console.error("Push was delivered but its status could not be saved", notificationId, String(error));
        failed++;
      }
    } else {
      try {
        await setPushResult(admin, notificationId, false, "Push delivery failed for all registered devices: " + failures.join(", "));
      } catch (error) {
        console.error("Could not record push delivery failure", notificationId, String(error));
      }
      failed++;
    }
  }

  return json({ processed: (notifications || []).length, sent, failed, skipped });
});
