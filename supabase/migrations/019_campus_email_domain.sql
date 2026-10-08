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
