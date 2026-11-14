-- =============================================================================
-- 0008 · Pairing, standings, ranking and stage progression
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Building blocks
-- -----------------------------------------------------------------------------

-- Seed positions of a 2^n draw, so that seed 1 meets seed 2 only in the final:
-- 8 -> {1,8,4,5,2,7,3,6}.
create function private.bracket_order(p_size int)
returns int[] language plpgsql immutable set search_path = '' as $$
declare
  v_order int[] := array[1];
  v_n     int := 1;
begin
  while v_n < p_size loop
    select array_agg(q.x order by q.ord, q.k) into v_order
    from (
      select t.ord, 1 as k, t.s as x from unnest(v_order) with ordinality t (s, ord)
      union all
      select t.ord, 2, 2 * v_n + 1 - t.s from unnest(v_order) with ordinality t (s, ord)
    ) q;
    v_n := v_n * 2;
  end loop;
  return v_order;
end $$;

create function private.round_label(p_matches int, p_match_no int, p_prefix text default '')
returns text language sql immutable set search_path = '' as $$
  select btrim(p_prefix || ' ' || case p_matches
    when 1 then 'Final'
    when 2 then 'Semi-final ' || p_match_no
    when 4 then 'Quarter-final ' || p_match_no
    else 'Round of ' || p_matches * 2 || ' · ' || p_match_no
  end);
$$;

-- Inserts one match. Without source matches the sides are final, so a match
-- with a single side is a bye that side wins outright.
create function private.match_add(
  p_stage_id uuid, p_bracket text, p_round int, p_match_no int, p_label text,
  p_side_a uuid default null, p_side_b uuid default null,
  p_a_source uuid default null, p_a_outcome text default null,
  p_b_source uuid default null, p_b_outcome text default null,
  p_group_id uuid default null, p_meta jsonb default '{}')
returns uuid language plpgsql set search_path = '' as $$
declare
  v_id     uuid;
  v_wired  boolean := p_a_source is not null or p_b_source is not null;
  v_status text;
begin
  v_status := case
    when v_wired then 'pending'
    when p_side_a is not null and p_side_b is not null then 'ready'
    else 'bye'
  end;
  insert into app.matches (
    event_id, stage_id, group_id, seq, bracket, round_no, match_no, label,
    side_a, side_b, a_source_match, a_source_outcome, b_source_match, b_source_outcome,
    status, winner_id, completed_at, meta)
  select s.event_id, s.id, p_group_id,
         coalesce((select max(m.seq) from app.matches m where m.stage_id = s.id), 0) + 1,
         p_bracket, p_round, p_match_no, p_label,
         p_side_a, p_side_b, p_a_source, p_a_outcome, p_b_source, p_b_outcome,
         v_status,
         case when v_status = 'bye' then coalesce(p_side_a, p_side_b) end,
         case when v_status = 'bye' then now() end,
         coalesce(p_meta, '{}')
  from app.event_stages s where s.id = p_stage_id
  returning id into v_id;
  return v_id;
end $$;

create function private.match_at(p_stage_id uuid, p_bracket text, p_round int, p_match_no int)
returns uuid language sql stable set search_path = '' as $$
  select id from app.matches
  where stage_id = p_stage_id and bracket = p_bracket and round_no = p_round and match_no = p_match_no;
$$;

-- -----------------------------------------------------------------------------
-- Bracket wiring: feeding winners and losers into the matches that wait on them
-- -----------------------------------------------------------------------------
create function private.match_resolve(p_match_id uuid) returns void
language plpgsql set search_path = '' as $$ begin null; end $$;  -- forward declaration

create function private.match_propagate(p_match_id uuid)
returns void language plpgsql set search_path = '' as $$
declare
  v_m app.matches;
  v_d record;
begin
  select * into v_m from app.matches where id = p_match_id;
  for v_d in
    select id, meta from app.matches
    where a_source_match = v_m.id or b_source_match = v_m.id
    order by seq
  loop
    -- A grand-final reset is only played when the losers-bracket champion
    -- (side b) wins the first grand final.
    if coalesce((v_d.meta ->> 'reset')::boolean, false) and v_m.winner_id is not distinct from v_m.side_a then
      update app.matches set status = 'cancelled' where id = v_d.id and status = 'pending';
      continue;
    end if;
    update app.matches d
    set side_a = case when d.a_source_match = v_m.id
                      then case d.a_source_outcome when 'winner' then v_m.winner_id else v_m.loser_id end
                      else d.side_a end,
        side_b = case when d.b_source_match = v_m.id
                      then case d.b_source_outcome when 'winner' then v_m.winner_id else v_m.loser_id end
                      else d.side_b end
    where d.id = v_d.id;
    perform private.match_resolve(v_d.id);
  end loop;
end $$;

