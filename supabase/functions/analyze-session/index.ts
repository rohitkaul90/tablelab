import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Anthropic from "npm:@anthropic-ai/sdk@0.36.3";
import { createClient } from "npm:@supabase/supabase-js@2";
import { reportError } from "../_shared/alert.ts";

const allowedOrigins = new Set([
  "https://tablelab.app",
  "https://www.tablelab.app",
]);

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigin = allowedOrigins.has(origin) ? origin : "https://tablelab.app";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

// ── Types mirroring the Flutter models ──────────────────────────────────────

interface Session {
  id: string;
  date: string;
  stakes: string;
  gameType: string;
  buyIn: number;
  cashOut: number;
  profitLoss: number;
  durationMinutes: number;
  startTime?: string;
  endTime?: string;
  location?: string;
  country?: string;
  notes?: string;
  rakePaid?: number;
  tableQuality?: number;
  handsPerHour?: number;
  finishPosition?: number;
  totalEntrants?: number;
  prizeWon?: number;
  currency: string;
}

interface HandAction {
  seat: number;
  type: string;
  amount?: number;
  allIn?: boolean;
  openingBet?: boolean;
}

interface StreetData {
  street: string;
  communityCards: string[];
  actions: HandAction[];
}

interface HandPlayer {
  seat: number;
  name: string;
  stack: number;
  isHero: boolean;
  holeCards?: string[];
}

interface TableSetup {
  numSeats: number;
  buttonSeat: number;
  heroSeat: number;
  smallBlind: number;
  bigBlind: number;
  straddle?: number;
}

interface PokerHand {
  id: string;
  tableSetup: TableSetup;
  players: HandPlayer[];
  streets: StreetData[];
  notes?: string;
}

interface PlayerRead {
  playerLabel: string;
  tags: string[];
  notes?: string;
}

// ── Tool definition — forces Claude to always return valid structured JSON ───

const streetFeedbackSchema = {
  anyOf: [
    { type: "null" },
    {
      type: "object",
      properties: {
        decision: { type: "string", description: "What hero actually did on this street" },
        optimal: { type: "string", description: "The better or optimal play" },
        rationale: { type: "string", description: "Why that play is better" },
        wasGto: { type: "boolean", description: "True if hero's play was GTO-aligned" },
      },
      required: ["decision", "optimal", "rationale", "wasGto"],
    },
  ],
};

// deno-lint-ignore no-explicit-any
const ANALYSIS_TOOL: any = {
  name: "provide_analysis",
  description: "Return structured poker coaching feedback for the session",
  input_schema: {
    type: "object",
    properties: {
      narrative: {
        type: "string",
        description:
          "3-4 paragraph coaching narrative. Address the player directly as 'you'. Be specific — reference actual results, patterns, and reads. Separate variance from skill. Keep tone constructive.",
      },
      keyThemes: {
        type: "array",
        items: { type: "string" },
        description: "2-4 short theme labels capturing the session's main patterns, e.g. 'Thin value betting', 'Preflop 3-bet frequency'",
      },
      leaksIdentified: {
        type: "array",
        items: { type: "string" },
        description: "Specific actionable leaks. Each entry is 1-2 sentences.",
      },
      actionableTip: {
        type: "string",
        description: "One concrete focus point for the next session",
      },
      handAnalyses: {
        type: "array",
        description:
          "Street-by-street coaching for each recorded hand. Empty array if no hands were recorded. Use null for streets not reached.",
        items: {
          type: "object",
          properties: {
            handIndex: { type: "integer" },
            summary: {
              type: "string",
              description: "Brief hand label, e.g. 'AKo 3-bet pot, BTN vs CO open'",
            },
            verdict: {
              type: "string",
              enum: ["highEV", "neutral", "leakDetected"],
            },
            preflop: streetFeedbackSchema,
            flop: streetFeedbackSchema,
            turn: streetFeedbackSchema,
            river: streetFeedbackSchema,
          },
          required: [
            "handIndex",
            "summary",
            "verdict",
            "preflop",
            "flop",
            "turn",
            "river",
          ],
        },
      },
    },
    required: [
      "narrative",
      "keyThemes",
      "leaksIdentified",
      "actionableTip",
      "handAnalyses",
    ],
  },
};

