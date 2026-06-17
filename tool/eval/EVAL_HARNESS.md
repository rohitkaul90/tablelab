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
