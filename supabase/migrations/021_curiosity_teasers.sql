-- Nool — Curiosity / re-engagement teasers
-- Run after 017_notifications.sql (+ optional FCM webhook on notifications INSERT).
--
-- Adds:
--   • notifications.type = 'curiosity'
--   • profiles.last_active_at / curiosity_push_enabled
--   • touch_last_active() — client heartbeat
--   • enqueue_curiosity_teasers() — cron / Edge (service_role)
--
-- Caps: ≤1 curiosity row / user / 20h; skip if active in last 6h;
--       skip if curiosity_push_enabled = false.

-- ---------------------------------------------------------------------------
-- 1) Expand notifications.type check
-- ---------------------------------------------------------------------------
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
  check (type in (
    'friend_request',
    'friend_accepted',
    'dm_message',
    'group_message',
    'vibe',
    'reaction',
    'system',
    'curiosity'
  ));

-- ---------------------------------------------------------------------------
-- 2) Profile prefs + activity
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists last_active_at timestamptz;

alter table public.profiles
  add column if not exists curiosity_push_enabled boolean not null default true;

comment on column public.profiles.last_active_at is
  'Client heartbeat — used to skip re-engagement when recently active.';
comment on column public.profiles.curiosity_push_enabled is
  'Merak bildirimleri — user opt-out for curiosity / teaser pushes.';

create index if not exists profiles_curiosity_inactive_idx
  on public.profiles (last_active_at)
  where curiosity_push_enabled = true;

-- ---------------------------------------------------------------------------
-- 3) Client: touch last_active
-- ---------------------------------------------------------------------------
create or replace function public.touch_last_active()
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  update public.profiles
  set last_active_at = now()
  where id = auth.uid();
end;
$$;

grant execute on function public.touch_last_active() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Client: sync curiosity preference
-- ---------------------------------------------------------------------------
create or replace function public.set_curiosity_push_enabled(p_enabled boolean)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  update public.profiles
  set curiosity_push_enabled = coalesce(p_enabled, true)
  where id = auth.uid();
end;
$$;

grant execute on function public.set_curiosity_push_enabled(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Copy pool (TR default + EN in data) — privacy-safe, no spoilers
-- ---------------------------------------------------------------------------
create or replace function public.nool_curiosity_copy(p_kind text)
returns table (title text, body text, en_title text, en_body text)
language sql
immutable
as $$
  select t.title, t.body, t.en_title, t.en_body
  from (values
    (
      'nearby',
      'Kampüsünde bir şeyler oluyor',
      'Radar ısındı — bakmadan bilmeyeceksin.',
      'Something''s heating up on campus',
      'Radar''s warm — you won''t know until you look.'
    ),
    (
      'radar',
      'Radar''da hareket var',
      'Yakında drop''lar kıpırdıyor. Spoiler yok.',
      'Movement on the radar',
      'Nearby drops are stirring. No spoilers.'
    ),
    (
      'streak',
      'Ateş sönmek üzere',
      'Kadronun kaos ateşi zayıf düşüyor — kaçırma.',
      'Fire about to die',
      'Your circle chaos fire is fading — don''t ghost it.'
    ),
    (
      'unseen',
      'Görmediğin vibes birikiyor',
      'Akışta seni bekleyen kaos var. Merak et.',
      'Unseen vibes stacking up',
      'Chaos is waiting in the feed. Stay curious.'
    ),
    (
      'friends',
      'Kadro kıpırdadı',
      'Arkadaş tarafında hareket — detay yok, sadece sinyal.',
      'Your circle stirred',
      'Friend-side motion — signal only, no spoilers.'
    ),
    (
      'night',
      'Gece Nool''uyor',
      'Kampüs uyanık. Sen?',
      'Night mode: Nool''ing',
      'Campus is awake. Are you?'
    )
  ) as t(kind, title, body, en_title, en_body)
  where t.kind = p_kind;
$$;

-- ---------------------------------------------------------------------------
-- 6) Cron / service_role: enqueue teasers (max ~1 / user / day)
-- ---------------------------------------------------------------------------
create or replace function public.enqueue_curiosity_teasers(
  p_limit int default 200,
  p_inactive_hours int default 18,
  p_cooldown_hours int default 20
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_kind text;
  v_title text;
  v_body text;
  v_en_title text;
  v_en_body text;
  v_count int := 0;
  v_kinds text[] := array['nearby', 'radar', 'streak', 'unseen', 'friends', 'night'];
begin
  -- Prefer service_role; also allow postgres/cron.
  if auth.role() is distinct from 'service_role'
     and current_user is distinct from 'postgres' then
    raise exception 'service_role required' using errcode = '42501';
  end if;

  for r in
    select p.id
    from public.profiles p
    where p.curiosity_push_enabled is true
      and (
        p.last_active_at is null
        or p.last_active_at < now() - make_interval(hours => greatest(p_inactive_hours, 1))
      )
      and not exists (
        select 1
        from public.notifications n
        where n.user_id = p.id
          and n.type = 'curiosity'
          and n.created_at > now() - make_interval(hours => greatest(p_cooldown_hours, 12))
      )
      -- Soft daily cap: < 2 curiosity in last 24h
      and (
        select count(*)
        from public.notifications n2
        where n2.user_id = p.id
          and n2.type = 'curiosity'
          and n2.created_at > now() - interval '24 hours'
      ) < 2
    order by p.last_active_at nulls first
    limit greatest(least(p_limit, 2000), 1)
  loop
    v_kind := v_kinds[1 + floor(random() * array_length(v_kinds, 1))::int];

    select c.title, c.body, c.en_title, c.en_body
      into v_title, v_body, v_en_title, v_en_body
    from public.nool_curiosity_copy(v_kind) c;

    if v_title is null then
      continue;
    end if;

    perform public.insert_notification(
      r.id,
      'curiosity',
      v_title,
      v_body,
      jsonb_build_object(
        'kind', v_kind,
        'en_title', v_en_title,
        'en_body', v_en_body,
        'source', 'cron'
      )
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.enqueue_curiosity_teasers(int, int, int) from public;
grant execute on function public.enqueue_curiosity_teasers(int, int, int)
  to service_role;

comment on function public.enqueue_curiosity_teasers(int, int, int) is
  'Cron: insert curiosity notification rows for inactive opted-in users. '
  'Pair with Database Webhook on notifications INSERT → fcm-notify.';

-- ---------------------------------------------------------------------------
-- Optional pg_cron (enable extension in Dashboard first):
--
--   select cron.schedule(
--     'nool-curiosity-teasers',
--     '0 16 * * *',  -- 16:00 UTC ≈ evening TR
--     $$ select public.enqueue_curiosity_teasers(); $$
--   );
--
-- Or Edge cron hitting:
--   POST /functions/v1/curiosity-cron  (service role JWT)
-- ---------------------------------------------------------------------------
