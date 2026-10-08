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
