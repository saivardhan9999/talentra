# Continuous integration and Discord notifications

Every push to `main` / `master` and every pull request runs `.github/workflows/verify.yml` on GitHub Actions:

1. starts a `postgres:16` container named `talentra-pg` (the same image and name the scripts use locally);
2. rebuilds the schema from `sql/NN_*.sql` and runs milestones M1–M18 against it;
3. seeds the database at **1% of laptop scale** (10k profiles, 50k applications) and runs M19 and M20;
4. keeps the full log as a build artifact (14 days);
5. posts the result to a Discord channel, if a webhook is configured.

A run takes about 6–7 minutes. The full laptop-scale seed (1M profiles, 5M applications, 16 GB, about 1 h 40 min) doesn't fit a hosted runner and stays a manual run (`SEED_SCALE=1 ./run_phase1.sh m19 m20`). It can also be started by hand with **Run workflow** (`workflow_dispatch`) on the Actions tab.

**Run the same check locally** without touching your seeded database:

```sh
TALENTRA_DB=talentra_ci SEED_SCALE=0.01 MSYS_NO_PATHCONV=1 ./run_phase1.sh
```

## Discord notifications (one-time setup, about 10 minutes)

1. In Discord, open the channel → **Edit Channel → Integrations → Webhooks → New Webhook**. Name it "Talentra CI" and **Copy Webhook URL**.
2. On GitHub, open the repository → **Settings → Secrets and variables → Actions → New repository secret**. Name it `DISCORD_WEBHOOK_URL` and paste the URL.
3. Push any commit. The channel gets a message like:

   > ✅ verify passed · g-s-jithesh/talentra
   > VERIFIED: m1 m2 … m20 — seed at 1% scale
   > Branch main · Commit abc1234 · Duration 6 min

   A failure is red and quotes the first failing check, e.g. `FAIL Q1 job search returned no rows`, with a link to the run.

**Keep the webhook URL secret.** Anyone who has it can post to the channel. It lives only in GitHub's encrypted secrets, never in the repository. If it leaks, delete the webhook in Discord and create a new one. Builds from forks don't receive secrets and simply skip the notification.

**Why no ChatOps.** Triggering workflows from Discord would need an always-on bot with a GitHub token, and channel members could run workflows. GitHub's **Re-run jobs** button and `gh workflow run verify` already cover it, and there is nothing to deploy.

**How the notifier stays safe.** `ci/notify_discord.py` reads everything from environment variables, so commit messages and log lines are only ever data inside the JSON body, never text spliced into a shell command. It disables @mentions. A failed notification never changes the build result. `DRY_RUN=1 python3 ci/notify_discord.py verify.log` prints the message without sending it.
