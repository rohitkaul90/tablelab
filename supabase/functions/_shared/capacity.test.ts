// deno test supabase/functions/_shared/capacity.test.ts
import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { isCapacityError } from "./capacity.ts";

Deno.test("429 (Anthropic rate limit) is capacity", () => {
  assert(isCapacityError({ status: 429, message: "rate_limit" }));
});

Deno.test("529 (overloaded) is capacity", () => {
  assert(isCapacityError({ status: 529 }));
});

Deno.test("billing_error type is capacity", () => {
  assert(isCapacityError({ status: 400, error: { type: "billing_error" } }));
});

Deno.test("nested error.error.type billing_error is capacity", () => {
  assert(isCapacityError({ status: 403, error: { error: { type: "billing_error" } } }));
});

Deno.test("credit-balance message is capacity (spend cap)", () => {
  assert(isCapacityError({
    status: 400,
    message: "Your credit balance is too low to access the Anthropic API.",
  }));
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
