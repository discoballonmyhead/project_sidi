-- =============================================================================
-- 0011 · Public API: facilities, resources, availability, bookings, payments
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Facility & resource management
-- -----------------------------------------------------------------------------
create function public.org_facilities(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff'], true);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', f.id, 'name', f.name, 'address', f.address, 'city', f.city, 'tenure', f.tenure,
             'cancel_hours', f.cancel_hours, 'is_active', f.is_active,
             'monthly_cost', (select coalesce(sum(case c.cadence
                                 when 'weekly' then c.amount * 52 / 12
                                 when 'monthly' then c.amount
                                 when 'quarterly' then c.amount / 3
                                 else c.amount / 12 end), 0)
                              from app.recurring_costs c where c.facility_id = f.id and c.is_active),
             'resources', coalesce((
               select jsonb_agg(to_jsonb(r) || jsonb_build_object(
                        'hours', coalesce((
                          select jsonb_agg(jsonb_build_object(
                                   'weekday', h.weekday, 'opens', to_char(h.opens, 'HH24:MI'),
                                   'closes', to_char(h.closes, 'HH24:MI'), 'price', h.price)
                                 order by h.weekday, h.opens)
                          from app.resource_hours h where h.resource_id = r.id), '[]'::jsonb),
                        'blocks', coalesce((
                          select jsonb_agg(jsonb_build_object(
                                   'id', k.id, 'starts_at', lower(k.during), 'ends_at', upper(k.during), 'reason', k.reason)
                                 order by lower(k.during))
                          from app.resource_blocks k
                          where k.resource_id = r.id and upper(k.during) > now()), '[]'::jsonb))
                      order by r.sport_code, r.name)
               from app.v_resources r where r.facility_id = f.id), '[]'::jsonb))
           order by f.name)
    from app.facilities f where f.org_id = p_org_id), '[]'::jsonb);
end $$;

