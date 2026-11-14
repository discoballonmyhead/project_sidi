-- =============================================================================
-- 0012 · Public API: membership plans, memberships, the performance journey
-- =============================================================================

create function public.org_plans(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff'], true);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(pl) || jsonb_build_object(
             'member_count', (select count(*) from app.memberships m
                              where m.plan_id = pl.id and m.status = 'active'))
           order by pl.is_active desc, pl.price)
    from app.membership_plans pl where pl.org_id = p_org_id), '[]'::jsonb);
end $$;

create function public.org_plan_save(p_org_id uuid, p_plan jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := private.require_org(p_org_id);
  v_id   uuid := (p_plan ->> 'id')::uuid;
  v_tier text := coalesce(p_plan ->> 'tier', 'member');
begin
  perform private.require_feature(p_org_id, 'memberships');
  if v_id is null then
    insert into app.membership_plans (org_id, name, description, tier, sport_code, price, billing_period,
                                      booking_discount_pct, tracks_performance)
    values (p_org_id, private.clean(p_plan ->> 'name'), private.clean(p_plan ->> 'description'), v_tier,
            private.clean(p_plan ->> 'sport_code'), coalesce((p_plan ->> 'price')::numeric, 0),
            coalesce(p_plan ->> 'billing_period', 'monthly'),
            coalesce((p_plan ->> 'booking_discount_pct')::numeric, 0),
            coalesce((p_plan ->> 'tracks_performance')::boolean, v_tier in ('club', 'mentee')))
    returning id into v_id;
  else
    update app.membership_plans
    set name = coalesce(private.clean(p_plan ->> 'name'), name),
        description = case when p_plan ? 'description' then private.clean(p_plan ->> 'description') else description end,
        tier = coalesce(p_plan ->> 'tier', tier),
        sport_code = case when p_plan ? 'sport_code' then private.clean(p_plan ->> 'sport_code') else sport_code end,
        price = coalesce((p_plan ->> 'price')::numeric, price),
        billing_period = coalesce(p_plan ->> 'billing_period', billing_period),
        booking_discount_pct = coalesce((p_plan ->> 'booking_discount_pct')::numeric, booking_discount_pct),
        tracks_performance = coalesce((p_plan ->> 'tracks_performance')::boolean, tracks_performance),
        is_active = coalesce((p_plan ->> 'is_active')::boolean, is_active)
    where id = v_id and org_id = p_org_id;
    if not found then
      perform private.fail(404, 'plan_not_found', 'Plan not found.');
    end if;
  end if;
  return jsonb_build_object('id', v_id);
exception
  when check_violation or not_null_violation or foreign_key_violation or invalid_text_representation then
    perform private.fail(422, 'invalid_plan', 'Check the plan name, tier, price and discount.');
    return null;
end $$;

-- -----------------------------------------------------------------------------
-- Member side
-- -----------------------------------------------------------------------------
create function public.membership_join(p_plan_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := private.uid();
  v_plan app.membership_plans;
  v_id   uuid;
begin
  select pl.* into v_plan
  from app.membership_plans pl join app.organizations o on o.id = pl.org_id
  where pl.id = p_plan_id and pl.is_active and o.status = 'approved';
  if not found then
    perform private.fail(404, 'plan_not_found', 'This plan is not available.');
  end if;
  begin
    insert into app.memberships (org_id, plan_id, user_id, note)
    values (v_plan.org_id, v_plan.id, v_uid, private.clean(p_note))
    returning id into v_id;
  exception when unique_violation then
    perform private.fail(409, 'already_joined', 'You already hold or have requested this plan.');
  end;
  perform private.notify_org(v_plan.org_id, 'membership_requested', 'New membership request',
    (select display_name from app.profiles where id = v_uid) || ' · ' || v_plan.name,
    jsonb_build_object('membership_id', v_id));
  return jsonb_build_object('id', v_id);
end $$;

create function public.membership_cancel(p_membership_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  update app.memberships set status = 'cancelled'
  where id = p_membership_id and user_id = v_uid and status in ('pending', 'active', 'paused');
  if not found then
    perform private.fail(404, 'membership_not_found', 'Membership not found.');
  end if;
  perform private.payment_void_for('membership', p_membership_id);
end $$;

create function public.my_memberships()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(m) || jsonb_build_object(
             'report_count', (select count(*) from app.performance_reports r where r.membership_id = m.id),
             'session_count', (select count(*) from app.training_sessions s where s.membership_id = m.id))
           order by array_position(array['active', 'pending', 'paused'], m.status) nulls last, m.created_at desc)
    from app.v_memberships m where m.user_id = v_uid), '[]'::jsonb);
