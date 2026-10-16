// Smoke test for the demo UI's API (run while the server is up): node smoke-test.js
// Exercises every endpoint and the blocking walkthrough, and leaves the data as it found it.
const base = process.env.UI_URL || 'http://localhost:3000';
const call = async (path, persona, opts = {}) => {
  const t0 = Date.now();
  const res = await fetch(base + path, { ...opts, headers: { 'content-type': 'application/json', 'x-persona': String(persona || '') } });
  const body = await res.json();
  if (!res.ok) throw new Error(`${path}: ${body.error}`);
  return { body, ms: Date.now() - t0 };
};
const check = (ok, label) => { if (!ok) { console.error('FAIL', label); process.exit(1); } console.log('PASS', label); };

(async () => {
  const { body: people } = await call('/api/personas');
  const p = Object.fromEntries(people.map((x) => [x.key, x]));
  check(people.length === 6, `6 personas resolved from the data (${people.map((x) => x.key).join(', ')})`);
  const name = p.candidate.label.replace('Candidate — ', '');
  // name + the candidate's city: the city index narrows the search before row-level security runs
  const search = `/api/candidates?skill=&city=${p.candidate.city_id}&name=` + encodeURIComponent(name);

  let r = await call('/api/jobs?q=java%20developer', p.candidate.user_id);
  check(r.body.length > 0 && r.body.every((j) => j.status === 'open' && j.publish_state === 'published'), `candidate job search: ${r.body.length} published open jobs (${r.ms} ms)`);
  r = await call('/api/jobs?q=', p.recruiter.user_id);
  check(r.body.length > 0 && r.body.every((j) => j.company === p.recruiter.org_name), `recruiter sees only own company's requirements (${r.body.length}, ${r.ms} ms)`);
  r = await call(search, p.recruiter.user_id);
  const found = (rows) => rows.some((c) => String(c.id) === String(p.candidate.profile_id));   // the exact profile, not a namesake
  check(found(r.body), `recruiter finds candidate "${name}" by name (${r.ms} ms)`);
  r = await call('/api/my-applications?lang=ta', p.candidate.user_id);
  check(r.body.length > 0, `candidate's applications with Tamil labels: ${r.body.length} (${r.ms} ms)`);
  r = await call('/api/pipeline', p.recruiter.user_id);
  check(r.body.job && r.body.stages.length > 0, `recruiter pipeline for "${r.body.job.title}" (${r.ms} ms)`);
  r = await call('/api/funnel', p.employer.user_id);
  check(r.body.length > 0, `employer hiring funnel: ${r.body.length} months (${r.ms} ms)`);

  // blocking walkthrough
  const { body: blk } = await call('/api/blocks', p.candidate.user_id, { method: 'POST', body: JSON.stringify({ organisation_id: p.recruiter.org_id }) });
  r = await call(search, p.recruiter.user_id);
  check(!found(r.body), 'after the candidate blocks the company, its recruiter no longer finds them');
  r = await call(search, p.other_recruiter.user_id);
  check(found(r.body), "another company's recruiter still finds them");
  r = await call('/api/blocks', p.recruiter.user_id);
  check(r.body.length === 0, 'the blocked recruiter cannot see the block itself');
  await call(`/api/blocks/${blk.id}/unblock`, p.candidate.user_id, { method: 'POST' });
  r = await call(search, p.recruiter.user_id);
  check(found(r.body), 'after unblocking, the recruiter finds them again');
})().catch((e) => { console.error('FAIL', e.message); process.exit(1); });
