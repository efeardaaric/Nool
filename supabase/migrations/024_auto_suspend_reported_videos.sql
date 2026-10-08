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
