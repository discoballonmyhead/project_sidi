#!/usr/bin/env bash
# Builds the backend on a scratch database and runs the SQL test suite.
#   PGHOST / PGPORT / PGUSER select the server (defaults: local socket, postgres).
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${TEST_DB:-sidi_test}"
export PGUSER="${PGUSER:-postgres}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -d postgres -c "drop database if exists ${DB}" -c "create database ${DB}"
"${PSQL[@]}" -d "$DB" -f tests/00_supabase_stub.sql
for f in migrations/*.sql; do
  "${PSQL[@]}" -d "$DB" -f "$f"
done
echo "migrations: ok"
for f in tests/[0-9][1-9]_*.sql tests/[1-9][0-9]_*.sql; do
  [ -e "$f" ] || continue
  "${PSQL[@]}" -d "$DB" -o /dev/null -f "$f"
  echo "$(basename "$f"): ok"
done
