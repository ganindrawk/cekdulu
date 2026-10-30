/**
 * CekDulu Edge Function: save-affiliate-secret
 * ------------------------------------------
 * POST only, admin-only.
 *
 * Stores marketplace API credentials. The `secret` field is WRITE-ONLY:
 * it is AES-GCM encrypted (key from AFFILIATE_ENCRYPTION_KEY) and stored
 * under the `secret` key of affiliate_credentials.credentials, which the
 * public.affiliate_credentials_safe view strips on read. The function
 * returns { ok: true } and never returns or logs the secret.
 *
 * Body: {
 *   marketplace: "shopee" | "tokopedia",
 *   secret: string,                 // required, write-only
 *   app_id?: string,
 *   affiliate_id?: string,
 *   sub_id_default?: string         // stored as default_sub_id
 * }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encryptSecret } from "../_shared/crypto.ts";
import { json, requireAdmin, serviceClient } from "../_shared/supa.ts";

const PLAIN_FIELDS = ["app_id", "affiliate_id"] as const;

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

    const marketplace = String(body["marketplace"] ?? "");
    if (marketplace !== "shopee" && marketplace !== "tokopedia") {
      return json({ ok: false, error: "invalid_marketplace" }, 400);
    }

    const secret = String(body["secret"] ?? "");
    if (!secret) {
      return json({ ok: false, error: "secret_required" }, 400);
    }

    const encrypted = await encryptSecret(secret);

    const svc = serviceClient();
    const { data: existing } = await svc
      .from("affiliate_credentials")
      .select("credentials")
      .eq("marketplace", marketplace)
      .maybeSingle();

    const credentials: Record<string, unknown> = {
      ...((existing?.credentials as Record<string, unknown> | null) ?? {}),
    };
    for (const key of PLAIN_FIELDS) {
      if (body[key] !== undefined) credentials[key] = String(body[key]);
    }
    if (body["sub_id_default"] !== undefined) {
      credentials["default_sub_id"] = String(body["sub_id_default"]);
    }
    credentials["secret"] = encrypted; // write-only; stripped by the safe view

    const { error } = await svc
      .from("affiliate_credentials")
      .upsert({ marketplace, credentials }, { onConflict: "marketplace" });
    if (error) throw error;

    return json({ ok: true });
  } catch (e) {
    if (e instanceof Response) return e;
    // Never leak details or credentials in error responses.
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
