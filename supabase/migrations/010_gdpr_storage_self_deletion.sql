-- Nool — GDPR / KVKK: storage + medya self-deletion destekleri
-- ============================================================================: Supabase Dashboard → SQL Editor'de çalıştırın (005–008 sonrası).
--
-- ---------------------------------------------------------------------------
-- Sınırlar (okuyun)
-- ---------------------------------------------------------------------------
-- • videos.user_id YOK — drop sahipliği device_id + username (text).
--   Storage + videos satır silme Flutter tarafında, profil silmeden ÖNCE yapılır
--   (ProfileService.deleteUserAccountAndAssets).
-- • comments yalnızca device_id / username taşır; auth.users ile FK yok.
--   Video silinince o videoya ait yorumlar CASCADE ile gider.
--   Başka kullanıcıların videolarına yazılmış yorumlar device_id ile
--   istemcide temizlenir; sunucu bunu auth.uid() ile eşleyemez.
-- • squads / blocked_users: profiles / auth CASCADE ile temizlenir.
-- • reports.reporter_id: ON DELETE SET NULL (şikayet anonim kalır).
-- • Storage: campus-drops yolları genelde {deviceId}/{videoId}.ext;
--   avatars: {uid}/{uuid}.ext. İstemci her iki klasörü + videos.storage_path
--   listesini siler.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1a) comments DELETE (fallback istemci yolu; RPC security definer tercih)
-- ---------------------------------------------------------------------------
drop policy if exists "comments_delete" on public.comments;
create policy "comments_delete"
  on public.comments for delete
  to anon, authenticated
  using (true);

grant delete on public.comments to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1b) Storage DELETE politikaları (GDPR wipe + drop silme)
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

-- avatars_delete_own zaten 006'da: folder = auth.uid()

-- ---------------------------------------------------------------------------
-- 2) GDPR tetikleyici — profiles BEFORE DELETE → auth.users hard-delete
--    (005 ile aynı sözleşme; refresh / idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.delete_user_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is distinct from old.id then
    raise exception 'GDPR: yalnızca kendi profilinizi silebilirsiniz.'
      using errcode = '42501';
  end if;

  -- auth.users → profiles ON DELETE CASCADE
  delete from auth.users where id = old.id;

  -- Orijinal profiles DELETE'i iptal (çift silme / recursion engeli).
  return null;
end;
$$;

comment on function public.delete_user_account() is
  'profiles BEFORE DELETE — auth.users hard-delete (GDPR / KVKK / App Store).';

drop trigger if exists profiles_before_delete_gdpr on public.profiles;
create trigger profiles_before_delete_gdpr
  before delete on public.profiles
  for each row
  execute function public.delete_user_account();

-- ---------------------------------------------------------------------------
-- 3) RPC — istemci tek çağrıyla hesabı siler (storage wipe SONRASI)
-- ---------------------------------------------------------------------------
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  -- profiles DELETE → profiles_before_delete_gdpr → auth.users
  -- Squads / blocked_users cascade; reports.reporter_id null olur.
  delete from public.profiles where id = auth.uid();
end;
$$;

comment on function public.delete_own_account() is
  'GDPR self-deletion RPC. Flutter önce Storage + videos/comments silmeli, '
  'sonra bu RPC''yi çağırmalı.';

grant execute on function public.delete_own_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Opsiyonel yardımcı: kendi device/username medyasını DB'den temizle
--    (Storage ayrı — istemci Storage API kullanır)
-- ---------------------------------------------------------------------------
create or replace function public.purge_own_video_rows(
  p_device_id text default null,
  p_usernames text[] default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
  v_n integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  -- Yorumlar: bu cihazın bıraktığı (videolar CASCADE + yabancı videolar)
  if p_device_id is not null and length(trim(p_device_id)) > 0 then
    delete from public.comments where device_id = p_device_id;
  end if;

  if p_usernames is not null and cardinality(p_usernames) > 0 then
    delete from public.comments
    where public.nool_norm_username(username) = any (
      select public.nool_norm_username(u) from unnest(p_usernames) as u
    );
  end if;

  -- Videolar (yorumlar video_id CASCADE ile gider)
  if p_device_id is not null and length(trim(p_device_id)) > 0 then
    delete from public.videos where device_id = p_device_id;
    get diagnostics v_n = row_count;
    v_deleted := v_deleted + v_n;
  end if;

  if p_usernames is not null and cardinality(p_usernames) > 0 then
    delete from public.videos
    where public.nool_norm_username(username) = any (
      select public.nool_norm_username(u) from unnest(p_usernames) as u
    );
    get diagnostics v_n = row_count;
    v_deleted := v_deleted + v_n;
  end if;

  return v_deleted;
end;
$$;

comment on function public.purge_own_video_rows(text, text[]) is
  'GDPR: oturum açıkken device_id / username ile videos + comments satırlarını siler. '
  'Storage nesneleri istemci tarafından silinmelidir. '
  'LIMIT: comments/videos auth.uid taşımaz — yanlış device_id gönderilmemeli.';

grant execute on function public.purge_own_video_rows(text, text[]) to authenticated;
