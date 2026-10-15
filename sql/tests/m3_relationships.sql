-- Milestone 3 (B8-B11): key relationships exist with the stated cardinality and delete rule,
-- and no FK relies on an implicit (unstated) update/delete rule.
\set ON_ERROR_STOP on
CREATE TEMP TABLE expected_fk (child text, cols text, parent text, on_delete char, one_to_one boolean);
-- on_delete: r = RESTRICT, c = CASCADE, n = SET NULL
INSERT INTO expected_fk VALUES
 ('candidate_profile','user_account_id','user_account','r', true),
 ('candidate_email','candidate_profile_id','candidate_profile','c', false),
 ('candidate_phone','candidate_profile_id','candidate_profile','c', false),
 ('candidate_address','candidate_profile_id','candidate_profile','c', false),
 ('candidate_education','candidate_profile_id','candidate_profile','c', false),
 ('candidate_work_experience','candidate_profile_id','candidate_profile','c', false),
 ('candidate_skill','candidate_profile_id','candidate_profile','c', false),
 ('candidate_skill','skill_id','skill','r', false),
 ('candidate_language','candidate_profile_id','candidate_profile','c', false),
 ('resume','candidate_profile_id','candidate_profile','c', false),
 ('resume_version','resume_id','resume','c', false),
 ('profile_project','candidate_profile_id','candidate_profile','c', false),
 ('candidate_assessment_result','candidate_profile_id','candidate_profile','c', false),
 ('course_enrolment','candidate_profile_id','candidate_profile','c', false),
 ('profile_view_event','candidate_profile_id','candidate_profile','r', false),
 ('candidate_activity_log','candidate_profile_id','candidate_profile','r', false),
 ('job_requirement','organisation_id','organisation','r', false),
 ('job_requirement_location','job_requirement_id','job_requirement','c', false),
 ('job_requirement_skill','job_requirement_id','job_requirement','c', false),
 ('job_position','job_requirement_id','job_requirement','c', false),
 ('questionnaire_question','questionnaire_id','questionnaire','c', false),
 ('application','job_requirement_id','job_requirement','r', false),
 ('application','candidate_profile_id','candidate_profile','r', false),
 ('application','resume_version_id','resume_version','r', false),
 ('application_status_history','application_id','application','r', false),
 ('application_answer','application_id','application','c', false),
 ('interview','application_id','application','r', false),
 ('offer','application_id','application','r', false),
 ('placement','application_id,job_requirement_id','application','r', true),
 ('placement','job_position_id,job_requirement_id','job_position','r', true),
 ('talent_list','job_requirement_id,organisation_id','job_requirement','r', false),
 ('talent_list_entry','talent_list_id','talent_list','r', false),
 ('talent_list_entry','candidate_profile_id','candidate_profile','r', false);

DO $$
DECLARE r record; bad text; n int := 0;
BEGIN
    FOR r IN SELECT * FROM expected_fk LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint k
            WHERE k.contype = 'f' AND k.conrelid = r.child::regclass AND k.confrelid = r.parent::regclass
              AND k.confdeltype = r.on_delete
              AND (SELECT string_agg(a.attname, ',' ORDER BY u.ord) FROM unnest(k.conkey) WITH ORDINALITY u(attnum, ord)
                   JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = u.attnum) = r.cols)
        THEN
            RAISE EXCEPTION 'FAIL missing FK %(%) -> % with ON DELETE %', r.child, r.cols, r.parent, r.on_delete;
        END IF;
        -- 1:0..1 relationships must be backed by a unique index on the FK column
        IF r.one_to_one AND NOT EXISTS (
            SELECT 1 FROM pg_index x JOIN pg_attribute a ON a.attrelid = x.indrelid AND a.attnum = x.indkey[0]
            WHERE x.indrelid = r.child::regclass AND x.indisunique AND x.indnkeyatts = 1
              AND a.attname = split_part(r.cols, ',', 1))
        THEN
            RAISE EXCEPTION 'FAIL %.% should be unique (1:0..1)', r.child, r.cols;
        END IF;
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'PASS % documented relationships exist with the stated cardinality and ON DELETE rule', n;

    -- Every FK states its rules explicitly (NO ACTION = the engine default, i.e. not stated)
    SELECT string_agg(conrelid::regclass || '.' || conname, ', ') INTO bad FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    WHERE k.contype = 'f' AND NOT c.relispartition AND (k.confdeltype = 'a' OR k.confupdtype = 'a');
    IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL FK without an explicit ON UPDATE/ON DELETE rule: %', bad; END IF;
    SELECT count(*) INTO n FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
    WHERE k.contype = 'f' AND NOT c.relispartition;
    RAISE NOTICE 'PASS all % foreign keys state explicit ON UPDATE and ON DELETE rules', n;
END $$;

-- Print the delete-rule summary for review
SELECT confdeltype AS on_delete, count(*) AS fk_count
FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
WHERE k.contype = 'f' AND NOT c.relispartition GROUP BY 1 ORDER BY 1;
