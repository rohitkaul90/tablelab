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
//     tool/eval/score.ts [fixturesDir] [outDir] [--limit N] [--baseline path] [--rerun-errored]
//
//   --limit N         score a deterministic, bucket-spanning sample of N fixtures
//                     (cheap iteration); writes report.sample.* and never clobbers
//                     the committed full baseline. Omit for the full gate run.
//   --baseline P      diff against report P (default: <outDir>/report.json, the
//                     prior run). A FULL run that regresses any dimension exits 1.
//   --rerun-errored   re-score ONLY the spots the prior <outDir>/report.json
//                     marked errored (recover a partial run after connection
//                     blips), then merge them back in. No diff, no gating; safe
//                     to repeat until 0 errored.
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
    // EQR (DCE Tier A): hero's realized equity per street name. A hero-equity
    // claim is accepted if it matches the RAW equity OR this realized figure.
    realizedEquityByStreet?: Record<string, number>;
    // SPR (DCE Tier A): effective stack ÷ pot per street name. Heuristic
    // context, not card-logic graded — baked for the report + future use. The
    // SPR stack-off % is phrased like a pot-odds price, which the card-logic
    // adjudicator already leaves unchecked (it only grades hero-equity claims).
    sprByStreet?: Record<string, number>;
  };
  // User satisfaction signal for user-flagged spots (absent on Pluribus spots).
  // rating: -1 thumbs-down (dissatisfied), +1 thumbs-up (satisfied control).
  userSignal?: { rating: number; ratedAt?: string | null } | null;
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

