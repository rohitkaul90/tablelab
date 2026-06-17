// Stage 2 of the eval harness: score the REAL analyze-hand prompt against the
// baked fixtures and emit a card-logic accuracy report.
//
// For each fixture it imports the ACTUAL production prompt code
// (buildPrompt + SYSTEM_PROMPT + COACHING_TOOL from the Edge Function's
// prompt.ts — that import is why we extracted it), feeds the fixture's
// hand + reads + pre-baked equityFacts, calls Claude exactly as prod does
// (claude-sonnet-4-6, temperature 0, forced tool call), then scores the model's
// prose for card-logic errors.
//
// Scoring is HYBRID: a strong-model LLM judge (Opus) EXTRACTS factual claims
// from the free prose, then a DETERMINISTIC adjudicator rules each claim against
// the Stage-1 labels (computed independently by the Dart evaluator). The judge
// proposes; deterministic code decides — the headline number's authority never
// rests on a model. See launch/EVAL_HARNESS.md.
//
// Run locally (needs ANTHROPIC_API_KEY; costs ~$0.034/hand + judge tokens):
//   deno run --allow-read --allow-write --allow-env --allow-net \
//     tool/eval/score.ts [fixturesDir] [outDir]
//
// NOT wired into CI — it spends money and needs the key (mirrors
// scripts/ai-cost-report.mjs).

import Anthropic from "npm:@anthropic-ai/sdk@0.36.3";
import {
  buildPrompt,
  COACHING_TOOL,
  type PlayerRead,
  type PokerHand,
  SYSTEM_PROMPT,
} from "../../supabase/functions/analyze-hand/prompt.ts";

const COACH_MODEL = "claude-sonnet-4-6"; // must mirror analyze-hand/index.ts
const JUDGE_MODEL = "claude-opus-4-8"; // strongest card logic for claim extraction
const CONCURRENCY = 8; // fixtures scored in parallel (SDK auto-retries 429s)

/// Run `fn` over `items` with at most `limit` in flight; results stay in input
/// order. A ~300-spot run is two API calls per item, so sequential execution is
/// ~2h of mostly-idle wall-clock — bounded concurrency cuts it to minutes.
async function mapPool<T, R>(
  items: T[],
  limit: number,
  fn: (item: T, i: number) => Promise<R>,
): Promise<(R | undefined)[]> {
  const results = new Array<R | undefined>(items.length);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= items.length) break;
      // Never let one item's unexpected throw reject Promise.all — that would
      // discard every other worker's completed result and lose a costed run
      // with no report. The slot is left undefined; the caller fills it.
      try {
        results[i] = await fn(items[i], i);
      } catch (e) {
        console.error(`mapPool: item ${i} threw: ${e instanceof Error ? e.message : e}`);
        results[i] = undefined;
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker()),
  );
  return results;
}

// ── Fixture / label types (the Stage-1 bake output) ──────────────────────────

interface StreetLabel {
  street: string;
  board: string[];
  heroCategory: string;
  heroEquity: number | null;
  boatOrQuadsPossible: boolean;
  flushPossible: boolean;
  flushSuit: string | null;
  allowedStraightWindows: string[];
}
// The math-forced correct action on a pot-odds-decisive spot (null otherwise).
interface ForcedDecisionLabel {
  street: string;
  heroCalled: boolean;
  requiredPct: number;
  heroEquityPct: number;
  forcedAction: string; // 'call' | 'fold'
  heroActionCorrect: boolean;
}
interface Fixture {
  id: string;
  source: string;
  bucket: string;
  reads: PlayerRead[];
  hand: PokerHand;
  equityFacts: string[];
  labels: {
    heroHoleCards: string[];
    finalBoard: string[];
    perStreet: StreetLabel[];
    forcedDecision?: ForcedDecisionLabel | null;
  };
}

// ── A claim the judge extracted from the model's prose ───────────────────────

interface Claim {
  street: string; // preflop|flop|turn|river|overall
  subject: string; // hero|villain|board
  category: string; // hand_category|straight|flush|equity|pot_odds|card_identity|other
  text: string; // the phrase it came from
  handCategoryNamed?: string | null; // e.g. "full house","flush","two pair"
  straightRanks?: string | null; // e.g. "T-J-Q-K-A" (dash-joined) if a specific straight is named
  suit?: string | null; // for flush claims
  percent?: number | null; // for equity/pot_odds claims
}

