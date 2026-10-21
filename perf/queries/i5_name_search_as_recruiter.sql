-- I5 Candidate name search as a recruiter (Profile): best matches first, through the trigram name index, under row-level security
-- as: recruiter_busy
SELECT id, full_name, similarity(full_name, :'cand_name') AS score
FROM candidate_profile
WHERE full_name % :'cand_name' AND deleted_at IS NULL
ORDER BY score DESC
LIMIT 25;
