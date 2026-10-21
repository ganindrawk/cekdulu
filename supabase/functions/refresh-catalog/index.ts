/**
 * CekDulu Edge Function: refresh-catalog
 * -------------------------------------
 * Periodically refreshes catalog data (price, rating, review_count).
 *
 * Auth: EITHER an admin JWT (Authorization: Bearer <jwt>) OR the shared
 * CRON_SECRET (header x-cron-secret). The cron path lets schedulers call
 * this without a user session.
 *
 * Behavior:
 *   - Shopee products: best-effort refresh via the Shopee Open Platform API.
 *     The exact item-info endpoint is a TODO (validate at open.shopee.com);
 *     per-product failures are collected, never fatal to the whole run.
 *   - Tokopedia products: no public affiliate/product API exists, so products
 *     whose data_refreshed_at is older than REFRESH_STALE_DAYS (default 7)
 *     are reported in `tokopedia_needs_manual_update` for an admin to fix
 *     manually in the dashboard.
 *
 * Scheduling options (see supabase/README.md):
 *   a) Supabase pg_cron + pg_net calling the function URL with x-cron-secret
 *      stored in the Supabase vault.
 *   b) External scheduler (GitHub Actions / VPS cron) curling the URL.
 *
 * No credentials are hardcoded; everything comes from function secrets.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { decryptSecret } from "../_shared/crypto.ts";
import { json, requireAdmin, serviceClient } from "../_shared/supa.ts";

// TODO: validate the item-info endpoint at https://open.shopee.com before
// production use. Research note (2026-10-14): community-documented v2 API
// (multiple SDKs, e.g. develaparx/marketplace-skills, quovadis86/shopee-sdk)
// gives it as:
//   GET https://partner.shopeemobile.com/api/v2/product/get_item_base_info
//   ?partner_id=..&timestamp=..&access_token=..&sign=<hmac-sha256>...
// (note: get_item_BASE_info, not get_item_info). Public docs vary and the
// exact query params/response fields must be confirmed in the official
// console; only this path + mapShopeeItem() need changing once confirmed.
const SHOPEE_API_BASE =
  Deno.env.get("SHOPEE_API_BASE") ?? "https://open-api.shopee.com";
const SHOPEE_ITEM_INFO_PATH = "/api/v2/product/get_item_info"; // TODO validate

const STALE_DAYS = Number(Deno.env.get("REFRESH_STALE_DAYS") ?? "7");
const BATCH_LIMIT = Number(Deno.env.get("REFRESH_BATCH_LIMIT") ?? "200");

interface ShopeeItem {
  price?: number;
  rating?: number;
  reviewCount?: number;
}

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

/**
 * Best-effort refresh of one Shopee product. Throws on any failure; the
 * caller records it per product and continues with the rest.
 */
async function refreshShopeeProduct(
  product: { id: string; marketplace_url: string | null },
  creds: { partnerId: string; partnerKey: string },
): Promise<ShopeeItem> {
  if (!product.marketplace_url) throw new Error("missing marketplace_url");
  const timestamp = Math.floor(Date.now() / 1000);
  const baseString =
    `${creds.partnerId}${SHOPEE_ITEM_INFO_PATH}${timestamp}`;
  const sign = await hmacSha256Hex(creds.partnerKey, baseString);
  const url =
    `${SHOPEE_API_BASE}${SHOPEE_ITEM_INFO_PATH}` +
    `?partner_id=${encodeURIComponent(creds.partnerId)}` +
    `&timestamp=${timestamp}&sign=${sign}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ target_url: product.marketplace_url }),
  });
  if (!res.ok) throw new Error(`Shopee API HTTP ${res.status}`);
  const data: Record<string, unknown> = await res.json();
  // TODO: map the real response fields once the endpoint is validated.
  const item = (data["item"] ?? data["data"] ?? {}) as Record<string, unknown>;
  const price = Number(item["price"] ?? item["current_price"] ?? NaN);
  const rating = Number(item["rating"] ?? item["item_rating"] ?? NaN);
  const reviewCount = Number(
    item["review_count"] ?? item["comment_count"] ?? NaN,
  );
  if (Number.isNaN(price) && Number.isNaN(rating)) {
    throw new Error("unrecognized Shopee item response");
  }
  return {
    ...(Number.isNaN(price) ? {} : { price }),
    ...(Number.isNaN(rating) ? {} : { rating }),
    ...(Number.isNaN(reviewCount) ? {} : { reviewCount }),
  };
}

function authorized(req: Request): boolean {
  const cronSecret = Deno.env.get("CRON_SECRET");
  return !!cronSecret &&
    req.headers.get("x-cron-secret") === cronSecret;
}

serve(async (req: Request): Promise<Response> => {
  try {
    const svc = serviceClient();
    if (!authorized(req)) {
      await requireAdmin(req); // throws 401/403 Response otherwise
    }

    // ---- Shopee: best-effort refresh -------------------------------------
    const { data: credRow } = await svc
      .from("affiliate_credentials")
      .select("credentials")
      .eq("marketplace", "shopee")
      .maybeSingle();
    const creds = (credRow?.credentials as Record<string, unknown> | null) ??
      {};
    const appId = typeof creds["app_id"] === "string" ? creds["app_id"] : "";
    const secretEnc =
      typeof creds["secret"] === "string" ? creds["secret"] : "";
    const hasShopeeCreds = !!(appId && secretEnc);

    let attempted = 0;
    let updated = 0;
    const failed: Array<{ id: string; reason: string }> = [];

    if (hasShopeeCreds) {
      const partnerKey = await decryptSecret(secretEnc);
      const { data: products } = await svc
        .from("products")
        .select("id, marketplace_url")
        .eq("marketplace", "shopee")
        .limit(BATCH_LIMIT);

      for (const p of (products ?? []) as Array<{
        id: string;
        marketplace_url: string | null;
      }>) {
        attempted++;
        try {
          const item = await refreshShopeeProduct(p, {
            partnerId: appId,
            partnerKey,
          });
          const patch: Record<string, unknown> = {
            data_refreshed_at: new Date().toISOString(),
          };
          if (item.price !== undefined) patch["price"] = item.price;
          if (item.rating !== undefined) patch["rating"] = item.rating;
          if (item.reviewCount !== undefined) {
            patch["review_count"] = item.reviewCount;
          }
          const { error } = await svc
            .from("products")
            .update(patch)
            .eq("id", p.id);
          if (error) throw error;
          updated++;
        } catch (e) {
          failed.push({
            id: p.id,
            reason: e instanceof Error ? e.message : "unknown",
          });
        }
      }
    }

    // ---- Tokopedia: report stale products for manual update --------------
    const staleCutoff = new Date(
      Date.now() - STALE_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();
    const { data: staleTokopedia } = await svc
      .from("products")
      .select("id, name, marketplace_url, data_refreshed_at")
      .eq("marketplace", "tokopedia")
      .or(`data_refreshed_at.is.null,data_refreshed_at.lt.${staleCutoff}`)
      .limit(BATCH_LIMIT);

    return json({
      ok: true,
      shopee: {
        attempted,
        updated,
        failed,
        skipped_no_credentials: !hasShopeeCreds,
      },
      tokopedia_needs_manual_update: (staleTokopedia ?? []).map((p) => ({
        id: p["id"],
        name: p["name"],
        marketplace_url: p["marketplace_url"],
        data_refreshed_at: p["data_refreshed_at"],
      })),
    });
  } catch (e) {
    if (e instanceof Response) return e;
    return json({ ok: false, error: "internal_error" }, 500);
  }
});
