# Talentra — Competitive Coverage Benchmark and Coverage Gap Register

Docket §4 asks every team to compare its data coverage with at least three job platforms (Naukri, Monster (now foundit), LinkedIn): list what each captures on candidate and employer profiles, and show where Talentra matches, exceeds or falls short. The gaps feed the **coverage gap register** that M20 (B66) validates the seeded data against.

The competitor columns describe what each platform visibly asks for or shows on its public product pages and profile forms. They are not taken from any internal data model.
**Legend:** ✔ captured · ◐ partly / free text only · ✘ not captured · — not applicable.

## Candidate profile

| Data element | Naukri | Monster / foundit | LinkedIn | Talentra | Where in Talentra |
|---|---|---|---|---|---|
| Name in any script, language recorded | ◐ | ◐ | ◐ | ✔ **exceeds** | `candidate_profile.full_name` (no script/order assumption), `name_language_id` |
| Headline / summary | ✔ | ✔ | ✔ | ✔ | `headline`, `summary` + `summary_language_id` |
| Contact: multiple emails / phones, verified | ◐ | ◐ | ◐ | ✔ **exceeds** | `candidate_email`, `candidate_phone` (E.164 + country, verified_at, primary) |
| Addresses | ◐ | ◐ | ✘ | ✔ | `candidate_address` (typed, coordinates with source) |
| Date of birth, gender, marital status | ✔ | ✔ | ✘ | ✔ | `candidate_profile` (gender includes non-binary / prefer not to say) |
| Current / expected salary, notice period | ✔ | ✔ | ✘ | ✔ **exceeds** | disclosure status separates "not disclosed" from "not applicable"; currency and period |
| Total experience, fresher flag | ✔ | ✔ | ◐ | ✔ | `total_experience_months`, `is_fresher` (CHECK-consistent) |
| Work history | ✔ | ✔ | ✔ | ✔ | `candidate_work_experience` (role, industry, city, dates) |
| Education with grades | ✔ | ✔ | ✔ | ✔ | `candidate_education` (qualification, field, institution, grade scale) |
| Skills with proficiency / years | ✔ | ✔ | ◐ | ✔ | `candidate_skill` (proficiency, experience months, last used) + multilingual `skill_alias` |
| Skill endorsements by others | ✘ | ✘ | ✔ | ✘ **gap G1** | — |
| Languages with read / write / speak | ✔ | ✔ | ◐ | ✔ | `candidate_language` |
| Certifications | ✔ | ✔ | ✔ | ✔ | `candidate_certification` |
| Projects (incl. gig projects) | ✔ | ◐ | ✔ | ✔ **exceeds** | `profile_project` for candidates and gig workers, with skills and outcome |
| Assessments / test scores | ◐ | ✔ | ◐ | ✔ | `assessment`, `candidate_assessment_result` |
| Courses | ✘ | ◐ | ✔ | ✔ | `course`, `course_enrolment` |
| Resume versions and templates | ✔ | ✔ | ◐ | ✔ **exceeds** | `resume`, `resume_version` (file metadata, template-built body, history) |
| Preferred locations / roles / work mode | ✔ | ✔ | ✔ | ✔ | `candidate_preferred_location`, `candidate_preferred_job_role` |
| Recommendations / references | ✘ | ✘ | ✔ | ✘ **gap G2** | — |
| Volunteer work, awards, publications, patents | ◐ | ✘ | ✔ | ✘ **gap G3** | — (free text in `summary` only) |
| Career break | ✔ | ✘ | ✔ | ✘ **gap G4** | — (inferable from work-history gaps) |
| Disability / diversity self-identification | ✔ | ✘ | ◐ | ✘ **gap G5** | — (deliberately not stored yet: Sensitive, needs consent design) |
| Work authorisation / visa | ✘ | ✔ | ✘ | ✘ **gap G6** | — |
| Preferred shift | ✔ | ◐ | ✘ | ✘ **gap G7** | — (questionnaires can ask per requirement) |
| Social / portfolio links | ✔ | ◐ | ✔ | ✔ | `candidate_social_link` |
| Profile completeness score | ✔ | ✔ | ✔ | ✔ | `profile_completion_pct` + per-section `candidate_profile_section_score` |
| Privacy: visibility, block a company | ✔ | ◐ | ◐ | ✔ **exceeds** | `profile_visibility_id`, `user_preference` privacy flags, `block_entry` enforced by row-level security |
| Consent history | ✘ | ✘ | ◐ | ✔ **exceeds** | `consent_record` (append-only, policy version, evidence) |
| Job alerts / saved searches | ✔ | ✔ | ✔ | ✔ | `job_alert` (multi-criteria, frequency, channel preferences) |
| Who viewed / downloaded my profile | ✔ | ◐ | ✔ | ✔ **exceeds** | `profile_view_event`, `profile_download_event` with the credit deduction |
| Network (connections, followers) | ✘ | ✘ | ✔ | ✘ **gap G8** | — (out of scope: Talentra is not a social network) |

## Employer / company

