import { createClient } from "npm:@supabase/supabase-js@2";
import { reportError } from "../_shared/alert.ts";

// CORS locked to the web origins (mirrors the AI functions). Mobile sends no
// Origin header and is unaffected; the web build is origin-checked.
const allowedOrigins = new Set([
  "https://tablelab.app",
  "https://www.tablelab.app",
]);

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigin = allowedOrigins.has(origin) ? origin : "https://tablelab.app";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

const CATEGORIES = new Set(["bug", "idea", "praise", "other"]);
const MAX_MESSAGE = 4000; // generous; Discord caps the *posted* line separately
const FEEDBACK_DAILY_LIMIT = 15; // light anti-spam per user

const CATEGORY_ICON: Record<string, string> = {
  bug: "🐞",
  idea: "💡",
  praise: "🎉",
  other: "🗣️",
};

function json(body: unknown, status: number, cors: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// Post the feedback to the dedicated #user-feedback Discord channel. Unlike the
// ops alert channel (ALERT_WEBHOOK_URL, which must stay user-data-free), this
// webhook intentionally carries the user's text. No-op when unset.
async function postToDiscord(text: string): Promise<void> {
  const url = Deno.env.get("FEEDBACK_WEBHOOK_URL");
  if (!url) return;
  try {
    await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: text.slice(0, 1900) }), // Discord 2000-char cap
      signal: AbortSignal.timeout(3000),
    });
  } catch (e) {
    // Posting to Discord must never fail the request — the row is already saved.
    console.error("feedback webhook failed:", e instanceof Error ? e.message : e);
  }
}

Deno.serve(async (req) => {
  const cors = getCorsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, cors);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401, cors);

  // Verify the caller is a legitimate authenticated user (anon + JWT client).
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "Unauthorized" }, 401, cors);

  // Parse + validate input.
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid request" }, 400, cors);
  }

  const category = String(payload.category ?? "").toLowerCase();
  const message = String(payload.message ?? "").trim();
  const shareEmail = payload.shareEmail === true;
  const ratingRaw = payload.rating;
  const rating = typeof ratingRaw === "number" && ratingRaw >= 1 && ratingRaw <= 5
    ? Math.round(ratingRaw)
    : null;
  const appVersion = payload.appVersion ? String(payload.appVersion).slice(0, 40) : null;
  const platform = payload.platform ? String(payload.platform).slice(0, 20) : null;

  if (!CATEGORIES.has(category)) return json({ error: "Invalid category" }, 400, cors);
  if (!message) return json({ error: "Message is required" }, 400, cors);
  if (message.length > MAX_MESSAGE) {
    return json({ error: "Message too long" }, 400, cors);
  }

  // Service-role client for the write — the anon+JWT token doesn't reliably
  // propagate into PostgREST's RLS context, so scope user_id explicitly here.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Light per-user daily rate limit (anti-spam).
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error: countErr } = await admin
    .from("feedback")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", since);
  if (countErr) {
    console.error("feedback rate-limit read failed:", countErr.code, countErr.message);
    await reportError("submit-feedback", `rate-limit read failed: ${countErr.code} ${countErr.message}`);
  }
  if ((count ?? 0) >= FEEDBACK_DAILY_LIMIT) {
    return json({ error: "Daily feedback limit reached. Thanks — try again tomorrow." }, 429, cors);
  }

  const { error: insertErr } = await admin.from("feedback").insert({
    user_id: user.id,
    email: shareEmail ? (user.email ?? null) : null,
    category,
    message,
    rating,
    app_version: appVersion,
    platform,
  });
  if (insertErr) {
    console.error("feedback insert failed:", insertErr.code, insertErr.message);
    await reportError("submit-feedback", `insert failed: ${insertErr.code} ${insertErr.message}`);
    return json({ error: "Could not save feedback. Please try again." }, 500, cors);
  }

  // Notify Discord (best-effort, after the durable write).
  const icon = CATEGORY_ICON[category] ?? "🗣️";
  const meta = [appVersion, platform].filter(Boolean).join(" ");
  const stars = rating ? ` · ${"★".repeat(rating)}${"☆".repeat(5 - rating)}` : "";
  const who = shareEmail && user.email
    ? `— ${user.email}`
    : `— user ${user.id.slice(0, 8)}…`;
  await postToDiscord(`${icon} [${category}]${meta ? ` ${meta}` : ""}${stars}\n"${message}"\n${who}`);

  return json({ success: true }, 200, cors);
});