interface Violation {
  fixtureId: string;
  street: string;
  category: string;
  detail: string;
  claim: string;
}

// ── Anthropic plumbing ────────────────────────────────────────────────────────

const client = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

// deno-lint-ignore no-explicit-any
function toolInput(message: any): Record<string, unknown> | null {
  const block = message.content.find((c: { type: string }) => c.type === "tool_use");
  return block ? block.input : null;
}

/** Call the production coaching prompt exactly as analyze-hand does. */
async function runCoaching(fx: Fixture): Promise<Record<string, unknown>> {
  const { prompt } = buildPrompt(fx.hand, fx.reads ?? [], fx.equityFacts ?? []);
  const message = await client.messages.create({
    model: COACH_MODEL,
    max_tokens: 2000,
    temperature: 0,
    system: [{ type: "text", text: SYSTEM_PROMPT }],
    tools: [COACHING_TOOL],
    tool_choice: { type: "tool", name: "provide_hand_coaching" },
    messages: [{ role: "user", content: prompt }],
  });
  const input = toolInput(message);
  if (!input) throw new Error(`${fx.id}: model returned no coaching tool call`);
  return input;
}

// Tool the judge is forced to call: a flat list of extracted factual claims.
// deno-lint-ignore no-explicit-any
const EXTRACT_TOOL: any = {
  name: "report_claims",
  description: "Report every factual poker claim made in the coaching prose.",
  input_schema: {
    type: "object",
    properties: {
      claims: {
        type: "array",
        items: {
          type: "object",
          properties: {
            street: { type: "string", enum: ["preflop", "flop", "turn", "river", "overall"] },
            subject: { type: "string", enum: ["hero", "villain", "board"] },
            category: {
              type: "string",
              enum: ["hand_category", "straight", "flush", "equity", "pot_odds", "card_identity", "other"],
            },
            text: { type: "string", description: "the exact phrase the claim came from" },
            handCategoryNamed: {
              anyOf: [{ type: "null" }, { type: "string" }],
              description:
                "if a made-hand category is asserted to EXIST (not merely a draw), name it: 'high card','one pair','two pair','three of a kind','straight','flush','full house','quads','straight flush'. Null otherwise.",
            },
            straightRanks: {
              anyOf: [{ type: "null" }, { type: "string" }],
              description: "if a SPECIFIC straight is named, its five ranks dash-joined high-low e.g. 'T-J-Q-K-A'. Null otherwise.",
            },
            suit: { anyOf: [{ type: "null" }, { type: "string" }] },
            percent: {
              anyOf: [{ type: "null" }, { type: "number" }],
              description:
                "For category 'equity', the percent MUST be HERO's own equity/chance-to-win against the range, as a point estimate FOR THIS STREET, else null. Do NOT put a number here when it is: a required/break-even/FLOOR pot-odds price ('needs 19%', 'the 19% floor', 'clears the price') — that is category 'pot_odds'; a percentage of the VILLAIN's range ('loses to 93% of his range' — hero's equity is the complement, not 93); a PRIOR-street equity quoted while discussing a later street ('from 84% preflop to 63%' on the flop → only 63 is the flop equity); or a bound rather than a point estimate ('exceeds 50%', 'at least 30%').",
            },
          },
          required: ["street", "subject", "category", "text", "handCategoryNamed", "straightRanks", "suit", "percent"],
        },
      },
    },
    required: ["claims"],
  },
};

