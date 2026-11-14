-- Staff, payroll and the budgeting dashboard.
select t.user('boss@sidi.test');
set role authenticated;
select set_config('test.org', t.org('boss@sidi.test', 'Budget Sports Club')::text, false);
select set_config('test.fac', public.org_facility_save(current_setting('test.org')::uuid,
  '{"name": "Rented hall", "tenure": "rented"}') ->> 'id', false);

-- Salaries are pro-rated by calendar days.
reset role;
select t.eq(private.pay_for_period('monthly', 30000, date '2026-09-01', date '2026-09-30'), 30000::numeric, 'a full month is a full salary');
select t.eq(private.pay_for_period('monthly', 30000, date '2026-09-16', date '2026-09-30'), 15000::numeric, 'half of September');
select t.eq(private.pay_for_period('monthly', 31000, date '2026-10-01', date '2026-11-30'), 62000::numeric, 'two full months');
select t.eq(private.pay_for_period('weekly', 7000, date '2026-09-01', date '2026-09-14'), 14000::numeric, 'two weeks');
set role authenticated;

select public.org_employee_save(current_setting('test.org')::uuid,
  '{"full_name": "Asha Verma", "job_title": "Head coach", "pay_basis": "monthly", "pay_rate": 40000, "joined_on": "2026-01-01"}');
select public.org_employee_save(current_setting('test.org')::uuid,
  '{"full_name": "Bikram Das", "job_title": "Front desk", "employment_type": "part_time", "pay_basis": "hourly", "pay_rate": 200, "joined_on": "2026-01-01"}');
select t.throws(format($$select public.org_employee_save(%L, '{"full_name": "Z", "pay_basis": "daily"}')$$, current_setting('test.org')),
  'invalid_employee');

select set_config('test.run', public.org_payroll_run_create(current_setting('test.org')::uuid, date '2026-10-01', date '2026-10-31') ->> 'id', false);
select t.throws(format($$select public.org_payroll_run_create(%L, date '2026-10-15', date '2026-11-15')$$, current_setting('test.org')),
  'period_overlaps');
select t.eq((public.org_payroll_run(current_setting('test.run')::uuid) ->> 'total')::numeric, 40000::numeric, 'the salaried line is pre-filled');

-- Hours for the hourly employee, a bonus and a deduction.
select public.org_payroll_item_update((i ->> 'id')::uuid, '{"hours": 80, "bonus": 1000, "deductions": 500}')
from jsonb_array_elements(public.org_payroll_run(current_setting('test.run')::uuid) -> 'items') i where i ->> 'pay_basis' = 'hourly';
select t.eq((public.org_payroll_run(current_setting('test.run')::uuid) ->> 'total')::numeric, 56500::numeric, '40000 + 80h x 200 + 1000 - 500');

select t.throws(format($$select public.org_payroll_run_set_status(%L, 'paid')$$, current_setting('test.run')), 'invalid_transition',
  'a run is approved before it is paid');
select public.org_payroll_run_set_status(current_setting('test.run')::uuid, 'approved');
select t.throws(format($$select public.org_payroll_item_update(%L, '{"bonus": 99999}')$$,
  public.org_payroll_run(current_setting('test.run')::uuid) #>> '{items,0,id}'), 'payroll_locked');
select public.org_payroll_run_set_status(current_setting('test.run')::uuid, 'paid');
select t.throws(format('select public.org_payroll_run_delete(%L)', current_setting('test.run')), 'payroll_locked');

-- Recurring rent, one-off costs, income and a budget limit.
select public.org_recurring_save(current_setting('test.org')::uuid, format(
  '{"category": "rent", "amount": 50000, "cadence": "monthly", "starts_on": "%s", "facility_id": "%s"}',
  date_trunc('month', current_date - interval '2 months')::date, current_setting('test.fac'))::jsonb);
select public.org_recurring_save(current_setting('test.org')::uuid, format(
  '{"category": "utilities", "amount": 2000, "cadence": "weekly", "starts_on": "%s"}', current_date - 27)::jsonb);
select public.org_ledger_add(current_setting('test.org')::uuid, format(
  '{"direction": "expense", "category": "equipment", "amount": 12000, "occurred_on": "%s", "note": "Shuttles"}', current_date - 3)::jsonb);
select public.org_ledger_add(current_setting('test.org')::uuid, format(
  '{"direction": "income", "category": "sponsorship", "amount": 75000, "occurred_on": "%s"}', current_date - 10)::jsonb);
select t.throws(format($$select public.org_ledger_add(%L, '{"category": "snacks", "amount": 10}')$$, current_setting('test.org')), 'invalid_entry');
select public.org_budget_limit_set(current_setting('test.org')::uuid, 'equipment', 10000);

select set_config('test.d', public.org_budget_dashboard(current_setting('test.org')::uuid,
  date_trunc('month', current_date - interval '2 months')::date, current_date, 'month')::text, false);
-- rent x3, utilities x4 (days -27, -20, -13, -6), equipment, and the payroll run paid today
select t.eq((current_setting('test.d')::jsonb #>> '{totals,expense}')::numeric, (150000 + 8000 + 12000 + 56500)::numeric, 'total spend');
select t.eq((current_setting('test.d')::jsonb #>> '{totals,income}')::numeric, 75000::numeric, 'total income');
select t.eq((current_setting('test.d')::jsonb #>> '{totals,recurring_expense}')::numeric, 158000::numeric, 'recurring share');
select t.eq(jsonb_array_length(current_setting('test.d')::jsonb -> 'series'), 3, 'three monthly buckets');
select t.eq((select (c ->> 'amount')::numeric from jsonb_array_elements(current_setting('test.d')::jsonb -> 'categories') c
             where c ->> 'category' = 'rent'), 150000::numeric, 'rent by category');
select t.ok((select (c ->> 'monthly_limit')::numeric = 10000 from jsonb_array_elements(current_setting('test.d')::jsonb -> 'categories') c
             where c ->> 'category' = 'equipment'), 'the budget limit rides along with its category');
select t.eq((select (f ->> 'expense')::numeric from jsonb_array_elements(current_setting('test.d')::jsonb -> 'facilities') f),
  150000::numeric, 'rent is attributed to its facility');
select t.ok(jsonb_array_length(public.org_budget_dashboard(current_setting('test.org')::uuid, current_date - 27, current_date, 'week') -> 'series') in (4, 5),
  'weekly buckets');

-- Booked entries are locked; manual ones can be removed.
select t.throws(format('select public.org_ledger_delete(%L)',
  t.q(format($$select id from app.ledger_entries where org_id = %L and source = 'payroll'$$, current_setting('test.org'))) ->> 'id'), 'entry_locked');
select public.org_ledger_delete((t.q(format($$select id from app.ledger_entries where org_id = %L and category = 'equipment'$$,
  current_setting('test.org'))) ->> 'id')::uuid);
reset role;
