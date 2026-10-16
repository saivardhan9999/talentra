-- Milestone 8 (B27-B29): Administration, Organisation and Gig relationships exist with the stated
-- cardinality and delete rule (same checker as m3).
\set ON_ERROR_STOP on
CREATE TEMP TABLE expected_fk (child text, cols text, parent text, on_delete char, one_to_one boolean);
-- on_delete: r = RESTRICT, c = CASCADE, n = SET NULL
INSERT INTO expected_fk VALUES
 -- Administration: user -> role -> permission, audit event -> actor
 ('user_account','user_account_status_id','user_account_status','r', false),
 ('user_account_role','user_account_id','user_account','r', false),
 ('user_account_role','role_id','role','r', false),
 ('role_permission','role_id','role','c', false),
 ('role_permission','permission_id','permission','c', false),
 ('audit_event','created_by','user_account','r', false),
 ('audit_event','audit_action_id','audit_action','r', false),
 ('audit_event','organisation_id','organisation','r', false),
 -- Organisation: hierarchy, locations, identifiers, recruiter / administrator mapping
 ('organisation','parent_organisation_id','organisation','r', false),
 ('organisation','organisation_type_id','organisation_type','r', false),
 ('organisation','verification_status_id','verification_status','r', false),
 ('organisation','organisation_account_status_id','organisation_account_status','r', false),
 ('organisation_location','organisation_id','organisation','c', false),
 ('organisation_location','city_id','city','r', false),
 ('organisation_registration_identifier','organisation_id','organisation','r', false),
 ('organisation_registration_identifier','verification_status_id','verification_status','r', false),
 ('organisation_member','organisation_id','organisation','r', false),
 ('organisation_member','user_account_id','user_account','r', false),
 ('organisation_member','organisation_member_type_id','organisation_member_type','r', false),
 -- Gig: worker side
 ('gig_worker_profile','user_account_id','user_account','r', true),
 ('gig_worker_service','gig_worker_profile_id','gig_worker_profile','c', false),
 ('gig_worker_availability','gig_worker_profile_id','gig_worker_profile','c', false),
 ('profile_project','gig_worker_profile_id','gig_worker_profile','c', false),
 -- Gig: requester side, application -> assignment -> earnings / rating
 ('gig_request','requester_user_account_id','user_account','r', false),
 ('gig_request','requester_organisation_id','organisation','r', false),
 ('gig_request_skill','gig_request_id','gig_request','c', false),
 ('gig_application','gig_request_id','gig_request','r', false),
 ('gig_application','gig_worker_profile_id','gig_worker_profile','r', false),
 ('gig_assignment','gig_application_id,gig_worker_profile_id','gig_application','r', true),
 ('gig_earning_snapshot','gig_assignment_id','gig_assignment','r', false),
 ('gig_rating','gig_assignment_id','gig_assignment','r', true),
 ('gig_worker_list_entry','owner_user_account_id','user_account','r', false),
 ('gig_worker_list_entry','gig_worker_profile_id','gig_worker_profile','r', false);

\ir check_expected_fk.sql
