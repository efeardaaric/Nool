-- Nool — 24 saat TTL: süresi dolmuş video satırları + storage object’leri silinsin.
-- Supabase SQL Editor'de 001–009 sonrası çalıştırın.
--
-- RLS zaten 24 saatten eski satırları gizler; bu migration fiziksel temizlik yapar.
-- İstemci `purge_expired_videos` RPC’sini ara sıra çağırabilir; pg_cron varsa saatlik job kurulur.

create or replace function public.purge_expired_videos()
returns integer
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  deleted_count integer := 0;
begin
  with doomed as (
    delete from public.videos v
    where v.created_at < now() - interval '24 hours'
    returning v.storage_path
  ),
  removed_storage as (
    delete from storage.objects o
    where o.bucket_id in ('campus-drops', 'videos')
      and o.name in (select storage_path from doomed where storage_path is not null)
    returning 1
  )
  select count(*)::integer into deleted_count from doomed;

  return coalesce(deleted_count, 0);
end;
$$;

comment on function public.purge_expired_videos() is
  '24 saatten eski videos satırlarını ve ilişkili storage object’lerini siler. Dönüş: silinen satır sayısı.';

-- Anon/authenticated çağırabilir (security definer; yalnızca süresi dolmuşları siler).
grant execute on function public.purge_expired_videos() to anon, authenticated;

-- pg_cron varsa saatlik temizlik (extension yoksa sessizce atlanır).
-- $do$ etiketi: iç stringlerde $$ kullanılsa bile dış blok bozulmasın.
do $do$
begin
  begin
    create extension if not exists pg_cron with schema extensions;
  exception
    when others then
      raise notice 'pg_cron yok — purge_expired_videos manuel / istemci RPC ile çalışır.';
      return;
  end;

  begin
    perform cron.unschedule('purge-old-nool-videos');
  exception
    when others then null;
  end;

  begin
    -- Düz string kullan: iç içe $$ do bloğunu erken kapatır (syntax error at "select").
    perform cron.schedule(
      'purge-old-nool-videos',
      '20 * * * *',
      'select public.purge_expired_videos();'
    );
  exception
    when others then
      raise notice 'cron.schedule başarısız — Dashboard’dan Edge Function / cron ekleyin.';
  end;
end $do$;
