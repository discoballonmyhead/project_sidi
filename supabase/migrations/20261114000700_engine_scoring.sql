-- =============================================================================
-- 0007 · Scoring engines
--
-- Contract: private.<engine>(config jsonb, score jsonb, final boolean) -> jsonb
--
--   {
--     "complete": true,              -- the score decides the match
--     "outcome":  "win",             -- win | tie | draw | no_result
--     "winner":   "a",               -- a | b | null
--     "summary":  "21-18 19-21 21-15",
--     "margin":   "by 12 runs",      -- optional, human readable
--     "a": {"sets": 2, "score": 61}, -- generic stats the standings engine reads
--     "b": {"sets": 1, "score": 54}
--   }
--
-- `sets` is the first counting unit (games, rubbers), `score` the second
-- (points, runs). Cricket adds nrr_runs / nrr_overs for net run rate.
-- Engines are pure: same input, same output, no table access. With
-- final = false an unfinished score is accepted (live scoring); with
-- final = true an unfinished or impossible score is rejected.
-- =============================================================================

create function private.score_side(p_sets int, p_score int)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('sets', p_sets, 'score', p_score);
$$;

-- -----------------------------------------------------------------------------
-- Rally-point games: badminton and table tennis, singles and doubles.
-- config: {"best_of": 3, "points": 21, "win_by": 2, "cap": 30}
-- score:  {"games": [[21, 18], [19, 21], [21, 15]], "retired": "a" | "b"}
-- -----------------------------------------------------------------------------
create function private.score_rally_games(p_config jsonb, p_score jsonb, p_final boolean)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_best    int := coalesce((p_config ->> 'best_of')::int, 3);
  v_points  int := coalesce((p_config ->> 'points')::int, 21);
  v_win_by  int := coalesce((p_config ->> 'win_by')::int, 2);
  v_cap     int := (p_config ->> 'cap')::int;
  v_need    int := v_best / 2 + 1;
  v_games   jsonb := coalesce(p_score -> 'games', '[]'::jsonb);
  v_retired text := p_score ->> 'retired';
  v_game    jsonb;
  v_x int; v_y int; v_hi int; v_lo int;
  v_i int := 0;
  v_a_sets int := 0; v_b_sets int := 0; v_a_pts int := 0; v_b_pts int := 0;
  v_decided boolean := false;
  v_open    boolean := false;
  v_parts   text[] := '{}';
  v_winner  text;
begin
  if jsonb_typeof(v_games) <> 'array' then
    perform private.fail(422, 'invalid_score', 'Games must be a list of [a, b] scores.');
  end if;

  for v_game in select value from jsonb_array_elements(v_games) loop
    v_i := v_i + 1;
    if v_decided then
      perform private.fail(422, 'invalid_score', format('Game %s was played after the match was decided.', v_i));
    end if;
    if v_open then
      perform private.fail(422, 'invalid_score', format('Game %s is not finished.', v_i - 1));
    end if;
    if jsonb_typeof(v_game) <> 'array' or jsonb_array_length(v_game) <> 2
       or jsonb_typeof(v_game -> 0) <> 'number' or jsonb_typeof(v_game -> 1) <> 'number' then
      perform private.fail(422, 'invalid_score', format('Game %s must be two numbers.', v_i));
    end if;
    v_x := (v_game ->> 0)::int;
    v_y := (v_game ->> 1)::int;
    v_hi := greatest(v_x, v_y);
    v_lo := least(v_x, v_y);
    if v_lo < 0 or (v_cap is not null and v_hi > v_cap) then
      perform private.fail(422, 'invalid_score', format('Game %s: %s-%s is out of range.', v_i, v_x, v_y));
    end if;

    if (v_hi >= v_points and v_hi - v_lo >= v_win_by) or (v_cap is not null and v_hi = v_cap) then
      -- A finished game ends exactly at the target, exactly `win_by` clear
      -- after deuce, or at the cap by a single point.
      if not (v_hi = v_points
              or v_hi - v_lo = v_win_by
              or (v_cap is not null and v_hi = v_cap and v_hi - v_lo between 1 and v_win_by)) then
        perform private.fail(422, 'invalid_score', format('Game %s: %s-%s is not a possible score.', v_i, v_x, v_y));
      end if;
      if v_x > v_y then v_a_sets := v_a_sets + 1; else v_b_sets := v_b_sets + 1; end if;
      v_decided := v_a_sets = v_need or v_b_sets = v_need;
    else
      v_open := true;
    end if;
    v_a_pts := v_a_pts + v_x;
    v_b_pts := v_b_pts + v_y;
    v_parts := v_parts || (v_x || '-' || v_y);
  end loop;

  if v_retired in ('a', 'b') then
    v_winner := case v_retired when 'a' then 'b' else 'a' end;
  elsif v_decided then
    v_winner := case when v_a_sets > v_b_sets then 'a' else 'b' end;
  elsif p_final then
    perform private.fail(422, 'match_not_finished',
      format('A side needs %s games to win this match.', v_need));
  end if;

  return jsonb_build_object(
    'complete', v_winner is not null,
    'outcome', case when v_winner is not null then 'win' end,
    'winner', v_winner,
    'summary', array_to_string(v_parts, ' '),
    'margin', case when v_retired in ('a', 'b') then 'retired' end,
    'a', private.score_side(v_a_sets, v_a_pts),
    'b', private.score_side(v_b_sets, v_b_pts));
