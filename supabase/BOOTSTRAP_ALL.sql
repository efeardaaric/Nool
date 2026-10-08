-- Nool full schema bootstrap — run once in Supabase SQL Editor after project reset
-- Generated from migrations 001→024 (numeric then filename order)


-- ========== BEGIN: 001_videos_postgis.sql ==========
-- Nool — videos + PostGIS skor sıralaması
-- Supabase SQL Editor'de çalıştırın (veya CLI migrate).

create extension if not exists postgis;

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  username text not null,
  caption text not null default '',
  subtitle text not null default '',
  track_label text not null default 'original audio',
  storage_path text not null,
  video_url text not null,
  vibe_count integer not null default 0 check (vibe_count >= 0),
  comment_count integer not null default 0 check (comment_count >= 0),
  -- Point(lng, lat) — geography; ST_Distance metre döner
  location geography(Point, 4326) not null,
  created_at timestamptz not null default now()
);

create index if not exists videos_location_gix
  on public.videos using gist (location);

create index if not exists videos_created_at_idx
  on public.videos (created_at desc);

insert into storage.buckets (id, name, public)
values ('videos', 'videos', true)
on conflict (id) do nothing;

-- Skor = vibe / (mesafe_m × yaş_saat)
create or replace function public.get_nearby_videos(
  p_lat double precision,
  p_lng double precision,
  p_limit integer default 40
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision
)
language sql
stable
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    st_distance(v.location, origin.g) as distance_m,
    (
      v.vibe_count::double precision
      / (
          greatest(st_distance(v.location, origin.g), 1.0)
          * greatest(
              extract(epoch from (now() - v.created_at)) / 3600.0,
              0.01
            )
        )
    ) as score
  from public.videos v
  cross join origin
  where v.created_at >= now() - interval '24 hours'
  order by score desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

-- Meta kayıt: Point(lng, lat) sunucuda üretilir
create or replace function public.create_video(
  p_id uuid,
  p_device_id text,
  p_username text,
  p_caption text,
  p_subtitle text,
  p_track_label text,
  p_storage_path text,
  p_video_url text,
  p_lat double precision,
  p_lng double precision
)
returns public.videos
language plpgsql
as $$
declare
  row public.videos;
begin
  insert into public.videos (
    id,
    device_id,
    username,
    caption,
    subtitle,
    track_label,
    storage_path,
    video_url,
    location
  )
  values (
    p_id,
    p_device_id,
    p_username,
    coalesce(p_caption, ''),
    coalesce(p_subtitle, ''),
    coalesce(p_track_label, 'original audio'),
    p_storage_path,
    p_video_url,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
  )
  returning * into row;

  return row;
end;
$$;

create or replace function public.increment_vibe(p_video_id uuid)
returns void
language sql
as $$
  update public.videos
  set vibe_count = vibe_count + 1
  where id = p_video_id
    and created_at >= now() - interval '24 hours';
$$;

-- Opsiyonel pg_cron temizliği:
-- select cron.schedule(
--   'purge-old-nool-videos',
--   '15 * * * *',
--   $$delete from public.videos where created_at < now() - interval '24 hours'$$
-- );

grant execute on function public.get_nearby_videos(double precision, double precision, integer)
  to anon, authenticated;

grant execute on function public.create_video(
  uuid, text, text, text, text, text, text, text, double precision, double precision
) to anon, authenticated;

grant execute on function public.increment_vibe(uuid)
  to anon, authenticated;

alter table public.videos enable row level security;

drop policy if exists "videos_select_fresh" on public.videos;
create policy "videos_select_fresh"
  on public.videos for select
  to anon, authenticated
  using (created_at >= now() - interval '24 hours');

drop policy if exists "videos_insert_anon" on public.videos;
create policy "videos_insert_anon"
  on public.videos for insert
  to anon, authenticated
  with check (true);

drop policy if exists "videos_update_vibe" on public.videos;
create policy "videos_update_vibe"
  on public.videos for update
  to anon, authenticated
  using (created_at >= now() - interval '24 hours');

-- Storage: herkes okusun, herkes yüklesin (anon vibe app)
drop policy if exists "videos_storage_read" on storage.objects;
create policy "videos_storage_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'videos');

drop policy if exists "videos_storage_insert" on storage.objects;
create policy "videos_storage_insert"
  on storage.objects for insert
  to anon, authenticated
  with check (bucket_id = 'videos');

-- ========== END: 001_videos_postgis.sql ==========

-- ========== BEGIN: 002_comments_realtime.sql ==========
-- Nool — video yorumları + Realtime
-- 001_videos_postgis.sql sonrası çalıştırın.

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  device_id text not null,
  username text not null,
  body text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);

create index if not exists comments_video_created_idx
  on public.comments (video_id, created_at asc);

alter table public.comments enable row level security;

drop policy if exists "comments_select" on public.comments;
create policy "comments_select"
  on public.comments for select
  to anon, authenticated
  using (true);

drop policy if exists "comments_insert" on public.comments;
create policy "comments_insert"
  on public.comments for insert
  to anon, authenticated
  with check (char_length(trim(body)) > 0 and char_length(body) <= 500);

-- Realtime yayın
alter publication supabase_realtime add table public.comments;

-- Yorum sayacı
create or replace function public.bump_comment_count()
returns trigger
language plpgsql
as $$
begin
  update public.videos
  set comment_count = comment_count + 1
  where id = new.video_id;
  return new;
end;
$$;

drop trigger if exists trg_bump_comment_count on public.comments;
create trigger trg_bump_comment_count
  after insert on public.comments
  for each row execute function public.bump_comment_count();

-- ========== END: 002_comments_realtime.sql ==========

-- ========== BEGIN: 003_campus_drops_bucket.sql ==========
-- campus-drops storage bucket (Mystery Camera uploads)
insert into storage.buckets (id, name, public)
values ('campus-drops', 'campus-drops', true)
on conflict (id) do nothing;

drop policy if exists "campus_drops_read" on storage.objects;
create policy "campus_drops_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'campus-drops');

drop policy if exists "campus_drops_insert" on storage.objects;
create policy "campus_drops_insert"
  on storage.objects for insert
  to anon, authenticated
  with check (bucket_id = 'campus-drops');

-- ========== END: 003_campus_drops_bucket.sql ==========

-- ========== BEGIN: 004_trending_hotspots.sql ==========
-- 5km içi video kümeleri (ısı haritası / trend noktalar)
create or replace function public.get_trending_hotspots(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 5000,
  p_limit integer default 20
)
returns table (
  cluster_id text,
  name text,
  latitude double precision,
  longitude double precision,
  drop_count bigint,
  distance_m double precision
)
language sql
stable
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  fresh as (
    select
      v.id,
      v.location,
      -- ~120–150m grid (derece cinsinden kabaca)
      st_snaptogrid(v.location::geometry, 0.0012, 0.0012) as cell
    from public.videos v
    cross join origin o
    where v.created_at >= now() - interval '24 hours'
      and st_dwithin(v.location, o.g, greatest(p_radius_m, 100))
  ),
  clustered as (
    select
      md5(st_astext(cell)) as cluster_id,
      st_y(st_centroid(st_collect(cell))) as latitude,
      st_x(st_centroid(st_collect(cell))) as longitude,
      count(*)::bigint as drop_count,
      st_setsrid(
        st_makepoint(
          st_x(st_centroid(st_collect(cell))),
          st_y(st_centroid(st_collect(cell)))
        ),
        4326
      )::geography as center
    from fresh
    group by cell
  )
  select
    c.cluster_id,
    case
      when c.drop_count >= 40 then 'Şenlik Alanı'
      when c.drop_count >= 25 then 'Merkez Kütüphane'
      when c.drop_count >= 15 then 'Hazırlık Binası'
      when c.drop_count >= 8 then 'Kantinci Önü'
      when c.drop_count >= 4 then 'Amfi Arkası'
      else 'Sokak Drop''u'
    end as name,
    c.latitude,
    c.longitude,
    c.drop_count,
    st_distance(c.center, o.g) as distance_m
  from clustered c
  cross join origin o
  order by c.drop_count desc, distance_m asc
  limit greatest(coalesce(p_limit, 20), 1);
$$;

grant execute on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) to anon, authenticated;

-- Hotspot filtresi: opsiyonel yarıçap (metre)
create or replace function public.get_nearby_videos(
  p_lat double precision,
  p_lng double precision,
  p_limit integer default 40,
  p_radius_m double precision default null
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision
)
language sql
stable
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    st_distance(v.location, origin.g) as distance_m,
    (
      v.vibe_count::double precision
      / (
          greatest(st_distance(v.location, origin.g), 1.0)
          * greatest(
              extract(epoch from (now() - v.created_at)) / 3600.0,
              0.01
            )
        )
    ) as score
  from public.videos v
  cross join origin
  where v.created_at >= now() - interval '24 hours'
    and (
      p_radius_m is null
      or st_dwithin(v.location, origin.g, p_radius_m)
    )
  order by score desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_nearby_videos(
  double precision, double precision, integer, double precision
) to anon, authenticated;

-- ========== END: 004_trending_hotspots.sql ==========

-- ========== BEGIN: 005_profiles_squads_gdpr.sql ==========
-- Nool — profiles, squads (arkadaşlık) + GDPR self-deletion
-- Supabase SQL Editor'de çalıştırın (001–004 sonrası).

-- ---------------------------------------------------------------------------
-- 1) Profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  bio text not null default '' check (char_length(bio) <= 150),
  avatar_url text,
  created_at timestamptz not null default now(),
  constraint profiles_username_unique unique (username),
  constraint profiles_username_nonempty check (char_length(trim(username)) > 0)
);

create index if not exists profiles_username_idx
  on public.profiles (username);

comment on table public.profiles is
  'Nool kullanıcı profili — auth.users ile 1:1; silinince GDPR tetikleyicisi auth kaydını da siler.';

-- Auth kaydı oluşunca profil satırı (username metadata veya anon fallback).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
begin
  v_username := nullif(trim(coalesce(new.raw_user_meta_data ->> 'username', '')), '');
  if v_username is null then
    v_username := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');
  end if;
  if v_username is null then
    v_username := 'anon_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;

  insert into public.profiles (id, username, avatar_url)
  values (
    new.id,
    v_username,
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2) Squads (arkadaşlık istekleri)
-- ---------------------------------------------------------------------------
create table if not exists public.squads (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  receiver_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  constraint squads_sender_receiver_unique unique (sender_id, receiver_id),
  constraint squads_no_self check (sender_id <> receiver_id)
);

create index if not exists squads_sender_idx on public.squads (sender_id);
create index if not exists squads_receiver_idx on public.squads (receiver_id);
create index if not exists squads_status_idx on public.squads (status);

comment on table public.squads is
  'Squad arkadaşlık ilişkisi: pending / accepted / rejected.';

