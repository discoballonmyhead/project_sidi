-- The competition engine, exercised only through the public API: every stage
-- format, multi-stage pipelines, byes, corrections and each scoring engine.
select t.user('host@sidi.test'), t.user('fan@sidi.test');
set role authenticated;
select set_config('test.org', t.org('host@sidi.test', 'Tournament House', array['tournaments', 'paid_entries'])::text, false);

-- ---------------------------------------------------------------------------
-- Round robin: 5 players, 10 matches, the table follows the seeds
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'badminton', 'bwf_3x21',
  '[{"name": "League", "format": "round_robin", "config": {}}]', 5)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 10, 'C(5,2) matches');
select t.eq((t.q(format('select count(distinct round_no) n from app.matches where event_id = %L', current_setting('test.e'))) ->> 'n')::int,
  5, 'five rounds, one side resting in each');
select t.eq(t.play_out(current_setting('test.e')::uuid), 10, 'all played');
select t.eq(t.rank_of(current_setting('test.e')::uuid, 1), 1, 'seed 1 wins the league');
select t.eq(t.rank_of(current_setting('test.e')::uuid, 5), 5, 'seed 5 is last');
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{event,status}', 'completed', 'event completed');
select t.eq((public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,standings,0,won}')::int, 4, 'leader won 4');
select t.eq((public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,standings,0,sets_for}')::int, 8, 'and 8 games');

-- ---------------------------------------------------------------------------
-- Knockout with byes: 6 entrants in a draw of 8, bronze match
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'table_tennis', 'ittf_bo5',
  '[{"name": "Draw", "format": "single_elimination", "config": {"third_place": true}}]', 6)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 8, '4 + 2 + 1 + bronze');
select t.eq((t.q(format($$select count(*) n from app.matches where event_id = %L and status = 'bye'$$, current_setting('test.e'))) ->> 'n')::int,
  2, 'seeds 1 and 2 get byes');
select t.eq((t.q(format($$select count(*) n from app.matches where event_id = %L and status = 'ready'$$, current_setting('test.e'))) ->> 'n')::int,
  2, 'only 3v6 and 4v5 are playable');
select t.eq(t.q(format($$select a.seed sa, b.seed sb from app.matches m join app.entrants a on a.id = m.side_a
  left join app.entrants b on b.id = m.side_b where m.event_id = %L and m.round_no = 2 and m.match_no = 1$$, current_setting('test.e'))) ->> 'sa',
  '1', 'seed 1 was moved into the semi-final');
select t.eq(t.play_out(current_setting('test.e')::uuid), 6, '2 quarters, 2 semis, final, bronze');
select t.eq(array[t.rank_of(current_setting('test.e')::uuid, 1), t.rank_of(current_setting('test.e')::uuid, 2),
                  t.rank_of(current_setting('test.e')::uuid, 3), t.rank_of(current_setting('test.e')::uuid, 4)],
            array[1, 2, 3, 4], 'gold, silver, bronze, fourth');

-- ---------------------------------------------------------------------------
-- Corrections: a result can be reopened until the next match is played
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'badminton', 'bwf_3x21',
  '[{"name": "Draw", "format": "single_elimination", "config": {}}]', 4)::text, false);
select public.org_event_start(current_setting('test.e')::uuid);
select set_config('test.m', t.q(format('select id from app.matches where event_id = %L and round_no = 1 and match_no = 1',
  current_setting('test.e'))) ->> 'id', false);
select t.throws(format($$select public.org_match_score(%L, '{"games": [[21, 19]]}', true)$$, current_setting('test.m')), 'match_not_finished');
select t.throws(format($$select public.org_match_score(%L, '{"games": [[21, 20], [21, 3]]}', true)$$, current_setting('test.m')), 'invalid_score');
select t.eq(public.org_match_score(current_setting('test.m')::uuid, '{"games": [[21, 19], [11, 7]]}') ->> 'status', 'live', 'live scoring');
select t.eq(public.org_match_score(current_setting('test.m')::uuid, '{"games": [[21, 19], [18, 21], [30, 29]]}', true) ->> 'status',
  'completed', 'final score accepted');
