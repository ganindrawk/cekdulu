-- =============================================================================
-- CekDulu Migration 002: Row Level Security policies
-- -----------------------------------------------------------------------------
-- Idempotent: DROP POLICY IF EXISTS before each CREATE POLICY.
-- Run AFTER 001_initial_schema.sql.
--
-- Roles:
--   * anon / authenticated -> end users of the Flutter app (via Supabase Auth)
--   * service_role         -> server-side Edge Functions (bypasses RLS)
--
-- Admin check helper: public.is_admin() reads profiles.role for auth.uid().
-- It is SECURITY DEFINER so it works inside policies regardless of the
-- caller's own row visibility.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: is the current JWT user an admin?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$$;

COMMENT ON FUNCTION public.is_admin() IS 'Returns true when the current authenticated user has the admin role. SECURITY DEFINER.';

-- ---------------------------------------------------------------------------
-- Guard: only admins may change the role column (prevents self-promotion).
-- The UPDATE policies below allow owners to edit their own profile; this
-- trigger rejects any role change attempted by a non-admin.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_role_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Direct database connections carry no JWT (auth.uid() IS NULL) and already
  -- bypass RLS as table owner; the guard only applies to API-driven (JWT)
  -- writes. This keeps ops scripts (e.g. seed.sql run via psql) working.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can change user roles';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_role_guard ON public.profiles;
CREATE TRIGGER trg_profiles_role_guard
  BEFORE UPDATE OF role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_role_escalation();

-- ---------------------------------------------------------------------------
-- Enable RLS on all app tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.affiliate_links       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.affiliate_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_history          ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- profiles
--   * Users read/update their own profile (role change blocked by trigger).
--   * Admins have full access (incl. role assignment).
-- ===========================================================================
DROP POLICY IF EXISTS "profiles_select_own_or_admin" ON public.profiles;
CREATE POLICY "profiles_select_own_or_admin"
  ON public.profiles FOR SELECT TO authenticated
  USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "profiles_update_own_or_admin" ON public.profiles;
CREATE POLICY "profiles_update_own_or_admin"
  ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id OR public.is_admin())
  WITH CHECK (auth.uid() = id OR public.is_admin());

-- No INSERT policy for end users: rows are created by the
-- handle_new_user() trigger on auth.users signup (see 001).

-- ===========================================================================
-- products (catalog)
--   * Any authenticated user can read (needed for scan results).
--   * Writes are admin-only.
-- ===========================================================================
DROP POLICY IF EXISTS "products_select_authenticated" ON public.products;
CREATE POLICY "products_select_authenticated"
  ON public.products FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "products_admin_write" ON public.products;
CREATE POLICY "products_admin_write"
  ON public.products FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ===========================================================================
-- affiliate_links
--   * Any authenticated user can read (needed to open affiliate URLs).
--   * Writes are admin-only.
-- ===========================================================================
DROP POLICY IF EXISTS "affiliate_links_select_authenticated" ON public.affiliate_links;
CREATE POLICY "affiliate_links_select_authenticated"
  ON public.affiliate_links FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "affiliate_links_admin_write" ON public.affiliate_links;
CREATE POLICY "affiliate_links_admin_write"
  ON public.affiliate_links FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ===========================================================================
-- affiliate_credentials
--   * Admin-only read/write. There is intentionally NO policy for non-admins.
--   * SECRET WRITE-ONLY RULE: the "secret" key inside the credentials JSONB
--     must never be read back through the API. Admin UI / tooling MUST read
--     via the public.affiliate_credentials_safe view below, which strips the
--     secret key. The raw table is only touched server-side by Edge Functions
--     using the service_role key (which bypasses RLS).
-- ===========================================================================
DROP POLICY IF EXISTS "affiliate_credentials_admin_all" ON public.affiliate_credentials;
CREATE POLICY "affiliate_credentials_admin_all"
  ON public.affiliate_credentials FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Safe view for admin reads: same rows, secret key removed from the payload.
-- security_invoker = true  -> the invoker's RLS policies still apply
-- (requires PostgreSQL 15+; Supabase provides it).
DROP VIEW IF EXISTS public.affiliate_credentials_safe;
CREATE VIEW public.affiliate_credentials_safe
WITH (security_invoker = true) AS
SELECT
  id,
  marketplace,
  credentials - 'secret' AS credentials,  -- secret key stripped: write-only
  created_at,
  updated_at
FROM public.affiliate_credentials;

COMMENT ON VIEW public.affiliate_credentials_safe IS 'Admin-safe read view of affiliate credentials with the write-only "secret" key removed. Use this for all UI reads.';

GRANT SELECT ON public.affiliate_credentials_safe TO authenticated;

-- ===========================================================================
-- scan_history
--   * Users have full access to their OWN rows only.
--   * Admins have full access to all rows.
-- ===========================================================================
DROP POLICY IF EXISTS "scan_history_select_own_or_admin" ON public.scan_history;
CREATE POLICY "scan_history_select_own_or_admin"
  ON public.scan_history FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "scan_history_insert_own_or_admin" ON public.scan_history;
CREATE POLICY "scan_history_insert_own_or_admin"
  ON public.scan_history FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "scan_history_update_own_or_admin" ON public.scan_history;
CREATE POLICY "scan_history_update_own_or_admin"
  ON public.scan_history FOR UPDATE TO authenticated
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "scan_history_delete_own_or_admin" ON public.scan_history;
CREATE POLICY "scan_history_delete_own_or_admin"
  ON public.scan_history FOR DELETE TO authenticated
  USING (auth.uid() = user_id OR public.is_admin());