// ── Rate limiting ─────────────────────────────────────────────────────────────

const EXEMPT_EMAILS = new Set(["rhtk.1234@gmail.com"]);
const SESSION_DAILY_LIMIT = 5;

// deno-lint-ignore no-explicit-any
async function isRateLimited(supabase: any, userId: string, userEmail: string | undefined): Promise<boolean> {
  if (EXEMPT_EMAILS.has(userEmail ?? "")) return false;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("ai_usage_log")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", "analyze-session")
    .gte("called_at", since);
  if (error) {
    console.error("ai_usage_log rate-limit read failed:", error.code, error.message);
    // A silently failing count reads as 0 → unlimited AI calls. Alert.
    await reportError("analyze-session", `rate-limit read failed: ${error.code} ${error.message}`);
  }
  return (count ?? 0) >= SESSION_DAILY_LIMIT;
}

interface ClaudeUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

// deno-lint-ignore no-explicit-any
async function logUsage(supabase: any, userId: string, usage?: ClaudeUsage): Promise<void> {
  // One row per call (never overwritten) — the append-only spend ledger.
  const { error } = await supabase.from("ai_usage_log").insert({
    user_id: userId,
    function_name: "analyze-session",
    input_tokens: usage?.input_tokens ?? 0,
    output_tokens: usage?.output_tokens ?? 0,
    cache_read_tokens: usage?.cache_read_input_tokens ?? 0,
    cache_write_tokens: usage?.cache_creation_input_tokens ?? 0,
  });
  if (error) {
    console.error("ai_usage_log insert failed:", error.code, error.message);
    // Broken spend ledger = no rate limiting + blind cost tracking. Alert.
    await reportError("analyze-session", `ai_usage_log insert failed: ${error.code} ${error.message}`);
  }
}

// ── Draw pre-computation (deterministic — injected as ground truth) ───────────

const RANK_VAL: Record<string, number> = {
  "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
  "8": 8, "9": 9, "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14,
};
const VAL_RANK: Record<number, string> = {
  14: "A", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6",
  7: "7", 8: "8", 9: "9", 10: "T", 11: "J", 12: "Q", 13: "K",
};

