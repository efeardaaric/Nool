import { isAuthorizedServerRequest } from "../_shared/authorize.ts";
// Nool — Scheduled curiosity / re-engagement enqueue
//
// Invoked by Supabase Cron / external scheduler with service role.
// Inserts `notifications` rows (type=curiosity); pair with Database Webhook
// on notifications INSERT → fcm-notify for push delivery.
//
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto)
// Deploy: supabase functions deploy curiosity-cron --no-verify-jwt
//
// Cron example (Dashboard → Edge Functions → Schedules):
//   POST https://<ref>.supabase.co/functions/v1/curiosity-cron
//   Header: Authorization: Bearer <SERVICE_ROLE_KEY>
//   Body: { "limit": 200 }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-nool-webhook-secret",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }

    if (!isAuthorizedServerRequest(req)) {
      return json({ error: "Unauthorized" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Missing SUPABASE_URL / SERVICE_ROLE_KEY" }, 500);
    }

    let limit = 200;
    let inactiveHours = 18;
    let cooldownHours = 20;
    try {
      const body = await req.json() as Record<string, unknown>;
      if (typeof body.limit === "number") limit = body.limit;
      if (typeof body.inactive_hours === "number") {
        inactiveHours = body.inactive_hours;
      }
      if (typeof body.cooldown_hours === "number") {
        cooldownHours = body.cooldown_hours;
      }
    } catch {
      // empty body ok
    }

    const supabase = createClient(supabaseUrl, serviceKey);
    const { data, error } = await supabase.rpc("enqueue_curiosity_teasers", {
      p_limit: limit,
      p_inactive_hours: inactiveHours,
      p_cooldown_hours: cooldownHours,
    });

    if (error) {
      console.error("enqueue_curiosity_teasers:", error);
      return json({ error: error.message }, 500);
    }

    return json({ ok: true, enqueued: data ?? 0 }, 200);
  } catch (e) {
    console.error("curiosity-cron:", e);
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
