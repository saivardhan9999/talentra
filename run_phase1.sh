#!/usr/bin/env bash
# Rebuild the schema (every sql/NN_*.sql, in order) in the talentra-pg container and verify milestones.
#   ./run_phase1.sh            rebuild + verify all milestones
#   ./run_phase1.sh m3         rebuild + verify milestone 3 only
#   ./run_phase1.sh --no-build m5   verify milestone 5 against the existing database
# Milestones 19+ need the seeded dataset: after a rebuild it is generated (sql/seed/NN_*.sql) just before
# the first of them runs, so milestones 1-18 still run against the empty schema.
#   SEED_SCALE=0.01 ./run_phase1.sh m19   seed at 1% of laptop scale (default 1 = 1M profiles, 5M applications)
set -eo pipefail
C=talentra-pg
PSQL="docker exec $C psql -U postgres -d talentra -q -v ON_ERROR_STOP=1"
BUILT=0
if [ "$1" = "--no-build" ]; then shift; else
  docker exec $C psql -U postgres -q -c "DROP DATABASE IF EXISTS talentra WITH (FORCE)" \
    -c "CREATE DATABASE talentra ENCODING 'UTF8' TEMPLATE template0"
  for f in $(cd sql && ls [0-9][0-9]_*.sql); do
    echo "== build ${f%.sql}"; $PSQL -f /sql/$f
  done
  BUILT=1
fi
ALL=$(cd sql/tests && ls m[0-9]*_*.sql | sed 's/_.*//' | sort -V | tr '\n' ' ')
LIST="${*:-$ALL}"   # every milestone named on the command line (default: all)
for m in $LIST; do
  if [ "$BUILT" = 1 ] && [ "${m#m}" -ge 19 ]; then
    for f in $(cd sql/seed && ls [0-9][0-9]_*.sql); do
      echo "== seed ${f%.sql} (scale ${SEED_SCALE:-1})"; s=$(date +%s)
      $PSQL -v scale="${SEED_SCALE:-1}" -f /sql/seed/$f 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'
      echo "   $(( $(date +%s) - s ))s"
    done
    BUILT=0
  fi
  f=$(cd sql/tests && ls ${m}_*.sql)
  echo; echo "==================== ${m}: ${f%.sql} ===================="
  $PSQL -f /sql/tests/$f 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'
done
echo; echo "VERIFIED: $LIST"
