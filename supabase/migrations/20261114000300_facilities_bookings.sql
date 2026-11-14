-- =============================================================================
-- 0003 · Facilities, bookable resources and the booking calendar
-- =============================================================================

create table app.facilities (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references app.organizations (id) on delete cascade,
  name         text not null check (char_length(name) between 2 and 80),
  address      text,
  city         text,
  tenure       text not null default 'owned' check (tenure in ('owned', 'rented', 'leased')),
  cancel_hours int  not null default 6 check (cancel_hours between 0 and 168),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index facilities_org_idx on app.facilities (org_id);
create trigger facilities_touch before update on app.facilities
  for each row execute function private.touch_updated_at();

-- A court, table, pitch, net or gym floor. `capacity` > 1 turns a slot into a
-- shared session (gym floors, group classes) instead of an exclusive hire.
create table app.resources (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references app.organizations (id) on delete cascade,
  facility_id  uuid not null references app.facilities (id) on delete cascade,
  sport_code   text not null references app.sports (code),
  kind         text not null default 'court'
               check (kind in ('court', 'table', 'pitch', 'net', 'gym_floor', 'studio', 'other')),
  name         text not null check (char_length(name) between 1 and 60),
  capacity     int  not null default 1 check (capacity between 1 and 500),
  slot_minutes int  not null default 60 check (slot_minutes between 15 and 480),
  price        numeric(10, 2) not null default 0 check (price >= 0),
  auto_confirm boolean not null default true,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);
create index resources_facility_idx on app.resources (facility_id);
create index resources_org_idx on app.resources (org_id);

-- Opening hours per weekday (0 = Sunday). Several bands per day are allowed,
-- each with an optional price override, which is how peak pricing is modelled.
create table app.resource_hours (
  id          uuid primary key default gen_random_uuid(),
  resource_id uuid not null references app.resources (id) on delete cascade,
  weekday     smallint not null check (weekday between 0 and 6),
  opens       time not null,
  closes      time not null,
  price       numeric(10, 2) check (price >= 0),
  check (opens < closes)
);
create index resource_hours_idx on app.resource_hours (resource_id, weekday);

create table app.resource_blocks (
  id          uuid primary key default gen_random_uuid(),
  resource_id uuid not null references app.resources (id) on delete cascade,
  during      tstzrange not null check (not isempty(during)),
  reason      text,
  created_by  uuid references app.profiles (id),
  created_at  timestamptz not null default now()
);
create index resource_blocks_idx on app.resource_blocks using gist (resource_id, during);

create table app.bookings (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references app.organizations (id) on delete cascade,
  resource_id   uuid not null references app.resources (id) on delete cascade,
  user_id       uuid references app.profiles (id) on delete set null,
  customer_name text,
  kind          text not null default 'customer'
                check (kind in ('customer', 'walk_in', 'tournament', 'training')),
  during        tstzrange not null check (not isempty(during)),
  status        text not null default 'confirmed'
                check (status in ('pending', 'confirmed', 'cancelled', 'completed', 'no_show')),
  -- Copied from the resource (capacity = 1) so the constraint below can use it.
  exclusive     boolean not null default true,
  price         numeric(10, 2) not null default 0 check (price >= 0),
  notes         text check (char_length(notes) <= 500),
  cancel_reason text,
  cancelled_at  timestamptz,
  created_by    uuid references app.profiles (id),
  created_at    timestamptz not null default now(),
  -- The database, not the app, guarantees a court is never double booked.
  constraint bookings_no_overlap exclude using gist (resource_id with =, during with &&)
    where (exclusive and status in ('pending', 'confirmed', 'completed'))
);
create index bookings_user_idx on app.bookings (user_id, during);
create index bookings_org_idx on app.bookings using gist (org_id, during);

-- -----------------------------------------------------------------------------
-- Read models
-- -----------------------------------------------------------------------------
create view app.v_resources as
select r.id, r.org_id, r.facility_id, r.sport_code, r.kind, r.name, r.capacity,
       r.slot_minutes, r.price, r.auto_confirm, r.is_active,
       f.name as facility_name, f.city as facility_city, f.address as facility_address,
       f.cancel_hours, f.is_active as facility_is_active,
       o.name as org_name, o.currency, o.timezone, o.status as org_status
from app.resources r
join app.facilities f on f.id = r.facility_id
join app.organizations o on o.id = r.org_id;

create view app.v_bookings as
select b.id, b.org_id, b.resource_id, b.user_id, b.kind, b.status, b.price, b.notes,
       lower(b.during) as starts_at, upper(b.during) as ends_at,
       -- Wall-clock time at the venue: what a booking is shown as, wherever
       -- the device looking at it happens to be.
       lower(b.during) at time zone r.timezone as starts_local,
       upper(b.during) at time zone r.timezone as ends_local,
       b.cancel_reason, b.cancelled_at, b.created_at,
       coalesce(p.display_name, b.customer_name, 'Guest') as customer_name,
       r.name as resource_name, r.sport_code, r.kind as resource_kind,
       r.facility_id, r.facility_name, r.facility_city, r.cancel_hours,
       r.org_name, r.currency, r.timezone
from app.bookings b
join app.v_resources r on r.id = b.resource_id
left join app.profiles p on p.id = b.user_id;

-- Bookable slots of one resource on one local calendar day.
create function private.resource_slots(p_resource_id uuid, p_date date)
returns table (starts_at timestamptz, ends_at timestamptz, starts_local timestamp, ends_local timestamp,
               price numeric, booked int, capacity int, blocked boolean)
language sql stable set search_path = '' as $$
  select s.starts_at,
         s.starts_at + make_interval(mins => r.slot_minutes) as ends_at,
         s.starts_local,
         s.starts_local + make_interval(mins => r.slot_minutes) as ends_local,
         coalesce(h.price, r.price) as price,
         (select count(*)::int from app.bookings b
          where b.resource_id = r.id
            and b.status in ('pending', 'confirmed', 'completed')
            and b.during && tstzrange(s.starts_at, s.starts_at + make_interval(mins => r.slot_minutes))) as booked,
         r.capacity,
         exists (select 1 from app.resource_blocks k
                 where k.resource_id = r.id
                   and k.during && tstzrange(s.starts_at, s.starts_at + make_interval(mins => r.slot_minutes))) as blocked
  from app.v_resources r
  join app.resource_hours h on h.resource_id = r.id and h.weekday = extract(dow from p_date)::int
  cross join lateral (
    select (g at time zone r.timezone) as starts_at, g as starts_local
    from generate_series(
      p_date + h.opens,
      p_date + h.closes - make_interval(mins => r.slot_minutes),
      make_interval(mins => r.slot_minutes)) g
  ) s
  where r.id = p_resource_id
  order by s.starts_at;
$$;
