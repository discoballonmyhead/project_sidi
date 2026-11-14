-- =============================================================================
-- 0015 · Public API: the admin console (moderation, approvals, feature access)
-- Every function here starts with private.require_staff().
-- =============================================================================

create function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  return jsonb_build_object(
    'role', private.platform_role(v_uid),
    'pending', (
      select jsonb_build_object(
        'org_approval', count(*) filter (where kind = 'org_approval'),
        'org_verification', count(*) filter (where kind = 'org_verification'),
        'feature_access', count(*) filter (where kind = 'feature_access'))
      from app.requests where status = 'pending'),
    'open_reports', (select count(*) from app.reports where status = 'open'),
    'organizations', (
      select jsonb_build_object(
        'total', count(*),
        'approved', count(*) filter (where status = 'approved'),
        'pending', count(*) filter (where status = 'pending'),
        'suspended', count(*) filter (where status = 'suspended'),
        'verified', count(*) filter (where is_verified))
      from app.organizations),
    'users', (select count(*) from app.profiles),
    'tournaments_live', (select count(*) from app.tournaments where status in ('open', 'closed', 'live')),
    'bookings_7d', (select count(*) from app.bookings where created_at > now() - interval '7 days'));
end $$;

create function public.admin_requests(
  p_status text default 'pending', p_kind text default null, p_limit int default 50, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(r) order by r.created_at)
    from (select * from app.v_requests
          where (p_status is null or status = p_status) and (p_kind is null or kind = p_kind)
          order by case when p_status = 'pending' then created_at end,
                   case when p_status is distinct from 'pending' then created_at end desc
          limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0)) r), '[]'::jsonb);
end $$;

create function public.admin_request_decide(p_request_id uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  if not p_approve and private.clean(p_note) is null then
    perform private.fail(422, 'note_required', 'Tell the organisation why the request was rejected.');
  end if;
  perform private.decide_request(p_request_id, p_approve, p_note, v_uid);
end $$;

create function public.admin_orgs(p_query text default null, p_status text default null, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select o.id, o.name, o.status, o.is_verified, o.city, o.sports, o.created_at,
             o.contact_email, o.contact_phone, p.display_name as owner_name,
             coalesce((select jsonb_agg(f.feature_key) from app.org_features f where f.org_id = o.id), '[]'::jsonb) as features,
             (select count(*)::int from app.reports r
              where r.target_type = 'organization' and r.target_id = o.id and r.status = 'open') as open_reports
      from app.organizations o join app.profiles p on p.id = o.owner_id
      where (p_status is null or o.status = p_status)
        and (private.clean(p_query) is null or o.name ilike '%' || private.clean(p_query) || '%')
      order by o.created_at desc
      limit least(greatest(p_limit, 1), 200)) q), '[]'::jsonb);
end $$;

-- Suspend, reinstate or (un)verify an organisation outside the request queue.
create function public.admin_org_moderate(p_org_id uuid, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_staff();
  v_org app.organizations;
begin
  select * into v_org from app.organizations where id = p_org_id;
  if not found then
    perform private.fail(404, 'org_not_found', 'Organisation not found.');
  end if;
  if p_action in ('suspend', 'unverify') and private.clean(p_note) is null then
    perform private.fail(422, 'note_required', 'Add a note explaining this action.');
  end if;
  case p_action
    when 'suspend' then
      perform private.set_org_status(p_org_id, 'suspended', v_uid);
    when 'reinstate' then
      perform private.set_org_status(p_org_id, 'approved', v_uid);
      update app.requests set status = 'approved', decided_by = v_uid, decided_at = now()
      where org_id = p_org_id and kind = 'org_approval' and status = 'pending';
    when 'verify' then
      update app.organizations set is_verified = true, verified_at = now() where id = p_org_id;
    when 'unverify' then
      update app.organizations set is_verified = false, verified_at = null where id = p_org_id;
    else
      perform private.fail(422, 'invalid_action', 'Unknown moderation action.');
  end case;
  perform private.audit('org.' || p_action, 'organization', p_org_id, jsonb_build_object('note', private.clean(p_note)));
  perform private.notify_org(p_org_id, 'org_moderated', 'Organisation ' || p_action,
    coalesce(private.clean(p_note), v_org.name));
end $$;

-- Switch a feature on or off directly. Admins only.
create function public.admin_org_set_feature(p_org_id uuid, p_feature_key text, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff(true);
begin
  if not exists (select 1 from app.features where key = p_feature_key)
     or not exists (select 1 from app.organizations where id = p_org_id) then
    perform private.fail(404, 'feature_not_found', 'Unknown feature or organisation.');
  end if;
  if p_enabled then
    perform private.grant_feature(p_org_id, p_feature_key, v_uid);
  else
    delete from app.org_features where org_id = p_org_id and feature_key = p_feature_key;
  end if;
  perform private.audit(case when p_enabled then 'feature.granted' else 'feature.revoked' end,
    'organization', p_org_id, jsonb_build_object('feature', p_feature_key));
end $$;

create function public.admin_reports(p_status text default 'open', p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select r.id, r.target_type, r.target_id, r.reason, r.status, r.resolution, r.created_at, r.resolved_at,
             p.display_name as reporter_name,
             case r.target_type
               when 'organization' then (select name from app.organizations where id = r.target_id)
               when 'tournament' then (select name from app.tournaments where id = r.target_id)
               else (select display_name from app.profiles where id = r.target_id)
             end as target_name
      from app.reports r join app.profiles p on p.id = r.reporter_id
      where p_status is null or r.status = p_status
      order by r.created_at desc
      limit least(greatest(p_limit, 1), 500)) q), '[]'::jsonb);
