-- =============================================================================
-- 0010 · Public API: session, catalogue, discovery, organisation lifecycle
--
-- Conventions for every function in `public`:
--   * SECURITY DEFINER with an empty search_path, every name schema-qualified
--   * the first statement authenticates (private.uid) and authorises
--     (private.require_org / private.require_staff) the caller
--   * input arrives as scalars or one jsonb document that is read field by
--     field, never interpolated into SQL
--   * the result is jsonb, built from the app.v_* read models
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Session
-- -----------------------------------------------------------------------------
create function public.me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  return (
    select jsonb_build_object(
      'profile', to_jsonb(p),
      'email', (select u.email from auth.users u where u.id = v_uid),
      'platform_role', private.platform_role(v_uid),
      'organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', o.id, 'name', o.name, 'role', m.role, 'status', o.status,
                 'is_verified', o.is_verified, 'logo_url', o.logo_url, 'currency', o.currency,
                 'features', coalesce((select jsonb_agg(f.feature_key) from app.org_features f where f.org_id = o.id), '[]'::jsonb))
               order by o.name)
        from app.org_members m join app.organizations o on o.id = m.org_id
        where m.user_id = v_uid), '[]'::jsonb),
      'unread_notifications', (select count(*) from app.notifications n where n.user_id = v_uid and n.read_at is null))
    from app.profiles p where p.id = v_uid);
end $$;

create function public.profile_update(p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  begin
    update app.profiles
    set display_name = coalesce(private.clean(p_patch ->> 'display_name'), display_name),
        username   = case when p_patch ? 'username' then lower(private.clean(p_patch ->> 'username')) else username end,
        phone      = case when p_patch ? 'phone' then private.clean(p_patch ->> 'phone') else phone end,
        city       = case when p_patch ? 'city' then private.clean(p_patch ->> 'city') else city end,
        bio        = case when p_patch ? 'bio' then private.clean(p_patch ->> 'bio') else bio end,
        avatar_url = case when p_patch ? 'avatar_url' then private.clean(p_patch ->> 'avatar_url') else avatar_url end
    where id = v_uid;
  exception
    when unique_violation then
      perform private.fail(409, 'username_taken', 'That username is already taken.');
    when check_violation then
      perform private.fail(422, 'invalid_profile',
        'Usernames are 3-24 lowercase letters, digits or underscores; names are up to 60 characters.');
  end;
  return public.me();
end $$;

create function public.notifications_list(p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(n) order by n.created_at desc)
    from (select id, kind, title, body, data, read_at, created_at
          from app.notifications where user_id = v_uid
          order by created_at desc limit least(greatest(p_limit, 1), 200)) n), '[]'::jsonb);
end $$;

create function public.notifications_mark_read()
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  update app.notifications set read_at = now() where user_id = v_uid and read_at is null;
end $$;

-- Reference data the app is driven by: sports, rulesets, formats, templates.
create function public.catalog()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'sports', (select jsonb_agg(to_jsonb(s) order by s.sort_order) from app.sports s),
    'features', (select jsonb_agg(to_jsonb(f) order by f.sort_order) from app.features f),
    'rulesets', (select jsonb_agg(to_jsonb(r) order by r.sort_order) from app.rulesets r),
    'stage_formats', (
      select jsonb_agg(jsonb_build_object(
               'key', f.key, 'name', f.name, 'description', f.description,
               'needs_winner', f.needs_winner, 'options', f.options) order by f.sort_order)
      from app.stage_formats f),
    'format_templates', (select jsonb_agg(to_jsonb(t) order by t.sort_order) from app.format_templates t),
    'metrics', (select jsonb_agg(to_jsonb(d) order by d.sport_code, d.sort_order)
                from app.metric_definitions d where d.org_id is null));
$$;

