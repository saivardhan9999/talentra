#!/usr/bin/env bash
# Talentra v2 runner.
#   ./run.sh reset            drop and rebuild talentra_v2: migrate + seed + test (about a minute at 10k profiles)
#   ./run.sh migrate          apply pending migrations (each in its own transaction, recorded with a checksum)
#   ./run.sh seed [profiles]  load synthetic data (default 10000 candidate profiles)
#   ./run.sh test             run db/tests/*.sql (every test rolls back, so the seeded data is unchanged)
#   ./run.sh bench            latency benchmark of the access patterns -> docs/benchmark-results.md
#   ./run.sh dictionary       regenerate docs/data-dictionary.md and docs/logical-erd.md from the live catalog
# Env: V2_DB (default talentra_v2), PG_CONTAINER (default talentra-pg).
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
DB=${V2_DB:-talentra_v2}
CONTAINER=${PG_CONTAINER:-talentra-pg}

psql_db()    { docker exec -i "$CONTAINER" psql -U postgres -d "$DB" -X -q -v ON_ERROR_STOP=1 "$@"; }
psql_admin() { docker exec -i "$CONTAINER" psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 "$@"; }

migrate() {
  psql_db -c "SET client_min_messages = warning" -c "CREATE TABLE IF NOT EXISTS schema_migration (version text PRIMARY KEY, name text NOT NULL, checksum text NOT NULL,
              applied_at timestamptz NOT NULL DEFAULT now(), duration_ms integer NOT NULL)"
  for f in db/migrations/V*.sql; do
    local base v name sum applied
    base=$(basename "$f" .sql); v=${base%%__*}; name=${base#*__}
    sum=$(sha256sum "$f" | cut -c1-64)
    applied=$(psql_db -At -c "SELECT checksum FROM schema_migration WHERE version = '$v'")
    if [ -n "$applied" ]; then
      [ "$applied" = "$sum" ] || { echo "ERROR: $f was edited after it was applied. Write a new migration instead."; exit 1; }
      continue
    fi
    { echo "BEGIN;"; cat "$f"; echo
      echo "INSERT INTO schema_migration (version, name, checksum, duration_ms)
            VALUES ('$v', '$name', '$sum', (extract(epoch FROM clock_timestamp() - now()) * 1000)::int);"
      echo "COMMIT;"; } | psql_db
    echo "applied $base"
  done
}

seed() {
  local n=${1:-10000} t0=$SECONDS
  psql_db -1 -v profiles="$n" < db/seed/seed.sql      # one transaction: all or nothing
  psql_db -c "ANALYZE"
  echo "seeded $n profiles in $((SECONDS - t0)) s"
}

# Each file runs with db/tests/_helpers.sql prepended. Files that must commit (t04: real parallel connections) run on a
# throwaway clone of the database, so the seeded data is never changed by a test.
run_tests() {
  local failed=0 f out target
  for f in db/tests/t*.sql; do
    target=$DB
    if grep -q 'run.sh runs this file on a throwaway clone' "$f"; then
      target=${DB}_scratch
      psql_admin -c "DROP DATABASE IF EXISTS $target WITH (FORCE)" -c "CREATE DATABASE $target TEMPLATE $DB"
    fi
    if out=$(cat db/tests/_helpers.sql "$f" | docker exec -i "$CONTAINER" psql -U postgres -d "$target" -X -q -o /dev/null -v ON_ERROR_STOP=1 2>&1); then
      echo "$out" | grep -E 'PASS|FINDING' | sed -E 's/.*(PASS|FINDING)/\1/'
    else
      echo "$out" | { grep -E 'PASS' || true; } | sed -E 's/.*PASS/PASS/'
      echo "FAIL $(basename "$f"):"; echo "$out" | { grep -vE 'PASS' || true; } | sed 's/^/    /'
      failed=1
    fi
    [ "$target" = "$DB" ] || psql_admin -c "DROP DATABASE IF EXISTS $target WITH (FORCE)"
  done
  if [ $failed = 0 ]; then echo "all tests passed"; else echo "TESTS FAILED"; exit 1; fi
}

case "${1:-}" in
  reset)
    psql_admin -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)" -c "CREATE DATABASE $DB"
    migrate; seed "${2:-10000}"; run_tests ;;
  migrate)    migrate ;;
  seed)       seed "${2:-10000}" ;;
  test)       run_tests ;;
  bench)      python bench/bench.py --db "$DB" --container "$CONTAINER" ;;
  dictionary) psql_db -At < db/dictionary.sql > docs/data-dictionary.md
              python db/erd.py "$DB" "$CONTAINER" > docs/logical-erd.md
              echo "wrote docs/data-dictionary.md and docs/logical-erd.md" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
