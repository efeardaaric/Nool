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