-- -----------------------------------------------------------------------------
-- Discovery
-- -----------------------------------------------------------------------------
create function public.orgs_search(
  p_query text default null, p_sport text default null, p_limit int default 30, p_offset int default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.is_verified desc, q.name), '[]'::jsonb)
  from (
    select o.id, o.name, o.description, o.city, o.sports, o.logo_url, o.is_verified, o.currency,
           (select count(*)::int from app.resources r
            join app.facilities f on f.id = r.facility_id
            where r.org_id = o.id and r.is_active and f.is_active) as resource_count,
           (select min(r.price) from app.resources r where r.org_id = o.id and r.is_active) as min_price
    from app.organizations o
    where o.status = 'approved'
      and (private.clean(p_query) is null
           or o.name ilike '%' || private.clean(p_query) || '%'
           or o.city ilike '%' || private.clean(p_query) || '%')
      and (private.clean(p_sport) is null or p_sport = any (o.sports))
    order by o.is_verified desc, o.name
    limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0)
  ) q;
$$;

-- Public profile of an organisation. Unapproved organisations are only
-- visible to their own team and to platform staff.
create function public.org_detail(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid  uuid := auth.uid();
  v_role text := private.org_role(p_org_id, v_uid);
  v_org  app.organizations;
begin
  select * into v_org from app.organizations where id = p_org_id;
  if not found or (v_org.status <> 'approved' and v_role is null and private.platform_role(v_uid) is null) then
    perform private.fail(404, 'org_not_found', 'Organisation not found.');
  end if;
  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', v_org.id, 'name', v_org.name, 'description', v_org.description, 'status', v_org.status,
      'is_verified', v_org.is_verified, 'sports', v_org.sports, 'city', v_org.city,
      'address', v_org.address, 'contact_email', v_org.contact_email,
      'contact_phone', v_org.contact_phone, 'logo_url', v_org.logo_url,
      'currency', v_org.currency, 'timezone', v_org.timezone),
    'my_role', v_role,
    'facilities', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', f.id, 'name', f.name, 'address', f.address, 'city', f.city,
               'resources', coalesce((
                 select jsonb_agg(to_jsonb(r) order by r.sport_code, r.name)
                 from app.v_resources r where r.facility_id = f.id and r.is_active), '[]'::jsonb))
             order by f.name)
      from app.facilities f where f.org_id = p_org_id and f.is_active), '[]'::jsonb),
    'plans', coalesce((
      select jsonb_agg(to_jsonb(pl) order by pl.price)
      from app.membership_plans pl where pl.org_id = p_org_id and pl.is_active), '[]'::jsonb),
    'tournaments', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.starts_on desc)
      from app.v_tournaments t
      where t.org_id = p_org_id and t.status not in ('draft', 'cancelled')), '[]'::jsonb),
    'my_memberships', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.created_at desc)
      from app.v_memberships m
      where m.org_id = p_org_id and m.user_id = v_uid
        and m.status in ('pending', 'active', 'paused')), '[]'::jsonb));
end $$;

