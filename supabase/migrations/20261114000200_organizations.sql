-- =============================================================================
-- 0002 · Organisations, staff access, feature flags and the moderation queue
-- =============================================================================

create table app.sports (
  code       text primary key,
  name       text not null,
  icon       text not null,
  sort_order int  not null default 0
);

create table app.organizations (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  name          text not null check (char_length(name) between 3 and 80),
  description   text check (char_length(description) <= 2000),
  owner_id      uuid not null references app.profiles (id),
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected', 'suspended')),
  is_verified   boolean not null default false,
  verified_at   timestamptz,
  sports        text[] not null default '{}',
  city          text,
  address       text,
  contact_email text,
  contact_phone text,
  logo_url      text,
  currency      text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  timezone      text not null default 'Asia/Kolkata',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index organizations_status_idx on app.organizations (status);
create trigger organizations_touch before update on app.organizations
  for each row execute function private.touch_updated_at();

-- People who can operate the organisation inside the app.
create table app.org_members (
  org_id   uuid not null references app.organizations (id) on delete cascade,
  user_id  uuid not null references app.profiles (id) on delete cascade,
  role     text not null check (role in ('owner', 'manager', 'coach', 'staff')),
  added_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index org_members_user_idx on app.org_members (user_id);

-- Capabilities an organisation can hold. `auto_grant` features come with
-- approval; the others go through a feature-access request.
create table app.features (
  key               text primary key,
  name              text not null,
  description       text not null,
  auto_grant        boolean not null default false,
  requires_verified boolean not null default false,
  sort_order        int not null default 0
);

create table app.org_features (
  org_id      uuid not null references app.organizations (id) on delete cascade,
  feature_key text not null references app.features (key) on delete cascade,
  granted_by  uuid references app.profiles (id),
  granted_at  timestamptz not null default now(),
  primary key (org_id, feature_key)
);

-- One queue for everything platform staff have to decide.
create table app.requests (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('org_approval', 'org_verification', 'feature_access')),
  org_id        uuid not null references app.organizations (id) on delete cascade,
  requester_id  uuid not null references app.profiles (id),
  feature_key   text references app.features (key),
  message       text check (char_length(message) <= 2000),
  documents     jsonb not null default '[]',
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  decided_by    uuid references app.profiles (id),
  decided_at    timestamptz,
  decision_note text,
  created_at    timestamptz not null default now(),
  check ((kind = 'feature_access') = (feature_key is not null))
);
create unique index requests_one_pending_idx
  on app.requests (org_id, kind, coalesce(feature_key, ''))
  where status = 'pending';
create index requests_queue_idx on app.requests (status, created_at);

-- User-submitted moderation reports.
create table app.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references app.profiles (id),
  target_type text not null check (target_type in ('organization', 'tournament', 'user')),
  target_id   uuid not null,
  reason      text not null check (char_length(reason) between 5 and 1000),
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  resolved_by uuid references app.profiles (id),
  resolved_at timestamptz,
  resolution  text,
  created_at  timestamptz not null default now()
);
create index reports_status_idx on app.reports (status, created_at);

-- -----------------------------------------------------------------------------
-- Organisation guards
-- -----------------------------------------------------------------------------
create function private.org_role(p_org_id uuid, p_user_id uuid)
returns text language sql stable set search_path = '' as $$
  select role from app.org_members where org_id = p_org_id and user_id = p_user_id;
$$;

-- Returns the caller's id when they hold one of `p_roles` in an organisation
-- that is allowed to operate. `p_allow_unapproved` lets owners keep editing
-- their application while it is still pending.
create function private.require_org(
  p_org_id uuid,
  p_roles text[] default array['owner', 'manager'],
  p_allow_unapproved boolean default false)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  v_uid    uuid := private.uid();
  v_role   text;
  v_status text;
begin
  select o.status, m.role into v_status, v_role
  from app.organizations o
  left join app.org_members m on m.org_id = o.id and m.user_id = v_uid
  where o.id = p_org_id;

  if v_status is null then
    perform private.fail(404, 'org_not_found', 'Organisation not found.');
  end if;
  if v_role is null or not (v_role = any (p_roles)) then
    perform private.fail(403, 'forbidden', 'You do not have access to this organisation.');
  end if;
  if v_status <> 'approved' and not p_allow_unapproved then
    perform private.fail(403, 'org_not_approved',
      case v_status
        when 'pending'   then 'This organisation is still waiting for approval.'
        when 'suspended' then 'This organisation has been suspended.'
        else 'This organisation was not approved.'
      end);
  end if;
  return v_uid;
end $$;

create function private.has_feature(p_org_id uuid, p_feature text)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from app.org_features where org_id = p_org_id and feature_key = p_feature);
$$;