-- Creates or updates a facility. `monthly_cost` on a new facility records the
-- rent (rented / leased) or loan repayment (owned) as a recurring cost.
create function public.org_facility_save(p_org_id uuid, p_facility jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := private.require_org(p_org_id);
  v_id     uuid := (p_facility ->> 'id')::uuid;
  v_name   text := private.clean(p_facility ->> 'name');
  v_tenure text := coalesce(p_facility ->> 'tenure', 'owned');
  v_cost   numeric := coalesce((p_facility ->> 'monthly_cost')::numeric, 0);
begin
  if v_tenure not in ('owned', 'rented', 'leased') then
    perform private.fail(422, 'invalid_facility', 'Tenure must be owned, rented or leased.');
  end if;
  if v_id is null then
    if v_name is null then
      perform private.fail(422, 'invalid_facility', 'Give the facility a name.');
    end if;
    insert into app.facilities (org_id, name, address, city, tenure, cancel_hours)
    values (p_org_id, v_name, private.clean(p_facility ->> 'address'), private.clean(p_facility ->> 'city'),
            v_tenure, coalesce((p_facility ->> 'cancel_hours')::int, 6))
    returning id into v_id;
    if v_cost > 0 then
      insert into app.recurring_costs (org_id, facility_id, category, amount, cadence, note)
      values (p_org_id, v_id, case v_tenure when 'owned' then 'mortgage' else 'rent' end, v_cost, 'monthly',
              case v_tenure when 'owned' then 'Loan repayment · ' else 'Rent · ' end || v_name);
    end if;
  else
    update app.facilities
    set name = coalesce(v_name, name),
        address = case when p_facility ? 'address' then private.clean(p_facility ->> 'address') else address end,
        city = case when p_facility ? 'city' then private.clean(p_facility ->> 'city') else city end,
        tenure = case when p_facility ? 'tenure' then v_tenure else tenure end,
        cancel_hours = coalesce((p_facility ->> 'cancel_hours')::int, cancel_hours),
        is_active = coalesce((p_facility ->> 'is_active')::boolean, is_active)
    where id = v_id and org_id = p_org_id;
    if not found then
      perform private.fail(404, 'facility_not_found', 'Facility not found.');
    end if;
  end if;
  return jsonb_build_object('id', v_id);
exception when check_violation then
  perform private.fail(422, 'invalid_facility', 'Check the facility name and cancellation window.');
  return null;
end $$;

-- Creates or updates a bookable resource. `hours` replaces the opening hours:
-- [{"weekday": 1, "opens": "06:00", "closes": "22:00", "price": 400}]
create function public.org_resource_save(p_org_id uuid, p_resource jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id);
  v_id  uuid := (p_resource ->> 'id')::uuid;
  v_new boolean := (p_resource ->> 'id') is null;
begin
  perform private.require_feature(p_org_id, 'bookings');
  if v_new then
    if not exists (select 1 from app.facilities
                   where id = (p_resource ->> 'facility_id')::uuid and org_id = p_org_id) then
      perform private.fail(404, 'facility_not_found', 'Facility not found.');
    end if;
    insert into app.resources (org_id, facility_id, sport_code, kind, name, capacity, slot_minutes, price, auto_confirm)
    values (p_org_id, (p_resource ->> 'facility_id')::uuid, p_resource ->> 'sport_code',
            coalesce(p_resource ->> 'kind', 'court'), private.clean(p_resource ->> 'name'),
            coalesce((p_resource ->> 'capacity')::int, 1), coalesce((p_resource ->> 'slot_minutes')::int, 60),
            coalesce((p_resource ->> 'price')::numeric, 0), coalesce((p_resource ->> 'auto_confirm')::boolean, true))
    returning id into v_id;
  else
    update app.resources
    set name = coalesce(private.clean(p_resource ->> 'name'), name),
        sport_code = coalesce(p_resource ->> 'sport_code', sport_code),
        kind = coalesce(p_resource ->> 'kind', kind),
        capacity = coalesce((p_resource ->> 'capacity')::int, capacity),
        slot_minutes = coalesce((p_resource ->> 'slot_minutes')::int, slot_minutes),
        price = coalesce((p_resource ->> 'price')::numeric, price),
        auto_confirm = coalesce((p_resource ->> 'auto_confirm')::boolean, auto_confirm),
        is_active = coalesce((p_resource ->> 'is_active')::boolean, is_active)
    where id = v_id and org_id = p_org_id;
    if not found then
      perform private.fail(404, 'resource_not_found', 'Resource not found.');
    end if;
  end if;

  if jsonb_typeof(p_resource -> 'hours') = 'array' then
    delete from app.resource_hours where resource_id = v_id;
    insert into app.resource_hours (resource_id, weekday, opens, closes, price)
    select v_id, (h ->> 'weekday')::smallint, (h ->> 'opens')::time,
           case when h ->> 'closes' in ('24:00', '00:00') then time '24:00' else (h ->> 'closes')::time end,
           (h ->> 'price')::numeric
    from jsonb_array_elements(p_resource -> 'hours') h;
  elsif v_new then
    insert into app.resource_hours (resource_id, weekday, opens, closes)
    select v_id, d, time '06:00', time '22:00' from generate_series(0, 6) d;
  end if;
  return jsonb_build_object('id', v_id);
exception
  when check_violation or not_null_violation or foreign_key_violation or invalid_datetime_format
       or datetime_field_overflow or invalid_text_representation then
    perform private.fail(422, 'invalid_resource',
      'Check the resource details: name, sport, slot length (15-480 min), price and opening hours.');
    return null;
end $$;

create function public.org_resource_block(p_resource_id uuid, p_from timestamptz, p_to timestamptz, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  v_uid := private.require_org((select org_id from app.resources where id = p_resource_id),
                               array['owner', 'manager', 'staff']);
  if p_from is null or p_to is null or p_to <= p_from then
    perform private.fail(422, 'invalid_range', 'The block must end after it starts.');
  end if;
  insert into app.resource_blocks (resource_id, during, reason, created_by)
  values (p_resource_id, tstzrange(p_from, p_to), private.clean(p_reason), v_uid);
end $$;

create function public.org_resource_unblock(p_block_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_org(
    (select r.org_id from app.resource_blocks k join app.resources r on r.id = k.resource_id where k.id = p_block_id),
    array['owner', 'manager', 'staff']);
  delete from app.resource_blocks where id = p_block_id;
end $$;

-- -----------------------------------------------------------------------------
-- Booking
-- -----------------------------------------------------------------------------
create function private.member_discount(p_org_id uuid, p_user_id uuid)
returns numeric language sql stable set search_path = '' as $$
  select coalesce(max(pl.booking_discount_pct), 0)
  from app.memberships m join app.membership_plans pl on pl.id = m.plan_id
  where m.org_id = p_org_id and m.user_id = p_user_id and m.status = 'active';
$$;

create function public.resource_availability(p_resource_id uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.uid();
  v_res app.v_resources;
begin
  select * into v_res from app.v_resources where id = p_resource_id;
  if not found or v_res.org_status <> 'approved' then
    perform private.fail(404, 'resource_not_found', 'Resource not found.');
  end if;
  return jsonb_build_object(
    'resource', to_jsonb(v_res),
    'date', p_date,
    'discount_pct', private.member_discount(v_res.org_id, v_uid),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
               'starts_at', s.starts_at, 'ends_at', s.ends_at, 'price', s.price,
               'remaining', greatest(s.capacity - s.booked, 0),
               'status', case
                 when s.blocked then 'blocked'
                 when s.starts_at <= now() then 'past'
                 when s.booked >= s.capacity then 'full'
                 else 'free' end)
             order by s.starts_at)
      from private.resource_slots(p_resource_id, p_date) s), '[]'::jsonb));
