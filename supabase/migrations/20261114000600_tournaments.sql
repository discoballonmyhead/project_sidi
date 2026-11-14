-- =============================================================================
-- 0006 · Tournaments: engine registries, tournaments, events, stages, matches
--
-- The competition engine is a pipeline of interchangeable parts, selected by
-- data rather than by code paths:
--
--   ruleset        -> scoring engine   how a score becomes a result
--   stage format   -> pairing engine   which matches exist, and when
--                  -> ranking engine   how a finished stage is ordered
--   stage config   -> advancement      who moves on to the next stage
--
-- An event is an ordered list of stages, so single-stage (a knockout),
-- two-stage (groups then knockout) and longer formats (groups, Super 8,
-- knockout) are the same thing with a different number of rows.
-- Adding a format means writing one private function and inserting one row.
-- =============================================================================

create table app.scoring_engines (
  kind        text primary key,
  fn          text not null,          -- private.<fn>(config jsonb, score jsonb, final boolean) returns jsonb
  name        text not null,
  description text not null
);

create table app.rulesets (
  key            text primary key,
  sport_code     text not null references app.sports (code),
  name           text not null,
  governing_body text,
  description    text not null,
  scoring_kind   text not null references app.scoring_engines (kind),
  config         jsonb not null default '{}',
  -- League points per outcome and the ordered tie-break chain for tables.
  points         jsonb not null default '{"win": 1, "loss": 0}',
  tiebreakers    jsonb not null default '["points", "h2h_points", "set_diff", "score_diff"]',
  is_team        boolean not null default false,
  sort_order     int not null default 0
);

create table app.stage_formats (
  key          text primary key,
  name         text not null,
  description  text not null,
  pair_fn      text not null,         -- private.<fn>(stage_id uuid) returns int (matches created)
  rank_fn      text not null,         -- private.<fn>(stage_id uuid) returns void
  needs_winner boolean not null default false,   -- knockout: ties and draws are not a result
  incremental  boolean not null default false,   -- pairs one round at a time (Swiss)
  options      jsonb not null default '[]',      -- config fields the UI offers
  sort_order   int not null default 0
);

-- Named presets: how international bodies actually run their events.
create table app.format_templates (
  key            text primary key,
  sport_code     text references app.sports (code),
  name           text not null,
  governing_body text,
  description    text not null,
  ruleset_key    text references app.rulesets (key),
  stages         jsonb not null,       -- [{name, format, config}]
  sort_order     int not null default 0
);

