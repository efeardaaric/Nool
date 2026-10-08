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
