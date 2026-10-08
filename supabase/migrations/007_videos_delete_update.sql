-- Profil: kendi drop’unu sil / caption düzenle.
-- (Drop’lar 24s TTL; istemci cihaz + username ile filtreler.)

drop policy if exists "videos_delete_own" on public.videos;
create policy "videos_delete_own"
  on public.videos for delete
  to anon, authenticated
  using (true);

drop policy if exists "videos_update_vibe" on public.videos;
drop policy if exists "videos_update_own" on public.videos;
create policy "videos_update_own"
  on public.videos for update
  to anon, authenticated
  using (true)
  with check (true);

grant delete on public.videos to anon, authenticated;
