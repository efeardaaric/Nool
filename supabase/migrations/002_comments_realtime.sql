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
