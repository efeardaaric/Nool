# Curiosity / re-engagement teasers

Nool occasionally pings inactive users with privacy-safe curiosity copy
(“Radar’da hareket var”, streak fire about to die, etc.) — no spoilers.

## Pieces

| Layer | What |
|-------|------|
| SQL `021_curiosity_teasers.sql` | `curiosity` type, `last_active_at`, `curiosity_push_enabled`, `enqueue_curiosity_teasers()`, `touch_last_active()` |
| Edge `curiosity-cron` | Cron POST → enqueue notification rows |
| Edge `fcm-notify` | On `notifications` INSERT → FCM (skips curiosity if opted out / active &lt; 6h) |
| Flutter | Settings **Merak bildirimleri** + local evening teaser via `flutter_local_notifications` |

Caps: server ≤1–2/day (20h cooldown + inactive ≥18h). Client local teaser ≤1/day and skips if app opened in last 12h.

---

## 1) Apply SQL

Supabase → **SQL Editor** → run `supabase/migrations/021_curiosity_teasers.sql`.

---

## 2) Deploy Edge Functions

```bash
supabase functions deploy fcm-notify --no-verify-jwt
supabase functions deploy curiosity-cron --no-verify-jwt
```

FCM still needs `FIREBASE_SERVICE_ACCOUNT_JSON` (see `fcm-notify/README.md`).

---

## 3) Database Webhook (push)

If not already: **Database → Webhooks** on `public.notifications` **INSERT** →
`https://<PROJECT_REF>.supabase.co/functions/v1/fcm-notify`

Curiosity rows then push like social notifications.

---

## 4) Schedule cron

### Option A — Edge Function schedule (Dashboard)

**Edge Functions → curiosity-cron → Schedules** (or external cron):

- Method: `POST`
- URL: `https://<PROJECT_REF>.supabase.co/functions/v1/curiosity-cron`
- Header: `Authorization: Bearer <SERVICE_ROLE_KEY>`
- Body: `{ "limit": 200, "inactive_hours": 18, "cooldown_hours": 20 }`
- Cadence: e.g. once daily ~16:00 UTC (evening TR)

### Option B — pg_cron

```sql
select cron.schedule(
  'nool-curiosity-teasers',
  '0 16 * * *',
  $$ select public.enqueue_curiosity_teasers(); $$
);
```

---

## 5) Flutter / Firebase (already wired)

- Client calls `touch_last_active` on resume / sign-in
- Toggle syncs `set_curiosity_push_enabled`
- Local scheduled teaser is the fallback when FCM/cron isn’t fully configured
- iOS: Push + local notifications share OS permission
- Android: `POST_NOTIFICATIONS` + boot-complete for reschedule

---

## Test

1. User idle ≥18h, `curiosity_push_enabled = true`, has `fcm_token`
2. `select enqueue_curiosity_teasers(10);` as service role → row in `notifications`
3. Webhook → device push / in-app center shows type `curiosity`
4. Toggle off in Settings → no more enqueue/push; local schedule cancelled

## Required server authorization

Set `NOOL_SERVER_WEBHOOK_SECRET` to a strong, server-only random value. Configure the Database Webhook / cron request with the same `x-nool-webhook-secret` header. Requests without the secret return 401, including when deployed with `--no-verify-jwt`. Never put this secret in Flutter or repository files.
