/**
 * Shared Supabase helpers for CekDulu Edge Functions (Deno).
 *
 * - serviceClient(): service_role client (bypasses RLS). Used ONLY server-side.
 * - requireAdmin(req): validates the caller's JWT and requires the admin role.
 *   Throws a Response (401/403) on failure so handlers can `return` it via
 *   `if (e instanceof Response) return e`.
 * - json(): tiny JSON response helper.
 */

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.39.0";

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing env SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key, { auth: { persistSession: false } });
}

function unauthorized(message: string, status = 401): Response {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Validate the caller's JWT and require role='admin' in public.profiles.
 * Returns the caller's user id. Throws a Response on auth failure.
 */
export async function requireAdmin(req: Request): Promise<string> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (!jwt) throw unauthorized("unauthorized");
  const svc = serviceClient();
  const { data, error } = await svc.auth.getUser(jwt);
  if (error || !data.user) throw unauthorized("unauthorized");
  const { data: profile } = await svc
    .from("profiles")
    .select("role")
    .eq("id", data.user.id)
    .maybeSingle();
  if (profile?.role !== "admin") {
    throw unauthorized("forbidden: admin only", 403);
  }
  return data.user.id;
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