// maxRetries (with the SDK's exponential backoff) so a transient connection
// blip retries instead of erroring the spot out — fewer errored spots per run.
const client = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")!, maxRetries: 4 });

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
        const rawPct = Math.round(exact.heroEquity * 100);
        // EQR: the prompt injects BOTH raw equity and a realized-equity
        // HEURISTIC, so a hero-equity claim is correct if it matches EITHER
        // (within 12pt). Only flag when it matches neither.
        // NOTE: realized equity has NO independent oracle — it comes from the
        // same decision_context.dart heuristic used in prod, so this only
        // confirms the model is CONSISTENT with the grounded number; it does NOT
        // validate the heuristic itself. Raw equity (Monte-Carlo sim) is the real
        // card-logic oracle; realized is accepted as consistent context.
        const realized = fx.labels.realizedEquityByStreet?.[c.street];
        const realizedPct = realized != null ? Math.round(realized * 100) : null;
        const offRaw = Math.abs(c.percent - rawPct);
        const offRealized = realizedPct != null ? Math.abs(c.percent - realizedPct) : Infinity;
        if (offRaw > 12 && offRealized > 12) {
          const realizedNote = realizedPct != null ? ` (realized ~${realizedPct}%)` : "";
          add(c, `states hero equity ${c.percent}% but the ${c.street} equity FACT is ~${rawPct}%${realizedNote} — >12pt from both`);
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
// Word boundaries matter: without them "Nonetheless…", "Nullified…", and
// "No, calling was an error" prefix-match and a REAL mistake gets suppressed.
// "no <mistake-word>" is matched tightly (a qualifier then a mistake noun) so
// "no calling was an error" / "No, …" do NOT count as benign.
const _benignMistake =
  /^\s*(null\b|none\b|n\/?a\b|no\s+(significant\s+|major\s+|real\s+|notable\s+|obvious\s+|clear\s+|other\s+)?(mistakes?|leaks?|errors?|issues?|blunders?)\b|well[-\s]?played\b|nothing\b)/i;

function checkVerdictConsistency(
  analysis: Record<string, unknown>,
): VerdictIssue[] {
  const verdict = analysis.verdict as string | undefined;
  const km = analysis.keyMistake;
  const kmText = typeof km === "string" ? km.trim() : "";
  const hasMistake = kmText.length > 0 && !_benignMistake.test(kmText);
  const isLeak = verdict === "leakDetected";
  const isHighEv = verdict === "highEV";

  let nonGto = 0;
  for (const s of _STREETS) {
    const st = analysis[s] as Record<string, unknown> | null | undefined;
    if (st && st.wasGto === false) nonGto++;
  }
  const N = nonGto > 0;
  const kmSnip = kmText
    ? `"${kmText.slice(0, 90)}${kmText.length > 90 ? "…" : ""}"`
    : "null";

  // GRADED consistency. The verdict scale is 3-level (highEV / neutral /
  // leakDetected) by deliberate product choice, so a `neutral` hand MAY carry a
  // minor keyMistake and/or one non-GTO street — that is coherent coaching, not
  // a contradiction. Only these are genuine self-contradictions:
  //   (1) leakDetected with no real keyMistake — a leak must name its mistake;
  //   (2) leakDetected but every street marked GTO — a leak must flag a street;
  //   (3) a real keyMistake but every street GTO — the named mistake has no street;
  //   (4) highEV ("great") with a real keyMistake — a great hand names no mistake.
  // Previously this demanded ALL THREE signals agree, which mis-flagged ~77
  // legitimate "neutral + minor note" hands (73.7% -> 97.8% after this fix; see
  // the 2026-06 eval-gate triage). keyMistake⇒street stays aggregate-only — it
  // does NOT verify the SAME street is named (avoids NLP false positives).
  const issues: VerdictIssue[] = [];
  if (isLeak && !hasMistake) {
    issues.push({ rule: "leak-without-mistake", detail: `verdict=leakDetected but keyMistake is empty/benign (${kmSnip})` });
  }
  if (isLeak && !N) {
    issues.push({ rule: "leak-without-nongto-street", detail: `verdict=leakDetected but every street is marked GTO — the leak flags no street (keyMistake=${kmSnip})` });
  }
  if (hasMistake && !N) {
    issues.push({ rule: "mistake-without-nongto-street", detail: `keyMistake names an error but every street is marked GTO: ${kmSnip}` });
  }
  if (isHighEv && hasMistake) {
    issues.push({ rule: "highev-with-mistake", detail: `verdict=highEV (great hand) but a keyMistake is named: ${kmSnip}` });
  }
  return issues;
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
  // Tolerance band: within ~Monte-Carlo noise of the price it isn't "forced".
  // A <2pt edge (e.g. eq 29% vs req 30%) is a coin-flip-close decision, not a
  // mathematically-forced one — don't score it. Drops 3 near-tie spots; the
  // remaining decisive spots agree 100% (eval-gate triage 2026-06).
  if (Math.abs(fd.heroEquityPct - fd.requiredPct) < 2) return null;
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

// ── Frequency agreement (DCE Q1) ─────────────────────────────────────────────
// For spots where the prompt was grounded with a `[HEURISTIC — GTO frequency]`
// line, check the coaching doesn't CONTRADICT the injected solver mix; for a
// multiway-tendency spot (no per-hand frequency exists), flag any specific
// action % the coaching invents. A SEPARATE judge call (only on spots with such
// a FACT, ~the synthetic gto-frequency bucket) so it never perturbs the
// card-logic judge and can't confound the gated dimensions.

// Coarse action buckets — the FACT's small/medium/big bets all map to "bet".
const _coarseAction: Record<string, string> = {
  "check": "check", "call": "call", "fold": "fold", "raise": "raise",
  "all-in": "allin", "bet": "bet", "small bet": "bet", "medium bet": "bet",
  "big bet": "bet",
};

interface ParsedFreqFact {
  // One coarse-action→frequency mix PER STREET segment the FACT renders
  // (flop, turn, …). Kept per-street because a multi-street FACT carries a
  // separate decision per street — summing the same action across streets is
  // a different decision and would fabricate >100% "frequencies" (a real bug
  // the turn-coverage spots exposed). For a flop-only FACT this is a 1-element
  // list, so single-street scoring is byte-identical to before.
  gtoByStreet: Record<string, number>[] | null;
  multiway: boolean;
}

// Parse the injected GTO-frequency FACT's mix into per-street coarse-action
// frequencies. Within a street the small/medium/big bet labels DO sum into one
// "bet" total (they are the same decision); across streets they do NOT.
export function parseFreqFact(equityFacts: string[]): ParsedFreqFact {
  const gtoLine = (equityFacts ?? []).find((f) => f.includes("[HEURISTIC — GTO frequency"));
  const multiway = (equityFacts ?? []).some((f) => f.includes("[HEURISTIC — multiway tendency"));
  if (!gtoLine) return { gtoByStreet: null, multiway };
  // Split into per-street segments: "flop (…): <freqs>; turn (…): <freqs>." —
  // each freq list runs to the next ";" (street boundary) or "." (FACT end).
  const segRe = /(?:flop|turn|river) \([^)]*\):\s*([^;.\]]*)/g;
  // Longer labels first so "small bet" matches before "bet".
  const re = /(all-in|small bet|medium bet|big bet|bet|check|call|fold|raise)\s*~(\d+)%/g;
  const byStreet: Record<string, number>[] = [];
  let seg: RegExpExecArray | null;
  while ((seg = segRe.exec(gtoLine)) !== null) {
    const freqs: Record<string, number> = {};
    let m: RegExpExecArray | null;
    re.lastIndex = 0;
    while ((m = re.exec(seg[1])) !== null) {
      const coarse = _coarseAction[m[1]];
      if (coarse) freqs[coarse] = (freqs[coarse] ?? 0) + Number(m[2]) / 100;
    }
    if (Object.keys(freqs).length) byStreet.push(freqs);
  }
  return { gtoByStreet: byStreet.length ? byStreet : null, multiway };
}

