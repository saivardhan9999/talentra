-- Milestone 16 (B51-B53): Notifications, Analytics and shared team relationships exist with the stated
-- cardinality and delete rule (same checker as m3, m8, m12), plus the star-schema rules.
\set ON_ERROR_STOP on
CREATE TEMP TABLE expected_fk (child text, cols text, parent text, on_delete char, one_to_one boolean);
-- on_delete: r = RESTRICT, c = CASCADE, n = SET NULL
INSERT INTO expected_fk VALUES
 -- B51 Notifications, preferences and community: preference -> user, delivery -> notification, post -> reaction
 ('user_preference','user_account_id','user_account','c', true),
 ('user_preference','preferred_language_id','language','r', false),
 ('notification_preference','user_account_id','user_account','c', false),
 ('notification_preference','notification_type_id','notification_type','r', false),
 ('notification_preference','outreach_channel_id','outreach_channel','r', false),
 ('job_alert','candidate_profile_id','candidate_profile','c', false),
 ('notification','recipient_user_account_id','user_account','r', false),
 ('notification','job_alert_id','job_alert','n', false),
 ('notification_delivery','notification_id','notification','r', false),
 ('notification_delivery','outreach_channel_id','outreach_channel','r', false),
 ('community_post','author_user_account_id','user_account','r', false),
 ('community_post','parent_community_post_id','community_post','r', false),
 ('community_reaction','community_post_id','community_post','c', false),
 ('community_reaction','user_account_id','user_account','c', false),
 ('support_ticket','raised_by_user_account_id','user_account','r', false),
 ('support_ticket','organisation_id','organisation','r', false),
 ('support_ticket','assigned_to_user_account_id','user_account','r', false),
 ('support_ticket_message','support_ticket_id','support_ticket','r', false),
 ('support_ticket_message','author_user_account_id','user_account','r', false),
 ('faq','question_label_key_id','ui_label_key','r', true),
 ('faq','answer_label_key_id','ui_label_key','r', false),
 ('referral_event','referral_id','referral','r', false),
 ('referral_event','application_id','application','r', false),
 -- B53 Shared: credential -> user, consent -> user, session -> user, audit event -> actor, block -> blocker / blocked
 ('user_credential','user_account_id','user_account','r', false),
 ('consent_record','user_account_id','user_account','r', false),
 ('user_session','user_account_id','user_account','r', false),
 ('audit_event','created_by','user_account','r', false),
 ('block_entry','blocker_user_account_id','user_account','r', false),
 ('block_entry','blocked_user_account_id','user_account','r', false),
 ('block_entry','blocked_organisation_id','organisation','r', false),
 ('system_error_event','created_by','user_account','r', false),
 -- B52 Analytics: fact -> dimension (a sample; the rule below checks every fact and dimension key)
 ('dim_organisation','hq_dim_location_id','dim_location','r', false),
 ('dim_candidate','registered_date_id','dim_date','r', false),
 ('dim_job_requirement','dim_organisation_id','dim_organisation','r', false),
 ('fact_application','dim_job_requirement_id','dim_job_requirement','r', false),
 ('fact_application','dim_candidate_id','dim_candidate','r', false),
 ('fact_application','applied_date_id','dim_date','r', false),
 ('fact_job_posting','dim_job_requirement_id','dim_job_requirement','r', false),
 ('fact_payment','amount_currency_id','currency','r', false),
 ('fact_wallet_transaction','dim_organisation_id','dim_organisation','r', false);

\ir check_expected_fk.sql

DO $$
DECLARE bad text; n int;
BEGIN
    -- Every *_date_id column of an analytical table is an FK to dim_date, and every dim_<x>_id column an FK to dim_<x>
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relkind IN ('r','p') AND c.relname ~ '^(dim|fact)_' AND a.attnum > 0 AND NOT a.attisdropped
      AND (a.attname ~ '_date_id$' OR a.attname ~ 'dim_[a-z_]+_id$')
      AND NOT EXISTS (
          SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f' AND k.conkey = ARRAY[a.attnum]
            AND k.confrelid = (CASE WHEN a.attname ~ '_date_id$' THEN 'dim_date'
                                    ELSE substring(a.attname from '(dim_[a-z_]+)_id$') END)::regclass);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL dimension key without its FK: %', bad; END IF;
    SELECT count(*) INTO n FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
    WHERE k.contype = 'f' AND c.relname ~ '^fact_' AND (SELECT relname FROM pg_class WHERE oid = k.confrelid) ~ '^dim_';
    RAISE NOTICE 'PASS every fact and dimension key is an enforced FK to its dimension (% fact -> dimension FKs)', n;

    -- D19: the marts reference only marts, plus shared master data (currency) and the audit actor
    SELECT string_agg(c.relname || ' -> ' || p.relname, ', ') INTO bad
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_class p ON p.oid = k.confrelid
    WHERE k.contype = 'f' AND c.relname ~ '^(dim|fact)_' AND NOT c.relispartition
      AND p.relname !~ '^(dim|fact)_' AND p.relname NOT IN ('currency', 'user_account');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL analytical table references a transactional table: %', bad; END IF;
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY (k.conkey)
    WHERE k.contype = 'f' AND c.relname ~ '^(dim|fact)_' AND (SELECT relname FROM pg_class WHERE oid = k.confrelid) = 'user_account'
      AND a.attname NOT IN ('created_by', 'updated_by');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL analytical table references a user: %', bad; END IF;
    RAISE NOTICE 'PASS marts reference only marts, currency and the audit actor; source ids are degenerate keys (D19)';

    -- Aggregate -> fact: each aggregate is derived from its facts (materialised-view dependency)
    SELECT string_agg(x.agg || ' needs ' || x.fact, ', ') INTO bad FROM (VALUES
        ('agg_hiring_funnel_monthly', 'fact_application'), ('agg_job_posting_monthly', 'fact_job_posting'),
        ('agg_sourcing_monthly', 'fact_profile_engagement'), ('agg_sourcing_monthly', 'fact_outreach'),
        ('agg_revenue_monthly', 'fact_payment')) x(agg, fact)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_rewrite r JOIN pg_depend d ON d.objid = r.oid AND d.classid = 'pg_rewrite'::regclass
        WHERE r.ev_class = x.agg::regclass AND d.refobjid = x.fact::regclass);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL aggregate not derived from its fact: %', bad; END IF;
    RAISE NOTICE 'PASS aggregate -> fact lineage: 4 aggregates derived from 5 facts';
END $$;
