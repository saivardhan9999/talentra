"""Draws the Talentra schema diagrams (tables grouped by module, foreign keys as labelled arrows) with Graphviz, straight
from the live PostgreSQL catalogs, and writes docs/schema/{v1,v2}-schema.{svg,png} plus docs/schema-diagram.md.

  python docs/schema/make_schema_diagram.py        (Docker container talentra-pg running; Graphviz `dot` on PATH)

Business tables only: reference data and lookup tables are left out, and so are the created_by / updated_by keys that
every business table has. Arrow = one parent to many children; flat bar = one to one; dashed = optional (nullable) key."""
import json, os, re, shutil, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DOT = shutil.which('dot') or r'C:\Program Files (x86)\Graphviz\bin\dot.exe'
SQL = r"""
SELECT json_build_object(
 'tables', (SELECT json_agg(json_build_object('name', c.relname,
     'lookup', EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'ui_label_id')
               AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'code'),
     'business', EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'created_by'),
     'partitioned', c.relkind = 'p') ORDER BY c.relname)
   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition AND c.relname <> 'schema_migration'),
 'fks', (SELECT json_agg(json_build_object('child', k.conrelid::regclass::text, 'parent', k.confrelid::regclass::text,
     'cols', (SELECT array_agg(a.attname ORDER BY array_position(k.conkey, a.attnum)) FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)),
     'nullable', EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey) AND NOT a.attnotnull),
     'unique', EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = k.conrelid AND i.indisunique AND i.indpred IS NULL
                       AND i.indnkeyatts = cardinality(k.conkey) AND (SELECT array_agg(x ORDER BY x) FROM unnest(i.indkey::int2[]) x)
                                                                     = (SELECT array_agg(x ORDER BY x) FROM unnest(k.conkey) x))))
   FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
   WHERE k.contype = 'f' AND NOT c.relispartition
     AND NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey) AND a.attname IN ('created_by', 'updated_by'))))
"""
VERSIONS = {
    'v2': {'db': 'talentra_v2', 'title': 'v2 core schema', 'folder': os.path.join(ROOT, 'v2', 'db', 'migrations'), 'pattern': r'V(\d{3})__.*\.sql$',
           'modules': {'003': 'Identity and access', '004': 'Organisation', '005': 'Audit', '006': 'Candidate profile',
                       '007': 'Jobs and applications', '008': 'Billing and licences', '009': 'Notifications'}},
    'v1': {'db': 'talentra', 'title': 'v1 full schema', 'folder': os.path.join(ROOT, 'sql'), 'pattern': r'(\d\d)_.*\.sql$',
           'modules': {'02': 'Profile', '03': 'Jobs and applications', '05': 'Administration', '06': 'Organisation', '07': 'Gig marketplace',
                       '08': 'Administration', '09': 'Subscriptions and wallet', '10': 'Licences and devices', '11': 'Sourcing',
                       '12': 'Notifications and community', '13': 'Shared items', '14': 'Analytics'},
           # created early in 00_foundation.sql so every module can reference them; they belong to these modules
           'overrides': {'user_account': 'Administration', 'organisation': 'Organisation'}},
}
COLOURS = ['#2f6db5', '#b5452f', '#2f8f6b', '#8a5ab3', '#b58a1f', '#1f8fa6', '#b3477f', '#5f7a2a', '#a35f2a', '#4a5cb3', '#2a8a8a', '#9a3f3f']

def fetch(db):
    out = subprocess.run(['docker', 'exec', '-i', 'talentra-pg', 'psql', '-U', 'postgres', '-d', db, '-X', '-At'], input=SQL,
                         capture_output=True, text=True, encoding='utf-8')
    if out.returncode:
        raise SystemExit(out.stderr)
    return json.loads(out.stdout)

def owners(cfg):
    """table -> module, from the file that creates it; v1 lookups come from create_lookup_table() calls."""
    owner, lookups = {}, set()
    for f in sorted(os.listdir(cfg['folder'])):
        m = re.match(cfg['pattern'], f)
        if not m:
            continue
        text = open(os.path.join(cfg['folder'], f), encoding='utf-8').read()
        lookups |= {t.lower() for t in re.findall(r"create_lookup_table\(\s*'(\w+)'", text)}
        label = cfg['modules'].get(m.group(1))
        if label:
            for t in re.findall(r'CREATE TABLE (?:IF NOT EXISTS )?(\w+)', text, re.I):
                owner.setdefault(t.lower(), label)
    owner.update(cfg.get('overrides', {}))
    return owner, lookups

