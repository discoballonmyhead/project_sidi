-- =============================================================================
-- 0014 · Public API: tournaments, events, entries, the draw, scoring, posters
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Guards: resolve the row, then check the caller manages its organisation
-- -----------------------------------------------------------------------------
create function private.require_tournament(p_tournament_id uuid)
returns app.tournaments language plpgsql stable set search_path = '' as $$
declare v_t app.tournaments;
begin
  select * into v_t from app.tournaments where id = p_tournament_id;
  if not found then
    perform private.fail(404, 'tournament_not_found', 'Tournament not found.');
  end if;
  perform private.require_org(v_t.org_id);
  return v_t;
end $$;

create function private.require_event(p_event_id uuid)
returns app.tournament_events language plpgsql stable set search_path = '' as $$
declare v_e app.tournament_events;
begin
  select * into v_e from app.tournament_events where id = p_event_id;
  if not found then
    perform private.fail(404, 'event_not_found', 'Event not found.');
  end if;
  perform private.require_org(v_e.org_id);
  return v_e;
end $$;

create function private.require_match(p_match_id uuid)
returns app.tournament_events language plpgsql stable set search_path = '' as $$
declare v_event uuid;
begin
  select event_id into v_event from app.matches where id = p_match_id;
  if v_event is null then
    perform private.fail(404, 'match_not_found', 'Match not found.');
  end if;
  return private.require_event(v_event);
end $$;

create function private.can_manage_tournament(p_org_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(private.org_role(p_org_id, auth.uid()) in ('owner', 'manager'), false);
$$;

-- -----------------------------------------------------------------------------
-- Browsing
-- -----------------------------------------------------------------------------
create function public.tournaments_search(
  p_query text default null, p_sport text default null, p_scope text default 'upcoming',
  p_limit int default 30, p_offset int default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.sort_key, q.name), '[]'::jsonb)
  from (
    select t.*,
           case when p_scope = 'past' then -extract(epoch from t.starts_on::timestamp)
                else extract(epoch from t.starts_on::timestamp) end as sort_key
    from app.v_tournaments t
    where case when p_scope = 'past' then t.status = 'completed'
               else t.status in ('open', 'closed', 'live') end
      and (private.clean(p_sport) is null or t.sport_code = p_sport)
      and (private.clean(p_query) is null
           or t.name ilike '%' || private.clean(p_query) || '%'
           or t.org_name ilike '%' || private.clean(p_query) || '%'
           or t.venue ilike '%' || private.clean(p_query) || '%')
    order by sort_key
    limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0)
  ) q;
$$;

create function public.tournament_detail(p_tournament_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_t      app.v_tournaments;
  v_manage boolean;
begin
  select * into v_t from app.v_tournaments where id = p_tournament_id;
  v_manage := found and private.can_manage_tournament(v_t.org_id);
  if not found or (v_t.status = 'draft' and not v_manage) then
    perform private.fail(404, 'tournament_not_found', 'Tournament not found.');
  end if;
  return jsonb_build_object(
    'tournament', to_jsonb(v_t),
    'can_manage', v_manage,
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'name', e.name, 'entrant_kind', e.entrant_kind, 'category', e.category,
               'ruleset_key', e.ruleset_key, 'ruleset_name', r.name, 'template_key', e.template_key,
               'entry_fee', e.entry_fee, 'max_entrants', e.max_entrants, 'status', e.status,
               'accepted_count', (select count(*) from app.entrants x where x.event_id = e.id and x.status = 'accepted'),
               'pending_count', case when v_manage then
                 (select count(*) from app.entrants x where x.event_id = e.id and x.status = 'pending') end,
               'stages', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', s.id, 'seq', s.seq, 'name', s.name, 'format_key', s.format_key,
                          'format_name', f.name, 'config', s.config, 'status', s.status) order by s.seq)
                 from app.event_stages s join app.stage_formats f on f.key = s.format_key
                 where s.event_id = e.id), '[]'::jsonb),
               'podium', coalesce((
                 select jsonb_agg(jsonb_build_object('rank', x.final_rank, 'name', x.name) order by x.final_rank)
                 from app.entrants x where x.event_id = e.id and x.final_rank <= 4), '[]'::jsonb),
               'my_entry', (
                 select jsonb_build_object('id', x.id, 'name', x.name, 'status', x.status, 'payment', x.payment)
                 from app.v_entrants x
                 where x.event_id = e.id and x.registered_by = v_uid
                 order by x.created_at desc limit 1))
             order by e.created_at)
      from app.tournament_events e join app.rulesets r on r.key = e.ruleset_key
      where e.tournament_id = p_tournament_id), '[]'::jsonb),
    'posters', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.created_at desc)
      from (select id, kind, template, title, payload, image_url, is_published, created_at
            from app.posters
            where tournament_id = p_tournament_id and (is_published or v_manage)) p), '[]'::jsonb));