select t.throws(format($$select public.org_match_score(%L, '{"games": [[21, 0], [21, 0]]}', true)$$, current_setting('test.m')), 'match_already_final');
select t.ok((t.q(format('select side_a from app.matches where event_id = %L and round_no = 2', current_setting('test.e'))) ->> 'side_a') is not null,
  'the winner moved into the final');
select public.org_match_reopen(current_setting('test.m')::uuid);
select t.ok((t.q(format('select side_a from app.matches where event_id = %L and round_no = 2', current_setting('test.e'))) ->> 'side_a') is null,
  'reopening pulls the winner back out');
select public.org_match_walkover(current_setting('test.m')::uuid, 'b');
select t.eq(t.play_out(current_setting('test.e')::uuid), 2, 'the rest is played');
select t.eq(t.rank_of(current_setting('test.e')::uuid, 4), 2, 'the walkover winner (seed 4) reached the final');
select t.throws(format('select public.org_match_reopen(%L)', current_setting('test.m')), 'stage_closed');

-- Only the host can score.
select t.login('fan@sidi.test');
select t.throws(format($$select public.org_match_score(%L, '{}')$$, current_setting('test.m')), 'forbidden');
select t.throws(format('select public.org_event_reset(%L)', current_setting('test.e')), 'forbidden');
select t.login('host@sidi.test');

-- ---------------------------------------------------------------------------
-- Double elimination: 6 entrants, with and without a grand-final reset
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'badminton', 'bwf_3x15',
  '[{"name": "Double KO", "format": "double_elimination", "config": {"grand_final_reset": true}}]', 6)::text, false);
select public.org_event_start(current_setting('test.e')::uuid);
select t.eq((t.q(format($$select count(*) n from app.matches where event_id = %L and bracket = 'losers'$$, current_setting('test.e'))) ->> 'n')::int,
  6, 'losers bracket of an 8-draw has 2+2+1+1 matches');
select t.play_out(current_setting('test.e')::uuid);
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{event,status}', 'completed', 'double elimination completes');
select t.eq(array[t.rank_of(current_setting('test.e')::uuid, 1), t.rank_of(current_setting('test.e')::uuid, 2), t.rank_of(current_setting('test.e')::uuid, 3)],
  array[1, 2, 3], 'seeds 1-2-3 on the podium');
select t.eq(t.q(format($$select status from app.matches where event_id = %L and bracket = 'grand_final' and round_no = 2$$,
  current_setting('test.e'))) ->> 'status', 'cancelled', 'no reset when the winners-bracket champion wins');
select t.eq((t.q(format($$select count(*) n from app.matches where event_id = %L and status in ('pending', 'ready', 'live')$$,
  current_setting('test.e'))) ->> 'n')::int, 0, 'nothing left hanging');

-- The losers-bracket champion wins the first grand final: the reset is played.
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'badminton', 'bwf_3x21',
  '[{"name": "Double KO", "format": "double_elimination", "config": {"grand_final_reset": true}}]', 4)::text, false);
select public.org_event_start(current_setting('test.e')::uuid);
select t.play_out(current_setting('test.e')::uuid, true);
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{event,status}', 'completed', 'reset final played out');
select t.eq(t.q(format($$select status from app.matches where event_id = %L and bracket = 'grand_final' and round_no = 2$$,
  current_setting('test.e'))) ->> 'status', 'completed', 'the reset match was played');

-- ---------------------------------------------------------------------------
-- Swiss: 7 players, 3 rounds, one bye a round, no rematches
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'table_tennis', 'ittf_bo3',
  '[{"name": "Swiss", "format": "swiss", "config": {"rounds": 3}}]', 7)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 4, 'round one: 3 matches and a bye');
select t.eq(t.play_out(current_setting('test.e')::uuid), 9, '3 rounds x 3 matches, paired round by round');
select t.eq((t.q(format($$select count(*) n from app.matches where event_id = %L and status = 'bye'$$, current_setting('test.e'))) ->> 'n')::int,
  3, 'one bye per round');
select t.eq((t.q(format($$select count(distinct side_a) n from app.matches where event_id = %L and status = 'bye'$$, current_setting('test.e'))) ->> 'n')::int,
  3, 'nobody gets two byes');
