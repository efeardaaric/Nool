-- Nool — profiles.fcm_token for FCM push delivery
-- Supabase SQL Editor'de çalıştırın (001–008 sonrası).
--
-- Flutter istemci: NotificationService token'ı auth kullanıcısının
-- profiles satırına yazar. Edge Function `fcm-notify` squad INSERT
-- webhook'unda receiver_id üzerinden bu kolonu okur.

alter table public.profiles
  add column if not exists fcm_token text;

comment on column public.profiles.fcm_token is
  'Firebase Cloud Messaging device token — son aktif cihaz; null = push kapalı / henüz kayıt yok.';

-- Token lookup by receiver on notify path (exact match / null filter).
create index if not exists profiles_fcm_token_idx
  on public.profiles (fcm_token)
  where fcm_token is not null;
