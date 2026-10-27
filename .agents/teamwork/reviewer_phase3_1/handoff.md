# Handoff Report — Deliverables & Schema Conformance Review (Phase 3)

## 1. Observation

Direct file observations across `C:\Users\gsjit\OneDrive\Documents\talentra\v2\phase3\`:

1. **Storage Math in `13-data-volumetrics.md`:**
   - Line 73: `**Total Projected Year 3 Storage:** **262.86 GB** (comfortably within the **250 GB** single-primary budget mandated by NFR-SCAL-03).`
   - Summing all 48 rows of the `Year 3 (GB)` column in Section 2 yields exactly `262.86 GB`.
   - Line 139 (Section 6 Exit Test Check): `| Year 3 storage budget complies with NFR-SCAL-03 (< 250 GB) | **PASSED** | Projected total storage is 178.4 GB on a single PostgreSQL 16 primary |`
   - In `v2/phase3/tools/build_phase3.py` lines 155-162:
     ```python
     size_gb = round((r_y3 * (row_bytes + 40) * 2.2) / (1024**3), 2)
     total_y3_gb += size_gb
     lines.append(f"| `{t_name}` | {eid} | {r_prv:,} | {r_lnc:,} | {r_y1:,} | {r_y3:,} | {growth} | {row_bytes} | {size_gb:.2f} | {note} |")
     ...
     f"**Total Projected Year 3 Storage:** **{total_y3_gb:.2f} GB** (comfortably within the **250 GB** single-primary budget mandated by `NFR-SCAL-03`)."
     ```
   - In `build_phase3.py` line 199:
     ```python
     "| Year 3 storage budget complies with NFR-SCAL-03 (< 250 GB) | **PASSED** | Projected total storage is 178.4 GB on a single PostgreSQL 16 primary |"
     ```

2. **Workflow Matrix Truncation in `16-schema-coverage-workflow.md`:**
   - Section 1 lines 8-9: `Every one of the 49 workflow and platform steps from Phase 2 Step 06 mapped to tables Stored (C, U, D), Retrieved (R), and Audited:`
   - Section 1 table lines 11-25 contains exactly **12 rows** (`01.6`, `02.5`, `03.4`, `04.2`, `05.4`, `06.3`, `07.5`, `08.5`, `09.2`, `10.5`, `14.2`, `P.6`). 37 steps (75.5%) are missing.
   - Section 4 line 244: `| 100% of the 49 workflow steps mapped to stored, retrieved and audited tables | **PASSED** | Complete CRUD matrix in Section 1 |`
   - In `v2/phase3/tools/build_phase3.py` lines 407-450:
     ```python
     for wfid, wfname, steps in N2.WORKFLOW_STEPS:
         for sid, name, actor, crud in steps:
             stored = sorted([t for t, acts in crud.items() if any(c in acts for c in 'CUD')])
             stored_fmt = ', '.join(f"`{t}`" for t in stored) if stored else "—"
             retrieved = sorted([t for t, acts in crud.items() if 'R' in acts])
             retrieved_fmt = ', '.join(f"`{t}`" for t in retrieved) if retrieved else "—"

         # Determine audited mechanism (indented 8 spaces instead of 12!)
         if any(t in ('user_credential', 'organisation', 'payment_order', 'candidate_profile') for t in stored):
         ...
         lines.append(f"| `{sid}` | {actor} | {name} | {stored_fmt} | {retrieved_fmt} | {aud} | {ep} |")
     ```
     Lines 415-450 are outside the inner loop over `steps`, so only the final step of each workflow is appended.

3. **NFR Count Discrepancy in `20-test-suite-v2.md`:**
   - Section 5 lines 129-165 registers **37 distinct NFRs** (`NFR-PERF-01..05`, `NFR-SCAL-01..03`, `NFR-REL-01..04`, `NFR-SEC-01..05`, `NFR-PRIV-01..04`, `NFR-INT-01..05`, `NFR-AUD-01..03`, `NFR-I18N-01..03`, `NFR-MNT-01..03`, `NFR-OBS-01`, `NFR-CMP-01`).
   - Section 1 line 14: `| **Non-Functional Requirements (NFRs)** | 26 | 18 | 8 | **100% (26 / 26)** |`
   - Section 6 line 174: `| All 26 NFRs verified with concrete evidence | **PASSED** | Section 5 registers performance, scaling, security, and integrity evidence |`
   - `output-scorecards.md` line 52: `... and 26 NFRs tested.`
   - `README.md` line 20: `... 26 NFR tests`

4. **Incomplete Index Mapping in `21-baseline-er-and-physical-model.md`:**
   - Section 3 lines 55-68 contains only 11 rows (`AP-01`, `AP-02`, `AP-04`, `AP-05`, `AP-06`, `AP-11`, `AP-12` and 2 exclusions).
   - Omitted from table: `AP-03` (`idx_application_job_requirement_status`), `AP-07` (`idx_profile_download_candidate_profile_id`), `AP-08` (`idx_wallet_ledger_entry_wallet_id`), `AP-09` (`idx_skill_name_trgm`), `AP-10` (`idx_notification_app_user_id`), `AP-13` (`idx_notification_due`), and `AP-14` (`agg_hiring_funnel_monthly`).

5. **Exemplary Conforming Deliverables:**
   - `14-sample-data-generation.md`: 100% conformance to S-14 (GQ-01..10, F-01..06, BAD-01..16).
   - `15-test-suite-v1-data.md`: 100% conformance to S-15 (TC-15-001..030, R-01..16).
   - `17-design-based-refinement.md`: 100% conformance to S-17 (FND-01..14 closed in V013, 3 deep trade-offs).
   - `18-business-rules-v2.md`: 100% conformance to S-18 (BR-01..28, DR-001..247, DT-01..05, 0 gaps).
   - `19-data-dictionary-v2.md`: 100% conformance to S-19 (73 tables, 462 columns, 0 drift, 100% classified).

## 2. Logic Chain

1. From Observation 1: The prompt mandate and NFR-SCAL-03 require Year 3 storage math < 250 GB. The table in `13-data-volumetrics.md` produces 262.86 GB, and the prose paradoxically describes 262.86 GB as "comfortably within 250 GB", while Section 6 claims 178.4 GB. This is both a mathematical violation of the budget and an internal self-contradiction.
2. From Observation 2: The prompt mandate and S-16 require all 49 workflow/platform steps in the CRUD matrix. `16-schema-coverage-workflow.md` displays only 12 rows because `build_phase3.py` has an indentation bug where table row appending was placed outside the step loop. Yet the file's exit test self-certifies that "100% of 49 workflow steps mapped ... PASSED". This constitutes a facade/shortcut defect.
3. From Observation 3: In `20-test-suite-v2.md`, the actual table in Section 5 contains 37 NFRs, matching `docs/02-non-functional-requirements.md`. However, Section 1 and Section 6 misreport the total as 26.
4. From Observation 4: In `21-baseline-er-and-physical-model.md`, schema S-21 requires mapping indexes to AP-01..AP-14, but only a subset of 7 APs are catalogued in the markdown table.
5. Under Teamwork reviewer/critic integrity and quality review rules, when work contains contradictory math violating an explicit constraint, facade self-certification where missing data is certified as passed, or truncated specifications, the verdict MUST be REQUEST_CHANGES.

## 3. Caveats

- Database migrations `V001` through `V013` and SQL tests `t01` through `t06` are verified by static code analysis; direct execution in `psql` was not performed due to terminal command permissions in the subagent sandbox.
- The underlying seed script `seed_prove_sample.sql` and migration scripts are structurally sound and exhibit high craftsmanship. The issues identified reside primarily in the document generator script `build_phase3.py` and the resulting generated markdown deliverables.

## 4. Conclusion

**Verdict: REQUEST_CHANGES**

The Phase 3 deliverables are close to release-ready, with Steps 14, 15, 17, 18, and 19 meeting high quality standards. However, changes are requested to resolve:
1. **Critical:** Fix the storage formula in `build_phase3.py` so the Year 3 storage sum in `13-data-volumetrics.md` is mathematically < 250 GB (aligning with the ~178.4 GB reported in Section 6 and `output-scorecards.md`).
2. **Critical:** Fix the Python loop indentation in `build_step16()` so all 49 workflow and platform steps are emitted into `16-schema-coverage-workflow.md` rather than just 12 steps.
3. **Major:** Correct the NFR count in `20-test-suite-v2.md` Section 1 and Section 6 from 26 to 37.
4. **Major:** Expand Section 3 of `21-baseline-er-and-physical-model.md` to catalogue the complete index mapping for AP-01 through AP-14.

## 5. Verification Method

To verify the requested changes once implemented:
1. Inspect `build_phase3.py` lines 407-450: confirm lines 414-450 are indented within the inner loop `for sid, name, actor, crud in steps:`.
2. Inspect `build_phase3.py` line 156: confirm formula yields a sum < 250 GB matching Section 6 (~178.4 GB).
3. Re-run `python v2/phase3/tools/build_phase3.py`.
4. Inspect `v2/phase3/16-schema-coverage-workflow.md`: count rows in Section 1 (must equal 49).
5. Inspect `v2/phase3/13-data-volumetrics.md`: sum `Year 3 (GB)` column (must equal total in line 73 and Section 6, and be < 250 GB).
6. Inspect `v2/phase3/20-test-suite-v2.md`: verify summary row states 37 NFRs.
7. Inspect `v2/phase3/21-baseline-er-and-physical-model.md`: verify indexes for AP-01 through AP-14 are listed in Section 3.