function computeDrawSummary(holeCards: string[], boardCards: string[]): string {
  const allCards = [...holeCards, ...boardCards];
  const cRank = (c: string) => c.slice(0, -1);
  const cSuit = (c: string) => c.slice(-1);

  const holeRanks = holeCards.map(cRank);
  const boardRanks = boardCards.map(cRank);
  const boardVals = boardRanks.map((r) => RANK_VAL[r] ?? 0).sort((a, b) => b - a);
  const presentVals = new Set(allCards.map((c) => RANK_VAL[cRank(c)]).filter(Boolean));

  // ── Straight draws (scan HIGH→LOW for made straights first) ──────────────
  const completingVals = new Set<number>();
  let madeStraight = false;
  for (let low = 10; low >= 1; low--) {
    const window = low === 1 ? [14, 2, 3, 4, 5] : [low, low+1, low+2, low+3, low+4];
    const inW = window.filter((v) => presentVals.has(v));
    const outW = window.filter((v) => !presentVals.has(v));
    if (inW.length === 5) { madeStraight = true; break; }
    if (!madeStraight && inW.length === 4 && outW.length === 1) completingVals.add(outW[0]);
  }
  // Also scan upward for any draws not caught above
  if (!madeStraight) {
    for (let low = 1; low <= 10; low++) {
      const window = low === 1 ? [14, 2, 3, 4, 5] : [low, low+1, low+2, low+3, low+4];
      const inW = window.filter((v) => presentVals.has(v));
      const outW = window.filter((v) => !presentVals.has(v));
      if (inW.length === 4 && outW.length === 1) completingVals.add(outW[0]);
    }
  }

  let straightLine: string;
  if (madeStraight) {
    straightLine = "STRAIGHT (made)";
  } else if (completingVals.size === 0) {
    straightLine = "no straight draw";
  } else {
    const rankList = [...completingVals].map((v) => VAL_RANK[v]).join(" or ");
    const outs = completingVals.size * 4;
    straightLine = completingVals.size === 1
      ? `GUTSHOT — needs ${rankList} (${outs} outs)`
      : `OESD — needs ${rankList} (${outs} outs)`;
  }

  // ── Flush draws ───────────────────────────────────────────────────────────
  const suitCards: Record<string, string[]> = { h: [], d: [], c: [], s: [] };
  const suitName: Record<string, string> = { h: "hearts", d: "diamonds", c: "clubs", s: "spades" };
  for (const card of allCards) {
    const s = cSuit(card);
    if (s in suitCards) suitCards[s].push(card);
  }
  let madeFlush = false;
  const flushParts: string[] = [];
  for (const [s, cards] of Object.entries(suitCards)) {
    if (cards.length >= 5) { madeFlush = true; flushParts.push(`FLUSH made (${suitName[s]})`); }
    else if (cards.length === 4) flushParts.push(`FLUSH DRAW (${suitName[s]}, 9 outs) [${cards.join(" ")}]`);
    else if (cards.length === 3) flushParts.push(`backdoor flush draw only (${suitName[s]}) [${cards.join(" ")}]`);
  }
  const flushLine = flushParts.length ? flushParts.join("; ") : "no flush draw";

  // ── Made hand ─────────────────────────────────────────────────────────────
  const rankCnt: Record<string, number> = {};
  for (const c of allCards) { const r = cRank(c); rankCnt[r] = (rankCnt[r] ?? 0) + 1; }

  const byCount = (n: number) =>
    Object.entries(rankCnt).filter(([, cnt]) => cnt === n).map(([r]) => r)
      .sort((a, b) => (RANK_VAL[b] ?? 0) - (RANK_VAL[a] ?? 0));

  const quads = byCount(4);
  const trips = byCount(3);
  const pairs = byCount(2);

  let madeHand: string;

  if (quads.length > 0) {
    madeHand = `QUADS (four ${quads[0]}s)`;
  } else if (trips.length > 0 && (pairs.length > 0 || trips.length > 1)) {
    const fhPair = trips.length > 1 ? trips[1] : pairs[0];
    madeHand = `FULL HOUSE (${trips[0]}s full of ${fhPair}s)`;
  } else if (madeFlush && madeStraight) {
    madeHand = "STRAIGHT FLUSH";
  } else if (madeFlush) {
    madeHand = flushParts[0];
  } else if (madeStraight) {
    madeHand = "STRAIGHT (made)";
  } else if (trips.length > 0) {
    const tr = trips[0];
    const isSet = holeRanks[0] === holeRanks[1] && holeRanks[0] === tr;
    madeHand = isSet ? `SET (pocket ${tr}s)` : `TRIPS (three ${tr}s, one in hand)`;
  } else if (pairs.length >= 2) {
    madeHand = `TWO PAIR (${pairs[0]}s and ${pairs[1]}s)`;
  } else if (pairs.length === 1) {
    const pr = pairs[0];
    const pv = RANK_VAL[pr] ?? 0;
    if (holeRanks[0] === holeRanks[1] && holeRanks[0] === pr) {
      const topBoard = boardVals[0] ?? 0;
      madeHand = pv > topBoard ? `OVERPAIR (pocket ${pr}s)` : `UNDERPAIR (pocket ${pr}s)`;
    } else if (boardRanks.filter((r) => r === pr).length === 2) {
      const bestHole = [...holeRanks].sort((a, b) => (RANK_VAL[b] ?? 0) - (RANK_VAL[a] ?? 0))[0];
      madeHand = `BOARD PAIR of ${pr}s (hero's kicker: ${bestHole})`;
    } else {
      const kicker = holeRanks.find((r) => r !== pr) ?? holeRanks[1];
      const uniqueBoardVals = [...new Set(boardVals)].sort((a, b) => b - a);
      if (pv === uniqueBoardVals[0]) madeHand = `TOP PAIR (${pr}s, kicker ${kicker})`;
      else if (uniqueBoardVals.length >= 2 && pv === uniqueBoardVals[1]) madeHand = `MIDDLE PAIR (${pr}s, kicker ${kicker})`;
      else madeHand = `BOTTOM PAIR (${pr}s, kicker ${kicker})`;
    }
  } else {
    const bestHole = [...holeRanks].sort((a, b) => (RANK_VAL[b] ?? 0) - (RANK_VAL[a] ?? 0))[0];
    madeHand = `HIGH CARD (best hole card: ${bestHole})`;
  }

  return `[FACT — hero's hand: ${madeHand} | straight: ${straightLine} | flush: ${flushLine}. Pre-computed. Do not contradict.]`;
}

