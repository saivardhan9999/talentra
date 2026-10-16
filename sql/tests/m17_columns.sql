-- Milestone 17 (B54-B56): Notifications, Analytics and shared team columns carry a type, standard domain,
-- justified nullability and an explicit sensitive-data class (same rules as m9 and m13, for Phase 4), plus
-- the credential class B56 calls out and the analytics privacy rule (D19).
\set ON_ERROR_STOP on
SET t.phase = '4';
\ir check_columns.sql

DO $$
DECLARE bad text;
BEGIN
    -- B56: credentials are Sensitive, and stored only as an adaptive hash or a keyed hash
    SELECT string_agg(c, ', ') INTO bad FROM unnest(ARRAY['password_hash', 'provider_subject_hmac']) c
    WHERE coalesce(col_description('user_credential'::regclass,
                   (SELECT attnum FROM pg_attribute WHERE attrelid = 'user_credential'::regclass AND attname = c)), '') !~ 'class=Sensitive';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL credential column not classed Sensitive: %', bad; END IF;
    -- schema-wide: nothing that looks like a secret is stored except as a hash
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace s ON s.oid = c.relnamespace
    WHERE s.nspname = 'public' AND c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0 AND NOT a.attisdropped
      AND a.attname ~ '(password|secret|otp|pin_code|api_key)' AND a.attname !~ '_(hash|hmac)$';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL secret-like column not stored as a hash: %', bad; END IF;
    RAISE NOTICE 'PASS credentials are Sensitive and stored only as an argon2id hash or an HMAC (B56)';

    -- D19: the analytical layer carries no Personal or Sensitive column
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relkind IN ('r','p') AND c.relname ~ '^(dim|fact|agg)_' AND a.attnum > 0
      AND col_description(c.oid, a.attnum) ~ 'class=(Personal|Sensitive)';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL personal data in the analytical layer: %', bad; END IF;
    SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO bad
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relkind IN ('r','p','m') AND c.relname ~ '^(dim|fact|agg)_' AND a.attnum > 0
      AND a.attname ~ '(email|phone|full_name|given_name|family_name|address|birth)';
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL identifier column in the analytical layer: %', bad; END IF;
    RAISE NOTICE 'PASS analytical layer holds no Personal or Sensitive data (bands and codes only, D19)';

    -- Consent evidence: what was agreed, which version, granted or withdrawn, when
    SELECT string_agg(c, ', ') INTO bad FROM unnest(ARRAY['consent_purpose_id', 'policy_version', 'is_granted', 'recorded_at']) c
    WHERE NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'consent_record'::regclass AND attname = c AND attnotnull);
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL consent_record missing mandatory evidence column: %', bad; END IF;
    RAISE NOTICE 'PASS consent records state purpose, policy version, grant or withdrawal and time';

    -- Messaging boundary: the stored notification text is short (summary for the in-app list and audit only)
    IF (SELECT format_type(atttypid, atttypmod) FROM pg_attribute WHERE attrelid = 'notification'::regclass AND attname = 'summary')
       <> 'character varying(300)' THEN
        RAISE EXCEPTION 'FAIL notification.summary must stay a short bounded string';
    END IF;
    RAISE NOTICE 'PASS notification text limited to a 300-character summary (messaging boundary)';

    -- User-entered community text records its language where known (rule group 7)
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'community_post'::regclass AND attname = 'body_language_id') THEN
        RAISE EXCEPTION 'FAIL community_post must record the language of its text';
    END IF;
    RAISE NOTICE 'PASS community text records its language (rule group 7)';
END $$;