const JUDGE_SYSTEM =
  `You extract factual claims from poker coaching prose for an automated card-logic check. ` +
  `Do NOT judge whether the advice is good — only surface the concrete factual assertions: ` +
  `made hands attributed to hero or a villain, named straights, flushes, equity/pot-odds percentages, and exact card identities. ` +
  `A "draw" (e.g. "flush draw","gutshot") is NOT a made-hand claim — only report handCategoryNamed when the prose asserts the made hand EXISTS now. ` +
  `Set handCategoryNamed (and straightRanks) to null for NEGATED or HYPOTHETICAL hands: "the board is unpaired so no full house exists", "no flush is possible", "villain COULD boat up if it pairs", "a straight would complete with a 9" — none of these assert a present made hand. Only a positive present-tense assertion counts. ` +
  `EQUITY vs POT-ODDS: a category 'equity' claim's percent is HERO's own chance to win, for THAT street, as a point estimate. A required/break-even/FLOOR price ("needs 19%", "the 19% floor") is category 'pot_odds', not equity. "Hero loses to 93% of the range" is NOT 93% equity (hero's equity is the complement). A prior-street number quoted on a later street ("84% preflop ... 63% now") contributes only the current-street value. A bound ("exceeds 50%") is not a point estimate — null. ` +
  `Attribute each claim to the street whose discussion it appears in. Be exhaustive but do not invent claims the text does not make.`;

async function extractClaims(fx: Fixture, analysis: Record<string, unknown>): Promise<Claim[]> {
  // Gather the prose fields the model produced.
  const parts: string[] = [];
  const push = (label: string, v: unknown) => {
    if (typeof v === "string" && v.trim()) parts.push(`[${label}] ${v}`);
  };
  push("summary", analysis.summary);
  push("keyMistake", analysis.keyMistake);
  for (const st of ["preflop", "flop", "turn", "river"]) {
    const s = analysis[st] as Record<string, unknown> | null;
    if (s) {
      push(`${st}.decision`, s.decision);
      push(`${st}.optimal`, s.optimal);
      push(`${st}.rationale`, s.rationale);
    }
  }
  const prose = parts.join("\n");

  const message = await client.messages.create({
    // NB: claude-opus-4-8 removed temperature/top_p/top_k (400 if sent) — unlike
    // the coach's claude-sonnet-4-6, which still accepts temperature. The judge
    // only proposes claims; the deterministic adjudicator decides, so the lack
    // of a temperature knob here doesn't affect the score's authority.
    model: JUDGE_MODEL,
    max_tokens: 4000,
    system: [{ type: "text", text: JUDGE_SYSTEM }],
    tools: [EXTRACT_TOOL],
    tool_choice: { type: "tool", name: "report_claims" },
    messages: [{
      role: "user",
      content:
        `Hand context — hero hole cards: ${fx.labels.heroHoleCards.join(" ")}; final board: ${fx.labels.finalBoard.join(" ")}.\n\n` +
        `Coaching prose to extract from:\n${prose}`,
    }],
  });
  const input = toolInput(message);
  return ((input?.claims as Claim[]) ?? []);
}

// ── Deterministic adjudicator: rule each claim against the baked labels ───────

const _boatWords = ["full house", "boat", "quads", "four of a kind", "four-of-a-kind"];

function labelForStreet(fx: Fixture, street: string): StreetLabel | null {
  const ps = fx.labels.perStreet;
  if (ps.length === 0) return null;
  const found = ps.find((s) => s.street === street);
  // "overall"/"preflop"/unmatched → use the final (most complete) board label.
  return found ?? ps[ps.length - 1];
}

interface AdjudResult {
  violations: Violation[];
  // Hero-equity claims that WERE checked against a baked equity label.
  scoredEquity: number;
  // Hero-equity claims that couldn't be checked because the claim's street has
  // no baked equity label (e.g. a villain folded earlier so the street wasn't
  // modeled). Reported as a coverage ratio so the equity dimension can't
  // silently degrade to ~0 while the headline still reads ~100%.
  unscoredEquity: number;
}

