-- A2 Organisation (B67): the largest corporate groups, walking the parent hierarchy recursively.
WITH RECURSIVE tree AS (
    SELECT id AS root_id, id, 0 AS depth FROM organisation WHERE parent_organisation_id IS NULL
    UNION ALL
    SELECT t.root_id, o.id, t.depth + 1 FROM organisation o JOIN tree t ON o.parent_organisation_id = t.id
)
SELECT r.legal_name AS group_parent, count(*) - 1 AS subsidiaries, max(t.depth) AS levels
FROM tree t JOIN organisation r ON r.id = t.root_id
GROUP BY r.legal_name, t.root_id
HAVING count(*) > 1
ORDER BY subsidiaries DESC, group_parent
LIMIT 10;
