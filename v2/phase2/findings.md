# Phase 2 — Findings for the rebuild

Reconciled directly against the PostgreSQL physical DDL (`db/migrations/V001..V013`) with zero catalog drift.

What the Model phase found that the v2 model does not enforce or protect yet. Each finding names the step that found it, its severity (roadmap p.11: high blocks green, medium is fixed in this pass or deferred with a reason, low when convenient) and the fix the rebuild should make.

| ID | Step | Severity | Where | Finding | Fix in the rebuild |
|---|---|---|---|---|---|
| FND-01 | 08 | high | job_requirement | A published job can return to draft: job_status_id and published_at are both updatable by the API role, and ck_job_requirement_published only ties draft to published_at IS NULL. FR-JOB-02 forbids it. | job_status_transition table + guard trigger (like the application pipeline); published_at immutable once set. |
| FND-02 | 08 | medium | job_requirement | closed and filled jobs can be reopened by any status update; no transition rule exists for jobs. | same transition table: closed and filled are final; paused ↔ open only. |
| FND-03 | 08 | high | organisation | No entry point lets staff verify or reject an organisation (FR-ORG-06); only the schema owner can change verification_status_id. | organisation_set_verification() definer function, staff only, transitions pending → verified / rejected, rejected → pending; audited. |
| FND-04 | 08 | medium | user_device | No entry point revokes a device (FR-IAM-06); revoked_at exists but no role can set it. | auth_revoke_device(): owner or staff, ends the device sessions, audited. |
| FND-05 | 08 | medium | app_user | Account status has no transition rule: suspend and deactivate have no entry point, and nothing stops erased → active except the email check. | account_status transitions in a guard: erased is final; staff-only suspend and reactivate. |
| FND-06 | 08 | low | subscription | subscription_guard does not stop cancelled_at being cleared, so a cancellation can be undone silently. | guard: cancelled_at may go from NULL to a value only. |
| FND-07 | 08 | low | organisation_member, candidate_block | valid_to and unblocked_at can be set back to NULL, reopening a closed period instead of starting a new row. | guard: closing timestamps are write-once; reopening inserts a new row. |
| FND-08 | 08 | low | notification | notification_record_result accepts any status code without checking the current status (delivered → queued is possible). | check the move against notification status transitions inside the function. |
| FND-09 | 12 | high | consent_record, notification | Consent purposes marketing_email, whatsapp_alerts and profile_visible_to_recruiters exist but nothing reads them: marketing notifications and recruiter visibility do not check consent. | notification_apply_preference also checks consent_current for marketing and WhatsApp; profile visibility requires the consent. |
| FND-10 | 12 | medium | application_answer | Erasure keeps answer_text (personal free text) on applications it keeps. | candidate_erase blanks answer_text to "erased". |
| FND-11 | 12 | low | user_device | Erasure keeps device_label (e.g. "Priya's iPhone"). | candidate_erase blanks device_label. |
| FND-12 | 12 | medium | profile sections | Columns without a class comment default to Internal, so profile content such as institution, company and job title is labelled Internal although it is personal data. | apply the classification rule of step 12 in the column comments (reclassification list in the register). |
| FND-13 | 11 | medium | organisation, wallet | "Every organisation has exactly one wallet": at most one is a constraint, at least one only holds when the organisation is created through auth_register_employer. | deferred constraint trigger, or create the wallet in an organisation AFTER INSERT trigger. |
| FND-14 | 11 | medium | user_credential | Account lockout after repeated failures relies on the auth service alone; the columns exist but no database rule uses them. | auth_record_login_failure() function that increments, locks and audits in one transaction. |

**Total:** 14 — high 3, medium 7, low 4.
