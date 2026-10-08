-- Nool — Kadro (squad circle) owner + DELETE
-- Supabase SQL Editor'de 021 sonrası çalıştırın.
--
-- Owner = created_by. DELETE cascade already on members / drops / streaks / messages.

-- ---------------------------------------------------------------------------
-- 1) Owner column + backfill (earliest member)
-- ---------------------------------------------------------------------------
alter table public.squad_groups
  add column if not exists created_by uuid references public.profiles (id) on delete set null;

comment on column public.squad_groups.created_by is
  'Kadro kurucusu — yalnızca owner DELETE edebilir.';

update public.squad_groups g
set created_by = sub.user_id
from (
  select distinct on (m.group_id)
    m.group_id,
    m.user_id
  from public.squad_group_members m
  order by m.group_id, m.joined_at asc nulls last, m.id asc
) sub
where g.id = sub.group_id
  and g.created_by is null;

create index if not exists squad_groups_created_by_idx
  on public.squad_groups (created_by);

-- ---------------------------------------------------------------------------
-- 2) Insert: creator must be auth.uid()
-- ---------------------------------------------------------------------------
drop policy if exists "squad_groups_insert_auth" on public.squad_groups;
create policy "squad_groups_insert_auth"
  on public.squad_groups for insert
  to authenticated
  with check (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) Delete: owner only (CASCADE cleans children)
-- ---------------------------------------------------------------------------
drop policy if exists "squad_groups_delete_owner" on public.squad_groups;
create policy "squad_groups_delete_owner"
  on public.squad_groups for delete
  to authenticated
  using (created_by = auth.uid());

grant delete on public.squad_groups to authenticated;
