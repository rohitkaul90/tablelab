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
              description: "a stated equity/pot-odds percentage as a number 0-100, else null",
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
    model: JUDGE_MODEL,
    max_tokens: 4000,
    temperature: 0,
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

function adjudicate(fx: Fixture, claims: Claim[]): Violation[] {
  const out: Violation[] = [];
  const add = (c: Claim, detail: string) =>
    out.push({ fixtureId: fx.id, street: c.street, category: c.category, detail, claim: c.text });

  for (const c of claims) {
    const lab = labelForStreet(fx, c.street);
    if (!lab) continue;

    // 1. Boat/quads on an unpaired board (the documented failure class).
    const named = (c.handCategoryNamed ?? "").toLowerCase();
    const mentionsBoat = _boatWords.some((w) => named.includes(w) || c.text.toLowerCase().includes(w));
    if (mentionsBoat && !anyStreetAllows(fx, "boat")) {
      add(c, `claims a full house/quads but no board in this hand is paired (boat/quads impossible)`);
      continue;
    }

    // 2. Made flush when the board can't make one.
    const mentionsFlush = named.includes("flush") || (c.category === "flush" && (c.handCategoryNamed != null));
    if (mentionsFlush && !named.includes("straight flush") && !lab.flushPossible && !anyStreetAllows(fx, "flush")) {
      add(c, `claims a flush but no board reaches 3+ of a suit (flush impossible)`);
      continue;
    }

    // 3. A specifically-named straight that the board cannot complete.
    if (c.straightRanks) {
      const norm = normalizeWindow(c.straightRanks);
      const allowedAnywhere = new Set(fx.labels.perStreet.flatMap((s) => s.allowedStraightWindows.map(normalizeWindow)));
      if (norm && !allowedAnywhere.has(norm)) {
        add(c, `names straight ${c.straightRanks} which no board window allows (${[...allowedAnywhere].join(", ") || "no straights possible"})`);
        continue;
      }
    }

    // 4. Stated equity/pot-odds % that contradicts the injected FACT.
    if (c.percent != null && (c.category === "equity" || c.category === "pot_odds") && lab.heroEquity != null) {
      const factPct = Math.round(lab.heroEquity * 100);
      if (Math.abs(c.percent - factPct) > 12) {
        add(c, `states ${c.percent}% but the equity FACT for ${lab.street} is ~${factPct}% (>12pt deviation)`);
        continue;
      }
    }
  }
  return out;
}

function anyStreetAllows(fx: Fixture, kind: "boat" | "flush"): boolean {
  return fx.labels.perStreet.some((s) => kind === "boat" ? s.boatOrQuadsPossible : s.flushPossible);
}

const _rankOrder = "23456789TJQKA";
function normalizeWindow(s: string): string | null {
  const ranks = s.toUpperCase().split(/[-\s,]+/).map((r) => r === "10" ? "T" : r).filter((r) => _rankOrder.includes(r));
  if (ranks.length !== 5) return null;
  const idxs = ranks.map((r) => _rankOrder.indexOf(r)).sort((a, b) => a - b);
  return idxs.join("-");
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

  const results: { id: string; bucket: string; claims: number; violations: Violation[] }[] = [];
  for (const fx of fixtures) {
    try {
      const analysis = await runCoaching(fx);
      const claims = await extractClaims(fx, analysis);
      const violations = adjudicate(fx, claims);
      results.push({ id: fx.id, bucket: fx.bucket, claims: claims.length, violations });
      const mark = violations.length === 0 ? "OK " : "ERR";
      console.log(`${mark} ${fx.id}  (${claims.length} claims, ${violations.length} violations)`);
      for (const v of violations) console.log(`      - [${v.street}/${v.category}] ${v.detail}`);
    } catch (e) {
      console.error(`FAIL ${fx.id}: ${e instanceof Error ? e.message : e}`);
      results.push({ id: fx.id, bucket: fx.bucket, claims: 0, violations: [{ fixtureId: fx.id, street: "-", category: "harness_error", detail: String(e), claim: "" }] });
    }
  }

  const clean = results.filter((r) => r.violations.length === 0).length;
  const accuracy = results.length ? (100 * clean / results.length) : 0;
  const byCategory: Record<string, number> = {};
  for (const r of results) {
    for (const v of r.violations) byCategory[v.category] = (byCategory[v.category] ?? 0) + 1;
  }

  const report = { generatedFor: COACH_MODEL, total: results.length, clean, cardLogicAccuracyPct: Number(accuracy.toFixed(1)), byCategory, results };
  await Deno.writeTextFile(`${outDir}/report.json`, JSON.stringify(report, null, 2));
  await Deno.writeTextFile(`${outDir}/report.md`, renderMarkdown(report));

  console.log(`\nCard-logic accuracy: ${accuracy.toFixed(1)}%  (${clean}/${results.length} spots clean)`);
  console.log(`Report: ${outDir}/report.md`);
}

// deno-lint-ignore no-explicit-any
function renderMarkdown(r: any): string {
  const lines = [
    `# Eval harness — card-logic report`,
    ``,
    `- Model under test: \`${r.generatedFor}\``,
    `- **Card-logic accuracy: ${r.cardLogicAccuracyPct}%** (${r.clean}/${r.total} spots with zero card-logic errors)`,
    ``,
    `## Violations by category`,
    ``,
    Object.keys(r.byCategory).length
      ? Object.entries(r.byCategory).map(([k, v]) => `- ${k}: ${v}`).join("\n")
      : `_None._`,
    ``,
    `## Per-spot`,
    ``,
    `| Spot | Bucket | Claims | Violations |`,
    `|---|---|---|---|`,
    // deno-lint-ignore no-explicit-any
    ...r.results.map((s: any) => `| ${s.id} | ${s.bucket} | ${s.claims} | ${s.violations.length} |`),
  ];
  return lines.join("\n") + "\n";
}

if (import.meta.main) await main();
