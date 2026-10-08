-- Apply after 025, first on staging. Deploy together with the updated client.
-- Historical device IDs and usernames are not proof of account ownership.
begin;

alter table public.videos add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.comments add column if not exists user_id uuid references auth.users(id) on delete cascade;

-- Only trust Storage's server-recorded uploader for historical video ownership.
update public.videos v set user_id = o.owner_id::uuid
from storage.objects o
where v.user_id is null and o.bucket_id in ('campus-drops', 'videos')
  and o.name = v.storage_path
  and o.owner_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and exists (select 1 from auth.users u where u.id::text = o.owner_id);

create or replace function public.nool_assign_content_owner()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  new.user_id := auth.uid();
  select p.username into new.username from public.profiles p where p.id = auth.uid();
  if new.username is null then raise exception 'Profile required.' using errcode = '42501'; end if;
  return new;
end $$;
drop trigger if exists nool_video_owner on public.videos;
create trigger nool_video_owner before insert on public.videos
  for each row execute function public.nool_assign_content_owner();
drop trigger if exists nool_comment_owner on public.comments;
create trigger nool_comment_owner before insert on public.comments
  for each row execute function public.nool_assign_content_owner();

-- Replace permissive mutation policies rather than add policies (RLS uses OR).
do $$ declare p record; begin
  for p in select tablename, policyname from pg_policies
    where schemaname = 'public' and tablename in ('videos','comments')
      and cmd in ('INSERT','UPDATE','DELETE','ALL')
  loop execute format('drop policy %I on public.%I', p.policyname, p.tablename); end loop;
end $$;
create policy videos_insert_owner on public.videos for insert to authenticated
  with check (user_id = auth.uid()
    and split_part(storage_path, '/', 1) = auth.uid()::text
    and status = 'active' and vibe_count = 0 and comment_count = 0
    and (visibility = 'public' or (visibility = 'campus'
      and campus_domain = public.nool_my_campus_domain())));
create policy videos_update_owner on public.videos for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy videos_delete_owner on public.videos for delete to authenticated
  using (user_id = auth.uid());
-- Owners need to select their rows for UPDATE/DELETE, including suspended drops.
create policy videos_select_owner on public.videos for select to authenticated
  using (user_id = auth.uid());
create policy comments_insert_owner on public.comments for insert to authenticated
  with check (user_id = auth.uid() and length(trim(body)) between 1 and 500
    and exists (select 1 from public.videos v where v.id = video_id));
create policy comments_delete_owner on public.comments for delete to authenticated
  using (user_id = auth.uid());
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments for select to anon, authenticated
  using (exists (select 1 from public.videos v where v.id = video_id));

revoke insert, update, delete on public.videos from anon;
revoke insert on public.videos from authenticated;
grant insert(id,device_id,username,caption,subtitle,track_label,storage_path,video_url,location,visibility,campus_domain)
  on public.videos to authenticated;
revoke update on public.videos from authenticated;
grant update(caption) on public.videos to authenticated;
revoke insert, update, delete on public.comments from anon;
revoke update on public.comments from authenticated;

-- Counters run in trusted triggers; clients cannot write another author's row.
create or replace function public.bump_comment_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.videos set comment_count = comment_count + 1 where id = new.video_id;
  return new;
end $$;

create or replace function public.delete_own_video(p_video_id uuid, p_device_id text)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode = '42501'; end if;
  delete from public.videos where id = p_video_id and user_id = auth.uid();
  if not found then raise exception 'Not owner or missing.' using errcode = '42501'; end if;
end $$;
revoke all on function public.delete_own_video(uuid,text) from public, anon;
grant execute on function public.delete_own_video(uuid,text) to authenticated;

create or replace function public.purge_own_video_rows(p_device_id text default null, p_usernames text[] default null)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer; begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode = '42501'; end if;
  delete from public.comments where user_id = auth.uid();
  delete from public.videos where user_id = auth.uid();
  get diagnostics n = row_count; return n;
end $$;
revoke all on function public.purge_own_video_rows(text,text[]) from public, anon;
grant execute on function public.purge_own_video_rows(text,text[]) to authenticated;

-- Only the authenticated revocation backend can authorize Apple account deletion.
create table if not exists public.nool_account_deletion_authorizations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  expires_at timestamptz not null
);
alter table public.nool_account_deletion_authorizations enable row level security;
revoke all on public.nool_account_deletion_authorizations from public, anon, authenticated;
grant select, insert, update, delete on public.nool_account_deletion_authorizations to service_role;

