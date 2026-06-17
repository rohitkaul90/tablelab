# AI eval harness — ops doc

Measures the **card-logic accuracy** of the live `analyze-hand` coaching by
running the **real production prompt** against a fixed benchmark of hands with
known-correct answers. Design rationale + roadmap context: `launch/EVAL_HARNESS.md`.

This is the trust instrument: it produces the publishable accuracy number and
acts as a **regression gate** before any prompt / `SYSTEM_PROMPT` / model change.

## Two stages

| Stage | Lang | When | Cost | What |
|---|---|---|---|---|
| **1. bake** | Dart (`bake_fixtures.dart`) | rarely (benchmark changes) | $0 | PHH → `PokerHand`, compute on-device `equityFacts`, bake independent ground-truth labels |
| **2. score** | Deno (`score.ts`) | every prompt/model change | ~$0.034/hand + judge | import the REAL prompt, call Claude, score prose vs labels |

**Why two languages, two implementations:** the labels come from the Dart
`lib/equity/evaluator.dart`; the prompt's card-logic FACTs come from the
TypeScript `computeBoardSummary`/`computeDrawSummary` in the Edge Function. They
are *separate codebases*, so the scorer catches **FACT-generator bugs**, not
just model hallucinations.

**Faithfulness:** `score.ts` imports `buildPrompt` + `SYSTEM_PROMPT` +
`COACHING_TOOL` from `supabase/functions/analyze-hand/prompt.ts` — the exact prod
code (extracted out of `index.ts` precisely so it's importable without booting
`serve()`). The one thing Deno can't recompute — the Dart `equityFacts` — is
baked in Stage 1 and fed in. Periodically sanity-check against deployed prod by
calling the function over HTTP (Approach A in the spec).

## Run it

### 1. Bake fixtures (free, deterministic)

```bash
# Edit tool/eval/spots.json to curate the benchmark, then:
dart run tool/eval/bake_fixtures.dart            # spots.json -> tool/eval/fixtures/*.json
```

Each spot in `spots.json`:

```json
{
  "id": "pluribus-100-1-mrpink",      // fixture filename + report key (unique)
  "file": "tool/eval/samples/pluribus-100-1.phh",
  "source": "pluribus/100/1",          // human label
  "hero": 3,                            // 1-based PHH player index; must have known hole cards
  "bucket": "card-logic",               // "card-logic" | "solver-checkable"
  "notes": "…",                         // optional; becomes hand.notes (AI ground-truth hint)
  "reads": [ { "playerLabel": "MrWhite", "tags": ["calling_station"] } ]  // optional
}
```

`bake` skips (and logs) a spot whose hero has no face-up hole cards or whose
equity is unmodelable. Fixtures are **checked into the repo** so Stage-2 runs are
reproducible and diffable across prompt changes.

### 2. Score (costs money — run locally, never in CI)

```bash
export ANTHROPIC_API_KEY=sk-ant-...          # your key; ~$0.034/hand + Opus judge tokens
deno run --allow-read --allow-write --allow-env --allow-net \
  tool/eval/score.ts                          # fixtures/ -> tool/eval/reports/report.{md,json}
```

A ~300-spot run ≈ $10. Keep it manual (like `scripts/ai-cost-report.mjs`).

## Scoring (the MVP: card-logic)

Hybrid, so the score's authority never rests on a model:

1. **Coach** — feed each fixture through the real prompt → structured coaching.
2. **Judge (Opus)** — extracts factual claims from the prose (made hands,
   named straights, flushes, equity/pot-odds %s, card identities). It only
   *proposes* claims.
3. **Adjudicator (deterministic)** — rules each claim against the baked labels.
   Current checks (conservative, low false-positive):
   - full house / quads named on a board no street pairs → violation;
   - a made flush named when no board reaches 3+ of a suit → violation;
   - a specific straight named that no board window allows → violation;
   - a stated hero equity/pot-odds % that deviates >12 pts from the injected
     FACT → violation.

**Headline metric:** % of spots with **zero** card-logic violations.

## Verdict consistency (a second dimension)

Separate from card-logic, the scorer checks the coach output's **self-
consistency** — directly from the structured fields, no judge, no extra API
call. The `SYSTEM_PROMPT` requires `verdict=leakDetected ⟺ keyMistake present ⟺
at least one street marked wasGto:false`; the three leak signals must agree (all
"clean" or all "leak"). A disagreement (e.g. `leakDetected` + a keyMistake
naming a river error, but every street `wasGto:true`) is the self-contradiction
class the trust pack exists to catch. A benign null-stand-in keyMistake ("none",
"null", "well-played") is treated as no mistake, not a contradiction.

