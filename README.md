# Talentra — Database Design Hackathon

PostgreSQL 16 schema for the Talentra job search and demand management platform: design, DDL, a synthetic data generator at laptop scale, the query set, and the checks that prove every milestone.

[![verify](../../actions/workflows/verify.yml/badge.svg)](../../actions/workflows/verify.yml)

**Progress:** milestones 1–21 of 23 are done (schema complete, seeded at laptop scale, performance measured: [phase5-performance.md](docs/phase5-performance.md)). Security (M22) and backup / sign-off (M23) are next. The build log with every error and fix is in [notes.md](notes.md).

## Design documents

| Phase | Scope | Design | Data dictionary |
|---|---|---|---|
| 1 | Master data, Profile, Jobs and Applications | [phase1-design.md](docs/phase1-design.md) | [phase1](docs/phase1-data-dictionary.md) |
| 2 | Administration, Organisation, Gig marketplace | [phase2-design.md](docs/phase2-design.md) | [phase2](docs/phase2-data-dictionary.md) |
| 3 | Licences and devices, Sourcing, Subscriptions and wallet | [phase3-design.md](docs/phase3-design.md) | [phase3](docs/phase3-data-dictionary.md) |
| 4 | Notifications and community, Analytics, Shared items | [phase4-design.md](docs/phase4-design.md) | [phase4](docs/phase4-data-dictionary.md) |
| 5 | Seed data, queries and validation | [phase5-design.md](docs/phase5-design.md) | query report: [phase5-query-report.md](docs/phase5-query-report.md); validation: [phase5-seed-validation.md](docs/phase5-seed-validation.md) |

Also: [competitive coverage benchmark and gap register](docs/coverage-gap-register.md) · [how to verify each milestone](docs/phase1-verification-guide.md) · [CI and Discord notifications](docs/ci.md).

## Run

```sh
docker run -d --name talentra-pg --shm-size=1g -e POSTGRES_PASSWORD=talentra -p 5433:5432 \
  -v "$PWD/sql:/sql" postgres:16
MSYS_NO_PATHCONV=1 ./run_phase1.sh m1 m2 m3            # rebuild + verify the milestones named
SEED_SCALE=0.01 MSYS_NO_PATHCONV=1 ./run_phase1.sh      # everything, seed at 1% (about 7 minutes)
SEED_SCALE=1 MSYS_NO_PATHCONV=1 ./run_phase1.sh m19 m20 # laptop scale: 1M profiles, 5M applications (~1 h 40 min, 16 GB)
./run_report.sh                                         # regenerate the M20 query and validation reports
```

- `MSYS_NO_PATHCONV=1` is needed only in Git Bash on Windows.
- `TALENTRA_DB=talentra_ci` runs everything in a scratch database and leaves the seeded one alone.
- `--shm-size=1g` is needed for parallel queries on the seeded tables.
- Port 5433 avoids clashing with a locally installed PostgreSQL; the scripts themselves use `docker exec`.

## Demo UI

A thin local web app over the seeded database. It shows the queries as screens, with a "Viewing as" switch so you can watch the database's row-level security hide data per person (a recruiter sees only their company's jobs; a candidate who blocks a company disappears for its recruiters). See [ui/README.md](ui/README.md).

```sh
cd ui && npm install && npm start      # http://localhost:3000
```
