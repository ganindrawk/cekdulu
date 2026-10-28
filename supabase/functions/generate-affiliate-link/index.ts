/**
 * CekDulu Edge Function: generate-affiliate-link
 * --------------------------------------------
 * POST only, ADMIN-ONLY (deliberate choice: generating affiliate links spends
 * the owner's affiliate attribution and calls a paid/rate-limited partner API,
 * so regular users must not invoke it directly).
 *
 * Flow:
 *   1. Resolve target Shopee URL from { product_id } (via products table)
 *      or { shopee_url } directly.
 *   2. Load the owner's Shopee credentials from affiliate_credentials
 *      (service_role, bypasses RLS), decrypt the write-only secret server-side.
 *   3. Call the Shopee Open Platform API to generate the affiliate short link.
 *   4. Deactivate previous active links for the product, insert the new one.
 *   5. Return { ok: true, affiliate_url }.
 *
 * Body: { product_id?: string, shopee_url?: string }
 *   - product_id alone      -> uses products.marketplace_url (must be Shopee)
 *   - shopee_url alone      -> generates a link without persisting a product
 *   - both                  -> persists against product_id
 *
 * ---------------------------------------------------------------------------
 * TODO (must be validated before production use):
 *   Public documentation for the Shopee affiliate link-generation endpoint
 *   varies. Confirm the exact API path, request fields, signing scheme and
 *   response fields in the Open Platform console at https://open.shopee.com,
 *   then adjust ONLY SHOPEE_GENERATE_LINK_PATH and parseGenerateLinkResponse()
 *   below. The HMAC-SHA256 request signing implemented here follows the
 *   documented Open Platform v2 scheme:
 *     sign = hex(HMAC_SHA256(partner_key, partner_id + api_path + timestamp))
 * ---------------------------------------------------------------------------
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { decryptSecret } from "../_shared/crypto.ts";
import { json, requireAdmin, serviceClient } from "../_shared/supa.ts";

const SHOPEE_API_BASE =
  Deno.env.get("SHOPEE_API_BASE") ?? "https://open-api.shopee.com";
// TODO: validate at https://open.shopee.com before production use.
// Research note (2026-10-14): an unofficial archived SDK
// (github.com/snja/shopee-affiliate-openapi, 2022, archived 2024-10)
// shows the real affiliate link endpoint is NOT REST on open-api.shopee.com.
// It was a GraphQL mutation on the region-specific host:
//   POST https://open-api.affiliate.shopee.co.id/graphql
//   mutation { generateShortLink(input: {originUrl: "<url>", subIds: [...]}) { shortLink } }
// with auth header "SHA256 Credential=<appid>, Signature=<sig>, Timestamp=<ts>"
// where sig = sha256(appid + timestamp + json(payload) + secret).
// The API may have changed since 2022; confirm the current mutation name,
// input fields and signing scheme in the official console, then rewrite
// generateShopeeAffiliateLink() to match (GraphQL + SHA256 header, no HMAC).
const SHOPEE_GENERATE_LINK_PATH = "/api/v2/affiliate/link_generate";

async function hmacSha256Hex(key: string, message: string): Promise<string> {
  const te = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    te.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, te.encode(message));
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface ShopeeCreds {
  partnerId: string;
  partnerKey: string; // decrypted write-only secret
  subId?: string;
}

/**
 * Call Shopee Open Platform to generate an affiliate short link.
 * Isolated so only the path + response parsing need changing after the
 * endpoint is validated (see TODO at the top of this file).
 */
async function generateShopeeAffiliateLink(
  creds: ShopeeCreds,
  targetUrl: string,
): Promise<string> {
  const timestamp = Math.floor(Date.now() / 1000);
  const baseString = `${creds.partnerId}${SHOPEE_GENERATE_LINK_PATH}${timestamp}`;
  const sign = await hmacSha256Hex(creds.partnerKey, baseString);

  const url =
    `${SHOPEE_API_BASE}${SHOPEE_GENERATE_LINK_PATH}` +
    `?partner_id=${encodeURIComponent(creds.partnerId)}` +
    `&timestamp=${timestamp}&sign=${sign}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target_url: targetUrl,
      ...(creds.subId ? { sub_id: creds.subId } : {}),
    }),
  });
  if (!res.ok) {
    throw new Error(`Shopee API HTTP ${res.status}`);
  }
  const data: Record<string, unknown> = await res.json();
  // Defensive parsing: field names differ across doc versions.
  const nested = (data["data"] as Record<string, unknown> | undefined) ?? {};
  const link =
    data["short_link"] ??
    data["shortLink"] ??
    data["affiliate_link"] ??
    nested["short_link"] ??
    nested["shortLink"];
  if (typeof link !== "string" || !link) {
    throw new Error(
      "Unrecognized Shopee response; validate the endpoint at open.shopee.com",
    );
  }
  return link;
}

serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      return json({ ok: false, error: "method_not_allowed" }, 405);
    }

    const adminId = await requireAdmin(req);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ ok: false, error: "invalid_json" }, 400);
    }

    const productId =
      typeof body["product_id"] === "string" ? body["product_id"] : null;
    let targetUrl =
      typeof body["shopee_url"] === "string" ? body["shopee_url"].trim() : "";

    const svc = serviceClient();

    if (productId) {
      const { data: product, error: pErr } = await svc
        .from("products")
        .select("id, marketplace, marketplace_url")
        .eq("id", productId)
        .maybeSingle();
      if (pErr) throw pErr;
      if (!product) return json({ ok: false, error: "product_not_found" }, 404);
      if (product["marketplace"] !== "shopee" || !product["marketplace_url"]) {
        return json({ ok: false, error: "product_not_shopee" }, 400);
      }
      targetUrl = String(product["marketplace_url"]);
    }

    if (!targetUrl || !/^https?:\/\//i.test(targetUrl)) {
      return json({ ok: false, error: "shopee_url_required" }, 400);
    }

    const { data: credRow, error: cErr } = await svc
      .from("affiliate_credentials")
      .select("credentials")
      .eq("marketplace", "shopee")
      .maybeSingle();
    if (cErr) throw cErr;
    const creds = (credRow?.credentials as Record<string, unknown> | null) ??
      {};
    const appId = typeof creds["app_id"] === "string" ? creds["app_id"] : "";
    const secretEnc =
      typeof creds["secret"] === "string" ? creds["secret"] : "";
    if (!appId || !secretEnc) {
      return json({ ok: false, error: "shopee_credentials_missing" }, 400);
    }
    const partnerKey = await decryptSecret(secretEnc);
    const subId =
      typeof creds["default_sub_id"] === "string"
        ? creds["default_sub_id"]
        : undefined;

    const affiliateUrl = await generateShopeeAffiliateLink(
      { partnerId: appId, partnerKey, subId },
      targetUrl,
    );

    if (productId) {
      // Retire previous active links for this product, then insert the new one.
      await svc
        .from("affiliate_links")
        .update({ status: "inactive" })
        .eq("product_id", productId)
        .eq("marketplace", "shopee")
        .eq("status", "active");
      const { error: iErr } = await svc.from("affiliate_links").insert({
        product_id: productId,
        marketplace: "shopee",
        original_url: targetUrl,
        affiliate_url: affiliateUrl,
        status: "active",
        created_by: adminId,
      });
      if (iErr) throw iErr;
    }

    return json({ ok: true, affiliate_url: affiliateUrl });
  } catch (e) {
    if (e instanceof Response) return e;
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