create function private.require_feature(p_org_id uuid, p_feature text)
returns void language plpgsql stable set search_path = '' as $$
begin
  if not private.has_feature(p_org_id, p_feature) then
    perform private.fail(403, 'feature_not_enabled',
      format('The "%s" feature is not enabled for this organisation. Request access from the Access tab.', p_feature));
  end if;
end $$;

create function private.grant_feature(p_org_id uuid, p_feature text, p_by uuid)
returns void language sql set search_path = '' as $$
  insert into app.org_features (org_id, feature_key, granted_by)
  values (p_org_id, p_feature, p_by)
  on conflict do nothing;
$$;

-- Tells every owner / manager of an organisation about something.
create function private.notify_org(p_org_id uuid, p_kind text, p_title text, p_body text default null, p_data jsonb default '{}')
returns void language sql set search_path = '' as $$
  insert into app.notifications (user_id, kind, title, body, data)
  select m.user_id, p_kind, p_title, p_body, coalesce(p_data, '{}') || jsonb_build_object('org_id', p_org_id)
  from app.org_members m
  where m.org_id = p_org_id and m.role in ('owner', 'manager');
$$;

-- -----------------------------------------------------------------------------
-- Moderation decisions (called by the admin RPCs)
-- -----------------------------------------------------------------------------
create function private.set_org_status(p_org_id uuid, p_status text, p_by uuid)
returns void language plpgsql set search_path = '' as $$
begin
  update app.organizations set status = p_status where id = p_org_id;
  if p_status = 'approved' then
    insert into app.org_features (org_id, feature_key, granted_by)
    select p_org_id, f.key, p_by from app.features f where f.auto_grant
    on conflict do nothing;
  end if;
end $$;

create function private.decide_request(p_request_id uuid, p_approve boolean, p_note text, p_by uuid)
returns app.requests language plpgsql set search_path = '' as $$
declare
  v_req     app.requests;
  v_org     app.organizations;
  v_feature app.features;
begin
  select * into v_req from app.requests where id = p_request_id for update;
  if not found then
    perform private.fail(404, 'request_not_found', 'Request not found.');
  end if;
  if v_req.status <> 'pending' then
    perform private.fail(409, 'request_already_decided', 'This request has already been decided.');
  end if;
  select * into v_org from app.organizations where id = v_req.org_id;

  if p_approve then
    if v_req.kind = 'org_approval' then
      perform private.set_org_status(v_org.id, 'approved', p_by);
    elsif v_req.kind = 'org_verification' then
      if v_org.status <> 'approved' then
        perform private.fail(409, 'org_not_approved', 'Approve the organisation before verifying it.');
      end if;
      update app.organizations set is_verified = true, verified_at = now() where id = v_org.id;
    else
      select * into v_feature from app.features where key = v_req.feature_key;
      if v_org.status <> 'approved' then
        perform private.fail(409, 'org_not_approved', 'The organisation is not approved.');
      end if;
      if v_feature.requires_verified and not v_org.is_verified then
        perform private.fail(409, 'verification_required',
          format('"%s" can only be granted to verified organisations.', v_feature.name));
      end if;
      perform private.grant_feature(v_org.id, v_req.feature_key, p_by);
    end if;
  elsif v_req.kind = 'org_approval' then
    perform private.set_org_status(v_org.id, 'rejected', p_by);
  end if;

  update app.requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      decided_by = p_by, decided_at = now(), decision_note = private.clean(p_note)
  where id = p_request_id
  returning * into v_req;

  perform private.audit('request.' || v_req.status, 'request', v_req.id,
    jsonb_build_object('kind', v_req.kind, 'org_id', v_req.org_id, 'feature', v_req.feature_key));
  perform private.notify_org(v_org.id, 'request_decided',
    format('%s %s',
      case v_req.kind
        when 'org_approval' then 'Organisation application'
        when 'org_verification' then 'Verification request'
        else 'Feature request'
      end,
      v_req.status),
    coalesce(v_req.decision_note, v_org.name),
    jsonb_build_object('request_id', v_req.id, 'kind', v_req.kind));
  return v_req;
end $$;

-- -----------------------------------------------------------------------------
-- Read models
-- -----------------------------------------------------------------------------
create view app.v_requests as
select r.id, r.kind, r.status, r.message, r.documents, r.feature_key,
       f.name as feature_name, r.created_at, r.decided_at, r.decision_note,
       r.org_id, o.name as org_name, o.status as org_status, o.is_verified as org_is_verified,
       o.city as org_city, o.sports as org_sports,
       r.requester_id, p.display_name as requester_name,
       d.display_name as decided_by_name
from app.requests r
join app.organizations o on o.id = r.org_id
join app.profiles p on p.id = r.requester_id
left join app.features f on f.key = r.feature_key
left join app.profiles d on d.id = r.decided_by;
