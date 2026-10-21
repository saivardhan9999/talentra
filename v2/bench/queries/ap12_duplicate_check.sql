-- AP-12 Registration duplicate check by phone
-- as: owner
SELECT u.id, p.full_name FROM app_user u LEFT JOIN candidate_profile p ON p.app_user_id = u.id WHERE u.phone_e164 = :'dup_phone';
