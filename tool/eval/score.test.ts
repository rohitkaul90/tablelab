// Regression tests for the frequency-agreement adjudicator (DCE Q1 phase 2b).
//
// Guards the cross-street-summing bug the turn-coverage spots exposed: a
// multi-street GTO-frequency FACT must be parsed PER STREET, never summed
// across streets (which fabricated >100% "frequencies" and fired false
// DISAGREEs). Importing score.ts is safe — main() is import.meta.main-guarded.
//
//   deno test --allow-read tool/eval/score.test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { checkFrequencyAgreement, parseFreqFact } from "./score.ts";

// A realistic two-street FACT (flop has three bet sizes summing to 94% within
// the street; turn is a separate decision). Mirrors the live rendering.
const TWO_STREET = [
  "[HEURISTIC — GTO frequency (a soft PRIOR): " +
  "flop (IP, a strong made hand, after a check to hero): medium bet ~76%, small bet ~18%, check ~7%; " +
  "turn (IP, a strong made hand, after a check to hero): check ~60%, small bet ~40%. " +
  "Use it to sanity-check whether hero's line is balanced.]",
];

const FLOP_ONLY = [
  "[HEURISTIC — GTO frequency (a soft PRIOR): " +
  "flop (OOP, a marginal made hand, first to act): check ~65%, small bet ~34%. " +
  "Use it to sanity-check whether hero's line is balanced.]",
];

Deno.test("parseFreqFact splits per street — bet sizes sum WITHIN a street, never across", () => {
  const p = parseFreqFact(TWO_STREET);
  assert(p.gtoByStreet != null);
  assertEquals(p.gtoByStreet!.length, 2);
  // flop: medium 76 + small 18 = 94% bet (within-street sum is correct); check 7%.
  assertEquals(Math.round(p.gtoByStreet![0].bet * 100), 94);
  assertEquals(Math.round(p.gtoByStreet![0].check * 100), 7);
  // turn: its OWN decision — check 60%, bet 40%. NOT summed onto the flop.
  assertEquals(Math.round(p.gtoByStreet![1].check * 100), 60);
  assertEquals(Math.round(p.gtoByStreet![1].bet * 100), 40);
  // The bug guard: no fabricated >100% frequency anywhere.
  for (const street of p.gtoByStreet!) {
    for (const f of Object.values(street)) assert(f <= 1.0, `frequency ${f} > 100%`);
  }
});

Deno.test("parseFreqFact on a flop-only FACT yields a single segment (byte-identical to pre-fix)", () => {
  const p = parseFreqFact(FLOP_ONLY);
  assert(p.gtoByStreet != null);
  assertEquals(p.gtoByStreet!.length, 1);
  assertEquals(Math.round(p.gtoByStreet![0].check * 100), 65);
  assertEquals(Math.round(p.gtoByStreet![0].bet * 100), 34);
});

Deno.test("checkFrequencyAgreement: a claim matching ANY street is consistent", () => {
  const p = parseFreqFact(TWO_STREET);
  // check ~60% matches the turn segment exactly — no violation even though the
  // flop check is 7% (different street, different decision).
  const r = checkFrequencyAgreement(p, [{ action: "check", percent: 60 }]);
  assertEquals(r.scored, true);
  assertEquals(r.violations.length, 0);
});

Deno.test("checkFrequencyAgreement: a claim contradicting EVERY street violates (no >100% phantom)", () => {
  const p = parseFreqFact(TWO_STREET);
  // check ~96% matches neither flop (7%) nor turn (60%) → a real contradiction.
  const r = checkFrequencyAgreement(p, [{ action: "check", percent: 96 }]);
  assertEquals(r.violations.length, 1);
  // The message must cite the real per-street values, never a summed >100%.
  assert(!/~1\d\d%|~[2-9]\d\d%/.test(r.violations[0]), `phantom >100% in: ${r.violations[0]}`);
  assert(r.violations[0].includes("~7%") && r.violations[0].includes("~60%"));
});

Deno.test("checkFrequencyAgreement: an action no street lists is skipped, not violated", () => {
  const p = parseFreqFact(TWO_STREET);
  // Neither street lists fold → the claim is simply unscored.
  const r = checkFrequencyAgreement(p, [{ action: "fold", percent: 50 }]);
  assertEquals(r.violations.length, 0);
});
