-- =============================================================================
-- CekDulu seed: test accounts (LOCAL / STAGING ONLY - never production)
-- -----------------------------------------------------------------------------
-- Links the Supabase Auth test users to their app profiles and assigns roles:
--   admin@test.local -> role 'admin'
--   user@test.local  -> role 'user'
--
-- PREREQUISITE: the auth users must already exist in auth.users. Create them
-- first via the Supabase Auth Admin API (service_role key) as documented in
-- seed_test_accounts.md. This script only links/promotes their profiles.
--
-- Idempotent: safe to re-run (INSERT ... ON CONFLICT DO UPDATE).
--
-- Execution (fail-closed guard requires app.env=local|staging):
--   PGOPTIONS="-c app.env=local" psql "$DATABASE_URL" -f seed.sql
--
-- NEVER run this against production. The guard below aborts when app.env is
-- anything other than 'local' or 'staging' (including unset).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Fail-closed guard: refuse to seed unless explicitly targeting local/staging.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_env TEXT := current_setting('app.env', true);
BEGIN
  IF v_env IS DISTINCT FROM 'local' AND v_env IS DISTINCT FROM 'staging' THEN
    RAISE EXCEPTION
      'SEED BLOCKED (fail-closed): app.env must be ''local'' or ''staging'', got %. Aborting.',
      COALESCE(v_env, '<unset>');
  END IF;
  RAISE NOTICE 'Seed guard passed: app.env = %', v_env;
END
$$;

-- ---------------------------------------------------------------------------
-- Admin test account: link profile and force role 'admin' (idempotent).
-- ---------------------------------------------------------------------------
INSERT INTO public.profiles (id, email, role)
SELECT id, email, 'admin'::public.user_role
FROM auth.users
WHERE email = 'admin@test.local'
ON CONFLICT (id) DO UPDATE
SET email      = EXCLUDED.email,
    role       = 'admin'::public.user_role,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- Regular user test account: link profile and force role 'user' (idempotent).
-- ---------------------------------------------------------------------------
INSERT INTO public.profiles (id, email, role)
SELECT id, email, 'user'::public.user_role
FROM auth.users
WHERE email = 'user@test.local'
ON CONFLICT (id) DO UPDATE
SET email      = EXCLUDED.email,
    role       = 'user'::public.user_role,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- Post-condition check: both test profiles must exist, otherwise the auth
-- users were not created first (see seed_test_accounts.md step 1).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_missing TEXT[];
BEGIN
  SELECT array_agg(e)
    INTO v_missing
    FROM (VALUES ('admin@test.local'), ('user@test.local')) AS t(e)
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.email = t.e);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'Seed incomplete: no auth.users row found for %. Create the auth users first via the Auth Admin API (see seed_test_accounts.md).',
      array_to_string(v_missing, ', ');
  END IF;

  RAISE NOTICE 'Seed OK: test profiles present for admin@test.local and user@test.local';
END
$$;

-- Verification output (emails and roles only - never secrets).
SELECT email, role, created_at
FROM public.profiles
WHERE email IN ('admin@test.local', 'user@test.local')
ORDER BY email;
