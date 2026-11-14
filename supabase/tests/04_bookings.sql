-- Facilities, availability, bookings, capacity, cancellation and payments.
select t.user('desk@sidi.test'), t.user('p1@sidi.test'), t.user('p2@sidi.test');
set role authenticated;
select set_config('test.org', t.org('desk@sidi.test', 'Court House')::text, false);

-- A rented hall records its rent as a recurring cost.
select set_config('test.fac', public.org_facility_save(current_setting('test.org')::uuid,
  '{"name": "Main hall", "tenure": "rented", "monthly_cost": 60000, "cancel_hours": 4}') ->> 'id', false);
select t.eq((t.q(format($$select amount, category from app.recurring_costs where facility_id = %L$$,
  current_setting('test.fac'))) ->> 'category'), 'rent', 'rent became a recurring cost');

-- Court 1: hourly slots 06-22 every day, peak price after 18:00 on all days.
select set_config('test.court', public.org_resource_save(current_setting('test.org')::uuid, jsonb_build_object(
  'facility_id', current_setting('test.fac'), 'sport_code', 'badminton', 'name', 'Court 1', 'price', 400,
  'hours', (select jsonb_agg(h) from generate_series(0, 6) d,
            lateral (values (jsonb_build_object('weekday', d, 'opens', '06:00', 'closes', '18:00')),
                            (jsonb_build_object('weekday', d, 'opens', '18:00', 'closes', '22:00', 'price', 600))) v (h)))) ->> 'id', false);
select t.throws(format($$select public.org_resource_save(%L, '{"facility_id": %s, "sport_code": "badminton", "name": "Bad", "slot_minutes": 5}')$$,
  current_setting('test.org'), to_jsonb(current_setting('test.fac'))), 'invalid_resource');

-- Tomorrow 07:00 and 19:00 local time.
select set_config('test.t7', (((current_date + 1) + time '07:00') at time zone 'Asia/Kolkata')::text, false);
select set_config('test.t19', (((current_date + 1) + time '19:00') at time zone 'Asia/Kolkata')::text, false);

select t.login('p1@sidi.test');
select t.eq(jsonb_array_length(public.resource_availability(current_setting('test.court')::uuid, current_date + 1) -> 'slots'), 16,
  '16 one-hour slots between 06:00 and 22:00');
select t.eq((public.booking_create(current_setting('test.court')::uuid, current_setting('test.t7')::timestamptz, 2) ->> 'price')::numeric,
  800::numeric, 'two off-peak slots cost 800');
select t.eq((public.booking_create(current_setting('test.court')::uuid, current_setting('test.t19')::timestamptz) ->> 'price')::numeric,
  600::numeric, 'the peak band overrides the price');

-- The court cannot be double booked, by anyone, on any overlapping slot.
select t.login('p2@sidi.test');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.court'),
  (current_setting('test.t7')::timestamptz + interval '1 hour')::text), 'slot_taken');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.court'),
  (current_setting('test.t7')::timestamptz + interval '30 minutes')::text), 'outside_hours', 'off-grid start');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.court'),
  (((current_date + 1) + time '23:00') at time zone 'Asia/Kolkata')::text), 'outside_hours');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.court'),
  (now() - interval '1 day')::text), 'in_the_past');
select t.eq((select count(*) from jsonb_array_elements(
  public.resource_availability(current_setting('test.court')::uuid, current_date + 1) -> 'slots') s
  where s ->> 'status' = 'full'), 3::bigint, 'three slots show as taken');

-- Maintenance blocks close slots.
select t.login('desk@sidi.test');
-- Organisations type venue wall-clock times: 10:00 to 12:00 tomorrow.
select public.org_resource_block(current_setting('test.court')::uuid,
  (current_date + 1) + time '10:00', (current_date + 1) + time '12:00', 'Floor polish');
select t.login('p2@sidi.test');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.court'),
  (current_setting('test.t7')::timestamptz + interval '3 hours')::text), 'slot_blocked');

