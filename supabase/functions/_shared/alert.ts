// Ops alert → Discord (or any Slack-compatible webhook).
//
// Set via: supabase secrets set ALERT_WEBHOOK_URL=<discord webhook URL + /slack>
// The /slack suffix makes Discord accept the Slack-style {"text": ...} payload —
// the same format scripts/smoke-test.mjs sends to SMOKE_ALERT_WEBHOOK, so one
// channel serves both. No-op when the secret is unset (safe to deploy first,
// configure later). Never include user data in `detail` — function name, error
// code/message, and timestamps only.

export async function reportError(fn: string, detail: string): Promise<void> {
  const url = Deno.env.get("ALERT_WEBHOOK_URL");
  if (!url) return;
  try {
    await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      // Discord caps messages at 2000 chars — trim with margin.
      body: JSON.stringify({ text: `🔴 ${fn}: ${detail}`.slice(0, 1900) }),
      signal: AbortSignal.timeout(3000),
    });
  } catch (e) {
    // Alerting must never break the request path.
    console.error("alert webhook failed:", e instanceof Error ? e.message : e);
  }
}
