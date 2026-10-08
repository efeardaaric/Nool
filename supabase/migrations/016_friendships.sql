-- Nool — Friendship helpers on existing `squads` table
-- Supabase SQL Editor'de 001–015 sonrası çalıştırın.
--
-- `squads` zaten arkadaşlık istekleri (pending / accepted / rejected).
-- Bu migration: unordered pair uniqueness, block-aware send RPC,
-- reject / cancel / unfriend RPCs.

-- ---------------------------------------------------------------------------
-- 1) Unordered unique pair (A→B ve B→A aynı anda olamaz)
-- ---------------------------------------------------------------------------
create unique index if not exists squads_unordered_pair_uidx
  on public.squads (
    least(sender_id, receiver_id),
    greatest(sender_id, receiver_id)
  );

-- ---------------------------------------------------------------------------
-- 2) Block helper (either direction)
-- ---------------------------------------------------------------------------
create or replace function public.nool_users_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.blocked_users b
    where (b.blocker_id = p_a and b.blocked_user_id = p_b)
       or (b.blocker_id = p_b and b.blocked_user_id = p_a)
  );
$$;

grant execute on function public.nool_users_blocked(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) send_friend_request(receiver_id) — block-aware insert / revive
-- ---------------------------------------------------------------------------
create or replace function public.send_friend_request(p_receiver_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_receiver_id is null or p_receiver_id = v_me then
    raise exception 'Invalid receiver';
  end if;

  if public.nool_users_blocked(v_me, p_receiver_id) then
    raise exception 'User is blocked' using errcode = '42501';
  end if;

  -- Existing edge either direction?
  select * into v_row
  from public.squads s
  where (s.sender_id = v_me and s.receiver_id = p_receiver_id)
     or (s.sender_id = p_receiver_id and s.receiver_id = v_me)
  limit 1;

  if found then
    if v_row.status = 'accepted' then
      return v_row;
    end if;
    if v_row.status = 'pending' then
      return v_row;
    end if;
    -- rejected → reopen as new pending from me
    update public.squads
    set
      sender_id = v_me,
      receiver_id = p_receiver_id,
      status = 'pending',
      created_at = now()
    where id = v_row.id
    returning * into v_row;
    return v_row;
  end if;

  insert into public.squads (sender_id, receiver_id, status)
  values (v_me, p_receiver_id, 'pending')
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.send_friend_request(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) accept / reject / cancel / unfriend
-- ---------------------------------------------------------------------------
create or replace function public.accept_friend_request(p_request_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_row from public.squads where id = p_request_id;
  if not found then
    raise exception 'Request not found';
  end if;

  if v_row.receiver_id <> v_me then
    raise exception 'Only receiver can accept' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  if public.nool_users_blocked(v_row.sender_id, v_row.receiver_id) then
    raise exception 'User is blocked' using errcode = '42501';
  end if;

  update public.squads
  set status = 'accepted'
  where id = p_request_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.accept_friend_request(uuid) to authenticated;

create or replace function public.reject_friend_request(p_request_id uuid)
returns public.squads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_row from public.squads where id = p_request_id;
  if not found then
    raise exception 'Request not found';
  end if;

  if v_row.receiver_id <> v_me then
    raise exception 'Only receiver can reject' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  update public.squads
  set status = 'rejected'
  where id = p_request_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.reject_friend_request(uuid) to authenticated;

create or replace function public.cancel_friend_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.squads;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_row from public.squads where id = p_request_id;
  if not found then
    return;
  end if;

  if v_row.sender_id <> v_me then
    raise exception 'Only sender can cancel' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  delete from public.squads where id = p_request_id;
end;
$$;

grant execute on function public.cancel_friend_request(uuid) to authenticated;

create or replace function public.remove_friend(p_other_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  delete from public.squads
  where status = 'accepted'
    and (
      (sender_id = v_me and receiver_id = p_other_user_id)
      or (sender_id = p_other_user_id and receiver_id = v_me)
    );
end;
$$;

grant execute on function public.remove_friend(uuid) to authenticated;