**Metric:** **verdict consistency %** = scored spots with zero verdict issues.
This is intermittent (temperature-0 isn't bitwise deterministic, so a model
contradiction may appear on one run and not the next) — read it over the whole
set, not per spot.

## Forced-decision agreement (the spec's verdict-agreement, tightly scoped)

On a **pot-odds-DECISIVE** spot — hero faces a wager that closes the action (a
river call, or a call/fold that puts hero all-in) — the correct action is
mathematically forced: call iff hero's equity meets the break-even price. Stage 1
bakes this as `forcedDecision` (`tool/eval/forced_decision.dart` re-derives the
decisive price by replaying the hand — an INDEPENDENT implementation of the Edge
Function's `heroPotOddsFact`, so a mismatch is itself a bug; the equity is the
on-device cross-check's). Most spots have no decisive decision → `null` → not
scored.

Stage 2 checks whether the model's `wasGto` for the decision street agrees with
whether hero's actual action was the forced-correct one. **Metric:** **forced-
verdict agreement %** over the decisive subset only (everything else silent; a
decisive spot where the model gave no `wasGto` for the street is reported
`unscored`, never guessed). This is the spec's math-forced verdict agreement —
the equity/pot-odds consistency the card-logic MVP deliberately scoped out.

## Read the report

`tool/eval/reports/report.md`: headline accuracy %, violations by category, and
a per-spot table. `report.json` has the full claim/violation detail and is
diffable run-to-run (which spots regressed/improved).

Accuracy is over **scored** spots only. Two integrity counters sit beside it:
**errored** (a refusal / 5xx / timeout — excluded from the denominator so an API
blip can't move the number) and **unscored equity claims** (an equity claim on a
street with no baked equity label — surfaced, never silently dropped). Each
board-constraint claim is checked against the label of the street it was
attributed to, so an early-street hallucination is not excused by a later runout
card. Spot-audit a few `report.json` claims each run to keep the judge honest.

## Regression gate

Before shipping a prompt/`SYSTEM_PROMPT`/model change: re-bake if the benchmark
changed, run `score.ts`, and block on a card-logic regression vs the previous
`report.json`.

## Add a benchmark spot

1. Drop the `.phh` into `tool/eval/samples/` (or point `file` at any path).
   Source: `github.com/uoftcprg/phh-dataset` (Pluribus hands have all hole cards).
2. Add an entry to `spots.json` (pick a hero with known cards; choose the bucket).
3. `dart run tool/eval/bake_fixtures.dart` and commit the new fixture.

### Bulk curation (`curate.dart`)

To generate a balanced set at scale instead of hand-picking, point the curator
at a Pluribus corpus:

```bash
# one-time: sparse-clone just the Pluribus data
git clone --depth 1 --filter=blob:none --sparse https://github.com/uoftcprg/phh-dataset.git /tmp/phh
( cd /tmp/phh && git sparse-checkout set data/pluribus )

dart run tool/eval/curate.dart /tmp/phh/data/pluribus 30   # -> spots.json + samples/pluribus/*.phh
dart run tool/eval/bake_fixtures.dart                       # -> fixtures/
```

It classifies each hand's final board texture and fills quotas weighted toward
the hallucination-prone shapes (flush / paired / straight boards), plus a small
solver-checkable set (preflop all-ins). Hero = a known-cards player who never
folded, so every spot has postflop streets to score. Re-running overwrites
`spots.json`; commit the chosen `.phh` files + baked fixtures.

Curate toward the two buckets: **card-logic stress** (paired/tripled boards,
straight-completing boards, monotone/two-tone flush boards, thin bluff-catches —
the patched-bug triggers) and **solver-checkable** (preflop all-ins, pot-odds-
decisive rivers; for the future verdict-agreement scorer).

## Limits (read honestly)

- The LLM judge adds its own noise; mitigated by deterministic adjudication.
  Spot-audit a few `report.json` claim lists each run to keep the judge honest.
  Read the number as "≥ this accurate," not gospel.
- Verdict-agreement scoring (vs card-logic) is **not yet built** — it lands on
  the solver-checkable subset only (preflop all-ins, pot-odds-decisive rivers).
- Made-hand grading is coarse (the 9 categories). It catches the board-constraint
  failure class, not fine errors like "top pair" vs "middle pair."
