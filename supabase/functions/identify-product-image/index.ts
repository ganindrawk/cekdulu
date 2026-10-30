/**
 * CekDulu Edge Function: identify-product-image
 * ---------------------------------------------
 * POST only, any authenticated user.
 *
 * Identifies a consumer product from a photo using the configured AI
 * providers as a fallback chain (combo): providers are tried in priority
 * order (ai_credentials.priority, 1 = primary). On 429 (quota exhausted)
 * or 503 (unavailable) the next provider is tried automatically; other
 * errors stop the chain so configuration mistakes surface immediately.
 * Gemini uses generateContent; other providers (openai/groq/openrouter/
 * custom) use the OpenAI-compatible chat completions format. The API keys
 * never leave the server: they are read (decrypted) server-side via the
 * service_role key.
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

    // Load SEMUA kredensial AI server-side (service_role bypasses RLS),
    // urut priority (1 = utama). Butuh migrasi 008. Bila migrasi belum
    // jalan, select gagal dan fungsi mengembalikan ai_not_configured
    // (aman, bukan bocor).
    const svc = serviceClient();
    const { data: credRows, error: credErr } = await svc
      .from("ai_credentials")
      .select("credentials, model, provider, base_url, priority")
      .order("priority", { ascending: true })
      .order("created_at", { ascending: true });
    if (credErr || !credRows || credRows.length === 0) {
      return json({ ok: false, error: "ai_not_configured" }, 503);
    }

    // Rantai fallback (combo): coba provider satu per satu sesuai urutan.
    // - Sukses -> langsung dipakai, berhenti.
    // - 429 (kuota habis) / 503 (layanan tidak tersedia) -> lanjut ke
    //   provider berikutnya.
    // - Error lain (401/403 key salah, 400 model salah, dsb) -> berhenti,
    //   karena itu kesalahan konfigurasi yang tidak akan membaik di
    //   provider lain; laporkan agar admin memperbaikinya.
    // - Gangguan jaringan / key rusak pada satu provider -> lewati saja
    //   (diperlakukan seperti 503) agar rantai tetap jalan.
    let resultText: string | null = null;
    let lastStatus: number | null = null;
    for (const credRow of credRows) {
      const encryptedKey = (credRow.credentials as Record<string, unknown>)
        ?.["api_key"];
      if (typeof encryptedKey !== "string" || !encryptedKey) continue;
      const provider = String(
        (credRow as Record<string, unknown>)["provider"] || "gemini",
      );
      const model = String(
        (credRow as Record<string, unknown>)["model"] || "",
      );
      if (!model) continue;
      let apiKey: string;
      try {
        apiKey = await decryptSecret(encryptedKey);
      } catch {
        console.error(`AI key decrypt failed for ${provider}, skipping...`);
        lastStatus = 503;
        continue;
      }
      let attempt: { text: string } | { status: number };
      try {
        if (provider === "gemini") {
          attempt = await identifyWithGemini(apiKey, model, imageB64, mimeType);
        } else {
          const baseUrl = String(
            (credRow as Record<string, unknown>)["base_url"] || "",
          ).replace(/\/+$/, "");
          if (!baseUrl) continue;
          attempt = await identifyWithOpenAiCompatible(
            apiKey,
            model,
            baseUrl,
            imageB64,
            mimeType,
          );
        }
      } catch {
        // Gangguan jaringan / respons tak terduga: perlakukan seperti 503.
        console.error(`AI provider ${provider} unreachable, trying next...`);
        lastStatus = 503;
        continue;
      }
      if ("text" in attempt) {
        resultText = attempt.text;
        break;
      }
      lastStatus = attempt.status;
      if (attempt.status !== 429 && attempt.status !== 503) break;
      console.error(
        `AI provider ${provider} returned ${attempt.status}, trying next...`,
      );
    }

    if (resultText === null) {
      // Semua provider gagal. Bila terakhir 429, aplikasi menampilkan
      // "Kuota AI tercapai" seperti sebelumnya (provider_status 429).
      console.error("All AI providers failed, last status:", lastStatus);
      return json(
        { ok: false, error: "ai_provider_error", provider_status: lastStatus },
        502,
      );
    }
    const text = resultText;

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

/// Panggil Gemini generateContent (dengan fallback model bila 503/429).
/// Mengembalikan { text } bila sukses, atau { status } HTTP provider bila gagal.
async function identifyWithGemini(
  apiKey: string,
  model: string,
  imageB64: string,
  mimeType: string,
): Promise<{ text: string } | { status: number }> {
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
    // Fallback untuk 503 (service unavailable) dan 429 (kuota/rate limit
    // per-model — model lain punya kuota terpisah); error lain langsung gagal.
    if (res.status != 503 && res.status != 429) break;
    console.error(`Gemini ${res.status} on model ${m}, trying fallback...`);
  }

  const geminiResFinal = geminiRes;
  if (geminiResFinal == null || !geminiResFinal.ok) {
    // Do not forward provider error details (may leak key info); log server-side only.
    // Return the status code to help diagnose (400=bad request, 401/403=invalid key, 404=bad model, 429=quota).
    console.error("Gemini API error:", lastStatus);
    return { status: lastStatus ?? 502 };
  }

  const geminiJson = await geminiResFinal.json();
  return { text: geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text ?? "" };
}

/// Panggil endpoint OpenAI-compatible (OpenAI / Groq / OpenRouter / custom):
/// POST {base_url}/chat/completions dengan image_url detail high (teks kecil
/// pada kemasan harus terbaca). Mengembalikan { text } atau { status }.
async function identifyWithOpenAiCompatible(
  apiKey: string,
  model: string,
  baseUrl: string,
  imageB64: string,
  mimeType: string,
): Promise<{ text: string } | { status: number }> {
  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: PROMPT },
            {
              type: "image_url",
              image_url: {
                url: `data:${mimeType};base64,${imageB64}`,
                detail: "high",
              },
            },
          ],
        },
      ],
      temperature: 0.1,
      max_completion_tokens: 256,
      response_format: { type: "json_object" },
    }),
  });
  if (!res.ok) {
    console.error("OpenAI-compatible API error:", res.status);
    return { status: res.status };
  }
  const chatJson = await res.json();
  const content = chatJson?.choices?.[0]?.message?.content;
  return { text: typeof content === "string" ? content : "" };
}
