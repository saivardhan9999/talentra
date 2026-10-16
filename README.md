# Talentra — Database Design Hackathon

PostgreSQL 16 schema for the Talentra job search and demand management platform.

## Phase 1 (done): Master data, Profile, Jobs and Applications
- Design and decisions: [docs/phase1-design.md](docs/phase1-design.md)
- Data dictionary (generated): [docs/phase1-data-dictionary.md](docs/phase1-data-dictionary.md)
- DDL: `sql/00_foundation.sql` → `sql/04_seed_reference.sql`
- Verification: [docs/phase1-verification-guide.md](docs/phase1-verification-guide.md), scripts `sql/tests/m1_*.sql`–`m6_*.sql`

## Run
```sh
docker run -d --name talentra-pg --shm-size=1g -e POSTGRES_PASSWORD=talentra -p 5432:5432 \
  -v "$PWD/sql:/sql" postgres:16
MSYS_NO_PATHCONV=1 ./run_phase1.sh        # rebuild + verify milestones 1-6
MSYS_NO_PATHCONV=1 ./run_phase1.sh m3     # rebuild + verify one milestone
```
Regenerate the data dictionary after schema changes:
```sh
docker exec talentra-pg psql -U postgres -d talentra -q -f /sql/tests/data_dictionary.sql
```