select t.eq((t.q(format($$select count(*) n from (select least(side_a, side_b), greatest(side_a, side_b) from app.matches
  where event_id = %L and side_b is not null group by 1, 2 having count(*) > 1) d$$, current_setting('test.e'))) ->> 'n')::int, 0, 'no rematches');
select t.eq(t.rank_of(current_setting('test.e')::uuid, 1), 1, 'the unbeaten top seed wins');

-- ---------------------------------------------------------------------------
-- Two stages: BWF World Tour Finals (2 groups of 4 -> semi-finals -> final)
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'badminton', 'bwf_3x21',
  (t.q($$select stages from app.format_templates where key = 'bwf_tour_finals'$$) -> 'stages'), 8)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 12, 'two groups of four: 6 matches each');
select t.eq(t.q(format($$select string_agg(e.seed::text, ',' order by e.seed) seeds from app.stage_entrants se
  join app.entrants e on e.id = se.entrant_id join app.stage_groups g on g.id = se.group_id
  where e.event_id = %L and g.seq = 1$$, current_setting('test.e'))) ->> 'seeds', '1,4,5,8', 'snake seeding into group A');
select t.eq(t.play_out(current_setting('test.e')::uuid), 15, '12 group matches, 2 semis, the final');
-- Group A: 1,4,5,8 -> A1 = seed 1, A2 = seed 4. Group B: 2,3,6,7 -> B1 = 2, B2 = 3.
select t.eq(t.q(format($$select a.seed || 'v' || b.seed as pairing from app.matches m
  join app.event_stages s on s.id = m.stage_id and s.seq = 2
  join app.entrants a on a.id = m.side_a join app.entrants b on b.id = m.side_b
  where m.event_id = %L and m.round_no = 1 and m.match_no = 1$$, current_setting('test.e'))) ->> 'pairing', '1v3', 'A1 meets B2');
select t.eq(t.q(format($$select least(a.seed, b.seed) || 'v' || greatest(a.seed, b.seed) as pairing from app.matches m
  join app.event_stages s on s.id = m.stage_id and s.seq = 2
  join app.entrants a on a.id = m.side_a join app.entrants b on b.id = m.side_b
  where m.event_id = %L and m.round_no = 1 and m.match_no = 2$$, current_setting('test.e'))) ->> 'pairing', '2v4', 'B1 meets A2');
select t.eq(array[t.rank_of(current_setting('test.e')::uuid, 1), t.rank_of(current_setting('test.e')::uuid, 2)], array[1, 2], 'final placings');
select t.ok(t.rank_of(current_setting('test.e')::uuid, 8) is null, 'sides knocked out in the groups have no final placing');

-- ---------------------------------------------------------------------------
-- Three stages: ICC T20 World Cup (4 groups -> Super 8 -> knockout), 12 teams
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'cricket', 'icc_t20',
  (t.q($$select stages from app.format_templates where key = 'icc_t20_world_cup'$$) -> 'stages'), 12)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 12, '4 groups of 3');
select t.eq(t.play_out(current_setting('test.e')::uuid), 12 + 12 + 3, 'groups, Super 8 (2 groups of 4), semis and final');
select t.eq((t.q(format($$select count(*) n from app.stage_entrants se join app.event_stages s on s.id = se.stage_id
  where s.event_id = %L and s.seq = 2$$, current_setting('test.e'))) ->> 'n')::int, 8, 'eight sides reach the Super 8');
select t.eq(t.rank_of(current_setting('test.e')::uuid, 1), 1, 'top seed lifts the cup');
select t.eq(jsonb_array_length(public.event_detail(current_setting('test.e')::uuid) -> 'stages'), 3, 'three stages');
select t.ok((public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,standings,0,nrr}')::numeric > 0, 'group winners carry a positive net run rate');

-- ---------------------------------------------------------------------------
-- League + page playoff (IPL style), 5 teams home and away
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'cricket', 'icc_t20',
  (t.q($$select stages from app.format_templates where key = 't20_league_playoffs'$$) -> 'stages'), 5)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 20, 'double round robin of five');