-- Once everything a match waits on is settled it becomes playable, or, when a
-- bye upstream left it with fewer than two sides, a bye that keeps cascading.
create or replace function private.match_resolve(p_match_id uuid)
returns void language plpgsql set search_path = '' as $$
declare v_d app.matches;
begin
  select * into v_d from app.matches where id = p_match_id for update;
  if v_d.status <> 'pending' then
    return;
  end if;
  if exists (
    select 1 from app.matches s
    where s.id in (v_d.a_source_match, v_d.b_source_match)
      and s.status not in ('completed', 'walkover', 'bye', 'cancelled')) then
    return;
  end if;

  if v_d.side_a is not null and v_d.side_b is not null then
    update app.matches set status = 'ready' where id = v_d.id;
  else
    update app.matches
    set status = 'bye', winner_id = coalesce(v_d.side_a, v_d.side_b), completed_at = now()
    where id = v_d.id;
    perform private.match_propagate(v_d.id);
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Standings engine
--
-- One table function for every league-style stage. League points come from the
-- ruleset's `points`, and the order from its `tiebreakers` chain, e.g.
--   badminton  ["points", "h2h_points", "set_diff", "score_diff"]
--   cricket    ["points", "wins", "nrr", "h2h_points"]
-- Head-to-head values are computed inside each group of entrants level on
-- points, which is how BWF, ITTF and ICC all define them.
-- -----------------------------------------------------------------------------
create function private.stage_standings(p_stage_id uuid)
returns table (
  entrant_id uuid, group_id uuid, seed int,
  played int, won int, lost int, tied int, drawn int, no_result int,
  points numeric, sets_for int, sets_against int, score_for int, score_against int,
  nrr numeric, buchholz numeric, h2h_points numeric, "position" int)
language plpgsql stable set search_path = '' as $$
declare
  v_points jsonb;
  v_chain  jsonb;
  v_order  text := '';
  v_key    text;
begin
  select coalesce(r.points, '{}'::jsonb), coalesce(r.tiebreakers, '["points"]'::jsonb)
    into v_points, v_chain
  from app.event_stages s
  join app.tournament_events e on e.id = s.event_id
  join app.rulesets r on r.key = coalesce(s.config ->> 'ruleset', e.ruleset_key)
  where s.id = p_stage_id;

  -- Whitelisted tie-breakers only: the chain is data, the SQL is not.
  for v_key in select value from jsonb_array_elements_text(v_chain) loop
    v_order := v_order || case v_key
      when 'points'          then 't.points desc, '
      when 'wins'            then 't.won desc, '
      when 'h2h_points'      then 't.h2h_points desc, '
      when 'h2h_set_diff'    then 't.h2h_set_diff desc, '
      when 'h2h_score_diff'  then 't.h2h_score_diff desc, '
      when 'h2h_set_ratio'   then 't.h2h_set_ratio desc, '
      when 'h2h_score_ratio' then 't.h2h_score_ratio desc, '
      when 'set_diff'        then '(t.sets_for - t.sets_against) desc, '
      when 'set_ratio'       then '(case when t.sets_against = 0 then 1e9 else t.sets_for::numeric / t.sets_against end) desc, '
      when 'score_diff'      then '(t.score_for - t.score_against) desc, '
      when 'score_ratio'     then '(case when t.score_against = 0 then 1e9 else t.score_for::numeric / t.score_against end) desc, '
      when 'nrr'             then 't.nrr desc, '
      when 'buchholz'        then 't.buchholz desc, '
      else ''
    end;
  end loop;
  v_order := v_order || 't.seed, t.entrant_id';

  return query execute format($q$
    with sides as (
      select m.id, m.status, m.outcome, m.winner_id, m.side_a as me, m.side_b as opp,
             m.result -> 'a' as mine, m.result -> 'b' as theirs
      from app.matches m
      where m.stage_id = $1 and m.status in ('completed', 'walkover', 'bye') and m.side_a is not null
      union all
      select m.id, m.status, m.outcome, m.winner_id, m.side_b, m.side_a,
             m.result -> 'b', m.result -> 'a'
      from app.matches m
      where m.stage_id = $1 and m.status in ('completed', 'walkover', 'bye') and m.side_b is not null
    ),
    lines as (
      select s.me, s.opp, s.status, s.outcome,
             (s.status = 'bye' or (s.outcome = 'win' and s.winner_id = s.me)) as is_win,
             (s.outcome = 'win' and s.winner_id <> s.me) as is_loss,
             case
               when s.status = 'bye' or (s.outcome = 'win' and s.winner_id = s.me)
                 then coalesce(($2 ->> 'win')::numeric, 1)
               when s.outcome = 'win' and s.status = 'walkover'
                 then coalesce(($2 ->> 'walkover_loss')::numeric, ($2 ->> 'loss')::numeric, 0)
               when s.outcome = 'win'       then coalesce(($2 ->> 'loss')::numeric, 0)
               when s.outcome = 'tie'       then coalesce(($2 ->> 'tie')::numeric, 0)
               when s.outcome = 'draw'      then coalesce(($2 ->> 'draw')::numeric, 0)
               when s.outcome = 'no_result' then coalesce(($2 ->> 'no_result')::numeric, 0)
               else 0
             end as pts,
             coalesce((s.mine ->> 'sets')::int, 0) as sf, coalesce((s.theirs ->> 'sets')::int, 0) as sa,
             coalesce((s.mine ->> 'score')::int, 0) as pf, coalesce((s.theirs ->> 'score')::int, 0) as pa,
             coalesce((s.mine ->> 'nrr_runs')::numeric, 0) as rf, coalesce((s.mine ->> 'nrr_overs')::numeric, 0) as of,
             coalesce((s.theirs ->> 'nrr_runs')::numeric, 0) as ra, coalesce((s.theirs ->> 'nrr_overs')::numeric, 0) as oa
      from sides s
    ),
    base as (
      select se.entrant_id, se.group_id, se.seed,
             count(l.me) filter (where l.status <> 'bye')::int as played,
             count(*) filter (where l.is_win)::int as won,
             count(*) filter (where l.is_loss)::int as lost,
             count(*) filter (where l.outcome = 'tie')::int as tied,
             count(*) filter (where l.outcome = 'draw')::int as drawn,
             count(*) filter (where l.outcome = 'no_result')::int as no_result,
             coalesce(sum(l.pts), 0) as points,
             coalesce(sum(l.sf), 0)::int as sets_for, coalesce(sum(l.sa), 0)::int as sets_against,
             coalesce(sum(l.pf), 0)::int as score_for, coalesce(sum(l.pa), 0)::int as score_against,
             round(coalesce(sum(l.rf) / nullif(sum(l.of), 0), 0)
                 - coalesce(sum(l.ra) / nullif(sum(l.oa), 0), 0), 3) as nrr
      from app.stage_entrants se
      left join lines l on l.me = se.entrant_id
      where se.stage_id = $1
      group by se.entrant_id, se.group_id, se.seed
    ),
    t as (
      select b.*,
             coalesce((select sum(o.points) from lines l join base o on o.entrant_id = l.opp
                       where l.me = b.entrant_id), 0) as buchholz,
             coalesce(h.pts, 0) as h2h_points,
             coalesce(h.sf - h.sa, 0) as h2h_set_diff,
             coalesce(h.pf - h.pa, 0) as h2h_score_diff,
             case when coalesce(h.sa, 0) = 0 then coalesce(h.sf, 0)::numeric else h.sf::numeric / h.sa end as h2h_set_ratio,
             case when coalesce(h.pa, 0) = 0 then coalesce(h.pf, 0)::numeric else h.pf::numeric / h.pa end as h2h_score_ratio
      from base b
      left join lateral (
        select sum(l.pts) as pts, sum(l.sf) as sf, sum(l.sa) as sa, sum(l.pf) as pf, sum(l.pa) as pa
        from lines l
        join base o on o.entrant_id = l.opp
        where l.me = b.entrant_id
          and o.group_id is not distinct from b.group_id
          and o.points = b.points
      ) h on true
    )
    select t.entrant_id, t.group_id, t.seed, t.played, t.won, t.lost, t.tied, t.drawn, t.no_result,
           t.points, t.sets_for, t.sets_against, t.score_for, t.score_against,
           t.nrr, t.buchholz, t.h2h_points,
           row_number() over (partition by t.group_id order by %s)::int
    from t
    order by t.group_id, 18
  $q$, v_order) using p_stage_id, v_points;