end $$;

create function public.my_journey(p_membership_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  if not exists (select 1 from app.memberships where id = p_membership_id and user_id = v_uid) then
    perform private.fail(404, 'membership_not_found', 'Membership not found.');
  end if;
  return private.journey(p_membership_id);
end $$;

-- -----------------------------------------------------------------------------
-- Organisation side
-- -----------------------------------------------------------------------------
create function private.require_membership(p_membership_id uuid, p_roles text[] default array['owner', 'manager', 'coach'])
returns app.memberships language plpgsql stable set search_path = '' as $$
declare v_m app.memberships;
begin
  select * into v_m from app.memberships where id = p_membership_id;
  if not found then
    perform private.fail(404, 'membership_not_found', 'Membership not found.');
  end if;
  perform private.require_org(v_m.org_id, p_roles);
  return v_m;
end $$;

create function public.org_memberships(p_org_id uuid, p_status text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff']);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(m) || jsonb_build_object(
             'last_session_on', (select max(s.held_on) from app.training_sessions s where s.membership_id = m.id),
             'payment', (select jsonb_build_object('id', p.id, 'status', p.status, 'amount', p.amount)
                         from app.payments p where p.purpose = 'membership' and p.ref_id = m.id
                         order by p.created_at desc limit 1))
           order by array_position(array['pending', 'active', 'paused'], m.status) nulls last, m.member_name)
    from app.v_memberships m
    where m.org_id = p_org_id and (p_status is null or m.status = p_status)), '[]'::jsonb);
end $$;

