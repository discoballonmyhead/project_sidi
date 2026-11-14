-- Test helpers. Tests call the public RPCs as the `authenticated` role with a
-- JWT subject set, exactly like PostgREST does; `t.*` is how they look behind
-- the curtain.
create schema t;

create function t.user(p_email text) returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  select id into v_id from auth.users where email = p_email;
  if v_id is null then
    insert into auth.users (email, raw_user_meta_data)
    values (p_email, jsonb_build_object('display_name', initcap(split_part(p_email, '@', 1))))
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- Become a signed-in user (or a visitor with p_email = null).
create function t.login(p_email text) returns void language plpgsql security definer as $$
begin
  perform set_config('request.jwt.claims',
    case when p_email is null then '' else json_build_object('sub', t.user(p_email))::text end, false);
end $$;

create function t.ok(p_condition boolean, p_message text) returns void language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end $$;

create function t.eq(p_actual anyelement, p_expected anyelement, p_message text) returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'ASSERTION FAILED: % (expected %, got %)', p_message, p_expected, p_actual;
  end if;
end $$;

-- Asserts that a statement fails with the given error slug or SQLSTATE.
create function t.throws(p_sql text, p_expected text, p_message text default null) returns void language plpgsql as $$
declare v_state text; v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_msg = p_expected or v_state = p_expected then
      return;
    end if;
    raise exception 'ASSERTION FAILED: % (expected %, got % / %)', coalesce(p_message, p_sql), p_expected, v_state, v_msg;
  end;
  raise exception 'ASSERTION FAILED: % (expected %, but it succeeded)', coalesce(p_message, p_sql), p_expected;
end $$;

-- Peek at data as the owner.
create function t.q(p_sql text) returns jsonb language plpgsql security definer as $$
declare v jsonb;
begin
  execute 'select to_jsonb(x) from (' || p_sql || ') x limit 1' into v;
  return v;
end $$;

create function t.exec(p_sql text) returns void language plpgsql security definer as $$
begin
  execute p_sql;
end $$;

-- An approved organisation owned by p_email, with the given features.
create function t.org(p_email text, p_name text, p_features text[] default '{}') returns uuid
language plpgsql security definer as $$
declare v_id uuid; v_admin uuid := t.user('admin@sidi.test');
begin
  insert into app.platform_roles (user_id, role) values (v_admin, 'admin') on conflict do nothing;
  perform t.login(p_email);
  v_id := (public.org_create(jsonb_build_object('name', p_name, 'sports',
            jsonb_build_array('badminton', 'table_tennis', 'cricket', 'gym'), 'city', 'Kolkata')) ->> 'id')::uuid;
  perform t.login('admin@sidi.test');
  perform public.admin_request_decide(
    (select id from app.requests where org_id = v_id and kind = 'org_approval'), true);
  perform private.grant_feature(v_id, f, v_admin) from unnest(p_features) f;
  perform t.login(p_email);
  return v_id;
end $$;

-- A score that makes side `p_winner` win, in the shape the ruleset expects.
create function t.winning_score(p_ruleset text, p_winner text) returns jsonb language plpgsql security definer as $$
declare
  v_r app.rulesets;
  v_game jsonb;
  v_games jsonb;
  v_need int;
  v_quota int;
