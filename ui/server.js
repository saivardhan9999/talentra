// Talentra demo UI — a thin local web app over the seeded database.
// Every request runs as the application role (talentra_app) with the chosen person's identity in
// app.current_user_id, so row-level security decides what each person sees.
// Demo shortcut: the server logs in as the database owner and switches role per request
// (SET LOCAL ROLE); a production app would log in as its own LOGIN role (M22).
const express = require('express');
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:talentra@localhost:5433/talentra',
  max: 8,
});
const app = express();
app.use(express.json());
app.use(express.static(__dirname + '/public'));

let personas = [];

// Run fn(client) inside a transaction as talentra_app acting for userId.
async function asUser(userId, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL statement_timeout = '15s'");
    await client.query('SET LOCAL ROLE talentra_app');
    await client.query("SELECT set_config('app.current_user_id', $1, true)", [String(userId)]);
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

function persona(req) {
  const p = personas.find((x) => String(x.user_id) === String(req.get('x-persona')));
  if (!p) throw Object.assign(new Error('Choose who you are viewing as.'), { status: 400 });
  return p;
}

const route = (handler) => async (req, res) => {
  try {
    res.json(await handler(req));
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
};

// Demo people, resolved from the seeded data (as the owner, at startup).
async function loadPersonas() {
  const q = (sql, params) => pool.query(sql, params).then((r) => r.rows[0]);
  const busy = await q(`SELECT r.organisation_id AS org_id, o.legal_name FROM fact_job_posting f
                        JOIN job_requirement r ON r.id = f.job_requirement_id JOIN organisation o ON o.id = r.organisation_id
                        ORDER BY f.application_count DESC, f.job_requirement_id LIMIT 1`);
  const other = await q(`SELECT o.id AS org_id, o.legal_name FROM organisation o
                         WHERE o.id <> $1 AND EXISTS (SELECT 1 FROM job_requirement r WHERE r.organisation_id = o.id AND r.job_requirement_status_id = 1)
                         ORDER BY o.id LIMIT 1`, [busy.org_id]);
  const member = (orgId, roleId) => q(`SELECT u.id AS user_id, u.email FROM organisation_member m JOIN user_account u ON u.id = m.user_account_id
                                       WHERE m.organisation_id = $1 AND m.role_id = $2 AND m.valid_to IS NULL ORDER BY m.id LIMIT 1`, [orgId, roleId]);
  const employer = await member(busy.org_id, 6);
  const recruiter = await member(busy.org_id, 7);
  const otherRecruiter = await member(other.org_id, 7);
  const candidate = await q(`SELECT p.user_account_id AS user_id, p.full_name, p.id AS profile_id, p.current_city_id AS city_id
                             FROM application a JOIN job_requirement r ON r.id = a.job_requirement_id
                             JOIN candidate_profile p ON p.id = a.candidate_profile_id
                             WHERE r.organisation_id = $1 AND p.profile_visibility_id = 1 AND p.deleted_at IS NULL AND p.family_name IS NOT NULL
                               AND p.full_name ~ '^[A-Za-z ]+$'
                             ORDER BY a.id LIMIT 1`, [busy.org_id]);
  const consultant = await q(`SELECT u.id AS user_id, u.email FROM sourcing_request s JOIN user_account u ON u.id = s.consultant_user_account_id
                              WHERE s.sourcing_request_status_id = 2 ORDER BY s.id LIMIT 1`);
  const admin = await q(`SELECT u.id AS user_id, u.email FROM user_account_role g JOIN user_account u ON u.id = g.user_account_id
                         WHERE g.role_id = 2 AND g.revoked_at IS NULL ORDER BY u.id LIMIT 1`);
  personas = [
    { key: 'candidate', label: `Candidate — ${candidate.full_name}`, user_id: candidate.user_id, profile_id: candidate.profile_id, city_id: candidate.city_id },
    { key: 'employer', label: `Employer — ${busy.legal_name}`, user_id: employer.user_id, org_id: busy.org_id, org_name: busy.legal_name },
    { key: 'recruiter', label: `Recruiter — ${busy.legal_name}`, user_id: recruiter.user_id, org_id: busy.org_id, org_name: busy.legal_name },
    { key: 'other_recruiter', label: `Recruiter — ${other.legal_name}`, user_id: otherRecruiter.user_id, org_id: other.org_id, org_name: other.legal_name },
    { key: 'consultant', label: `Consultant — ${consultant.email}`, user_id: consultant.user_id },
    { key: 'admin', label: `Platform admin — ${admin.email}`, user_id: admin.user_id },
  ];
}

app.get('/api/personas', route(async () => personas));

app.get('/api/cities', route(async () =>
  (await pool.query(`SELECT c.id, c.name FROM city c JOIN state s ON s.id = c.state_id
                     WHERE s.country_id = (SELECT id FROM country WHERE iso_alpha2 = 'IN') ORDER BY c.name`)).rows));
app.get('/api/skills', route(async () => (await pool.query('SELECT id, name FROM skill ORDER BY name')).rows));

// Job search (Q1): what this person may see — candidates see published, open jobs;
// a recruiter sees their own company's requirements, drafts included, and no one else's.
app.get('/api/jobs', route(async (req) => {
  const p = persona(req);
  const text = (req.query.q || '').trim();
  const city = req.query.city ? Number(req.query.city) : null;
  return asUser(p.user_id, async (c) => (await c.query(`
    SELECT r.id, r.title, o.legal_name AS company, st.code AS status, ps.code AS publish_state,
           r.salary_min_amount, r.salary_max_amount, r.published_at::date AS published,
           (SELECT string_agg(ci.name, ', ') FROM job_requirement_location l JOIN city ci ON ci.id = l.city_id WHERE l.job_requirement_id = r.id) AS cities
    FROM job_requirement r
    JOIN organisation o ON o.id = r.organisation_id
    JOIN job_requirement_status st ON st.id = r.job_requirement_status_id
    JOIN publish_state ps ON ps.id = r.publish_state_id
    WHERE r.deleted_at IS NULL
      AND ($1 = '' OR r.search_document @@ websearch_to_tsquery('simple', $1))
      AND ($2::bigint IS NULL OR EXISTS (SELECT 1 FROM job_requirement_location l WHERE l.job_requirement_id = r.id AND l.city_id = $2))
    ORDER BY r.published_at DESC NULLS LAST, r.id DESC
    LIMIT 25`, [text, city])).rows);
}));

// Candidate search (Q2): row-level security hides hidden profiles and anyone who blocked this person.
app.get('/api/candidates', route(async (req) => {
  const p = persona(req);
  const name = (req.query.name || '').trim();
  const skill = req.query.skill ? Number(req.query.skill) : null;
  const city = req.query.city ? Number(req.query.city) : null;
  if (!name && !skill && !city) throw Object.assign(new Error('Enter a name, a skill or a city.'), { status: 400 });
  return asUser(p.user_id, async (c) => (await c.query(`
    SELECT p.id, p.full_name, p.headline, ci.name AS city, p.total_experience_months / 12 AS years, pv.code AS visibility
    FROM candidate_profile p
    LEFT JOIN city ci ON ci.id = p.current_city_id
    JOIN profile_visibility pv ON pv.id = p.profile_visibility_id
    WHERE p.deleted_at IS NULL
      AND ($1 = '' OR p.full_name % $1 OR p.full_name ILIKE $1 || '%')
      AND ($2::bigint IS NULL OR EXISTS (SELECT 1 FROM candidate_skill s WHERE s.candidate_profile_id = p.id AND s.skill_id = $2))
      AND ($3::bigint IS NULL OR p.current_city_id = $3)
    ORDER BY ($1 <> '' AND p.full_name ILIKE $1 || '%') DESC, p.last_active_at DESC NULLS LAST
    LIMIT 25`, [name, skill, city])).rows);
}));

// A candidate's own applications (Q3), status labels in the chosen language with fallback.
app.get('/api/my-applications', route(async (req) => {
  const p = persona(req);
  const lang = ['en', 'hi', 'ta'].includes(req.query.lang) ? req.query.lang : 'en';
  return asUser(p.user_id, async (c) => (await c.query(`
    SELECT a.id, coalesce(r.title, '(no longer listed)') AS title, o.legal_name AS company,
           coalesce(t.label_text, d.label_text) AS status, a.applied_at::date AS applied, a.status_changed_at::date AS since
    FROM application a
    JOIN candidate_profile cp ON cp.id = a.candidate_profile_id
    LEFT JOIN job_requirement r ON r.id = a.job_requirement_id
    LEFT JOIN organisation o ON o.id = r.organisation_id
    JOIN application_status s ON s.id = a.application_status_id
    LEFT JOIN ui_label_translation t ON t.ui_label_key_id = s.ui_label_key_id AND t.language_id = (SELECT id FROM language WHERE code = $1)
    JOIN ui_label_translation d ON d.ui_label_key_id = s.ui_label_key_id AND d.language_id = (SELECT id FROM language WHERE is_default)
    WHERE cp.user_account_id = app_current_user_id()
    ORDER BY a.applied_at DESC`, [lang])).rows);
}));

// Recruiter pipeline (Q4) for the busiest requirement this person can see.
app.get('/api/pipeline', route(async (req) => {
  const p = persona(req);
  return asUser(p.user_id, async (c) => {
    const job = (await c.query(`SELECT r.id, r.title, o.legal_name AS company FROM job_requirement r JOIN organisation o ON o.id = r.organisation_id
                                JOIN fact_job_posting f ON f.job_requirement_id = r.id
                                ORDER BY f.application_count DESC LIMIT 1`)).rows[0];
    if (!job) return { job: null, stages: [], recent: [] };
    const stages = (await c.query(`SELECT s.code AS stage, count(*)::int AS applications FROM application a
                                   JOIN application_status s ON s.id = a.application_status_id
                                   WHERE a.job_requirement_id = $1 GROUP BY s.code, s.sort_order, s.id ORDER BY s.sort_order, s.id`, [job.id])).rows;
    const recent = (await c.query(`SELECT a.id, coalesce(p.full_name, '(profile hidden from you)') AS candidate, s.code AS stage, a.status_changed_at::date AS since
                                   FROM application a JOIN application_status s ON s.id = a.application_status_id
                                   LEFT JOIN candidate_profile p ON p.id = a.candidate_profile_id
                                   WHERE a.job_requirement_id = $1 ORDER BY a.status_changed_at DESC LIMIT 15`, [job.id])).rows;
    return { job, stages, recent };
  });
}));

// Hiring funnel (Q10) for this person's organisation, from the aggregate.
app.get('/api/funnel', route(async (req) => {
  const p = persona(req);
  if (!p.org_id) throw Object.assign(new Error('The hiring funnel belongs to an employer or recruiter.'), { status: 400 });
  return asUser(p.user_id, async (c) => (await c.query(`
    SELECT to_char(month_start, 'Mon YYYY') AS month, applied_count, shortlisted_count, interviewed_count, offered_count, joined_count,
           round(100.0 * joined_count / nullif(applied_count, 0), 2) AS hire_pct, avg_days_to_hire
    FROM agg_hiring_funnel_monthly WHERE organisation_id = $1 ORDER BY month_start DESC LIMIT 12`, [p.org_id])).rows);
}));

// Blocking (M18): the candidate blocks a company; its recruiters stop seeing the profile.
app.get('/api/blocks', route(async (req) => {
  const p = persona(req);
  return asUser(p.user_id, async (c) => (await c.query(`
    SELECT b.id, coalesce(o.legal_name, u.email) AS blocked, b.blocked_at::date AS since
    FROM block_entry b LEFT JOIN organisation o ON o.id = b.blocked_organisation_id LEFT JOIN user_account u ON u.id = b.blocked_user_account_id
    WHERE b.unblocked_at IS NULL ORDER BY b.blocked_at DESC`)).rows);
}));
app.post('/api/blocks', route(async (req) => {
  const p = persona(req);
  const orgId = Number(req.body.organisation_id);
  return asUser(p.user_id, async (c) => (await c.query(
    `INSERT INTO block_entry (blocker_user_account_id, blocked_organisation_id) VALUES (app_current_user_id(), $1) RETURNING id`, [orgId])).rows[0]);
}));
app.post('/api/blocks/:id/unblock', route(async (req) => {
  const p = persona(req);
  return asUser(p.user_id, async (c) => ({
    updated: (await c.query('UPDATE block_entry SET unblocked_at = now() WHERE id = $1 AND unblocked_at IS NULL', [Number(req.params.id)])).rowCount,
  }));
}));

const port = Number(process.env.PORT || 3000);
loadPersonas()
  .then(() => app.listen(port, () => console.log(`Talentra demo UI on http://localhost:${port}`)))
  .catch((e) => { console.error('Could not start:', e.message); process.exit(1); });