def build(key, cfg):
    data = fetch(cfg['db'])
    owner, lookups = owners(cfg)
    tables = {t['name']: t for t in data['tables']
              if t['business'] and not t['lookup'] and t['name'] not in lookups and t['name'] in owner}
    fks = [f for f in data['fks'] if f['parent'] in tables and f['child'] in tables]
    modules = []
    for t in tables:
        if owner[t] not in modules:
            modules.append(owner[t])
    modules.sort(key=lambda m: list(cfg['modules'].values()).index(m))
    lines = ['digraph schema {',
             f'  graph [rankdir=LR, bgcolor="white", fontname="Helvetica", fontsize=22, labelloc=t, label="Talentra {cfg["title"]}  ·  '
             f'{len(tables)} business tables  ·  {len(fks)} foreign keys", pad=0.4, nodesep=0.25, ranksep=0.9, compound=true, newrank=true];',
             '  node [shape=box, style="rounded,filled", fillcolor="white", fontname="Consolas", fontsize=11, height=0.3, margin="0.12,0.04"];',
             '  edge [color="#7b8794", arrowsize=0.6, fontname="Consolas", fontsize=8, fontcolor="#3d4b5c"];']
    for i, m in enumerate(modules):
        c = COLOURS[i % len(COLOURS)]
        lines.append(f'  subgraph "cluster_{i}" {{ label="{m}"; fontname="Helvetica-Bold"; fontsize=15; fontcolor="{c}"; color="{c}"; '
                     f'style="rounded,filled"; fillcolor="{c}10"; penwidth=1.4;')
        for t in sorted(n for n in tables if owner[n] == m):
            extra = ' (partitioned)' if tables[t]['partitioned'] else ''
            lines.append(f'    "{t}" [label="{t}{extra}", color="{c}", penwidth=1.4];')
        lines.append('  }')
    for f in fks:
        if f['parent'] == f['child']:
            attrs = 'arrowhead=normal'
        else:
            attrs = 'arrowhead=tee' if f['unique'] else 'arrowhead=normal'
        style = ', style=dashed' if f['nullable'] else ''
        lines.append(f'  "{f["parent"]}" -> "{f["child"]}" [label="{", ".join(f["cols"])}", {attrs}{style}];')
    lines.append('}')
    dot_src = '\n'.join(lines)
    for fmt in ('svg', 'png'):
        args = [DOT, f'-T{fmt}', '-o', os.path.join(HERE, f'{key}-schema.{fmt}')] + (['-Gdpi=110'] if fmt == 'png' else [])
        subprocess.run(args, input=dot_src, text=True, check=True, encoding='utf-8')
    return len(tables), len(fks), modules

stats = {k: build(k, cfg) for k, cfg in VERSIONS.items()}
md = ['# Talentra schema diagrams', '',
      'Generated from the live PostgreSQL catalogs by `python docs/schema/make_schema_diagram.py`; rerun it after a schema change. '
      'Boxes are tables, grouped and coloured by module; arrows go from the parent table to the child table and are labelled with '
      'the foreign-key column (for example `app_user → app_user_id → user_credential`).', '',
      '**Legend:** arrow = one parent, many children · flat bar = one to one · dashed line = optional (nullable) key. '
      'Business tables only: reference data, lookup tables and the `created_by` / `updated_by` keys on every table are left out.', '',
      'Interactive version (click a table to see its links): https://claude.ai/artifact/RNxTuejDgwdhzBAczCgEhz', '']
for key, (nt, nf, mods) in stats.items():
    cfg = VERSIONS[key]
    md += [f'## {cfg["title"].capitalize()} (`{cfg["db"]}`)', '',
           f'{nt} business tables, {nf} foreign keys, {len(mods)} modules: {", ".join(mods)}.', '',
           f'[![Talentra {cfg["title"]}]({"schema/" + key + "-schema.svg"})]({"schema/" + key + "-schema.svg"})', '',
           f'Open the [SVG](schema/{key}-schema.svg) to zoom without losing sharpness, or the [PNG](schema/{key}-schema.png).', '']
open(os.path.join(ROOT, 'docs', 'schema-diagram.md'), 'w', encoding='utf-8', newline='\n').write('\n'.join(md))
for k, (nt, nf, mods) in stats.items():
    print(k, nt, 'tables', nf, 'fks', len(mods), 'modules')
