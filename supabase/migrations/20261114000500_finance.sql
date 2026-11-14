-- =============================================================================
-- 0005 · Payments, staff & payroll, ledger and budgeting
-- =============================================================================

-- Money owed to an organisation by a customer. No card data is handled here:
-- the organisation records how each payment was settled (cash, UPI, bank...);
-- a payment gateway can later flip `status` through the same private function.
create table app.payments (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references app.organizations (id) on delete cascade,
  payer_id    uuid references app.profiles (id) on delete set null,
  purpose     text not null check (purpose in ('booking', 'membership', 'tournament_entry', 'other')),
  ref_id      uuid,
  description text,
  amount      numeric(10, 2) not null check (amount > 0),
  currency    text not null,
  status      text not null default 'pending'
              check (status in ('pending', 'paid', 'refunded', 'waived', 'void')),
  method      text check (method in ('cash', 'upi', 'card', 'bank_transfer', 'online', 'other')),
  note        text,
  recorded_by uuid references app.profiles (id) on delete set null,
  paid_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index payments_org_idx on app.payments (org_id, status, created_at desc);
create index payments_ref_idx on app.payments (purpose, ref_id);
create index payments_payer_idx on app.payments (payer_id);

create table app.employees (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references app.organizations (id) on delete cascade,
  user_id         uuid references app.profiles (id) on delete set null,
  full_name       text not null check (char_length(full_name) between 2 and 80),
  job_title       text not null default 'Staff',
  employment_type text not null default 'full_time'
                  check (employment_type in ('full_time', 'part_time', 'contract')),
  pay_basis       text not null default 'monthly' check (pay_basis in ('hourly', 'weekly', 'monthly')),
  pay_rate        numeric(10, 2) not null default 0 check (pay_rate >= 0),
  facility_id     uuid references app.facilities (id) on delete set null,
  joined_on       date not null default current_date,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);
create index employees_org_idx on app.employees (org_id);

create table app.payroll_runs (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references app.organizations (id) on delete cascade,
  period_start date not null,
  period_end   date not null,
  status       text not null default 'draft' check (status in ('draft', 'approved', 'paid')),
  created_by   uuid references app.profiles (id) on delete set null,
  approved_at  timestamptz,
  paid_at      timestamptz,
  created_at   timestamptz not null default now(),
  check (period_start <= period_end)
);
create index payroll_runs_org_idx on app.payroll_runs (org_id, period_end desc);

create table app.payroll_items (
  id          uuid primary key default gen_random_uuid(),
  run_id      uuid not null references app.payroll_runs (id) on delete cascade,
  employee_id uuid not null references app.employees (id) on delete restrict,
  hours       numeric(7, 2) not null default 0 check (hours >= 0),
  base_amount numeric(10, 2) not null default 0 check (base_amount >= 0),
  bonus       numeric(10, 2) not null default 0 check (bonus >= 0),
  deductions  numeric(10, 2) not null default 0 check (deductions >= 0),
  net_amount  numeric(10, 2) generated always as (greatest(base_amount + bonus - deductions, 0)) stored,
  note        text,
  unique (run_id, employee_id)
);

create table app.ledger_entries (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references app.organizations (id) on delete cascade,
  facility_id uuid references app.facilities (id) on delete set null,
  direction   text not null check (direction in ('income', 'expense')),
  category    text not null check (category in (
                'bookings', 'memberships', 'tournaments', 'sponsorship', 'other_income',
                'rent', 'mortgage', 'utilities', 'maintenance', 'equipment', 'payroll',
                'marketing', 'tournament_costs', 'insurance', 'taxes', 'other')),
  amount      numeric(12, 2) not null check (amount > 0),
  occurred_on date not null default current_date,
  note        text,
  source      text not null default 'manual' check (source in ('manual', 'payment', 'payroll')),
  source_id   uuid,
  created_by  uuid references app.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index ledger_entries_org_idx on app.ledger_entries (org_id, occurred_on);
create unique index ledger_entries_source_idx on app.ledger_entries (source, source_id) where source <> 'manual';

-- Costs that repeat (rent on a rented hall, loan on an owned one, utilities).
-- They are expanded into dated occurrences when a budget window is read, so
-- nothing has to run on a schedule.
create table app.recurring_costs (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references app.organizations (id) on delete cascade,
  facility_id uuid references app.facilities (id) on delete cascade,
  category    text not null,
  amount      numeric(12, 2) not null check (amount > 0),
  cadence     text not null default 'monthly' check (cadence in ('weekly', 'monthly', 'quarterly', 'yearly')),
  starts_on   date not null default current_date,
  ends_on     date,
  note        text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  check (category in ('rent', 'mortgage', 'utilities', 'maintenance', 'equipment',
                      'marketing', 'insurance', 'taxes', 'other'))
);
create index recurring_costs_org_idx on app.recurring_costs (org_id);

create table app.budget_limits (
  org_id        uuid not null references app.organizations (id) on delete cascade,
  category      text not null,
  monthly_limit numeric(12, 2) not null check (monthly_limit > 0),
  primary key (org_id, category)
);

-- -----------------------------------------------------------------------------
-- Payments
-- -----------------------------------------------------------------------------
create function private.payment_open(
  p_org_id uuid, p_payer_id uuid, p_purpose text, p_ref_id uuid, p_amount numeric, p_description text)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  if coalesce(p_amount, 0) <= 0 then
    return null;
  end if;
  insert into app.payments (org_id, payer_id, purpose, ref_id, amount, currency, description)
  select p_org_id, p_payer_id, p_purpose, p_ref_id, p_amount, o.currency, p_description
  from app.organizations o where o.id = p_org_id
  returning id into v_id;
  return v_id;
end $$;

-- The single place a payment changes state. Paid payments show up as income
-- in the ledger; undoing a payment removes that income again.
create function private.payment_settle(p_payment_id uuid, p_status text, p_method text, p_note text, p_by uuid)
returns app.payments language plpgsql set search_path = '' as $$
declare
  v_pay      app.payments;
  v_facility uuid;
begin
  select * into v_pay from app.payments where id = p_payment_id for update;
  if not found then
    perform private.fail(404, 'payment_not_found', 'Payment not found.');
  end if;
  if p_status not in ('pending', 'paid', 'refunded', 'waived', 'void') then
    perform private.fail(422, 'invalid_status', 'Unknown payment status.');
  end if;
  if p_status = 'refunded' and v_pay.status <> 'paid' then
    perform private.fail(409, 'payment_not_paid', 'Only a paid payment can be refunded.');
  end if;

  update app.payments
  set status = p_status,
      method = case when p_status = 'paid' then coalesce(p_method, method, 'cash') else method end,
      note = coalesce(private.clean(p_note), note),
      recorded_by = p_by,
      paid_at = case when p_status = 'paid' then now() when p_status = 'pending' then null else paid_at end
  where id = p_payment_id
  returning * into v_pay;

  delete from app.ledger_entries where source = 'payment' and source_id = v_pay.id;
  if v_pay.status = 'paid' then
    if v_pay.purpose = 'booking' then
      select r.facility_id into v_facility
      from app.bookings b join app.resources r on r.id = b.resource_id
      where b.id = v_pay.ref_id;
    end if;
    insert into app.ledger_entries (org_id, facility_id, direction, category, amount, occurred_on, note, source, source_id, created_by)
    values (v_pay.org_id, v_facility, 'income',
            case v_pay.purpose
              when 'booking' then 'bookings'
              when 'membership' then 'memberships'
              when 'tournament_entry' then 'tournaments'
              else 'other_income'
            end,
            v_pay.amount, current_date, v_pay.description, 'payment', v_pay.id, p_by);
  end if;
  return v_pay;
end $$;

-- Closes whatever is still open for a cancelled booking / entry / membership.
create function private.payment_void_for(p_purpose text, p_ref_id uuid)
returns void language sql set search_path = '' as $$
  update app.payments set status = 'void'
  where purpose = p_purpose and ref_id = p_ref_id and status = 'pending';
$$;

create view app.v_payments as
select pay.id, pay.org_id, pay.payer_id, pay.purpose, pay.ref_id, pay.description,
       pay.amount, pay.currency, pay.status, pay.method, pay.note, pay.paid_at, pay.created_at,
       p.display_name as payer_name
from app.payments pay
left join app.profiles p on p.id = pay.payer_id;

-- -----------------------------------------------------------------------------
-- Payroll
-- -----------------------------------------------------------------------------
-- Salary owed for [p_from, p_to]: monthly salaries are pro-rated by the share
-- of each calendar month that falls inside the period, weekly ones by days / 7.
-- Hourly staff start at 0 and are paid from the hours entered on the run.
create function private.pay_for_period(p_basis text, p_rate numeric, p_from date, p_to date)
returns numeric language sql immutable set search_path = '' as $$
  select round(case p_basis
    when 'monthly' then p_rate * (
      select coalesce(sum(
        (least(p_to, (m + interval '1 month - 1 day')::date) - greatest(p_from, m::date) + 1)::numeric
        / extract(day from m + interval '1 month - 1 day')::numeric), 0)
      from generate_series(date_trunc('month', p_from::timestamp), p_to::timestamp, interval '1 month') m)
    when 'weekly' then p_rate * (p_to - p_from + 1) / 7.0
    else 0
  end, 2);
$$;

create view app.v_payroll_runs as
select r.id, r.org_id, r.period_start, r.period_end, r.status, r.approved_at, r.paid_at, r.created_at,
       coalesce(sum(i.net_amount), 0) as total,
       count(i.id)::int as headcount
from app.payroll_runs r
left join app.payroll_items i on i.run_id = r.id
group by r.id;

-- -----------------------------------------------------------------------------
-- Budgeting
-- -----------------------------------------------------------------------------
-- Every money movement inside a window: booked ledger entries plus the
-- occurrences of recurring costs that fall in it.
create function private.ledger_window(p_org_id uuid, p_from date, p_to date)
returns table (
  occurred_on date, direction text, category text, amount numeric,
  facility_id uuid, note text, recurring boolean, entry_id uuid)
language sql stable set search_path = '' as $$
  select e.occurred_on, e.direction, e.category, e.amount, e.facility_id, e.note, false, e.id
  from app.ledger_entries e
  where e.org_id = p_org_id and e.occurred_on between p_from and p_to
  union all
  select o.due, 'expense', c.category, c.amount, c.facility_id, c.note, true, c.id
  from app.recurring_costs c
  cross join lateral (
    select (c.starts_on + n * case c.cadence
              when 'weekly' then interval '1 week'
              when 'monthly' then interval '1 month'
              when 'quarterly' then interval '3 months'
              else interval '1 year' end)::date as due
    from generate_series(0, greatest(p_to - c.starts_on, 0) / case c.cadence
              when 'weekly' then 7 when 'monthly' then 28 when 'quarterly' then 89 else 365 end) n
  ) o
  where c.org_id = p_org_id and c.is_active
    and o.due between greatest(p_from, c.starts_on) and least(p_to, coalesce(c.ends_on, p_to));
$$;

create function private.budget_dashboard(p_org_id uuid, p_from date, p_to date, p_bucket text)
returns jsonb language sql stable set search_path = '' as $$
  with w as materialized (
    select * from private.ledger_window(p_org_id, p_from, p_to)
  ),
  buckets as (
    select g::date as bucket_start
    from generate_series(date_trunc(p_bucket, p_from::timestamp), p_to::timestamp,
                         ('1 ' || p_bucket)::interval) g
  ),
  months as (
    select greatest(round((p_to - p_from + 1) / 30.4375, 2), 0.01) as n
  )
  select jsonb_build_object(
    'from', p_from, 'to', p_to, 'bucket', p_bucket,
    'currency', (select currency from app.organizations where id = p_org_id),
    'totals', (
      select jsonb_build_object(
        'income',  coalesce(sum(amount) filter (where direction = 'income'), 0),
        'expense', coalesce(sum(amount) filter (where direction = 'expense'), 0),
        'net',     coalesce(sum(case direction when 'income' then amount else -amount end), 0),
        'recurring_expense', coalesce(sum(amount) filter (where recurring), 0))
      from w),
    'series', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'bucket_start', b.bucket_start,
               'income',  coalesce((select sum(amount) from w
                                    where direction = 'income'
                                      and date_trunc(p_bucket, occurred_on::timestamp)::date = b.bucket_start), 0),
               'expense', coalesce((select sum(amount) from w
                                    where direction = 'expense'
                                      and date_trunc(p_bucket, occurred_on::timestamp)::date = b.bucket_start), 0))
             order by b.bucket_start), '[]'::jsonb)
      from buckets b),
    'categories', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'direction', c.direction, 'category', c.category, 'amount', c.amount,
               'monthly_limit', l.monthly_limit,
               'period_limit', round(l.monthly_limit * (select n from months), 2))
             order by c.direction, c.amount desc), '[]'::jsonb)
      from (
        select direction, category, sum(amount) as amount from w group by 1, 2
        union all
        select 'expense', bl.category, 0 from app.budget_limits bl
        where bl.org_id = p_org_id
          and not exists (select 1 from w where w.direction = 'expense' and w.category = bl.category)
      ) c
      left join app.budget_limits l
        on l.org_id = p_org_id and l.category = c.category and c.direction = 'expense'),
    'facilities', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'facility_id', f.id, 'name', f.name, 'tenure', f.tenure,
               'income',  coalesce((select sum(amount) from w where w.facility_id = f.id and direction = 'income'), 0),
               'expense', coalesce((select sum(amount) from w where w.facility_id = f.id and direction = 'expense'), 0))
             order by f.name), '[]'::jsonb)
      from app.facilities f where f.org_id = p_org_id),
    'recurring', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'category', c.category, 'amount', c.amount, 'cadence', c.cadence,
               'starts_on', c.starts_on, 'ends_on', c.ends_on, 'note', c.note,
               'is_active', c.is_active, 'facility_id', c.facility_id, 'facility_name', f.name)
             order by c.amount desc), '[]'::jsonb)
      from app.recurring_costs c
      left join app.facilities f on f.id = c.facility_id
      where c.org_id = p_org_id),
    'entries', (
      select coalesce(jsonb_agg(to_jsonb(e) order by e.occurred_on desc), '[]'::jsonb)
      from (
        select w.entry_id as id, w.occurred_on, w.direction, w.category, w.amount, w.note,
               w.recurring, w.facility_id, f.name as facility_name,
               coalesce(le.source, 'recurring') as source
        from w
        left join app.facilities f on f.id = w.facility_id
        left join app.ledger_entries le on le.id = w.entry_id and not w.recurring
        order by w.occurred_on desc
        limit 200) e));
$$;
