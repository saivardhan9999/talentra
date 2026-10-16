# Talentra demo UI

A thin local web app over the seeded database. It exists to *show* the design working: the M20 queries as screens, and the access rules applied by the database itself. Building a UI is out of scope in the docket, so this is a demo, not a product.

## Run it

Prerequisites:
- The database container is up and seeded (`SEED_SCALE=1 ./run_phase1.sh m19`, or `SEED_SCALE=0.01` for a quick dataset).
- Node.js 18 or newer.

```sh
cd ui
npm install
npm start            # http://localhost:3000
node smoke-test.js   # optional: exercises every screen and the blocking walkthrough (with the server running)
```

The server connects to `postgres://postgres:talentra@localhost:5433/talentra` (the container maps its port 5432 to 5433 on the host). Set `DATABASE_URL` to use another address.

## What it shows

Pick who you are with **Viewing as**. The six people (a candidate, an employer, a recruiter, a recruiter at another company, a consultant, a platform admin) are resolved from the seeded data when the server starts.

| Tab | Query | What to notice |
|---|---|---|
| Job search | Q1 (full text + city) | A candidate sees published, open jobs. A recruiter sees only their own company's requirements, drafts included |
| Candidate search | Q2 (skill / city / name) | Hidden profiles, and anyone who blocked you or your company, never come back |
| My applications | Q3 | Status labels in English, Tamil or Hindi, falling back to English where a translation is missing |
| Pipeline | Q4 | Stage counts for the busiest requirement you can see |
| Hiring funnel | Q10 | Monthly funnel from the analytics aggregate |
| Privacy and blocking | M18 rule | Step-by-step walkthrough of the block rule (block, check as each recruiter, unblock) |

**How access is enforced.** Every request runs `SET LOCAL ROLE talentra_app` and sets `app.current_user_id` to the chosen person, inside its own transaction. Row-level security then decides which rows exist for that person; the page never filters. *Demo shortcut:* the server logs in as the database owner and switches role per request; a production app would log in as its own login role (security milestone M22).

**Speed at laptop scale** (1M profiles, 5M applications):
- searches and lists come back in 0.1–0.3 s;
- a name search takes about 1 s with a city, and several seconds without one. Under row-level security PostgreSQL won't run a name-similarity filter before the security checks, so a name-only search can't use the name index. That's recorded as an M21 performance item.
