/**
 * Shared AES-GCM helpers for CekDulu Edge Functions (Deno).
 *
 * The write-only `secret` inside affiliate_credentials is stored encrypted.
 * Key material comes ONLY from the AFFILIATE_ENCRYPTION_KEY environment
 * variable (base64 of 32 random bytes). Never log plaintext or keys.
 */

const te = new TextEncoder();
const td = new TextDecoder();

function b64encode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function b64decode(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function getKeyB64(): string {
  const k = Deno.env.get("AFFILIATE_ENCRYPTION_KEY");
  if (!k) throw new Error("Missing env AFFILIATE_ENCRYPTION_KEY");
  return k;
}

async function importKey(): Promise<CryptoKey> {
  const raw = b64decode(getKeyB64().trim());
  if (raw.length !== 32) {
    throw new Error("AFFILIATE_ENCRYPTION_KEY must base64-decode to 32 bytes");
  }
  return await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, [
    "encrypt",
    "decrypt",
  ]);
}

/** Encrypt plaintext. Returns "ivBase64.cipherBase64". */
export async function encryptSecret(plaintext: string): Promise<string> {
  const key = await importKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    te.encode(plaintext),
  );
  return `${b64encode(iv)}.${b64encode(new Uint8Array(ct))}`;
}

/** Decrypt a payload produced by encryptSecret(). */
export async function decryptSecret(payload: string): Promise<string> {
  const key = await importKey();
  const parts = payload.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw new Error("Malformed encrypted payload");
  }
  const pt = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: b64decode(parts[0]) },
    key,
    b64decode(parts[1]),
  );
  return td.decode(pt);
}
