-- Nool — hesap silinince kullanıcının drop satırları + storage object’leri temizlensin.
-- 005’teki delete_own_account RPC’sini genişletir (007/008’e dokunmaz).

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  uname text;
  bare text;
  with_at text;
begin
  if auth.uid() is null then
    raise exception 'Oturum gerekli.' using errcode = '42501';
  end if;

  select p.username into uname
  from public.profiles p
  where p.id = auth.uid();

  if uname is not null and length(trim(uname)) > 0 then
    bare := ltrim(trim(uname), '@');
    with_at := '@' || bare;

    -- Aktif + süresi dolmuş drop satırları (username @ varyantları).
    with doomed as (
      delete from public.videos v
      where v.username in (uname, bare, with_at)
      returning v.storage_path
    )
    delete from storage.objects o
    where o.bucket_id in ('campus-drops', 'videos')
      and o.name in (select storage_path from doomed);
  end if;

  -- profiles DELETE → profiles_before_delete_gdpr → auth.users
  delete from public.profiles where id = auth.uid();
end;
$$;

comment on function public.delete_own_account() is
  'GDPR self-delete: username drop’larını + storage object’lerini temizler, sonra profil/auth siler.';

grant execute on function public.delete_own_account() to authenticated;
