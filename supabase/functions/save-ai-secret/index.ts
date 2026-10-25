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
 *   provider: "gemini",          // required
 *   api_key: string,             // required, write-only
 *   model?: string               // e.g. "gemini-3.5-flash" (stored plaintext)
 * }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encryptSecret } from "../_shared/crypto.ts";
import { json, requireAdmin, serviceClient } from "../_shared/supa.ts";

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
    if (provider !== "gemini") {
      return json(
        { ok: false, error: "invalid_provider", got: provider },
        400,
      );
    }

    const apiKey = String(body["api_key"] ?? "").trim();
    if (!apiKey) {
      return json({ ok: false, error: "api_key_required" }, 400);
    }

    const model = String(body["model"] ?? "gemini-3.5-flash").trim() ||
      "gemini-3.5-flash";

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

    return json({ ok: true });
  } catch (e) {
    if (e instanceof Response) return e;
    // Never leak details or credentials in error responses.
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
