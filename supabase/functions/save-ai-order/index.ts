/**
 * CekDulu Edge Function: save-ai-order
 * ------------------------------------
 * POST only, admin-only.
 *
 * Stores the AI provider fallback chain order (combo) for image
 * recognition. The first provider in the order is the default: it is
 * tried first by identify-product-image, and only on 429 (quota
 * exhausted) or 503 (unavailable) does the next provider get tried.
 *
 * Body: {
 *   order: ["gemini", "openai", ...]   // desired order, first = default
 * }
 *
 * Only providers that already have a stored key are ordered; unknown
 * names are ignored. Providers not mentioned keep their relative order
 * after the listed ones. is_active is synced so the first provider is
 * the primary (kept for the settings screen display).
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { json, requireAdmin, serviceClient } from "../_shared/supa.ts";

const KNOWN = ["gemini", "openai", "groq", "openrouter", "custom"];

serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      return json({ ok: false, error: "method_not_allowed" }, 405);
    }

    await requireAdmin(req);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ ok: false, error: "invalid_json" }, 400);
    }

    const rawOrder = body["order"];
    if (!Array.isArray(rawOrder) || rawOrder.length === 0) {
      return json({ ok: false, error: "order_required" }, 400);
    }
    const wanted: string[] = [];
    for (const item of rawOrder) {
      const name = String(item ?? "");
      if (!KNOWN.includes(name)) continue;
      if (!wanted.includes(name)) wanted.push(name);
    }
    if (wanted.length === 0) {
      return json({ ok: false, error: "order_required" }, 400);
    }

    const svc = serviceClient();
    const { data: rows, error: fetchErr } = await svc
      .from("ai_credentials")
      .select("provider, priority")
      .order("priority", { ascending: true });
    if (fetchErr) {
      console.error("save-ai-order fetch failed:", fetchErr.message);
      return json({ ok: false, error: "db_error", detail: fetchErr.message }, 500);
    }
    const existing = ((rows ?? []) as Array<Record<string, unknown>>)
      .map((r) => String(r["provider"] ?? ""))
      .filter((p) => p);

    // Urutan baru: yang disebut dulu (bila sudah tersimpan), sisanya
    // mempertahankan urutan lamanya di belakang.
    const finalOrder = [
      ...wanted.filter((p) => existing.includes(p)),
      ...existing.filter((p) => !wanted.includes(p)),
    ];
    if (finalOrder.length === 0) {
      return json({ ok: false, error: "no_providers_configured" }, 400);
    }

    for (let i = 0; i < finalOrder.length; i++) {
      const { error } = await svc
        .from("ai_credentials")
        .update({ priority: i + 1 })
        .eq("provider", finalOrder[i]);
      if (error) {
        console.error("save-ai-order update failed:", error.message);
        return json({ ok: false, error: "db_error", detail: error.message }, 500);
      }
    }

    // Sinkronkan is_active: urutan pertama = utama.
    const { error: syncErr1 } = await svc
      .from("ai_credentials")
      .update({ is_active: true })
      .eq("provider", finalOrder[0]);
    const { error: syncErr2 } = await svc
      .from("ai_credentials")
      .update({ is_active: false })
      .neq("provider", finalOrder[0]);
    const syncErr = syncErr1 ?? syncErr2;
    if (syncErr) {
      console.error("save-ai-order is_active sync failed:", syncErr.message);
      return json({ ok: false, error: "db_error", detail: syncErr.message }, 500);
    }

    return json({ ok: true, order: finalOrder });
  } catch (e) {
    if (e instanceof Response) return e;
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
