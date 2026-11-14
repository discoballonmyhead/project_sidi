-- Organisation lifecycle and the moderation queue.
select t.user('owner@sidi.test'), t.user('admin@sidi.test'), t.user('mod@sidi.test'), t.user('coach@sidi.test');
insert into app.platform_roles (user_id, role) values (t.user('admin@sidi.test'), 'admin') on conflict do nothing;
insert into app.platform_roles (user_id, role) values (t.user('mod@sidi.test'), 'moderator') on conflict do nothing;
set role authenticated;

select t.login('owner@sidi.test');
select t.throws($$select public.org_create('{"name": "X", "sports": ["badminton"]}')$$, 'invalid_name');
select t.throws($$select public.org_create('{"name": "Smash Arena", "sports": ["chess"]}')$$, 'invalid_sports');
select public.org_create('{"name": "Smash Arena", "sports": ["badminton", "gym"], "city": "Kolkata", "message": "Four courts in Salt Lake"}');
select set_config('test.org', (t.q($$select id from app.organizations where name = 'Smash Arena'$$) ->> 'id'), false);

-- A pending organisation cannot operate, and is hidden from everyone else.
select t.eq(public.org_overview(current_setting('test.org')::uuid) #>> '{organization,status}', 'pending', 'owner sees the pending org');
select t.throws(format($$select public.org_facility_save(%L, '{"name": "Main hall"}')$$, current_setting('test.org')), 'org_not_approved');
select t.login('coach@sidi.test');
select t.throws(format('select public.org_detail(%L)', current_setting('test.org')), 'org_not_found', 'pending orgs are not public');
select t.eq(jsonb_array_length(public.orgs_search('Smash')), 0, 'pending orgs are not searchable');
select t.throws(format('select public.org_overview(%L)', current_setting('test.org')), 'forbidden', 'strangers cannot manage');

-- A moderator approves it; the default features arrive with approval.
select t.login('mod@sidi.test');
select t.eq((public.admin_overview() #>> '{pending,org_approval}')::int, 1, 'the request is in the queue');
select t.throws(format('select public.admin_request_decide(%L, false)',
  t.q($$select id from app.requests where kind = 'org_approval' and status = 'pending'$$) ->> 'id'), 'note_required');
select public.admin_request_decide((t.q($$select id from app.requests where kind = 'org_approval' and status = 'pending'$$) ->> 'id')::uuid, true, 'Welcome');
select t.throws(format('select public.admin_request_decide(%L, true)',
  t.q($$select id from app.requests where kind = 'org_approval'$$) ->> 'id'), 'request_already_decided');

select t.login('owner@sidi.test');
select t.eq(public.org_overview(current_setting('test.org')::uuid) #>> '{organization,status}', 'approved', 'approved');
select t.ok(public.org_overview(current_setting('test.org')::uuid) -> 'features' ? 'bookings', 'bookings granted on approval');
select t.ok(not public.org_overview(current_setting('test.org')::uuid) -> 'features' ? 'tournaments', 'tournament hosting is not automatic');
select t.eq(jsonb_array_length(public.orgs_search('Smash')), 1, 'approved orgs are searchable');
select t.ok((select count(*) from jsonb_array_elements(public.notifications_list()) n where n ->> 'kind' = 'request_decided') = 1,
  'the owner is told about the decision');

-- Feature access: hosting needs a request, paid entries need verification first.
select t.throws(format($$select public.org_tournament_save(%L, '{"name": "Open", "sport_code": "badminton", "starts_on": "2027-01-10"}')$$,
  current_setting('test.org')), 'feature_not_enabled');
select public.org_request_feature(current_setting('test.org')::uuid, 'tournaments', 'We run a monthly open');
select t.throws(format($$select public.org_request_feature(%L, 'tournaments')$$, current_setting('test.org')), 'request_pending');
select t.throws(format($$select public.org_request_feature(%L, 'paid_entries')$$, current_setting('test.org')), 'verification_required');
select t.throws(format($$select public.org_request_verification(%L, 'pls')$$, current_setting('test.org')), 'invalid_request');
select public.org_request_verification(current_setting('test.org')::uuid, 'Registered society WB/2019/1234, smasharena.example', '["https://example.com/reg.pdf"]');

select t.login('mod@sidi.test');
select t.eq(jsonb_array_length(public.admin_requests('pending')), 2, 'two requests wait for review');
select public.admin_request_decide(r.id, true, null)
from (select (x ->> 'id')::uuid as id from jsonb_array_elements(public.admin_requests('pending')) x) r;
select t.throws(format($$select public.admin_org_set_feature(%L, 'paid_entries', true)$$, current_setting('test.org')),
  'forbidden', 'moderators cannot grant features directly');

select t.login('owner@sidi.test');
select t.ok((public.org_access(current_setting('test.org')::uuid) ->> 'is_verified')::boolean, 'verified');
select t.ok(public.me() #> '{organizations,0,features}' ? 'tournaments', 'tournament hosting granted');
select public.org_request_feature(current_setting('test.org')::uuid, 'paid_entries', null);
select t.login('admin@sidi.test');
select public.admin_request_decide((x ->> 'id')::uuid, true) from jsonb_array_elements(public.admin_requests('pending')) x;

-- Team access.
select t.login('owner@sidi.test');
select public.profile_update('{"username": "owner1"}');
select public.org_team_set(current_setting('test.org')::uuid, 'coach@sidi.test', 'coach');
select t.throws(format($$select public.org_team_set(%L, 'nobody@sidi.test', 'staff')$$, current_setting('test.org')), 'user_not_found');
select t.throws(format($$select public.org_team_set(%L, '@owner1', 'staff')$$, current_setting('test.org')), 'owner_fixed');
select t.eq(jsonb_array_length(public.org_team(current_setting('test.org')::uuid)), 2, 'two people on the team');
select t.login('coach@sidi.test');
select t.throws(format($$select public.org_update(%L, '{"name": "Hijacked"}')$$, current_setting('test.org')), 'forbidden', 'coaches cannot edit the org');
select t.throws(format('select public.org_budget_dashboard(%L, current_date - 30, current_date)', current_setting('test.org')),
  'forbidden', 'coaches cannot see finance');

-- Suspension switches the organisation off; reports reach the queue.
select public.report_content('organization', current_setting('test.org')::uuid, 'Charges for courts that do not exist');
select t.login('mod@sidi.test');
select t.eq(jsonb_array_length(public.admin_reports()), 1, 'report queued');
select public.admin_org_moderate(current_setting('test.org')::uuid, 'suspend', 'Under review');
select public.admin_report_resolve((public.admin_reports() #>> '{0,id}')::uuid, 'actioned', 'Suspended');
select t.login('owner@sidi.test');
select t.throws(format($$select public.org_facility_save(%L, '{"name": "Main hall"}')$$, current_setting('test.org')), 'org_not_approved');
select t.login('admin@sidi.test');
select public.admin_org_moderate(current_setting('test.org')::uuid, 'reinstate');
select t.ok(jsonb_array_length(public.admin_audit()) >= 6, 'moderation is audited');
select t.throws('select public.admin_set_role(auth.uid(), null)', 'own_role');
reset role;
