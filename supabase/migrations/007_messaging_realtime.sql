-- Nool — 1:1 DM (Instagram tarzı) + squad Realtime
-- Supabase SQL Editor'de 001–006 sonrası çalıştırın.
--
-- Bu migration:
--   • conversations / messages tabloları + RLS
--   • arkadaşlık kontrolü ile get_or_create_dm RPC
--   • squads + messages + conversations Realtime yayını
--   • conversation list / mesaj geçmişi indeksleri

-- ---------------------------------------------------------------------------
-- 1) Conversations (1:1 — participant_low < participant_high)
-- ---------------------------------------------------------------------------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  participant_low uuid not null references public.profiles (id) on delete cascade,
  participant_high uuid not null references public.profiles (id) on delete cascade,
  last_message_at timestamptz,
  last_message_preview text not null default '',
  created_at timestamptz not null default now(),
  constraint conversations_ordered check (participant_low < participant_high),
  constraint conversations_pair_unique unique (participant_low, participant_high)
);

create index if not exists conversations_low_idx
  on public.conversations (participant_low, last_message_at desc nulls last);
create index if not exists conversations_high_idx
  on public.conversations (participant_high, last_message_at desc nulls last);
create index if not exists conversations_last_msg_idx
  on public.conversations (last_message_at desc nulls last);

comment on table public.conversations is
  '1:1 DM konuşması — yalnızca accepted squad çiftleri.';

-- ---------------------------------------------------------------------------
-- 2) Messages
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null
    check (char_length(trim(body)) > 0 and char_length(body) <= 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at asc);
create index if not exists messages_sender_idx
  on public.messages (sender_id);

comment on table public.messages is
  'DM mesajları — yalnızca conversation katılımcıları okur/yazar.';

-- ---------------------------------------------------------------------------
-- 3) Helpers
-- ---------------------------------------------------------------------------
create or replace function public._are_squad_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.squads s
    where s.status = 'accepted'
      and (
        (s.sender_id = a and s.receiver_id = b)
        or (s.sender_id = b and s.receiver_id = a)
      )
  );
$$;

create or replace function public._is_conversation_participant(cid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = cid
      and (c.participant_low = uid or c.participant_high = uid)
  );
$$;

-- Son mesaj önizlemesini conversation üzerinde tut.
create or replace function public.bump_conversation_preview()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
  set
    last_message_at = new.created_at,
    last_message_preview = left(new.body, 120)
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists trg_bump_conversation_preview on public.messages;
create trigger trg_bump_conversation_preview
  after insert on public.messages
  for each row
  execute function public.bump_conversation_preview();

-- ---------------------------------------------------------------------------
-- 4) RPCs
-- ---------------------------------------------------------------------------

