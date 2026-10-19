// apple-link — called by the iOS app right after a successful Sign in with Apple.
//
// Exchanges the one-shot `authorizationCode` from Apple's credential for a
// refresh token and stores it (service-role, keyed by user_id) so that
// `delete-account` can revoke it later — App Store Review Guideline 5.1.1(v)
// requires revoking Sign in with Apple tokens when the user deletes their
// account. The client treats this call as best-effort: a failure is alerted here
// and never blocks sign-in.
//
// Deploy AFTER 20261019_apple_refresh_tokens.sql is applied and the APPLE_SIWA_*
// secrets are set (see _shared/apple.ts). Default verify_jwt = true (user token).
import { createClient } from "npm:@supabase/supabase-js@2";
import { reportError } from "../_shared/alert.ts";
import { appleConfigFromEnv, exchangeAuthorizationCode } from "../_shared/apple.ts";

const allowedOrigins = new Set(["https://tablelab.app", "https://www.tablelab.app"]);

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigin = allowedOrigins.has(origin) ? origin : "https://tablelab.app";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

function json(body: unknown, status: number, cors: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, cors);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401, cors);

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "Unauthorized" }, 401, cors);

  // Only an account that actually carries an Apple identity can link one.
  const identities = (user.identities ?? []) as Array<{ provider?: string }>;
  if (!identities.some((i) => i.provider === "apple")) {
    return json({ error: "No Apple identity on this account" }, 400, cors);
  }

  let code: unknown;
  try {
    ({ authorizationCode: code } = await req.json());
  } catch {
    return json({ error: "Invalid JSON" }, 400, cors);
  }
  if (typeof code !== "string" || code.length < 10 || code.length > 2048) {
    return json({ error: "authorizationCode required" }, 400, cors);
  }

  const cfg = appleConfigFromEnv();
  if (!cfg) {
    await reportError("apple-link", "APPLE_SIWA_* secrets are not set — refresh token NOT stored");
    return json({ error: "Apple linking unavailable" }, 503, cors);
  }

  try {
    const tokens = await exchangeAuthorizationCode(cfg, code);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { error } = await admin
      .from("apple_refresh_tokens")
      .upsert(
        { user_id: user.id, refresh_token: tokens.refreshToken, updated_at: new Date().toISOString() },
        { onConflict: "user_id" },
      );
    if (error) {
      // supabase-js doesn't throw — check explicitly (GRANTs gotcha: a 42501 here
      // would otherwise be a silent "200 but nothing stored").
      await reportError("apple-link", `refresh token upsert failed: ${error.code ?? ""} ${error.message}`);
      return json({ error: "Could not store Apple link" }, 500, cors);
    }
    return json({ linked: true }, 200, cors);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("apple-link:", msg);
    await reportError("apple-link", msg);
    return json({ error: "Apple token exchange failed" }, 502, cors);
  }
});
