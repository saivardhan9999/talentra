-- AP-09 Skill type-ahead on two typed letters
-- as: candidate
SELECT id, name FROM skill WHERE lower(name) LIKE 'py%' OR lower(name) % 'pyth' ORDER BY lower(name) LIKE 'py%' DESC, name LIMIT 10;