export interface FreqClaim {
  action: string; // check | bet | call | fold | raise | allin
  percent?: number | null; // explicit % the coaching stated, if any
  qualifier?: string | null; // always | usually | often | sometimes | rarely | never
}

const FREQ_EXTRACT_TOOL: any = {
  name: "report_frequency_claims",
  description: "List every claim the coaching prose makes about HOW OFTEN to take an action.",
  input_schema: {
    type: "object",
    properties: {
      claims: {
        type: "array",
        items: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["check", "bet", "call", "fold", "raise", "allin"] },
            percent: { type: ["number", "null"], description: "An explicit percentage the text states for this action, else null" },
            qualifier: { type: ["string", "null"], enum: ["always", "usually", "often", "sometimes", "rarely", "never", null], description: "A frequency word the text uses for this action, else null" },
          },
          required: ["action"],
        },
      },
    },
    required: ["claims"],
  },
};

const FREQ_JUDGE_SYSTEM =
  `You extract claims about ACTION FREQUENCY from poker coaching prose, for an automated consistency check. ` +
  `Surface only statements about how OFTEN to take an action — an explicit percentage ("bet ~60%", "check most of the time") ` +
  `or a frequency word (always/usually/often/sometimes/rarely/never). Map each to {action, percent, qualifier}. ` +
  `Do NOT judge whether the advice is good; do not invent claims the text does not make. Empty list if it states no frequencies.`;

async function extractFreqClaims(analysis: Record<string, unknown>): Promise<FreqClaim[]> {
  const text = JSON.stringify(analysis);
  const resp = await client.messages.create({
    model: JUDGE_MODEL,
    max_tokens: 1024,
    system: FREQ_JUDGE_SYSTEM,
    tools: [FREQ_EXTRACT_TOOL],
    tool_choice: { type: "tool", name: "report_frequency_claims" },
    messages: [{ role: "user", content: `Coaching output:\n${text}` }],
  });
  const input = toolInput(resp);
  return ((input?.claims as FreqClaim[]) ?? []);
}

interface FreqAgreement {
  scored: boolean; // only spots with a GTO/multiway FACT are scored
  violations: string[];
}

// ±15pt: the FACT is coarse (hand-class aggregate, texture-class) so only a
// gross contradiction counts. Qualitative claims map to loose bands.
export function checkFrequencyAgreement(parsed: ParsedFreqFact, claims: FreqClaim[]): FreqAgreement {
  const violations: string[] = [];
  if (parsed.gtoByStreet) {
    for (const c of claims) {
      // The streets whose mix lists this action. The coaching claim carries no
      // street label, so it is consistent if it agrees with ANY street that
      // takes the action — a violation requires contradicting them ALL (the
      // FACT is a coarse soft prior; only gross, unambiguous conflicts count).
      const fs = parsed.gtoByStreet
        .map((s) => s[c.action])
        .filter((f): f is number => f != null);
      if (fs.length === 0) continue; // action no street lists (e.g. raise) — skip
      const pcts = fs.map((f) => `~${Math.round(f * 100)}%`).join(" / ");
      if (c.percent != null) {
        if (fs.every((f) => Math.abs(c.percent! / 100 - f) > 0.15)) {
          violations.push(`coaching states ${c.action} ~${c.percent}% but the GTO FACT is ${pcts}`);
        }
      } else if (c.qualifier === "never" && fs.every((f) => f >= 0.30)) {
        violations.push(`coaching says ${c.action} is never right, but GTO takes it ${pcts}`);
      } else if (c.qualifier === "always" && fs.every((f) => f <= 0.70)) {
        violations.push(`coaching says ${c.action} is always right, but GTO takes it only ${pcts}`);
      }
    }
    return { scored: true, violations };
  }
  if (parsed.multiway) {
    for (const c of claims) {
      if (c.percent != null) {
        violations.push(`states a specific multiway frequency (${c.action} ~${c.percent}%) — no solver model exists multiway, this is false precision`);
      }
    }
    return { scored: true, violations };
  }
  return { scored: false, violations: [] };
}