function adjudicate(fx: Fixture, claims: Claim[]): AdjudResult {
  const out: Violation[] = [];
  let unscoredEquity = 0;
  let scoredEquity = 0;
  const add = (c: Claim, detail: string) =>
    out.push({ fixtureId: fx.id, street: c.street, category: c.category, detail, claim: c.text });

  for (const c of claims) {
    const lab = labelForStreet(fx, c.street);
    if (!lab) continue;

    // Each board-constraint claim is checked against the label of the street
    // it was attributed to — NOT pooled across the whole hand. A boat/flush/
    // straight named while discussing an early street must be makeable from
    // THAT street's board; a later runout card that enables it does not excuse
    // the claim (this is the exact early-street-hallucination class the harness
    // exists to catch). "overall"/"preflop" claims fall back to the final board.

    // 1. Boat/quads claim on a board that street doesn't pair.
    // Trust the judge's structured handCategoryNamed (set only when the prose
    // asserts the hand EXISTS) — do NOT raw-text-scan c.text, which fires on
    // negations ("no full house yet") and hypotheticals ("could boat up").
    const named = (c.handCategoryNamed ?? "").toLowerCase();
    const mentionsBoat = _boatWords.some((w) => named.includes(w));
    if (mentionsBoat && !lab.boatOrQuadsPossible) {
      add(c, `claims a full house/quads but the ${lab.street} board (${lab.board.join(" ")}) is unpaired — boat/quads impossible`);
      continue;
    }

    // 2. Made-flush claim when that street's board can't make one.
    const mentionsFlush = named.includes("flush") || (c.category === "flush" && (c.handCategoryNamed != null));
    if (mentionsFlush && !named.includes("straight flush") && !lab.flushPossible) {
      add(c, `claims a flush but the ${lab.street} board (${lab.board.join(" ")}) has no 3+ of a suit — flush impossible`);
      continue;
    }

    // 3. A specifically-named straight that street's board cannot complete.
    if (c.straightRanks) {
      const norm = normalizeWindow(c.straightRanks);
      const allowedHere = new Set(lab.allowedStraightWindows.map(normalizeWindow));
      if (norm && !allowedHere.has(norm)) {
        add(c, `names straight ${c.straightRanks} which the ${lab.street} board cannot make (allowed: ${lab.allowedStraightWindows.join(", ") || "none"})`);
        continue;
      }
    }

    // 4. A stated HERO-EQUITY % that contradicts the injected equity FACT.
    // Strict: only an `equity` claim about hero, matched to the SAME street's
    // label. Pot-odds claims are a different quantity (the required price, not
    // hero's equity) and are NOT checked here (verdict scorer, PR3). When the
    // street has no equity label, the claim is counted as unscored, not passed.
    if (c.percent != null && c.category === "equity" && c.subject === "hero") {
      const exact = fx.labels.perStreet.find((s) => s.street === c.street);
      if (exact?.heroEquity != null) {
        scoredEquity++;
        const factPct = Math.round(exact.heroEquity * 100);
        if (Math.abs(c.percent - factPct) > 12) {
          add(c, `states hero equity ${c.percent}% but the ${c.street} equity FACT is ~${factPct}% (>12pt)`);
          continue;
        }
      } else {
        unscoredEquity++;
      }
    }
  }
  return { violations: out, scoredEquity, unscoredEquity };
}

const _rankOrder = "23456789TJQKA";
function normalizeWindow(s: string): string | null {
  const ranks = s.toUpperCase().split(/[-\s,]+/).map((r) => r === "10" ? "T" : r).filter((r) => _rankOrder.includes(r));
  if (ranks.length !== 5) return null;
  const idxs = ranks.map((r) => _rankOrder.indexOf(r)).sort((a, b) => a - b);
  return idxs.join("-");
}

// ── Verdict self-consistency (PR 3, part 1) ──────────────────────────────────
// The coach's own output must tell ONE story (the SYSTEM_PROMPT's consistency
// rules): leakDetected ⟺ keyMistake present ⟺ at least one street marked
// non-GTO. This is the self-contradiction class the trust pack exists to catch
// ("AA folds to a nit" — keyMistake names a fold while every street reads fine).
// Checked directly from the structured output — no judge, no ground truth.

const _STREETS = ["preflop", "flop", "turn", "river"] as const;

interface VerdictIssue {
  rule: string;
  detail: string;
}

// A "real" keyMistake names an error; a benign null-stand-in ("none", "no
// significant mistakes", "well played") is the model failing to use null but is
// NOT a strategic contradiction — don't treat it as a present mistake.
const _benignMistake = /^\s*(null|none|n\/a|no\b.*\b(mistake|leak|error|issue)|well[- ]played|no significant|nothing\b)/i;

