-- =============================================================================
-- 0013 · Public API: staff, payroll, ledger and the budgeting dashboard
-- Finance is restricted to owners and managers.
-- =============================================================================

create function public.org_employees(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(e) || jsonb_build_object(
             'facility_name', f.name,
             'linked_name', p.display_name,
             'paid_total', (select coalesce(sum(i.net_amount), 0)
                            from app.payroll_items i join app.payroll_runs r on r.id = i.run_id
                            where i.employee_id = e.id and r.status = 'paid'))
           order by e.is_active desc, e.full_name)
    from app.employees e
    left join app.facilities f on f.id = e.facility_id
    left join app.profiles p on p.id = e.user_id
    where e.org_id = p_org_id), '[]'::jsonb);
end $$;

create function public.org_employee_save(p_org_id uuid, p_employee jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := private.require_org(p_org_id);
  v_id   uuid := (p_employee ->> 'id')::uuid;
  v_user uuid := private.find_user(p_employee ->> 'handle');
begin
  perform private.require_feature(p_org_id, 'payroll');
  if p_employee ->> 'facility_id' is not null and not exists (
       select 1 from app.facilities where id = (p_employee ->> 'facility_id')::uuid and org_id = p_org_id) then
    perform private.fail(404, 'facility_not_found', 'Facility not found.');
  end if;
  if v_id is null then
    insert into app.employees (org_id, user_id, full_name, job_title, employment_type, pay_basis, pay_rate,
                               facility_id, joined_on)
    values (p_org_id, v_user, private.clean(p_employee ->> 'full_name'),
            coalesce(private.clean(p_employee ->> 'job_title'), 'Staff'),
            coalesce(p_employee ->> 'employment_type', 'full_time'),
            coalesce(p_employee ->> 'pay_basis', 'monthly'),
            coalesce((p_employee ->> 'pay_rate')::numeric, 0),
            (p_employee ->> 'facility_id')::uuid,
            coalesce((p_employee ->> 'joined_on')::date, current_date))
    returning id into v_id;
  else
    update app.employees
    set full_name = coalesce(private.clean(p_employee ->> 'full_name'), full_name),
        job_title = coalesce(private.clean(p_employee ->> 'job_title'), job_title),
        employment_type = coalesce(p_employee ->> 'employment_type', employment_type),
        pay_basis = coalesce(p_employee ->> 'pay_basis', pay_basis),
        pay_rate = coalesce((p_employee ->> 'pay_rate')::numeric, pay_rate),
        facility_id = case when p_employee ? 'facility_id' then (p_employee ->> 'facility_id')::uuid else facility_id end,
        user_id = case when p_employee ? 'handle' then v_user else user_id end,
        is_active = coalesce((p_employee ->> 'is_active')::boolean, is_active)
    where id = v_id and org_id = p_org_id;
    if not found then
      perform private.fail(404, 'employee_not_found', 'Employee not found.');
    end if;
  end if;
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format then
  perform private.fail(422, 'invalid_employee', 'Check the name, employment type, pay basis and rate.');
  return null;
end $$;

-- -----------------------------------------------------------------------------
-- Payroll runs: draft -> approved -> paid (which books the expense)
-- -----------------------------------------------------------------------------
create function private.require_payroll_run(p_run_id uuid)
returns app.payroll_runs language plpgsql stable set search_path = '' as $$
declare v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found then
    perform private.fail(404, 'payroll_run_not_found', 'Payroll run not found.');
  end if;
  perform private.require_org(v_run.org_id);
  return v_run;
end $$;

create function public.org_payroll_runs(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(r) order by r.period_end desc, r.created_at desc)
    from app.v_payroll_runs r where r.org_id = p_org_id), '[]'::jsonb);
end $$;

create function public.org_payroll_run(p_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_run app.payroll_runs := private.require_payroll_run(p_run_id);
begin
  return (select to_jsonb(r) from app.v_payroll_runs r where r.id = p_run_id) || jsonb_build_object(
    'currency', (select currency from app.organizations where id = v_run.org_id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', i.id, 'employee_id', e.id, 'full_name', e.full_name, 'job_title', e.job_title,
               'pay_basis', e.pay_basis, 'pay_rate', e.pay_rate, 'hours', i.hours,
               'base_amount', i.base_amount, 'bonus', i.bonus, 'deductions', i.deductions,
               'net_amount', i.net_amount, 'note', i.note)
             order by e.full_name)
      from app.payroll_items i join app.employees e on e.id = i.employee_id
      where i.run_id = p_run_id), '[]'::jsonb));
end $$;

