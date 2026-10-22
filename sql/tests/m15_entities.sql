-- Milestone 15 (B48-B50): Notifications, Analytics and shared team entities exist; every docket item
-- maps to an entity; analytical objects are prefixed; every KPI has a fact and an aggregate path.
\set ON_ERROR_STOP on
\ir expected_entity.sql

DO $$
DECLARE bad text; n int;
BEGIN
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity e
    WHERE e.phase = 4 AND to_regclass(e.table_name) IS NULL;
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL expected entity missing: %', bad; END IF;
    FOR bad, n IN SELECT module, count(*) FROM expected_entity WHERE phase = 4 GROUP BY module ORDER BY module LOOP
        RAISE NOTICE 'PASS % : % entities present', rpad(bad, 22), n;
    END LOOP;

    -- Every docket item for B48 and B50 maps to a table (or a column where the item is a setting)
    SELECT string_agg(item, ', ') INTO bad FROM (VALUES
        ('notification preferences', 'notification_preference', NULL), ('job alert preferences', 'job_alert', NULL),
        ('language preference', 'user_preference', 'preferred_language_id'), ('privacy settings', 'user_preference', 'allow_profile_download'),
        ('notification deliveries', 'notification_delivery', NULL), ('community posts', 'community_post', NULL),
        ('reactions', 'community_reaction', NULL), ('support tickets', 'support_ticket', NULL), ('FAQs', 'faq', NULL),
        ('referral events', 'referral_event', NULL),
        ('credentials', 'user_credential', NULL), ('consent records', 'consent_record', NULL),
        ('identity sessions (D15)', 'user_session', NULL), ('audit trail', 'audit_event', NULL),
        ('blocking lists', 'block_entry', NULL), ('system errors (Tier 1)', 'system_error_event', NULL)) v(item, tbl, col)
    WHERE to_regclass(v.tbl) IS NULL
       OR (v.col IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = v.tbl::regclass AND attname = v.col));
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL docket item without an entity: %', bad; END IF;
    RAISE NOTICE 'PASS all 16 notification, preference, community and shared-item docket entries map to an entity';

    -- Rule group 8: analytical objects are prefixed, and only analytical objects use the prefixes
    SELECT string_agg(table_name, ', ') INTO bad FROM expected_entity
    WHERE (module = 'analytics') <> (table_name ~ '^(dim|fact|agg)_');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL analytics prefix rule broken by: %', bad; END IF;
    SELECT string_agg(c.relname, ', ') INTO bad FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind = 'm' AND c.relname !~ '^agg_';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL materialised view without agg_ prefix: %', bad; END IF;
    RAISE NOTICE 'PASS analytical objects prefixed dim_ / fact_ / agg_ (rule group 8)';

    -- Aggregates are materialised views that read only facts and dimensions
    SELECT count(*) INTO n FROM pg_class WHERE relkind = 'm' AND relname ~ '^agg_';
    IF n < 4 THEN RAISE EXCEPTION 'FAIL expected 4 aggregates, found %', n; END IF;
    SELECT string_agg(DISTINCT v.relname || ' -> ' || t.relname, ', ') INTO bad
    FROM pg_class v JOIN pg_rewrite r ON r.ev_class = v.oid JOIN pg_depend d ON d.objid = r.oid AND d.classid = 'pg_rewrite'::regclass
    JOIN pg_class t ON t.oid = d.refobjid AND t.oid <> v.oid
    WHERE v.relkind = 'm' AND t.relkind IN ('r','p') AND t.relname !~ '^(dim|fact)_';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL aggregate reads a transactional table: %', bad; END IF;
    RAISE NOTICE 'PASS % aggregates (materialised views) read only facts and dimensions', n;

    -- KPI coverage (KPI set derived from the §2 workflows, see phase4-design.md)
    SELECT string_agg(kpi, ', ') INTO bad FROM (VALUES
        ('applications and stage conversion', 'fact_application', 'agg_hiring_funnel_monthly'),
        ('time to shortlist / time to hire', 'fact_application', 'agg_hiring_funnel_monthly'),
        ('requirements posted, fill rate, time to fill', 'fact_job_posting', 'agg_job_posting_monthly'),
        ('profile views, downloads and credits used', 'fact_profile_engagement', 'agg_sourcing_monthly'),
        ('outreach delivery and response rate', 'fact_outreach', 'agg_sourcing_monthly'),
        ('consultant request acceptance and decision time', 'fact_sourcing_request', NULL),
        ('revenue, refunds and credits sold', 'fact_payment', 'agg_revenue_monthly'),
        ('credits consumed by purpose', 'fact_wallet_transaction', NULL),
        ('gig fill, earnings and rating', 'fact_gig_assignment', NULL),
        ('logins and device-limit refusals', 'fact_login_daily', NULL),
        ('notification delivery rate', 'fact_notification_daily', NULL),
        ('support volume and resolution time', 'fact_support_ticket', NULL),
        ('candidate supply and profile completeness', 'dim_candidate', NULL)) k(kpi, fact, agg)
    WHERE to_regclass(k.fact) IS NULL OR (k.agg IS NOT NULL AND to_regclass(k.agg) IS NULL);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL KPI without its fact or aggregate: %', bad; END IF;
    RAISE NOTICE 'PASS 13 KPIs each have a fact (and an aggregate where pre-computed)';

    -- Messaging boundary (docket §6): no message body is stored for notifications
    IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid IN ('notification'::regclass, 'notification_delivery'::regclass)
               AND attname ~ '(body|content|html)' AND NOT attisdropped) THEN
        RAISE EXCEPTION 'FAIL notification stores a message body';
    END IF;
    RAISE NOTICE 'PASS notifications keep template reference and summary only (messaging boundary)';
END $$;