-- ---------------------------------------------------------------------------
-- 3) GDPR — Security Definer self-deletion
--
-- Flutter istemcisi auth.users silemez. Kullanıcı kendi profiles satırını
-- sildiğinde BEFORE DELETE tetikleyici auth.users kaydını hard-delete eder.
-- CASCADE profili zaten temizleyeceği için trigger RETURN NULL ile
-- orijinal DELETE'i iptal eder (çift silme / recursion engeli).
-- ---------------------------------------------------------------------------
create or replace function public.delete_user_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sadece kendi hesabını silebilir (service_role hariç güvenli yol).
  if auth.uid() is distinct from old.id then
    raise exception 'GDPR: yalnızca kendi profilinizi silebilirsiniz.'
      using errcode = '42501';
  end if;

  -- auth.users silinince profiles ON DELETE CASCADE ile gider.
  delete from auth.users where id = old.id;

  -- Bu BEFORE DELETE işlemini iptal et; cascade zaten profili kaldırır.
  return null;
end;
$$;

comment on function public.delete_user_account() is
  'profiles BEFORE DELETE — auth.users hard-delete (GDPR / App Store self-deletion).';

drop trigger if exists profiles_before_delete_gdpr on public.profiles;
create trigger profiles_before_delete_gdpr
  before delete on public.profiles
  for each row
  execute function public.delete_user_account();

-- İstemci kolaylığı: tek RPC ile kendi hesabını sil.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  -- profiles DELETE → profiles_before_delete_gdpr → auth.users
  delete from public.profiles where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Row Level Security — profiles
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all"
  on public.profiles for select
  to anon, authenticated
  using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own"
  on public.profiles for delete
  to authenticated
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 5) Row Level Security — squads
-- ---------------------------------------------------------------------------
alter table public.squads enable row level security;

drop policy if exists "squads_select_participants" on public.squads;
create policy "squads_select_participants"
  on public.squads for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

drop policy if exists "squads_insert_as_sender" on public.squads;
create policy "squads_insert_as_sender"
  on public.squads for insert
  to authenticated
  with check (auth.uid() = sender_id);

drop policy if exists "squads_update_participants" on public.squads;
create policy "squads_update_participants"
  on public.squads for update
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id)
  with check (auth.uid() = sender_id or auth.uid() = receiver_id);

drop policy if exists "squads_delete_participants" on public.squads;
create policy "squads_delete_participants"
  on public.squads for delete
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant select on public.profiles to anon, authenticated;
grant insert, update, delete on public.profiles to authenticated;

grant select, insert, update, delete on public.squads to authenticated;

-- ========== END: 005_profiles_squads_gdpr.sql ==========

-- ========== BEGIN: 006_avatars_bucket.sql ==========
-- Avatars storage bucket (profil fotoğrafları)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_read" on storage.objects;
create policy "avatars_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ========== END: 006_avatars_bucket.sql ==========

-- ========== BEGIN: 007_videos_delete_update.sql ==========
-- Profil: kendi drop’unu sil / caption düzenle.
-- (Drop’lar 24s TTL; istemci cihaz + username ile filtreler.)

drop policy if exists "videos_delete_own" on public.videos;
create policy "videos_delete_own"
  on public.videos for delete
  to anon, authenticated
  using (true);

drop policy if exists "videos_update_vibe" on public.videos;
drop policy if exists "videos_update_own" on public.videos;
create policy "videos_update_own"
  on public.videos for update
  to anon, authenticated
  using (true)
  with check (true);

grant delete on public.videos to anon, authenticated;

-- ========== END: 007_videos_delete_update.sql ==========

-- ========== BEGIN: 008_ugc_reports_blocks.sql ==========
-- Nool — Apple UGC moderation: reports + blocked_users
-- Supabase SQL Editor'de çalıştırın (001–007 sonrası).
--
-- Not: videos tablosunda user_id yok; yalnızca username (text).
-- blocked_users.blocked_user_id = profiles.id (UUID).
-- Feed / hotspot filtreleri: engellenen profilin username'i ile
-- videos.username eşleşir (@'li / @'siz varyantlar dahil).

-- ---------------------------------------------------------------------------
-- 1) reports
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users (id) on delete set null,
  reported_video_id uuid references public.videos (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

create index if not exists reports_reporter_idx
  on public.reports (reporter_id);

create index if not exists reports_video_idx
  on public.reports (reported_video_id);

create index if not exists reports_created_at_idx
  on public.reports (created_at desc);

comment on table public.reports is
  'UGC şikayetleri — Apple App Store kullanıcı içerik moderasyonu.';

-- ---------------------------------------------------------------------------
-- 2) blocked_users
-- ---------------------------------------------------------------------------
create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_user_id),
  constraint blocked_users_no_self check (blocker_id <> blocked_user_id)
);

create index if not exists blocked_users_blocker_idx
  on public.blocked_users (blocker_id);

create index if not exists blocked_users_blocked_idx
  on public.blocked_users (blocked_user_id);

comment on table public.blocked_users is
  'Kalıcı kullanıcı engeli — blocker_id engelleyen, blocked_user_id = profiles.id.';

-- Username normalize: trim + leading @ kaldır
create or replace function public.nool_norm_username(p text)
returns text
language sql
immutable
as $$
  select lower(
    nullif(
      ltrim(trim(coalesce(p, '')), '@'),
      ''
    )
  );
$$;

-- Oturum sahibinin engellediği username seti (normalize)
create or replace function public.nool_blocked_usernames()
returns table (uname text)
language sql
stable
security invoker
as $$
  select distinct public.nool_norm_username(p.username) as uname
  from public.blocked_users b
  join public.profiles p on p.id = b.blocked_user_id
  where b.blocker_id = auth.uid()
    and public.nool_norm_username(p.username) is not null;
$$;

-- ---------------------------------------------------------------------------
-- 3) RLS
-- ---------------------------------------------------------------------------
alter table public.reports enable row level security;
alter table public.blocked_users enable row level security;

drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own"
  on public.reports for insert
  to authenticated
  with check (auth.uid() = reporter_id);

drop policy if exists "reports_select_own" on public.reports;
create policy "reports_select_own"
  on public.reports for select
  to authenticated
  using (auth.uid() = reporter_id);

drop policy if exists "blocked_insert_own" on public.blocked_users;
create policy "blocked_insert_own"
  on public.blocked_users for insert
  to authenticated
  with check (auth.uid() = blocker_id);

drop policy if exists "blocked_select_own" on public.blocked_users;
create policy "blocked_select_own"
  on public.blocked_users for select
  to authenticated
  using (auth.uid() = blocker_id);

drop policy if exists "blocked_delete_own" on public.blocked_users;
create policy "blocked_delete_own"
  on public.blocked_users for delete
  to authenticated
  using (auth.uid() = blocker_id);

grant select, insert on public.reports to authenticated;
grant select, insert, delete on public.blocked_users to authenticated;

-- ---------------------------------------------------------------------------
-- 4) get_nearby_videos — engellenen kullanıcı videolarını dışla
-- ---------------------------------------------------------------------------
create or replace function public.get_nearby_videos(
  p_lat double precision,
  p_lng double precision,
  p_limit integer default 40,
  p_radius_m double precision default null
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision
)
language sql
stable
security invoker
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    st_distance(v.location, origin.g) as distance_m,
    (
      v.vibe_count::double precision
      / (
          greatest(st_distance(v.location, origin.g), 1.0)
          * greatest(
              extract(epoch from (now() - v.created_at)) / 3600.0,
              0.01
            )
        )
    ) as score
  from public.videos v
  cross join origin
  where v.created_at >= now() - interval '24 hours'
    and (
      p_radius_m is null
      or st_dwithin(v.location, origin.g, p_radius_m)
    )
    and (
      auth.uid() is null
      or public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by score desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_nearby_videos(
  double precision, double precision, integer, double precision
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) get_trending_hotspots — engellenen kullanıcı drop'larını kümeden çıkar
-- ---------------------------------------------------------------------------
create or replace function public.get_trending_hotspots(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 5000,
  p_limit integer default 20
)
returns table (
  cluster_id text,
  name text,
  latitude double precision,
  longitude double precision,
  drop_count bigint,
  distance_m double precision
)
language sql
stable
security invoker
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  ),
  fresh as (
    select
      v.id,
      v.location,
      st_snaptogrid(v.location::geometry, 0.0012, 0.0012) as cell
    from public.videos v
    cross join origin o
    where v.created_at >= now() - interval '24 hours'
      and st_dwithin(v.location, o.g, greatest(p_radius_m, 100))
      and (
        auth.uid() is null
        or public.nool_norm_username(v.username) is null
        or public.nool_norm_username(v.username) not in (select uname from blocked)
      )
  ),
  clustered as (
    select
      md5(st_astext(cell)) as cluster_id,
      st_y(st_centroid(st_collect(cell))) as latitude,
      st_x(st_centroid(st_collect(cell))) as longitude,
      count(*)::bigint as drop_count,
      st_setsrid(
        st_makepoint(
          st_x(st_centroid(st_collect(cell))),
          st_y(st_centroid(st_collect(cell)))
        ),
        4326
      )::geography as center
    from fresh
    group by cell
  )
  select
    c.cluster_id,
    case
      when c.drop_count >= 40 then 'Şenlik Alanı'
      when c.drop_count >= 25 then 'Merkez Kütüphane'
      when c.drop_count >= 15 then 'Hazırlık Binası'
      when c.drop_count >= 8 then 'Kantinci Önü'
      when c.drop_count >= 4 then 'Amfi Arkası'
      else 'Sokak Drop''u'
    end as name,
    c.latitude,
    c.longitude,
    c.drop_count,
    st_distance(c.center, o.g) as distance_m
  from clustered c
  cross join origin o
  order by c.drop_count desc, distance_m asc
  limit greatest(coalesce(p_limit, 20), 1);
$$;

grant execute on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) to anon, authenticated;

-- ========== END: 008_ugc_reports_blocks.sql ==========

-- ========== BEGIN: 009_profiles_fcm_token.sql ==========
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

-- ========== END: 009_profiles_fcm_token.sql ==========

-- ========== BEGIN: 010_gdpr_storage_self_deletion.sql ==========
-- Nool — GDPR / KVKK: storage + medya self-deletion destekleri
-- ============================================================================: Supabase Dashboard → SQL Editor'de çalıştırın (005–008 sonrası).
--
-- ---------------------------------------------------------------------------
-- Sınırlar (okuyun)
-- ---------------------------------------------------------------------------
-- • videos.user_id YOK — drop sahipliği device_id + username (text).
--   Storage + videos satır silme Flutter tarafında, profil silmeden ÖNCE yapılır
--   (ProfileService.deleteUserAccountAndAssets).
-- • comments yalnızca device_id / username taşır; auth.users ile FK yok.
--   Video silinince o videoya ait yorumlar CASCADE ile gider.
--   Başka kullanıcıların videolarına yazılmış yorumlar device_id ile
--   istemcide temizlenir; sunucu bunu auth.uid() ile eşleyemez.
-- • squads / blocked_users: profiles / auth CASCADE ile temizlenir.
-- • reports.reporter_id: ON DELETE SET NULL (şikayet anonim kalır).
-- • Storage: campus-drops yolları genelde {deviceId}/{videoId}.ext;
--   avatars: {uid}/{uuid}.ext. İstemci her iki klasörü + videos.storage_path
--   listesini siler.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1a) comments DELETE (fallback istemci yolu; RPC security definer tercih)
-- ---------------------------------------------------------------------------
drop policy if exists "comments_delete" on public.comments;
create policy "comments_delete"
  on public.comments for delete
  to anon, authenticated
  using (true);

