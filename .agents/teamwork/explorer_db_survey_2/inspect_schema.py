import os, re, json

migrations_dir = r"C:\Users\gsjit\OneDrive\Documents\talentra\v2\db\migrations"
files = sorted([f for f in os.listdir(migrations_dir) if f.endswith(".sql")])

print(f"Total migration files: {len(files)}")
for f in files:
    path = os.path.join(migrations_dir, f)
    size = os.path.getsize(path)
    print(f"  {f} ({size} bytes)")

all_sql = {}
for f in files:
    with open(os.path.join(migrations_dir, f), encoding="utf-8") as fp:
        all_sql[f] = fp.read()

combined_sql = "\n".join(all_sql.values())

# 1. Domains
domains = re.findall(r'CREATE DOMAIN\s+(\w+)\s+AS\s+([^;]+);', combined_sql)
print(f"\nDomains ({len(domains)}):")
for d, spec in domains:
    print(f"  - {d}: {spec.strip()}")

# 2. Lookups from V002
lookups_match = re.search(r"lookups jsonb := '(\{.*?\})';", combined_sql, re.S)
if lookups_match:
    lookups = json.loads(lookups_match.group(1))
    print(f"\nLookup tables in V002 ({len(lookups)}):")
    for k, v in sorted(lookups.items()):
        print(f"  - {k} ({len(v)} values): {', '.join(x[0] for x in v)}")

# 3. Tables created via CREATE TABLE
table_creates = []
for f, content in all_sql.items():
    for m in re.finditer(r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(\w+)\s*\((.*?)\)([^;]*);', content, re.S):
        tname = m.group(1)
        body = m.group(2)
        tail = m.group(3)
        table_creates.append((f, tname, body, tail))

print(f"\nExplicit CREATE TABLE statements ({len(table_creates)}):")
for f, tname, body, tail in table_creates:
    lines = [line.strip() for line in body.split('\n') if line.strip() and not line.strip().startswith('--')]
    print(f"  - {tname} in {f} ({len(lines)} def lines)")

# 4. Triggers
triggers = re.findall(r'CREATE TRIGGER\s+(\w+)\s+(BEFORE|AFTER)\s+([^;]+?)\s+ON\s+(\w+)\s+FOR EACH ROW\s+EXECUTE FUNCTION\s+(\w+)\((.*?)\);', combined_sql)
print(f"\nTriggers ({len(triggers)}):")
for tg, timing, events, tbl, fn, args in triggers:
    print(f"  - {tg} on {tbl} ({timing} {events.strip()}) -> {fn}()")

# 5. Functions
functions = re.findall(r'CREATE\s+(?:OR REPLACE\s+)?FUNCTION\s+(\w+)\s*\((.*?)\)\s*RETURNS\s+([^;]+?)\s+LANGUAGE', combined_sql, re.S)
print(f"\nFunctions ({len(functions)}):")
for fn, args, ret in functions:
    clean_args = " ".join(args.split())
    clean_ret = " ".join(ret.split())
    print(f"  - {fn}({clean_args}) -> {clean_ret}")