function checkVerdictConsistency(
  analysis: Record<string, unknown>,
): VerdictIssue[] {
  const verdict = analysis.verdict as string | undefined;
  const km = analysis.keyMistake;
  const kmText = typeof km === "string" ? km.trim() : "";
  const hasMistake = kmText.length > 0 && !_benignMistake.test(kmText);
  const isLeak = verdict === "leakDetected";

  let nonGto = 0;
  for (const s of _STREETS) {
    const st = analysis[s] as Record<string, unknown> | null | undefined;
    if (st && st.wasGto === false) nonGto++;
  }
  const N = nonGto > 0;

  // The three leak signals must agree: a hand is either consistently CLEAN
  // (no leak verdict, no real keyMistake, all streets GTO) or consistently a
  // LEAK (leakDetected + keyMistake + a non-GTO street). Any disagreement is
  // the self-contradiction class the trust pack exists to catch.
  if (isLeak === hasMistake && hasMistake === N) return [];

  const kmSnip = kmText
    ? `"${kmText.slice(0, 90)}${kmText.length > 90 ? "…" : ""}"`
    : "null";
  return [{
    rule: "verdict-signals-disagree",
    detail:
      `verdict=${verdict ?? "?"}, keyMistake=${kmSnip}, non-GTO streets=${nonGto} — ` +
      `leak signals must agree (all-clean or all-leak)`,
  }];
}

// ── Forced-decision agreement (PR 3, part 2) ─────────────────────────────────
// On a pot-odds-DECISIVE spot the correct action is mathematically forced (the
// baked forcedDecision). Check whether the model's wasGto for the decision
// street agrees with whether hero's actual action was the forced-correct one.
// Only spots with a baked forcedDecision contribute; everything else is silent.

interface ForcedVerdictResult {
  scored: boolean; // could we compare (model gave a wasGto for the street)?
  agreed: boolean;
  detail: string;
}

