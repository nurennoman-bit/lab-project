-- ADMIN PASSWORD BHULE GELE / ALADA PASSWORD DIYE ACCOUNT AGE THEKE THAKLE:
-- 1) Niche 'NOTUN_PASSWORD' er jaygay tomar notun password lekho (kompokkhe 6 char, quote er bhitore)
-- 2) Supabase > SQL Editor > New query > paste > RUN
-- 3) App e nuren@gmail.com + oi notun password diye login koro
update auth.users
set encrypted_password = extensions.crypt('NOTUN_PASSWORD', extensions.gen_salt('bf')),
    email_confirmed_at = coalesce(email_confirmed_at, now())
where lower(email) = 'nuren@gmail.com';
