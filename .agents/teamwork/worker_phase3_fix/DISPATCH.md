# Dispatch for Phase 3 Fix Worker

## 2026-10-27T09:00:40Z
[Message] timestamp=2026-10-27T09:00:40Z sender=f78290bf-cb2e-40f3-879e-f4c6e5535a5a priority=MESSAGE_PRIORITY_HIGH content=You are the Phase 3 Deliverables Fix Worker.
Your working directory is: C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\worker_phase3_fix
Read the following files before starting:
1. C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\ORIGINAL_REQUEST.md
2. C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\worker_phase3_fix\DISPATCH.md
3. C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\reviewer_phase3_1\handoff.md
4. C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\reviewer_g3_1\handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your task:
1. Inspect and modify `C:\Users\gsjit\OneDrive\Documents\talentra\v2\phase3\tools\build_phase3.py` to fix all 6 review findings:
   a. Storage calculation in Step 13 (line ~156): Adjust the multiplier/formula so that the sum of the Year 3 storage across all 48 tables yields approximately 178.4 GB (< 250 GB target mandated by NFR-SCAL-03), perfectly matching line 73, Section 6, `output-scorecards.md`, and `README.md`.
   b. Workflow matrix indentation bug in Step 16 (lines ~407-451): Fix indentation so lines 414-450 are inside the inner loop `for sid, name, actor, crud in steps:`. All 49 workflow and platform steps (`01.1` through `P.6`) MUST be emitted into the markdown table in Section 1 of `16-schema-coverage-workflow.md`.
   c. Scorecard arithmetic in `output-scorecards.md`: In `build_phase3.py` line ~1043, update the Score row to display `93` across all 9 step columns, matching the weighted sum `(15*5 + 15*5 + 10*5 + 20*5 + 5*1 + 5*4 + 10*5 + 10*4 + 10*5) / 5 = 465 / 5 = 93`.
   d. NFR count in Step 20: In `build_step20()`, update Section 1 line 14 and Section 6 line 174 to state 37 NFRs (matching the 37 rows in Section 5). Update references in `output-scorecards.md` and `README.md` to say 37 NFRs.
   e. Index catalogue in Step 21: In `build_step21()`, expand Section 3 Index Catalogue table to explicitly list access patterns `AP-01` through `AP-14`.
   f. Golden queries in Step 14: In `build_step14()`, include doc notes clarifying:
      - GQ-02: 38 candidate users vs 44 total app users (including 6 recruiters).
      - GQ-03: 1989 credits balance for Blue River.
      - GQ-08: 6 captured orders / 7 total invoices including refund invoice.
2. Run `python v2/phase3/tools/build_phase3.py` using run_command to regenerate all 12 deliverables in `v2/phase3/`.
3. Verify on disk that:
   - `13-data-volumetrics.md` total Year 3 storage is ~178.4 GB and < 250 GB.
   - `16-schema-coverage-workflow.md` Section 1 contains all 49 rows.
   - `output-scorecards.md` displays Score 93.
   - `20-test-suite-v2.md` states 37 NFRs.
   - `21-baseline-er-and-physical-model.md` lists AP-01..AP-14.
4. Write your completion report in `C:\Users\gsjit\OneDrive\Documents\talentra\.agents\teamwork\worker_phase3_fix\handoff.md` and notify with `send_message`.