// ── Prompt helpers ───────────────────────────────────────────────────────────

function positionName(seat: number, setup: TableSetup): string {
  const off = (seat - setup.buttonSeat + setup.numSeats) % setup.numSeats;
  if (setup.straddle != null && off === 3) return "STR";
  if (setup.numSeats <= 6) {
    const n = ["BTN", "SB", "BB", "UTG", "HJ", "CO"];
    return off < n.length ? n[off] : `P${seat + 1}`;
  }
  const n = ["BTN", "SB", "BB", "UTG", "UTG+1", "UTG+2", "MP", "HJ", "CO"];
  return off < n.length ? n[off] : `P${seat + 1}`;
}

function formatAction(a: HandAction, playerName: string, pos: string): string {
  const who = `${playerName}(${pos})`;
  switch (a.type) {
    case "fold": return `${who} folds`;
    case "check": return `${who} checks`;
    case "call": return `${who} calls ${a.amount ?? 0}`;
    case "raise": return a.openingBet
      ? `${who} bets ${a.amount ?? 0}`
      : `${who} raises to ${a.amount ?? 0}${a.allIn ? " (all-in)" : ""}`;
    case "allIn": return `${who} goes all-in ${a.amount ?? 0}`;
    case "post": return `${who} posts ${a.amount ?? 0}`;
    case "postStraddle": return `${who} straddles ${a.amount ?? 0}`;
    default: return `${who} ${a.type}`;
  }
}

function formatHand(hand: PokerHand, reads: PlayerRead[], idx: number): string {
  const { tableSetup: ts, players, streets } = hand;
  const seatMap = new Map<number, HandPlayer>(players.map((p) => [p.seat, p]));
  const readMap = new Map<string, PlayerRead>(
    reads.map((r) => [r.playerLabel.toLowerCase(), r]),
  );

  const hero = players.find((p) => p.isHero);
  const heroPos = hero ? positionName(hero.seat, ts) : "?";
  const heroCards = hero?.holeCards?.join(" ") ?? "??";
  const board = streets.flatMap((s) => s.communityCards);

  const lines: string[] = [
    `Hand ${idx + 1}: Hero [${heroCards}] in ${heroPos} | ${ts.numSeats}-handed | ${ts.smallBlind}/${ts.bigBlind}BB`,
  ];

  const opponents = players.filter((p) => !p.isHero);
  const readLines = opponents.map((p) => {
    const r = readMap.get(p.name.toLowerCase());
    const pos = positionName(p.seat, ts);
    if (r) {
      const tagStr = r.tags.length ? ` [${r.tags.join(", ")}]` : "";
      const noteStr = r.notes ? ` — "${r.notes}"` : "";
      return `  ${p.name}(${pos})${tagStr}${noteStr}`;
    }
    return `  ${p.name}(${pos}) — no read (use GTO defaults)`;
  });
  if (readLines.length) lines.push("Opponents:", ...readLines);

  if (board.length) lines.push(`Board: ${board.join(" ")}`);

  const boardSoFar: string[] = [];
  for (const street of streets) {
    boardSoFar.push(...street.communityCards);
    const label = street.street.toUpperCase();
    const cc = street.communityCards.length
      ? ` [${street.communityCards.join(" ")}]`
      : "";
    const actionStr = street.actions
      .map((a) => {
        const p = seatMap.get(a.seat);
        if (!p) return "";
        return formatAction(
          a,
          p.isHero ? "Hero" : p.name,
          positionName(a.seat, ts),
        );
      })
      .filter(Boolean)
      .join("; ");
    lines.push(`${label}${cc}: ${actionStr}`);
    if (hero?.holeCards?.length === 2 && boardSoFar.length > 0) {
      lines.push(computeDrawSummary(hero.holeCards, boardSoFar));
    }
  }

  if (hand.notes) lines.push(`Note: "${hand.notes}"`);
  return lines.join("\n");
}