-- Remove the profile-delete/auth-delete recursion; delete via the explicit RPC.
drop trigger if exists profiles_before_delete_gdpr on public.profiles;
revoke delete on public.profiles from authenticated, anon;
create or replace function public.delete_own_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode = '42501'; end if;
  if exists (select 1 from auth.identities where user_id = auth.uid() and provider = 'apple')
    and not exists (select 1 from public.nool_account_deletion_authorizations
      where user_id = auth.uid() and expires_at > now()) then
    raise exception 'Reauthorize Apple account deletion first.' using errcode = '42501';
  end if;
  if exists (select 1 from storage.objects where owner_id = auth.uid()::text
    and bucket_id in ('campus-drops','videos','avatars','group-drops')) then
    raise exception 'Delete account media first.' using errcode = '55000';
  end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

-- Restrict Storage writes/deletes using the authenticated uploader, never device_id.
drop policy if exists campus_drops_insert on storage.objects;
drop policy if exists videos_storage_insert on storage.objects;
drop policy if exists campus_drops_delete on storage.objects;
drop policy if exists videos_storage_delete on storage.objects;
create policy nool_video_storage_insert_owner on storage.objects for insert to authenticated
  with check (bucket_id in ('campus-drops','videos')
    and (storage.foldername(name))[1] = auth.uid()::text);
create policy nool_video_storage_delete_owner on storage.objects for delete to authenticated
  using (bucket_id in ('campus-drops','videos') and owner_id = auth.uid()::text);

-- Public profile reads must not expose student email addresses or push tokens.
revoke select on public.profiles from anon, authenticated;
grant select(id,username,bio,avatar_url,created_at,email_domain,university_id)
  on public.profiles to anon, authenticated;
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(p) from public.profiles p where p.id = auth.uid();
$$;
revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;

-- A supplied email is not verification. Derive membership from confirmed Auth email.
create or replace function public.nool_guard_campus_membership()
returns trigger language plpgsql security definer set search_path = public as $$
declare verified text; domain text; begin
  if tg_op = 'INSERT' or new.student_email is distinct from old.student_email
    or new.email_domain is distinct from old.email_domain
    or new.university_id is distinct from old.university_id then
    if new.student_email is null and new.email_domain is null and new.university_id is null then return new; end if;
    select lower(email) into verified from auth.users
      where id = new.id and email_confirmed_at is not null;
    domain := public.nool_email_domain(verified);
    if verified is null or domain is null
      or (domain !~ '(^|\.)edu(\.[a-z]{2})?$' and domain !~ '(^|\.)ac\.[a-z]{2}$')
      or lower(trim(new.student_email)) is distinct from verified
      or new.email_domain is distinct from domain or new.university_id is distinct from domain then
      raise exception 'Use your verified university sign-in email.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists nool_verified_campus on public.profiles;
create trigger nool_verified_campus before insert or update of student_email,email_domain,university_id
  on public.profiles for each row execute function public.nool_guard_campus_membership();

-- Ignore any unverified legacy membership, even before its profile is edited.
create or replace function public.nool_my_campus_domain()
returns text language sql stable security definer set search_path = public as $$
  select public.nool_email_domain(u.email) from auth.users u
  join public.profiles p on p.id = u.id
  where u.id = auth.uid() and u.email_confirmed_at is not null
    and lower(p.student_email) = lower(u.email)
    and p.email_domain = public.nool_email_domain(u.email)
    and (p.email_domain ~ '(^|\.)edu(\.[a-z]{2})?$' or p.email_domain ~ '(^|\.)ac\.[a-z]{2}$');
$$;
revoke all on function public.nool_my_campus_domain() from public, anon;
grant execute on function public.nool_my_campus_domain() to authenticated;

-- claim_student_email returns a private profile only to its owner.
create or replace function public.claim_student_email(p_email text)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare row public.profiles; domain text; begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode = '42501'; end if;
  domain := public.nool_email_domain(p_email);
  update public.profiles set student_email = lower(trim(p_email)),
    email_domain = domain, university_id = domain where id = auth.uid() returning * into row;
  if row.id is null then raise exception 'Profile missing.' using errcode = 'P0002'; end if;
  return row;
end $$;
revoke all on function public.claim_student_email(text) from public, anon;
grant execute on function public.claim_student_email(text) to authenticated;

create or replace function public.get_my_media_objects()
returns table(bucket_id text, name text) language sql stable security definer set search_path = public as $$
  select o.bucket_id, o.name from storage.objects o
  where o.owner_id = auth.uid()::text
    and o.bucket_id in ('campus-drops','videos','avatars','group-drops');
$$;
revoke all on function public.get_my_media_objects() from public, anon;
grant execute on function public.get_my_media_objects() to authenticated;
-- Bind username identity to the authenticated author, including after a rename.
create or replace function public.nool_sync_author_username()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.videos set username = new.username where user_id = new.id;
  update public.comments set username = new.username where user_id = new.id;
  return new;
end $$;
create trigger nool_sync_author_username after update of username on public.profiles
  for each row execute function public.nool_sync_author_username();
commit;
