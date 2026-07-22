-- campus-drops storage bucket (Mystery Camera uploads)
insert into storage.buckets (id, name, public)
values ('campus-drops', 'campus-drops', true)
on conflict (id) do nothing;

drop policy if exists "campus_drops_read" on storage.objects;
create policy "campus_drops_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'campus-drops');

drop policy if exists "campus_drops_insert" on storage.objects;
create policy "campus_drops_insert"
  on storage.objects for insert
  to anon, authenticated
  with check (bucket_id = 'campus-drops');
