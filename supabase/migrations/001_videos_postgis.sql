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
