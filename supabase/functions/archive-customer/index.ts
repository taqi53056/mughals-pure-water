import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response(405, { error: "POST required" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization");
  if (!url || !anonKey || !serviceKey || !authorization) {
    return response(500, { error: "Server configuration or authorization is missing." });
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const adminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return response(401, { error: "Valid sign-in required." });
  const { data: isAdmin, error: roleError } = await userClient.rpc("is_admin");
  if (roleError || isAdmin !== true) return response(403, { error: "Admin access required." });

  let body: Record<string, unknown>;
  try { body = await req.json(); }
  catch { return response(400, { error: "Invalid JSON body." }); }

  let job: Record<string, unknown> | null = null;
  if (body.customer_id !== undefined && body.customer_id !== null) {
    const customerId = Number(body.customer_id);
    if (!Number.isSafeInteger(customerId) || customerId <= 0) {
      return response(400, { error: "A valid customer_id is required." });
    }
    const { data, error } = await userClient.rpc("prepare_customer_archive", {
      p_customer_id: customerId
    });
    if (error) return response(400, { error: error.message });
    job = data as Record<string, unknown>;
  } else if (body.job_id !== undefined && body.job_id !== null) {
    const jobId = Number(body.job_id);
    if (!Number.isSafeInteger(jobId) || jobId <= 0) {
      return response(400, { error: "A valid job_id is required." });
    }
    const { data, error } = await adminClient
      .from("customer_archive_jobs")
      .select("id,archive_id,auth_user_id,status")
      .eq("id", jobId)
      .eq("status", "pending_auth_deletion")
      .single();
    if (error || !data) return response(404, { error: "Pending archive job not found." });
    job = data as Record<string, unknown>;
  } else {
    return response(400, { error: "customer_id or job_id is required." });
  }

  const jobId = Number(job?.job_id ?? job?.id);
  const archiveId = Number(job?.archive_id);
  const authUserId = typeof job?.auth_user_id === "string" ? job.auth_user_id : null;
  if (!Number.isSafeInteger(jobId) || jobId <= 0) {
    return response(500, { error: "Archive job could not be confirmed." });
  }

  if (authUserId) {
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(authUserId);
    if (deleteError && !/user.*not found|not found/i.test(deleteError.message)) {
      await adminClient.from("customer_archive_jobs").update({
        status: "pending_auth_deletion",
        last_error: deleteError.message
      }).eq("id", jobId);
      return response(200, {
        status: "pending_auth_deletion",
        auth_deleted: false,
        job_id: jobId,
        archive_id: archiveId,
        error: "Personal records were archived, but authentication cleanup needs retry."
      });
    }
  }

  const { error: finishError } = await adminClient
    .from("customer_archive_jobs")
    .update({
      status: "completed",
      auth_user_id: null,
      last_error: null,
      completed_at: new Date().toISOString()
    })
    .eq("id", jobId);

  if (finishError) {
    return response(200, {
      status: "pending_auth_deletion",
      auth_deleted: Boolean(authUserId),
      job_id: jobId,
      archive_id: archiveId,
      error: "Auth cleanup succeeded or was unnecessary, but archive job status needs reconciliation."
    });
  }

  return response(200, {
    ok: true,
    status: "completed",
    job_id: jobId,
    archive_id: archiveId,
    archive_ref: job?.archive_ref ?? null
  });
});
