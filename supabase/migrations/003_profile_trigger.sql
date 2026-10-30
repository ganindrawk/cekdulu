-- =============================================================================
-- CekDulu Migration 003: profile auto-creation trigger (re-assertion)
-- -----------------------------------------------------------------------------
-- Idempotent: CREATE OR REPLACE + DROP TRIGGER IF EXISTS throughout.
-- Run AFTER 001_initial_schema.sql (and 002_rls_policies.sql).
--
-- NOTE: the canonical definition of public.handle_new_user() and the
-- on_auth_user_created trigger already lives in 001_initial_schema.sql.
-- This migration re-asserts them so the signup -> profiles flow is
-- explicitly versioned and survives partial/failed earlier runs.
--
-- Dashboard alternative: Supabase Dashboard -> Database -> Webhooks can create
-- the same AFTER INSERT ON auth.users trigger without SQL, but keeping it in
-- migrations is preferred (versioned, reproducible across environments).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Function: create a profiles row for every new auth user.
-- Role always starts as 'user'; promotion is admin-only (see 002).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, role)
  VALUES (NEW.id, NEW.email, 'user')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Creates a public.profiles row (role=user) for each new auth.users row. Re-asserted in 003.';

-- ---------------------------------------------------------------------------
-- Trigger: AFTER INSERT ON auth.users
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
