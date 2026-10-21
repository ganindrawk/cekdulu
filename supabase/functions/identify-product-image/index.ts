/**
 * CekDulu Edge Function: identify-product-image
 * ---------------------------------------------
 * POST only, any authenticated user.
 *
 * Identifies a consumer product from a photo using the configured AI
 * provider (Gemini). The API key never leaves the server: it is read
 * (decrypted) server-side via the service_role key.
 *
 * Body: {
 *   image_base64: string,   // JPEG/PNG bytes as base64 (app should resize ≤1024px first)
 *   mime_type?: string      // default "image/jpeg"
 * }
 *
 * Returns: {
 *   ok: true,
 *   brand: string | null,
 *   product_name: string | null,
 *   variant: string | null
 * }
 * On failure: { ok: false, error: "<code>" } — never leaks the API key.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { decryptSecret } from "../_shared/crypto.ts";
import { json, serviceClient } from "../_shared/supa.ts";

const PROMPT = `Identify the consumer packaged product shown in this photo.
This is for matching the photo against a small product catalog.
Return ONLY a JSON object (no markdown fences, no explanation) with keys:
- "brand": brand name as printed on the packaging (e.g. "Better", "Nabati"), or null if not visible
- "product_name": full product name as printed (e.g. "Better Sandwich Biscuit", "Nabati Wafer"), or null
- "variant": flavor/variant/pack size if visible (e.g. "Vanilla Cream", "isi 10", "110g"), or null
If no recognizable consumer product is visible, return {"brand": null, "product_name": null, "variant": null}.`;

async function requireAuth(req: Request): Promise<void> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (!jwt) {
    throw new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const svc = serviceClient();
  const { data, error } = await svc.auth.getUser(jwt);
  if (error || !data.user) {
    throw new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
}

serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      return json({ ok: false, error: "method_not_allowed" }, 405);
    }

    await requireAuth(req);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ ok: false, error: "invalid_json" }, 400);
    }

    const imageB64 = String(body["image_base64"] ?? "");
    if (!imageB64 || imageB64.length < 100) {
      return json({ ok: false, error: "image_required" }, 400);
    }
    if (imageB64.length > 4_000_000) {
      return json({ ok: false, error: "image_too_large" }, 413);
    }
    const mimeType = String(body["mime_type"] ?? "image/jpeg");

    // Load AI credentials server-side (service_role bypasses RLS).
    const svc = serviceClient();
    const { data: credRow, error: credErr } = await svc
      .from("ai_credentials")
      .select("credentials, model")
      .eq("provider", "gemini")
      .maybeSingle();
    if (credErr || !credRow) {
      return json({ ok: false, error: "ai_not_configured" }, 503);
    }
    const encryptedKey = (credRow.credentials as Record<string, unknown>)
      ?.["api_key"];
    if (typeof encryptedKey !== "string" || !encryptedKey) {
      return json({ ok: false, error: "ai_not_configured" }, 503);
    }
    const model = String(
      (credRow as Record<string, unknown>)["model"] || "gemini-3.5-flash",
    );
    let apiKey: string;
    try {
      apiKey = await decryptSecret(encryptedKey);
    } catch {
      return json({ ok: false, error: "ai_key_error" }, 500);
    }

    // Call Gemini (dengan fallback ke model lain jika 503).
    const modelsToTry = [...new Set([
      model,
      'gemini-3.5-flash-lite',
      'gemini-3.8-flash',
    ])]; // hapus duplikat, jaga urutan

    let geminiRes: Response | null = null;
    let lastStatus: number | null = null;
    for (const m of modelsToTry) {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(m)}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify({
            contents: [
              {
                parts: [
                  { text: PROMPT },
                  { inline_data: { mime_type: mimeType, data: imageB64 } },
                ],
              },
            ],
            generationConfig: {
              response_mime_type: "application/json",
              maxOutputTokens: 256,
              temperature: 0.1,
            },
          }),
        },
      );
      if (res.ok) {
        geminiRes = res;
        break;
      }
      lastStatus = res.status;
      // Hanya fallback untuk 503 (service unavailable); error lain langsung gagal.
      if (res.status != 503) break;
      console.error(`Gemini 503 on model ${m}, trying fallback...`);
    }

    const geminiResFinal = geminiRes;
    if (geminiResFinal == null || !geminiResFinal.ok) {
      // Do not forward provider error details (may leak key info); log server-side only.
      // Return the status code to help diagnose (400=bad request, 401/403=invalid key, 404=bad model, 429=quota).
      console.error("Gemini API error:", lastStatus);
      return json(
        { ok: false, error: "ai_provider_error", provider_status: lastStatus },
        502,
      );
    }

    const geminiJson = await geminiResFinal.json();
    const text: string =
      geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    let parsed: Record<string, unknown> = {};
    try {
      // Strip accidental fences just in case.
      parsed = JSON.parse(text.replace(/```json|```/g, "").trim());
    } catch {
      return json({ ok: false, error: "ai_parse_error" }, 502);
    }

    const str = (v: unknown): string | null =>
      typeof v === "string" && v.trim() ? v.trim() : null;

    return json({
      ok: true,
      brand: str(parsed["brand"]),
      product_name: str(parsed["product_name"]),
      variant: str(parsed["variant"]),
    });
  } catch (e) {
    if (e instanceof Response) return e;
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