create function public.report_content(p_target_type text, p_target_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  if p_target_type not in ('organization', 'tournament', 'user')
     or char_length(coalesce(private.clean(p_reason), '')) < 5 then
    perform private.fail(422, 'invalid_report', 'Tell us what is wrong in a few words.');
  end if;
  insert into app.reports (reporter_id, target_type, target_id, reason)
  values (v_uid, p_target_type, p_target_id, private.clean(p_reason));
end $$;

-- -----------------------------------------------------------------------------
-- Organisation lifecycle
-- -----------------------------------------------------------------------------
create function public.org_create(p_org jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := private.uid();
  v_name   text := private.clean(p_org ->> 'name');
  v_sports text[];
  v_slug   text;
  v_id     uuid;
begin
  if v_name is null or char_length(v_name) not between 3 and 80 then
    perform private.fail(422, 'invalid_name', 'Give the organisation a name of 3 to 80 characters.');
  end if;
  select coalesce(array_agg(s.code), '{}') into v_sports
  from app.sports s
  where s.code in (select jsonb_array_elements_text(coalesce(p_org -> 'sports', '[]'::jsonb)));
  if cardinality(v_sports) = 0 then
    perform private.fail(422, 'invalid_sports', 'Pick at least one sport.');
  end if;
  if (select count(*) from app.organizations where owner_id = v_uid and status = 'pending') >= 3 then
    perform private.fail(409, 'too_many_pending', 'You already have three organisations waiting for approval.');
  end if;

  v_slug := private.slugify(v_name);
  if exists (select 1 from app.organizations where slug = v_slug) then
    v_slug := v_slug || '-' || substr(gen_random_uuid()::text, 1, 6);
  end if;

  insert into app.organizations (slug, name, description, owner_id, sports, city, address,
                                 contact_email, contact_phone, currency, timezone)
  values (v_slug, v_name, private.clean(p_org ->> 'description'), v_uid, v_sports,
          private.clean(p_org ->> 'city'), private.clean(p_org ->> 'address'),
          private.clean(p_org ->> 'contact_email'), private.clean(p_org ->> 'contact_phone'),
          coalesce(upper(private.clean(p_org ->> 'currency')), 'INR'),
          coalesce(private.clean(p_org ->> 'timezone'), 'Asia/Kolkata'))
  returning id into v_id;

  insert into app.org_members (org_id, user_id, role) values (v_id, v_uid, 'owner');
  insert into app.requests (kind, org_id, requester_id, message)
  values ('org_approval', v_id, v_uid, private.clean(p_org ->> 'message'));
  perform private.audit('org.created', 'organization', v_id, jsonb_build_object('name', v_name));
  return jsonb_build_object('id', v_id);
exception
  when check_violation then
    perform private.fail(422, 'invalid_org', 'Check the currency code and text lengths.');
    return null;
end $$;

create function public.org_update(p_org_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager'], true);
begin
  update app.organizations
  set name          = coalesce(private.clean(p_patch ->> 'name'), name),
      description   = case when p_patch ? 'description' then private.clean(p_patch ->> 'description') else description end,
      city          = case when p_patch ? 'city' then private.clean(p_patch ->> 'city') else city end,
      address       = case when p_patch ? 'address' then private.clean(p_patch ->> 'address') else address end,
      contact_email = case when p_patch ? 'contact_email' then private.clean(p_patch ->> 'contact_email') else contact_email end,
      contact_phone = case when p_patch ? 'contact_phone' then private.clean(p_patch ->> 'contact_phone') else contact_phone end,
      logo_url      = case when p_patch ? 'logo_url' then private.clean(p_patch ->> 'logo_url') else logo_url end,
      timezone      = coalesce(private.clean(p_patch ->> 'timezone'), timezone),
      sports        = case when p_patch ? 'sports'
                           then (select coalesce(array_agg(s.code), sports) from app.sports s
                                 where s.code in (select jsonb_array_elements_text(p_patch -> 'sports')))
                           else sports end
  where id = p_org_id;
end $$;

-- Dashboard header for the manage section.
create function public.org_overview(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff'], true);
  v_org app.organizations;
  v_month date := date_trunc('month', current_date)::date;
begin
  select * into v_org from app.organizations where id = p_org_id;
  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', v_org.id, 'name', v_org.name, 'description', v_org.description, 'status', v_org.status,
      'is_verified', v_org.is_verified, 'sports', v_org.sports, 'city', v_org.city,
      'address', v_org.address, 'contact_email', v_org.contact_email,
      'contact_phone', v_org.contact_phone, 'logo_url', v_org.logo_url,
      'currency', v_org.currency, 'timezone', v_org.timezone),
    'my_role', private.org_role(p_org_id, v_uid),
    'features', coalesce((select jsonb_agg(feature_key) from app.org_features where org_id = p_org_id), '[]'::jsonb),
    'stats', jsonb_build_object(
      'facilities', (select count(*) from app.facilities where org_id = p_org_id and is_active),
      'resources', (select count(*) from app.resources where org_id = p_org_id and is_active),
      'bookings_today', (select count(*) from app.bookings b
                         where b.org_id = p_org_id and b.status in ('pending', 'confirmed', 'completed')
                           and (lower(b.during) at time zone v_org.timezone)::date
                               = (now() at time zone v_org.timezone)::date),
      'bookings_upcoming', (select count(*) from app.bookings b
                            where b.org_id = p_org_id and b.status in ('pending', 'confirmed')
                              and lower(b.during) > now()),
      'bookings_pending', (select count(*) from app.bookings b
                           where b.org_id = p_org_id and b.status = 'pending'),
      'members_active', (select count(*) from app.memberships where org_id = p_org_id and status = 'active'),
      'members_pending', (select count(*) from app.memberships where org_id = p_org_id and status = 'pending'),
      'mentees', (select count(*) from app.memberships m join app.membership_plans pl on pl.id = m.plan_id
                  where m.org_id = p_org_id and m.status = 'active' and pl.tracks_performance),
      'employees', (select count(*) from app.employees where org_id = p_org_id and is_active),
      'payments_due', (select coalesce(sum(amount), 0) from app.payments where org_id = p_org_id and status = 'pending'),
      'month_income', (select coalesce(sum(amount), 0) from private.ledger_window(p_org_id, v_month, current_date)
                       where direction = 'income'),
      'month_expense', (select coalesce(sum(amount), 0) from private.ledger_window(p_org_id, v_month, current_date)
                        where direction = 'expense'),
      'tournaments_active', (select count(*) from app.tournaments
                             where org_id = p_org_id and status in ('open', 'closed', 'live')),
      'entrants_pending', (select count(*) from app.entrants en
                           join app.tournament_events e on e.id = en.event_id
                           where e.org_id = p_org_id and en.status = 'pending'),
      'requests_pending', (select count(*) from app.requests where org_id = p_org_id and status = 'pending')));
end $$;

-- Features, verification state and the requests an organisation has filed.
create function public.org_access(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager'], true);
begin
  return (
    select jsonb_build_object(
      'status', o.status, 'is_verified', o.is_verified, 'verified_at', o.verified_at,
      'features', (
        select jsonb_agg(jsonb_build_object(
                 'key', f.key, 'name', f.name, 'description', f.description,
                 'auto_grant', f.auto_grant, 'requires_verified', f.requires_verified,
                 'enabled', exists (select 1 from app.org_features x where x.org_id = o.id and x.feature_key = f.key),
                 'pending', exists (select 1 from app.requests r
                                    where r.org_id = o.id and r.feature_key = f.key and r.status = 'pending'))
               order by f.sort_order)
        from app.features f),
      'requests', coalesce((
        select jsonb_agg(to_jsonb(r) order by r.created_at desc)
        from app.v_requests r where r.org_id = o.id), '[]'::jsonb))
    from app.organizations o where o.id = p_org_id);
end $$;

create function public.org_request_verification(p_org_id uuid, p_message text, p_documents jsonb default '[]')
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id);
begin
  if (select is_verified from app.organizations where id = p_org_id) then
    perform private.fail(409, 'already_verified', 'This organisation is already verified.');
  end if;
  if char_length(coalesce(private.clean(p_message), '')) < 10 then
    perform private.fail(422, 'invalid_request',
      'Describe the organisation and how it can be verified (registration number, website, address).');
  end if;
  insert into app.requests (kind, org_id, requester_id, message, documents)
  values ('org_verification', p_org_id, v_uid, private.clean(p_message),
          case when jsonb_typeof(p_documents) = 'array' then p_documents else '[]'::jsonb end);
exception when unique_violation then
  perform private.fail(409, 'request_pending', 'A verification request is already waiting for review.');
end $$;

create function public.org_request_feature(p_org_id uuid, p_feature_key text, p_message text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := private.require_org(p_org_id);
  v_feature app.features;
begin
  select * into v_feature from app.features where key = p_feature_key;
  if not found then
    perform private.fail(404, 'feature_not_found', 'Unknown feature.');
  end if;
  if private.has_feature(p_org_id, p_feature_key) then
    perform private.fail(409, 'feature_enabled', 'This feature is already enabled.');
  end if;
  if v_feature.requires_verified and not (select is_verified from app.organizations where id = p_org_id) then
    perform private.fail(409, 'verification_required',
      format('"%s" is only available to verified organisations. Apply for verification first.', v_feature.name));
  end if;
  insert into app.requests (kind, org_id, requester_id, feature_key, message)
  values ('feature_access', p_org_id, v_uid, p_feature_key, private.clean(p_message));
exception when unique_violation then
  perform private.fail(409, 'request_pending', 'A request for this feature is already waiting for review.');
end $$;

create function public.org_request_withdraw(p_request_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid;
  v_uid uuid;
begin
  select org_id into v_org from app.requests where id = p_request_id and status = 'pending' and kind <> 'org_approval';
  if v_org is null then
    perform private.fail(404, 'request_not_found', 'No pending request to withdraw.');
  end if;
  v_uid := private.require_org(v_org, array['owner', 'manager'], true);
  update app.requests set status = 'withdrawn', decided_at = now() where id = p_request_id;
end $$;

-- -----------------------------------------------------------------------------
-- Team access
-- -----------------------------------------------------------------------------
create function public.org_team(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff'], true);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'user_id', m.user_id, 'role', m.role, 'added_at', m.added_at,
             'display_name', p.display_name, 'username', p.username, 'avatar_url', p.avatar_url)
           order by array_position(array['owner', 'manager', 'coach', 'staff'], m.role), p.display_name)
    from app.org_members m join app.profiles p on p.id = m.user_id
    where m.org_id = p_org_id), '[]'::jsonb);
end $$;

-- Adds a person by @username or e-mail, or changes their role.
create function public.org_team_set(p_org_id uuid, p_handle text, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := private.require_org(p_org_id);
  v_target uuid := private.find_user(p_handle);
begin
  if p_role not in ('manager', 'coach', 'staff') then
    perform private.fail(422, 'invalid_role', 'Role must be manager, coach or staff.');
  end if;
  if v_target is null then
    perform private.fail(404, 'user_not_found', 'No account matches that username or e-mail.');
  end if;
  if private.org_role(p_org_id, v_target) = 'owner' then
    perform private.fail(409, 'owner_fixed', 'The owner''s role cannot be changed.');
  end if;
  if p_role = 'manager' and private.org_role(p_org_id, v_uid) <> 'owner' then
    perform private.fail(403, 'forbidden', 'Only the owner can appoint managers.');
  end if;
  insert into app.org_members (org_id, user_id, role) values (p_org_id, v_target, p_role)
  on conflict (org_id, user_id) do update set role = excluded.role;
  perform private.notify(v_target, 'team_added', 'You were added to a team',
    (select name from app.organizations where id = p_org_id) || ' · ' || p_role,
    jsonb_build_object('org_id', p_org_id));
  perform private.audit('org.team_set', 'organization', p_org_id, jsonb_build_object('user_id', v_target, 'role', p_role));
end $$;

create function public.org_team_remove(p_org_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := private.require_org(p_org_id);
  v_role text := private.org_role(p_org_id, p_user_id);
begin
  if v_role = 'owner' then
    perform private.fail(409, 'owner_fixed', 'The owner cannot be removed.');
  end if;
  if v_role = 'manager' and private.org_role(p_org_id, v_uid) <> 'owner' then
    perform private.fail(403, 'forbidden', 'Only the owner can remove managers.');
  end if;
  delete from app.org_members where org_id = p_org_id and user_id = p_user_id;
  perform private.audit('org.team_removed', 'organization', p_org_id, jsonb_build_object('user_id', p_user_id));
end $$;

-- Used by storage policies: may the caller upload media for this organisation?
create function public.can_manage_org(p_org_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(private.org_role(p_org_id, auth.uid()) in ('owner', 'manager'), false);
$$;