function checkForcedVerdict(
  fx: Fixture,
  analysis: Record<string, unknown>,
): ForcedVerdictResult | null {
  const fd = fx.labels.forcedDecision;
  if (!fd) return null;
  const st = analysis[fd.street] as Record<string, unknown> | null | undefined;
  const base =
    `${fd.street}: hero ${fd.heroCalled ? "called" : "folded"}, forced=${fd.forcedAction} ` +
    `(eq ${fd.heroEquityPct}% vs req ${fd.requiredPct}%), heroActionCorrect=${fd.heroActionCorrect}`;
  if (!st || typeof st.wasGto !== "boolean") {
    return { scored: false, agreed: false, detail: `${base}; model gave no wasGto for ${fd.street}` };
  }
  const agreed = st.wasGto === fd.heroActionCorrect;
  return { scored: true, agreed, detail: `${base}; model wasGto=${st.wasGto} → ${agreed ? "AGREE" : "DISAGREE"}` };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const fixturesDir = Deno.args[0] ?? "tool/eval/fixtures";
  const outDir = Deno.args[1] ?? "tool/eval/reports";
  await Deno.mkdir(outDir, { recursive: true });

  const fixtures: Fixture[] = [];
  for await (const entry of Deno.readDir(fixturesDir)) {
    if (entry.isFile && entry.name.endsWith(".json")) {
      fixtures.push(JSON.parse(await Deno.readTextFile(`${fixturesDir}/${entry.name}`)));
    }
  }
  fixtures.sort((a, b) => a.id.localeCompare(b.id));
  console.log(`Scoring ${fixtures.length} fixtures against the real ${COACH_MODEL} prompt...\n`);

  interface SpotResult {
    id: string;
    bucket: string;
    // The full extracted claims, persisted to report.json so a run can be
    // spot-audited (did the judge extract real claims? did the adjudicator miss
    // one?) — the spec's "keep the judge honest" check. The markdown report
    // shows only counts.
    claims: Claim[];
    violations: Violation[];
    scoredEquity: number;
    unscoredEquity: number;
    // Verdict self-consistency issues in the coach's own output (PR 3 part 1) —
    // a separate dimension from card-logic, scored from the structured fields.
    verdictIssues: VerdictIssue[];
    // Forced-decision agreement (PR 3 part 2) — null unless this spot has a
    // pot-odds-decisive forcedDecision label.
    forcedVerdict: ForcedVerdictResult | null;
    // A harness/API failure (refusal, 5xx, timeout) — NOT a card-logic error.
    // Excluded from the accuracy denominator so an API blip can't move the
    // published number; reported separately.
    errored: boolean;
    errorDetail?: string;
  }

  const errResult = (fx: Fixture, detail: string): SpotResult => ({
    id: fx.id, bucket: fx.bucket, claims: [], violations: [],
    scoredEquity: 0, unscoredEquity: 0, verdictIssues: [], forcedVerdict: null, errored: true, errorDetail: detail,
  });

  let done = 0;
  const raw = await mapPool(
    fixtures,
    CONCURRENCY,
    async (fx): Promise<SpotResult> => {
      try {
        const analysis = await runCoaching(fx);
        const claims = await extractClaims(fx, analysis);
        const { violations, scoredEquity, unscoredEquity } = adjudicate(fx, claims);
        const verdictIssues = checkVerdictConsistency(analysis);
        const forcedVerdict = checkForcedVerdict(fx, analysis);
        const mark = violations.length === 0 && verdictIssues.length === 0 ? "OK " : "ERR";
        const fv = forcedVerdict ? `, forced:${forcedVerdict.scored ? (forcedVerdict.agreed ? "agree" : "DISAGREE") : "unscored"}` : "";
        console.log(`[${++done}/${fixtures.length}] ${mark} ${fx.id}  (${claims.length} claims, ${violations.length} card-logic, ${verdictIssues.length} verdict${fv})`);
        for (const v of violations) console.log(`      - card-logic [${v.street}/${v.category}] ${v.detail}`);
        for (const v of verdictIssues) console.log(`      - verdict [${v.rule}] ${v.detail}`);
        if (forcedVerdict && forcedVerdict.scored && !forcedVerdict.agreed) console.log(`      - forced-verdict DISAGREE: ${forcedVerdict.detail}`);
        return { id: fx.id, bucket: fx.bucket, claims, violations, scoredEquity, unscoredEquity, verdictIssues, forcedVerdict, errored: false };
      } catch (e) {
        const detail = e instanceof Error ? e.message : String(e);
        console.error(`[${++done}/${fixtures.length}] ERRORED ${fx.id}: ${detail} (excluded from accuracy)`);
        return errResult(fx, detail);
      }
    },
  );
  // A `undefined` slot means mapPool's worker caught an unexpected throw — treat
  // it as an errored spot so the run still produces a complete report.
  const results: SpotResult[] = raw.map(
    (r, i) => r ?? errResult(fixtures[i], "worker crashed unexpectedly"),
  );

  // Accuracy is over SCORED spots only — harness errors are excluded, never
  // conflated with card-logic failures.
  const scored = results.filter((r) => !r.errored);
  const erroredCount = results.length - scored.length;
  const clean = scored.filter((r) => r.violations.length === 0).length;
  const accuracy = scored.length ? (100 * clean / scored.length) : 0;
  const scoredEquityTotal = results.reduce((n, r) => n + r.scoredEquity, 0);
  const unscoredEquityTotal = results.reduce((n, r) => n + r.unscoredEquity, 0);
  const equityClaimsTotal = scoredEquityTotal + unscoredEquityTotal;
  const equityCoveragePct = equityClaimsTotal
    ? Number((100 * scoredEquityTotal / equityClaimsTotal).toFixed(1))
    : 0;
  const byCategory: Record<string, number> = {};
  for (const r of results) {
    for (const v of r.violations) byCategory[v.category] = (byCategory[v.category] ?? 0) + 1;
  }

  // Verdict self-consistency is a separate dimension (over scored spots).
  const verdictConsistent = scored.filter((r) => r.verdictIssues.length === 0).length;
  const verdictConsistencyPct = scored.length
    ? Number((100 * verdictConsistent / scored.length).toFixed(1))
    : 0;
  const byVerdictRule: Record<string, number> = {};
  for (const r of results) {
    for (const v of r.verdictIssues) byVerdictRule[v.rule] = (byVerdictRule[v.rule] ?? 0) + 1;
  }

  // Forced-decision verdict agreement — only the pot-odds-decisive subset.
  const fvScored = scored.filter((r) => r.forcedVerdict?.scored);
  const fvAgreed = fvScored.filter((r) => r.forcedVerdict!.agreed).length;
  const fvUnscored = scored.filter((r) => r.forcedVerdict && !r.forcedVerdict.scored).length;
  const forcedVerdictAgreementPct = fvScored.length
    ? Number((100 * fvAgreed / fvScored.length).toFixed(1))
    : 0;

  const report = {
    generatedFor: COACH_MODEL,
    total: results.length,
    scored: scored.length,
    errored: erroredCount,
    clean,
    cardLogicAccuracyPct: Number(accuracy.toFixed(1)),
    equityClaimsScored: scoredEquityTotal,
    equityClaimsUnscored: unscoredEquityTotal,
    equityCoveragePct,
    verdictConsistent,
    verdictConsistencyPct,
    forcedVerdictScored: fvScored.length,
    forcedVerdictAgreed: fvAgreed,
    forcedVerdictUnscored: fvUnscored,
    forcedVerdictAgreementPct,
    byCategory,
    byVerdictRule,
    results,
  };
  await Deno.writeTextFile(`${outDir}/report.json`, JSON.stringify(report, null, 2));
  await Deno.writeTextFile(`${outDir}/report.md`, renderMarkdown(report));

  console.log(`\nCard-logic accuracy:  ${accuracy.toFixed(1)}%  (${clean}/${scored.length} scored spots clean${erroredCount ? `; ${erroredCount} errored, excluded` : ""})`);
  console.log(`Verdict consistency:  ${verdictConsistencyPct}%  (${verdictConsistent}/${scored.length} spots with self-consistent verdicts)`);
  console.log(`Forced-verdict agree: ${forcedVerdictAgreementPct}%  (${fvAgreed}/${fvScored.length} decisive spots${fvUnscored ? `; ${fvUnscored} unscored` : ""})`);
  console.log(`Equity check coverage: ${equityCoveragePct}%  (${scoredEquityTotal} scored / ${equityClaimsTotal} hero-equity claims)`);
  console.log(`Report: ${outDir}/report.md`);
}

