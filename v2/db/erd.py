"""Logical ER diagrams (Mermaid, one per subject area) generated from the live catalog: ./run.sh dictionary -> docs/logical-erd.md.
Audit columns are left out (they are on every business table). Usage: python db/erd.py [--relations] [database] [container]
--relations: tables and foreign-key links only, no attributes -> docs/relationship-erd.md"""
import json, subprocess, sys
RELATIONS = '--relations' in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
DB = ARGS[0] if len(ARGS) > 0 else 'talentra_v2'
CONTAINER = ARGS[1] if len(ARGS) > 1 else 'talentra-pg'
# area -> (tables drawn in full, context tables drawn as a stub)
AREAS = {
    'Identity and access': (['app_user', 'user_credential', 'user_access_role', 'consent_record', 'user_device', 'user_session'], []),
    'Organisation': (['organisation', 'organisation_location', 'organisation_tax_identifier', 'organisation_member'], ['app_user']),
    'Candidate profile': (['candidate_profile', 'candidate_education', 'candidate_experience', 'candidate_skill', 'candidate_language', 'resume',
                           'candidate_block', 'job_alert'], ['app_user', 'organisation']),
    'Jobs and applications': (['job_requirement', 'job_requirement_location', 'job_requirement_skill', 'screening_question', 'application',
                               'application_answer', 'application_status_history'], ['organisation', 'candidate_profile', 'resume', 'app_user']),
    'Billing and licences': (['plan', 'subscription', 'wallet', 'wallet_ledger_entry', 'payment_order', 'payment_event', 'invoice', 'profile_download'],
                             ['organisation', 'app_user', 'candidate_profile']),
    'Notifications and audit': (['notification_preference', 'notification', 'audit_event', 'system_error'], ['app_user', 'organisation']),
}
SQL = r"""
SELECT json_build_object(
 'cols', (SELECT json_agg(json_build_object('t', c.relname, 'n', a.attname, 'type', CASE WHEN t.typtype = 'd' THEN t.typname ELSE format_type(a.atttypid, NULL) END,
          'null', NOT a.attnotnull, 'pk', EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p' AND a.attnum = ANY (k.conkey)),
          'fk', EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f' AND a.attnum = ANY (k.conkey)),
          'uk', EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisunique AND NOT i.indisprimary AND i.indpred IS NULL AND i.indnkeyatts = 1 AND i.indkey[0] = a.attnum))
          ORDER BY c.relname, a.attnum)
          FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace AND ns.nspname = 'public'
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped JOIN pg_type t ON t.oid = a.atttypid
          WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND a.attname NOT IN ('created_at', 'created_by', 'updated_at', 'updated_by')),
 'fks', (SELECT json_agg(json_build_object('child', k.conrelid::regclass::text, 'parent', k.confrelid::regclass::text,
          'cols', (SELECT array_agg(a.attname ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)),
          'nullable', EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey) AND NOT a.attnotnull),
          'unique', EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = k.conrelid AND i.indisunique AND i.indpred IS NULL AND cardinality(k.conkey) = 1 AND i.indnkeyatts = 1 AND i.indkey[0] = k.conkey[1])))
          FROM pg_constraint k WHERE k.contype = 'f' AND k.conname NOT LIKE '%created_by' AND k.conname NOT LIKE '%updated_by'))
"""
out = subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', DB, '-X', '-At'], input=SQL,
                     capture_output=True, text=True, encoding='utf-8').stdout
data = json.loads(out)
cols = {}
for c in data['cols']:
    cols.setdefault(c['t'], []).append(c)
Q = '"'
res = []
everything = []          # every relationship once, for the whole-schema overview
for area, (main, ctx) in AREAS.items():
    lines = ['### ' + area, '', '```mermaid', 'erDiagram']
    seen = set()
    for f in data['fks']:
        if f['child'] in main and (f['parent'] in main or f['parent'] in ctx):
            key = (f['child'], f['parent'], tuple(f['cols']))
            if key in seen:
                continue
            seen.add(key)
            left = '|o' if f['nullable'] else '||'
            right = 'o|' if f['unique'] else 'o{'
            rel = '    ' + f['parent'] + ' ' + left + '--' + right + ' ' + f['child'] + ' : ' + Q + ', '.join(f['cols']) + Q
            lines.append(rel)
            if rel not in everything:
                everything.append(rel)
    for t in ([] if RELATIONS else main):
        lines.append('    ' + t + ' {')
        for c in cols.get(t, []):
            keys = ','.join(k for k, v in (('PK', c['pk']), ('FK', c['fk']), ('UK', c['uk'])) if v)
            typ = c['type'].replace(' ', '_').replace('timestamp_with_time_zone', 'timestamptz')
            lines.append('        ' + typ + ' ' + c['n'] + ((' ' + keys) if keys else '') + (' ' + Q + 'nullable' + Q if c['null'] else ''))
        lines.append('    }')
    for t in ([] if RELATIONS else ctx):
        lines.append('    ' + t + ' {')
        lines.append('        bigint id PK ' + Q + 'see its own area' + Q)
        lines.append('    }')
    lines.append('```')
    res.append('\n'.join(lines))
sys.stdout.reconfigure(encoding='utf-8')
if RELATIONS:
    tables = {w for r in everything for w in r.split()[0:3:2]}
    NL = chr(10)
    print('# Relationship ER diagrams (generated)' + NL + NL
          + 'Tables and the foreign keys that connect them, no attributes. Each line reads **parent → foreign-key column → child**: '
          + '`app_user ||--o| user_credential : "app_user_id"` means one app_user has at most one user_credential, linked by '
          + '`user_credential.app_user_id`. Generated by `./run.sh dictionary` from the live catalog; attributes are in '
          + '[logical-erd.md](logical-erd.md). Audit-column keys and keys to lookup tables are left out.' + NL + NL
          + 'Notation: `||--o{` one-to-many · `||--o|` one-to-one · `|o--` optional parent (nullable key).' + NL)
    print(f'## Whole schema ({len(tables)} tables, {len(everything)} relationships)' + NL + NL
          + '```mermaid' + NL + 'erDiagram' + NL + NL.join(everything) + NL + '```' + NL)
    print((NL + NL).join(r.replace('### ', '## ', 1) for r in res))
    sys.exit()
print('# Logical ER diagrams (generated)\n\nGenerated by `./run.sh dictionary` from the live catalog; do not edit by hand. '
      'Audit columns are omitted; keys to lookup tables are listed as attributes, not drawn. '
      'Notation: `||--o{` one-to-many, `||--o|` one-to-one, `|o` optional parent (nullable key).\n')
print('\n\n'.join(res))
