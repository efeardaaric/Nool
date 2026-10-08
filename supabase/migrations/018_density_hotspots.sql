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