end $$;

-- Everything needed to render one event: stages, tables, draws and results.
create function public.event_detail(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_e      app.tournament_events;
  v_t      app.tournaments;
  v_manage boolean;
begin
  select * into v_e from app.tournament_events where id = p_event_id;
  if found then
    select * into v_t from app.tournaments where id = v_e.tournament_id;
    v_manage := private.can_manage_tournament(v_e.org_id);
  end if;
  if v_e.id is null or (v_t.status = 'draft' and not v_manage) then
    perform private.fail(404, 'event_not_found', 'Event not found.');
  end if;
  return jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_e.id, 'tournament_id', v_e.tournament_id, 'tournament_name', v_t.name,
      'org_id', v_e.org_id, 'sport_code', v_t.sport_code, 'name', v_e.name, 'entrant_kind', v_e.entrant_kind,
      'category', v_e.category, 'entry_fee', v_e.entry_fee, 'max_entrants', v_e.max_entrants,
      'status', v_e.status, 'template_key', v_e.template_key,
      'currency', (select currency from app.organizations where id = v_e.org_id)),
    'ruleset', (select to_jsonb(r) from app.rulesets r where r.key = v_e.ruleset_key),
    'can_manage', v_manage,
    'entrants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'name', x.name, 'seed', x.seed, 'status', x.status,
               'final_rank', x.final_rank, 'members', x.members) order by x.seed nulls last, x.name)
      from app.v_entrants x where x.event_id = p_event_id and x.status = 'accepted'), '[]'::jsonb),
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'seq', s.seq, 'name', s.name, 'format_key', s.format_key,
               'format_name', f.name, 'config', s.config, 'status', s.status,
               'has_table', f.rank_fn = 'rank_standings',
               'standings', case when f.rank_fn = 'rank_standings' and s.status <> 'pending' then coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'entrant_id', st.entrant_id, 'name', en.name, 'group_name', g.name,
                          'position', st.position, 'played', st.played, 'won', st.won, 'lost', st.lost,
                          'tied', st.tied, 'drawn', st.drawn, 'no_result', st.no_result, 'points', st.points,
                          'sets_for', st.sets_for, 'sets_against', st.sets_against,
                          'score_for', st.score_for, 'score_against', st.score_against, 'nrr', st.nrr)
                        order by g.seq nulls first, st.position)
                 from private.stage_standings(s.id) st
                 join app.entrants en on en.id = st.entrant_id
                 left join app.stage_groups g on g.id = st.group_id), '[]'::jsonb) else '[]'::jsonb end,
               'matches', coalesce((
                 select jsonb_agg(to_jsonb(m) order by m.seq)
                 from app.v_matches m where m.stage_id = s.id), '[]'::jsonb))
             order by s.seq)
      from app.event_stages s join app.stage_formats f on f.key = s.format_key
      where s.event_id = p_event_id), '[]'::jsonb));
end $$;