-- Squad reddet (yalnızca alıcı).
create or replace function public.reject_squad_request(p_request_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.squads;
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  update public.squads
  set status = 'rejected'
  where id = p_request_id
    and receiver_id = auth.uid()
    and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'İstek bulunamadı veya reddedilemez.' using errcode = 'P0002';
  end if;

  return v_row;
end;
$$;

grant execute on function public.reject_squad_request(uuid) to authenticated;

-- Squad isteği gönder / rejected sonrası yeniden dene.
create or replace function public.send_squad_request(p_receiver_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.squads;
begin
  if v_uid is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;
  if p_receiver_id = v_uid then
    raise exception 'Kendine squad isteği gönderemezsin.';
  end if;
  if not exists (select 1 from public.profiles where id = p_receiver_id) then
    raise exception 'Kullanıcı bulunamadı.' using errcode = 'P0002';
  end if;

  -- Mevcut satır (her iki yön).
  select * into v_row
  from public.squads
  where (sender_id = v_uid and receiver_id = p_receiver_id)
     or (sender_id = p_receiver_id and receiver_id = v_uid)
  limit 1;

  if found then
    if v_row.status = 'accepted' then
      return v_row;
    end if;
    if v_row.status = 'pending' then
      return v_row;
    end if;
    -- rejected → yeniden pending (gönderen = şimdiki kullanıcı)
    update public.squads
    set
      sender_id = v_uid,
      receiver_id = p_receiver_id,
      status = 'pending',
      created_at = now()
    where id = v_row.id
    returning * into v_row;
    return v_row;
  end if;

  insert into public.squads (sender_id, receiver_id, status)
  values (v_uid, p_receiver_id, 'pending')
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.send_squad_request(uuid) to authenticated;

-- DM konuşması aç / getir (yalnızca accepted squad).
create or replace function public.get_or_create_dm(p_other_user_id uuid)
returns public.conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_low uuid;
  v_high uuid;
  v_row public.conversations;
begin
  if v_uid is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;
  if p_other_user_id = v_uid then
    raise exception 'Kendinle sohbet açılamaz.';
  end if;
  if not public._are_squad_friends(v_uid, p_other_user_id) then
    raise exception 'Önce squad olmalısınız.' using errcode = '42501';
  end if;

  if v_uid < p_other_user_id then
    v_low := v_uid;
    v_high := p_other_user_id;
  else
    v_low := p_other_user_id;
    v_high := v_uid;
  end if;

  select * into v_row
  from public.conversations
  where participant_low = v_low and participant_high = v_high;

  if found then
    return v_row;
  end if;

  insert into public.conversations (participant_low, participant_high)
  values (v_low, v_high)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.get_or_create_dm(uuid) to authenticated;

-- Mesaj gönder (katılımcı + arkadaşlık kontrolü).
create or replace function public.send_dm(
  p_conversation_id uuid,
  p_body text
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_conv public.conversations;
  v_other uuid;
  v_body text := trim(p_body);
  v_row public.messages;
begin
  if v_uid is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;
  if v_body is null or char_length(v_body) = 0 then
    raise exception 'Boş mesaj gönderilemez.';
  end if;
  if char_length(v_body) > 2000 then
    raise exception 'Mesaj en fazla 2000 karakter olabilir.';
  end if;

  select * into v_conv
  from public.conversations
  where id = p_conversation_id;

  if not found then
    raise exception 'Sohbet bulunamadı.' using errcode = 'P0002';
  end if;

  if v_conv.participant_low <> v_uid and v_conv.participant_high <> v_uid then
    raise exception 'Bu sohbete yazamazsın.' using errcode = '42501';
  end if;

  v_other := case
    when v_conv.participant_low = v_uid then v_conv.participant_high
    else v_conv.participant_low
  end;

  if not public._are_squad_friends(v_uid, v_other) then
    raise exception 'Squad bağı yok — mesaj engellendi.' using errcode = '42501';
  end if;

  insert into public.messages (conversation_id, sender_id, body)
  values (p_conversation_id, v_uid, v_body)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.send_dm(uuid, text) to authenticated;

-- Inbox listesi: conversation + karşı profil + önizleme.
create or replace function public.list_my_conversations()
returns table (
  conversation_id uuid,
  other_user_id uuid,
  other_username text,
  other_avatar_url text,
  last_message_at timestamptz,
  last_message_preview text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id as conversation_id,
    case
      when c.participant_low = auth.uid() then c.participant_high
      else c.participant_low
    end as other_user_id,
    p.username as other_username,
    p.avatar_url as other_avatar_url,
    c.last_message_at,
    c.last_message_preview,
    c.created_at
  from public.conversations c
  join public.profiles p
    on p.id = case
      when c.participant_low = auth.uid() then c.participant_high
      else c.participant_low
    end
  where auth.uid() is not null
    and (c.participant_low = auth.uid() or c.participant_high = auth.uid())
  order by c.last_message_at desc nulls last, c.created_at desc;
$$;

grant execute on function public.list_my_conversations() to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Row Level Security
-- ---------------------------------------------------------------------------
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

drop policy if exists "conversations_select_participants" on public.conversations;
create policy "conversations_select_participants"
  on public.conversations for select
  to authenticated
  using (
    auth.uid() = participant_low or auth.uid() = participant_high
  );

-- Insert/update yalnızca RPC (security definer) üzerinden.
drop policy if exists "conversations_no_direct_insert" on public.conversations;
create policy "conversations_no_direct_insert"
  on public.conversations for insert
  to authenticated
  with check (false);

drop policy if exists "conversations_no_direct_update" on public.conversations;
create policy "conversations_no_direct_update"
  on public.conversations for update
  to authenticated
  using (false);

drop policy if exists "messages_select_participants" on public.messages;
create policy "messages_select_participants"
  on public.messages for select
  to authenticated
  using (public._is_conversation_participant(conversation_id, auth.uid()));

drop policy if exists "messages_no_direct_insert" on public.messages;
create policy "messages_no_direct_insert"
  on public.messages for insert
  to authenticated
  with check (false);

drop policy if exists "messages_update_read" on public.messages;
create policy "messages_update_read"
  on public.messages for update
  to authenticated
  using (
    public._is_conversation_participant(conversation_id, auth.uid())
    and sender_id <> auth.uid()
  )
  with check (
    public._is_conversation_participant(conversation_id, auth.uid())
    and sender_id <> auth.uid()
  );

-- ---------------------------------------------------------------------------
-- 6) Grants
-- ---------------------------------------------------------------------------
grant select on public.conversations to authenticated;
grant select, update on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Realtime publication
-- ---------------------------------------------------------------------------
-- UPDATE oldRecord için (squad kabul tespiti).
alter table public.squads replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.messages;
  exception
    when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.conversations;
  exception
    when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.squads;
  exception
    when duplicate_object then null;
  end;
end $$;