begin
  select * into v_r from app.rulesets where key = p_ruleset;
  if v_r.scoring_kind = 'rally_games' then
    v_need := (v_r.config ->> 'best_of')::int / 2 + 1;
    v_game := case p_winner when 'a' then jsonb_build_array((v_r.config ->> 'points')::int, 7)
                            else jsonb_build_array(7, (v_r.config ->> 'points')::int) end;
    select jsonb_agg(v_game) into v_games from generate_series(1, v_need);
    return jsonb_build_object('games', v_games);
  elsif v_r.scoring_kind = 'team_tie' then
    v_need := (v_r.config #>> '{rubber,best_of}')::int / 2 + 1;
    v_game := case p_winner when 'a' then jsonb_build_array((v_r.config #>> '{rubber,points}')::int, 5)
                            else jsonb_build_array(5, (v_r.config #>> '{rubber,points}')::int) end;
    select jsonb_agg(v_game) into v_games from generate_series(1, v_need);
    return jsonb_build_object('rubbers', (
      select jsonb_agg(jsonb_build_object('games', v_games)) from generate_series(1, (v_r.config ->> 'win_at')::int)));
  elsif v_r.scoring_kind = 'cricket_limited' then
    v_quota := (v_r.config ->> 'overs')::int * (v_r.config ->> 'balls_per_over')::int;
    return jsonb_build_object('innings', jsonb_build_array(
      jsonb_build_object('side', 'a', 'runs', 160, 'wickets', 6, 'balls', v_quota),
      case p_winner
        when 'a' then jsonb_build_object('side', 'b', 'runs', 140, 'wickets', 8, 'balls', v_quota)
        else jsonb_build_object('side', 'b', 'runs', 161, 'wickets', 4, 'balls', v_quota - 9) end));
  else
    return jsonb_build_object('innings', jsonb_build_array(
      jsonb_build_object('side', 'a', 'runs', 300, 'wickets', 10),
      jsonb_build_object('side', 'b', 'runs', 250, 'wickets', 10),
      jsonb_build_object('side', 'a', 'runs', 200, 'wickets', 10),
      case p_winner
        when 'a' then jsonb_build_object('side', 'b', 'runs', 150, 'wickets', 10)
        else jsonb_build_object('side', 'b', 'runs', 251, 'wickets', 6) end));
  end if;
end $$;

-- Plays every playable match of an event through the public API until none is
-- left. The better seed wins, so outcomes are predictable; p_upset makes the
-- losers-bracket champion win the first grand final. Returns the count.
create function t.play_out(p_event_id uuid, p_upset boolean default false) returns int language plpgsql security definer as $$
declare
  v_m record;
  v_ruleset text;
  v_count int := 0;
begin
  select ruleset_key into v_ruleset from app.tournament_events where id = p_event_id;
  loop
    select m.id, a.seed as seed_a, b.seed as seed_b,
           (p_upset and m.bracket = 'grand_final' and m.round_no = 1) as upset into v_m
    from app.matches m
    join app.stage_entrants a on a.stage_id = m.stage_id and a.entrant_id = m.side_a
    join app.stage_entrants b on b.stage_id = m.stage_id and b.entrant_id = m.side_b
    where m.event_id = p_event_id and m.status = 'ready'
    order by (select seq from app.event_stages s where s.id = m.stage_id), m.seq
    limit 1;
    exit when not found;
    perform public.org_match_score(v_m.id,
      t.winning_score(v_ruleset, case when v_m.upset then 'b'
                                      when v_m.seed_a < v_m.seed_b then 'a' else 'b' end), true);
    v_count := v_count + 1;
    if v_count > 2000 then raise exception 'play_out did not terminate'; end if;
  end loop;
  return v_count;
end $$;

-- A tournament with one event built from a template and N seeded entrants.
create function t.event(p_org uuid, p_sport text, p_ruleset text, p_stages jsonb, p_entrants int)
returns uuid language plpgsql security definer as $$
declare v_t uuid; v_e uuid;
begin
  v_t := (public.org_tournament_save(p_org, jsonb_build_object(
            'name', 'Test cup ' || substr(gen_random_uuid()::text, 1, 6), 'sport_code', p_sport,
            'starts_on', current_date + 7)) ->> 'id')::uuid;
  v_e := (public.org_event_save(v_t, jsonb_build_object(
            'name', 'Main event', 'ruleset_key', p_ruleset, 'stages', p_stages)) ->> 'id')::uuid;
  perform public.org_entrants_add(v_e, (
    select jsonb_agg(jsonb_build_object('name', 'Seed ' || i, 'seed', i)) from generate_series(1, p_entrants) i));
  return v_e;
end $$;

create function t.rank_of(p_event_id uuid, p_seed int) returns int language sql security definer as $$
  select final_rank from app.entrants where event_id = p_event_id and seed = p_seed;
$$;

grant usage on schema t to anon, authenticated;
grant execute on all functions in schema t to anon, authenticated;
