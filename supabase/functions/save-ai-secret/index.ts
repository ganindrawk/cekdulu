/**
 * CekDulu Edge Function: save-ai-secret
 * -------------------------------------
 * POST only, admin-only.
 *
 * Stores the AI provider API key for image recognition. The `api_key` field
 * is WRITE-ONLY: it is AES-GCM encrypted (key from AFFILIATE_ENCRYPTION_KEY)
 * and stored under the `api_key` key of ai_credentials.credentials, which the
 * public.ai_credentials_safe view strips on read. The function returns
 * { ok: true } and never returns or logs the key.
 *
 * Body: {
 *   provider: "gemini" | "openai" | "groq" | "openrouter" | "custom",
 *   api_key: string,             // required, write-only
 *   model?: string,              // stored plaintext; default per provider
 *   base_url?: string            // OpenAI-compatible endpoint; preset per
 *                                // provider when omitted, required for "custom"
 * }
 *
 * The saved provider becomes the active one (ai_credentials.is_active):
 * identify-product-image always calls the active provider. Other rows keep
 * their stored keys but are inactive until re-saved.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encryptSecret } from "../_shared/crypto.ts";
import { json, requireAdmin, serviceClient } from "../_shared/supa.ts";

const ALLOWED_PROVIDERS = ["gemini", "openai", "groq", "openrouter", "custom"];

// Preset base URL untuk provider OpenAI-compatible (bisa ditimpa client).
const PRESET_BASE_URL: Record<string, string> = {
  openai: "https://api.openai.com/v1",
  groq: "https://api.groq.com/openai/v1",
  openrouter: "https://openrouter.ai/api/v1",
};

serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      return json({ ok: false, error: "method_not_allowed" }, 405);
    }

    await requireAdmin(req);

    let body: Record<string, unknown>;
    try {
      // Coba parse sebagai JSON; fallback ke text lalu parse manual
      // untuk menangani variasi Content-Type dari client.
      try {
        body = await req.json();
      } catch {
        const text = await req.text();
        body = JSON.parse(text) as Record<string, unknown>;
      }
    } catch {
      return json({ ok: false, error: "invalid_json" }, 400);
    }

    const provider = String(body["provider"] ?? "");
    if (!ALLOWED_PROVIDERS.includes(provider)) {
      return json(
        { ok: false, error: "invalid_provider", got: provider },
        400,
      );
    }

    const apiKey = String(body["api_key"] ?? "").trim();
    if (!apiKey) {
      return json({ ok: false, error: "api_key_required" }, 400);
    }

    // Model: default per provider; wajib diisi untuk groq/openrouter/custom
    // karena nama modelnya tidak bisa ditebak server.
    let model = String(body["model"] ?? "").trim();
    if (!model) {
      if (provider === "gemini") model = "gemini-3.5-flash";
      else if (provider === "openai") model = "gpt-5-mini";
      else return json({ ok: false, error: "model_required" }, 400);
    }

    // Base URL: Gemini tidak pakai; provider lain pakai preset bila kosong,
    // custom wajib mengisinya sendiri.
    let baseUrl = String(body["base_url"] ?? "").trim().replace(/\/+$/, "");
    if (provider === "gemini") {
      baseUrl = "";
    } else if (!baseUrl) {
      const preset = PRESET_BASE_URL[provider];
      if (!preset) {
        return json({ ok: false, error: "base_url_required" }, 400);
      }
      baseUrl = preset;
    }

    let encrypted: { iv: string; data: string };
    try {
      encrypted = await encryptSecret(apiKey);
    } catch (e) {
      console.error("save-ai-secret encrypt failed:", e);
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes("misconfigured") || msg.includes("ENCRYPTION_KEY")) {
        return json({ ok: false, error: "missing_encryption_key" }, 500);
      }
      return json({ ok: false, error: "encryption_failed" }, 500);
    }

    const svc = serviceClient();
    const { error } = await svc.from("ai_credentials").upsert(
      {
        provider,
        credentials: { api_key: encrypted }, // write-only; stripped by safe view
        model,
        base_url: baseUrl,
        is_active: true,
      },
      { onConflict: "provider" },
    );
    if (error) {
      console.error("save-ai-secret upsert failed:", error.message);
      return json(
        { ok: false, error: "db_error", detail: error.message },
        500,
      );
    }

    // Provider lain menjadi non-aktif (hanya satu provider aktif).
    const { error: deactivateErr } = await svc
      .from("ai_credentials")
      .update({ is_active: false })
      .neq("provider", provider);
    if (deactivateErr) {
      console.error("save-ai-secret deactivate failed:", deactivateErr.message);
      return json(
        { ok: false, error: "db_error", detail: deactivateErr.message },
        500,
      );
    }

    return json({ ok: true });
  } catch (e) {
    if (e instanceof Response) return e;
    // Never leak details or credentials in error responses.
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
