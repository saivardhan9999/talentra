"""Latency benchmark for the M21 report (B70/B71-B73).

Method: each query file runs inside the database container through psql over the local socket, with its
parameters resolved by sql/queries/params.sql. 3 warm-up runs are discarded, then RUNS measured runs;
the latency is psql's \\timing per execution (server execution + protocol, results discarded with \\o).
Reported: rows returned, min, p50, p95, p99, max in milliseconds. Warm cache (the data a query touches is
in shared buffers or the OS cache after the warm-up); cold-cache behaviour is discussed in the report.

usage: python perf/benchmark.py [--runs 50] [--db talentra] [--json out.json] [--role] file.sql [...]
  --role   run as talentra_app with the candidate / recruiter identity in the file's "-- as:" line
"""
import argparse, json, re, statistics, subprocess, sys

def pct(vals, p):
    s = sorted(vals)
    k = (len(s) - 1) * p / 100
    f = int(k)
    return s[f] if f == len(s) - 1 else s[f] + (s[f + 1] - s[f]) * (k - f)

def run(path, runs, db, as_role):
    text = open(path, encoding='utf-8').read()
    body = '\n'.join(l for l in text.splitlines() if not l.startswith('--')).strip()
    title = text.splitlines()[0].lstrip('- ').strip()
    m = re.search(r'^-- as: (\w+)', text, re.M)
    prelude = ''
    if as_role and m:
        prelude = f"BEGIN;\nSELECT set_config('app.current_user_id', :'{m.group(1)}', true) \\g /dev/null\nSET LOCAL ROLE talentra_app;\n"
    script = open('sql/queries/params.sql', encoding='utf-8').read() + '\n' + prelude
    script += '\\o /dev/null\n' + (body + '\n') * 3 + '\\o\nSELECT 1 AS warm_done \\g /dev/null\n\\timing on\n\\o /dev/null\n'
    script += (body + '\n') * runs + '\\o\n\\timing off\n'
    script += '\\o /dev/null\n' + body + '\n\\o\nSELECT :ROW_COUNT AS rows_returned;\n'
    if prelude:
        script += 'ROLLBACK;\n'
    out = subprocess.run(['docker', 'exec', '-i', 'talentra-pg', 'psql', '-U', 'postgres', '-d', db, '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1'],
                         input=script, capture_output=True, text=True, encoding='utf-8')
    if out.returncode != 0:
        raise SystemExit(f'{path}: {out.stderr.strip()[:400]}')
    times = [float(t) for t in re.findall(r'^Time: ([0-9.]+) ms', out.stdout, re.M)]
    rows = re.findall(r'^(\d+)$', out.stdout, re.M)
    if len(times) != runs:
        raise SystemExit(f'{path}: expected {runs} timings, got {len(times)}')
    return {'query': title.split(' (')[0], 'file': path, 'runs': runs, 'rows': int(rows[-1]) if rows else None,
            'min': min(times), 'p50': statistics.median(times), 'p95': pct(times, 95), 'p99': pct(times, 99), 'max': max(times)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+'); ap.add_argument('--runs', type=int, default=50)
    ap.add_argument('--db', default='talentra'); ap.add_argument('--json'); ap.add_argument('--role', action='store_true')
    a = ap.parse_args()
    results = []
    print(f'| Query | Rows | Runs | min | p50 | p95 | p99 | max |  (ms)')
    print('|---|---|---|---|---|---|---|---|')
    for f in a.files:
        r = run(f, a.runs, a.db, a.role)
        results.append(r)
        print(f"| {r['query']} | {r['rows']} | {r['runs']} | {r['min']:.1f} | {r['p50']:.1f} | {r['p95']:.1f} | {r['p99']:.1f} | {r['max']:.1f} |", flush=True)
    if a.json:
        json.dump(results, open(a.json, 'w', encoding='utf-8'), indent=1)

if __name__ == '__main__':
    main()
