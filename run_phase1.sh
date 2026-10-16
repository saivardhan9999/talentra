#!/usr/bin/env bash
# Rebuild the schema (every sql/NN_*.sql, in order) in the talentra-pg container and verify milestones.
#   ./run_phase1.sh            rebuild + verify all milestones
#   ./run_phase1.sh m3         rebuild + verify milestone 3 only
#   ./run_phase1.sh --no-build m5   verify milestone 5 against the existing database
set -eo pipefail
C=talentra-pg
PSQL="docker exec $C psql -U postgres -d talentra -q -v ON_ERROR_STOP=1"
if [ "$1" = "--no-build" ]; then shift; else
  docker exec $C psql -U postgres -q -c "DROP DATABASE IF EXISTS talentra WITH (FORCE)" \
    -c "CREATE DATABASE talentra ENCODING 'UTF8' TEMPLATE template0"
  for f in $(cd sql && ls [0-9][0-9]_*.sql); do
    echo "== build ${f%.sql}"; $PSQL -f /sql/$f
  done
fi
ALL=$(cd sql/tests && ls m[0-9]*_*.sql | sed 's/_.*//' | sort -V | tr '\n' ' ')
for m in ${1:-$ALL}; do
  f=$(cd sql/tests && ls ${m}_*.sql)
  echo; echo "==================== ${m}: ${f%.sql} ===================="
  $PSQL -f /sql/tests/$f 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'
done
echo; echo "VERIFIED: ${1:-$ALL}"
