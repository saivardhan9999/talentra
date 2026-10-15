#!/usr/bin/env bash
# Rebuild the Phase 1 schema in the talentra-pg container and verify milestones.
#   ./run_phase1.sh            rebuild + verify all milestones
#   ./run_phase1.sh m3         rebuild + verify milestone 3 only
#   ./run_phase1.sh --no-build m5   verify milestone 5 against the existing database
set -eo pipefail
C=talentra-pg
PSQL="docker exec $C psql -U postgres -d talentra -q -v ON_ERROR_STOP=1"
if [ "$1" = "--no-build" ]; then shift; else
  docker exec $C psql -U postgres -q -c "DROP DATABASE IF EXISTS talentra WITH (FORCE)" \
    -c "CREATE DATABASE talentra ENCODING 'UTF8' TEMPLATE template0"
  for f in 00_foundation 01_master_data 02_profile 03_jobs_applications 04_seed_reference; do
    echo "== build $f"; $PSQL -f /sql/$f.sql
  done
fi
for m in ${1:-m1 m2 m3 m4 m5 m6}; do
  f=$(cd sql/tests && ls ${m}_*.sql)
  echo; echo "==================== ${m}: ${f%.sql} ===================="
  $PSQL -f /sql/tests/$f 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'
done
echo; echo "VERIFIED: ${1:-m1 m2 m3 m4 m5 m6}"
