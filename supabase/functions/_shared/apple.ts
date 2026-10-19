// Sign in with Apple server-side helpers (Deno / WebCrypto, no dependencies).
//
// Apple's token + revoke endpoints authenticate the *app* with a client_secret:
// an ES256 JWT signed by a "Sign in with Apple" key from the developer portal
// (Certificates, Identifiers & Profiles → Keys). Secrets (supabase secrets set):
//   APPLE_SIWA_KEY_ID        — the key's 10-char Key ID
//   APPLE_SIWA_PRIVATE_KEY   — the downloaded AuthKey_XXXX.p8 contents (PEM;
//                              literal newlines or "\n"-escaped both accepted)
//   APPLE_TEAM_ID            — 10-char Team ID
//   APPLE_BUNDLE_ID          — com.pokertracker.pokerTracker (the client_id for
//                              the native iOS flow)
// Used by `apple-link` (authorization code → refresh token at sign-in) and
// `delete-account` (revoke on deletion; App Store guideline 5.1.1(v)).

const APPLE_AUD = "https://appleid.apple.com";
const TOKEN_URL = "https://appleid.apple.com/auth/token";
const REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export interface AppleConfig {
  keyId: string;
  privateKeyPem: string;
  teamId: string;
  bundleId: string;
}

/** The iOS bundle id doubles as Apple's client_id for the native flow. It is
 *  public (pinned in ios/fastlane + ExportOptions.plist), so it is a default,
 *  not a required secret — only the three genuinely secret values can fail the
 *  path closed. */
export const DEFAULT_BUNDLE_ID = "com.pokertracker.pokerTracker";

/** Reads the secrets; returns null (not throws) when a required one is unset so
 *  callers can degrade with an alert instead of failing the request. */
export function appleConfigFromEnv(): AppleConfig | null {
  const keyId = Deno.env.get("APPLE_SIWA_KEY_ID");
  const privateKeyPem = Deno.env.get("APPLE_SIWA_PRIVATE_KEY");
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const bundleId = Deno.env.get("APPLE_BUNDLE_ID") || DEFAULT_BUNDLE_ID;
  if (!keyId || !privateKeyPem || !teamId) return null;
  return { keyId, privateKeyPem, teamId, bundleId };
}

/** `sub` claim of a JWT's payload without verifying the signature — only for a
 *  token Apple just handed us over TLS in its own /auth/token response, where
 *  the transport is the trust anchor. Returns null on any malformed input. */
export function idTokenSubject(idToken: string): string | null {
  const parts = idToken.split(".");
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
    const payload = JSON.parse(atob(b64 + pad));
    return typeof payload.sub === "string" && payload.sub.length > 0 ? payload.sub : null;
  } catch {
    return null;
  }
}

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Explicit ArrayBuffer backing: WebCrypto's BufferSource rejects the
// ArrayBufferLike (SharedArrayBuffer-capable) type a bare Uint8Array infers.
function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Builds Apple's client_secret: ES256 JWT {iss: team, sub: bundle id,
 *  aud: appleid.apple.com}, valid for [ttlSeconds] (Apple caps at 6 months;
 *  we only need it for one request). */
export async function appleClientSecret(
  cfg: AppleConfig,
  now: number = Math.floor(Date.now() / 1000),
  ttlSeconds = 600,
): Promise<string> {
  const enc = new TextEncoder();
  const header = base64url(enc.encode(JSON.stringify({ alg: "ES256", kid: cfg.keyId, typ: "JWT" })));
  const payload = base64url(enc.encode(JSON.stringify({
    iss: cfg.teamId,
    iat: now,
    exp: now + ttlSeconds,
    aud: APPLE_AUD,
    sub: cfg.bundleId,
  })));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(cfg.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto ECDSA emits the raw r||s concatenation JWS ES256 requires (not DER).
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    enc.encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(sig))}`;
}

export interface AppleTokens {
  refreshToken: string;
  accessToken?: string;
  /** Apple's ID token for the authorization that produced the code — its `sub`
   *  is the Apple user id the caller MUST be checked against before storing. */
  idToken?: string;
}

/** Exchanges the sign-in `authorizationCode` (valid ~5 min, single use) for a
 *  refresh token. Throws with Apple's error code on failure. */
export async function exchangeAuthorizationCode(
  cfg: AppleConfig,
  authorizationCode: string,
): Promise<AppleTokens> {
  const body = new URLSearchParams({
    client_id: cfg.bundleId,
    client_secret: await appleClientSecret(cfg),
    code: authorizationCode,
    grant_type: "authorization_code",
  });
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
    signal: AbortSignal.timeout(10_000),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || typeof json.refresh_token !== "string") {
    throw new Error(`apple token exchange failed: ${res.status} ${json.error ?? ""}`.trim());
  }
  return {
    refreshToken: json.refresh_token,
    accessToken: json.access_token,
    idToken: typeof json.id_token === "string" ? json.id_token : undefined,
  };
}

/** Revokes a refresh token. Apple answers 200 on success (and also when the
 *  token was already invalid). Throws on any other status. */
export async function revokeRefreshToken(cfg: AppleConfig, refreshToken: string): Promise<void> {
  const body = new URLSearchParams({
    client_id: cfg.bundleId,
    client_secret: await appleClientSecret(cfg),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  const res = await fetch(REVOKE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`apple revoke failed: ${res.status} ${text.slice(0, 200)}`);
  }
}