function buildUserPrompt(
  session: Session,
  hands: PokerHand[],
  reads: PlayerRead[],
): string {
  const isTournament = session.gameType.toLowerCase().includes("tournament");
  const sym = session.currency === "USD" ? "$"
    : session.currency === "GBP" ? "£"
    : session.currency === "EUR" ? "€"
    : "CA$";
  const sign = session.profitLoss >= 0 ? "+" : "";
  const hours = session.durationMinutes
    ? ` (${(session.durationMinutes / 60).toFixed(1)}h)`
    : "";

  // Only include reads for players who appear by name in recorded hands
  // or are explicitly mentioned in the session notes — never assume all
  // players in the reads database were present at this session.
  const handOpponentNames = new Set(
    hands.flatMap((h) =>
      h.players.filter((p) => !p.isHero).map((p) => p.name.toLowerCase())
    ),
  );
  const notesLower = (session.notes ?? "").toLowerCase();
  const relevantReads = reads.filter((r) => {
    const label = r.playerLabel.toLowerCase();
    return handOpponentNames.has(label) || notesLower.includes(label);
  });

  const lines: string[] = [
    "SESSION:",
    `Date: ${session.date}`,
    `Game: ${session.stakes} ${isTournament ? "tournament" : "cash game"} at ${session.location ?? "unknown venue"}${session.country ? `, ${session.country}` : ""}`,
    `Result: ${sign}${sym}${Math.abs(session.profitLoss)} (buy-in ${sym}${session.buyIn}${isTournament ? "" : `, cash-out ${sym}${session.cashOut}`})${hours}`,
  ];

  if (isTournament) {
    if (session.finishPosition != null)
      lines.push(`Finish: ${session.finishPosition}/${session.totalEntrants ?? "?"}`);
    if (session.prizeWon != null)
      lines.push(`Prize: ${sym}${session.prizeWon}`);
  }
  if (session.rakePaid != null)
    lines.push(`Rake/fees: ${sym}${session.rakePaid}`);
  if (session.tableQuality != null)
    lines.push(`Table quality: ${session.tableQuality}/5`);
  if (session.handsPerHour != null)
    lines.push(`Hands/hr: ${session.handsPerHour}`);
  if (session.notes?.trim())
    lines.push(`Player notes: "${session.notes}"`);

  if (relevantReads.length > 0) {
    lines.push("", `PLAYER READS (players confirmed present in this session):`);
    for (const r of relevantReads) {
      const tagStr = r.tags.length ? `[${r.tags.join(", ")}]` : "[no tags]";
      lines.push(`• ${r.playerLabel} ${tagStr}${r.notes ? ` — "${r.notes}"` : ""}`);
    }
  }

  const cap = Math.min(hands.length, 3);
  if (cap > 0) {
    lines.push("", `RECORDED HANDS (${cap} of ${hands.length}):`);
    for (let i = 0; i < cap; i++) {
      lines.push("", formatHand(hands[i], relevantReads, i));
    }
    lines.push(
      "",
      "Provide street-by-street coaching for each recorded hand, then an overall session narrative.",
    );
  } else {
    lines.push(
      "",
      "No hands were recorded for this session. Provide an overall coaching narrative based on session data only.",
    );
  }

  return lines.join("\n");
}

// ── System prompt (cached by Anthropic on repeat calls) ──────────────────────