| Data element | Naukri | Monster / foundit | LinkedIn | Talentra | Where in Talentra |
|---|---|---|---|---|---|
| Company profile (industry, size, founded, website, logo) | ✔ | ✔ | ✔ | ✔ | `organisation` |
| Multiple locations, headquarters | ◐ | ◐ | ✔ | ✔ | `organisation_location` (one HQ enforced) |
| Corporate hierarchy (group, subsidiaries) | ✘ | ✘ | ◐ | ✔ **exceeds** | `parent_organisation_id` with cycle prevention |
| Tax / registration identifiers, verification | ◐ | ◐ | ✘ | ✔ **exceeds** | `organisation_registration_identifier` (token + HMAC + masked; verified evidence) |
| Mapped recruiters with history | ◐ | ◐ | ◐ | ✔ **exceeds** | `organisation_member` (effective-dated, no overlap) |
| Company specialties, followers, culture pages | ◐ | ◐ | ✔ | ✘ **gap G9** | — |
| Company reviews and ratings | ✔ (AmbitionBox) | ◐ | ✘ | ✘ **gap G10** | Tier 3, not built |
| Salary benchmarks | ✔ | ◐ | ✔ | ✘ **gap G11** | Tier 3, not built |

## Jobs and hiring workflow

| Data element | Naukri | Monster / foundit | LinkedIn | Talentra | Where in Talentra |
|---|---|---|---|---|---|
| Requirement with salary range, experience range, skills, locations | ✔ | ✔ | ✔ | ✔ | `job_requirement` (+ CHECKs), `job_requirement_skill/location/qualification` |
| Positions tracked individually | ✘ | ✘ | ✘ | ✔ **exceeds** | `job_position`, `placement` |
| Screening questionnaires with knock-outs | ✔ | ✔ | ✔ | ✔ | `questionnaire*`, `application_answer` |
| Full pipeline with history | ◐ | ◐ | ◐ | ✔ **exceeds** | `application_status_history`, transition table, interviews, offers |
| Consultant / agency sourcing marketplace | ✘ | ✘ | ✘ | ✔ **exceeds** | `sourcing_request`, consultant shortlists |
| Bulk outreach with delivery status | ✔ | ✔ | ✔ (InMail) | ✔ | `outreach_batch`, `outreach_recipient` |
| Gig marketplace (windows, pricing, assignments, ratings) | ✘ | ✘ | ✘ | ✔ **exceeds** | gig module (separate subsystem, D3) |
| Licences, seats, device limits | ◐ | ◐ | ◐ | ✔ **exceeds** | licences module (limits enforced under concurrency) |
| Credits wallet with ledger | ✔ | ◐ | ✘ | ✔ **exceeds** | `wallet`, append-only `wallet_ledger_entry` |
| Trending job snapshots, feature flags | ◐ | ◐ | ◐ | ✘ **gap G12** | Tier 3, not built |

## Coverage gap register

| Id | Gap | Priority | Decision | Validation in M20 |
|---|---|---|---|---|
| G1 | Skill endorsements | Low | Not planned: social feature, weak signal for hiring decisions | none (not modelled) |
| G2 | Recommendations / references | Medium | Future: `candidate_reference` with consent of the referee | none (not modelled) |
| G3 | Volunteer work, awards, publications, patents | Low | Future: one `candidate_achievement` table with a type lookup | none |
| G4 | Career break | Medium | Future: typed entry in `candidate_work_experience` (`is_career_break`) | finding: gaps in work history are not flagged |
| G5 | Disability / diversity self-identification | Medium | Deferred: Sensitive class, needs explicit consent purpose and access design (M22) | none (deliberately not stored) |
| G6 | Work authorisation / visa | Low (India-first) | Future: `candidate_work_authorisation` per country | none |
| G7 | Preferred shift | Medium | Covered per requirement by questionnaires; profile field later | finding: shift preference only in questionnaire answers |
| G8 | Professional network | Out of scope | Not a social network | none |
| G9 | Company culture pages, followers | Low | Future content module | none |
| G10–G12 | Reviews, salary benchmarks, trending snapshots, feature flags | Tier 3 | Optional; not built | none |
| Q1 | Duplicate registrations | High (data quality) | Dedupe on phone + normalised name; flag with `duplicate_of_candidate_profile_id` | **finding counted** (unflagged duplicate groups) |
| Q2 | Names with stray whitespace from imports | Medium | Normalise at import; keep raw for audit | **finding counted** |
| Q3 | Joined applications without a placement | Medium | Positions exhausted: placement recorded when a position is reopened | **finding counted** |
| Q4 | Unverified contact details | Medium | Verification campaign; outreach prefers verified numbers | **finding counted** |

**Summary.** Talentra matches the three platforms on the core candidate and employer profile. It exceeds all three on what this platform is for: multilingual data, the full hiring pipeline with positions and placements, the consultant marketplace, gigs, licences and devices, the credit ledger, consent and blocking enforced in the database, and download history with the charge. It falls short on social-network features (endorsements, recommendations, network), some self-identification fields, and the optional Tier 3 reference data.
