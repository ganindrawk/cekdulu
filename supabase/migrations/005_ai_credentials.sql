-- =============================================================================
-- Migration 005: AI provider credentials for image recognition
-- =============================================================================
-- Table: public.ai_credentials
-- API credentials for AI image-recognition providers (one row per provider).
--
-- SECURITY MODEL (same as affiliate_credentials):
--   * credentials JSONB payload: {"api_key": "<WRITE-ONLY, AES-GCM encrypted>"}
--   * model TEXT: model ID (e.g. "gemini-3.5-flash") — NOT secret, stored plaintext.
--   * Encryption applied at application layer via Edge Functions using
--     AFFILIATE_ENCRYPTION_KEY (never hardcode, never commit to git).
--   * The "api_key" is WRITE-ONLY: written once via save-ai-secret, never read
--     back through the API. Admin reads go through
--     public.ai_credentials_safe view (below), which strips the api_key.
--     Server-side Edge Functions use the service_role key (bypasses RLS) to
--     access the raw row when calling the AI provider API.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_credentials (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider    TEXT        NOT NULL UNIQUE CHECK (provider IN ('gemini')),
  credentials JSONB       NOT NULL DEFAULT '{}'::jsonb,
  model       TEXT        NOT NULL DEFAULT 'gemini-3.5-flash',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.ai_credentials IS 'AI provider API credentials for image recognition. api_key is write-only; admin UI must read via ai_credentials_safe view.';
COMMENT ON COLUMN public.ai_credentials.credentials IS 'JSONB payload {"api_key": "<encrypted>"}. Never log or return the api_key.';
COMMENT ON COLUMN public.ai_credentials.model IS 'AI model ID, e.g. gemini-3.5-flash. Not secret; admin-configurable.';

ALTER TABLE public.ai_credentials ENABLE ROW LEVEL SECURITY;

-- Admin-only read/write. No policy for non-admins (deny by default).
DROP POLICY IF EXISTS "ai_credentials_admin_all" ON public.ai_credentials;
CREATE POLICY "ai_credentials_admin_all"
  ON public.ai_credentials FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Safe view for admin reads: strips the api_key, keeps provider + model.
DROP VIEW IF EXISTS public.ai_credentials_safe;
CREATE VIEW public.ai_credentials_safe
WITH (security_invoker = true) AS
SELECT
  id,
  provider,
  model,
  (credentials - 'api_key') AS credentials,
  created_at,
  updated_at
FROM public.ai_credentials;

COMMENT ON VIEW public.ai_credentials_safe IS 'Admin-safe view of ai_credentials with the api_key stripped.';
