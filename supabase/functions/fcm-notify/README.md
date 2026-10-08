# fcm-notify — Social FCM push

Supabase Edge Function: push on **`notifications` INSERT** (preferred) or legacy **`squads` INSERT**.

In-app rows are created by SQL triggers in `017_notifications.sql` (friend request / accept, DM, group message). This function turns those rows (or legacy squad inserts) into FCM v1 pushes via `profiles.fcm_token`.

---

## 1) SQL

Run in order (SQL Editor):

1. `009_profiles_fcm_token.sql` (if not already)
2. `016_friendships.sql`
3. `017_notifications.sql`

Optional Realtime for badge:

```sql
alter publication supabase_realtime add table public.notifications;
```

---

## 2) Secret: `FIREBASE_SERVICE_ACCOUNT_JSON`

Firebase service-account JSON in Supabase Edge Function secrets.

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat /path/to/service-account.json)"
```

---

## 3) Deploy

```bash
supabase functions deploy fcm-notify --no-verify-jwt
```

---

## 4) Database Webhooks

### Preferred: `notifications` INSERT

1. Database → Webhooks → Create
2. Name: `notifications_insert_fcm`
3. Table: `public.notifications`
4. Events: **Insert**
5. URL: `https://<PROJECT_REF>.supabase.co/functions/v1/fcm-notify`
6. Headers: `Content-Type: application/json`

Function reads `record.user_id`, `title`, `body`, `type`, `data`.

### Legacy (optional): `squads` INSERT

Keep `squads_insert_fcm` only if needed. Prefer **only** the notifications webhook to avoid duplicate friend-request pushes (SQL trigger already inserts a notification row).

---

## 5) Flutter

- In-app center: Mesajlar / Profil → bell
- Friend requests: Mesajlar / Profil → İstekler
- FCM degrades gracefully if Firebase config missing

---

## 6) Test

1. Run migrations 016 + 017
2. Redeploy `fcm-notify` + notifications webhook
3. Device signed in → `profiles.fcm_token` set
4. Friend request / DM → in-app list + push (if FCM ready)

## Required server authorization

Set `NOOL_SERVER_WEBHOOK_SECRET` to a strong, server-only random value. Configure the Database Webhook / cron request with the same `x-nool-webhook-secret` header. Requests without the secret return 401, including when deployed with `--no-verify-jwt`. Never put this secret in Flutter or repository files.
