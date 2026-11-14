-- =============================================================================
-- 0001 · Foundation
--
-- Schema layout (the security model of the whole backend):
--   app      tables + internal read-model views. Never exposed through the API.
--   private  internal functions: guards, domain logic, the tournament engine.
--            No client role can execute anything in here.
--   public   the API surface. Only SECURITY DEFINER RPCs with a pinned empty
--            search_path live here; they authenticate the caller, authorise
--            the action and then delegate to `private`.
--
-- Client roles (anon / authenticated) get EXECUTE on selected public RPCs and
-- nothing else: no table privileges, and RLS is enabled without policies on
-- every table as a second line of defence.
-- =============================================================================

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists app;
create schema if not exists private;

revoke all on schema app from public, anon, authenticated;
revoke all on schema private from public, anon, authenticated;

-- Functions are not callable by default. Postgres grants EXECUTE to PUBLIC
-- globally and Supabase adds per-schema grants for the API roles, so both are
-- withdrawn here; the last migration re-revokes everything and then grants the
-- public RPCs one by one.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges in schema private revoke execute on functions from anon, authenticated;
alter default privileges in schema app revoke all on tables from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Errors. `PTxxx` SQLSTATEs are turned into HTTP status xxx by PostgREST and
-- reach the app as PostgrestException(code: 'PTxxx', message: <slug>, details).
-- -----------------------------------------------------------------------------
create function private.fail(p_status int, p_slug text, p_detail text default null)
returns void language plpgsql set search_path = '' as $$
begin
  raise exception using
    errcode = 'PT' || p_status::text,
    message = p_slug,
    detail  = coalesce(p_detail, p_slug);
end $$;

create function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Profiles & platform roles
-- -----------------------------------------------------------------------------
create table app.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null check (char_length(display_name) between 1 and 60),
  username      text unique check (username ~ '^[a-z0-9_]{3,24}$'),
  avatar_url    text,
  phone         text,
  city          text,
  bio           text check (char_length(bio) <= 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger profiles_touch before update on app.profiles
  for each row execute function private.touch_updated_at();

create table app.platform_roles (
  user_id    uuid primary key references app.profiles (id) on delete cascade,
  role       text not null check (role in ('admin', 'moderator')),
  granted_by uuid references app.profiles (id),
  granted_at timestamptz not null default now()
);

create table app.audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid references app.profiles (id) on delete set null,
  action     text not null,
  entity     text not null,
  entity_id  uuid,
  data       jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index audit_log_created_idx on app.audit_log (created_at desc);

create table app.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references app.profiles (id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text,
  data       jsonb not null default '{}',
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on app.notifications (user_id, created_at desc);

-- A profile row for every auth user.
create function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into app.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Player'), 60)
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- -----------------------------------------------------------------------------
-- Guards
-- -----------------------------------------------------------------------------
create function private.uid()
returns uuid language plpgsql stable set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    perform private.fail(401, 'not_authenticated', 'Sign in to continue.');
  end if;
  return v_uid;
end $$;

create function private.platform_role(p_user_id uuid)
returns text language sql stable set search_path = '' as $$
  select role from app.platform_roles where user_id = p_user_id;
$$;

-- Moderators can review the queue; only admins can change roles and features.
create function private.require_staff(p_admin_only boolean default false)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  v_uid  uuid := private.uid();
  v_role text := private.platform_role(v_uid);
begin
  if v_role is null or (p_admin_only and v_role <> 'admin') then
    perform private.fail(403, 'forbidden', 'Platform staff only.');
  end if;
  return v_uid;
end $$;

create function private.audit(p_action text, p_entity text, p_entity_id uuid, p_data jsonb default '{}')
returns void language sql set search_path = '' as $$
  insert into app.audit_log (actor_id, action, entity, entity_id, data)
  values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_data, '{}'));
$$;

create function private.notify(p_user_id uuid, p_kind text, p_title text, p_body text default null, p_data jsonb default '{}')
returns void language sql set search_path = '' as $$
  insert into app.notifications (user_id, kind, title, body, data)
  select p_user_id, p_kind, p_title, p_body, coalesce(p_data, '{}')
  where p_user_id is not null;
$$;

-- Trims, and turns blank strings into null. Used on every free-text input.
create function private.clean(p_text text)
returns text language sql immutable set search_path = '' as $$
  select nullif(btrim(p_text), '');
$$;

create function private.slugify(p_text text)
returns text language sql immutable set search_path = '' as $$
  select coalesce(nullif(btrim(regexp_replace(lower(p_text), '[^a-z0-9]+', '-', 'g'), '-'), ''), 'item');
$$;

-- Resolves a teammate / staff member by @username or e-mail address.
create function private.find_user(p_handle text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_handle text := lower(btrim(coalesce(p_handle, '')));
  v_id     uuid;
begin
  if v_handle = '' then
    return null;
  end if;
  if position('@' in v_handle) > 1 then
    select u.id into v_id from auth.users u where lower(u.email) = v_handle limit 1;
  else
    select p.id into v_id from app.profiles p where p.username = ltrim(v_handle, '@');
  end if;
  return v_id;
end $$;
