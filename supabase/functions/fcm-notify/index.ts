import { isAuthorizedServerRequest } from "../_shared/authorize.ts";
// Nool — FCM v1 push for social events
//
// Accepts Database Webhook payloads from:
//   - public.notifications INSERT  (preferred — friend, DM, group, curiosity, …)
//   - public.squads INSERT         (legacy squad invite)
//
// Curiosity rows: skipped when curiosity_push_enabled=false or last_active_at < 6h.
//
// Secrets:
//   FIREBASE_SERVICE_ACCOUNT_JSON  — full Firebase service-account JSON string
//   SUPABASE_URL                   — auto in Edge Functions
//   SUPABASE_SERVICE_ROLE_KEY      — auto in Edge Functions
//
// Deploy: supabase functions deploy fcm-notify --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.9.6/index.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-nool-webhook-secret",
};

interface ServiceAccount {
  project_id: string;
  private_key: string;
  client_email: string;
}

interface WebhookPayload {
  type?: string;
  table?: string;
  schema?: string;
  record?: Record<string, unknown>;
  old_record?: Record<string, unknown> | null;
}

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

    const payload = (await req.json()) as WebhookPayload;
    const record = payload.record;
    if (!record) {
      return json({ error: "Missing record" }, 400);
    }

    if (payload.type && payload.type !== "INSERT") {
      return json({ skipped: true, reason: `event ${payload.type}` }, 200);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Missing SUPABASE_URL / SERVICE_ROLE_KEY" }, 500);
    }

    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!saRaw) {
      return json({ error: "FIREBASE_SERVICE_ACCOUNT_JSON not set" }, 500);
    }

    let sa: ServiceAccount;
    try {
      sa = JSON.parse(saRaw) as ServiceAccount;
    } catch {
      return json({ error: "Invalid FIREBASE_SERVICE_ACCOUNT_JSON" }, 500);
    }
    if (!sa.project_id || !sa.private_key || !sa.client_email) {
      return json({ error: "Service account missing required fields" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    let userId: string | undefined;
    let title: string;
    let body: string;
    let data: Record<string, string>;

    if (payload.table === "notifications") {
      userId = record.user_id as string | undefined;
      title = (record.title as string) || "Nool";
      body = (record.body as string) || "";
      const rawData = (record.data as Record<string, unknown>) || {};
      data = {
        type: String(record.type ?? "system"),
        notification_id: String(record.id ?? ""),
        title,
        body,
        ...Object.fromEntries(
          Object.entries(rawData).map(([k, v]) => [k, String(v ?? "")]),
        ),
      };
    } else {
      // Legacy squads INSERT
      const senderId = record.sender_id as string | undefined;
      const receiverId = record.receiver_id as string | undefined;
      if (!senderId || !receiverId) {
        return json({ error: "Missing sender_id / receiver_id" }, 400);
      }
      if (record.status && record.status !== "pending") {
        return json({ skipped: true, reason: `status ${record.status}` }, 200);
      }
      userId = receiverId;

      const { data: sender, error: sendErr } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", senderId)
        .maybeSingle();
      if (sendErr) {
        return json({ error: sendErr.message }, 500);
      }
      const rawName =
        (sender?.username as string | undefined)?.trim() || "birisi";
      const handle = rawName.startsWith("@") ? rawName.slice(1) : rawName;
      title = "Kanka isteği";
      body = `@${handle} seninle kanka olmak istiyor.`;
      data = {
        type: "friend_request",
        squad_id: String(record.id ?? ""),
        sender_id: senderId,
        receiver_id: receiverId,
        title,
        body,
      };
    }

    if (!userId) {
      return json({ error: "Missing target user_id" }, 400);
    }

    const { data: profile, error: recvErr } = await supabase
      .from("profiles")
      .select("fcm_token, curiosity_push_enabled, last_active_at")
      .eq("id", userId)
      .maybeSingle();

    if (recvErr) {
      console.error("receiver lookup:", recvErr);
      return json({ error: recvErr.message }, 500);
    }

    const notifType = String(
      payload.table === "notifications"
        ? (record.type ?? data.type ?? "system")
        : (data.type ?? "system"),
    );

    // Curiosity / re-engagement: respect opt-out + recent activity.
    if (notifType === "curiosity") {
      if (profile?.curiosity_push_enabled === false) {
        return json({ skipped: true, reason: "curiosity_opt_out" }, 200);
      }
      const lastActive = profile?.last_active_at as string | null | undefined;
      if (lastActive) {
        const ageMs = Date.now() - new Date(lastActive).getTime();
        if (Number.isFinite(ageMs) && ageMs < 6 * 60 * 60 * 1000) {
          return json({ skipped: true, reason: "recently_active" }, 200);
        }
      }
    }

    const token = profile?.fcm_token as string | null | undefined;
    if (!token) {
      return json({ skipped: true, reason: "no fcm_token" }, 200);
    }

    const accessToken = await getGoogleAccessToken(sa);
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: {
              priority: "HIGH",
              notification: {
                channelId: "nool_social",
                sound: "default",
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                },
              },
            },
          },
        }),
      },
    );

    const fcmText = await fcmRes.text();
    if (!fcmRes.ok) {
      console.error("FCM error:", fcmRes.status, fcmText);
      return json(
        { error: "FCM send failed", status: fcmRes.status, detail: fcmText },
        502,
      );
    }

    return json({ ok: true, fcm: safeJson(fcmText) }, 200);
  } catch (e) {
    console.error("fcm-notify:", e);
    return json({ error: String(e) }, 500);
  }
});

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const key = await importPKCS8(pem, "RS256");

  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(
      `OAuth token failed: ${res.status} ${JSON.stringify(data)}`,
    );
  }
  return data.access_token as string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