// ── CLI args ────────────────────────────────────────────────────────────────

interface CliArgs {
  fixturesDir: string;
  outDir: string;
  limit: number | null; // score a subsample of this many fixtures (iteration)
  baseline: string | null; // report.json to diff against (default: outDir/report.json)
  rerunErrored: boolean; // re-score only the prior report's errored spots, then merge
}

function parseArgs(argv: string[]): CliArgs {
  const positionals: string[] = [];
  let limit: number | null = null;
  let baseline: string | null = null;
  let rerunErrored = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--limit" || a === "-n") limit = Number(argv[++i]);
    else if (a.startsWith("--limit=")) limit = Number(a.slice("--limit=".length));
    else if (a === "--baseline") baseline = argv[++i];
    else if (a.startsWith("--baseline=")) baseline = a.slice("--baseline=".length);
    else if (a === "--rerun-errored") rerunErrored = true;
    else if (a.startsWith("-")) throw new Error(`Unknown flag: ${a}`);
    else positionals.push(a);
  }
  if (limit != null && (!Number.isInteger(limit) || limit <= 0)) {
    throw new Error(`--limit must be a positive integer`);
  }
  return {
    fixturesDir: positionals[0] ?? "tool/eval/fixtures",
    outDir: positionals[1] ?? "tool/eval/reports",
    limit,
    baseline,
    rerunErrored,
  };
}

/// Deterministic, bucket-spanning subsample: even stride across the (id-sorted)
/// list so `--limit 30` touches every texture bucket, not the first 30 ids (one
/// bucket). Same input + N → same sample, so iteration diffs are stable.
function sampleEvenly<T>(arr: T[], n: number): T[] {
  if (n >= arr.length) return arr;
  const out: T[] = [];
  for (let i = 0; i < n; i++) out.push(arr[Math.floor((i * arr.length) / n)]);
  return out;
}

// ── Regression diff vs a previous run ────────────────────────────────────────
// Compare this run to a prior report.json per spot id present in BOTH. A spot
// that PASSED a dimension before and is FLAGGED now is a regression (vice versa
// = improvement). Lets a prompt/model change be gated. NB temperature-0 is not
// bitwise-deterministic (esp. verdict consistency) — a lone single-spot flip
// can be noise, a cluster is real. Only a FULL run gates (exits non-zero).

type Dim = "card" | "verdict" | "forced" | "freq";
const _dimLabel: Record<Dim, string> = {
  card: "card-logic",
  verdict: "verdict-consistency",
  forced: "forced-verdict",
  freq: "frequency-agreement",
};
const _DIMS: Dim[] = ["card", "verdict", "forced", "freq"];

// true = passed the dimension, false = flagged, null = N/A (errored / unscored).
// Reads the fields shared by a live SpotResult and a parsed prior report row.
// deno-lint-ignore no-explicit-any
function spotDims(r: any): Record<Dim, boolean | null> {
  if (!r || r.errored) return { card: null, verdict: null, forced: null, freq: null };
  return {
    card: (r.violations?.length ?? 0) === 0,
    verdict: (r.verdictIssues?.length ?? 0) === 0,
    forced: r.forcedVerdict?.scored ? !!r.forcedVerdict.agreed : null,
    freq: r.freqAgreement?.scored ? (r.freqAgreement.violations?.length ?? 0) === 0 : null,
  };
}

interface RunDiff {
  baselinePath: string;
  comparedSpots: number;
  headline: Record<Dim, { prev: number | null; curr: number | null }>;
  regressions: Record<Dim, string[]>;
  improvements: Record<Dim, string[]>;
  hasRegression: boolean;
}

