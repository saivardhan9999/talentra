-- AP-05 Recruiter name search (typo-tolerant), best matches first
-- as: recruiter
SELECT p.id, p.full_name, similarity(p.full_name, :'common_name' || ' Sharma') AS score
FROM candidate_profile p WHERE p.full_name % (:'common_name' || ' Sharma')
ORDER BY score DESC LIMIT 20;