select t.eq(t.play_out(current_setting('test.e')::uuid), 24, 'league plus Qualifier 1, Eliminator, Qualifier 2 and the final');
select t.eq(array[t.rank_of(current_setting('test.e')::uuid, 1), t.rank_of(current_setting('test.e')::uuid, 2),
                  t.rank_of(current_setting('test.e')::uuid, 3), t.rank_of(current_setting('test.e')::uuid, 4)],
            array[1, 2, 3, 4], 'page playoff placings');

-- ---------------------------------------------------------------------------
-- Cricket tables: points, ties, no-results and net run rate
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'cricket', 'icc_t20',
  '[{"name": "League", "format": "round_robin", "config": {}}]', 3)::text, false);
select public.org_event_start(current_setting('test.e')::uuid);
-- Label the three matches by their seeds so the scores below are unambiguous.
reset role;
create temp table cm as
select m.id, a.seed sa, b.seed sb
from app.matches m join app.entrants a on a.id = m.side_a join app.entrants b on b.id = m.side_b
where m.event_id = current_setting('test.e')::uuid;
grant select on cm to authenticated;
set role authenticated;
-- 1 v 2: seed 1 makes 200/4 in 20 overs, seed 2 is all out for 100 in 15 overs (charged the full 20).
select public.org_match_score(id, jsonb_build_object('innings', jsonb_build_array(
  jsonb_build_object('side', case when sa = 1 then 'a' else 'b' end, 'runs', 200, 'wickets', 4, 'balls', 120),
  jsonb_build_object('side', case when sa = 1 then 'b' else 'a' end, 'runs', 100, 'wickets', 10, 'balls', 90))), true)
from cm where least(sa, sb) = 1 and greatest(sa, sb) = 2;
-- 1 v 3: washed out.
select public.org_match_score(id, '{"no_result": true}', true) from cm where least(sa, sb) = 1 and greatest(sa, sb) = 3;
-- 2 v 3: a tie, with no Super Over played.
select public.org_match_score(id, jsonb_build_object('innings', jsonb_build_array(
  jsonb_build_object('side', 'a', 'runs', 150, 'wickets', 7, 'balls', 120),
  jsonb_build_object('side', 'b', 'runs', 150, 'wickets', 9, 'balls', 120))), true)