end $$;

-- -----------------------------------------------------------------------------
-- Pairing engines: private.<pair_fn>(stage_id) -> number of matches created.
-- Returning 0 means "nothing left to pair", which is what closes a stage.
-- -----------------------------------------------------------------------------

-- Round robin by the circle method. Covers leagues, group stages (snake-seeded
-- groups), home-and-away (legs = 2) and a series between two sides.
create function private.pair_round_robin(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_stage   app.event_stages;
  v_groups  int;
  v_legs    int;
  v_n       int;
  v_group   record;
  v_arr     uuid[];
  v_size    int;
  v_a uuid; v_b uuid; v_tmp uuid;
  v_round   int;
  v_created int := 0;
  v_no      int;
begin
  if exists (select 1 from app.matches where stage_id = p_stage_id) then
    return 0;
  end if;
  select * into v_stage from app.event_stages where id = p_stage_id;
  v_groups := greatest(coalesce((v_stage.config ->> 'groups')::int, 1), 1);
  v_legs   := greatest(coalesce((v_stage.config ->> 'legs')::int, (v_stage.config ->> 'matches')::int, 1), 1);
  select count(*) into v_n from app.stage_entrants where stage_id = p_stage_id;
  if v_n < 2 * v_groups then
    perform private.fail(422, 'not_enough_entrants',
      format('%s group(s) need at least %s entrants; this stage has %s.', v_groups, 2 * v_groups, v_n));
  end if;

  insert into app.stage_groups (stage_id, seq, name)
  select p_stage_id, i, case when v_groups = 1 then 'League' else 'Group ' || chr(64 + i) end
  from generate_series(1, v_groups) i;

  -- Snake seeding: 1 2 3 4 / 8 7 6 5 / 9 10 11 12 ...
  update app.stage_entrants se
  set group_id = g.id
  from app.stage_groups g
  where se.stage_id = p_stage_id and g.stage_id = p_stage_id
    and g.seq = 1 + case when ((se.seed - 1) / v_groups) % 2 = 0
                         then (se.seed - 1) % v_groups
                         else v_groups - 1 - (se.seed - 1) % v_groups end;

  for v_group in select id from app.stage_groups where stage_id = p_stage_id order by seq loop
    select array_agg(entrant_id order by seed) into v_arr
    from app.stage_entrants where stage_id = p_stage_id and group_id = v_group.id;
    if array_length(v_arr, 1) % 2 = 1 then
      v_arr := v_arr || null::uuid;   -- the odd one out sits a round
    end if;
    v_size := array_length(v_arr, 1);

    for v_leg in 1..v_legs loop
      for v_r in 1..v_size - 1 loop
        v_round := (v_leg - 1) * (v_size - 1) + v_r;
        for v_i in 1..v_size / 2 loop
          v_a := v_arr[v_i];
          v_b := v_arr[v_size + 1 - v_i];
          if v_a is not null and v_b is not null then
            if (v_r + v_i + v_leg) % 2 = 1 then   -- alternate who is listed first
              v_tmp := v_a; v_a := v_b; v_b := v_tmp;
            end if;
            select coalesce(max(match_no), 0) + 1 into v_no
            from app.matches where stage_id = p_stage_id and bracket = 'main' and round_no = v_round;
            perform private.match_add(p_stage_id, 'main', v_round, v_no,
              case when v_n = 2 then 'Match ' || v_round else 'Round ' || v_round end,
              v_a, v_b, p_group_id => v_group.id);
            v_created := v_created + 1;
          end if;
        end loop;
        v_arr := v_arr[1:1] || v_arr[v_size:v_size] || v_arr[2:v_size - 1];
      end loop;
    end loop;
  end loop;
  return v_created;
end $$;

-- A series between exactly two sides (bilateral cricket series, best-of ties).
create function private.pair_series(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
begin
  if (select count(*) from app.stage_entrants where stage_id = p_stage_id) <> 2 then
    perform private.fail(422, 'not_enough_entrants', 'A series is played between exactly two sides.');
  end if;
  return private.pair_round_robin(p_stage_id);
end $$;

-- Builds a seeded elimination tree in `p_bracket` and returns its round count.
create function private.bracket_build(p_stage_id uuid, p_bracket text, p_third_place boolean, p_prefix text default '')
returns int language plpgsql set search_path = '' as $$
declare
  v_ids    uuid[];
  v_n      int;
  v_size   int := 2;
  v_rounds int := 1;
  v_order  int[];
  v_count  int;
begin
  select array_agg(entrant_id order by seed) into v_ids
  from app.stage_entrants where stage_id = p_stage_id;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n < 2 then
    perform private.fail(422, 'not_enough_entrants', 'A knockout needs at least two entrants.');
  end if;
  while v_size < v_n loop
    v_size := v_size * 2;
    v_rounds := v_rounds + 1;
  end loop;
  v_order := private.bracket_order(v_size);

  -- Round one: seeds beyond the field are byes for their opponents.
  for v_m in 1..v_size / 2 loop
    perform private.match_add(p_stage_id, p_bracket, 1, v_m,
      private.round_label(v_size / 2, v_m, p_prefix),
      v_ids[v_order[2 * v_m - 1]], v_ids[v_order[2 * v_m]]);
  end loop;

  v_count := v_size / 2;
  for v_r in 2..v_rounds loop
    v_count := v_count / 2;
    for v_m in 1..v_count loop
      perform private.match_add(p_stage_id, p_bracket, v_r, v_m,
        private.round_label(v_count, v_m, p_prefix),
        p_a_source => private.match_at(p_stage_id, p_bracket, v_r - 1, 2 * v_m - 1), p_a_outcome => 'winner',
        p_b_source => private.match_at(p_stage_id, p_bracket, v_r - 1, 2 * v_m),     p_b_outcome => 'winner');
    end loop;
  end loop;

  if p_third_place and v_rounds >= 2 then
    perform private.match_add(p_stage_id, 'third_place', v_rounds, 1, 'Third place',
      p_a_source => private.match_at(p_stage_id, p_bracket, v_rounds - 1, 1), p_a_outcome => 'loser',
      p_b_source => private.match_at(p_stage_id, p_bracket, v_rounds - 1, 2), p_b_outcome => 'loser');
  end if;
  return v_rounds;
end $$;

-- Lets first-round byes flow into the rounds that wait on them.
create function private.bracket_settle(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  for v_id in
    select id from app.matches
    where stage_id = p_stage_id and status = 'bye'
      and a_source_match is null and b_source_match is null
    order by seq
  loop
    perform private.match_propagate(v_id);
  end loop;
  return (select count(*)::int from app.matches where stage_id = p_stage_id);
end $$;

-- Single elimination. config: {"third_place": true}
create function private.pair_single_elimination(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from app.matches where stage_id = p_stage_id) then
    return 0;
  end if;
  perform private.bracket_build(p_stage_id, 'main',
    coalesce((select (config ->> 'third_place')::boolean from app.event_stages where id = p_stage_id), false));
  return private.bracket_settle(p_stage_id);
end $$;

-- Double elimination: a winners bracket, a losers bracket fed by its losers,
-- and a grand final. config: {"grand_final_reset": true}
create function private.pair_double_elimination(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_k     int;
  v_size  int;
  v_count int;
  v_final uuid;
begin
  if exists (select 1 from app.matches where stage_id = p_stage_id) then
    return 0;
  end if;
  if (select count(*) from app.stage_entrants where stage_id = p_stage_id) < 3 then
    perform private.fail(422, 'not_enough_entrants', 'Double elimination needs at least three entrants.');
  end if;
  v_k := private.bracket_build(p_stage_id, 'winners', false, 'Winners');
  v_size := (2 ^ v_k)::int;

  for v_j in 1..v_k - 1 loop
    v_count := v_size / (2 ^ (v_j + 1))::int;
    -- Minor round: survivors of the losers bracket meet each other.
    for v_m in 1..v_count loop
      if v_j = 1 then
        perform private.match_add(p_stage_id, 'losers', 1, v_m, 'Losers round 1 · ' || v_m,
          p_a_source => private.match_at(p_stage_id, 'winners', 1, 2 * v_m - 1), p_a_outcome => 'loser',
          p_b_source => private.match_at(p_stage_id, 'winners', 1, 2 * v_m),     p_b_outcome => 'loser');
      else
        perform private.match_add(p_stage_id, 'losers', 2 * v_j - 1, v_m,
          format('Losers round %s · %s', 2 * v_j - 1, v_m),
          p_a_source => private.match_at(p_stage_id, 'losers', 2 * v_j - 2, 2 * v_m - 1), p_a_outcome => 'winner',
          p_b_source => private.match_at(p_stage_id, 'losers', 2 * v_j - 2, 2 * v_m),     p_b_outcome => 'winner');
      end if;
    end loop;
    -- Major round: they meet the sides dropping out of the winners bracket,
    -- in mirrored order on alternate rounds to delay rematches.
    for v_m in 1..v_count loop
      perform private.match_add(p_stage_id, 'losers', 2 * v_j, v_m,
        case when v_j = v_k - 1 then 'Losers final' else format('Losers round %s · %s', 2 * v_j, v_m) end,
        p_a_source => private.match_at(p_stage_id, 'losers', 2 * v_j - 1, v_m), p_a_outcome => 'winner',
        p_b_source => private.match_at(p_stage_id, 'winners', v_j + 1,
                        case when v_j % 2 = 1 then v_count + 1 - v_m else v_m end), p_b_outcome => 'loser');
    end loop;
  end loop;

  v_final := private.match_add(p_stage_id, 'grand_final', 1, 1, 'Grand final',
    p_a_source => private.match_at(p_stage_id, 'winners', v_k, 1),          p_a_outcome => 'winner',
    p_b_source => private.match_at(p_stage_id, 'losers', 2 * (v_k - 1), 1), p_b_outcome => 'winner');
  if coalesce((select (config ->> 'grand_final_reset')::boolean from app.event_stages where id = p_stage_id), false) then
    perform private.match_add(p_stage_id, 'grand_final', 2, 1, 'Grand final reset',
      p_a_source => v_final, p_a_outcome => 'loser',
      p_b_source => v_final, p_b_outcome => 'winner',
      p_meta => '{"reset": true}');
  end if;
  return private.bracket_settle(p_stage_id);
end $$;

-- Swiss system: one round at a time, pairing neighbours in the table who have
-- not met. config: {"rounds": 5} (default: ceil(log2(entrants)))
create function private.pair_swiss(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_ids    uuid[];
  v_n      int;
  v_round  int;
  v_total  int;
  v_used   boolean[];
  v_bye    uuid;
  v_j      int;
  v_half   int;
  v_no     int := 0;
begin
  select count(*) into v_n from app.stage_entrants where stage_id = p_stage_id;
  if v_n < 2 then
    perform private.fail(422, 'not_enough_entrants', 'A Swiss stage needs at least two entrants.');
  end if;
  select coalesce(max(round_no), 0) into v_round from app.matches where stage_id = p_stage_id;
  select least(coalesce((config ->> 'rounds')::int, ceil(log(2, v_n))::int), greatest(v_n - 1, 1)) into v_total
  from app.event_stages where id = p_stage_id;
  if v_round >= greatest(v_total, 1) then
    return 0;
  end if;

  if v_round = 0 then
    select array_agg(entrant_id order by seed) into v_ids from app.stage_entrants where stage_id = p_stage_id;
  else
    select array_agg(s.entrant_id order by s.position) into v_ids from private.stage_standings(p_stage_id) s;
  end if;
  v_round := v_round + 1;

  -- Odd field: the lowest-placed entrant without a bye yet gets one (a win).
  if v_n % 2 = 1 then
    select x.id into v_bye
    from unnest(v_ids) with ordinality x (id, ord)
    where not exists (select 1 from app.matches m
                      where m.stage_id = p_stage_id and m.status = 'bye' and m.side_a = x.id)
    order by x.ord desc limit 1;
    v_bye := coalesce(v_bye, v_ids[v_n]);
    v_ids := array_remove(v_ids, v_bye);
    v_n := v_n - 1;
  end if;

  v_used := array_fill(false, array[v_n]);
  v_half := v_n / 2;
  for v_i in 1..v_n loop
    continue when v_used[v_i];
    v_j := null;
    if v_round = 1 then
      v_j := v_i + v_half;            -- top half meets bottom half
    else
      select min(k) into v_j from generate_series(v_i + 1, v_n) k
      where not v_used[k]
        and not exists (select 1 from app.matches m
                        where m.stage_id = p_stage_id
                          and ((m.side_a = v_ids[v_i] and m.side_b = v_ids[k])
                            or (m.side_a = v_ids[k] and m.side_b = v_ids[v_i])));
      if v_j is null then             -- everyone left has met: allow a rematch
        select min(k) into v_j from generate_series(v_i + 1, v_n) k where not v_used[k];
      end if;
    end if;
    v_used[v_i] := true;
    v_used[v_j] := true;
    v_no := v_no + 1;
    perform private.match_add(p_stage_id, 'main', v_round, v_no, 'Round ' || v_round, v_ids[v_i], v_ids[v_j]);
  end loop;

  if v_bye is not null then
    v_no := v_no + 1;
    perform private.match_add(p_stage_id, 'main', v_round, v_no, 'Round ' || v_round || ' bye', v_bye, null);
  end if;
  return v_no;
end $$;

-- Page playoff for the top four (IPL, BBL finals): the top two get a second life.
create function private.pair_page_playoff(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_ids uuid[];
  v_q1 uuid; v_el uuid; v_q2 uuid;
begin
  if exists (select 1 from app.matches where stage_id = p_stage_id) then
    return 0;
  end if;
  select array_agg(entrant_id order by seed) into v_ids from app.stage_entrants where stage_id = p_stage_id;
  if coalesce(array_length(v_ids, 1), 0) <> 4 then
    perform private.fail(422, 'not_enough_entrants', 'A page playoff is played by exactly four sides.');
  end if;
  v_q1 := private.match_add(p_stage_id, 'playoff', 1, 1, 'Qualifier 1', v_ids[1], v_ids[2]);
  v_el := private.match_add(p_stage_id, 'playoff', 1, 2, 'Eliminator', v_ids[3], v_ids[4]);
  v_q2 := private.match_add(p_stage_id, 'playoff', 2, 1, 'Qualifier 2',
    p_a_source => v_q1, p_a_outcome => 'loser', p_b_source => v_el, p_b_outcome => 'winner');
  perform private.match_add(p_stage_id, 'playoff', 3, 1, 'Final',
    p_a_source => v_q1, p_a_outcome => 'winner', p_b_source => v_q2, p_b_outcome => 'winner');
  return 4;
end $$;

-- -----------------------------------------------------------------------------
-- Ranking engines: private.<rank_fn>(stage_id) fills group_rank / final_rank.
-- -----------------------------------------------------------------------------

-- League-style stages: rank inside each group, then across groups by place.
create function private.rank_standings(p_stage_id uuid)
returns void language sql set search_path = '' as $$
  update app.stage_entrants se
  set group_rank = q.position, final_rank = q.overall
  from (
    select s.entrant_id, s.position,
           row_number() over (order by s.position, s.points desc,
                              s.sets_for - s.sets_against desc,
                              s.score_for - s.score_against desc,
                              s.nrr desc, s.seed)::int as overall
    from private.stage_standings(p_stage_id) s
  ) q
  where se.stage_id = p_stage_id and se.entrant_id = q.entrant_id;
$$;

-- Bracket stages: the later a side played its last match the better, and a
-- win there beats a loss. Works for single and double elimination and the
-- page playoff, because each bracket is weighted by when it is played.
create function private.rank_bracket(p_stage_id uuid)
returns void language sql set search_path = '' as $$
  with played as (
    select x.entrant_id, x.won,
           case m.bracket
             when 'grand_final' then 1000 + m.round_no
             when 'losers'      then 100 + m.round_no
             when 'third_place' then m.round_no - 0.5
             else m.round_no
           end as weight
    from app.matches m
    cross join lateral (values (m.side_a, m.winner_id = m.side_a), (m.side_b, m.winner_id = m.side_b)) x (entrant_id, won)
    where m.stage_id = p_stage_id and m.status in ('completed', 'walkover') and x.entrant_id is not null
  ),
  last_match as (
    select distinct on (entrant_id) entrant_id, weight, won
    from played order by entrant_id, weight desc
  )
  update app.stage_entrants se
  set final_rank = q.rank, group_rank = q.rank
  from (
    select s.entrant_id,
           row_number() over (order by l.weight desc nulls last, l.won desc nulls last, s.seed)::int as rank
    from app.stage_entrants s
    left join last_match l on l.entrant_id = s.entrant_id
    where s.stage_id = p_stage_id
  ) q
  where se.stage_id = p_stage_id and se.entrant_id = q.entrant_id;
$$;

-- -----------------------------------------------------------------------------
-- The pipeline: seed -> pair -> (score) -> progress -> rank -> advance
-- -----------------------------------------------------------------------------

-- Seeds the first stage from the accepted entrants: explicit seeds first, the
-- rest by a random draw or by registration order.
create function private.stage_fill(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_stage app.event_stages;
  v_count int;
begin
  select * into v_stage from app.event_stages where id = p_stage_id;
  delete from app.stage_entrants where stage_id = p_stage_id;
  insert into app.stage_entrants (stage_id, entrant_id, seed)
  select p_stage_id, e.id,
         row_number() over (order by e.seed nulls last,
           case when coalesce(v_stage.config ->> 'draw', 'random') = 'random' then random() end,
           e.created_at, e.id)
  from app.entrants e
  where e.event_id = v_stage.event_id and e.status = 'accepted';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

create function private.stage_start(p_stage_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_fn      text;
  v_created int;
begin
  select f.pair_fn into v_fn
  from app.event_stages s join app.stage_formats f on f.key = s.format_key
  where s.id = p_stage_id;
  update app.event_stages set status = 'live' where id = p_stage_id;
  execute format('select private.%I($1)', v_fn) into v_created using p_stage_id;
  if coalesce(v_created, 0) = 0 then
    perform private.fail(422, 'no_matches', 'This stage produced no matches.');
  end if;
  return v_created;
end $$;

-- Moves the qualifiers of a finished stage into the next one and seeds them.
-- next.config.qualify: {"per_group": 2, "best_next": 0} or {"top": 4}
-- Group winners are seeded first and runners-up are placed so that a winner
-- meets the runner-up of the neighbouring group (A1 v B2, B1 v A2).
create function private.stage_advance(p_from uuid, p_to uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_qualify   jsonb;
  v_groups    int;
  v_per_group int;
  v_top       int;
  v_best_next int;
  v_count     int;
begin
  select coalesce(config -> 'qualify', '{}'::jsonb) into v_qualify from app.event_stages where id = p_to;
  select count(*) into v_groups from app.stage_groups where stage_id = p_from;
  v_per_group := (v_qualify ->> 'per_group')::int;
  v_top       := (v_qualify ->> 'top')::int;
  v_best_next := coalesce((v_qualify ->> 'best_next')::int, 0);

  delete from app.stage_entrants where stage_id = p_to;
  if v_groups <= 1 or v_per_group is null then
    v_top := coalesce(v_top, v_per_group, 4);
    insert into app.stage_entrants (stage_id, entrant_id, seed)
    select p_to, se.entrant_id, row_number() over (order by se.final_rank)
    from app.stage_entrants se
    where se.stage_id = p_from and se.final_rank <= v_top;
  else
    insert into app.stage_entrants (stage_id, entrant_id, seed)
    select p_to, q.entrant_id, row_number() over (order by q.slot, q.final_rank)
    from (
      select se.entrant_id, se.final_rank,
             case
               when se.group_rank = 1 then g.seq
               when se.group_rank = 2 then 2 * v_groups
                    - case when v_groups % 2 = 0 then (g.seq - 1) # 1 else g.seq % v_groups end
               when se.group_rank <= v_per_group then (se.group_rank - 1) * v_groups + g.seq
               else v_per_group * v_groups + 1
             end as slot
      from app.stage_entrants se
      join app.stage_groups g on g.id = se.group_id
      where se.stage_id = p_from
        and (se.group_rank <= v_per_group
             or se.entrant_id in (
               select b.entrant_id from app.stage_entrants b
               where b.stage_id = p_from and b.group_rank = v_per_group + 1
               order by b.final_rank limit v_best_next))
    ) q;
  end if;
  get diagnostics v_count = row_count;
  if v_count < 2 then
    perform private.fail(422, 'not_enough_entrants', 'Fewer than two entrants qualified for the next stage.');
  end if;
  return v_count;
end $$;

create function private.stage_finish(p_stage_id uuid)
returns void language plpgsql set search_path = '' as $$
declare
  v_stage   app.event_stages;
  v_rank_fn text;
  v_next    uuid;
begin
  select s.* into v_stage from app.event_stages s where s.id = p_stage_id;
  select f.rank_fn into v_rank_fn from app.stage_formats f where f.key = v_stage.format_key;
  execute format('select private.%I($1)', v_rank_fn) using p_stage_id;
  update app.event_stages set status = 'completed' where id = p_stage_id;

  select id into v_next from app.event_stages where event_id = v_stage.event_id and seq = v_stage.seq + 1;
  if v_next is not null then
    perform private.stage_advance(p_stage_id, v_next);
    perform private.stage_start(v_next);
    return;
  end if;

  -- Last stage: its ranking is the event's final placing.
  update app.entrants e
  set final_rank = se.final_rank
  from app.stage_entrants se
  where se.stage_id = p_stage_id and se.entrant_id = e.id;
  update app.tournament_events set status = 'completed' where id = v_stage.event_id;
  update app.tournaments t
  set status = 'completed'
  from app.tournament_events e
  where e.id = v_stage.event_id and t.id = e.tournament_id and t.status = 'live'
    and not exists (select 1 from app.tournament_events o
                    where o.tournament_id = t.id and o.status <> 'completed');
end $$;

-- Called after every result. When nothing is left to play the pairing engine
-- gets one more turn (Swiss pairs its next round); if it has nothing to add
-- the stage is ranked and the next stage, if any, begins.
create function private.stage_progress(p_stage_id uuid)
returns void language plpgsql set search_path = '' as $$
declare
  v_fn      text;
  v_status  text;
  v_created int;
begin
  select s.status, f.pair_fn into v_status, v_fn
  from app.event_stages s join app.stage_formats f on f.key = s.format_key
  where s.id = p_stage_id;
  if v_status <> 'live'
     or exists (select 1 from app.matches
                where stage_id = p_stage_id and status in ('pending', 'ready', 'live')) then
    return;
  end if;
  execute format('select private.%I($1)', v_fn) into v_created using p_stage_id;
  if coalesce(v_created, 0) = 0 then
    perform private.stage_finish(p_stage_id);
  end if;
end $$;

create function private.event_start(p_event_id uuid)
returns int language plpgsql set search_path = '' as $$
declare
  v_event app.tournament_events;
  v_stage uuid;
  v_count int;
begin
  select * into v_event from app.tournament_events where id = p_event_id for update;
  if v_event.status <> 'setup' then
    perform private.fail(409, 'event_already_started', 'This event has already started.');
  end if;
  select id into v_stage from app.event_stages where event_id = p_event_id and seq = 1;
  if v_stage is null then
    perform private.fail(422, 'no_stages', 'Add at least one stage before starting.');
  end if;
  v_count := private.stage_fill(v_stage);
  if v_count < 2 then
    perform private.fail(422, 'not_enough_entrants', 'Accept at least two entrants before starting.');
  end if;
  update app.entrants set status = 'rejected', decided_at = now()
  where event_id = p_event_id and status in ('pending', 'waitlisted');
  update app.tournament_events set status = 'live' where id = p_event_id;
  update app.tournaments set status = 'live'
  where id = v_event.tournament_id and status in ('draft', 'open', 'closed');
  return private.stage_start(v_stage);
end $$;

-- Throws the draw away and puts the event back into setup.
create function private.event_reset(p_event_id uuid)
returns void language plpgsql set search_path = '' as $$
begin
  delete from app.bookings b using app.matches m
  where m.event_id = p_event_id and m.booking_id = b.id;
  delete from app.matches where event_id = p_event_id;
  delete from app.stage_entrants se using app.event_stages s
  where s.id = se.stage_id and s.event_id = p_event_id;
  delete from app.stage_groups g using app.event_stages s
  where s.id = g.stage_id and s.event_id = p_event_id;
  update app.event_stages set status = 'pending' where event_id = p_event_id;
  update app.entrants set final_rank = null where event_id = p_event_id;
  update app.tournament_events set status = 'setup' where id = p_event_id;
end $$;

-- -----------------------------------------------------------------------------
-- Results
-- -----------------------------------------------------------------------------
create function private.match_close(p_match_id uuid, p_status text, p_result jsonb)
returns void language plpgsql set search_path = '' as $$
declare
  v_m      app.matches;
  v_winner uuid;
  v_strict boolean;
begin
  select * into v_m from app.matches where id = p_match_id;
  select f.needs_winner into v_strict
  from app.event_stages s join app.stage_formats f on f.key = s.format_key
  where s.id = v_m.stage_id;
  if v_strict and p_result ->> 'outcome' <> 'win' then
    perform private.fail(422, 'winner_required',
      'A knockout match needs a winner. Record the tie-break (for example a Super Over) or a walkover.');
  end if;
  v_winner := case p_result ->> 'winner' when 'a' then v_m.side_a when 'b' then v_m.side_b end;

  update app.matches
  set status = p_status, result = p_result, outcome = p_result ->> 'outcome',
      winner_id = v_winner,
      loser_id = case when v_winner = v_m.side_a then v_m.side_b when v_winner = v_m.side_b then v_m.side_a end,
      completed_at = now()
  where id = p_match_id;

  perform private.match_propagate(p_match_id);
  perform private.stage_progress(v_m.stage_id);
end $$;

-- Records a score. Live updates (final = false) are stored as they come; a
-- final score is validated by the ruleset's scoring engine and then drives
-- the bracket and the tables.
create function private.match_record(p_match_id uuid, p_score jsonb, p_final boolean)
returns void language plpgsql set search_path = '' as $$
declare
  v_m       app.matches;
  v_ruleset text;
  v_result  jsonb;
begin
  select * into v_m from app.matches where id = p_match_id for update;
  if not found then
    perform private.fail(404, 'match_not_found', 'Match not found.');
  end if;
  if v_m.status in ('completed', 'walkover') then
    perform private.fail(409, 'match_already_final', 'This result is final. Reopen the match to correct it.');
  end if;
  if v_m.status not in ('ready', 'live') then
    perform private.fail(409, 'match_not_ready', 'Both sides of this match are not known yet.');
  end if;

  select coalesce(s.config ->> 'ruleset', e.ruleset_key) into v_ruleset
  from app.event_stages s join app.tournament_events e on e.id = s.event_id
  where s.id = v_m.stage_id;
  v_result := private.score_match(v_ruleset, p_score, p_final);

  if p_final then
    update app.matches set score = p_score where id = p_match_id;
    perform private.match_close(p_match_id, 'completed', v_result);
  else
    update app.matches set score = p_score, result = v_result, status = 'live' where id = p_match_id;
  end if;
end $$;

create function private.match_walkover(p_match_id uuid, p_winner_side text)
returns void language plpgsql set search_path = '' as $$
declare v_m app.matches;
begin
  select * into v_m from app.matches where id = p_match_id for update;
  if not found then
    perform private.fail(404, 'match_not_found', 'Match not found.');
  end if;
  if v_m.status not in ('ready', 'live') or p_winner_side not in ('a', 'b') then
    perform private.fail(409, 'match_not_ready', 'A walkover needs a match with both sides known.');
  end if;
  perform private.match_close(p_match_id, 'walkover', jsonb_build_object(
    'complete', true, 'outcome', 'win', 'winner', p_winner_side,
    'summary', 'Walkover', 'margin', 'walkover',
    'a', private.score_side(0, 0), 'b', private.score_side(0, 0)));
end $$;

-- Clears everything that was derived from a result, recursively through byes.
create function private.match_unwind(p_match_id uuid)
returns void language plpgsql set search_path = '' as $$
declare v_d record;
begin
  for v_d in
    select id, status from app.matches
    where a_source_match = p_match_id or b_source_match = p_match_id
  loop
    if v_d.status in ('live', 'completed', 'walkover') then
      perform private.fail(409, 'next_match_played',
        'A later match that depends on this result has already been played. Reopen that one first.');
    end if;
    if v_d.status = 'bye' then
      perform private.match_unwind(v_d.id);
    end if;
    update app.matches d
    set side_a = case when d.a_source_match = p_match_id then null else d.side_a end,
        side_b = case when d.b_source_match = p_match_id then null else d.side_b end,
        status = 'pending', winner_id = null, loser_id = null, completed_at = null
    where d.id = v_d.id;
  end loop;
end $$;

-- Reopens a final result so it can be corrected.
create function private.match_reopen(p_match_id uuid)
returns void language plpgsql set search_path = '' as $$
declare
  v_m           app.matches;
  v_stage       app.event_stages;
  v_incremental boolean;
begin
  select * into v_m from app.matches where id = p_match_id for update;
  if not found then
    perform private.fail(404, 'match_not_found', 'Match not found.');
  end if;
  if v_m.status not in ('completed', 'walkover') then
    perform private.fail(409, 'match_not_final', 'Only a finished match can be reopened.');
  end if;
  select * into v_stage from app.event_stages where id = v_m.stage_id;
  select incremental into v_incremental from app.stage_formats where key = v_stage.format_key;
  if v_stage.status <> 'live' then
    perform private.fail(409, 'stage_closed', 'This stage is finished and its standings have been used.');
  end if;
  if v_incremental and exists (
       select 1 from app.matches where stage_id = v_m.stage_id and round_no > v_m.round_no) then
    perform private.fail(409, 'next_match_played', 'The next round was already paired from this result.');
  end if;

  perform private.match_unwind(p_match_id);
  update app.matches
  set status = 'ready', result = null, outcome = null, winner_id = null, loser_id = null, completed_at = null
  where id = p_match_id;
end $$;