grant delete on public.comments to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1b) Storage DELETE politikaları (GDPR wipe + drop silme)
-- ---------------------------------------------------------------------------
drop policy if exists "campus_drops_delete" on storage.objects;
create policy "campus_drops_delete"
  on storage.objects for delete
  to anon, authenticated
  using (bucket_id = 'campus-drops');

drop policy if exists "videos_storage_delete" on storage.objects;
create policy "videos_storage_delete"
  on storage.objects for delete
  to anon, authenticated
  using (bucket_id = 'videos');

-- avatars_delete_own zaten 006'da: folder = auth.uid()

-- ---------------------------------------------------------------------------
-- 2) GDPR tetikleyici — profiles BEFORE DELETE → auth.users hard-delete
--    (005 ile aynı sözleşme; refresh / idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.delete_user_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is distinct from old.id then
    raise exception 'GDPR: yalnızca kendi profilinizi silebilirsiniz.'
      using errcode = '42501';
  end if;

  -- auth.users → profiles ON DELETE CASCADE
  delete from auth.users where id = old.id;

  -- Orijinal profiles DELETE'i iptal (çift silme / recursion engeli).
  return null;
end;
$$;

comment on function public.delete_user_account() is
  'profiles BEFORE DELETE — auth.users hard-delete (GDPR / KVKK / App Store).';

drop trigger if exists profiles_before_delete_gdpr on public.profiles;
create trigger profiles_before_delete_gdpr
  before delete on public.profiles
  for each row
  execute function public.delete_user_account();

-- ---------------------------------------------------------------------------
-- 3) RPC — istemci tek çağrıyla hesabı siler (storage wipe SONRASI)
-- ---------------------------------------------------------------------------
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  -- profiles DELETE → profiles_before_delete_gdpr → auth.users
  -- Squads / blocked_users cascade; reports.reporter_id null olur.
  delete from public.profiles where id = auth.uid();
end;
$$;

comment on function public.delete_own_account() is
  'GDPR self-deletion RPC. Flutter önce Storage + videos/comments silmeli, '
  'sonra bu RPC''yi çağırmalı.';

grant execute on function public.delete_own_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Opsiyonel yardımcı: kendi device/username medyasını DB'den temizle
--    (Storage ayrı — istemci Storage API kullanır)
-- ---------------------------------------------------------------------------
create or replace function public.purge_own_video_rows(
  p_device_id text default null,
  p_usernames text[] default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
  v_n integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  -- Yorumlar: bu cihazın bıraktığı (videolar CASCADE + yabancı videolar)
  if p_device_id is not null and length(trim(p_device_id)) > 0 then
    delete from public.comments where device_id = p_device_id;
  end if;

  if p_usernames is not null and cardinality(p_usernames) > 0 then
    delete from public.comments
    where public.nool_norm_username(username) = any (
      select public.nool_norm_username(u) from unnest(p_usernames) as u
    );
  end if;

  -- Videolar (yorumlar video_id CASCADE ile gider)
  if p_device_id is not null and length(trim(p_device_id)) > 0 then
    delete from public.videos where device_id = p_device_id;
    get diagnostics v_n = row_count;
    v_deleted := v_deleted + v_n;
  end if;

  if p_usernames is not null and cardinality(p_usernames) > 0 then
    delete from public.videos
    where public.nool_norm_username(username) = any (
      select public.nool_norm_username(u) from unnest(p_usernames) as u
    );
    get diagnostics v_n = row_count;
    v_deleted := v_deleted + v_n;
  end if;

  return v_deleted;
end;
$$;

comment on function public.purge_own_video_rows(text, text[]) is
  'GDPR: oturum açıkken device_id / username ile videos + comments satırlarını siler. '
  'Storage nesneleri istemci tarafından silinmelidir. '
  'LIMIT: comments/videos auth.uid taşımaz — yanlış device_id gönderilmemeli.';

grant execute on function public.purge_own_video_rows(text, text[]) to authenticated;

-- ========== END: 010_gdpr_storage_self_deletion.sql ==========

-- ========== BEGIN: 011_squad_circles_streaks.sql ==========
-- Nool — Squad Circles + Group Video Drops + Kaos Ateşi (streaks)
-- Supabase SQL Editor'de 001–010 sonrası çalıştırın.
--
-- Storage: `group-drops` bucket — public read + authenticated insert
-- (campus-drops ile aynı kalıp; aşağıda bucket + policies).

-- ---------------------------------------------------------------------------
-- 1) Tables
-- ---------------------------------------------------------------------------
create table if not exists public.squad_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now(),
  constraint squad_groups_name_nonempty check (char_length(trim(name)) > 0)
);

comment on table public.squad_groups is
  'Kadro (squad circle) — grup video drop + Kaos Ateşi streak.';

create table if not exists public.squad_group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.squad_groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  constraint squad_group_members_unique unique (group_id, user_id)
);

create index if not exists squad_group_members_user_idx
  on public.squad_group_members (user_id);
create index if not exists squad_group_members_group_idx
  on public.squad_group_members (group_id);

create table if not exists public.group_drops (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.squad_groups (id) on delete cascade,
  video_url text not null,
  caption text not null default '',
  sender_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text,
  created_at timestamptz not null default now()
);

create index if not exists group_drops_group_created_idx
  on public.group_drops (group_id, created_at desc);

create table if not exists public.group_streaks (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null unique references public.squad_groups (id) on delete cascade,
  current_streak int not null default 0,
  last_drop_at timestamptz,
  streak_expiry_at timestamptz
);

-- Minimal chat so GroupChatScreen is not placeholder-only.
create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.squad_groups (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint group_messages_body_nonempty check (char_length(trim(body)) > 0)
);

create index if not exists group_messages_group_created_idx
  on public.group_messages (group_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2) Membership helper (SECURITY DEFINER — avoids RLS recursion)
-- ---------------------------------------------------------------------------
create or replace function public.is_squad_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.squad_group_members m
    where m.group_id = p_group_id
      and m.user_id = auth.uid()
  );
$$;

grant execute on function public.is_squad_group_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Kaos Ateşi — trigger on group_drops INSERT
--
-- IF last_drop_at IS NULL THEN streak := 1
-- ELSIF now() - last_drop_at <= 24h THEN streak := current_streak + 1
-- ELSIF now() - last_drop_at <= 48h THEN streak := 1  -- grace restart
-- ELSE streak := 1  -- fully dead → this drop starts fresh at 1
-- END IF
-- ---------------------------------------------------------------------------
create or replace function public.update_group_streak_on_drop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_streak int;
  v_last timestamptz;
  v_current int;
begin
  select current_streak, last_drop_at
    into v_current, v_last
  from public.group_streaks
  where group_id = new.group_id
  for update;

  if not found then
    insert into public.group_streaks (
      group_id, current_streak, last_drop_at, streak_expiry_at
    ) values (
      new.group_id, 1, now(), now() + interval '24 hours'
    );
    return new;
  end if;

  if v_last is null then
    v_streak := 1;
  elsif now() - v_last <= interval '24 hours' then
    v_streak := coalesce(v_current, 0) + 1;
  elsif now() - v_last <= interval '48 hours' then
    -- Broke daily but within grace → restart at 1
    v_streak := 1;
  else
    -- Fully dead → this drop starts fresh at 1
    v_streak := 1;
  end if;

  update public.group_streaks
  set
    current_streak = v_streak,
    last_drop_at = now(),
    streak_expiry_at = now() + interval '24 hours'
  where group_id = new.group_id;

  return new;
end;
$$;

comment on function public.update_group_streak_on_drop() is
  'group_drops AFTER INSERT — Kaos Ateşi streak (24h continue / 48h grace restart).';

drop trigger if exists group_drops_after_insert_streak on public.group_drops;
create trigger group_drops_after_insert_streak
  after insert on public.group_drops
  for each row
  execute function public.update_group_streak_on_drop();

-- ---------------------------------------------------------------------------
-- 4) RLS
-- ---------------------------------------------------------------------------
alter table public.squad_groups enable row level security;
alter table public.squad_group_members enable row level security;
alter table public.group_drops enable row level security;
alter table public.group_streaks enable row level security;
alter table public.group_messages enable row level security;

-- squad_groups: members select; any authenticated can create
drop policy if exists "squad_groups_select_members" on public.squad_groups;
create policy "squad_groups_select_members"
  on public.squad_groups for select
  to authenticated
  using (public.is_squad_group_member(id));

drop policy if exists "squad_groups_insert_auth" on public.squad_groups;
create policy "squad_groups_insert_auth"
  on public.squad_groups for insert
  to authenticated
  with check (true);

-- squad_group_members: members see roster; creator/member can add (self or batch)
drop policy if exists "squad_group_members_select" on public.squad_group_members;
create policy "squad_group_members_select"
  on public.squad_group_members for select
  to authenticated
  using (public.is_squad_group_member(group_id) or user_id = auth.uid());

-- First member may self-join an empty group; existing members may add others.
drop policy if exists "squad_group_members_insert" on public.squad_group_members;
create policy "squad_group_members_insert"
  on public.squad_group_members for insert
  to authenticated
  with check (
    public.is_squad_group_member(group_id)
    or (
      user_id = auth.uid()
      and not exists (
        select 1
        from public.squad_group_members m
        where m.group_id = squad_group_members.group_id
      )
    )
  );

-- group_drops: members select + insert as self
drop policy if exists "group_drops_select_members" on public.group_drops;
create policy "group_drops_select_members"
  on public.group_drops for select
  to authenticated
  using (public.is_squad_group_member(group_id));

drop policy if exists "group_drops_insert_members" on public.group_drops;
create policy "group_drops_insert_members"
  on public.group_drops for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_squad_group_member(group_id)
  );

-- group_streaks: members select; updates only via security definer trigger
drop policy if exists "group_streaks_select_members" on public.group_streaks;
create policy "group_streaks_select_members"
  on public.group_streaks for select
  to authenticated
  using (public.is_squad_group_member(group_id));

drop policy if exists "group_streaks_insert_members" on public.group_streaks;
create policy "group_streaks_insert_members"
  on public.group_streaks for insert
  to authenticated
  with check (public.is_squad_group_member(group_id));

-- group_messages: members select + insert as self
drop policy if exists "group_messages_select_members" on public.group_messages;
create policy "group_messages_select_members"
  on public.group_messages for select
  to authenticated
  using (public.is_squad_group_member(group_id));

drop policy if exists "group_messages_insert_members" on public.group_messages;
create policy "group_messages_insert_members"
  on public.group_messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_squad_group_member(group_id)
  );

-- ---------------------------------------------------------------------------
-- 5) Storage — group-drops bucket (public read + authenticated insert)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('group-drops', 'group-drops', true)
on conflict (id) do nothing;

drop policy if exists "group_drops_storage_read" on storage.objects;
create policy "group_drops_storage_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'group-drops');

drop policy if exists "group_drops_storage_insert" on storage.objects;
create policy "group_drops_storage_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'group-drops');