// deno-lint-ignore no-explicit-any
function renderMarkdown(r: any): string {
  const lines = [
    `# Eval harness — report`,
    ``,
    `- Model under test: \`${r.generatedFor}\``,
    `- **Card-logic accuracy: ${r.cardLogicAccuracyPct}%** (${r.clean}/${r.scored} scored spots with zero card-logic errors)`,
    `- **Verdict consistency: ${r.verdictConsistencyPct}%** (${r.verdictConsistent}/${r.scored} spots with self-consistent verdicts)`,
    `- **Forced-verdict agreement: ${r.forcedVerdictAgreementPct}%** (${r.forcedVerdictAgreed}/${r.forcedVerdictScored} pot-odds-decisive spots${r.forcedVerdictUnscored ? `; ${r.forcedVerdictUnscored} unscored` : ""})`,
    `- Errored (harness/API, excluded): ${r.errored}`,
    `- Equity-check coverage: ${r.equityCoveragePct}% (${r.equityClaimsScored} scored / ${r.equityClaimsScored + r.equityClaimsUnscored} hero-equity claims)`,
    ``,
    `## Card-logic violations by category`,
    ``,
    Object.keys(r.byCategory).length
      ? Object.entries(r.byCategory).map(([k, v]) => `- ${k}: ${v}`).join("\n")
      : `_None._`,
    ``,
    `## Verdict-consistency issues by rule`,
    ``,
    Object.keys(r.byVerdictRule).length
      ? Object.entries(r.byVerdictRule).map(([k, v]) => `- ${k}: ${v}`).join("\n")
      : `_None._`,
    ``,
    `## Per-spot`,
    ``,
    `| Spot | Bucket | Claims | Card-logic | Verdict | Status |`,
    `|---|---|---|---|---|---|`,
    // deno-lint-ignore no-explicit-any
    ...r.results.map((s: any) => `| ${s.id} | ${s.bucket} | ${s.claims.length} | ${s.violations.length} | ${s.verdictIssues.length} | ${s.errored ? "errored" : "scored"} |`),
  ];
  return lines.join("\n") + "\n";
}

if (import.meta.main) await main();