end $$;

-- -----------------------------------------------------------------------------
-- Team ties: a fixed order of rubbers, each a rally-games match.
-- Thomas / Uber / Sudirman Cup, ITTF team events, Olympic team format.
-- config: {"rubbers": [{"code": "MS1", "label": "Men's singles 1"}, ...],
--          "win_at": 3, "play_all": false, "rubber": {<rally config>}}
-- score:  {"rubbers": [{"games": [[...]], "retired": null}, ...]}
-- -----------------------------------------------------------------------------
create function private.score_team_tie(p_config jsonb, p_score jsonb, p_final boolean)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_slots    int := jsonb_array_length(coalesce(p_config -> 'rubbers', '[]'::jsonb));
  v_win_at   int := coalesce((p_config ->> 'win_at')::int, v_slots / 2 + 1);
  v_play_all boolean := coalesce((p_config ->> 'play_all')::boolean, false);
  v_rubbers  jsonb := coalesce(p_score -> 'rubbers', '[]'::jsonb);
  v_rubber   jsonb;
  v_res      jsonb;
  v_i int := 0;
  v_a int := 0; v_b int := 0; v_a_games int := 0; v_b_games int := 0;
  v_played int := 0;
  v_decided boolean := false;
  v_open    boolean := false;
  v_lines   jsonb := '[]'::jsonb;
  v_winner  text;
  v_done    boolean;