-- ---------------------------------------------------------------------------
-- 6) Grants
-- ---------------------------------------------------------------------------
grant select, insert on public.squad_groups to authenticated;
grant select, insert on public.squad_group_members to authenticated;
grant select, insert on public.group_drops to authenticated;
grant select, insert on public.group_streaks to authenticated;
grant select, insert on public.group_messages to authenticated;

-- ========== END: 011_squad_circles_streaks.sql ==========

-- ========== BEGIN: 012_profiles_university_id.sql ==========
-- Nool — profiles.university_id for Campus feed tab
-- Supabase SQL Editor'de çalıştırın (011 sonrası).
--
-- Campus sekmesi: aynı university_id'ye sahip uploader'ların
-- son 24s videoları (istemci: videos.username → profiles.username join).

alter table public.profiles
  add column if not exists university_id text;

comment on column public.profiles.university_id is
  'Kampüs / üniversite anahtarı (örn. okul slug veya e-posta domain). '
  'Campus feed filtresi için kullanılır.';

create index if not exists profiles_university_id_idx
  on public.profiles (university_id)
  where university_id is not null;

-- ========== END: 012_profiles_university_id.sql ==========

-- ========== BEGIN: 013_video_reactions.sql ==========
-- Nool — emoji reactions on videos
-- Aggregates live on videos.reaction_counts (JSONB) for fast feed reads.
-- Run in Supabase SQL Editor if CLI migrate is not used.

-- ---------------------------------------------------------------------------
-- 1) Aggregated counts column on videos
-- ---------------------------------------------------------------------------
alter table public.videos
  add column if not exists reaction_counts jsonb not null default '{}'::jsonb;

comment on column public.videos.reaction_counts is
  'Aggregated emoji reaction counts, e.g. {"laugh":3,"pepper":1,"smile":0,"angry":2,"star":5}';

-- ---------------------------------------------------------------------------
-- 2) Per-user reaction rows
-- ---------------------------------------------------------------------------
create table if not exists public.video_reactions (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reaction_type text not null
    check (reaction_type in ('laugh', 'pepper', 'smile', 'angry', 'star')),
  created_at timestamptz not null default now(),
  unique (user_id, video_id, reaction_type)
);

create index if not exists video_reactions_video_id_idx
  on public.video_reactions (video_id);

create index if not exists video_reactions_user_id_idx
  on public.video_reactions (user_id);

-- ---------------------------------------------------------------------------
-- 3) Trigger — keep videos.reaction_counts in sync
-- ---------------------------------------------------------------------------
create or replace function public.refresh_video_reaction_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  target := coalesce(new.video_id, old.video_id);

  update public.videos v
  set reaction_counts = coalesce(
    (
      select jsonb_object_agg(r.reaction_type, r.cnt)
      from (
        select reaction_type, count(*)::int as cnt
        from public.video_reactions
        where video_id = target
        group by reaction_type
      ) r
    ),
    '{}'::jsonb
  )
  where v.id = target;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_video_reactions_counts on public.video_reactions;
create trigger trg_video_reactions_counts
  after insert or delete or update of reaction_type, video_id
  on public.video_reactions
  for each row
  execute function public.refresh_video_reaction_counts();

-- ---------------------------------------------------------------------------
-- 4) RLS
-- ---------------------------------------------------------------------------
alter table public.video_reactions enable row level security;

drop policy if exists "video_reactions_select_all" on public.video_reactions;
create policy "video_reactions_select_all"
  on public.video_reactions for select
  to anon, authenticated
  using (true);

drop policy if exists "video_reactions_insert_own" on public.video_reactions;
create policy "video_reactions_insert_own"
  on public.video_reactions for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "video_reactions_delete_own" on public.video_reactions;
create policy "video_reactions_delete_own"
  on public.video_reactions for delete
  to authenticated
  using (auth.uid() = user_id);

grant select on public.video_reactions to anon, authenticated;
grant insert, delete on public.video_reactions to authenticated;

-- Aggregates are on videos (already selectable). Ensure column is readable.
-- (videos SELECT policies from earlier migrations still apply.)

-- ---------------------------------------------------------------------------
-- 5) Feed RPC — include reaction_counts
-- ---------------------------------------------------------------------------
-- Return type değiştiği için REPLACE yetmez; önce düşür.
drop function if exists public.get_nearby_videos(
  double precision, double precision, integer, double precision
);
drop function if exists public.get_nearby_videos(
  double precision, double precision, integer
);

create function public.get_nearby_videos(
  p_lat double precision,
  p_lng double precision,
  p_limit integer default 40,
  p_radius_m double precision default null
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision,
  reaction_counts jsonb
)
language sql
stable
security invoker
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    st_distance(v.location, origin.g) as distance_m,
    (
      v.vibe_count::double precision
      / (
          greatest(st_distance(v.location, origin.g), 1.0)
          * greatest(
              extract(epoch from (now() - v.created_at)) / 3600.0,
              0.01
            )
        )
    ) as score,
    coalesce(v.reaction_counts, '{}'::jsonb) as reaction_counts
  from public.videos v
  cross join origin
  where v.created_at >= now() - interval '24 hours'
    and (
      p_radius_m is null
      or st_dwithin(v.location, origin.g, p_radius_m)
    )
    and (
      auth.uid() is null
      or public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by score desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_nearby_videos(
  double precision, double precision, integer, double precision
) to anon, authenticated;

-- ========== END: 013_video_reactions.sql ==========

-- ========== BEGIN: 014_direct_messages.sql ==========
-- Nool — 1:1 Direct Messages (Direkt mesajlar)
-- Supabase SQL Editor'de 001–013 sonrası çalıştırın.
--
-- Tables: dm_threads, dm_messages
-- RPC: get_or_create_dm_thread(other_user_id)
-- Realtime: dm_messages publication (optional enable in Dashboard)

-- ---------------------------------------------------------------------------
-- 1) Tables
-- ---------------------------------------------------------------------------
create table if not exists public.dm_threads (
  id uuid primary key default gen_random_uuid(),
  participant_a uuid not null references public.profiles (id) on delete cascade,
  participant_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz,
  last_message_preview text,
  constraint dm_threads_ordered check (participant_a < participant_b),
  constraint dm_threads_pair_unique unique (participant_a, participant_b),
  constraint dm_threads_not_self check (participant_a <> participant_b)
);

comment on table public.dm_threads is
  '1:1 DM thread — participant_a < participant_b (ordered pair).';

create index if not exists dm_threads_last_message_idx
  on public.dm_threads (last_message_at desc nulls last);

create index if not exists dm_threads_participant_a_idx
  on public.dm_threads (participant_a);

create index if not exists dm_threads_participant_b_idx
  on public.dm_threads (participant_b);

create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.dm_threads (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint dm_messages_body_nonempty check (char_length(trim(body)) > 0)
);

comment on table public.dm_messages is
  '1:1 DM messages within a dm_threads row.';

create index if not exists dm_messages_thread_created_idx
  on public.dm_messages (thread_id, created_at asc);

-- ---------------------------------------------------------------------------
-- 2) Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_dm_thread_participant(p_thread_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.dm_threads t
    where t.id = p_thread_id
      and (t.participant_a = auth.uid() or t.participant_b = auth.uid())
  );
$$;

grant execute on function public.is_dm_thread_participant(uuid) to authenticated;

-- Keep last_message_* + updated_at in sync on insert.
create or replace function public.touch_dm_thread_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.dm_threads
  set
    last_message_at = new.created_at,
    last_message_preview = left(trim(new.body), 140),
    updated_at = now()
  where id = new.thread_id;
  return new;
end;
$$;

drop trigger if exists dm_messages_touch_thread on public.dm_messages;
create trigger dm_messages_touch_thread
  after insert on public.dm_messages
  for each row
  execute function public.touch_dm_thread_on_message();

-- ---------------------------------------------------------------------------
-- 3) get_or_create_dm_thread(other_user_id)
-- ---------------------------------------------------------------------------
create or replace function public.get_or_create_dm_thread(p_other_user_id uuid)
returns public.dm_threads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_row public.dm_threads;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if p_other_user_id is null or p_other_user_id = v_me then
    raise exception 'Invalid other user';
  end if;

  if v_me < p_other_user_id then
    v_a := v_me;
    v_b := p_other_user_id;
  else
    v_a := p_other_user_id;
    v_b := v_me;
  end if;

  select * into v_row
  from public.dm_threads
  where participant_a = v_a and participant_b = v_b;

  if found then
    return v_row;
  end if;

  insert into public.dm_threads (participant_a, participant_b)
  values (v_a, v_b)
  on conflict (participant_a, participant_b) do update
    set updated_at = public.dm_threads.updated_at
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.get_or_create_dm_thread(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) RLS
-- ---------------------------------------------------------------------------
alter table public.dm_threads enable row level security;
alter table public.dm_messages enable row level security;

drop policy if exists "dm_threads_select_participants" on public.dm_threads;
create policy "dm_threads_select_participants"
  on public.dm_threads for select
  to authenticated
  using (participant_a = auth.uid() or participant_b = auth.uid());

-- Inserts go through get_or_create_dm_thread (security definer).
-- Allow direct insert only when caller is one participant (ordered pair).
drop policy if exists "dm_threads_insert_self" on public.dm_threads;
create policy "dm_threads_insert_self"
  on public.dm_threads for insert
  to authenticated
  with check (
    (participant_a = auth.uid() or participant_b = auth.uid())
    and participant_a < participant_b
  );

drop policy if exists "dm_threads_update_participants" on public.dm_threads;
create policy "dm_threads_update_participants"
  on public.dm_threads for update
  to authenticated
  using (participant_a = auth.uid() or participant_b = auth.uid())
  with check (participant_a = auth.uid() or participant_b = auth.uid());

drop policy if exists "dm_messages_select_participants" on public.dm_messages;
create policy "dm_messages_select_participants"
  on public.dm_messages for select
  to authenticated
  using (public.is_dm_thread_participant(thread_id));

drop policy if exists "dm_messages_insert_sender" on public.dm_messages;
create policy "dm_messages_insert_sender"
  on public.dm_messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_dm_thread_participant(thread_id)
  );

-- ---------------------------------------------------------------------------
-- 5) Grants
-- ---------------------------------------------------------------------------
grant select, insert, update on public.dm_threads to authenticated;
grant select, insert on public.dm_messages to authenticated;

-- Optional: enable Realtime for dm_messages in Dashboard → Database → Replication
-- alter publication supabase_realtime add table public.dm_messages;

-- ========== END: 014_direct_messages.sql ==========

-- ========== BEGIN: 015_video_vibes.sql ==========
-- Nool — per-user vibe (like) membership
-- Fixes: heart state lost after cold start because only vibe_count was
-- incremented with no (user_id, video_id) row to reload.
-- Run in Supabase SQL Editor if CLI migrate is not used.

-- ---------------------------------------------------------------------------
-- 1) Per-user vibe rows
-- ---------------------------------------------------------------------------
create table if not exists public.video_vibes (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, video_id)
);

create index if not exists video_vibes_video_id_idx
  on public.video_vibes (video_id);

create index if not exists video_vibes_user_id_idx
  on public.video_vibes (user_id);

comment on table public.video_vibes is
  'One row per user vibe on a video. Source of truth for heart UI.';