-- Customers cancel their own bookings, inside the venue's window only.
select t.login('p1@sidi.test');
select t.eq(jsonb_array_length(public.my_bookings()), 2, 'two upcoming bookings');
select t.eq(public.my_bookings() #>> '{0,starts_local}', to_char((current_date + 1) + time '07:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
  'bookings are reported in venue wall-clock time');
select t.ok((public.my_bookings() #>> '{0,can_cancel}')::boolean, 'the server says whether a booking can still be cancelled');
select t.throws(format('select public.booking_cancel(%L)', public.my_bookings() #>> '{0,id}'), 'booking_not_found', 'not p2''s booking')
from (select t.login('p2@sidi.test')) x;
select t.login('p1@sidi.test');
select public.booking_cancel((public.my_bookings() #>> '{1,id}')::uuid, 'Plans changed');
select t.eq(jsonb_array_length(public.my_bookings()), 1, 'one left after cancelling');
select t.login('p2@sidi.test');
select t.ok(public.booking_create(current_setting('test.court')::uuid, current_setting('test.t19')::timestamptz) ->> 'status' = 'confirmed',
  'a cancelled slot can be booked again');

-- Paying a booking books income against the facility; refunding removes it.
select t.login('desk@sidi.test');
select t.eq(jsonb_array_length(public.org_bookings(current_setting('test.org')::uuid, current_date + 1, current_date + 1)), 3,
  'front desk sees all bookings of the day, including the cancelled one');
select t.eq(jsonb_array_length(public.org_payments(current_setting('test.org')::uuid, 'pending')), 2, 'two payments due, one voided');
select public.org_payment_settle((public.org_payments(current_setting('test.org')::uuid, 'pending') #>> '{0,id}')::uuid, 'paid', 'upi');
select t.eq((public.org_overview(current_setting('test.org')::uuid) #>> '{stats,month_income}')::numeric, 600::numeric, 'income booked');
select t.eq((t.q(format($$select facility_id from app.ledger_entries where org_id = %L and source = 'payment'$$,
  current_setting('test.org'))) ->> 'facility_id'), current_setting('test.fac'), 'income is attributed to the facility');
select public.org_payment_settle((public.org_payments(current_setting('test.org')::uuid, 'paid') #>> '{0,id}')::uuid, 'refunded');
select t.eq((public.org_overview(current_setting('test.org')::uuid) #>> '{stats,month_income}')::numeric, 0::numeric, 'refund removes the income');

-- Walk-ins at the desk; a gym floor takes several people per slot.
select public.org_booking_create(current_setting('test.court')::uuid, (current_date + 1) + time '13:00', 1, 'Walk-in Ravi', null, 350);
select t.eq((select b ->> 'starts_local' from jsonb_array_elements(public.org_bookings(current_setting('test.org')::uuid, current_date + 1, current_date + 1)) b
             where b ->> 'kind' = 'walk_in'), to_char((current_date + 1) + time '13:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
  'a walk-in at 13:00 venue time reads back as 13:00');
select set_config('test.gym', public.org_resource_save(current_setting('test.org')::uuid, jsonb_build_object(
  'facility_id', current_setting('test.fac'), 'sport_code', 'gym', 'kind', 'gym_floor', 'name', 'Gym floor',
  'capacity', 2, 'price', 150)) ->> 'id', false);
select t.login('p1@sidi.test');
select public.booking_create(current_setting('test.gym')::uuid, current_setting('test.t7')::timestamptz);
select t.login('p2@sidi.test');
select public.booking_create(current_setting('test.gym')::uuid, current_setting('test.t7')::timestamptz);
select t.login('desk@sidi.test');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.gym'), current_setting('test.t7')), 'slot_taken',
  'the third person finds the session full');
select t.eq((public.resource_availability(current_setting('test.gym')::uuid, current_date + 1) #>> '{slots,1,status}'), 'full', 'shown as full');
reset role;
