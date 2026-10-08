-- Deploy with signed media playback support. Apply after 026 on staging first.
begin;
update storage.buckets set public = false where id in ('campus-drops','videos','group-drops');
drop policy if exists campus_drops_read on storage.objects;
drop policy if exists videos_storage_read on storage.objects;
drop policy if exists group_drops_storage_read on storage.objects;
drop policy if exists group_drops_storage_insert on storage.objects;

-- Invoker RLS on videos handles TTL, suspended content, verified campus and owners.
-- 024 limits public videos; add a verified same-campus selection policy.
create policy videos_select_verified_campus on public.videos for select to authenticated
  using (visibility = 'campus' and status = 'active'
    and created_at >= now() - interval '24 hours'
    and campus_domain = public.nool_my_campus_domain());
create policy nool_video_storage_read on storage.objects for select to anon, authenticated
  using (bucket_id in ('campus-drops','videos') and exists (
    select 1 from public.videos v where v.storage_path = name));
create policy nool_group_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'group-drops' and exists (
    select 1 from public.group_drops d where d.storage_path = name
      and public.is_squad_group_member(d.group_id)));
create policy nool_group_storage_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'group-drops' and exists (
    select 1 from public.squad_group_members m
      where m.group_id::text = (storage.foldername(name))[1] and m.user_id = auth.uid()));
create policy nool_group_storage_delete_owner on storage.objects for delete to authenticated
  using (bucket_id = 'group-drops' and owner_id = auth.uid()::text);
-- A nonmember must not use RLS-hidden membership rows to self-join a group.
create policy squad_groups_select_owner on public.squad_groups for select to authenticated
  using (created_by = auth.uid());
drop policy if exists squad_group_members_insert on public.squad_group_members;
create policy squad_group_members_insert on public.squad_group_members for insert to authenticated
  with check (public.is_squad_group_member(group_id) or exists (
    select 1 from public.squad_groups g where g.id = group_id and g.created_by = auth.uid()));
create or replace function public.get_campus_videos(
  p_limit integer default 40
)
returns table (
  id uuid,
  video_url text,
  username text,
  caption text,
  subtitle text,
  track_label text,
  vibe_count integer,
  comment_count integer,
  created_at timestamptz,
  distance_m double precision,
  score double precision,
  reaction_counts jsonb,
  campus_domain text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_domain text;
  uid uuid := auth.uid();
begin
  if uid is null then
    return;
  end if;

  my_domain := public.nool_my_campus_domain();

  if my_domain is null or my_domain = '' then
    return;
  end if;

  return query
  with blocked as (
    select distinct public.nool_norm_username(pr.username) as uname
    from public.blocked_users b
    join public.profiles pr on pr.id = b.blocked_user_id
    where b.blocker_id = uid
      and public.nool_norm_username(pr.username) is not null
  )
  select
    v.id,
    v.video_url,
    v.username,
    v.caption,
    v.subtitle,
    v.track_label,
    v.vibe_count,
    v.comment_count,
    v.created_at,
    null::double precision as distance_m,
    (
      v.vibe_count::double precision
      / greatest(
          extract(epoch from (now() - v.created_at)) / 3600.0,
          0.01
        )
    ) as score,
    coalesce(v.reaction_counts, '{}'::jsonb) as reaction_counts,
    v.campus_domain
  from public.videos v
  where v.created_at >= now() - interval '24 hours'
    and v.visibility = 'campus'
    and v.campus_domain = my_domain
    and coalesce(v.status, 'active') = 'active'
    and (
      public.nool_norm_username(v.username) is null
      or public.nool_norm_username(v.username) not in (select uname from blocked)
    )
  order by v.created_at desc
  limit greatest(coalesce(p_limit, 40), 1);
end;
$$;
revoke all on function public.get_campus_videos(integer) from public, anon;
grant execute on function public.get_campus_videos(integer) to authenticated;
commit;