// deno-lint-ignore no-explicit-any
function computeDiff(prior: any, curr: any, baselinePath: string): RunDiff {
  // deno-lint-ignore no-explicit-any
  const priorById = new Map<string, any>();
  // deno-lint-ignore no-explicit-any
  for (const r of ((prior.results ?? []) as any[])) priorById.set(r.id, r);
  const dims = _DIMS;
  const regressions: Record<Dim, string[]> = { card: [], verdict: [], forced: [], freq: [] };
  const improvements: Record<Dim, string[]> = { card: [], verdict: [], forced: [], freq: [] };
  let comparedSpots = 0;
  for (const r of (curr.results ?? [])) {
    const p = priorById.get(r.id);
    if (!p) continue;
    comparedSpots++;
    const pd = spotDims(p);
    const cd = spotDims(r);
    for (const d of dims) {
      if (pd[d] === true && cd[d] === false) regressions[d].push(r.id);
      else if (pd[d] === false && cd[d] === true) improvements[d].push(r.id);
    }
  }
  return {
    baselinePath,
    comparedSpots,
    headline: {
      card: { prev: prior.cardLogicAccuracyPct ?? null, curr: curr.cardLogicAccuracyPct ?? null },
      verdict: { prev: prior.verdictConsistencyPct ?? null, curr: curr.verdictConsistencyPct ?? null },
      forced: { prev: prior.forcedVerdictAgreementPct ?? null, curr: curr.forcedVerdictAgreementPct ?? null },
      freq: { prev: prior.frequencyAgreementPct ?? null, curr: curr.frequencyAgreementPct ?? null },
    },
    regressions,
    improvements,
    hasRegression: dims.some((d) => regressions[d].length > 0),
  };
}

