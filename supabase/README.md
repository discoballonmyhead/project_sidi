# Backend

Postgres on Supabase. The app never touches a table: it calls RPCs.

## Layout

| Schema    | Holds                                                   | Who can reach it            |
|-----------|---------------------------------------------------------|-----------------------------|
| `app`     | Tables and the `v_*` read-model views                   | Nobody through the API      |
| `private` | Guards, domain logic, the tournament engine             | Nobody through the API      |
| `public`  | The API: `SECURITY DEFINER` RPCs with `search_path = ''`| `authenticated`, a few `anon` |

Every public RPC authenticates the caller (`private.uid()`), authorises the
action (`private.require_org`, `private.require_staff`, `private.require_feature`)
and only then touches data. API roles have no table privileges, and row level
security is enabled with no policies on every table as a second barrier.

Errors are raised with `PTxxx` SQLSTATEs, which PostgREST turns into HTTP
status `xxx`. `message` is a stable slug (`slot_taken`), `details` the text
shown to the user.

Times an organisation enters (walk-ins, closures, match schedules, entry
deadlines) are wall-clock times at its venue and are converted with the
organisation's time zone. Read models return a `*_local` twin for every
venue time so the app shows the same clock on any device.

## Migrations

| File | Contents |
|------|----------|
| `0100_foundation` | Schemas, default privileges, errors, profiles, platform roles, audit log, notifications |
| `0200_organizations` | Organisations, team roles, features, the moderation queue |
| `0300_facilities_bookings` | Facilities, resources, opening hours, bookings (no-overlap exclusion constraint) |
| `0400_memberships_performance` | Plans, memberships, sessions, metrics, reports, the journey read model |
| `0500_finance` | Payments, employees, payroll, ledger, recurring costs, the budget dashboard |
| `0600_tournaments` | Engine registries, tournaments, events, stages, entrants, matches, posters |
| `0700_engine_scoring` | Scoring engines |
| `0800_engine_pairing` | Pairing, standings, ranking, stage progression |
| `0900_catalog` | Sports, features, rulesets, stage formats, format templates, metrics |
| `1000`-`1500_api_*` | The public RPCs, by domain |
| `1600_grants_storage` | Final lock-down, grants, the `media` storage bucket |

## The tournament engine

An event is an ordered list of stages. Each stage names a format, and the
format names the functions that run it, so the pipeline is data:

```
ruleset      -> scoring engine   private.score_*(config, score, final) -> result
stage format -> pairing engine   private.pair_*(stage_id)              -> matches created
             -> ranking engine   private.rank_*(stage_id)
stage config -> advancement      who qualifies for the next stage, and how they are seeded
```

`private.match_record` validates a score with the ruleset's engine;
`private.match_close` stores the result, feeds winners and losers into the
matches waiting on them and calls `private.stage_progress`, which either
lets the pairing engine add a round (Swiss), or ranks the stage, seeds the
next one and starts it.

To add a format: write `private.pair_<name>(uuid) returns int`, pick or write
a ranking function, insert a row in `app.stage_formats`. To add a ruleset for
an existing scoring engine, insert a row in `app.rulesets`. Templates such as
"ICC T20 World Cup" are rows in `app.format_templates`.

Scoring engines: `rally_games` (badminton, table tennis), `team_tie` (Thomas,
Uber and Sudirman Cup, ITTF team events), `cricket_limited` (T20, ODI, T10,
100-ball; DLS targets, Super Overs, net run rate), `cricket_multi` (Tests and
first-class: declarations, follow-on, innings victories, draws).

Stage formats: round robin (leagues, snake-seeded groups, home and away),
knockout (seeded, byes, third-place match), double elimination (with
grand-final reset), Swiss, page playoff, series.

## Running it

```bash
supabase link --project-ref <ref>
```

```bash
supabase db push
```

Make the first platform admin once, in the SQL editor:

```sql
insert into app.platform_roles (user_id, role)
select id, 'admin' from auth.users where email = 'you@example.com';
```

## Tests

`tests/run.sh` builds the schema on a scratch database of any Postgres 16
(a small stub stands in for Supabase's `auth` schema and roles) and runs the
suite. The tests call the public RPCs as the `authenticated` role, the way
PostgREST does, and play whole tournaments through every format.

```bash
PGHOST=127.0.0.1 PGPORT=5432 supabase/tests/run.sh
```