-- Opens a draft run with one line per active employee, pre-filled from their
-- salary. Hourly staff start at zero until their hours are entered.
create function public.org_payroll_run_create(p_org_id uuid, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id);
  v_id  uuid;
begin
  perform private.require_feature(p_org_id, 'payroll');
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    perform private.fail(422, 'invalid_period', 'Pick a pay period of up to a year.');
  end if;
  if exists (select 1 from app.payroll_runs
             where org_id = p_org_id and daterange(period_start, period_end, '[]') && daterange(p_from, p_to, '[]')) then
    perform private.fail(409, 'period_overlaps', 'A payroll run already covers part of this period.');
  end if;
  insert into app.payroll_runs (org_id, period_start, period_end, created_by)
  values (p_org_id, p_from, p_to, v_uid) returning id into v_id;
  insert into app.payroll_items (run_id, employee_id, base_amount)
  select v_id, e.id,
         private.pay_for_period(e.pay_basis, e.pay_rate, greatest(p_from, e.joined_on), p_to)
  from app.employees e
  where e.org_id = p_org_id and e.is_active and e.joined_on <= p_to;
  return jsonb_build_object('id', v_id);
end $$;

create function public.org_payroll_item_update(p_item_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_run app.payroll_runs;
begin
  v_run := private.require_payroll_run((select run_id from app.payroll_items where id = p_item_id));
  if v_run.status <> 'draft' then
    perform private.fail(409, 'payroll_locked', 'Only a draft run can be edited.');
  end if;
  update app.payroll_items i
  set hours = coalesce((p_patch ->> 'hours')::numeric, i.hours),
      base_amount = case
        when p_patch ? 'base_amount' then (p_patch ->> 'base_amount')::numeric
        when p_patch ? 'hours' and e.pay_basis = 'hourly' then round((p_patch ->> 'hours')::numeric * e.pay_rate, 2)
        else i.base_amount end,
      bonus = coalesce((p_patch ->> 'bonus')::numeric, i.bonus),
      deductions = coalesce((p_patch ->> 'deductions')::numeric, i.deductions),
      note = case when p_patch ? 'note' then private.clean(p_patch ->> 'note') else i.note end
  from app.employees e
  where i.id = p_item_id and e.id = i.employee_id;
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then
  perform private.fail(422, 'invalid_amount', 'Amounts and hours must be zero or more.');
end $$;

create function public.org_payroll_run_set_status(p_run_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_run   app.payroll_runs := private.require_payroll_run(p_run_id);
  v_total numeric;
begin
  if (v_run.status, p_status) not in (('draft', 'approved'), ('approved', 'draft'), ('approved', 'paid')) then
    perform private.fail(409, 'invalid_transition',
      format('A %s run cannot be moved to %s.', v_run.status, p_status));
  end if;
  select coalesce(sum(net_amount), 0) into v_total from app.payroll_items where run_id = p_run_id;
  if p_status = 'paid' then
    if v_total > 0 then
      insert into app.ledger_entries (org_id, direction, category, amount, occurred_on, note, source, source_id, created_by)
      values (v_run.org_id, 'expense', 'payroll', v_total, current_date,
              format('Payroll %s to %s', to_char(v_run.period_start, 'DD Mon'), to_char(v_run.period_end, 'DD Mon YYYY')),
              'payroll', v_run.id, auth.uid());
    end if;
    perform private.audit('payroll.paid', 'payroll_run', p_run_id, jsonb_build_object('total', v_total));
  end if;
  update app.payroll_runs
  set status = p_status,
      approved_at = case p_status when 'approved' then now() when 'draft' then null else approved_at end,
      paid_at = case when p_status = 'paid' then now() end
  where id = p_run_id;
end $$;

create function public.org_payroll_run_delete(p_run_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_run app.payroll_runs := private.require_payroll_run(p_run_id);
begin
  if v_run.status <> 'draft' then
    perform private.fail(409, 'payroll_locked', 'Only a draft run can be deleted.');
  end if;
  delete from app.payroll_runs where id = p_run_id;
end $$;

-- -----------------------------------------------------------------------------
-- Ledger, recurring costs, budget limits
-- -----------------------------------------------------------------------------
create function public.org_ledger_add(p_org_id uuid, p_entry jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id);
  v_id  uuid;
begin
  perform private.require_feature(p_org_id, 'budgeting');
  if p_entry ->> 'facility_id' is not null and not exists (
       select 1 from app.facilities where id = (p_entry ->> 'facility_id')::uuid and org_id = p_org_id) then
    perform private.fail(404, 'facility_not_found', 'Facility not found.');
  end if;
  insert into app.ledger_entries (org_id, facility_id, direction, category, amount, occurred_on, note, created_by)
  values (p_org_id, (p_entry ->> 'facility_id')::uuid, coalesce(p_entry ->> 'direction', 'expense'),
          p_entry ->> 'category', (p_entry ->> 'amount')::numeric,
          coalesce((p_entry ->> 'occurred_on')::date, current_date), private.clean(p_entry ->> 'note'), v_uid)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format then
  perform private.fail(422, 'invalid_entry', 'Pick a category and enter an amount above zero.');
  return null;
end $$;

create function public.org_ledger_delete(p_entry_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_entry app.ledger_entries;
begin
  select * into v_entry from app.ledger_entries where id = p_entry_id;
  if not found then
    perform private.fail(404, 'entry_not_found', 'Entry not found.');
  end if;
  perform private.require_org(v_entry.org_id);
  if v_entry.source <> 'manual' then
    perform private.fail(409, 'entry_locked',
      'This entry was booked by a payment or payroll run. Undo it there instead.');
  end if;
  delete from app.ledger_entries where id = p_entry_id;
end $$;

create function public.org_recurring_save(p_org_id uuid, p_cost jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id);
  v_id  uuid := (p_cost ->> 'id')::uuid;
begin
  perform private.require_feature(p_org_id, 'budgeting');
  if p_cost ->> 'facility_id' is not null and not exists (
       select 1 from app.facilities where id = (p_cost ->> 'facility_id')::uuid and org_id = p_org_id) then
    perform private.fail(404, 'facility_not_found', 'Facility not found.');
  end if;
  if v_id is null then
    insert into app.recurring_costs (org_id, facility_id, category, amount, cadence, starts_on, ends_on, note)
    values (p_org_id, (p_cost ->> 'facility_id')::uuid, p_cost ->> 'category', (p_cost ->> 'amount')::numeric,
            coalesce(p_cost ->> 'cadence', 'monthly'), coalesce((p_cost ->> 'starts_on')::date, current_date),
            (p_cost ->> 'ends_on')::date, private.clean(p_cost ->> 'note'))
    returning id into v_id;
  else
    update app.recurring_costs
    set category = coalesce(p_cost ->> 'category', category),
        amount = coalesce((p_cost ->> 'amount')::numeric, amount),
        cadence = coalesce(p_cost ->> 'cadence', cadence),
        starts_on = coalesce((p_cost ->> 'starts_on')::date, starts_on),
        ends_on = case when p_cost ? 'ends_on' then (p_cost ->> 'ends_on')::date else ends_on end,
        facility_id = case when p_cost ? 'facility_id' then (p_cost ->> 'facility_id')::uuid else facility_id end,
        note = case when p_cost ? 'note' then private.clean(p_cost ->> 'note') else note end,
        is_active = coalesce((p_cost ->> 'is_active')::boolean, is_active)
    where id = v_id and org_id = p_org_id;
    if not found then
      perform private.fail(404, 'cost_not_found', 'Recurring cost not found.');
    end if;
  end if;
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format then
  perform private.fail(422, 'invalid_cost', 'Pick a category, cadence and an amount above zero.');
  return null;
end $$;

create function public.org_recurring_delete(p_cost_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_org((select org_id from app.recurring_costs where id = p_cost_id));
  delete from app.recurring_costs where id = p_cost_id;
end $$;

-- A null or zero limit removes the budget for that category.
create function public.org_budget_limit_set(p_org_id uuid, p_category text, p_monthly_limit numeric)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id);
begin
  perform private.require_feature(p_org_id, 'budgeting');
  if coalesce(p_monthly_limit, 0) <= 0 then
    delete from app.budget_limits where org_id = p_org_id and category = p_category;
  else
    insert into app.budget_limits (org_id, category, monthly_limit)
    values (p_org_id, p_category, p_monthly_limit)
    on conflict (org_id, category) do update set monthly_limit = excluded.monthly_limit;
  end if;
end $$;

-- Income, spend and budget usage for a window, bucketed by week or month.
create function public.org_budget_dashboard(p_org_id uuid, p_from date, p_to date, p_bucket text default 'month')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id);
begin
  if p_bucket not in ('week', 'month') then
    perform private.fail(422, 'invalid_bucket', 'Bucket must be week or month.');
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 * 3 then
    perform private.fail(422, 'invalid_period', 'Pick a period of up to three years.');
  end if;
  return private.budget_dashboard(p_org_id, p_from, p_to, p_bucket);
end $$;