end $$;

-- The one way a booking comes into existence. Customer bookings must sit on
-- the resource's slot grid inside opening hours; organisation bookings
-- (tournament matches, training) may use any free time.
create function private.booking_place(
  p_resource_id uuid, p_starts_at timestamptz, p_slots int, p_user_id uuid, p_customer_name text,
  p_kind text, p_notes text, p_price numeric, p_by uuid, p_minutes int default null)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_res    app.v_resources;
  v_slot   interval;
  v_ends   timestamptz;
  v_price  numeric := 0;
  v_one    numeric;
  v_local  timestamp;
  v_at     timestamptz;
  v_id     uuid;
  v_public boolean := p_kind in ('customer', 'walk_in');
begin
  select * into v_res from app.v_resources where id = p_resource_id;
  if not found then
    perform private.fail(404, 'resource_not_found', 'Resource not found.');
  end if;
  if not v_res.is_active or not v_res.facility_is_active or v_res.org_status <> 'approved' then
    perform private.fail(409, 'resource_unavailable', 'This resource is not taking bookings.');
  end if;
  if p_starts_at is null or coalesce(p_slots, 0) not between 1 and 12 then
    perform private.fail(422, 'invalid_booking', 'Pick a start time and between 1 and 12 slots.');
  end if;
  v_slot := make_interval(mins => v_res.slot_minutes);

  if v_public then
    -- The desk may log a walk-in after the fact; customers book ahead only.
    if p_starts_at < now() - (case when p_kind = 'walk_in' then interval '12 hours' else interval '0' end) then
      perform private.fail(422, 'in_the_past', 'That time has already passed.');
    end if;
    for v_i in 0..p_slots - 1 loop
      v_at := p_starts_at + v_i * v_slot;
      v_local := v_at at time zone v_res.timezone;
      select coalesce(h.price, v_res.price) into v_one
      from app.resource_hours h
      where h.resource_id = p_resource_id
        and h.weekday = extract(dow from v_local)::int
        and v_local::time >= h.opens
        and (v_local::time - time '00:00') + v_slot <= (h.closes - time '00:00')
        and extract(epoch from (v_local::time - h.opens))::int % (v_res.slot_minutes * 60) = 0
      limit 1;
      if not found then
        perform private.fail(422, 'outside_hours', 'That time is outside the opening hours.');
      end if;
      v_price := v_price + v_one;
      -- Shared resources (gym floors, classes) fill up slot by slot.
      if v_res.capacity > 1 and (
           select count(*) from app.bookings b
           where b.resource_id = p_resource_id and b.status in ('pending', 'confirmed', 'completed')
             and b.during && tstzrange(v_at, v_at + v_slot)) >= v_res.capacity then
        perform private.fail(409, 'slot_taken', 'That session is full.');
      end if;
    end loop;
    v_ends := p_starts_at + p_slots * v_slot;
    if p_kind = 'customer' then
      v_price := round(v_price * (1 - private.member_discount(v_res.org_id, p_user_id) / 100), 2);
    end if;
  else
    v_ends := p_starts_at + make_interval(mins => coalesce(p_minutes, v_res.slot_minutes * p_slots));
    v_price := 0;
  end if;
  v_price := coalesce(p_price, v_price);

  if exists (select 1 from app.resource_blocks k
             where k.resource_id = p_resource_id and k.during && tstzrange(p_starts_at, v_ends)) then
    perform private.fail(409, 'slot_blocked', 'The resource is closed at that time.');
  end if;

  begin
    insert into app.bookings (org_id, resource_id, user_id, customer_name, kind, during, status,
                              exclusive, price, notes, created_by)
    values (v_res.org_id, p_resource_id, p_user_id, private.clean(p_customer_name), p_kind,
            tstzrange(p_starts_at, v_ends),
            case when p_kind = 'customer' and not v_res.auto_confirm then 'pending' else 'confirmed' end,
            v_res.capacity = 1, v_price, private.clean(p_notes), p_by)
    returning id into v_id;
  exception when exclusion_violation then
    perform private.fail(409, 'slot_taken', 'That time has just been taken.');
  end;

  if v_public then
    perform private.payment_open(v_res.org_id, p_user_id, 'booking', v_id, v_price,
      format('%s · %s', v_res.name, to_char(p_starts_at at time zone v_res.timezone, 'DD Mon HH24:MI')));
  end if;
  return v_id;
