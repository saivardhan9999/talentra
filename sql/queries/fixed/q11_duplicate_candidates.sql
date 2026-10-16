-- Q11 Duplicate candidate detection (data quality, performance): people registered more than once with the same
-- primary phone and the same name (ignoring stray spaces and case) that are not yet flagged as duplicates.
SELECT ph.phone_e164, lower(btrim(p.full_name)) AS name, count(*) AS profiles, array_agg(p.id ORDER BY p.created_at) AS profile_ids
FROM candidate_phone ph
JOIN candidate_profile p ON p.id = ph.candidate_profile_id
WHERE ph.is_primary AND p.deleted_at IS NULL
GROUP BY ph.phone_e164, lower(btrim(p.full_name))
HAVING count(*) > 1 AND bool_and(p.duplicate_of_candidate_profile_id IS NULL)
ORDER BY profiles DESC, ph.phone_e164
LIMIT 25;
