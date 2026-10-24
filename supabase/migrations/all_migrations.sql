-- CekDulu all-in-one migration (001 + 002 + 003). Jalankan sekali di Supabase SQL Editor.
-- Dibuat otomatis 2026-10-14. File individual tetap ada untuk versioning.


-- ============================================================
-- 001_initial_schema.sql
-- ============================================================
-- =============================================================================
-- CekDulu Migration 001: Initial schema
-- -----------------------------------------------------------------------------
-- Idempotent: safe to run multiple times (uses IF NOT EXISTS / OR REPLACE /
-- DROP ... IF EXISTS patterns throughout).
--
-- Tables:
--   public.profiles               - app user profile, 1:1 with auth.users
--   public.products               - product catalog (Shopee / Tokopedia)
--   public.affiliate_links        - affiliate URLs per product & marketplace
--   public.affiliate_credentials  - encrypted marketplace API credentials
--   public.scan_history           - per-user product scan log
-- =============================================================================

-- Required extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enum: user_role ('admin' | 'user')
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM ('admin', 'user');
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Table: profiles
-- One row per Supabase Auth user. Role defaults to 'user'; only admins may
-- promote a user (enforced in 002 via trigger).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT        NOT NULL,
  role        user_role   NOT NULL DEFAULT 'user',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.profiles IS 'App-level user profile linked 1:1 to auth.users. Never stores passwords.';
COMMENT ON COLUMN public.profiles.role IS 'RBAC role. Changeable by admins only (see prevent_role_escalation trigger in 002).';

-- ---------------------------------------------------------------------------
-- Table: products
-- Catalog of products matched from barcode/QR scans.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT        NOT NULL,
  description       TEXT,
  image_url         TEXT,
  marketplace       TEXT        NOT NULL CHECK (marketplace IN ('shopee', 'tokopedia')),
  marketplace_url   TEXT,
  price             NUMERIC(12, 2) CHECK (price IS NULL OR price >= 0),
  rating            NUMERIC(3, 2)  CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5)),
  review_count      INTEGER     NOT NULL DEFAULT 0 CHECK (review_count >= 0),
  data_refreshed_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.products IS 'Product catalog. Shown ordered by rating/review_count ("best reviews first").';
COMMENT ON COLUMN public.products.data_refreshed_at IS 'Last time price/stock/rating were refreshed from the marketplace.';

-- One canonical catalog row per marketplace listing URL (NULL URLs excluded).
CREATE UNIQUE INDEX IF NOT EXISTS uq_products_marketplace_url
  ON public.products (marketplace, marketplace_url)
  WHERE marketplace_url IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_products_marketplace
  ON public.products (marketplace);
CREATE INDEX IF NOT EXISTS idx_products_marketplace_url
  ON public.products (marketplace_url);
-- Supports "best reviews first" ordering: rating DESC, review_count DESC.
CREATE INDEX IF NOT EXISTS idx_products_best_reviews
  ON public.products (rating DESC NULLS LAST, review_count DESC);

-- ---------------------------------------------------------------------------
-- Table: affiliate_links
-- Affiliate (tracking) URL per product & marketplace.
--   Shopee   -> generated automatically via Shopee Affiliate API (Edge Function)
--   Tokopedia -> pasted manually by admin (no public affiliate API)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.affiliate_links (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    UUID        NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  marketplace   TEXT        NOT NULL CHECK (marketplace IN ('shopee', 'tokopedia')),
  original_url  TEXT        NOT NULL,
  affiliate_url TEXT        NOT NULL,
  status        TEXT        NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'inactive', 'expired')),
  created_by    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.affiliate_links IS 'Affiliate tracking links. Shopee links are auto-generated; Tokopedia links are pasted manually by admins.';

CREATE INDEX IF NOT EXISTS idx_affiliate_links_product
  ON public.affiliate_links (product_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_links_marketplace
  ON public.affiliate_links (marketplace);
CREATE INDEX IF NOT EXISTS idx_affiliate_links_status
  ON public.affiliate_links (status);

-- ---------------------------------------------------------------------------
-- Table: affiliate_credentials
-- Marketplace API credentials owned by the app owner (one row per marketplace).
--
-- SECURITY MODEL (important):
--   * The JSONB payload may look like:
--       {"app_id": "...", "secret": "<WRITE-ONLY>", "affiliate_id": "...",
--        "default_sub_id": "..."}
--   * Encryption is applied at the application layer: values are stored via
--     Edge Functions using secrets from the Edge Function secrets store
--     (never hardcode them in SQL, and never commit them to git).
--   * The "secret" key is WRITE-ONLY: it is written once and never read back
--     through the API. Admin reads go through the
--     public.affiliate_credentials_safe view (see 002), which strips the
--     secret key. Server-side Edge Functions use the service_role key
--     (bypasses RLS) to access the raw row when calling marketplace APIs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.affiliate_credentials (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  marketplace TEXT        NOT NULL UNIQUE CHECK (marketplace IN ('shopee', 'tokopedia')),
  credentials JSONB       NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.affiliate_credentials IS 'Marketplace API credentials. Secrets are write-only; admin UI must read via affiliate_credentials_safe view.';
COMMENT ON COLUMN public.affiliate_credentials.credentials IS 'JSONB credential payload. Encrypt at application layer / Edge Function secrets. Never log or return the "secret" key.';

-- ---------------------------------------------------------------------------
-- Table: scan_history
-- Log of product scans per user. product_id is NULL when the scanned code
-- did not match any catalog product.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.scan_history (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id   UUID        REFERENCES public.products(id) ON DELETE SET NULL,
  scanned_code TEXT        NOT NULL,
  scanned_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.scan_history IS 'Per-user scan log. product_id NULL = no catalog match.';

CREATE INDEX IF NOT EXISTS idx_scan_history_user
  ON public.scan_history (user_id);
CREATE INDEX IF NOT EXISTS idx_scan_history_scanned_at
  ON public.scan_history (scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_scan_history_product
  ON public.scan_history (product_id);

-- ---------------------------------------------------------------------------
-- Trigger helper: keep updated_at fresh
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['profiles', 'products', 'affiliate_links', 'affiliate_credentials']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%I_updated_at ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at()',
      t, t
    );
  END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- Trigger: auto-create a profile row when a new auth user signs up.
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 002_rls_policies.sql
-- ============================================================
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

-- ============================================================
-- 003_profile_trigger.sql
-- ============================================================
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
