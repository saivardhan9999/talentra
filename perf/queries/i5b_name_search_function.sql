-- I5b Candidate name search as a recruiter through app_search_candidates_by_name (same rule, trigram index usable)
-- as: recruiter_busy
SELECT id, full_name, score FROM app_search_candidates_by_name(:'cand_name', 25);
