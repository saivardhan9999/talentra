-- AP-11 Login: device-limit check and session open (write)
-- as: owner
SELECT auth_open_session(:cand_user, sha256('bench-device'::bytea), 'bench', sha256(gen_random_uuid()::text::bytea));