end $$;

create function public.booking_create(
  p_resource_id uuid, p_starts_at timestamptz, p_slots int default 1, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.uid();
  v_id  uuid;
  v_row app.v_bookings;
begin
  -- Serialise bookings per resource so capacity checks cannot race.
  perform 1 from app.resources where id = p_resource_id for update;
  v_id := private.booking_place(p_resource_id, p_starts_at, p_slots, v_uid, null, 'customer', p_notes, null, v_uid);
  select * into v_row from app.v_bookings where id = v_id;
  if v_row.status = 'pending' then
    perform private.notify_org(v_row.org_id, 'booking_pending', 'Booking waiting for confirmation',
      format('%s · %s', v_row.customer_name, v_row.resource_name), jsonb_build_object('booking_id', v_id));
  end if;
  return to_jsonb(v_row);
end $$;

create function public.booking_cancel(p_booking_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.uid();
  v_b   app.v_bookings;
begin
  select * into v_b from app.v_bookings where id = p_booking_id and user_id = v_uid;
  if not found then
    perform private.fail(404, 'booking_not_found', 'Booking not found.');
  end if;
  if v_b.status not in ('pending', 'confirmed') then
    perform private.fail(409, 'booking_closed', 'This booking can no longer be cancelled.');
  end if;
  if v_b.starts_at - make_interval(hours => v_b.cancel_hours) < now() then
    perform private.fail(409, 'too_late_to_cancel',
      format('Bookings here can be cancelled up to %s hours before the start. Contact the venue.', v_b.cancel_hours));
  end if;
  update app.bookings
  set status = 'cancelled', cancelled_at = now(), cancel_reason = private.clean(p_reason)
  where id = p_booking_id;
  perform private.payment_void_for('booking', p_booking_id);
  perform private.notify_org(v_b.org_id, 'booking_cancelled', 'Booking cancelled',
    format('%s · %s', v_b.customer_name, v_b.resource_name), jsonb_build_object('booking_id', p_booking_id));
end $$;

create function private.booking_json(p_row app.v_bookings)
returns jsonb language sql stable set search_path = '' as $$
  select to_jsonb(p_row) || jsonb_build_object('payment', (
    select jsonb_build_object('id', p.id, 'status', p.status, 'amount', p.amount, 'method', p.method)
    from app.payments p
    where p.purpose = 'booking' and p.ref_id = p_row.id
    order by p.created_at desc limit 1));
$$;

create function public.my_bookings(p_scope text default 'upcoming')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  return coalesce((
    select jsonb_agg(private.booking_json(b) order by
             case when p_scope = 'upcoming' then b.starts_at end,
             case when p_scope <> 'upcoming' then b.starts_at end desc)
    from app.v_bookings b
    where b.user_id = v_uid and b.kind = 'customer'
      and case when p_scope = 'upcoming'
               then b.ends_at >= now() and b.status in ('pending', 'confirmed')
               else b.ends_at < now() or b.status not in ('pending', 'confirmed') end), '[]'::jsonb);
end $$;

-- -----------------------------------------------------------------------------
-- Front desk
-- -----------------------------------------------------------------------------
create function public.org_bookings(p_org_id uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff']);
begin
  return coalesce((
    select jsonb_agg(private.booking_json(b) order by b.starts_at)
    from app.v_bookings b
    where b.org_id = p_org_id
      and (b.starts_at at time zone b.timezone)::date between p_from and p_to), '[]'::jsonb);
end $$;

-- Walk-in or phone booking taken at the desk, optionally for a registered user.
create function public.org_booking_create(
  p_resource_id uuid, p_starts_at timestamptz, p_slots int, p_customer_name text,
  p_handle text default null, p_price numeric default null, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid;
  v_user uuid := private.find_user(p_handle);
  v_id   uuid;
begin
  v_uid := private.require_org((select org_id from app.resources where id = p_resource_id),
                               array['owner', 'manager', 'staff']);
  if v_user is null and private.clean(p_customer_name) is null then
    perform private.fail(422, 'invalid_booking', 'Enter the customer''s name.');
  end if;
  perform 1 from app.resources where id = p_resource_id for update;
  v_id := private.booking_place(p_resource_id, p_starts_at, p_slots, v_user, p_customer_name,
                                'walk_in', p_notes, p_price, v_uid);
  return jsonb_build_object('id', v_id);
end $$;

create function public.org_booking_set_status(p_booking_id uuid, p_status text, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_b   app.v_bookings;
begin
  select * into v_b from app.v_bookings where id = p_booking_id;
  if not found then
    perform private.fail(404, 'booking_not_found', 'Booking not found.');
  end if;
  v_uid := private.require_org(v_b.org_id, array['owner', 'manager', 'staff']);
  if p_status not in ('confirmed', 'cancelled', 'completed', 'no_show') then
    perform private.fail(422, 'invalid_status', 'Unknown booking status.');
  end if;
  if v_b.status = 'cancelled' then
    perform private.fail(409, 'booking_closed', 'A cancelled booking cannot be changed. Create a new one.');
  end if;
  update app.bookings
  set status = p_status,
      cancelled_at = case when p_status = 'cancelled' then now() end,
      cancel_reason = case when p_status = 'cancelled' then private.clean(p_reason) end
  where id = p_booking_id;
  if p_status = 'cancelled' then
    perform private.payment_void_for('booking', p_booking_id);
  end if;
  perform private.notify(v_b.user_id, 'booking_' || p_status, 'Booking ' || replace(p_status, '_', ' '),
    format('%s · %s', v_b.org_name, v_b.resource_name), jsonb_build_object('booking_id', p_booking_id));
end $$;

-- -----------------------------------------------------------------------------
-- Payments desk
-- -----------------------------------------------------------------------------
create function public.org_payments(p_org_id uuid, p_status text default null, p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'staff']);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.created_at desc)
    from (select * from app.v_payments
          where org_id = p_org_id and (p_status is null or status = p_status)
          order by created_at desc limit least(greatest(p_limit, 1), 500)) p), '[]'::jsonb);
end $$;

create function public.org_payment_settle(
  p_payment_id uuid, p_status text, p_method text default null, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  v_uid := private.require_org((select org_id from app.payments where id = p_payment_id),
                               array['owner', 'manager', 'staff']);
  if p_method is not null and p_method not in ('cash', 'upi', 'card', 'bank_transfer', 'online', 'other') then
    perform private.fail(422, 'invalid_method', 'Unknown payment method.');
  end if;
  perform private.payment_settle(p_payment_id, p_status, p_method, p_note, v_uid);
end $$;
