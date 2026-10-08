-- Nool — In-app notifications + auto triggers (friend + DM)
-- Supabase SQL Editor'de 016_friendships.sql sonrası çalıştırın.
--
-- Optional: Database Webhook on `notifications` INSERT → Edge Function
-- `fcm-notify` (updated) for FCM push.

-- ---------------------------------------------------------------------------
-- 1) notifications table
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null
    check (type in (
      'friend_request',
      'friend_accepted',
      'dm_message',
      'group_message',
      'vibe',
      'reaction',
      'system'
    )),
  title text not null,
  body text not null default '',
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.notifications is
  'In-app notification center — user reads own rows only.';

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

-- ---------------------------------------------------------------------------
-- 2) RLS
-- ---------------------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Inserts come from security definer triggers (or service role).
-- Authenticated users should not insert arbitrary notifications.
drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, update, delete on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Helper: insert notification (security definer)
-- ---------------------------------------------------------------------------
create or replace function public.insert_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_user_id is null then
    return null;
  end if;

  -- Skip if blocked either way when actor present in data
  if (p_data ? 'actor_id') then
    if public.nool_users_blocked(
      p_user_id,
      (p_data ->> 'actor_id')::uuid
    ) then
      return null;
    end if;
  end if;

  insert into public.notifications (user_id, type, title, body, data)
  values (p_user_id, p_type, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb))
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.insert_notification(uuid, text, text, text, jsonb)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Trigger: squads INSERT pending → friend_request to receiver
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_squad_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;

  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  perform public.insert_notification(
    new.receiver_id,
    'friend_request',
    'Arkadaşlık isteği',
    coalesce(v_name, '@birisi') || ' seni arkadaş olarak eklemek istiyor.',
    jsonb_build_object(
      'actor_id', new.sender_id,
      'squad_id', new.id,
      'sender_id', new.sender_id,
      'receiver_id', new.receiver_id
    )
  );

  return new;
end;
$$;

drop trigger if exists on_squad_insert_notify on public.squads;
create trigger on_squad_insert_notify
  after insert on public.squads
  for each row
  execute function public.notify_on_squad_insert();

-- Also fire when rejected → pending reopen (UPDATE that changes status)
create or replace function public.notify_on_squad_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  -- Pending reopen (rejected → pending)
  if old.status = 'rejected' and new.status = 'pending' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.sender_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.receiver_id,
      'friend_request',
      'Arkadaşlık isteği',
      coalesce(v_name, '@birisi') || ' seni arkadaş olarak eklemek istiyor.',
      jsonb_build_object(
        'actor_id', new.sender_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  -- Accept → notify original sender
  if old.status = 'pending' and new.status = 'accepted' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.receiver_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.sender_id,
      'friend_accepted',
      'İstek kabul edildi',
      coalesce(v_name, '@birisi') || ' arkadaşlık isteğini kabul etti.',
      jsonb_build_object(
        'actor_id', new.receiver_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists on_squad_update_notify on public.squads;
create trigger on_squad_update_notify
  after update of status, sender_id, receiver_id on public.squads
  for each row
  execute function public.notify_on_squad_update();

-- ---------------------------------------------------------------------------
-- 5) Trigger: dm_messages INSERT → notify other participant
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_dm_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_other uuid;
  v_name text;
  v_preview text;
begin
  select case
    when t.participant_a = new.sender_id then t.participant_b
    else t.participant_a
  end
  into v_other
  from public.dm_threads t
  where t.id = new.thread_id;

  if v_other is null or v_other = new.sender_id then
    return new;
  end if;

  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;
  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  v_preview := left(trim(new.body), 120);

  perform public.insert_notification(
    v_other,
    'dm_message',
    'Yeni mesaj',
    coalesce(v_name, '@birisi') || ': ' || coalesce(v_preview, ''),
    jsonb_build_object(
      'actor_id', new.sender_id,
      'thread_id', new.thread_id,
      'message_id', new.id
    )
  );

  return new;
end;
$$;

drop trigger if exists on_dm_message_notify on public.dm_messages;
create trigger on_dm_message_notify
  after insert on public.dm_messages
  for each row
  execute function public.notify_on_dm_message();

-- ---------------------------------------------------------------------------
-- 6) Trigger: group_messages INSERT → notify other members (best-effort)
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_group_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_preview text;
  v_gname text;
  r record;
begin
  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;
  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  select coalesce(nullif(trim(name), ''), 'Kadro') into v_gname
  from public.squad_groups where id = new.group_id;

  v_preview := left(trim(new.body), 100);

  for r in
    select m.user_id
    from public.squad_group_members m
    where m.group_id = new.group_id
      and m.user_id <> new.sender_id
  loop
    perform public.insert_notification(
      r.user_id,
      'group_message',
      coalesce(v_gname, 'Kadro'),
      coalesce(v_name, '@birisi') || ': ' || coalesce(v_preview, ''),
      jsonb_build_object(
        'actor_id', new.sender_id,
        'group_id', new.group_id,
        'message_id', new.id
      )
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists on_group_message_notify on public.group_messages;
create trigger on_group_message_notify
  after insert on public.group_messages
  for each row
  execute function public.notify_on_group_message();

-- ---------------------------------------------------------------------------
-- 7) mark_notifications_read helper
-- ---------------------------------------------------------------------------
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_ids is null then
    update public.notifications
    set read_at = now()
    where user_id = auth.uid() and read_at is null;
  else
    update public.notifications
    set read_at = now()
    where user_id = auth.uid()
      and read_at is null
      and id = any (p_ids);
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

-- Optional Realtime:
-- alter publication supabase_realtime add table public.notifications;