-- ---------------------------------------------------------------------------
-- 2) Keep videos.vibe_count in sync (+1 insert / -1 delete)
-- Historical anonymous increments may leave count > membership; that is OK.
-- ---------------------------------------------------------------------------
create or replace function public.sync_video_vibe_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.videos
    set vibe_count = vibe_count + 1
    where id = new.video_id
      and created_at >= now() - interval '24 hours';
    return new;
  elsif tg_op = 'DELETE' then
    update public.videos
    set vibe_count = greatest(vibe_count - 1, 0)
    where id = old.video_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_video_vibes_count on public.video_vibes;
create trigger trg_video_vibes_count
  after insert or delete
  on public.video_vibes
  for each row
  execute function public.sync_video_vibe_count();

-- ---------------------------------------------------------------------------
-- 3) RLS
-- ---------------------------------------------------------------------------
alter table public.video_vibes enable row level security;

drop policy if exists "video_vibes_select_all" on public.video_vibes;
create policy "video_vibes_select_all"
  on public.video_vibes for select
  to anon, authenticated
  using (true);

drop policy if exists "video_vibes_insert_own" on public.video_vibes;
create policy "video_vibes_insert_own"
  on public.video_vibes for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "video_vibes_delete_own" on public.video_vibes;
create policy "video_vibes_delete_own"
  on public.video_vibes for delete
  to authenticated
  using (auth.uid() = user_id);

grant select on public.video_vibes to anon, authenticated;
grant insert, delete on public.video_vibes to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Legacy RPC — idempotent insert (no double-count on re-tap)
-- ---------------------------------------------------------------------------
create or replace function public.increment_vibe(p_video_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  insert into public.video_vibes (video_id, user_id)
  values (p_video_id, auth.uid())
  on conflict (user_id, video_id) do nothing;
end;
$$;

grant execute on function public.increment_vibe(uuid)
  to anon, authenticated;

-- ========== END: 015_video_vibes.sql ==========

-- ========== BEGIN: 016_friendships.sql ==========
-- Nool — Friendship helpers on existing `squads` table
-- Supabase SQL Editor'de 001–015 sonrası çalıştırın.
--
-- `squads` zaten arkadaşlık istekleri (pending / accepted / rejected).
-- Bu migration: unordered pair uniqueness, block-aware send RPC,
-- reject / cancel / unfriend RPCs.

-- ---------------------------------------------------------------------------
-- 1) Unordered unique pair (A→B ve B→A aynı anda olamaz)
-- ---------------------------------------------------------------------------
create unique index if not exists squads_unordered_pair_uidx
  on public.squads (
    least(sender_id, receiver_id),
    greatest(sender_id, receiver_id)
  );

-- ---------------------------------------------------------------------------
-- 2) Block helper (either direction)
-- ---------------------------------------------------------------------------
create or replace function public.nool_users_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.blocked_users b
    where (b.blocker_id = p_a and b.blocked_user_id = p_b)
       or (b.blocker_id = p_b and b.blocked_user_id = p_a)
  );
$$;

grant execute on function public.nool_users_blocked(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) send_friend_request(receiver_id) — block-aware insert / revive
-- ---------------------------------------------------------------------------
create or replace function public.send_friend_request(p_receiver_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_receiver_id is null or p_receiver_id = v_me then
    raise exception 'Invalid receiver';
  end if;

  if public.nool_users_blocked(v_me, p_receiver_id) then
    raise exception 'User is blocked' using errcode = '42501';
  end if;

  -- Existing edge either direction?
  select * into v_row
  from public.squads s
  where (s.sender_id = v_me and s.receiver_id = p_receiver_id)
     or (s.sender_id = p_receiver_id and s.receiver_id = v_me)
  limit 1;

  if found then
    if v_row.status = 'accepted' then
      return v_row;
    end if;
    if v_row.status = 'pending' then
      return v_row;
    end if;
    -- rejected → reopen as new pending from me
    update public.squads
    set
      sender_id = v_me,
      receiver_id = p_receiver_id,
      status = 'pending',
      created_at = now()
    where id = v_row.id
    returning * into v_row;
    return v_row;
  end if;

  insert into public.squads (sender_id, receiver_id, status)
  values (v_me, p_receiver_id, 'pending')
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.send_friend_request(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) accept / reject / cancel / unfriend
-- ---------------------------------------------------------------------------
create or replace function public.accept_friend_request(p_request_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_row from public.squads where id = p_request_id;
  if not found then
    raise exception 'Request not found';
  end if;

  if v_row.receiver_id <> v_me then
    raise exception 'Only receiver can accept' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  if public.nool_users_blocked(v_row.sender_id, v_row.receiver_id) then
    raise exception 'User is blocked' using errcode = '42501';
  end if;

  update public.squads
  set status = 'accepted'
  where id = p_request_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.accept_friend_request(uuid) to authenticated;

create or replace function public.reject_friend_request(p_request_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_row from public.squads where id = p_request_id;
  if not found then
    raise exception 'Request not found';
  end if;

  if v_row.receiver_id <> v_me then
    raise exception 'Only receiver can reject' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  update public.squads
  set status = 'rejected'
  where id = p_request_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.reject_friend_request(uuid) to authenticated;

create or replace function public.cancel_friend_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_row from public.squads where id = p_request_id;
  if not found then
    return;
  end if;

  if v_row.sender_id <> v_me then
    raise exception 'Only sender can cancel' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  delete from public.squads where id = p_request_id;
end;
$$;

grant execute on function public.cancel_friend_request(uuid) to authenticated;

create or replace function public.remove_friend(p_other_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  delete from public.squads
  where status = 'accepted'
    and (
      (sender_id = v_me and receiver_id = p_other_user_id)
      or (sender_id = p_other_user_id and receiver_id = v_me)
    );
end;
$$;

grant execute on function public.remove_friend(uuid) to authenticated;

-- ========== END: 016_friendships.sql ==========

-- ========== BEGIN: 017_notifications.sql ==========
-- Nool — In-app notifications + auto triggers (friend + DM)
-- Supabase SQL Editor'de 016_friendships.sql sonrası çalıştırın.
--
-- Optional: Database Webhook on `notifications` INSERT → Edge Function
-- `fcm-notify` (updated) for FCM push.

-- ---------------------------------------------------------------------------
-- 1) notifications table
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null
    check (type in (
      'friend_request',
      'friend_accepted',
      'dm_message',
      'group_message',
      'vibe',
      'reaction',
      'system'
    )),
  title text not null,
  body text not null default '',
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.notifications is
  'In-app notification center — user reads own rows only.';

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

-- ---------------------------------------------------------------------------
-- 2) RLS
-- ---------------------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Inserts come from security definer triggers (or service role).
-- Authenticated users should not insert arbitrary notifications.
drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, update, delete on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Helper: insert notification (security definer)
-- ---------------------------------------------------------------------------
create or replace function public.insert_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_user_id is null then
    return null;
  end if;

  -- Skip if blocked either way when actor present in data
  if (p_data ? 'actor_id') then
    if public.nool_users_blocked(
      p_user_id,
      (p_data ->> 'actor_id')::uuid
    ) then
      return null;
    end if;
  end if;

  insert into public.notifications (user_id, type, title, body, data)
  values (p_user_id, p_type, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb))
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.insert_notification(uuid, text, text, text, jsonb)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Trigger: squads INSERT pending → friend_request to receiver
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_squad_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;

  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  perform public.insert_notification(
    new.receiver_id,
    'friend_request',
    'Arkadaşlık isteği',
    coalesce(v_name, '@birisi') || ' seni arkadaş olarak eklemek istiyor.',
    jsonb_build_object(
      'actor_id', new.sender_id,
      'squad_id', new.id,
      'sender_id', new.sender_id,
      'receiver_id', new.receiver_id
    )
  );

  return new;
end;
$$;

drop trigger if exists on_squad_insert_notify on public.squads;
create trigger on_squad_insert_notify
  after insert on public.squads
  for each row
  execute function public.notify_on_squad_insert();

-- Also fire when rejected → pending reopen (UPDATE that changes status)
create or replace function public.notify_on_squad_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  -- Pending reopen (rejected → pending)
  if old.status = 'rejected' and new.status = 'pending' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.sender_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.receiver_id,
      'friend_request',
      'Arkadaşlık isteği',
      coalesce(v_name, '@birisi') || ' seni arkadaş olarak eklemek istiyor.',
      jsonb_build_object(
        'actor_id', new.sender_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  -- Accept → notify original sender
  if old.status = 'pending' and new.status = 'accepted' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.receiver_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.sender_id,
      'friend_accepted',
      'İstek kabul edildi',
      coalesce(v_name, '@birisi') || ' arkadaşlık isteğini kabul etti.',
      jsonb_build_object(
        'actor_id', new.receiver_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists on_squad_update_notify on public.squads;
create trigger on_squad_update_notify
  after update of status, sender_id, receiver_id on public.squads
  for each row
  execute function public.notify_on_squad_update();

-- ---------------------------------------------------------------------------
-- 5) Trigger: dm_messages INSERT → notify other participant
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_dm_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_other uuid;
  v_name text;
  v_preview text;
begin
  select case
    when t.participant_a = new.sender_id then t.participant_b
    else t.participant_a
  end
  into v_other
  from public.dm_threads t
  where t.id = new.thread_id;

  if v_other is null or v_other = new.sender_id then
    return new;
  end if;

  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;
  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  v_preview := left(trim(new.body), 120);

  perform public.insert_notification(
    v_other,
    'dm_message',
    'Yeni mesaj',
    coalesce(v_name, '@birisi') || ': ' || coalesce(v_preview, ''),
    jsonb_build_object(
      'actor_id', new.sender_id,
      'thread_id', new.thread_id,
      'message_id', new.id
    )
  );

  return new;
end;
$$;

drop trigger if exists on_dm_message_notify on public.dm_messages;
create trigger on_dm_message_notify
  after insert on public.dm_messages
  for each row
  execute function public.notify_on_dm_message();

-- ---------------------------------------------------------------------------
-- 6) Trigger: group_messages INSERT → notify other members (best-effort)
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_group_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_preview text;
  v_gname text;
  r record;
begin
  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;
  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  select coalesce(nullif(trim(name), ''), 'Kadro') into v_gname
  from public.squad_groups where id = new.group_id;

  v_preview := left(trim(new.body), 100);

  for r in
    select m.user_id
    from public.squad_group_members m
    where m.group_id = new.group_id
      and m.user_id <> new.sender_id
  loop
    perform public.insert_notification(
      r.user_id,
      'group_message',
      coalesce(v_gname, 'Kadro'),
      coalesce(v_name, '@birisi') || ': ' || coalesce(v_preview, ''),
      jsonb_build_object(
        'actor_id', new.sender_id,
        'group_id', new.group_id,
        'message_id', new.id
      )
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists on_group_message_notify on public.group_messages;
create trigger on_group_message_notify
  after insert on public.group_messages
  for each row
  execute function public.notify_on_group_message();

-- ---------------------------------------------------------------------------
-- 7) mark_notifications_read helper
-- ---------------------------------------------------------------------------
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_ids is null then
    update public.notifications
    set read_at = now()
    where user_id = auth.uid() and read_at is null;
  else
    update public.notifications
    set read_at = now()
    where user_id = auth.uid()
      and read_at is null
      and id = any (p_ids);
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

-- Optional Realtime:
-- alter publication supabase_realtime add table public.notifications;

-- ========== END: 017_notifications.sql ==========

-- ========== BEGIN: 018_density_hotspots.sql ==========
-- Nool — yoğunluk halkaları (500m → 20km) için trend kümeleri
-- Sahte kampüs isimleri kaldırıldı; pinler konum + video sayısı gösterir.
-- Grid, yarıçapa göre kabalaşır (yakında sık, uzakta seyrek küme).
--
-- Supabase SQL Editor'da çalıştır (CLI migrate kullanılmıyorsa):
--   supabase/migrations/018_density_hotspots.sql

create or replace function public.get_trending_hotspots(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 500,
  p_limit integer default 40
)
returns table (
  cluster_id text,
  name text,
  latitude double precision,
  longitude double precision,
  drop_count bigint,
  distance_m double precision
)
language sql
stable
security invoker
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  ),
  params as (
    select
      greatest(coalesce(p_radius_m, 500), 100)::double precision as radius_m,
      case
        when coalesce(p_radius_m, 500) <= 1000 then 0.00055
        when coalesce(p_radius_m, 500) <= 3000 then 0.00085
        when coalesce(p_radius_m, 500) <= 10000 then 0.0012
        else 0.0022
      end as cell_deg
  ),
  fresh as (
    select
      v.id,
      v.location,
      st_snaptogrid(v.location::geometry, p.cell_deg, p.cell_deg) as cell
    from public.videos v
    cross join origin o
    cross join params p
    where v.created_at >= now() - interval '24 hours'
      and st_dwithin(v.location, o.g, p.radius_m)
      and (
        auth.uid() is null
        or public.nool_norm_username(v.username) is null
        or public.nool_norm_username(v.username) not in (select uname from blocked)
      )
  ),
  clustered as (
    select
      md5(st_astext(cell)) as cluster_id,
      st_y(st_centroid(st_collect(cell))) as latitude,
      st_x(st_centroid(st_collect(cell))) as longitude,
      count(*)::bigint as drop_count,
      st_setsrid(
        st_makepoint(
          st_x(st_centroid(st_collect(cell))),
          st_y(st_centroid(st_collect(cell)))
        ),
        4326
      )::geography as center
    from fresh
    group by cell
  )
  select
    c.cluster_id,
    -- Konum etiketi: yalnızca video sayısı (UI pin + kart)
    case
      when c.drop_count = 1 then '1 video'
      else c.drop_count::text || ' video'
    end as name,
    c.latitude,
    c.longitude,
    c.drop_count,
    st_distance(c.center, o.g) as distance_m
  from clustered c
  cross join origin o
  order by c.drop_count desc, distance_m asc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) to anon, authenticated;

