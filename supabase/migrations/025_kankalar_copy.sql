-- Nool — user-facing Squad/Arkadaş copy → Kankalar (notifications + curiosity)

create or replace function public.notify_on_squad_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  select coalesce(nullif(trim(username), ''), 'birisi') into v_name
  from public.profiles where id = new.sender_id;

  if v_name is not null and left(v_name, 1) <> '@' then
    v_name := '@' || v_name;
  end if;

  perform public.insert_notification(
    new.receiver_id,
    'friend_request',
    'Kanka isteği',
    coalesce(v_name, '@birisi') || ' seninle kanka olmak istiyor.',
    jsonb_build_object(
      'actor_id', new.sender_id,
      'squad_id', new.id,
      'sender_id', new.sender_id,
      'receiver_id', new.receiver_id
    )
  );

  return new;
end;
$$;

create or replace function public.notify_on_squad_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if old.status = 'rejected' and new.status = 'pending' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.sender_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.receiver_id,
      'friend_request',
      'Kanka isteği',
      coalesce(v_name, '@birisi') || ' seninle kanka olmak istiyor.',
      jsonb_build_object(
        'actor_id', new.sender_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  if old.status = 'pending' and new.status = 'accepted' then
    select coalesce(nullif(trim(username), ''), 'birisi') into v_name
    from public.profiles where id = new.receiver_id;
    if v_name is not null and left(v_name, 1) <> '@' then
      v_name := '@' || v_name;
    end if;
    perform public.insert_notification(
      new.sender_id,
      'friend_accepted',
      'İstek kabul edildi',
      coalesce(v_name, '@birisi') || ' kanka isteğini kabul etti.',
      jsonb_build_object(
        'actor_id', new.receiver_id,
        'squad_id', new.id,
        'sender_id', new.sender_id,
        'receiver_id', new.receiver_id
      )
    );
  end if;

  return new;
end;
$$;

create or replace function public.nool_curiosity_copy(p_kind text)
returns table (title text, body text, en_title text, en_body text)
language sql
immutable
as $$
  select t.title, t.body, t.en_title, t.en_body
  from (values
    (
      'nearby',
      'Kampüsünde bir şeyler oluyor',
      'Radar ısındı — bakmadan bilmeyeceksin.',
      'Something''s heating up on campus',
      'Radar''s warm — you won''t know until you look.'
    ),
    (
      'radar',
      'Radar''da hareket var',
      'Yakında drop''lar kıpırdıyor. Spoiler yok.',
      'Movement on the radar',
      'Nearby drops are stirring. No spoilers.'
    ),
    (
      'streak',
      'Ateş sönmek üzere',
      'Kadronun kaos ateşi zayıf düşüyor — kaçırma.',
      'Fire about to die',
      'Your circle chaos fire is fading — don''t ghost it.'
    ),
    (
      'unseen',
      'Görmediğin vibes birikiyor',
      'Akışta seni bekleyen kaos var. Merak et.',
      'Unseen vibes stacking up',
      'Chaos is waiting in the feed. Stay curious.'
    ),
    (
      'friends',
      'Kadro kıpırdadı',
      'Kanka tarafında hareket — detay yok, sadece sinyal.',
      'Your circle stirred',
      'Buddy-side motion — signal only, no spoilers.'
    ),
    (
      'night',
      'Gece Nool''uyor',
      'Kampüs uyanık. Sen?',
      'Night mode: Nool''ing',
      'Campus is awake. Are you?'
    )
  ) as t(kind, title, body, en_title, en_body)
  where t.kind = p_kind;
$$;
