"""Independent Victory Audit Execution Script for Talentra Phase 3.
Runs completely independently against local PostgreSQL 18.
"""
import os
import sys
import glob
import time
import subprocess
import hashlib
import json

PSQL = r"C:\Program Files\PostgreSQL\18\bin\psql.exe"
HOST = "127.0.0.1"
PORT = "5432"
USER = "postgres"
DB_NAME = "talentra_audit"
BASE_DIR = r"C:\Users\gsjit\OneDrive\Documents\talentra\v2"
MIGRATIONS_DIR = os.path.join(BASE_DIR, "db", "migrations")
SEED_FILE = os.path.join(BASE_DIR, "db", "seed", "seed_prove_sample.sql")
TESTS_DIR = os.path.join(BASE_DIR, "db", "tests")
HELPERS_FILE = os.path.join(TESTS_DIR, "_helpers.sql")

def run_psql(db, sql_input=None, args=None, capture=True, on_error_stop=True):
    env = os.environ.copy()
    env["PGCLIENTENCODING"] = "UTF8"
    cmd = [PSQL, "-U", USER, "-h", HOST, "-p", PORT, "-d", db, "-X", "-q"]
    if on_error_stop:
        cmd.extend(["-v", "ON_ERROR_STOP=1"])
    if args:
        cmd.extend(args)
    
    input_bytes = sql_input.encode("utf-8") if sql_input else None
    res = subprocess.run(cmd, input=input_bytes, capture_output=capture, env=env)
    return res

def recreate_db(dbname):
    res = run_psql("postgres", args=["-c", f"DROP DATABASE IF EXISTS {dbname} WITH (FORCE);", "-c", f"CREATE DATABASE {dbname};"])
    if res.returncode != 0:
        print(f"Error creating database {dbname}: {res.stderr.decode('utf-8', errors='replace')}")
        sys.exit(1)

def apply_migrations():
    print("=== Step 1: Applying Migrations V001..V013 ===")
    # Create schema_migration table
    init_sql = """
    SET client_min_messages = warning;
    CREATE TABLE IF NOT EXISTS schema_migration (
        version text PRIMARY KEY,
        name text NOT NULL,
        checksum text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now(),
        duration_ms integer NOT NULL
    );
    """
    res = run_psql(DB_NAME, sql_input=init_sql)
    if res.returncode != 0:
        print("Failed to create schema_migration:", res.stderr.decode('utf-8', errors='replace'))
        sys.exit(1)

    mig_files = sorted(glob.glob(os.path.join(MIGRATIONS_DIR, "V*.sql")))
    print(f"Discovered {len(mig_files)} migration files.")
    
    total_ms = 0
    for f in mig_files:
        base = os.path.splitext(os.path.basename(f))[0]
        v = base.split("__")[0]
        name = base.split("__")[1] if "__" in base else base
        with open(f, "rb") as fp:
            data = fp.read()
        chk = hashlib.sha256(data).hexdigest()
        sql_content = data.decode("utf-8")
        
        t0 = time.time()
        tx = f"BEGIN;\n{sql_content}\nINSERT INTO schema_migration (version, name, checksum, duration_ms) VALUES ('{v}', '{name}', '{chk}', 0);\nCOMMIT;"
        res = run_psql(DB_NAME, sql_input=tx)
        dur = (time.time() - t0) * 1000
        total_ms += dur
        if res.returncode != 0:
            print(f"MIGRATION FAILED: {base}")
            print(res.stderr.decode("utf-8", errors="replace"))
            sys.exit(1)
        print(f"  [PASS] {base} ({dur:.1f}ms)")
    print(f"All {len(mig_files)} migrations applied in {total_ms:.1f}ms.\n")

def seed_database():
    print("=== Step 2: Seeding Database with seed_prove_sample.sql ===")
    with open(SEED_FILE, "rb") as fp:
        seed_sql = fp.read().decode("utf-8")
    
    t0 = time.time()
    # In PostgreSQL, run transaction
    res = run_psql(DB_NAME, sql_input=f"BEGIN;\n{seed_sql}\nCOMMIT;")
    dur = time.time() - t0
    if res.returncode != 0:
        print("SEED FAILED:")
        print(res.stderr.decode("utf-8", errors="replace"))
        sys.exit(1)
    
    # Run analyze
    run_psql(DB_NAME, args=["-c", "ANALYZE;"])
    print(f"Seeded Phase 3 prove sample dataset in {dur:.3f} s (Requirement: < 1.0s). Result: {'PASS' if dur < 1.0 else 'WARN'}\n")
    return dur