function renderDiffMarkdown(d: RunDiff | null): string[] {
  if (!d) return [];
  const dims = _DIMS;
  const lines = [
    `## Diff vs previous run`,
    ``,
    `Baseline: \`${d.baselinePath}\` · compared ${d.comparedSpots} shared spots.`,
    ``,
    `| Dimension | Prev | Curr | Regressed | Improved |`,
    `|---|---|---|---|---|`,
    ...dims.map((dim) => {
      const h = d.headline[dim];
      return `| ${_dimLabel[dim]} | ${h.prev ?? "—"}% | ${h.curr ?? "—"}% | ${d.regressions[dim].length} | ${d.improvements[dim].length} |`;
    }),
    ``,
  ];
  let any = false;
  for (const dim of dims) {
    if (d.regressions[dim].length) {
      any = true;
      lines.push(`**Regressed (${_dimLabel[dim]}):** ${d.regressions[dim].join(", ")}`, ``);
    }
  }
  if (!any) lines.push(`_No regressions vs baseline._`, ``);
  return lines;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const { fixturesDir, outDir, limit, baseline, rerunErrored } = parseArgs(Deno.args);
  await Deno.mkdir(outDir, { recursive: true });

  const fixtures: Fixture[] = [];
  for await (const entry of Deno.readDir(fixturesDir)) {
    if (entry.isFile && entry.name.endsWith(".json")) {
      fixtures.push(JSON.parse(await Deno.readTextFile(`${fixturesDir}/${entry.name}`)));
    }
  }
  fixtures.sort((a, b) => a.id.localeCompare(b.id));
  const allCount = fixtures.length;

  // Pick which fixtures to score this run:
  //  • --rerun-errored: only the spots the prior report.json marked errored —
  //    recover a partial run (connection blips) WITHOUT re-spending on the spots
  //    that already succeeded; merged back over the prior results below.
  //  • --limit N: a deterministic, bucket-spanning subsample (iteration aid).
  //  • default: the full set (the gate).
  let priorResults: SpotResult[] = [];
  let scoredFixtures: Fixture[];
  if (rerunErrored) {
    const prior = JSON.parse(await Deno.readTextFile(`${outDir}/report.json`));
    priorResults = (prior.results ?? []) as SpotResult[];
    const erroredIds = new Set(priorResults.filter((r) => r.errored).map((r) => r.id));
    scoredFixtures = fixtures.filter((f) => erroredIds.has(f.id));
    if (scoredFixtures.length === 0) {
      console.log("--rerun-errored: nothing errored in the prior report — nothing to do.");
      return;
    }
    console.log(`--rerun-errored: re-scoring ${scoredFixtures.length} errored spot(s) from ${outDir}/report.json...\n`);
  } else {
    scoredFixtures = limit != null ? sampleEvenly(fixtures, limit) : fixtures;
    if (limit != null) {
      console.log(`--limit ${limit}: scoring ${scoredFixtures.length} of ${allCount} fixtures (even stride across buckets).`);
    }
    console.log(`Scoring ${scoredFixtures.length} fixtures against the real ${COACH_MODEL} prompt...\n`);
  }

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
    // Frequency agreement (DCE Q1) — null unless the spot was grounded with a
    // GTO-frequency or multiway-tendency FACT.
    freqAgreement: FreqAgreement | null;
    // A harness/API failure (refusal, 5xx, timeout) — NOT a card-logic error.
    // Excluded from the accuracy denominator so an API blip can't move the
    // published number; reported separately.
    errored: boolean;
    errorDetail?: string;
    // User rating carried from the fixture (-1/+1) or null for Pluribus spots —
    // cross-tabbed against the objective dimensions below.
    userRating: number | null;
  }

  const errResult = (fx: Fixture, detail: string): SpotResult => ({
    id: fx.id, bucket: fx.bucket, claims: [], violations: [],
    scoredEquity: 0, unscoredEquity: 0, verdictIssues: [], forcedVerdict: null, freqAgreement: null,
    errored: true, errorDetail: detail,
    userRating: fx.userSignal?.rating ?? null,
  });

  let done = 0;
  const raw = await mapPool(
    scoredFixtures,
    CONCURRENCY,
    async (fx): Promise<SpotResult> => {
      try {
        const analysis = await runCoaching(fx);
        const claims = await extractClaims(fx, analysis);
        const { violations, scoredEquity, unscoredEquity } = adjudicate(fx, claims);
        const verdictIssues = checkVerdictConsistency(analysis);
        const forcedVerdict = checkForcedVerdict(fx, analysis);
        // Frequency agreement: only spend a judge call on spots whose prompt
        // carried a GTO-frequency / multiway-tendency FACT (else null/unscored).
        const parsedFreq = parseFreqFact(fx.equityFacts ?? []);
        let freqAgreement: FreqAgreement | null = null;
        if (parsedFreq.gtoByStreet || parsedFreq.multiway) {
          freqAgreement = checkFrequencyAgreement(parsedFreq, await extractFreqClaims(analysis));
        }
        const mark = violations.length === 0 && verdictIssues.length === 0 ? "OK " : "ERR";
        const fv = forcedVerdict ? `, forced:${forcedVerdict.scored ? (forcedVerdict.agreed ? "agree" : "DISAGREE") : "unscored"}` : "";
        const fa = freqAgreement ? `, freq:${freqAgreement.violations.length === 0 ? "agree" : "DISAGREE"}` : "";
        console.log(`[${++done}/${scoredFixtures.length}] ${mark} ${fx.id}  (${claims.length} claims, ${violations.length} card-logic, ${verdictIssues.length} verdict${fv}${fa})`);
        for (const v of violations) console.log(`      - card-logic [${v.street}/${v.category}] ${v.detail}`);
        for (const v of verdictIssues) console.log(`      - verdict [${v.rule}] ${v.detail}`);
        if (forcedVerdict && forcedVerdict.scored && !forcedVerdict.agreed) console.log(`      - forced-verdict DISAGREE: ${forcedVerdict.detail}`);
        for (const v of (freqAgreement?.violations ?? [])) console.log(`      - frequency ${v}`);
        return { id: fx.id, bucket: fx.bucket, claims, violations, scoredEquity, unscoredEquity, verdictIssues, forcedVerdict, freqAgreement, errored: false, userRating: fx.userSignal?.rating ?? null };
      } catch (e) {
        const detail = e instanceof Error ? e.message : String(e);
        console.error(`[${++done}/${scoredFixtures.length}] ERRORED ${fx.id}: ${detail} (excluded from accuracy)`);
        return errResult(fx, detail);
      }
    },
  );
  // A `undefined` slot means mapPool's worker caught an unexpected throw — treat
  // it as an errored spot so the run still produces a complete report.
  const scoredResults: SpotResult[] = raw.map(
    (r, i) => r ?? errResult(scoredFixtures[i], "worker crashed unexpectedly"),
  );
  // In --rerun-errored mode, overlay the freshly-scored spots onto the prior
  // full results (by id) so the report stays complete (all spots), not just the
  // re-runs. A spot that errors AGAIN simply stays errored.
  const results: SpotResult[] = rerunErrored
    ? (() => {
      const byId = new Map(priorResults.map((r) => [r.id, r]));
      for (const r of scoredResults) byId.set(r.id, r);
      return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
    })()
    : scoredResults;

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

  // Frequency agreement — only spots grounded with a GTO/multiway FACT. Coverage
  // (how many spots even carried a FACT) is reported separately as a diagnostic.
  const faScored = scored.filter((r) => r.freqAgreement?.scored);
  const faClean = faScored.filter((r) => r.freqAgreement!.violations.length === 0).length;
  const frequencyAgreementPct = faScored.length
    ? Number((100 * faClean / faScored.length).toFixed(1))
    : 0;
  const gtoFactSpots = scored.filter((r) =>
    r.freqAgreement?.scored && r.bucket === "gto-frequency").length;

  // ── User-flagged cross-tab ──────────────────────────────────────────────
  // The instrument the user asked for: of the hands a user was DISSATISFIED
  // with, which ones did an objective dimension explain, and which were
  // objectively clean but still disliked (the subjective gap the 3 scorers
  // can't see — the manual-review queue). Thumbs-up is the satisfied control:
  // an objective issue on a LIKED hand is a trust risk the user didn't catch.
  const objFlagged = (r: SpotResult): boolean =>
    r.violations.length > 0 ||
    r.verdictIssues.length > 0 ||
    (r.forcedVerdict?.scored === true && r.forcedVerdict.agreed === false);

  const disliked = scored.filter((r) => r.userRating === -1);
  const liked = scored.filter((r) => r.userRating === 1);
  const dislikedExplained = disliked.filter(objFlagged);
  const dislikedCleanIds = disliked.filter((r) => !objFlagged(r)).map((r) => r.id);
  const likedFlaggedIds = liked.filter(objFlagged).map((r) => r.id);
  const userFlagged = {
    disliked: disliked.length,
    dislikedExplained: dislikedExplained.length,
    dislikedCleanButDisliked: dislikedCleanIds.length,
    dislikedCleanIds, // ← the subjective-gap review queue
    liked: liked.length,
    likedWithObjectiveIssue: likedFlaggedIds.length,
    likedFlaggedIds,
  };

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
    frequencyScored: faScored.length,
    frequencyAgreed: faClean,
    frequencyAgreementPct,
    gtoFactSpots,
    byCategory,
    byVerdictRule,
    userFlagged,
    results,
  };
  // Diff vs a prior run. Default baseline = the existing report.json at outDir,
  // read BEFORE we overwrite it. A --limit run compares only the spots it
  // sampled and writes report.sample.* so it never clobbers a committed full
  // baseline.
  const baselinePath = baseline ?? `${outDir}/report.json`;
  let diff: RunDiff | null = null;
  // No diff in --rerun-errored mode: the "baseline" would be the partial report
  // we're patching, so a diff against it is meaningless.
  if (!rerunErrored) {
    try {
      const prior = JSON.parse(await Deno.readTextFile(baselinePath));
      diff = computeDiff(prior, report, baselinePath);
    } catch {
      // No prior baseline (first run) or unreadable — skip the diff silently.
    }
  }
  // deno-lint-ignore no-explicit-any
  (report as any).diff = diff;

  const stem = (limit != null && !rerunErrored) ? "report.sample" : "report";
  await Deno.writeTextFile(`${outDir}/${stem}.json`, JSON.stringify(report, null, 2));
  await Deno.writeTextFile(`${outDir}/${stem}.md`, renderMarkdown(report));

  console.log(`\nCard-logic accuracy:  ${accuracy.toFixed(1)}%  (${clean}/${scored.length} scored spots clean${erroredCount ? `; ${erroredCount} errored, excluded` : ""})`);
  console.log(`Verdict consistency:  ${verdictConsistencyPct}%  (${verdictConsistent}/${scored.length} spots with self-consistent verdicts)`);
  console.log(`Forced-verdict agree: ${forcedVerdictAgreementPct}%  (${fvAgreed}/${fvScored.length} decisive spots${fvUnscored ? `; ${fvUnscored} unscored` : ""})`);
  console.log(`Frequency agreement:  ${frequencyAgreementPct}%  (${faClean}/${faScored.length} GTO/multiway-FACT spots; ${gtoFactSpots} carried a GTO-frequency FACT)`);
  console.log(`Equity check coverage: ${equityCoveragePct}%  (${scoredEquityTotal} scored / ${equityClaimsTotal} hero-equity claims)`);
  if (disliked.length || liked.length) {
    console.log(`\nUser-flagged spots:`);
    if (disliked.length) {
      console.log(`  👎 disliked: ${disliked.length}  →  ${dislikedExplained.length} explained by an objective issue, ${dislikedCleanIds.length} clean-but-disliked (subjective gap)`);
      if (dislikedCleanIds.length) console.log(`     review queue: ${dislikedCleanIds.join(", ")}`);
    }
    if (liked.length) {
      console.log(`  👍 liked (control): ${liked.length}  →  ${likedFlaggedIds.length} with an objective issue the user didn't catch`);
      if (likedFlaggedIds.length) console.log(`     ${likedFlaggedIds.join(", ")}`);
    }
  }
  if (diff) {
    console.log(`\nDiff vs ${diff.baselinePath}  (${diff.comparedSpots} shared spots):`);
    for (const d of (["card", "verdict", "forced"] as const)) {
      const h = diff.headline[d];
      const reg = diff.regressions[d], imp = diff.improvements[d];
      console.log(`  ${_dimLabel[d]}: ${h.prev ?? "—"}% → ${h.curr ?? "—"}%  (${reg.length} regressed, ${imp.length} improved)`);
      if (reg.length) console.log(`     regressed: ${reg.join(", ")}`);
    }
  }
  console.log(`Report: ${outDir}/${stem}.md`);

  // Gate: a FULL run that regressed any dimension exits non-zero so it can block
  // a prompt/model change. A --limit sample is an iteration aid, not the gate
  // (temperature-0 isn't bitwise-deterministic — judge a lone flip as noise, a
  // cluster as real).
  if (diff?.hasRegression && limit == null) {
    console.error(`\n❌ Regression vs baseline (${diff.baselinePath}) — exit 1. See the "Diff vs previous run" section in ${stem}.md.`);
    Deno.exit(1);
  }
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
    `- **Frequency agreement: ${r.frequencyAgreementPct}%** (${r.frequencyAgreed}/${r.frequencyScored} GTO/multiway-FACT spots; ${r.gtoFactSpots} with a GTO-frequency FACT)`,
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
    ...userFlaggedSection(r.userFlagged),
    ...renderDiffMarkdown(r.diff),
    `## Per-spot`,
    ``,
    `| Spot | Bucket | User | Claims | Card-logic | Verdict | Status |`,
    `|---|---|---|---|---|---|---|`,
    // deno-lint-ignore no-explicit-any
    ...r.results.map((s: any) => `| ${s.id} | ${s.bucket} | ${s.userRating === -1 ? "👎" : s.userRating === 1 ? "👍" : ""} | ${s.claims.length} | ${s.violations.length} | ${s.verdictIssues.length} | ${s.errored ? "errored" : "scored"} |`),
  ];
  return lines.join("\n") + "\n";
}

// deno-lint-ignore no-explicit-any
function userFlaggedSection(u: any): string[] {
  if (!u || (u.disliked === 0 && u.liked === 0)) return [];
  const lines = [`## User-flagged spots`, ``];
  if (u.disliked) {
    lines.push(
      `**👎 Disliked: ${u.disliked}** — ${u.dislikedExplained} explained by an objective issue, ` +
        `**${u.dislikedCleanButDisliked} clean-but-disliked** (the subjective gap the 3 scorers can't see).`,
      ``,
    );
    if (u.dislikedCleanIds.length) {
      lines.push(`Review queue (objectively clean, still disliked):`, ``);
      lines.push(...u.dislikedCleanIds.map((id: string) => `- ${id}`), ``);
    }
  }
  if (u.liked) {
    lines.push(
      `**👍 Liked (satisfied control): ${u.liked}** — ${u.likedWithObjectiveIssue} carried an objective issue the user didn't catch.`,
      ``,
    );
    if (u.likedFlaggedIds.length) {
      lines.push(...u.likedFlaggedIds.map((id: string) => `- ${id}`), ``);
    }
  }
  return lines;
}

if (import.meta.main) await main();