comment on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) is
  'Vicinity density clusters: video counts within p_radius_m (500m–20km rings).';

-- ========== END: 018_density_hotspots.sql ==========

-- ========== BEGIN: 019_campus_email_domain.sql ==========
-- Nool — Campus feed by student email domain (not GPS)
-- Supabase SQL Editor'de çalıştırın (018 sonrası).
--
-- • profiles.student_email + email_domain → kampüs üyeliği
-- • university_id, email_domain ile senkron tutulur (geriye uyum)
-- • videos.visibility = 'campus' + campus_domain → yalnızca aynı domain okur
-- • get_campus_videos: konum yok; çağıranın domain'i dışındaki satırlar gelmez
-- • RLS: campus drop'lar yabancı domain / misafire görünmez
--
-- Doğrulama notu:
-- Flutter `claim_student_email` ile profil alanını yazar. Tam öğrenci-mail OTP
-- (magic link) için Auth → Email templates / SMTP ve isteğe bağlı
-- `auth.updateUser({ email })` veya ikinci e-posta akışı gerekir — bu migration
-- domain üyeliğini profil üzerinden kurar; OTP ayrı yapılandırma.

-- ---------------------------------------------------------------------------
-- 1) Profiles — öğrenci maili + domain
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists student_email text;

alter table public.profiles
  add column if not exists email_domain text;

comment on column public.profiles.student_email is
  'Kullanıcının kampüs üyeliği için girdiği öğrenci e-postası (örn. a@stu.istinye.edu.tr).';

comment on column public.profiles.email_domain is
  'Öğrenci e-postasından türetilen domain (lowercase). Campus feed anahtarı.';

-- Eski university_id → email_domain backfill
update public.profiles
set email_domain = lower(trim(university_id))
where email_domain is null
  and university_id is not null
  and length(trim(university_id)) > 0;

create index if not exists profiles_email_domain_idx
  on public.profiles (email_domain)
  where email_domain is not null;

-- ---------------------------------------------------------------------------
-- 2) Videos — visibility + campus_domain
-- ---------------------------------------------------------------------------
alter table public.videos
  add column if not exists visibility text not null default 'public';

alter table public.videos
  add column if not exists campus_domain text;

-- Constraint (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'videos_visibility_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos
      add constraint videos_visibility_check
      check (visibility in ('public', 'campus'));
  end if;
end $$;

comment on column public.videos.visibility is
  'public = Near You / Vibing; campus = yalnızca aynı email_domain üyeleri.';

comment on column public.videos.campus_domain is
  'visibility=campus iken uploader profilinin email_domain değeri.';

create index if not exists videos_campus_domain_idx
  on public.videos (campus_domain, created_at desc)
  where visibility = 'campus' and campus_domain is not null;

-- ---------------------------------------------------------------------------
-- 3) Helpers
-- ---------------------------------------------------------------------------
create or replace function public.nool_email_domain(p_email text)
returns text
language plpgsql
immutable
as $$
declare
  e text;
  at int;
  domain text;
begin
  e := lower(trim(coalesce(p_email, '')));
  if e = '' then
    return null;
  end if;
  at := position('@' in e);
  if at < 2 or at >= length(e) then
    return null;
  end if;
  domain := substring(e from at + 1);
  if domain = '' or position('@' in domain) > 0 or position('.' in domain) = 0 then
    return null;
  end if;
  return domain;
end;
$$;

comment on function public.nool_email_domain(text) is
  'Öğrenci e-postasından lowercase domain çıkarır; geçersizse null.';

create or replace function public.nool_my_campus_domain()
returns text
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    nullif(trim(p.email_domain), ''),
    nullif(trim(p.university_id), '')
  )
  from public.profiles p
  where p.id = auth.uid()
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4) claim_student_email — profil kampüs üyeliği
-- ---------------------------------------------------------------------------
create or replace function public.claim_student_email(p_email text)
returns public.profiles
language plpgsql
security invoker
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  domain text;
  normalized text;
  row public.profiles;
begin
  if uid is null then
    raise exception 'Kampüs e-postası için giriş yapmalısın.'
      using errcode = '42501';
  end if;

  normalized := lower(trim(coalesce(p_email, '')));
  domain := public.nool_email_domain(normalized);

  if domain is null then
    raise exception 'Geçerli bir öğrenci e-postası gir (örn. ad@stu.okul.edu.tr).'
      using errcode = '22023';
  end if;

  -- Esnek eşleşme: herhangi geçerli domain; *.edu / *.edu.tr tercih ama zorunlu değil.
  -- Spam domain engeli yok — ürün kararı: kullanıcı girdiği mailin domain’ine üye olur.

  update public.profiles
  set
    student_email = normalized,
    email_domain = domain,
    university_id = domain
  where id = uid
  returning * into row;

  if row.id is null then
    raise exception 'Profil bulunamadı.'
      using errcode = 'P0002';
  end if;

  return row;
end;
$$;

comment on function public.claim_student_email(text) is
  'Öğrenci e-postasını kaydeder; email_domain + university_id = domain. '
  'OTP doğrulama ayrı (Auth SMTP) — bu RPC profil üyeliğini yazar.';