-- Runs a score through a ruleset's engine without saving it: live validation
-- for the score sheet.
create function public.score_preview(p_ruleset_key text, p_score jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.uid();
  return private.score_match(p_ruleset_key, p_score, false);
end $$;

-- -----------------------------------------------------------------------------
-- Entering
-- -----------------------------------------------------------------------------
create function private.entrant_add_members(p_entrant_id uuid, p_members jsonb, p_captain uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if p_captain is not null then
    insert into app.entrant_members (entrant_id, user_id, name, is_captain)
    select p_entrant_id, p.id, p.display_name, true from app.profiles p where p.id = p_captain;
  end if;
  if jsonb_typeof(p_members) = 'array' then
    insert into app.entrant_members (entrant_id, user_id, name)
    select p_entrant_id,
           private.find_user(m ->> 'handle'),
           left(coalesce(private.clean(m ->> 'name'), private.clean(m #>> '{}'), 'Player'), 80)
    from jsonb_array_elements(p_members) m
    limit 30;
  end if;
end $$;

-- p_members: the caller's partner / team-mates, [{"name": "...", "handle": "@user"}]
create function public.event_register(
  p_event_id uuid, p_name text default null, p_members jsonb default '[]', p_contact text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := private.uid();
  v_e      app.tournament_events;
  v_t      app.tournaments;
  v_name   text;
  v_status text := 'pending';
  v_id     uuid;
begin
  select * into v_e from app.tournament_events where id = p_event_id for update;
  if found then
    select * into v_t from app.tournaments where id = v_e.tournament_id;
  end if;
  if v_e.id is null or v_t.status = 'draft' then
    perform private.fail(404, 'event_not_found', 'Event not found.');
  end if;
  if v_t.status <> 'open' or v_e.status <> 'setup'
     or (v_t.registration_closes_at is not null and v_t.registration_closes_at < now()) then
    perform private.fail(409, 'registration_closed', 'Registration for this event is closed.');
  end if;

  v_name := coalesce(private.clean(p_name), (select display_name from app.profiles where id = v_uid));
  if v_e.entrant_kind <> 'player' and private.clean(p_name) is null then
    perform private.fail(422, 'invalid_entry',
      case v_e.entrant_kind when 'pair' then 'Name your pair, for example "Rao / Mehta".' else 'Enter a team name.' end);
  end if;
  if v_e.max_entrants is not null and (
       select count(*) from app.entrants where event_id = p_event_id and status in ('pending', 'accepted')
     ) >= v_e.max_entrants then
    v_status := 'waitlisted';
  end if;

  begin
    insert into app.entrants (event_id, name, status, registered_by, contact)
    values (p_event_id, left(v_name, 80), v_status, v_uid, private.clean(p_contact))
    returning id into v_id;
  exception when unique_violation then
    perform private.fail(409, 'already_entered', 'You have already entered this event.');
  end;
  perform private.entrant_add_members(v_id, case when v_e.entrant_kind = 'player' then null else p_members end, v_uid);
  perform private.payment_open(v_e.org_id, v_uid, 'tournament_entry', v_id, v_e.entry_fee,
    format('%s · %s', v_t.name, v_e.name));
  perform private.notify_org(v_e.org_id, 'entry_received', 'New tournament entry',
    format('%s · %s', v_name, v_e.name), jsonb_build_object('tournament_id', v_t.id, 'event_id', v_e.id));
  return jsonb_build_object('id', v_id, 'status', v_status);
end $$;

create function public.entry_withdraw(p_entrant_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.uid();
  v_e   app.tournament_events;
begin
  select e.* into v_e
  from app.entrants en join app.tournament_events e on e.id = en.event_id
  where en.id = p_entrant_id and en.registered_by = v_uid and en.status in ('pending', 'accepted', 'waitlisted');
  if not found then
    perform private.fail(404, 'entry_not_found', 'Entry not found.');
  end if;
  if v_e.status <> 'setup' then
    perform private.fail(409, 'event_already_started',
      'The draw has been made. Ask the organiser to record a walkover instead.');
  end if;
  update app.entrants set status = 'withdrawn', decided_at = now() where id = p_entrant_id;
  perform private.payment_void_for('tournament_entry', p_entrant_id);
end $$;

create function public.my_entries()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', x.id, 'name', x.name, 'status', x.status, 'final_rank', x.final_rank, 'payment', x.payment,
             'event_id', e.id, 'event_name', e.name, 'event_status', e.status,
             'tournament_id', t.id, 'tournament_name', t.name, 'tournament_status', t.status,
             'sport_code', t.sport_code, 'starts_on', t.starts_on, 'org_name', t.org_name)
           order by t.starts_on desc)
    from app.v_entrants x
    join app.tournament_events e on e.id = x.event_id
    join app.v_tournaments t on t.id = e.tournament_id
    where x.registered_by = v_uid), '[]'::jsonb);
end $$;

-- -----------------------------------------------------------------------------
-- Hosting: tournaments and events
-- -----------------------------------------------------------------------------
create function public.org_tournaments(p_org_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.require_org(p_org_id, array['owner', 'manager', 'coach', 'staff']);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.starts_on desc)
    from app.v_tournaments t where t.org_id = p_org_id), '[]'::jsonb);
end $$;

create function public.org_tournament_save(p_org_id uuid, p_tournament jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_org(p_org_id);
  v_id  uuid := (p_tournament ->> 'id')::uuid;
begin
  perform private.require_feature(p_org_id, 'tournaments');
  if p_tournament ->> 'facility_id' is not null and not exists (
       select 1 from app.facilities where id = (p_tournament ->> 'facility_id')::uuid and org_id = p_org_id) then
    perform private.fail(404, 'facility_not_found', 'Facility not found.');
  end if;
  if v_id is null then
    insert into app.tournaments (org_id, sport_code, name, description, venue, facility_id, starts_on, ends_on,
                                 registration_closes_at, banner_url, rules, created_by)
    values (p_org_id, p_tournament ->> 'sport_code', private.clean(p_tournament ->> 'name'),
            private.clean(p_tournament ->> 'description'), private.clean(p_tournament ->> 'venue'),
            (p_tournament ->> 'facility_id')::uuid,
            (p_tournament ->> 'starts_on')::date,
            coalesce((p_tournament ->> 'ends_on')::date, (p_tournament ->> 'starts_on')::date),
            (p_tournament ->> 'registration_closes_at')::timestamptz,
            private.clean(p_tournament ->> 'banner_url'), private.clean(p_tournament ->> 'rules'), v_uid)
    returning id into v_id;
  else
    update app.tournaments
    set name = coalesce(private.clean(p_tournament ->> 'name'), name),
        description = case when p_tournament ? 'description' then private.clean(p_tournament ->> 'description') else description end,
        venue = case when p_tournament ? 'venue' then private.clean(p_tournament ->> 'venue') else venue end,
        facility_id = case when p_tournament ? 'facility_id' then (p_tournament ->> 'facility_id')::uuid else facility_id end,
        starts_on = coalesce((p_tournament ->> 'starts_on')::date, starts_on),
        ends_on = coalesce((p_tournament ->> 'ends_on')::date, ends_on),
        registration_closes_at = case when p_tournament ? 'registration_closes_at'
                                      then (p_tournament ->> 'registration_closes_at')::timestamptz
                                      else registration_closes_at end,
        banner_url = case when p_tournament ? 'banner_url' then private.clean(p_tournament ->> 'banner_url') else banner_url end,
        rules = case when p_tournament ? 'rules' then private.clean(p_tournament ->> 'rules') else rules end
    where id = v_id and org_id = p_org_id;
    if not found then
      perform private.fail(404, 'tournament_not_found', 'Tournament not found.');
    end if;
  end if;
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation or foreign_key_violation
            or invalid_text_representation or invalid_datetime_format then
  perform private.fail(422, 'invalid_tournament', 'Check the name, sport and dates (the end cannot be before the start).');
  return null;
end $$;

-- draft -> open <-> closed, and anything unfinished -> cancelled.
-- The engine moves a tournament to live and completed by itself.
create function public.org_tournament_set_status(p_tournament_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_t app.tournaments := private.require_tournament(p_tournament_id);
begin
  if (v_t.status, p_status) not in (
       ('draft', 'open'), ('open', 'closed'), ('closed', 'open'), ('open', 'draft'),
       ('draft', 'cancelled'), ('open', 'cancelled'), ('closed', 'cancelled'), ('live', 'cancelled')) then
    perform private.fail(409, 'invalid_transition',
      format('A %s tournament cannot be moved to %s.', v_t.status, p_status));
  end if;
  if p_status = 'open' and not exists (select 1 from app.tournament_events where tournament_id = p_tournament_id) then
    perform private.fail(422, 'no_events', 'Add at least one event before publishing.');
  end if;
  if p_status = 'draft' and exists (
       select 1 from app.entrants en join app.tournament_events e on e.id = en.event_id
       where e.tournament_id = p_tournament_id and en.registered_by is not null
         and en.status in ('pending', 'accepted', 'waitlisted')) then
    perform private.fail(409, 'has_entries', 'People have already entered. Close registration or cancel instead.');
  end if;
  update app.tournaments set status = p_status where id = p_tournament_id;
  perform private.audit('tournament.' || p_status, 'tournament', p_tournament_id);
end $$;

-- Creates or updates an event and its stage pipeline.
-- p_event.stages: [{"name": "Groups", "format": "round_robin", "config": {"groups": 4}}, ...]
-- When stages are omitted they are copied from the chosen template.
create function public.org_event_save(p_tournament_id uuid, p_event jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_t       app.tournaments := private.require_tournament(p_tournament_id);
  v_id      uuid := (p_event ->> 'id')::uuid;
  v_e       app.tournament_events;
  v_ruleset app.rulesets;
  v_stages  jsonb := p_event -> 'stages';
  v_fee     numeric := coalesce((p_event ->> 'entry_fee')::numeric, 0);
begin
  if v_t.status in ('completed', 'cancelled') then
    perform private.fail(409, 'tournament_closed', 'This tournament is finished.');
  end if;
  if v_id is not null then
    select * into v_e from app.tournament_events where id = v_id and tournament_id = p_tournament_id;
    if not found then
      perform private.fail(404, 'event_not_found', 'Event not found.');
    end if;
    if v_e.status <> 'setup' then
      perform private.fail(409, 'event_already_started', 'The draw has been made. Reset the event to change it.');
    end if;
  end if;

  select * into v_ruleset from app.rulesets where key = coalesce(p_event ->> 'ruleset_key', v_e.ruleset_key);
  if not found or v_ruleset.sport_code <> v_t.sport_code then
    perform private.fail(422, 'invalid_ruleset', 'Pick a ruleset for this tournament''s sport.');
  end if;
  if (p_event ? 'entry_fee' or v_id is null) and v_fee > 0 then
    perform private.require_feature(v_t.org_id, 'paid_entries');
  end if;

  if v_stages is null and v_id is null then
    select stages into v_stages from app.format_templates where key = p_event ->> 'template_key';
  end if;
  if v_stages is not null then
    if jsonb_typeof(v_stages) <> 'array' or jsonb_array_length(v_stages) not between 1 and 6 then
      perform private.fail(422, 'invalid_stages', 'An event has between one and six stages.');
    end if;
    if exists (select 1 from jsonb_array_elements(v_stages) s
               where not exists (select 1 from app.stage_formats f where f.key = s ->> 'format')) then
      perform private.fail(422, 'invalid_stages', 'Unknown stage format.');
    end if;
  elsif v_id is null then
    perform private.fail(422, 'invalid_stages', 'Pick a format template or define the stages.');
  end if;

  if v_id is null then
    insert into app.tournament_events (tournament_id, org_id, name, entrant_kind, category, ruleset_key,
                                       template_key, entry_fee, max_entrants)
    values (p_tournament_id, v_t.org_id, private.clean(p_event ->> 'name'),
            coalesce(p_event ->> 'entrant_kind', case when v_ruleset.is_team then 'team' else 'player' end),
            coalesce(p_event ->> 'category', 'open'), v_ruleset.key, p_event ->> 'template_key',
            v_fee, (p_event ->> 'max_entrants')::int)
    returning id into v_id;
  else
    update app.tournament_events
    set name = coalesce(private.clean(p_event ->> 'name'), name),
        entrant_kind = coalesce(p_event ->> 'entrant_kind', entrant_kind),
        category = coalesce(p_event ->> 'category', category),
        ruleset_key = v_ruleset.key,
        template_key = case when p_event ? 'template_key' then p_event ->> 'template_key' else template_key end,
        entry_fee = case when p_event ? 'entry_fee' then v_fee else entry_fee end,
        max_entrants = case when p_event ? 'max_entrants' then (p_event ->> 'max_entrants')::int else max_entrants end
    where id = v_id;
  end if;

  if v_stages is not null then
    delete from app.event_stages where event_id = v_id;
    insert into app.event_stages (event_id, seq, name, format_key, config)
    select v_id, s.ord, coalesce(private.clean(s.value ->> 'name'), 'Stage ' || s.ord),
           s.value ->> 'format', coalesce(s.value -> 'config', '{}'::jsonb)
    from jsonb_array_elements(v_stages) with ordinality s (value, ord);
  end if;
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation or foreign_key_violation or invalid_text_representation then
  perform private.fail(422, 'invalid_event', 'Check the event name, entrant type, category and entrant limit.');
  return null;
end $$;

create function public.org_event_delete(p_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events := private.require_event(p_event_id);
begin
  if v_e.status <> 'setup' then
    perform private.fail(409, 'event_already_started', 'Reset the event before deleting it.');
  end if;
  update app.payments set status = 'void'
  where purpose = 'tournament_entry' and status = 'pending'
    and ref_id in (select id from app.entrants where event_id = p_event_id);
  delete from app.tournament_events where id = p_event_id;
end $$;

-- -----------------------------------------------------------------------------
-- Hosting: entrants
-- -----------------------------------------------------------------------------
create function public.org_event_entrants(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_e app.tournament_events := private.require_event(p_event_id);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(x) || jsonb_build_object(
             'registered_by_name', (select display_name from app.profiles where id = x.registered_by))
           order by array_position(array['pending', 'waitlisted', 'accepted', 'rejected', 'withdrawn'], x.status),
                    x.seed nulls last, x.created_at)
    from app.v_entrants x where x.event_id = p_event_id), '[]'::jsonb);
end $$;

-- Adds entrants straight into the field (walk-ups, invited teams, imports).
-- p_entrants: [{"name": "Riverside CC", "seed": 1, "members": ["A", "B"]}] or ["Name", ...]
create function public.org_entrants_add(p_event_id uuid, p_entrants jsonb)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_e     app.tournament_events := private.require_event(p_event_id);
  v_item  jsonb;
  v_name  text;
  v_id    uuid;
  v_count int := 0;
begin
  if v_e.status <> 'setup' then
    perform private.fail(409, 'event_already_started', 'The draw has been made. Reset the event to add entrants.');
  end if;
  if jsonb_typeof(p_entrants) <> 'array' or jsonb_array_length(p_entrants) not between 1 and 256 then
    perform private.fail(422, 'invalid_entrants', 'Add between 1 and 256 entrants at a time.');
  end if;
  for v_item in select value from jsonb_array_elements(p_entrants) loop
    v_name := private.clean(case when jsonb_typeof(v_item) = 'object' then v_item ->> 'name' else v_item #>> '{}' end);
    continue when v_name is null;
    insert into app.entrants (event_id, name, seed, status, decided_at)
    values (p_event_id, left(v_name, 80),
            case when jsonb_typeof(v_item) = 'object' then (v_item ->> 'seed')::int end, 'accepted', now())
    returning id into v_id;
    if jsonb_typeof(v_item) = 'object' then
      perform private.entrant_add_members(v_id, v_item -> 'members', null);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Accept, wait-list or reject an entry.
create function public.org_entrant_decide(p_entrant_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_en app.entrants;
  v_e  app.tournament_events;
begin
  select * into v_en from app.entrants where id = p_entrant_id;
  if not found then
    perform private.fail(404, 'entry_not_found', 'Entry not found.');
  end if;
  v_e := private.require_event(v_en.event_id);
  if p_status not in ('accepted', 'waitlisted', 'rejected', 'pending') then
    perform private.fail(422, 'invalid_status', 'Unknown entry status.');
  end if;
  if v_e.status <> 'setup' then
    perform private.fail(409, 'event_already_started', 'The draw has been made. Reset the event to change the field.');
  end if;
  if p_status = 'accepted' and v_e.max_entrants is not null and (
       select count(*) from app.entrants
       where event_id = v_e.id and status = 'accepted' and id <> p_entrant_id) >= v_e.max_entrants then
    perform private.fail(409, 'event_full', format('This event is limited to %s entrants.', v_e.max_entrants));
  end if;
  update app.entrants set status = p_status, decided_at = now() where id = p_entrant_id;
  if p_status = 'rejected' then
    perform private.payment_void_for('tournament_entry', p_entrant_id);
  end if;
  perform private.notify(v_en.registered_by, 'entry_' || p_status, 'Entry ' || p_status,
    format('%s · %s', (select name from app.tournaments where id = v_e.tournament_id), v_e.name),
    jsonb_build_object('tournament_id', v_e.tournament_id, 'event_id', v_e.id));
end $$;

-- Rename or (re)seed an entrant; a null seed clears it.
create function public.org_entrant_update(p_entrant_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events;
begin
  v_e := private.require_event((select event_id from app.entrants where id = p_entrant_id));
  if v_e.status <> 'setup' and p_patch ? 'seed' then
    perform private.fail(409, 'event_already_started', 'Seeds are fixed once the draw is made.');
  end if;
  update app.entrants
  set name = coalesce(private.clean(p_patch ->> 'name'), name),
      seed = case when p_patch ? 'seed' then (p_patch ->> 'seed')::int else seed end
  where id = p_entrant_id;
exception when check_violation or invalid_text_representation then
  perform private.fail(422, 'invalid_entry', 'Seeds are whole numbers from 1.');
end $$;

create function public.org_entrant_remove(p_entrant_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events;
begin
  v_e := private.require_event((select event_id from app.entrants where id = p_entrant_id));
  if v_e.status <> 'setup' then
    perform private.fail(409, 'event_already_started', 'The draw has been made. Record a walkover instead.');
  end if;
  perform private.payment_void_for('tournament_entry', p_entrant_id);
  delete from app.entrants where id = p_entrant_id;
end $$;

-- -----------------------------------------------------------------------------
-- Hosting: running the event
-- -----------------------------------------------------------------------------
create function public.org_event_start(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_e       app.tournament_events := private.require_event(p_event_id);
  v_created int;
begin
  if (select status from app.tournaments where id = v_e.tournament_id) in ('completed', 'cancelled') then
    perform private.fail(409, 'tournament_closed', 'This tournament is finished.');
  end if;
  v_created := private.event_start(p_event_id);
  perform private.audit('event.started', 'event', p_event_id, jsonb_build_object('matches', v_created));
  return jsonb_build_object('matches', v_created);
end $$;

create function public.org_event_reset(p_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events := private.require_event(p_event_id);
begin
  perform private.event_reset(p_event_id);
  perform private.audit('event.reset', 'event', p_event_id);
end $$;

create function public.org_match_score(p_match_id uuid, p_score jsonb, p_final boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events := private.require_match(p_match_id);
begin
  perform private.match_record(p_match_id, coalesce(p_score, '{}'::jsonb), coalesce(p_final, false));
  return (select to_jsonb(m) from app.v_matches m where m.id = p_match_id);
end $$;

create function public.org_match_walkover(p_match_id uuid, p_winner_side text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events := private.require_match(p_match_id);
begin
  perform private.match_walkover(p_match_id, p_winner_side);
end $$;

create function public.org_match_reopen(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_e app.tournament_events := private.require_match(p_match_id);
begin
  perform private.match_reopen(p_match_id);
  perform private.audit('match.reopened', 'match', p_match_id);
end $$;

-- Puts a match on a court at a time (and blocks the court for customers).
-- A null resource clears the schedule.
create function public.org_match_schedule(
  p_match_id uuid, p_resource_id uuid, p_starts_at timestamptz, p_minutes int default 60)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_e       app.tournament_events := private.require_match(p_match_id);
  v_m       app.matches;
  v_booking uuid;
begin
  select * into v_m from app.matches where id = p_match_id for update;
  if v_m.status in ('completed', 'walkover', 'bye', 'cancelled') then
    perform private.fail(409, 'match_already_final', 'This match is already over.');
  end if;
  update app.matches set booking_id = null, resource_id = null, scheduled_at = null where id = p_match_id;
  delete from app.bookings where id = v_m.booking_id;

  if p_resource_id is null then
    update app.matches set scheduled_at = p_starts_at where id = p_match_id;
    return;
  end if;
  if not exists (select 1 from app.resources where id = p_resource_id and org_id = v_e.org_id) then
    perform private.fail(404, 'resource_not_found', 'Resource not found.');
  end if;
  if p_starts_at is null or coalesce(p_minutes, 0) not between 5 and 720 then
    perform private.fail(422, 'invalid_schedule', 'Pick a start time and a length between 5 minutes and 12 hours.');
  end if;
  v_booking := private.booking_place(p_resource_id, p_starts_at, 1, null,
    v_e.name || ' · ' || v_m.label, 'tournament', null, 0, auth.uid(), p_minutes);
  update app.matches
  set booking_id = v_booking, resource_id = p_resource_id, scheduled_at = p_starts_at
  where id = p_match_id;
end $$;

-- Lays the unscheduled matches of a stage across courts, round by round, so
-- no side is asked to play two matches at once. Busy courts are skipped.
create function public.org_stage_auto_schedule(
  p_stage_id uuid, p_resource_ids uuid[], p_starts_at timestamptz,
  p_match_minutes int default 45, p_gap_minutes int default 5)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_e       app.tournament_events;
  v_cursors timestamptz[];
  v_n       int := coalesce(cardinality(p_resource_ids), 0);
  v_m       record;
  v_level   text := '';
  v_idx     int;
  v_at      timestamptz;
  v_booking uuid;
  v_count   int := 0;
begin
  v_e := private.require_event((select event_id from app.event_stages where id = p_stage_id));
  if v_n not between 1 and 40 or p_starts_at is null
     or coalesce(p_match_minutes, 0) not between 5 and 720 or coalesce(p_gap_minutes, -1) not between 0 and 240 then
    perform private.fail(422, 'invalid_schedule', 'Pick courts, a start time and a match length.');
  end if;
  if (select count(*) from app.resources where id = any (p_resource_ids) and org_id = v_e.org_id) <> v_n then
    perform private.fail(404, 'resource_not_found', 'Every court must belong to this organisation.');
  end if;
  v_cursors := array_fill(p_starts_at, array[v_n]);

  for v_m in
    with recursive depth as (
      select m.id, 1 as d from app.matches m
      where m.stage_id = p_stage_id and m.a_source_match is null and m.b_source_match is null
      union all
      select m.id, depth.d + 1 from app.matches m
      join depth on depth.id in (m.a_source_match, m.b_source_match)
      where m.stage_id = p_stage_id
    )
    select m.id, m.label, (select max(d) from depth where depth.id = m.id) as d, m.round_no
    from app.matches m
    where m.stage_id = p_stage_id and m.status in ('pending', 'ready') and m.booking_id is null
    order by 3, m.round_no, m.seq
  loop
    -- A new round starts only when every court has finished the previous one.
    if v_level <> v_m.d || '/' || v_m.round_no then
      v_level := v_m.d || '/' || v_m.round_no;
      v_cursors := array_fill((select max(c) from unnest(v_cursors) c), array[v_n]);
    end if;
    select i into v_idx from generate_subscripts(v_cursors, 1) i order by v_cursors[i], i limit 1;
    v_at := v_cursors[v_idx];
    v_booking := null;
    for v_try in 1..200 loop
      begin
        v_booking := private.booking_place(p_resource_ids[v_idx], v_at, 1, null,
          v_e.name || ' · ' || v_m.label, 'tournament', null, 0, auth.uid(), p_match_minutes);
        exit;
      exception when sqlstate 'PT409' then
        v_at := v_at + make_interval(mins => p_match_minutes);
      end;
    end loop;
    if v_booking is null then
      perform private.fail(409, 'no_free_time', 'Could not find free court time. Try a later start or more courts.');
    end if;
    update app.matches
    set booking_id = v_booking, resource_id = p_resource_ids[v_idx], scheduled_at = v_at
    where id = v_m.id;
    v_cursors[v_idx] := v_at + make_interval(mins => p_match_minutes + p_gap_minutes);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- -----------------------------------------------------------------------------
-- Posters
-- -----------------------------------------------------------------------------
create function public.org_poster_save(p_tournament_id uuid, p_poster jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_t  app.tournaments := private.require_tournament(p_tournament_id);
  v_id uuid := (p_poster ->> 'id')::uuid;
begin
  if v_id is null then
    insert into app.posters (org_id, tournament_id, kind, template, title, payload, image_url, is_published, created_by)
    values (v_t.org_id, v_t.id, coalesce(p_poster ->> 'kind', 'promotion'),
            coalesce(private.clean(p_poster ->> 'template'), 'spotlight'),
            coalesce(private.clean(p_poster ->> 'title'), v_t.name),
            coalesce(p_poster -> 'payload', '{}'::jsonb), private.clean(p_poster ->> 'image_url'),
            coalesce((p_poster ->> 'is_published')::boolean, false), auth.uid())
    returning id into v_id;
  else
    update app.posters
    set kind = coalesce(p_poster ->> 'kind', kind),
        template = coalesce(private.clean(p_poster ->> 'template'), template),
        title = coalesce(private.clean(p_poster ->> 'title'), title),
        payload = coalesce(p_poster -> 'payload', payload),
        image_url = case when p_poster ? 'image_url' then private.clean(p_poster ->> 'image_url') else image_url end,
        is_published = coalesce((p_poster ->> 'is_published')::boolean, is_published)
    where id = v_id and tournament_id = p_tournament_id;
    if not found then
      perform private.fail(404, 'poster_not_found', 'Poster not found.');
    end if;
  end if;
  return jsonb_build_object('id', v_id);
exception when check_violation then
  perform private.fail(422, 'invalid_poster', 'Give the poster a title and pick promotion or winner.');
  return null;
end $$;

create function public.org_poster_delete(p_poster_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_tournament((select tournament_id from app.posters where id = p_poster_id));
  delete from app.posters where id = p_poster_id;
end $$;
