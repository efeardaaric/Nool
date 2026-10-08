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
