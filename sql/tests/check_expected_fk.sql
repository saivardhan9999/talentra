-- Checks the expected_fk rows inserted by the including script (m3, m8): each relationship exists
-- with the stated columns, ON DELETE rule and cardinality, and no FK relies on an implicit rule.
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
