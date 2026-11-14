-- The API roles can reach the public RPCs and nothing else.
select t.user('ana@sidi.test');

set role anon;
select t.login(null);
select t.ok(jsonb_array_length(public.catalog() -> 'sports') = 4, 'visitors can read the catalogue');
select t.ok(jsonb_typeof(public.orgs_search()) = 'array', 'visitors can browse organisations');
select t.throws('select public.me()', '42501', 'visitors cannot call member RPCs');
select t.throws('select * from app.profiles', '42501', 'visitors cannot read tables');
select t.throws('select private.uid()', '42501', 'visitors cannot call private functions');

set role authenticated;
select t.throws('select public.me()', 'not_authenticated', 'an RPC without a subject is rejected');
select t.login('ana@sidi.test');
select t.eq(public.me() #>> '{profile,display_name}', 'Ana', 'a profile is created with the auth user');
select t.throws('select * from app.profiles', '42501', 'members cannot read tables');
select t.throws('select * from app.v_bookings', '42501', 'members cannot read internal views');
select t.throws('insert into app.platform_roles (user_id, role) values (auth.uid(), ''admin'')', '42501',
  'members cannot make themselves admin');
select t.throws('select private.grant_feature(gen_random_uuid(), ''tournaments'', auth.uid())', '42501',
  'members cannot call private functions');
select t.throws('select private.score_match(''bwf_3x21'', ''{}'', false)', '42501', 'the engine is private');
select t.throws('select public.admin_overview()', 'forbidden', 'the admin console is staff only');
select t.throws('select public.admin_set_role(auth.uid(), ''admin'')', 'forbidden', 'role changes are admin only');

-- Profile edits are validated.
select public.profile_update('{"username": "ana_b", "city": "Kolkata"}');
select t.eq(public.me() #>> '{profile,username}', 'ana_b', 'username saved');
select t.throws($$select public.profile_update('{"username": "No Spaces!"}')$$, 'invalid_profile');
reset role;

-- Every table has RLS on, and no public function is callable by PUBLIC.
select t.eq((select count(*) from pg_tables where schemaname = 'app' and not rowsecurity), 0::bigint,
  'row level security is enabled on every table');
select t.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('public', 'private') and has_function_privilege('public', p.oid, 'execute')), 0::bigint,
  'no function is executable by PUBLIC');
select t.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.prosecdef
               and (p.proconfig is null or not p.proconfig @> array['search_path=""'])), 0::bigint,
  'every RPC pins an empty search_path');
