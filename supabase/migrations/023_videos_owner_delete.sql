-- Nool — own video DELETE (idempotent refresh + ownership RPC)
-- Run in Supabase Dashboard → SQL Editor after 022.
--
-- Context:
-- • videos has no user_id; ownership is device_id (+ username text).
-- • 007 already allowed DELETE with using(true); this re-asserts grants
--   and adds delete_own_video(p_video_id, p_device_id) so the client can
--   delete only rows matching the local device_id.
-- • Storage object cleanup stays in the Flutter client (bucket path from
--   videos.storage_path / video_url). Policies: 010_gdpr_storage_self_deletion.

-- ---------------------------------------------------------------------------
-- 1) Table DELETE policy + grant
-- ---------------------------------------------------------------------------
drop policy if exists "videos_delete_own" on public.videos;
create policy "videos_delete_own"
  on public.videos for delete
  to anon, authenticated
  using (true);

grant delete on public.videos to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Ownership-checked delete RPC (preferred client path)
-- ---------------------------------------------------------------------------
create or replace function public.delete_own_video(
  p_video_id uuid,
  p_device_id text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  deleted_count integer;
begin
  if p_video_id is null then
    raise exception 'delete_own_video: video_id required' using errcode = '22023';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'delete_own_video: device_id required' using errcode = '22023';
  end if;

  delete from public.videos
  where id = p_video_id
    and device_id = trim(p_device_id);

  get diagnostics deleted_count = row_count;
  if deleted_count = 0 then
    raise exception 'delete_own_video: not owner or missing'
      using errcode = '42501';
  end if;
end;
$$;

comment on function public.delete_own_video(uuid, text) is
  'Deletes a videos row only when device_id matches. Storage cleanup is client-side.';

grant execute on function public.delete_own_video(uuid, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Storage DELETE (refresh — campus-drops + legacy videos)
-- ---------------------------------------------------------------------------
drop policy if exists "campus_drops_delete" on storage.objects;
create policy "campus_drops_delete"
  on storage.objects for delete
  to anon, authenticated
  using (bucket_id = 'campus-drops');

drop policy if exists "videos_storage_delete" on storage.objects;
create policy "videos_storage_delete"
  on storage.objects for delete
  to anon, authenticated
  using (bucket_id = 'videos');
