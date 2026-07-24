-- Nool — kullanıcı engelleme (blocks) + etkileşim kapıları
-- Supabase SQL Editor'de 001–007 sonrası çalıştırın.
--
-- Bu migration:
--   • blocks tablosu + RLS
--   • are_users_blocked / list_my_blocks yardımcıları
--   • send_squad_request / get_or_create_dm / send_dm / list_my_conversations
--     engelli çiftlerde etkileşimi keser
--   • Engellemede pending/accepted squad satırını temizler

-- ---------------------------------------------------------------------------
-- 1) Blocks
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocks_pair_unique unique (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists blocks_blocker_idx on public.blocks (blocker_id);
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);

comment on table public.blocks is
  'Yönlü engel: blocker_id, blocked_id kullanıcısını engeller. Karşılıklı etkileşim her iki yönde de kesilir.';

-- ---------------------------------------------------------------------------
-- 2) Helpers
-- ---------------------------------------------------------------------------
create or replace function public._is_blocked_either(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocks bl
    where (bl.blocker_id = a and bl.blocked_id = b)
       or (bl.blocker_id = b and bl.blocked_id = a)
  );
$$;

-- İstemci: ben ↔ diğer engelli mi?
create or replace function public.are_users_blocked(p_other_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  if p_other_user_id is null or p_other_user_id = auth.uid() then
    return false;
  end if;
  return public._is_blocked_either(auth.uid(), p_other_user_id);
end;
$$;

grant execute on function public.are_users_blocked(uuid) to authenticated;

-- Engellediğim profiller (unblock UI).
create or replace function public.list_my_blocks()
returns table (
  blocked_id uuid,
  username text,
  avatar_url text,
  bio text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id as blocked_id,
    p.username,
    p.avatar_url,
    p.bio,
    b.created_at
  from public.blocks b
  join public.profiles p on p.id = b.blocked_id
  where auth.uid() is not null
    and b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

grant execute on function public.list_my_blocks() to authenticated;

-- Engelle + squad bağını kopar.
create or replace function public.block_user(p_blocked_id uuid)
returns public.blocks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.blocks;
begin
  if v_uid is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;
  if p_blocked_id = v_uid then
    raise exception 'Kendini engelleyemezsin.';
  end if;
  if not exists (select 1 from public.profiles where id = p_blocked_id) then
    raise exception 'Kullanıcı bulunamadı.' using errcode = 'P0002';
  end if;

  insert into public.blocks (blocker_id, blocked_id)
  values (v_uid, p_blocked_id)
  on conflict (blocker_id, blocked_id) do update
    set created_at = excluded.created_at
  returning * into v_row;

  -- Squad / arkadaşlık bağını kaldır (DM de squad ister).
  delete from public.squads
  where (sender_id = v_uid and receiver_id = p_blocked_id)
     or (sender_id = p_blocked_id and receiver_id = v_uid);

  return v_row;
end;
$$;

grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(p_blocked_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  delete from public.blocks
  where blocker_id = auth.uid()
    and blocked_id = p_blocked_id;
end;
$$;

grant execute on function public.unblock_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Gate existing RPCs (007 ile uyumlu — create or replace)
-- ---------------------------------------------------------------------------
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
  if public._is_blocked_either(v_uid, p_receiver_id) then
    raise exception 'Bu kullanıcıyla etkileşim engellendi.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = p_receiver_id) then
    raise exception 'Kullanıcı bulunamadı.' using errcode = 'P0002';
  end if;

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
  if public._is_blocked_either(v_uid, p_other_user_id) then
    raise exception 'Bu kullanıcıyla mesajlaşma engellendi.' using errcode = '42501';
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

  if public._is_blocked_either(v_uid, v_other) then
    raise exception 'Bu kullanıcıyla mesajlaşma engellendi.' using errcode = '42501';
  end if;

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
    and not public._is_blocked_either(
      auth.uid(),
      case
        when c.participant_low = auth.uid() then c.participant_high
        else c.participant_low
      end
    )
  order by c.last_message_at desc nulls last, c.created_at desc;
$$;

grant execute on function public.list_my_conversations() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Row Level Security — blocks
-- ---------------------------------------------------------------------------
alter table public.blocks enable row level security;

-- Engelleyen kendi listesini görür; engellenen de (bilgi / UI) satırı görebilir.
drop policy if exists "blocks_select_participants" on public.blocks;
create policy "blocks_select_participants"
  on public.blocks for select
  to authenticated
  using (auth.uid() = blocker_id or auth.uid() = blocked_id);

drop policy if exists "blocks_insert_as_blocker" on public.blocks;
create policy "blocks_insert_as_blocker"
  on public.blocks for insert
  to authenticated
  with check (auth.uid() = blocker_id);

drop policy if exists "blocks_delete_as_blocker" on public.blocks;
create policy "blocks_delete_as_blocker"
  on public.blocks for delete
  to authenticated
  using (auth.uid() = blocker_id);

-- ---------------------------------------------------------------------------
-- 5) Grants
-- ---------------------------------------------------------------------------
grant select, insert, delete on public.blocks to authenticated;