grant execute on function public.claim_student_email(text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5) get_campus_videos — yalnızca kendi domain
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER: campus satırlar RLS'te herkese kapalı tutulur;
-- yalnızca bu RPC (aynı domain) okuyabilir → Near You / Vibing sızmaz.
create or replace function public.get_campus_videos(
  p_limit integer default 40
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision,
  reaction_counts jsonb,
  campus_domain text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_domain text;
  uid uuid := auth.uid();
begin
  if uid is null then
    return;
  end if;

  select coalesce(
    nullif(trim(p.email_domain), ''),
    nullif(trim(p.university_id), '')
  )
  into my_domain
  from public.profiles p
  where p.id = uid
  limit 1;

  if my_domain is null or my_domain = '' then
    -- Üyelik yok → boş (istemci claim UI gösterir)
    return;
  end if;

  return query
  with blocked as (
    select distinct public.nool_norm_username(pr.username) as uname
    from public.blocked_users b
    join public.profiles pr on pr.id = b.blocked_user_id
    where b.blocker_id = uid
      and public.nool_norm_username(pr.username) is not null
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    null::double precision as distance_m,
    (
      v.vibe_count::double precision
      / greatest(
          extract(epoch from (now() - v.created_at)) / 3600.0,
          0.01
        )
    ) as score,
    coalesce(v.reaction_counts, '{}'::jsonb) as reaction_counts,
    v.campus_domain
  from public.videos v
  where v.created_at >= now() - interval '24 hours'
    and v.visibility = 'campus'
    and v.campus_domain = my_domain
    and (
      public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by v.created_at desc
  limit greatest(coalesce(p_limit, 40), 1);
end;
$$;

comment on function public.get_campus_videos(integer) is
  'Campus sekmesi: çağıranın email_domain ile eşleşen campus drop’lar. '
  'Domain yoksa boş döner. Konum kullanılmaz.';

grant execute on function public.get_campus_videos(integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6) create_video — opsiyonel campus visibility
-- ---------------------------------------------------------------------------
drop function if exists public.create_video(
  uuid, text, text, text, text, text, text, text, double precision, double precision
);

create or replace function public.create_video(
  p_id uuid,
  p_device_id text,
  p_username text,
  p_caption text,
  p_subtitle text,
  p_track_label text,
  p_storage_path text,
  p_video_url text,
  p_lat double precision,
  p_lng double precision,
  p_visibility text default 'public'
)
returns public.videos
language plpgsql
security invoker
set search_path = public
as $$
declare
  row public.videos;
  vis text := lower(trim(coalesce(p_visibility, 'public')));
  domain text;
begin
  if vis not in ('public', 'campus') then
    raise exception 'visibility public veya campus olmalı.'
      using errcode = '22023';
  end if;

  domain := null;
  if vis = 'campus' then
    domain := public.nool_my_campus_domain();
    if domain is null or domain = '' then
      raise exception 'Campus drop için önce öğrenci e-postanı bağla.'
        using errcode = '42501';
    end if;
  end if;

  insert into public.videos (
    id,
    device_id,
    username,
    caption,
    subtitle,
    track_label,
    storage_path,
    video_url,
    location,
    visibility,
    campus_domain
  )
  values (
    p_id,
    p_device_id,
    p_username,
    coalesce(p_caption, ''),
    coalesce(p_subtitle, ''),
    coalesce(p_track_label, 'original audio'),
    p_storage_path,
    p_video_url,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    vis,
    domain
  )
  returning * into row;

  return row;
end;
$$;

grant execute on function public.create_video(
  uuid, text, text, text, text, text, text, text,
  double precision, double precision, text
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) RLS — doğrudan SELECT yalnızca public; campus yalnız get_campus_videos
-- ---------------------------------------------------------------------------
drop policy if exists "videos_select_fresh" on public.videos;
create policy "videos_select_fresh"
  on public.videos for select
  to anon, authenticated
  using (
    created_at >= now() - interval '24 hours'
    and coalesce(visibility, 'public') = 'public'
  );

-- Insert: campus drop yalnızca kendi domain’iyle
drop policy if exists "videos_insert_anon" on public.videos;
create policy "videos_insert_anon"
  on public.videos for insert
  to anon, authenticated
  with check (
    coalesce(visibility, 'public') = 'public'
    or (
      visibility = 'campus'
      and auth.uid() is not null
      and campus_domain is not null
      and campus_domain = public.nool_my_campus_domain()
    )
  );

-- ---------------------------------------------------------------------------
-- 8) get_nearby_videos — campus drop’ları dışla
-- ---------------------------------------------------------------------------
drop function if exists public.get_nearby_videos(
  double precision, double precision, integer, double precision
);
drop function if exists public.get_nearby_videos(
  double precision, double precision, integer
);

create function public.get_nearby_videos(
  p_lat double precision,
  p_lng double precision,
  p_limit integer default 40,
  p_radius_m double precision default null
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision,
  reaction_counts jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    st_distance(v.location, origin.g) as distance_m,
    (
      v.vibe_count::double precision
      / (
          greatest(st_distance(v.location, origin.g), 1.0)
          * greatest(
              extract(epoch from (now() - v.created_at)) / 3600.0,
              0.01
            )
        )
    ) as score,
    coalesce(v.reaction_counts, '{}'::jsonb) as reaction_counts
  from public.videos v
  cross join origin
  where v.created_at >= now() - interval '24 hours'
    and coalesce(v.visibility, 'public') = 'public'
    and (
      p_radius_m is null
      or st_dwithin(v.location, origin.g, p_radius_m)
    )
    and (
      auth.uid() is null
      or public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by score desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_nearby_videos(
  double precision, double precision, integer, double precision
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9) get_trending_hotspots — yalnızca public drop’lar
-- ---------------------------------------------------------------------------
create or replace function public.get_trending_hotspots(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 500,
  p_limit integer default 40
)
returns table (
  cluster_id text,
  name text,
  latitude double precision,
  longitude double precision,
  drop_count bigint,
  distance_m double precision
)
language sql
stable
security invoker
set search_path = public
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  ),
  params as (
    select
      greatest(coalesce(p_radius_m, 500), 100)::double precision as radius_m,
      case
        when coalesce(p_radius_m, 500) <= 1000 then 0.00055
        when coalesce(p_radius_m, 500) <= 3000 then 0.00085
        when coalesce(p_radius_m, 500) <= 10000 then 0.0012
        else 0.0022
      end as cell_deg
  ),
  fresh as (
    select
      v.id,
      v.location,
      st_snaptogrid(v.location::geometry, p.cell_deg, p.cell_deg) as cell
    from public.videos v
    cross join origin o
    cross join params p
    where v.created_at >= now() - interval '24 hours'
      and coalesce(v.visibility, 'public') = 'public'
      and st_dwithin(v.location, o.g, p.radius_m)
      and (
        auth.uid() is null
        or public.nool_norm_username(v.username) is null
        or public.nool_norm_username(v.username) not in (select uname from blocked)
      )
  ),
  clustered as (
    select
      md5(st_astext(cell)) as cluster_id,
      st_y(st_centroid(st_collect(cell))) as latitude,
      st_x(st_centroid(st_collect(cell))) as longitude,
      count(*)::bigint as drop_count,
      st_setsrid(
        st_makepoint(
          st_x(st_centroid(st_collect(cell))),
          st_y(st_centroid(st_collect(cell)))
        ),
        4326
      )::geography as center
    from fresh
    group by cell
  )
  select
    c.cluster_id,
    case
      when c.drop_count = 1 then '1 video'
      else c.drop_count::text || ' video'
    end as name,
    c.latitude,
    c.longitude,
    c.drop_count,
    st_distance(c.center, o.g) as distance_m
  from clustered c
  cross join origin o
  order by c.drop_count desc, distance_m asc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) to anon, authenticated;

-- ========== END: 019_campus_email_domain.sql ==========

-- ========== BEGIN: 020_fix_dm_rpc.sql ==========
-- Nool — Fix DM RPC name mismatch (PGRST202)
--
-- Live DB may only have public.get_or_create_dm(...), while Flutter calls
-- public.get_or_create_dm_thread(p_other_user_id uuid).
--
-- Run this file in Supabase SQL Editor NOW (after 014 if tables missing):
--   /Users/efeardaaric/Desktop/Nool/Nool/supabase/migrations/020_fix_dm_rpc.sql
--
-- If dm_threads / dm_messages do not exist yet, run 014_direct_messages.sql first:
--   /Users/efeardaaric/Desktop/Nool/Nool/supabase/migrations/014_direct_messages.sql

-- ---------------------------------------------------------------------------
-- 1) Canonical RPC Flutter expects
-- ---------------------------------------------------------------------------
create or replace function public.get_or_create_dm_thread(p_other_user_id uuid)
returns public.dm_threads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_row public.dm_threads;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if p_other_user_id is null or p_other_user_id = v_me then
    raise exception 'Invalid other user';
  end if;

  if v_me < p_other_user_id then
    v_a := v_me;
    v_b := p_other_user_id;
  else
    v_a := p_other_user_id;
    v_b := v_me;
  end if;

  select * into v_row
  from public.dm_threads
  where participant_a = v_a and participant_b = v_b;

  if found then
    return v_row;
  end if;

  insert into public.dm_threads (participant_a, participant_b)
  values (v_a, v_b)
  on conflict (participant_a, participant_b) do update
    set updated_at = public.dm_threads.updated_at
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.get_or_create_dm_thread(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Compatibility alias — older name hinted by PostgREST (get_or_create_dm)
-- Only create if missing (do not clobber a live overload with a different
-- return type / arg list).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_or_create_dm'
      and pg_get_function_identity_arguments(p.oid) = 'uuid'
  ) then
    execute $fn$
      create function public.get_or_create_dm(p_other_user_id uuid)
      returns public.dm_threads
      language sql
      security definer
      set search_path = public
      as $body$
        select * from public.get_or_create_dm_thread(p_other_user_id);
      $body$;
    $fn$;
    execute 'grant execute on function public.get_or_create_dm(uuid) to authenticated';
  end if;
end;
$$;

-- Refresh PostgREST schema cache so RPCs appear immediately.
notify pgrst, 'reload schema';

-- ========== END: 020_fix_dm_rpc.sql ==========

-- ========== BEGIN: 021_curiosity_teasers.sql ==========
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

-- ========== END: 021_curiosity_teasers.sql ==========

-- ========== BEGIN: 022_kankalar_copy.sql ==========
-- Nool — user-facing Squad/Arkadaş copy → Kankalar (notifications + curiosity)

create or replace function public.notify_on_squad_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;

  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  perform public.insert_notification(
    new.receiver_id,
    'friend_request',
    'Kanka isteği',
    coalesce(v_name, '@birisi') || ' seninle kanka olmak istiyor.',
    jsonb_build_object(
      'actor_id', new.sender_id,
      'squad_id', new.id,
      'sender_id', new.sender_id,
      'receiver_id', new.receiver_id
    )
  );

  return new;
end;
$$;

create or replace function public.notify_on_squad_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if old.status = 'rejected' and new.status = 'pending' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.sender_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.receiver_id,
      'friend_request',
      'Kanka isteği',
      coalesce(v_name, '@birisi') || ' seninle kanka olmak istiyor.',
      jsonb_build_object(
        'actor_id', new.sender_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  if old.status = 'pending' and new.status = 'accepted' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.receiver_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.sender_id,
      'friend_accepted',
      'İstek kabul edildi',
      coalesce(v_name, '@birisi') || ' kanka isteğini kabul etti.',
      jsonb_build_object(
        'actor_id', new.receiver_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  return new;
end;
$$;

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
      'Kanka tarafında hareket — detay yok, sadece sinyal.',
      'Your circle stirred',
      'Buddy-side motion — signal only, no spoilers.'
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

-- ========== END: 022_kankalar_copy.sql ==========

-- ========== BEGIN: 022_squad_groups_owner_delete.sql ==========
-- Nool — Kadro (squad circle) owner + DELETE
-- Supabase SQL Editor'de 021 sonrası çalıştırın.
--
-- Owner = created_by. DELETE cascade already on members / drops / streaks / messages.

-- ---------------------------------------------------------------------------
-- 1) Owner column + backfill (earliest member)
-- ---------------------------------------------------------------------------
alter table public.squad_groups
  add column if not exists created_by uuid references public.profiles (id) on delete set null;

comment on column public.squad_groups.created_by is
  'Kadro kurucusu — yalnızca owner DELETE edebilir.';

update public.squad_groups g
set created_by = sub.user_id
from (
  select distinct on (m.group_id)
    m.group_id,
    m.user_id
  from public.squad_group_members m
  order by m.group_id, m.joined_at asc nulls last, m.id asc
) sub
where g.id = sub.group_id
  and g.created_by is null;

create index if not exists squad_groups_created_by_idx
  on public.squad_groups (created_by);

-- ---------------------------------------------------------------------------
-- 2) Insert: creator must be auth.uid()
-- ---------------------------------------------------------------------------
drop policy if exists "squad_groups_insert_auth" on public.squad_groups;
create policy "squad_groups_insert_auth"
  on public.squad_groups for insert
  to authenticated
  with check (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) Delete: owner only (CASCADE cleans children)
-- ---------------------------------------------------------------------------
drop policy if exists "squad_groups_delete_owner" on public.squad_groups;
create policy "squad_groups_delete_owner"
  on public.squad_groups for delete
  to authenticated
  using (created_by = auth.uid());

grant delete on public.squad_groups to authenticated;

-- ========== END: 022_squad_groups_owner_delete.sql ==========

-- ========== BEGIN: 023_videos_owner_delete.sql ==========
-- Nool — own video DELETE (idempotent refresh + ownership RPC)
-- Run in Supabase Dashboard → SQL Editor after 022.
--
-- Context:
-- • videos has no user_id; ownership is device_id (+ username text).
-- • 007 already allowed DELETE with using(true); this re-asserts grants
--   and adds delete_own_video(p_video_id, p_device_id) so the client can
--   delete only rows matching the local device_id.
-- • Storage object cleanup stays in the Flutter client (bucket path from
--   videos.storage_path / video_url). Policies: 010_gdpr_storage_self_deletion.

-- ---------------------------------------------------------------------------
-- 1) Table DELETE policy + grant
-- ---------------------------------------------------------------------------
drop policy if exists "videos_delete_own" on public.videos;
create policy "videos_delete_own"
  on public.videos for delete
  to anon, authenticated
  using (true);

