-- Nool — Fix DM RPC name mismatch (PGRST202)
--
-- Live DB may only have public.get_or_create_dm(...), while Flutter calls
-- public.get_or_create_dm_thread(p_other_user_id uuid).
--
-- Run this file in Supabase SQL Editor NOW (after 014 if tables missing):
--   /Users/efeardaaric/Desktop/Nool/Nool/supabase/migrations/020_fix_dm_rpc.sql
--
-- If dm_threads / dm_messages do not exist yet, run 014_direct_messages.sql first:
--   /Users/efeardaaric/Desktop/Nool/Nool/supabase/migrations/014_direct_messages.sql

-- ---------------------------------------------------------------------------
-- 1) Canonical RPC Flutter expects
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
-- 2) Compatibility alias — older name hinted by PostgREST (get_or_create_dm)
-- Only create if missing (do not clobber a live overload with a different
-- return type / arg list).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_or_create_dm'
      and pg_get_function_identity_arguments(p.oid) = 'uuid'
  ) then
    execute $fn$
      create function public.get_or_create_dm(p_other_user_id uuid)
      returns public.dm_threads
      language sql
      security definer
      set search_path = public
      as $body$
        select * from public.get_or_create_dm_thread(p_other_user_id);
      $body$;
    $fn$;
    execute 'grant execute on function public.get_or_create_dm(uuid) to authenticated';
  end if;
end;
$$;

-- Refresh PostgREST schema cache so RPCs appear immediately.
notify pgrst, 'reload schema';