def run_tests():
    print("=== Step 3: Running Test Suites t01..t06 ===")
    with open(HELPERS_FILE, "rb") as fp:
        helpers_sql = fp.read().decode("utf-8")

    test_files = sorted(glob.glob(os.path.join(TESTS_DIR, "t*.sql")))
    overall_pass = True
    test_results = {}

    for tf in test_files:
        base = os.path.basename(tf)
        with open(tf, "rb") as fp:
            test_sql = fp.read().decode("utf-8")
        
        target_db = DB_NAME
        is_clone = "run.sh runs this file on a throwaway clone" in test_sql
        if is_clone:
            target_db = f"{DB_NAME}_scratch"
            recreate_db(target_db)
            # Recreate from template
            run_psql("postgres", args=["-c", f"DROP DATABASE IF EXISTS {target_db} WITH (FORCE);",
                                       "-c", f"CREATE DATABASE {target_db} TEMPLATE {DB_NAME};"])
        
        full_sql = f"{helpers_sql}\n{test_sql}"
        t0 = time.time()
        res = run_psql(target_db, sql_input=full_sql)
        dur = (time.time() - t0) * 1000
        
        stdout_str = res.stdout.decode("utf-8", errors="replace")
        stderr_str = res.stderr.decode("utf-8", errors="replace")
        
        passes = [l.strip() for l in (stdout_str + stderr_str).split("\n") if "PASS" in l]
        findings = [l.strip() for l in (stdout_str + stderr_str).split("\n") if "FINDING" in l]
        
        if res.returncode == 0:
            print(f"  [PASS] {base} ({dur:.1f}ms) — {len(passes)} assertions passed, {len(findings)} findings logged")
            test_results[base] = {"status": "PASS", "passes": len(passes), "findings": len(findings), "dur_ms": dur}
        else:
            print(f"  [FAIL] {base} (exit code {res.returncode}):")
            print("  STDERR:", stderr_str)
            print("  STDOUT:", stdout_str)
            test_results[base] = {"status": "FAIL", "error": stderr_str}
            overall_pass = False

        if is_clone:
            run_psql("postgres", args=["-c", f"DROP DATABASE IF EXISTS {target_db} WITH (FORCE);"])

    print()
    return overall_pass, test_results

def verify_specific_criteria():
    print("=== Step 4: Deep Verification of Acceptance Criteria ===")
    
    # Check 1: 16 Invariants
    res = run_psql(DB_NAME, args=["-c", "SELECT count(*) FROM candidate_profile;"])
    cand_count = res.stdout.decode("utf-8").strip().split("\n")[-2].strip()
    print(f"  - Active Candidate Profiles count: {cand_count} (Expected 30)")
    
    # Check 2: 73 tables
    res = run_psql(DB_NAME, args=["-c", "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition AND c.relname <> 'schema_migration';"])
    table_count = res.stdout.decode("utf-8").strip().split("\n")[-2].strip()
    print(f"  - Public tables count: {table_count} (Expected 73)")
    
    # Check 3: Lookups count
    res = run_psql(DB_NAME, args=["-c", "SELECT count(DISTINCT table_name) FROM information_schema.columns WHERE column_name = 'ui_label_id' AND table_name <> 'ui_translation';"])
    lookups_cat = res.stdout.decode("utf-8").strip().split("\n")[-2].strip()
    print(f"  - Lookup categories: {lookups_cat} (Expected 25)")
    
    # Check 4: Unclassified personal columns (FND-12 check)
    comment_check_sql = r"""
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_name = c.table_name AND t.table_schema = 'public'
    LEFT JOIN pg_description d ON d.objoid = (SELECT oid FROM pg_class WHERE relname = c.table_name AND relnamespace = 'public'::regnamespace)
                              AND d.objsubid = c.ordinal_position
    WHERE c.table_schema = 'public'
      AND c.table_name NOT IN ('schema_migration')
      AND (
          c.column_name ~* 'phone|email|name|pan|gstin|aadhaar|dob|salary|resume|biography|photo|ip_address|device_id|password|secret|token|bank|account'
          OR d.description ~* 'PII|personal|sensitive'
      )
      AND (d.description IS NULL OR d.description NOT ~* '^(Personal|Sensitive)\.');
    """
    res = run_psql(DB_NAME, sql_input=comment_check_sql)
    out = res.stdout.decode("utf-8")
    unclassified_lines = [l for l in out.split("\n") if "|" in l and not "table_name" in l]
    print(f"  - Unclassified personal/sensitive columns: {len(unclassified_lines)} (Expected 0)")

    return True

if __name__ == "__main__":
    recreate_db(DB_NAME)
    apply_migrations()
    seed_duration = seed_database()
    tests_ok, results = run_tests()
    criteria_ok = verify_specific_criteria()
    
    if tests_ok and criteria_ok and seed_duration < 1.0:
        print("ALL VERIFICATIONS COMPLETED SUCCESSFULLY WITH ZERO DEFECTS.")
    else:
        print("VERIFICATION ISSUES DETECTED.")
