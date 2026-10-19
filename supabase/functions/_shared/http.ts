// Shared HTTP helpers for the app-called Edge Functions.
//
// CORS is locked to the web origins (CLAUDE.md: never revert to `*`); mobile
// sends no Origin header and is unaffected. `Vary: Origin` keeps caches honest.
// The AI functions and submit-feedback still carry their own identical copies —
// migrate them here opportunistically so an origin/header change lands once.

const allowedOrigins = new Set(["https://tablelab.app", "https://www.tablelab.app"]);

export function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigin = allowedOrigins.has(origin) ? origin : "https://tablelab.app";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

export function json(body: unknown, status: number, cors: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