from cm where least(sa, sb) = 2 and greatest(sa, sb) = 3;
select set_config('test.s', (public.event_detail(current_setting('test.e')::uuid) #> '{stages,0,standings}')::text, false);
select t.eq(current_setting('test.s')::jsonb #>> '{0,name}', 'Seed 1', 'seed 1 tops the table');
select t.eq((current_setting('test.s')::jsonb #>> '{0,points}')::numeric, 3::numeric, 'win (2) + no result (1)');
select t.eq((current_setting('test.s')::jsonb #>> '{0,nrr}')::numeric, 5.000::numeric, '200/20 - 100/20 = +5.000');
select t.eq(current_setting('test.s')::jsonb #>> '{1,name}', 'Seed 3', 'seed 3 second: tie (1) + no result (1), NRR 0');
select t.eq((current_setting('test.s')::jsonb #>> '{2,points}')::numeric, 1::numeric, 'seed 2: one point from the tie');
select t.eq((current_setting('test.s')::jsonb #>> '{2,nrr}')::numeric, -2.500::numeric, '(100+150)/40 - (200+150)/40 = -2.500');

-- Knockouts refuse a result without a winner.
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'cricket', 'icc_odi',
  '[{"name": "Final", "format": "single_elimination", "config": {}}]', 2)::text, false);
select public.org_event_start(current_setting('test.e')::uuid);
select set_config('test.m', t.q(format('select id from app.matches where event_id = %L', current_setting('test.e'))) ->> 'id', false);
select t.throws(format($$select public.org_match_score(%L, '{"innings": [{"side": "a", "runs": 250, "wickets": 8, "balls": 300},
  {"side": "b", "runs": 250, "wickets": 10, "balls": 298}]}', true)$$, current_setting('test.m')), 'winner_required');
select t.eq(public.org_match_score(current_setting('test.m')::uuid, '{"innings": [{"side": "a", "runs": 250, "wickets": 8, "balls": 300},
  {"side": "b", "runs": 250, "wickets": 10, "balls": 298}], "super_over": [{"a": 15, "b": 15}, {"a": 9, "b": 14}]}', true) #>> '{result,margin}',
  'in the Super Over', 'the second Super Over decides it');

-- ---------------------------------------------------------------------------
-- Team ties and Test series
-- ---------------------------------------------------------------------------
select set_config('test.e', t.event(current_setting('test.org')::uuid, 'badminton', 'bwf_sudirman',
  '[{"name": "Tie", "format": "single_elimination", "config": {}}]', 2)::text, false);
select public.org_event_start(current_setting('test.e')::uuid);
select t.eq(public.org_match_score((t.q(format('select id from app.matches where event_id = %L', current_setting('test.e'))) ->> 'id')::uuid,
  '{"rubbers": [{"games": [[21, 15], [21, 18]]}, {"games": [[17, 21], [21, 19], [19, 21]]},
                {"games": [[21, 9], [21, 11]]}, {"games": [[22, 20], [21, 16]]}]}', true) #>> '{result,summary}', '3-1', 'Sudirman Cup tie 3-1');

select set_config('test.e', t.event(current_setting('test.org')::uuid, 'cricket', 'icc_test',
  '[{"name": "Series", "format": "series", "config": {"matches": 3}}]', 2)::text, false);
select t.eq((public.org_event_start(current_setting('test.e')::uuid) ->> 'matches')::int, 3, 'a three-Test series');
select public.org_match_score((x ->> 'id')::uuid, case (x ->> 'round_no')::int
    when 1 then '{"innings": [{"side": "a", "runs": 480, "wickets": 7, "declared": true}, {"side": "b", "runs": 210, "wickets": 10},
                              {"side": "b", "runs": 190, "wickets": 10}]}'::jsonb
    when 2 then '{"innings": [{"side": "a", "runs": 300, "wickets": 10}, {"side": "b", "runs": 320, "wickets": 10},
                              {"side": "a", "runs": 250, "wickets": 9, "declared": true}, {"side": "b", "runs": 180, "wickets": 6}], "drawn": true}'::jsonb
    else '{"innings": [{"side": "a", "runs": 220, "wickets": 10}, {"side": "b", "runs": 260, "wickets": 10},
                       {"side": "a", "runs": 180, "wickets": 10}, {"side": "b", "runs": 141, "wickets": 8}]}'::jsonb end, true)
from jsonb_array_elements(public.event_detail(current_setting('test.e')::uuid) #> '{stages,0,matches}') x;
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,matches,0,result,margin}', 'by an innings and 80 runs', 'innings victory');
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,matches,2,result,margin}', 'by 2 wickets', 'fourth-innings chase');
select t.eq((public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,standings,0,points}')::numeric, 16::numeric, 'WTC points: 12 for a win + 4 for a draw');

-- ---------------------------------------------------------------------------
-- Entries: registration, entry fee, acceptance, scheduling on courts
-- ---------------------------------------------------------------------------
select set_config('test.t', public.org_tournament_save(current_setting('test.org')::uuid, format(
  '{"name": "Winter Open", "sport_code": "badminton", "starts_on": "%s"}', current_date + 20)::jsonb) ->> 'id', false);
select set_config('test.e', public.org_event_save(current_setting('test.t')::uuid,
  '{"name": "Men''s singles", "ruleset_key": "bwf_3x21", "template_key": "knockout", "entry_fee": 300, "max_entrants": 2}') ->> 'id', false);
select t.throws(format($$select public.org_event_save(%L, '{"name": "TT", "ruleset_key": "ittf_bo5", "template_key": "knockout"}')$$,
  current_setting('test.t')), 'invalid_ruleset', 'a table tennis ruleset does not fit a badminton tournament');

select t.login('fan@sidi.test');
select t.throws(format('select public.tournament_detail(%L)', current_setting('test.t')), 'tournament_not_found', 'drafts are private');
select t.login('host@sidi.test');
select public.org_tournament_set_status(current_setting('test.t')::uuid, 'open');

select t.login('fan@sidi.test');
select t.eq(jsonb_array_length(public.tournaments_search('Winter')), 1, 'published tournaments are listed');
select set_config('test.en', public.event_register(current_setting('test.e')::uuid) ->> 'id', false);
select t.throws(format('select public.event_register(%L)', current_setting('test.e')), 'already_entered');
select t.eq(public.tournament_detail(current_setting('test.t')::uuid) #>> '{events,0,my_entry,payment,status}', 'pending', 'the entry fee is due');
select t.login('p1@sidi.test');
select public.event_register(current_setting('test.e')::uuid);
select t.login('p2@sidi.test');
select t.eq(public.event_register(current_setting('test.e')::uuid) ->> 'status', 'waitlisted', 'the third entry is wait-listed');

select t.login('host@sidi.test');
select t.eq(jsonb_array_length(public.org_event_entrants(current_setting('test.e')::uuid)), 3, 'three entries to review');
select public.org_entrant_decide((x ->> 'id')::uuid, 'accepted')
from jsonb_array_elements(public.org_event_entrants(current_setting('test.e')::uuid)) x where x ->> 'status' = 'pending';
select t.throws(format($$select public.org_entrant_decide(%L, 'accepted')$$,
  (select x ->> 'id' from jsonb_array_elements(public.org_event_entrants(current_setting('test.e')::uuid)) x where x ->> 'status' = 'waitlisted')),
  'event_full');
select public.org_payment_settle((public.org_event_entrants(current_setting('test.e')::uuid) #>> '{0,payment,id}')::uuid, 'paid', 'upi');
select t.eq((public.org_overview(current_setting('test.org')::uuid) #>> '{stats,month_income}')::numeric, 300::numeric, 'entry fee booked as income');

select public.org_event_start(current_setting('test.e')::uuid);
select t.eq(public.tournament_detail(current_setting('test.t')::uuid) #>> '{tournament,status}', 'live', 'the tournament goes live with its first draw');
select t.login('fan@sidi.test');
select t.throws(format('select public.entry_withdraw(%L)', current_setting('test.en')), 'event_already_started');

-- Scheduling books the court, so customers cannot take it.
select t.login('host@sidi.test');
select set_config('test.court', public.org_resource_save(current_setting('test.org')::uuid, jsonb_build_object(
  'facility_id', public.org_facility_save(current_setting('test.org')::uuid, '{"name": "Arena"}') ->> 'id',
  'sport_code', 'badminton', 'name', 'Show court', 'price', 500)) ->> 'id', false);
select t.eq(public.org_stage_auto_schedule((public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,id}')::uuid,
  array[current_setting('test.court')::uuid], (current_date + 20) + time '10:00', 45, 5), 1, 'one match scheduled');
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,matches,0,scheduled_local}',
  to_char((current_date + 20) + time '10:00', 'YYYY-MM-DD"T"HH24:MI:SS'), '10:00 at the venue');
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{stages,0,matches,0,resource_name}', 'Show court', 'on the show court');
select t.login('fan@sidi.test');
select t.throws(format('select public.booking_create(%L, %L)', current_setting('test.court'),
  (((current_date + 20) + time '10:00') at time zone 'Asia/Kolkata')::text), 'slot_taken', 'the court is held for the match');

-- Posters: drafts stay private, published ones are public.
select t.login('host@sidi.test');
select public.org_poster_save(current_setting('test.t')::uuid, '{"kind": "promotion", "title": "Winter Open", "payload": {"headline": "Enter now"}}');
select public.org_poster_save(current_setting('test.t')::uuid, '{"kind": "winner", "title": "Champions", "is_published": true}');
select t.eq(jsonb_array_length(public.tournament_detail(current_setting('test.t')::uuid) -> 'posters'), 2, 'the host sees both posters');
select t.login('fan@sidi.test');
select t.eq(jsonb_array_length(public.tournament_detail(current_setting('test.t')::uuid) -> 'posters'), 1, 'the public sees the published one');

-- Resetting an event returns it to setup and frees the courts.
select t.login('host@sidi.test');
select public.org_event_reset(current_setting('test.e')::uuid);
select t.eq(public.event_detail(current_setting('test.e')::uuid) #>> '{event,status}', 'setup', 'back in setup');
select t.eq((t.q(format($$select count(*) n from app.bookings where resource_id = %L$$, current_setting('test.court'))) ->> 'n')::int, 0, 'court freed');
reset role;
