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
