import os, re, json

migrations_dir = r"C:\Users\gsjit\OneDrive\Documents\talentra\v2\db\migrations"
files = sorted([f for f in os.listdir(migrations_dir) if f.endswith(".sql")])
all_sql = "\n".join(open(os.path.join(migrations_dir, f), encoding="utf-8").read() for f in files)

# Parse lookups
lookups = json.loads(re.search(r"lookups jsonb := '(\{.*?\})';", all_sql, re.S).group(1))

# Parse CREATE TABLE
tables = {}
for m in re.finditer(r'^CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(\w+)\s*\((.*?)\)([^;]*);', all_sql, re.S | re.M):
    tname = m.group(1)
    body = m.group(2)
    tail = m.group(3)
    tables[tname] = {'body': body, 'tail': tail, 'is_lookup': False}

# Add lookup tables
for lk in lookups:
    tables[lk] = {'body': 'lookup table', 'tail': '', 'is_lookup': True}

print(f"Total tables recognized: {len(tables)}")
print(f"  Lookup tables: {len(lookups)}")
print(f"  Other tables: {len(tables) - len(lookups)}")

# Group tables by domain/module
# Let's inspect which file created each table
table_file = {}
for f in files:
    content = open(os.path.join(migrations_dir, f), encoding="utf-8").read()
    for m in re.finditer(r'^CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(\w+)', content, re.M):
        table_file[m.group(1)] = f
for lk in lookups:
    table_file[lk] = "V002__reference_data.sql (via create_lookup)"

file_tables = {}
for t, f in table_file.items():
    file_tables.setdefault(f, []).append(t)

for f in files:
    tbls = file_tables.get(f, [])
    print(f"\n{f}: {len(tbls)} tables")
    for t in sorted(tbls):
        print(f"    - {t}")