begin
  if jsonb_typeof(v_rubbers) <> 'array' or jsonb_array_length(v_rubbers) > v_slots then
    perform private.fail(422, 'invalid_score', format('This tie has %s rubbers.', v_slots));
  end if;

  for v_rubber in select value from jsonb_array_elements(v_rubbers) loop
    v_i := v_i + 1;
    if v_decided and not v_play_all then
      perform private.fail(422, 'invalid_score', format('Rubber %s was played after the tie was decided.', v_i));
    end if;
    if v_open then
      perform private.fail(422, 'invalid_score', format('Rubber %s is not finished.', v_i - 1));
    end if;
    v_res := private.score_rally_games(p_config -> 'rubber', v_rubber, false);
    if (v_res ->> 'complete')::boolean then
      v_played := v_played + 1;
      if v_res ->> 'winner' = 'a' then v_a := v_a + 1; else v_b := v_b + 1; end if;
      v_decided := v_a >= v_win_at or v_b >= v_win_at;
    else
      v_open := true;
    end if;
    v_a_games := v_a_games + (v_res #>> '{a,sets}')::int;
    v_b_games := v_b_games + (v_res #>> '{b,sets}')::int;
    v_lines := v_lines || jsonb_build_object(
      'code', p_config -> 'rubbers' -> (v_i - 1) ->> 'code',
      'winner', v_res ->> 'winner',
      'summary', v_res ->> 'summary');
  end loop;

  v_done := (v_decided and (not v_play_all or v_played = v_slots)) or (v_played = v_slots and not v_open);
  if v_done then
    v_winner := case when v_a > v_b then 'a' when v_b > v_a then 'b' end;
  elsif p_final then
    perform private.fail(422, 'match_not_finished',
      format('A team needs %s rubbers to win this tie.', v_win_at));
  end if;

  return jsonb_build_object(
    'complete', v_done,
    'outcome', case when not v_done then null when v_winner is null then 'tie' else 'win' end,
    'winner', v_winner,
    'summary', v_a || '-' || v_b,
    'margin', null,
    'rubbers', v_lines,
    'a', private.score_side(v_a, v_a_games),
    'b', private.score_side(v_b, v_b_games));
end $$;

-- Overs in cricket notation: 113 balls -> "18.5".
create function private.overs_text(p_balls int, p_bpo int)
returns text language sql immutable set search_path = '' as $$
  select (p_balls / p_bpo)::text || case when p_balls % p_bpo > 0 then '.' || (p_balls % p_bpo)::text else '' end;
$$;

-- -----------------------------------------------------------------------------
-- Limited-overs cricket: T20, ODI, T10, The Hundred and any club length.
-- config: {"overs": 20, "balls_per_over": 6, "wickets": 10, "super_over": true}
-- score:  {"innings": [{"side": "a", "runs": 182, "wickets": 6, "balls": 120},
--                      {"side": "b", "runs": 170, "wickets": 9, "balls": 120}],
--          "overs": 15,                              -- match shortened before the start
--          "revised": {"target": 140, "balls": 90},  -- DLS target for the chase
--          "super_over": [{"a": 12, "b": 10}],       -- one entry per Super Over played
--          "no_result": true}
-- Net run rate follows the ICC playing conditions: a side bowled out is
-- charged its full quota of overs, and after a revised target the side
-- batting first is credited with target - 1 off the overs the chase was given.
-- -----------------------------------------------------------------------------
create function private.score_cricket_limited(p_config jsonb, p_score jsonb, p_final boolean)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_bpo     int := coalesce((p_config ->> 'balls_per_over')::int, 6);
  v_wkts    int := coalesce((p_config ->> 'wickets')::int, 10);
  v_quota   int := round(coalesce((p_score ->> 'overs')::numeric, (p_config ->> 'overs')::numeric, 20) * v_bpo)::int;
  v_inn     jsonb := coalesce(p_score -> 'innings', '[]'::jsonb);
  v_n       int;
  v_first   jsonb; v_second jsonb;
  v_f_side  text;  v_s_side text;
  v_f_runs int; v_f_wk int; v_f_balls int;
  v_s_runs int; v_s_wk int; v_s_balls int;
  v_revised boolean := p_score ? 'revised' and jsonb_typeof(p_score -> 'revised') = 'object';
  v_chase_quota int;
  v_target  int;
  v_done    boolean := false;
  v_outcome text; v_winner text; v_margin text; v_summary text;
  v_so      jsonb;
  v_f_stat  jsonb := jsonb_build_object('sets', 0, 'score', 0, 'nrr_runs', 0, 'nrr_overs', 0);
  v_s_stat  jsonb := jsonb_build_object('sets', 0, 'score', 0, 'nrr_runs', 0, 'nrr_overs', 0);
begin
  if jsonb_typeof(v_inn) <> 'array' or jsonb_array_length(v_inn) > 2 then
    perform private.fail(422, 'invalid_score', 'A limited-overs match has at most two innings.');
  end if;
  v_n := jsonb_array_length(v_inn);

  if coalesce((p_score ->> 'no_result')::boolean, false) then
    return jsonb_build_object('complete', true, 'outcome', 'no_result', 'winner', null,
      'summary', 'No result', 'margin', null, 'a', v_f_stat, 'b', v_s_stat);
  end if;

  if v_n >= 1 then
    v_first  := v_inn -> 0;
    v_f_side := v_first ->> 'side';
    v_f_runs := coalesce((v_first ->> 'runs')::int, 0);
    v_f_wk   := coalesce((v_first ->> 'wickets')::int, 0);
    v_f_balls := coalesce((v_first ->> 'balls')::int, 0);
    if v_f_side not in ('a', 'b') or v_f_runs < 0 or v_f_wk not between 0 and v_wkts
       or v_f_balls not between 0 and v_quota then
      perform private.fail(422, 'invalid_score', 'First innings is out of range for this format.');
    end if;
    v_summary := format('%s/%s (%s)', v_f_runs, v_f_wk, private.overs_text(v_f_balls, v_bpo));
  end if;

  if v_n = 2 then
    v_second := v_inn -> 1;
    v_s_side := v_second ->> 'side';
    v_s_runs := coalesce((v_second ->> 'runs')::int, 0);
    v_s_wk   := coalesce((v_second ->> 'wickets')::int, 0);
    v_s_balls := coalesce((v_second ->> 'balls')::int, 0);
    v_chase_quota := case when v_revised then coalesce((p_score #>> '{revised,balls}')::int, v_quota) else v_quota end;
    v_target := case when v_revised then coalesce((p_score #>> '{revised,target}')::int, v_f_runs + 1) else v_f_runs + 1 end;
    if v_s_side not in ('a', 'b') or v_s_side = v_f_side or v_s_runs < 0
       or v_s_wk not between 0 and v_wkts or v_s_balls not between 0 and v_chase_quota then
      perform private.fail(422, 'invalid_score', 'Second innings is out of range for this format.');
    end if;
    v_summary := v_summary || format(' v %s/%s (%s)', v_s_runs, v_s_wk, private.overs_text(v_s_balls, v_bpo));

    v_done := v_s_runs >= v_target or v_s_wk = v_wkts or v_s_balls = v_chase_quota;
    if v_done then
      if v_s_runs >= v_target then
        v_outcome := 'win'; v_winner := v_s_side;
        v_margin := format('by %s wicket%s', v_wkts - v_s_wk, case when v_wkts - v_s_wk = 1 then '' else 's' end);
      elsif v_s_runs = v_target - 1 then
        v_outcome := 'tie';
        v_margin := 'match tied';
        -- A tie can be broken by one or more Super Overs; the last one counts.
        if jsonb_typeof(p_score -> 'super_over') = 'array' and jsonb_array_length(p_score -> 'super_over') > 0 then
          v_so := p_score -> 'super_over' -> -1;
          if (v_so ->> 'a')::int <> (v_so ->> 'b')::int then
            v_outcome := 'win';
            v_winner := case when (v_so ->> 'a')::int > (v_so ->> 'b')::int then 'a' else 'b' end;
            v_margin := 'in the Super Over';
          end if;
        end if;
      else
        v_outcome := 'win'; v_winner := v_f_side;
        v_margin := format('by %s run%s', v_target - 1 - v_s_runs, case when v_target - 1 - v_s_runs = 1 then '' else 's' end);
      end if;
      if v_revised then v_margin := v_margin || ' (DLS)'; end if;

      v_f_stat := jsonb_build_object('sets', 0, 'score', v_f_runs,
        'nrr_runs', case when v_revised then v_target - 1 else v_f_runs end,
        'nrr_overs', round((case when v_revised then v_chase_quota
                                 when v_f_wk = v_wkts then v_quota
                                 else v_f_balls end)::numeric / v_bpo, 4));
      v_s_stat := jsonb_build_object('sets', 0, 'score', v_s_runs,
        'nrr_runs', v_s_runs,
        'nrr_overs', round((case when v_s_wk = v_wkts then v_chase_quota else v_s_balls end)::numeric / v_bpo, 4));
    end if;
  end if;

  if not v_done and p_final then
    perform private.fail(422, 'match_not_finished',
      'The chase is not over. Enter both innings, or mark the match as no result.');
  end if;

  return jsonb_build_object(
    'complete', v_done,
    'outcome', v_outcome,
    'winner', v_winner,
    'summary', coalesce(v_summary, ''),
    'margin', v_margin,
    'batted_first', v_f_side,
    'a', case when v_f_side = 'b' then v_s_stat else v_f_stat end,
    'b', case when v_f_side = 'b' then v_f_stat else v_s_stat end);
end $$;

-- -----------------------------------------------------------------------------
-- Multi-innings cricket: Tests and first-class matches.
-- config: {"wickets": 10}
-- score:  {"innings": [{"side": "a", "runs": 350, "wickets": 10, "declared": false}, ...],
--          "drawn": true}
-- Up to four innings; a side may bat twice in a row (follow-on).
-- -----------------------------------------------------------------------------
create function private.score_cricket_multi(p_config jsonb, p_score jsonb, p_final boolean)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_wkts  int := coalesce((p_config ->> 'wickets')::int, 10);
  v_inn   jsonb := coalesce(p_score -> 'innings', '[]'::jsonb);
  v_n     int;
  v_i     jsonb;
  v_idx   int := 0;
  v_tot_a int := 0; v_tot_b int := 0; v_cnt_a int := 0; v_cnt_b int := 0;
  v_parts_a text[] := '{}'; v_parts_b text[] := '{}';
  v_last  jsonb; v_last_side text; v_last_over boolean;
  v_last_tot int; v_other_tot int;
  v_done  boolean := false;
  v_outcome text; v_winner text; v_margin text;
  v_once  text;
begin
  if jsonb_typeof(v_inn) <> 'array' or jsonb_array_length(v_inn) > 4 then
    perform private.fail(422, 'invalid_score', 'A match has at most four innings.');
  end if;
  v_n := jsonb_array_length(v_inn);

  for v_i in select value from jsonb_array_elements(v_inn) loop
    v_idx := v_idx + 1;
    if v_i ->> 'side' not in ('a', 'b') or coalesce((v_i ->> 'runs')::int, -1) < 0
       or coalesce((v_i ->> 'wickets')::int, -1) not between 0 and v_wkts then
      perform private.fail(422, 'invalid_score', format('Innings %s is out of range.', v_idx));
    end if;
    if v_i ->> 'side' = 'a' then
      v_tot_a := v_tot_a + (v_i ->> 'runs')::int; v_cnt_a := v_cnt_a + 1;
      v_parts_a := v_parts_a || ((v_i ->> 'runs') || case when (v_i ->> 'wickets')::int < v_wkts
        then '/' || (v_i ->> 'wickets') || case when coalesce((v_i ->> 'declared')::boolean, false) then 'd' else '' end
        else '' end);
    else
      v_tot_b := v_tot_b + (v_i ->> 'runs')::int; v_cnt_b := v_cnt_b + 1;
      v_parts_b := v_parts_b || ((v_i ->> 'runs') || case when (v_i ->> 'wickets')::int < v_wkts
        then '/' || (v_i ->> 'wickets') || case when coalesce((v_i ->> 'declared')::boolean, false) then 'd' else '' end
        else '' end);
    end if;
  end loop;
  if v_cnt_a > 2 or v_cnt_b > 2 then
    perform private.fail(422, 'invalid_score', 'A side bats at most twice.');
  end if;

  if coalesce((p_score ->> 'drawn')::boolean, false) then
    v_done := true; v_outcome := 'draw'; v_margin := 'match drawn';
  elsif v_n >= 3 then
    v_last := v_inn -> (v_n - 1);
    v_last_side := v_last ->> 'side';
    v_last_over := (v_last ->> 'wickets')::int = v_wkts;
    v_last_tot  := case v_last_side when 'a' then v_tot_a else v_tot_b end;
    v_other_tot := case v_last_side when 'a' then v_tot_b else v_tot_a end;

    if v_n = 4 then
      if v_last_tot > v_other_tot then
        v_done := true; v_outcome := 'win'; v_winner := v_last_side;
        v_margin := format('by %s wicket%s', v_wkts - (v_last ->> 'wickets')::int,
                           case when v_wkts - (v_last ->> 'wickets')::int = 1 then '' else 's' end);
      elsif v_last_over then
        v_done := true;
        if v_last_tot = v_other_tot then
          v_outcome := 'tie'; v_margin := 'match tied';
        else
          v_outcome := 'win'; v_winner := case v_last_side when 'a' then 'b' else 'a' end;
          v_margin := format('by %s run%s', v_other_tot - v_last_tot,
                             case when v_other_tot - v_last_tot = 1 then '' else 's' end);
        end if;
      end if;
    else
      -- Three innings: an innings victory when the side that has batted twice
      -- is all out still behind the side that batted once.
      v_once := case when v_cnt_a = 1 then 'a' else 'b' end;
      if v_last_side <> v_once and v_last_over and v_last_tot < v_other_tot then
        v_done := true; v_outcome := 'win'; v_winner := v_once;
        v_margin := format('by an innings and %s run%s', v_other_tot - v_last_tot,
                           case when v_other_tot - v_last_tot = 1 then '' else 's' end);
      end if;
    end if;
  end if;

  if not v_done and p_final then
    perform private.fail(422, 'match_not_finished',
      'The match is not decided. Enter the remaining innings or mark it as drawn.');
  end if;

  return jsonb_build_object(
    'complete', v_done,
    'outcome', v_outcome,
    'winner', v_winner,
    'summary', array_to_string(v_parts_a, ' & ') || ' v ' || array_to_string(v_parts_b, ' & '),
    'margin', v_margin,
    'a', private.score_side(0, v_tot_a),
    'b', private.score_side(0, v_tot_b));
end $$;

-- -----------------------------------------------------------------------------
-- Dispatcher: ruleset -> scoring engine. The function name comes from the
-- app.scoring_engines registry, which only migrations can write.
-- -----------------------------------------------------------------------------
create function private.score_match(p_ruleset_key text, p_score jsonb, p_final boolean)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_fn     text;
  v_config jsonb;
  v_result jsonb;
begin
  select e.fn, r.config into v_fn, v_config
  from app.rulesets r
  join app.scoring_engines e on e.kind = r.scoring_kind
  where r.key = p_ruleset_key;
  if v_fn is null then
    perform private.fail(404, 'ruleset_not_found', 'Unknown ruleset.');
  end if;
  execute format('select private.%I($1, $2, $3)', v_fn)
    into v_result using v_config, coalesce(p_score, '{}'::jsonb), p_final;
  return v_result;
end $$;