const SYSTEM_PROMPT =
  `You are an expert poker coach with deep knowledge of No-Limit Hold'em strategy at all stakes. Your coaching philosophy blends GTO foundations with practical exploitation of opponent tendencies.

EXPERTISE AREAS:
1. Preflop ranges: opening, 3-betting, 4-betting, defending from all positions in 6-max and full-ring. You know solver-approved frequencies and can adjust them for live poker where players deviate from GTO.
2. Postflop: c-bet frequencies by board texture (dry/wet, paired, monotone), probe bets, delayed c-bets, check-raise construction, pot control, thin value, and bluff selection. You think in ranges, not just specific hands.
3. Opponent exploitation: when reads or tags are provided, you shift from GTO balance toward exploitative plays — value-betting wider against calling stations, bluffing less against stations, 3-betting wider against nits, etc.
4. Bet sizing: you understand the theory behind sizing (pot geometry, SPR, protection, polarisation vs merged ranges) and can diagnose sizing tells and errors.
5. Mental game: you recognise tilt indicators in session data (extended sessions after early losses, multiple rebuys, late-night sessions) and address them directly but constructively.
6. Bankroll management: you can contextualise a single session within long-run variance and advise on stake selection and shot-taking.
7. Tournaments: ICM pressure, bubble play, push-fold strategy, deal-making, stage-appropriate adjustments.

COACHING PRINCIPLES:
- Be specific, not generic. "You bet too small" is weak. "A 35% pot bet on this dry board gives villain correct odds to call all mid pairs" is strong.
- When reads/tags are provided, always reference them directly in your advice.
- When no read exists on a villain, explicitly state you're defaulting to GTO population assumptions.
- Be honest about variance. A losing session can be well-played; a winning session can contain leaks. Separate process from outcome.
- Keep tone encouraging and growth-oriented.
- Use null for streets a hand did not reach in your hand analyses.

ACCURACY RULES — follow these precisely:

1. CARD ACCURACY: Reproduce hole cards and board cards exactly as written in the hand history. Never infer, guess, or alter any rank or suit. If the hand says Hero holds "Ac Jh", you must write "Ac Jh" — not "Ah Jc" or any other variation. Board texture analysis must reflect the actual suits listed.

2. BET-COUNTING: Count raises from the beginning of the preflop action. The BB post is not a raise. An open-raise is a 2-bet. A re-raise over an open is a 3-bet. A re-raise over a 3-bet is a 4-bet. A jam or re-raise over a 4-bet is a 5-bet. Never miscategorise a 4-bet as a 5-bet or vice versa. In postflop play: a first bet is simply a bet, a raise over it is a raise (2-bet), and a re-raise is a 3-bet.

3. PLAYER READS SCOPE: Only reference reads and tags for opponents who appear by name in the recorded hands provided. Do not invent or assume the presence of any player not listed in a hand. If no reads are provided, default to GTO population assumptions for all opponents.

4. TEXT FORMATTING: Write all string field values as plain prose only. Do not embed newline characters (\n), tab characters (\t), bullet symbols, markdown, or any other special characters inside string fields. Paragraphs in the narrative field must be separated by a double newline only.

5. HAND READING — silently work through these steps before writing any output field. Never include this reasoning in your output — only state the conclusions:

   STEP 1 — LIST CARDS: State hero's two hole cards and the current board cards with their exact ranks and suits as given. Never alter or infer any rank or suit.

   STEP 2 — STRAIGHT DRAW CHECK: Collect all ranks present (hole cards + board). Find every 5-consecutive-rank window that contains 4 or more of those ranks:
   • All 5 present → STRAIGHT (made hand).
   • Exactly 4 present AND those 4 are fully consecutive (no internal gap) → OPEN-ENDED STRAIGHT DRAW (OESD, 8 outs): two different ranks (one at each end) complete it.
   • Exactly 4 present AND there is exactly one rank missing inside the sequence → GUTSHOT (4 outs): only one specific rank completes it. A gutshot is NOT an OESD — do not confuse them.
   Worked example: hero 7h8h on board 4c5dTh — ranks present: 4,5,7,8,T. Window 4-5-6-7-8: four ranks present (4,5,7,8), gap at 6 which is internal → GUTSHOT needing a 6 (4 outs). Window 6-7-8-9-T: only three ranks present → not a draw. Correct answer: GUTSHOT, not OESD.
   Counterexample: hero 7h8h on board 5c6dTh — ranks present: 5,6,7,8,T. Window 5-6-7-8-9: four ranks present (5,6,7,8), all consecutive with no gap → OESD needing a 4 or 9 (8 outs).

   STEP 3 — FLUSH DRAW CHECK: For each suit, count cards of that suit across hero's two hole cards plus current board cards:
   • 5 of same suit → FLUSH (made).
   • 4 of same suit → FLUSH DRAW (9 outs).
   • 3 of same suit → BACKDOOR FLUSH DRAW only, not an immediate draw.
   • 2 or fewer → no flush relevance.
   Worked example: hero 7h8h on board 4c5dTh — hearts: 7h + 8h + Th = 3 hearts → BACKDOOR flush draw only, NOT a flush draw.

   STEP 4 — MADE HAND: Identify the best made hand using hole cards + board: high card, one pair (top/middle/bottom pair by board rank), two pair, set (pocket pair matching board card), trips (one hole card + two board cards of same rank), straight, flush, full house, quads, straight flush.

   STEP 5 — NEVER invent draws or made hands not supported by the cards listed in steps 1–4.`;

