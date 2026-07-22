-- Nool — profiles, squads (arkadaşlık) + GDPR self-deletion
-- Supabase SQL Editor'de çalıştırın (001–004 sonrası).

-- ---------------------------------------------------------------------------
-- 1) Profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  bio text not null default '' check (char_length(bio) <= 150),
  avatar_url text,
  created_at timestamptz not null default now(),
  constraint profiles_username_unique unique (username),
  constraint profiles_username_nonempty check (char_length(trim(username)) > 0)
);

create index if not exists profiles_username_idx
  on public.profiles (username);

comment on table public.profiles is
  'Nool kullanıcı profili — auth.users ile 1:1; silinince GDPR tetikleyicisi auth kaydını da siler.';

-- Auth kaydı oluşunca profil satırı (username metadata veya anon fallback).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
begin
  v_username := nullif(trim(coalesce(new.raw_user_meta_data ->> 'username', '')), '');
  if v_username is null then
    v_username := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');
  end if;
  if v_username is null then
    v_username := 'anon_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;

  insert into public.profiles (id, username, avatar_url)
  values (
    new.id,
    v_username,
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2) Squads (arkadaşlık istekleri)
-- ---------------------------------------------------------------------------
create table if not exists public.squads (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  receiver_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  constraint squads_sender_receiver_unique unique (sender_id, receiver_id),
  constraint squads_no_self check (sender_id <> receiver_id)
);

create index if not exists squads_sender_idx on public.squads (sender_id);
create index if not exists squads_receiver_idx on public.squads (receiver_id);
create index if not exists squads_status_idx on public.squads (status);

comment on table public.squads is
  'Squad arkadaşlık ilişkisi: pending / accepted / rejected.';

-- ---------------------------------------------------------------------------
-- 3) GDPR — Security Definer self-deletion
--
-- Flutter istemcisi auth.users silemez. Kullanıcı kendi profiles satırını
-- sildiğinde BEFORE DELETE tetikleyici auth.users kaydını hard-delete eder.
-- CASCADE profili zaten temizleyeceği için trigger RETURN NULL ile
-- orijinal DELETE'i iptal eder (çift silme / recursion engeli).
-- ---------------------------------------------------------------------------
create or replace function public.delete_user_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sadece kendi hesabını silebilir (service_role hariç güvenli yol).
  if auth.uid() is distinct from old.id then
    raise exception 'GDPR: yalnızca kendi profilinizi silebilirsiniz.'
      using errcode = '42501';
  end if;

  -- auth.users silinince profiles ON DELETE CASCADE ile gider.
  delete from auth.users where id = old.id;

  -- Bu BEFORE DELETE işlemini iptal et; cascade zaten profili kaldırır.
  return null;
end;
$$;

comment on function public.delete_user_account() is
  'profiles BEFORE DELETE — auth.users hard-delete (GDPR / App Store self-deletion).';

drop trigger if exists profiles_before_delete_gdpr on public.profiles;
create trigger profiles_before_delete_gdpr
  before delete on public.profiles
  for each row
  execute function public.delete_user_account();

-- İstemci kolaylığı: tek RPC ile kendi hesabını sil.
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
  delete from public.profiles where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Row Level Security — profiles
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all"
  on public.profiles for select
  to anon, authenticated
  using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own"
  on public.profiles for delete
  to authenticated
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 5) Row Level Security — squads
-- ---------------------------------------------------------------------------
alter table public.squads enable row level security;

drop policy if exists "squads_select_participants" on public.squads;
create policy "squads_select_participants"
  on public.squads for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

drop policy if exists "squads_insert_as_sender" on public.squads;
create policy "squads_insert_as_sender"
  on public.squads for insert
  to authenticated
  with check (auth.uid() = sender_id);

drop policy if exists "squads_update_participants" on public.squads;
create policy "squads_update_participants"
  on public.squads for update
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id)
  with check (auth.uid() = sender_id or auth.uid() = receiver_id);

drop policy if exists "squads_delete_participants" on public.squads;
create policy "squads_delete_participants"
  on public.squads for delete
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant select on public.profiles to anon, authenticated;
grant insert, update, delete on public.profiles to authenticated;

grant select, insert, update, delete on public.squads to authenticated;
