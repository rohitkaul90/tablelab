// deno test supabase/functions/_shared/capacity.test.ts
import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { isCapacityError } from "./capacity.ts";

Deno.test("429 (Anthropic rate limit) is capacity", () => {
  assert(isCapacityError({ status: 429, message: "rate_limit" }));
});

Deno.test("529 (overloaded) is capacity", () => {
  assert(isCapacityError({ status: 529 }));
});

// Defensive `billing_error` type branch — not the shape Anthropic emits for the
// spend cap (that's an invalid_request_error, see the prod-shape test below),
// but kept for other/future surfaces.
Deno.test("billing_error type is capacity (defensive branch)", () => {
  assert(isCapacityError({ status: 400, error: { type: "billing_error" } }));
});

Deno.test("nested error.error.type billing_error is capacity (defensive)", () => {
  assert(isCapacityError({ status: 403, error: { error: { type: "billing_error" } } }));
});

// The ACTUAL production spend-cap error: HTTP 400, type invalid_request_error,
// with the credit-balance wording in the SDK-stringified `message`. This is the
// path that runs in prod — if the message-regex branch is ever dropped, THIS
// test fails (the type check alone does not catch invalid_request_error).
Deno.test("real spend-cap shape (400 invalid_request_error + credit balance) is capacity", () => {
  const body = {
    type: "error",
    error: {
      type: "invalid_request_error",
      message: "Your credit balance is too low to access the Anthropic API.",
    },
  };
  assert(isCapacityError({
    status: 400,
    error: body,
    message: `400 ${JSON.stringify(body)}`,
  }));
});

// Guards the tightened regex (#3): a genuine request bug whose body happens to
// contain broad words like "insufficient"/"quota" must NOT be swallowed as
// capacity (which would suppress its ops alert).
Deno.test("400 invalid_request mentioning 'insufficient'/'quota' is NOT capacity", () => {
  const body = {
    type: "error",
    error: {
      type: "invalid_request_error",
      message: "tool input has insufficient fields; token quota schema invalid",
    },
  };
  assert(
    !isCapacityError({
      status: 400,
      error: body,
      message: `400 ${JSON.stringify(body)}`,
    }),
  );
});

Deno.test("malformed-request 400 is NOT capacity (real bug → should still alert)", () => {
  assert(
    !isCapacityError({
      status: 400,
      error: { type: "invalid_request_error" },
      message: "messages: roles must alternate",
    }),
  );
});

Deno.test("generic error is NOT capacity", () => {
  assert(!isCapacityError(new Error("Model did not return coaching tool call")));
});

Deno.test("CLAUDE_TIMEOUT-style error is NOT capacity", () => {
  assert(!isCapacityError(new Error("CLAUDE_TIMEOUT")));
});
