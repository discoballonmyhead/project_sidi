-- Plans, joining, coaching and the continuous performance report.
select t.user('head@sidi.test'), t.user('coachk@sidi.test'), t.user('mentee@sidi.test'), t.user('other@sidi.test');
set role authenticated;
select set_config('test.org', t.org('head@sidi.test', 'Shuttle Academy')::text, false);
select public.org_team_set(current_setting('test.org')::uuid, 'coachk@sidi.test', 'coach');

select set_config('test.plan', public.org_plan_save(current_setting('test.org')::uuid,
  '{"name": "Elite mentorship", "tier": "mentee", "sport_code": "badminton", "price": 5000, "booking_discount_pct": 20}') ->> 'id', false);
select t.ok((t.q(format('select tracks_performance from app.membership_plans where id = %L', current_setting('test.plan')))
  ->> 'tracks_performance')::boolean, 'mentee plans track performance by default');

select t.login('mentee@sidi.test');
select set_config('test.ms', public.membership_join(current_setting('test.plan')::uuid, 'State U17 player') ->> 'id', false);
select t.throws(format('select public.membership_join(%L)', current_setting('test.plan')), 'already_joined');
select t.eq(public.my_memberships() #>> '{0,status}', 'pending', 'waits for the academy');

select t.login('coachk@sidi.test');
select t.throws(format('select public.org_membership_decide(%L, true)', current_setting('test.ms')), 'forbidden', 'coaches cannot admit members');
select t.login('head@sidi.test');
select t.throws(format('select public.org_membership_decide(%L, true, %L)', current_setting('test.ms'), t.user('other@sidi.test')),
  'invalid_coach');
select public.org_membership_decide(current_setting('test.ms')::uuid, true, t.user('coachk@sidi.test'));
select t.eq(jsonb_array_length(public.org_payments(current_setting('test.org')::uuid, 'pending')), 1, 'the first fee is due');

-- The coach logs sessions, measurements and a report.
select t.login('coachk@sidi.test');
select public.org_session_log(current_setting('test.ms')::uuid, format('{"held_on": "%s", "minutes": 90, "focus": "Footwork"}', current_date - 14)::jsonb);
select public.org_session_log(current_setting('test.ms')::uuid, format('{"held_on": "%s", "attendance": "absent"}', current_date - 7)::jsonb);
select public.org_session_log(current_setting('test.ms')::uuid, '{"minutes": 60, "focus": "Smash"}');
select t.throws(format($$select public.org_session_log(%L, '{"attendance": "late"}')$$, current_setting('test.ms')), 'invalid_session');

select set_config('test.smash', (t.q($$select id from app.metric_definitions where key = 'smash_speed' and org_id is null$$) ->> 'id'), false);
select set_config('test.foot', (t.q($$select id from app.metric_definitions where key = 'footwork_drill' and sport_code = 'badminton'$$) ->> 'id'), false);
select public.org_performance_record(current_setting('test.ms')::uuid, jsonb_build_array(
  jsonb_build_object('metric_id', current_setting('test.smash'), 'value', 210),
  jsonb_build_object('metric_id', current_setting('test.foot'), 'value', 19.5)), current_date - 14);
select public.org_performance_record(current_setting('test.ms')::uuid, jsonb_build_array(
  jsonb_build_object('metric_id', current_setting('test.smash'), 'value', 228),
  jsonb_build_object('metric_id', current_setting('test.foot'), 'value', 17.8)));
select public.org_report_publish(current_setting('test.ms')::uuid,
  '{"rating": 7, "summary": "Clear gains in smash speed and court coverage.", "focus_areas": "Backhand clears"}');
select t.throws(format($$select public.org_report_publish(%L, '{"rating": 11, "summary": "Too generous"}')$$, current_setting('test.ms')),
  'invalid_report');

-- The mentee sees the whole journey; nobody else does.
select t.login('mentee@sidi.test');
select set_config('test.j', public.my_journey(current_setting('test.ms')::uuid)::text, false);
select t.eq((current_setting('test.j')::jsonb #>> '{attendance,present}')::int, 2, 'two sessions attended');
select t.eq((current_setting('test.j')::jsonb #>> '{attendance,absent}')::int, 1, 'one missed');
select t.eq(jsonb_array_length(current_setting('test.j')::jsonb -> 'metrics'), 2, 'two metrics tracked');
select t.eq((current_setting('test.j')::jsonb #>> '{metrics,0,first}')::numeric, 210::numeric, 'smash started at 210');
select t.eq((current_setting('test.j')::jsonb #>> '{metrics,0,latest}')::numeric, 228::numeric, 'and is now 228');
select t.eq((current_setting('test.j')::jsonb #>> '{metrics,1,best}')::numeric, 17.8::numeric, 'lower is better for the footwork drill');
select t.eq(current_setting('test.j')::jsonb #>> '{reports,0,coach_name}', 'Coachk', 'the report names its coach');
select t.eq(current_setting('test.j')::jsonb #>> '{membership,coach_name}', 'Coachk', 'the coach is assigned');
select t.ok((select count(*) from jsonb_array_elements(public.notifications_list()) n where n ->> 'kind' = 'report_published') = 1,
  'the mentee is told about the report');

select t.login('other@sidi.test');
select t.throws(format('select public.my_journey(%L)', current_setting('test.ms')), 'membership_not_found', 'journeys are private');
select t.throws(format('select public.org_member_journey(%L)', current_setting('test.ms')), 'forbidden');

-- Active members get their plan's discount on bookings.
select t.login('head@sidi.test');
select set_config('test.court', public.org_resource_save(current_setting('test.org')::uuid, jsonb_build_object(
  'facility_id', public.org_facility_save(current_setting('test.org')::uuid, '{"name": "Academy hall"}') ->> 'id',
  'sport_code', 'badminton', 'name', 'Court A', 'price', 500)) ->> 'id', false);
select t.login('mentee@sidi.test');
select t.eq((public.booking_create(current_setting('test.court')::uuid,
  ((current_date + 2) + time '08:00') at time zone 'Asia/Kolkata') ->> 'price')::numeric, 400::numeric, '20% member discount applied');
select public.membership_cancel(current_setting('test.ms')::uuid);
select t.eq(public.my_memberships() #>> '{0,status}', 'cancelled', 'cancelled by the member');
reset role;
