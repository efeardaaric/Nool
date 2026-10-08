-- Nool — profiles.university_id for Campus feed tab
-- Supabase SQL Editor'de çalıştırın (011 sonrası).
--
-- Campus sekmesi: aynı university_id'ye sahip uploader'ların
-- son 24s videoları (istemci: videos.username → profiles.username join).

alter table public.profiles
  add column if not exists university_id text;

comment on column public.profiles.university_id is
  'Kampüs / üniversite anahtarı (örn. okul slug veya e-posta domain). '
  'Campus feed filtresi için kullanılır.';

create index if not exists profiles_university_id_idx
  on public.profiles (university_id)
  where university_id is not null;
