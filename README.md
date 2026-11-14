# Sidi

Sports centre management and tournaments for badminton, table tennis, cricket
and gyms. Flutter app, Supabase (Postgres) backend.

**Players** find organisations, book courts, tables, nets and gym slots, join
memberships and mentorships, follow their own progress, and enter tournaments.

**Organisations** apply to join, get approved and verified, then run their
facilities, front desk, members and mentees, coaches' progress reports, staff
and payroll, budget, and tournaments with draws, live scoring and posters.

**Platform staff** work an admin console inside the app: organisation
approvals, verification, feature-access requests, reports, roles, audit log.

## Architecture

```
lib/
  app/        composition root: DI, router, navigation shell, theme
  core/       Failure/Result, the RPC client, AsyncCubit, shared widgets
  features/<feature>/
    domain/        entities and repository contracts (pure Dart)
    data/          JSON mappers and repositories that call the RPCs
    presentation/  cubits, pages, widgets
supabase/     migrations, SQL tests, backend notes
```

Features: `auth`, `catalog`, `discover`, `booking`, `membership`,
`organization`, `finance`, `tournaments`, `admin`.

- **State** is flutter_bloc with Cubits. Most screens load one thing and run
  actions on it, so they extend `AsyncCubit<T>` (`core/bloc`): content stays
  on screen while refreshing, a failed action reports itself without
  replacing the content, a successful one reloads. Forms use `SubmitCubit`.
  `SessionCubit` and `CatalogCubit` live for the whole app.
- **Dependencies point inwards.** Cubits depend on repository interfaces from
  `domain`; `data` implements them over one small `Rpc` interface, which is
  what tests fake. Repositories return `Result<T>` and never throw. There is
  no use-case layer: the cubits call repositories directly, because every use
  case would be a one-line pass-through to an RPC that already holds the rule.
- **The backend owns the rules.** Authorisation, booking conflicts, pricing,
  scoring, pairing and standings all live in Postgres. The score sheet, for
  example, asks the server what a score means as you type instead of
  re-implementing each sport's laws on the client.

The backend's schema layout, security model and the tournament engine are
described in [`supabase/README.md`](supabase/README.md).

## Run

Apply the backend (see `supabase/README.md`), then:

```bash
flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

## Test

```bash
flutter analyze
```

```bash
flutter test
```

```bash
PGHOST=127.0.0.1 PGPORT=5432 supabase/tests/run.sh
```

## Not built yet

- **Online payments.** Booking, membership and entry fees are tracked as
  payments that the organisation marks as settled (cash, UPI, card, bank).
  `private.payment_settle` is the single place a payment changes state, so a
  gateway webhook can call it.
- **Live push.** Scores and bookings refresh on pull or when a screen opens;
  there are no realtime subscriptions.
- **Ball-by-ball cricket.** Cricket is scored per innings (runs, wickets,
  overs), not per delivery.
- **File pickers.** Logos and banners are stored as URLs; only exported
  posters are uploaded by the app.
