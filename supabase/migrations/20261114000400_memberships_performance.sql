-- =============================================================================
-- 0004 · Membership plans, memberships and continuous performance tracking
-- =============================================================================

-- What an organisation sells beyond single slots. Tiers that track performance
-- (club members, mentees) get a coach, logged sessions, measured metrics and
-- periodic written reports: the "journey".
create table app.membership_plans (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references app.organizations (id) on delete cascade,
  name                 text not null check (char_length(name) between 2 and 80),
  description          text check (char_length(description) <= 1000),
  tier                 text not null default 'member' check (tier in ('pass', 'member', 'club', 'mentee')),
  sport_code           text references app.sports (code),
  price                numeric(10, 2) not null default 0 check (price >= 0),
  billing_period       text not null default 'monthly'
                       check (billing_period in ('one_time', 'weekly', 'monthly', 'quarterly', 'yearly')),
  booking_discount_pct numeric(5, 2) not null default 0 check (booking_discount_pct between 0 and 100),
  tracks_performance   boolean not null default false,
  is_active            boolean not null default true,
  created_at           timestamptz not null default now()
);
create index membership_plans_org_idx on app.membership_plans (org_id);

create table app.memberships (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references app.organizations (id) on delete cascade,
  plan_id    uuid not null references app.membership_plans (id) on delete restrict,
  user_id    uuid not null references app.profiles (id) on delete cascade,
  coach_id   uuid references app.profiles (id) on delete set null,
  status     text not null default 'pending'
             check (status in ('pending', 'active', 'paused', 'expired', 'cancelled', 'rejected')),
  note       text check (char_length(note) <= 500),
  starts_on  date,
  ends_on    date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index memberships_one_live_idx on app.memberships (plan_id, user_id)
  where status in ('pending', 'active', 'paused');
create index memberships_user_idx on app.memberships (user_id);
create index memberships_org_idx on app.memberships (org_id, status);
create trigger memberships_touch before update on app.memberships
  for each row execute function private.touch_updated_at();

create table app.training_sessions (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references app.organizations (id) on delete cascade,
  membership_id uuid not null references app.memberships (id) on delete cascade,
  coach_id      uuid references app.profiles (id) on delete set null,
  held_on       date not null default current_date,
  minutes       int not null default 60 check (minutes between 5 and 600),
  attendance    text not null default 'present' check (attendance in ('present', 'absent', 'excused')),
  focus         text,
  notes         text check (char_length(notes) <= 1000),
  created_at    timestamptz not null default now()
);
create index training_sessions_membership_idx on app.training_sessions (membership_id, held_on desc);

-- What gets measured. Rows without an org are the built-in catalogue.
create table app.metric_definitions (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid references app.organizations (id) on delete cascade,
  sport_code       text not null references app.sports (code),
  key              text not null check (key ~ '^[a-z0-9_]{2,40}$'),
  name             text not null,
  unit             text not null default '',
  higher_is_better boolean not null default true,
  sort_order       int not null default 0
);
create unique index metric_definitions_key_idx
  on app.metric_definitions (coalesce(org_id, '00000000-0000-0000-0000-000000000000'::uuid), sport_code, key);

create table app.performance_entries (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null references app.memberships (id) on delete cascade,
  metric_id     uuid not null references app.metric_definitions (id) on delete cascade,
  value         numeric(12, 3) not null,
  recorded_on   date not null default current_date,
  note          text,
  recorded_by   uuid references app.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);
create index performance_entries_idx on app.performance_entries (membership_id, metric_id, recorded_on);

create table app.performance_reports (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null references app.memberships (id) on delete cascade,
  coach_id      uuid references app.profiles (id) on delete set null,
  period_start  date not null,
  period_end    date not null,
  rating        smallint check (rating between 1 and 10),
  summary       text not null check (char_length(summary) between 5 and 4000),
  strengths     text,
  focus_areas   text,
  published_at  timestamptz not null default now(),
  check (period_start <= period_end)
);
create index performance_reports_idx on app.performance_reports (membership_id, period_end desc);

create view app.v_memberships as
select m.id, m.org_id, m.plan_id, m.user_id, m.coach_id, m.status, m.note,
       m.starts_on, m.ends_on, m.created_at,
       o.name as org_name, o.currency,
       pl.name as plan_name, pl.tier, pl.sport_code, pl.price, pl.billing_period,
       pl.tracks_performance, pl.booking_discount_pct,
       u.display_name as member_name, u.avatar_url as member_avatar_url,
       c.display_name as coach_name
from app.memberships m
join app.organizations o on o.id = m.org_id
join app.membership_plans pl on pl.id = m.plan_id
join app.profiles u on u.id = m.user_id
left join app.profiles c on c.id = m.coach_id;

-- The continuous performance report for one membership: attendance, a time
-- series per metric with its trend, coach reports and the latest sessions.
-- Shared by the member's own view and the coach's view.
create function private.journey(p_membership_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'membership', to_jsonb(m),
    'attendance', (
      select jsonb_build_object(
        'sessions', count(*),
        'present',  count(*) filter (where s.attendance = 'present'),
        'absent',   count(*) filter (where s.attendance = 'absent'),
        'excused',  count(*) filter (where s.attendance = 'excused'),
        'minutes',  coalesce(sum(s.minutes) filter (where s.attendance = 'present'), 0),
        'last_30_days', count(*) filter (where s.attendance = 'present' and s.held_on >= current_date - 30))
      from app.training_sessions s where s.membership_id = m.id),
    'metrics', coalesce((
      select jsonb_agg(x.metric order by x.sort_order, x.name)
      from (
        select d.sort_order, d.name,
               jsonb_build_object(
                 'id', d.id, 'key', d.key, 'name', d.name, 'unit', d.unit,
                 'higher_is_better', d.higher_is_better,
                 'first', (array_agg(e.value order by e.recorded_on, e.created_at))[1],
                 'latest', (array_agg(e.value order by e.recorded_on desc, e.created_at desc))[1],
                 'best', case when d.higher_is_better then max(e.value) else min(e.value) end,
                 'points', jsonb_agg(jsonb_build_object('on', e.recorded_on, 'value', e.value, 'note', e.note)
                                     order by e.recorded_on, e.created_at)) as metric
        from app.performance_entries e
        join app.metric_definitions d on d.id = e.metric_id
        where e.membership_id = m.id
        group by d.id
      ) x), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'period_start', r.period_start, 'period_end', r.period_end,
               'rating', r.rating, 'summary', r.summary, 'strengths', r.strengths,
               'focus_areas', r.focus_areas, 'published_at', r.published_at,
               'coach_name', c.display_name) order by r.period_end desc, r.published_at desc)
      from app.performance_reports r
      left join app.profiles c on c.id = r.coach_id
      where r.membership_id = m.id), '[]'::jsonb),
    'sessions', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.held_on desc, s.created_at desc)
      from (select t.id, t.held_on, t.minutes, t.attendance, t.focus, t.notes, t.created_at
            from app.training_sessions t
            where t.membership_id = m.id
            order by t.held_on desc, t.created_at desc
            limit 30) s), '[]'::jsonb))
  from app.v_memberships m
  where m.id = p_membership_id;
$$;
