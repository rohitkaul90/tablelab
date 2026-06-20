// Classify an Anthropic API failure as an "at capacity" condition — org spend
// cap hit, credit balance exhausted, Anthropic-side rate limit, or overload —
// as opposed to a genuine bug.
//
// Why this exists: when the $100 org spend cap binds, EVERY uncached analysis
// fails at once. Without this, each one fell through to the generic 500
// ("Analysis failed. Please try again.") AND fired a Discord ops alert — so the
// user saw a misleading "try again" and the ops channel got flooded exactly when
// the cap bound. Capacity errors instead return CAPACITY_MESSAGE with a 503 and
// are NOT alerted: spend is already monitored by Anthropic's $80 email alert and
// the daily digest, so per-call Discord alerts add only noise.
//
// Detection is defensive across SDK error shapes — prefer HTTP status, fall back
// to the error `type`, then to billing wording in the message. A bare 400 is NOT
// treated as capacity (that's usually a malformed request = a real bug); only a
// 400/403 whose type/message indicates billing counts.

export const CAPACITY_MESSAGE =
  "AI coaching is temporarily at capacity. Please try again later.";

export function isCapacityError(err: unknown): boolean {
  // deno-lint-ignore no-explicit-any
  const e = err as any;
  const status: number | undefined = typeof e?.status === "number"
    ? e.status
    : undefined;
  // The SDK exposes the parsed body in a couple of shapes across versions.
  const type: string | undefined = e?.error?.error?.type ?? e?.error?.type;
  const message: string = String(e?.message ?? "").toLowerCase();

  // Anthropic-side rate limit (429) or overload (529) — transient capacity.
  if (status === 429 || status === 529) return true;
  if (type === "rate_limit_error" || type === "overloaded_error") return true;

  // Spend cap / credit exhaustion. IMPORTANT: Anthropic surfaces this as an
  // HTTP 400 `invalid_request_error` ("Your credit balance is too low…"), NOT a
  // `billing_error` type — so the billing-wording match below is the PRIMARY
  // detector for the spend cap; the `type` check is only defensive for other
  // surfaces (and intentionally tested separately). The SDK's makeMessage
  // JSON-stringifies the response body into `message`, so the wording lands
  // there. Kept billing-specific (no broad "insufficient"/"quota") so a genuine
  // request bug isn't misclassified as capacity and have its ops alert silenced.
  if (type === "billing_error") return true;
  if (/credit balance|billing|spend limit/.test(message)) return true;

  return false;
}