create table app.tournaments (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references app.organizations (id) on delete cascade,
  sport_code             text not null references app.sports (code),
  name                   text not null check (char_length(name) between 3 and 100),
  description            text check (char_length(description) <= 4000),
  venue                  text,
  facility_id            uuid references app.facilities (id) on delete set null,
  starts_on              date not null,
  ends_on                date not null,
  registration_closes_at timestamptz,
  status                 text not null default 'draft'
                         check (status in ('draft', 'open', 'closed', 'live', 'completed', 'cancelled')),
  banner_url             text,
  rules                  text check (char_length(rules) <= 8000),
  created_by             uuid references app.profiles (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (starts_on <= ends_on)
);
create index tournaments_org_idx on app.tournaments (org_id);
create index tournaments_browse_idx on app.tournaments (status, starts_on);
create trigger tournaments_touch before update on app.tournaments
  for each row execute function private.touch_updated_at();

-- A competition inside a tournament: "Men's singles", "U17 doubles", "T20 cup".
create table app.tournament_events (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references app.tournaments (id) on delete cascade,
  org_id        uuid not null references app.organizations (id) on delete cascade,
  name          text not null check (char_length(name) between 2 and 80),
  entrant_kind  text not null default 'player' check (entrant_kind in ('player', 'pair', 'team')),
  category      text not null default 'open' check (category in ('open', 'men', 'women', 'mixed', 'junior')),
  ruleset_key   text not null references app.rulesets (key),
  template_key  text references app.format_templates (key),
  entry_fee     numeric(10, 2) not null default 0 check (entry_fee >= 0),
  max_entrants  int check (max_entrants >= 2),
  status        text not null default 'setup' check (status in ('setup', 'live', 'completed')),
  created_at    timestamptz not null default now()
);
create index tournament_events_tournament_idx on app.tournament_events (tournament_id);

create table app.event_stages (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references app.tournament_events (id) on delete cascade,
  seq        int  not null check (seq >= 1),
  name       text not null,
  format_key text not null references app.stage_formats (key),
  config     jsonb not null default '{}',
  status     text not null default 'pending' check (status in ('pending', 'live', 'completed')),
  unique (event_id, seq)
);

create table app.stage_groups (
  id       uuid primary key default gen_random_uuid(),
  stage_id uuid not null references app.event_stages (id) on delete cascade,
  seq      int  not null,
  name     text not null,
  unique (stage_id, seq)
);

-- A player, pair or team entered in an event.
create table app.entrants (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references app.tournament_events (id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 80),
  seed          int check (seed >= 1),
  status        text not null default 'pending'
                check (status in ('pending', 'accepted', 'waitlisted', 'rejected', 'withdrawn')),
  registered_by uuid references app.profiles (id) on delete set null,
  contact       text,
  final_rank    int,
  decided_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index entrants_event_idx on app.entrants (event_id, status);
create unique index entrants_one_per_user_idx on app.entrants (event_id, registered_by)
  where registered_by is not null and status in ('pending', 'accepted', 'waitlisted');

create table app.entrant_members (
  id         uuid primary key default gen_random_uuid(),
  entrant_id uuid not null references app.entrants (id) on delete cascade,
  user_id    uuid references app.profiles (id) on delete set null,
  name       text not null check (char_length(name) between 1 and 80),
  is_captain boolean not null default false
);
create index entrant_members_idx on app.entrant_members (entrant_id);

create table app.stage_entrants (
  stage_id   uuid not null references app.event_stages (id) on delete cascade,
  entrant_id uuid not null references app.entrants (id) on delete cascade,
  group_id   uuid references app.stage_groups (id) on delete set null,
  seed       int  not null,
  group_rank int,
  final_rank int,
  primary key (stage_id, entrant_id)
);

create table app.matches (
  id               uuid primary key default gen_random_uuid(),
  event_id         uuid not null references app.tournament_events (id) on delete cascade,
  stage_id         uuid not null references app.event_stages (id) on delete cascade,
  group_id         uuid references app.stage_groups (id) on delete set null,
  seq              int  not null,     -- creation order inside the stage
  bracket          text not null default 'main'
                   check (bracket in ('main', 'winners', 'losers', 'grand_final', 'third_place', 'playoff')),
  round_no         int  not null,
  match_no         int  not null,
  label            text not null,
  side_a           uuid references app.entrants (id) on delete set null,
  side_b           uuid references app.entrants (id) on delete set null,
  -- Bracket wiring: a side can be "the winner / loser of that match".
  a_source_match   uuid references app.matches (id) on delete set null,
  a_source_outcome text check (a_source_outcome in ('winner', 'loser')),
  b_source_match   uuid references app.matches (id) on delete set null,
  b_source_outcome text check (b_source_outcome in ('winner', 'loser')),
  status           text not null default 'pending'
                   check (status in ('pending', 'ready', 'live', 'completed', 'walkover', 'bye', 'cancelled')),
  score            jsonb not null default '{}',   -- raw input, shape owned by the scoring engine
  result           jsonb,                         -- normalised output of the scoring engine
  outcome          text check (outcome in ('win', 'tie', 'draw', 'no_result')),
  winner_id        uuid references app.entrants (id) on delete set null,
  loser_id         uuid references app.entrants (id) on delete set null,
  scheduled_at     timestamptz,
  resource_id      uuid references app.resources (id) on delete set null,
  booking_id       uuid references app.bookings (id) on delete set null,
  meta             jsonb not null default '{}',
  completed_at     timestamptz,
  updated_at       timestamptz not null default now(),
  unique (stage_id, seq),
  unique (stage_id, bracket, round_no, match_no)
);
create index matches_event_idx on app.matches (event_id);
create index matches_a_source_idx on app.matches (a_source_match);
create index matches_b_source_idx on app.matches (b_source_match);
create trigger matches_touch before update on app.matches
  for each row execute function private.touch_updated_at();

-- Promotion and winner posters designed in the manage section.
create table app.posters (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references app.organizations (id) on delete cascade,
  tournament_id uuid not null references app.tournaments (id) on delete cascade,
  kind          text not null default 'promotion' check (kind in ('promotion', 'winner')),
  template      text not null default 'spotlight',
  title         text not null check (char_length(title) between 1 and 120),
  payload       jsonb not null default '{}',   -- headline, lines, palette, winners...
  image_url     text,
  is_published  boolean not null default false,
  created_by    uuid references app.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index posters_tournament_idx on app.posters (tournament_id);
create trigger posters_touch before update on app.posters
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Read models
-- -----------------------------------------------------------------------------
create view app.v_tournaments as
select t.id, t.org_id, t.sport_code, t.name, t.description, t.venue, t.facility_id,
       t.starts_on, t.ends_on, t.registration_closes_at, t.status, t.banner_url, t.rules,
       t.created_at,
       t.registration_closes_at at time zone o.timezone as registration_closes_local,
       (t.status = 'open' and (t.registration_closes_at is null or t.registration_closes_at > now())) as registration_open,
       o.name as org_name, o.is_verified as org_is_verified, o.logo_url as org_logo_url,
       o.currency, o.city as org_city,
       f.name as facility_name,
       (select count(*)::int from app.tournament_events e where e.tournament_id = t.id) as event_count,
       (select count(*)::int from app.entrants en
        join app.tournament_events e on e.id = en.event_id
        where e.tournament_id = t.id and en.status = 'accepted') as entrant_count,
       (select min(e.entry_fee) from app.tournament_events e where e.tournament_id = t.id) as min_entry_fee
from app.tournaments t
join app.organizations o on o.id = t.org_id
left join app.facilities f on f.id = t.facility_id;

create view app.v_entrants as
select en.id, en.event_id, en.name, en.seed, en.status, en.registered_by, en.contact,
       en.final_rank, en.created_at, en.decided_at,
       coalesce((select jsonb_agg(jsonb_build_object(
                   'id', m.id, 'name', m.name, 'user_id', m.user_id, 'is_captain', m.is_captain)
                 order by m.is_captain desc, m.name)
                 from app.entrant_members m where m.entrant_id = en.id), '[]'::jsonb) as members,
       (select jsonb_build_object('id', p.id, 'status', p.status, 'amount', p.amount,
                                  'currency', p.currency, 'method', p.method)
        from app.payments p
        where p.purpose = 'tournament_entry' and p.ref_id = en.id
        order by p.created_at desc limit 1) as payment
from app.entrants en;

create view app.v_matches as
select m.id, m.event_id, m.stage_id, m.group_id, m.seq, m.bracket, m.round_no, m.match_no,
       m.label, m.status, m.score, m.result, m.outcome, m.winner_id, m.loser_id,
       m.side_a, m.side_b, a.name as side_a_name, b.name as side_b_name,
       a.seed as side_a_seed, b.seed as side_b_seed,
       case when m.side_a is null and m.a_source_match is not null
            then initcap(m.a_source_outcome) || ' of ' || sa.label end as side_a_placeholder,
       case when m.side_b is null and m.b_source_match is not null
            then initcap(m.b_source_outcome) || ' of ' || sb.label end as side_b_placeholder,
       m.scheduled_at, m.scheduled_at at time zone o.timezone as scheduled_local,
       m.resource_id, r.name as resource_name, m.completed_at,
       g.name as group_name, s.name as stage_name, s.seq as stage_seq, s.format_key
from app.matches m
join app.event_stages s on s.id = m.stage_id
join app.tournament_events te on te.id = m.event_id
join app.organizations o on o.id = te.org_id
left join app.entrants a on a.id = m.side_a
left join app.entrants b on b.id = m.side_b
left join app.matches sa on sa.id = m.a_source_match
left join app.matches sb on sb.id = m.b_source_match
left join app.stage_groups g on g.id = m.group_id
left join app.resources r on r.id = m.resource_id;