create function public.org_membership_decide(p_membership_id uuid, p_approve boolean, p_coach_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_m    app.memberships := private.require_membership(p_membership_id, array['owner', 'manager']);
  v_plan app.membership_plans;
begin
  if v_m.status <> 'pending' then
    perform private.fail(409, 'membership_decided', 'This request has already been decided.');
  end if;
  select * into v_plan from app.membership_plans where id = v_m.plan_id;
  if p_coach_id is not null and private.org_role(v_m.org_id, p_coach_id) is null then
    perform private.fail(422, 'invalid_coach', 'The coach must be on the organisation''s team.');
  end if;

  if p_approve then
    update app.memberships
    set status = 'active', coach_id = p_coach_id, starts_on = current_date,
        ends_on = case v_plan.billing_period
          when 'weekly' then current_date + 7
          when 'monthly' then (current_date + interval '1 month')::date
          when 'quarterly' then (current_date + interval '3 months')::date
          when 'yearly' then (current_date + interval '1 year')::date
        end
    where id = p_membership_id;
    perform private.payment_open(v_m.org_id, v_m.user_id, 'membership', v_m.id, v_plan.price, v_plan.name);
  else
    update app.memberships set status = 'rejected' where id = p_membership_id;
  end if;
  perform private.notify(v_m.user_id, 'membership_decided',
    case when p_approve then 'Membership approved' else 'Membership declined' end,
    v_plan.name, jsonb_build_object('membership_id', v_m.id, 'org_id', v_m.org_id));
end $$;

create function public.org_membership_update(p_membership_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_m app.memberships := private.require_membership(p_membership_id, array['owner', 'manager']);
begin
  if p_patch ? 'status' and p_patch ->> 'status' not in ('active', 'paused', 'expired', 'cancelled') then
    perform private.fail(422, 'invalid_status', 'Unknown membership status.');
  end if;
  if p_patch ->> 'coach_id' is not null and private.org_role(v_m.org_id, (p_patch ->> 'coach_id')::uuid) is null then
    perform private.fail(422, 'invalid_coach', 'The coach must be on the organisation''s team.');
  end if;
  update app.memberships
  set status = coalesce(p_patch ->> 'status', status),
      coach_id = case when p_patch ? 'coach_id' then (p_patch ->> 'coach_id')::uuid else coach_id end,
      ends_on = case when p_patch ? 'ends_on' then (p_patch ->> 'ends_on')::date else ends_on end
  where id = p_membership_id;
exception when unique_violation then
  perform private.fail(409, 'already_joined', 'This member already has a live membership on this plan.');
end $$;

create function public.org_member_journey(p_membership_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_m app.memberships := private.require_membership(p_membership_id);
begin
  return private.journey(p_membership_id) || jsonb_build_object(
    'available_metrics', coalesce((
      select jsonb_agg(to_jsonb(d) order by d.sort_order, d.name)
      from app.metric_definitions d
      join app.membership_plans pl on pl.id = v_m.plan_id
      where (d.org_id is null or d.org_id = v_m.org_id)
        and (pl.sport_code is null or d.sport_code = pl.sport_code)), '[]'::jsonb));
end $$;

create function public.org_metric_save(p_org_id uuid, p_metric jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach']);
  v_id  uuid;
begin
  insert into app.metric_definitions (org_id, sport_code, key, name, unit, higher_is_better, sort_order)
  values (p_org_id, p_metric ->> 'sport_code',
          private.slugify(replace(coalesce(p_metric ->> 'name', ''), ' ', '_')),
          private.clean(p_metric ->> 'name'), coalesce(private.clean(p_metric ->> 'unit'), ''),
          coalesce((p_metric ->> 'higher_is_better')::boolean, true), 100)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then
    perform private.fail(409, 'metric_exists', 'A metric with that name already exists.');
    return null;
  when check_violation or not_null_violation or foreign_key_violation then
    perform private.fail(422, 'invalid_metric', 'Give the metric a short name and a sport.');
    return null;
end $$;

create function public.org_session_log(p_membership_id uuid, p_session jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_m  app.memberships := private.require_membership(p_membership_id);
  v_id uuid;
begin
  perform private.require_feature(v_m.org_id, 'coaching');
  insert into app.training_sessions (org_id, membership_id, coach_id, held_on, minutes, attendance, focus, notes)
  values (v_m.org_id, v_m.id, auth.uid(),
          coalesce((p_session ->> 'held_on')::date, current_date),
          coalesce((p_session ->> 'minutes')::int, 60),
          coalesce(p_session ->> 'attendance', 'present'),
          private.clean(p_session ->> 'focus'), private.clean(p_session ->> 'notes'))
  returning id into v_id;
  return jsonb_build_object('id', v_id);
exception when check_violation or invalid_text_representation or invalid_datetime_format then
  perform private.fail(422, 'invalid_session', 'Check the session date, length and attendance.');
  return null;
end $$;

-- Records one or more measurements: [{"metric_id": "...", "value": 212, "note": "..."}]
create function public.org_performance_record(p_membership_id uuid, p_entries jsonb, p_recorded_on date default null)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_m     app.memberships := private.require_membership(p_membership_id);
  v_count int;
begin
  perform private.require_feature(v_m.org_id, 'coaching');
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    perform private.fail(422, 'invalid_entries', 'Add at least one measurement.');
  end if;
  insert into app.performance_entries (membership_id, metric_id, value, recorded_on, note, recorded_by)
  select v_m.id, d.id, (e ->> 'value')::numeric, coalesce(p_recorded_on, current_date),
         private.clean(e ->> 'note'), auth.uid()
  from jsonb_array_elements(p_entries) e
  join app.metric_definitions d
    on d.id = (e ->> 'metric_id')::uuid and (d.org_id is null or d.org_id = v_m.org_id)
  where e ->> 'value' is not null;
  get diagnostics v_count = row_count;
  return v_count;
exception when invalid_text_representation or numeric_value_out_of_range then
  perform private.fail(422, 'invalid_entries', 'Measurements must be numbers.');
  return 0;
end $$;

create function public.org_report_publish(p_membership_id uuid, p_report jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_m  app.memberships := private.require_membership(p_membership_id);
  v_id uuid;
begin
  perform private.require_feature(v_m.org_id, 'coaching');
  insert into app.performance_reports (membership_id, coach_id, period_start, period_end, rating,
                                       summary, strengths, focus_areas)
  values (v_m.id, auth.uid(),
          coalesce((p_report ->> 'period_start')::date, (current_date - interval '1 month')::date),
          coalesce((p_report ->> 'period_end')::date, current_date),
          (p_report ->> 'rating')::smallint, private.clean(p_report ->> 'summary'),
          private.clean(p_report ->> 'strengths'), private.clean(p_report ->> 'focus_areas'))
  returning id into v_id;
  perform private.notify(v_m.user_id, 'report_published', 'New progress report',
    (select name from app.organizations where id = v_m.org_id),
    jsonb_build_object('membership_id', v_m.id, 'report_id', v_id));
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format then
  perform private.fail(422, 'invalid_report', 'Write a summary and check the period and rating (1-10).');
  return null;
end $$;