grant delete on public.videos to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Ownership-checked delete RPC (preferred client path)
-- ---------------------------------------------------------------------------
create or replace function public.delete_own_video(
  p_video_id uuid,
  p_device_id text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  deleted_count integer;
begin
  if p_video_id is null then
    raise exception 'delete_own_video: video_id required' using errcode = '22023';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'delete_own_video: device_id required' using errcode = '22023';
  end if;

  delete from public.videos
  where id = p_video_id
    and device_id = trim(p_device_id);

  get diagnostics deleted_count = row_count;
  if deleted_count = 0 then
    raise exception 'delete_own_video: not owner or missing'
      using errcode = '42501';
  end if;
end;
$$;

comment on function public.delete_own_video(uuid, text) is
  'Deletes a videos row only when device_id matches. Storage cleanup is client-side.';

grant execute on function public.delete_own_video(uuid, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Storage DELETE (refresh — campus-drops + legacy videos)
-- ---------------------------------------------------------------------------
drop policy if exists "campus_drops_delete" on storage.objects;
create policy "campus_drops_delete"
  on storage.objects for delete
  to anon, authenticated
  using (bucket_id = 'campus-drops');

drop policy if exists "videos_storage_delete" on storage.objects;
create policy "videos_storage_delete"
  on storage.objects for delete
  to anon, authenticated
  using (bucket_id = 'videos');

-- ========== END: 023_videos_owner_delete.sql ==========

-- ========== BEGIN: 024_auto_suspend_reported_videos.sql ==========
-- Nool — 3 farklı kullanıcı şikayet → video otomatik askıya (suspended)
--
-- Supabase SQL Editor'da çalıştırın (001–023 sonrası).
--
-- Eşik: aynı video için DISTINCT reporter_id >= 3 → videos.status = 'suspended'
-- Askıdaki videolar: get_nearby_videos / get_campus_videos / get_trending_hotspots
-- ve doğrudan SELECT (RLS) ile keşiften çıkar; istemciye dönmez.
--
-- Tek kullanıcı aynı videoyu birden fazla saydıramaz:
-- UNIQUE (reporter_id, reported_video_id) where reporter_id IS NOT NULL.

-- ---------------------------------------------------------------------------
-- 1) videos.status
-- ---------------------------------------------------------------------------
alter table public.videos
  add column if not exists status text not null default 'active';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'videos_status_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos
      add constraint videos_status_check
      check (status in ('active', 'suspended'));
  end if;
end $$;

comment on column public.videos.status is
  'active = keşfedilebilir; suspended = 3+ şikayet sonrası keşiften çıkar.';

create index if not exists videos_status_created_at_idx
  on public.videos (status, created_at desc);

-- İstemcinin status'u elle değiştirmesini engelle (suspend yalnız moderation path).
create or replace function public.nool_guard_video_status()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and new.status is distinct from old.status
     and coalesce(current_setting('nool.moderation', true), '') is distinct from 'on'
  then
    new.status := old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_nool_guard_video_status on public.videos;
create trigger trg_nool_guard_video_status
  before update of status on public.videos
  for each row
  execute function public.nool_guard_video_status();

-- ---------------------------------------------------------------------------
-- 2) reports — tek kullanıcı / video (duplicate temizliği + unique)
-- ---------------------------------------------------------------------------
-- Aynı (reporter, video) için en eski satırı tut.
delete from public.reports a
using public.reports b
where a.reporter_id is not null
  and a.reporter_id = b.reporter_id
  and a.reported_video_id = b.reported_video_id
  and a.id > b.id;

create unique index if not exists reports_reporter_video_uidx
  on public.reports (reporter_id, reported_video_id)
  where reporter_id is not null;

comment on index public.reports_reporter_video_uidx is
  'Bir kullanıcı aynı videoyu yalnızca bir kez şikayet edebilir.';

-- ---------------------------------------------------------------------------
-- 3) Trigger: ≥3 distinct reporter → suspend
-- ---------------------------------------------------------------------------
create or replace function public.nool_maybe_suspend_reported_video()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  distinct_reporters integer;
  threshold constant integer := 3;
begin
  if new.reported_video_id is null then
    return new;
  end if;

  select count(distinct r.reporter_id)::integer
  into distinct_reporters
  from public.reports r
  where r.reported_video_id = new.reported_video_id
    and r.reporter_id is not null;

  if distinct_reporters >= threshold then
    perform set_config('nool.moderation', 'on', true);
    update public.videos v
    set status = 'suspended'
    where v.id = new.reported_video_id
      and v.status is distinct from 'suspended';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_nool_maybe_suspend_reported_video on public.reports;
create trigger trg_nool_maybe_suspend_reported_video
  after insert on public.reports
  for each row
  execute function public.nool_maybe_suspend_reported_video();

comment on function public.nool_maybe_suspend_reported_video() is
  '3+ farklı reporter_id → videos.status = suspended (keşiften çıkar).';

-- Mevcut veriyi backfill et
do $$
begin
  perform set_config('nool.moderation', 'on', true);
  update public.videos v
  set status = 'suspended'
  where v.status is distinct from 'suspended'
    and (
      select count(distinct r.reporter_id)
      from public.reports r
      where r.reported_video_id = v.id
        and r.reporter_id is not null
    ) >= 3;
end $$;

-- ---------------------------------------------------------------------------
-- 4) RLS — suspended doğrudan SELECT'te görünmez
-- ---------------------------------------------------------------------------
drop policy if exists "videos_select_fresh" on public.videos;
create policy "videos_select_fresh"
  on public.videos for select
  to anon, authenticated
  using (
    created_at >= now() - interval '24 hours'
    and coalesce(visibility, 'public') = 'public'
    and coalesce(status, 'active') = 'active'
  );

-- ---------------------------------------------------------------------------
-- 5) get_campus_videos — suspended dışla
-- ---------------------------------------------------------------------------
create or replace function public.get_campus_videos(
  p_limit integer default 40
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision,
  reaction_counts jsonb,
  campus_domain text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_domain text;
  uid uuid := auth.uid();
begin
  if uid is null then
    return;
  end if;

  select coalesce(
    nullif(trim(p.email_domain), ''),
    nullif(trim(p.university_id), '')
  )
  into my_domain
  from public.profiles p
  where p.id = uid
  limit 1;

  if my_domain is null or my_domain = '' then
    return;
  end if;

  return query
  with blocked as (
    select distinct public.nool_norm_username(pr.username) as uname
    from public.blocked_users b
    join public.profiles pr on pr.id = b.blocked_user_id
    where b.blocker_id = uid
      and public.nool_norm_username(pr.username) is not null
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    null::double precision as distance_m,
    (
      v.vibe_count::double precision
      / greatest(
          extract(epoch from (now() - v.created_at)) / 3600.0,
          0.01
        )
    ) as score,
    coalesce(v.reaction_counts, '{}'::jsonb) as reaction_counts,
    v.campus_domain
  from public.videos v
  where v.created_at >= now() - interval '24 hours'
    and v.visibility = 'campus'
    and v.campus_domain = my_domain
    and coalesce(v.status, 'active') = 'active'
    and (
      public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by v.created_at desc
  limit greatest(coalesce(p_limit, 40), 1);
end;
$$;

comment on function public.get_campus_videos(integer) is
  'Campus sekmesi: aynı domain + active (suspended hariç).';

grant execute on function public.get_campus_videos(integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6) get_nearby_videos — suspended dışla
-- ---------------------------------------------------------------------------
drop function if exists public.get_nearby_videos(
  double precision, double precision, integer, double precision
);
drop function if exists public.get_nearby_videos(
  double precision, double precision, integer
);

create function public.get_nearby_videos(
  p_lat double precision,
  p_lng double precision,
  p_limit integer default 40,
  p_radius_m double precision default null
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision,
  reaction_counts jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    st_distance(v.location, origin.g) as distance_m,
    (
      v.vibe_count::double precision
      / (
          greatest(st_distance(v.location, origin.g), 1.0)
          * greatest(
              extract(epoch from (now() - v.created_at)) / 3600.0,
              0.01
            )
        )
    ) as score,
    coalesce(v.reaction_counts, '{}'::jsonb) as reaction_counts
  from public.videos v
  cross join origin
  where v.created_at >= now() - interval '24 hours'
    and coalesce(v.visibility, 'public') = 'public'
    and coalesce(v.status, 'active') = 'active'
    and (
      p_radius_m is null
      or st_dwithin(v.location, origin.g, p_radius_m)
    )
    and (
      auth.uid() is null
      or public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by score desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_nearby_videos(
  double precision, double precision, integer, double precision
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) get_trending_hotspots — suspended dışla
-- ---------------------------------------------------------------------------
create or replace function public.get_trending_hotspots(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 500,
  p_limit integer default 40
)
returns table (
  cluster_id text,
  name text,
  latitude double precision,
  longitude double precision,
  drop_count bigint,
  distance_m double precision
)
language sql
stable
security invoker
set search_path = public
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  blocked as (
    select uname from public.nool_blocked_usernames()
  ),
  params as (
    select
      greatest(coalesce(p_radius_m, 500), 100)::double precision as radius_m,
      case
        when coalesce(p_radius_m, 500) <= 1000 then 0.00055
        when coalesce(p_radius_m, 500) <= 3000 then 0.00085
        when coalesce(p_radius_m, 500) <= 10000 then 0.0012
        else 0.0022
      end as cell_deg
  ),
  fresh as (
    select
      v.id,
      v.location,
      st_snaptogrid(v.location::geometry, p.cell_deg, p.cell_deg) as cell
    from public.videos v
    cross join origin o
    cross join params p
    where v.created_at >= now() - interval '24 hours'
      and coalesce(v.visibility, 'public') = 'public'
      and coalesce(v.status, 'active') = 'active'
      and st_dwithin(v.location, o.g, p.radius_m)
      and (
        auth.uid() is null
        or public.nool_norm_username(v.username) is null
        or public.nool_norm_username(v.username) not in (select uname from blocked)
      )
  ),
  clustered as (
    select
      md5(st_astext(cell)) as cluster_id,
      st_y(st_centroid(st_collect(cell))) as latitude,
      st_x(st_centroid(st_collect(cell))) as longitude,
      count(*)::bigint as drop_count,
      st_setsrid(
        st_makepoint(
          st_x(st_centroid(st_collect(cell))),
          st_y(st_centroid(st_collect(cell)))
        ),
        4326
      )::geography as center
    from fresh
    group by cell
  )
  select
    c.cluster_id,
    case
      when c.drop_count = 1 then '1 video'
      else c.drop_count::text || ' video'
    end as name,
    c.latitude,
    c.longitude,
    c.drop_count,
    st_distance(c.center, o.g) as distance_m
  from clustered c
  cross join origin o
  order by c.drop_count desc, distance_m asc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

grant execute on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) to anon, authenticated;

comment on function public.get_trending_hotspots(
  double precision, double precision, double precision, integer
) is
  'Vicinity density clusters; suspended videolar kümeden çıkar.';

-- ========== END: 024_auto_suspend_reported_videos.sql ==========