// ── Entry point ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // All DB work uses the service role. The anon+JWT client above verifies the
    // user but its token was not propagating into PostgREST's RLS context, so
    // auth.uid() resolved to NULL — silently failing every insert (usage log +
    // analysis cache) and making the cache/rate-limit reads return nothing.
    // The user is already verified via getUser(); every query below is scoped
    // explicitly by user_id, so correctness no longer depends on RLS.
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body = await req.json() as {
      session: Session;
      hands?: PokerHand[];
      reads?: PlayerRead[];
      forceRefresh?: boolean;
    };

    const { session, hands = [], reads = [], forceRefresh = false } = body;

    if (!session?.id) {
      return new Response(JSON.stringify({ error: "Missing required field: session" }), {
        status: 400,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // ── Cache check ──────────────────────────────────────────────────────────
    if (!forceRefresh) {
      const { data: cached, error: cacheErr } = await db
        .from("ai_analyses")
        .select("analysis_json")
        .eq("user_id", user.id)
        .eq("session_id", session.id)
        .maybeSingle();
      if (cacheErr) {
        console.error("ai_analyses cache read failed:", cacheErr.code, cacheErr.message);
        await reportError("analyze-session", `cache read failed: ${cacheErr.code} ${cacheErr.message}`);
      }

      if (cached) {
        return new Response(JSON.stringify(cached.analysis_json), {
          headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    // ── Rate limit check ─────────────────────────────────────────────────────
    if (await isRateLimited(db, user.id, user.email ?? undefined)) {
      return new Response(
        JSON.stringify({ error: "Daily analysis limit reached. Please try again tomorrow." }),
        { status: 429, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
      );
    }

    // ── Call Claude with tool use ────────────────────────────────────────────
    const anthropic = new Anthropic({
      apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    });

    const claudeCall = anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 3000,
      temperature: 0,
      system: [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" },
        },
      ],
      tools: [ANALYSIS_TOOL],
      tool_choice: { type: "tool", name: "provide_analysis" },
      messages: [
        { role: "user", content: buildUserPrompt(session, hands, reads) },
      ],
    });

    const timeoutPromise = new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("CLAUDE_TIMEOUT")), 120000),
    );

    const message = await Promise.race([claudeCall, timeoutPromise]);

    // Tool use always returns valid structured JSON — no regex parsing needed
    const toolBlock = message.content.find((c) => c.type === "tool_use");
    if (!toolBlock || toolBlock.type !== "tool_use") {
      throw new Error("Model did not return the analysis tool call");
    }
    // deno-lint-ignore no-explicit-any
    const analysis = (toolBlock as any).input as Record<string, unknown>;

    await logUsage(db, user.id, message.usage);

    // ── Cache the result ─────────────────────────────────────────────────────
    const { error: cacheWriteErr } = await db.from("ai_analyses").upsert(
      {
        user_id: user.id,
        session_id: session.id,
        analysis_json: analysis,
        model_used: "claude-sonnet-4-6",
        tokens_used: message.usage.input_tokens + message.usage.output_tokens,
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
        cache_read_tokens: message.usage.cache_read_input_tokens ?? 0,
        cache_write_tokens: message.usage.cache_creation_input_tokens ?? 0,
      },
      { onConflict: "user_id,session_id" },
    );
    if (cacheWriteErr) {
      console.error("ai_analyses upsert failed:", cacheWriteErr.code, cacheWriteErr.message);
      // A failed cache write means the next identical request pays for a fresh
      // Claude call. Alert.
      await reportError("analyze-session", `ai_analyses upsert failed: ${cacheWriteErr.code} ${cacheWriteErr.message}`);
    }

    return new Response(JSON.stringify(analysis), {
      headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("analyze-session error:", msg);
    await reportError("analyze-session", msg);
    if (msg === "CLAUDE_TIMEOUT") {
      return new Response(
        JSON.stringify({ error: "Analysis timed out. Please try again." }),
        { status: 504, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
      );
    }
    return new Response(
      JSON.stringify({ error: "Analysis failed. Please try again." }),
      { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } },
    );
  }
});