end $$;

create function public.admin_report_resolve(p_report_id uuid, p_status text, p_resolution text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  if p_status not in ('actioned', 'dismissed') then
    perform private.fail(422, 'invalid_status', 'Resolve a report as actioned or dismissed.');
  end if;
  update app.reports
  set status = p_status, resolution = private.clean(p_resolution), resolved_by = v_uid, resolved_at = now()
  where id = p_report_id and status = 'open';
  if not found then
    perform private.fail(404, 'report_not_found', 'No open report with that id.');
  end if;
  perform private.audit('report.' || p_status, 'report', p_report_id);
end $$;

-- Take a tournament down (for example after a report).
create function public.admin_tournament_cancel(p_tournament_id uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_staff();
  v_org uuid;
begin
  if private.clean(p_note) is null then
    perform private.fail(422, 'note_required', 'Add a note explaining this action.');
  end if;
  update app.tournaments set status = 'cancelled'
  where id = p_tournament_id and status not in ('completed', 'cancelled')
  returning org_id into v_org;
  if v_org is null then
    perform private.fail(404, 'tournament_not_found', 'No active tournament with that id.');
  end if;
  perform private.audit('tournament.cancelled_by_staff', 'tournament', p_tournament_id,
    jsonb_build_object('note', private.clean(p_note)));
  perform private.notify_org(v_org, 'tournament_cancelled', 'Tournament cancelled by the platform', private.clean(p_note));
end $$;

create function public.admin_users(p_query text default null, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select p.id, p.display_name, p.username, p.city, p.created_at, u.email,
             r.role as platform_role,
             (select count(*)::int from app.org_members m where m.user_id = p.id) as org_count
      from app.profiles p
      join auth.users u on u.id = p.id
      left join app.platform_roles r on r.user_id = p.id
      where private.clean(p_query) is null
         or p.display_name ilike '%' || private.clean(p_query) || '%'
         or p.username ilike '%' || private.clean(p_query) || '%'
         or u.email ilike '%' || private.clean(p_query) || '%'
      order by p.created_at desc
      limit least(greatest(p_limit, 1), 200)) q), '[]'::jsonb);
end $$;

-- Grant or remove a platform role. Admins only, and never on yourself, so the
-- last admin cannot lock the platform out.
create function public.admin_set_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff(true);
begin
  if p_user_id = v_uid then
    perform private.fail(409, 'own_role', 'You cannot change your own role.');
  end if;
  if p_role is null then
    delete from app.platform_roles where user_id = p_user_id;
  elsif p_role in ('admin', 'moderator') then
    insert into app.platform_roles (user_id, role, granted_by) values (p_user_id, p_role, v_uid)
    on conflict (user_id) do update set role = excluded.role, granted_by = excluded.granted_by, granted_at = now();
  else
    perform private.fail(422, 'invalid_role', 'Role must be admin or moderator.');
  end if;
  perform private.audit('role.set', 'user', p_user_id, jsonb_build_object('role', p_role));
exception when foreign_key_violation then
  perform private.fail(404, 'user_not_found', 'User not found.');
end $$;

create function public.admin_audit(p_limit int default 100, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_staff();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select a.id, a.action, a.entity, a.entity_id, a.data, a.created_at, p.display_name as actor_name
      from app.audit_log a left join app.profiles p on p.id = a.actor_id
      order by a.created_at desc
      limit least(greatest(p_limit, 1), 500) offset greatest(p_offset, 0)) q), '[]'::jsonb);
end $$;
