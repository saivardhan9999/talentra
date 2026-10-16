-- Q9 Skill lookup from what people type (lookup, multilingual): the canonical skill for an English alias,
-- a Hindi alias and a partial name.
SELECT q.typed, m.code, m.name
FROM (VALUES ('Core Java'), ('बिजली की वायरिंग'), ('postgres')) q(typed)
JOIN LATERAL (
    SELECT s.code, s.name FROM skill_alias a JOIN skill s ON s.id = a.skill_id WHERE lower(a.alias_name) = lower(q.typed)
    UNION
    SELECT s.code, s.name FROM skill s WHERE s.name ILIKE q.typed || '%'
) m ON true
ORDER BY q.typed;
