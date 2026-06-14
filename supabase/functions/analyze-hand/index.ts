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

// ── Types ────────────────────────────────────────────────────────────────────

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
  ante?: number;
}

interface PokerHand {
  id: string;
  tableSetup: TableSetup;
  players: HandPlayer[];
  streets: StreetData[];
  notes?: string;
  tournamentStage?: string;
}

interface PlayerRead {
  playerLabel: string;
  tags: string[];
  notes?: string;
}

// ── Tool definition ───────────────────────────────────────────────────────────

const streetFeedbackSchema = {
  anyOf: [
    { type: "null" },
    {
      type: "object",
      properties: {
        decision: { type: "string", description: "What hero actually did on this street" },
        optimal: { type: "string", description: "The optimal or better play against this opponent" },
        rationale: { type: "string", description: "Why that play is better, referencing opponent reads if available" },
        wasGto: { type: "boolean", description: "True if hero's play was GTO-aligned" },
        confidence: {
          type: "string",
          enum: ["high", "medium", "low"],
          description:
            "How clear-cut this street's assessment is: high = standard spot with a well-established answer, medium = read- or assumption-dependent, low = genuinely close or missing key information",
        },
        alternative: {
          anyOf: [{ type: "null" }, { type: "string" }],
          description:
            "A second genuinely defensible line for this street, in one sentence (e.g. 'A small raise for protection is also fine here'). Set to null when the optimal play is clearly unique.",
        },
      },
      required: ["decision", "optimal", "rationale", "wasGto", "confidence", "alternative"],
    },
  ],
};

// deno-lint-ignore no-explicit-any
const COACHING_TOOL: any = {
  name: "provide_hand_coaching",
  description: "Return detailed street-by-street coaching for a single recorded poker hand",
  input_schema: {
    type: "object",
    properties: {
      summary: {
        type: "string",
        description: "Brief hand label e.g. 'AKo 3-bet pot, BTN vs CO open' or 'Flopped top pair vs aggressor'",
      },
      verdict: {
        type: "string",
        enum: ["highEV", "neutral", "leakDetected"],
        description: "Overall assessment of hero's play across all streets",
      },
      keyMistake: {
        anyOf: [{ type: "null" }, { type: "string" }],
        description:
          "The single biggest error hero made, in 1-2 sentences. MUST match the per-street feedback: only name a street whose feedback you marked wasGto:false, and never contradict the equity/pot-odds FACTs (do not call a price-meeting call a mistake). Set to null when the hand was played fine — that includes a bluff-catch call whose equity meets its pot-odds price.",
      },
      preflop: streetFeedbackSchema,
      flop: streetFeedbackSchema,
      turn: streetFeedbackSchema,
      river: streetFeedbackSchema,
    },
    required: ["summary", "verdict", "keyMistake", "preflop", "flop", "turn", "river"],
  },
};

// ── Rate limiting ─────────────────────────────────────────────────────────────

const EXEMPT_EMAILS = new Set(["rhtk.1234@gmail.com"]);
const HAND_DAILY_LIMIT = 20;

// deno-lint-ignore no-explicit-any
async function isRateLimited(supabase: any, userId: string, userEmail: string | undefined): Promise<boolean> {
  if (EXEMPT_EMAILS.has(userEmail ?? "")) return false;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("ai_usage_log")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", "analyze-hand")
    .gte("called_at", since);
  if (error) {
    console.error("ai_usage_log rate-limit read failed:", error.code, error.message);
    // A silently failing count reads as 0 → unlimited AI calls. Alert.
    await reportError("analyze-hand", `rate-limit read failed: ${error.code} ${error.message}`);
  }
  return (count ?? 0) >= HAND_DAILY_LIMIT;
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
    function_name: "analyze-hand",
    input_tokens: usage?.input_tokens ?? 0,
    output_tokens: usage?.output_tokens ?? 0,
    cache_read_tokens: usage?.cache_read_input_tokens ?? 0,
    cache_write_tokens: usage?.cache_creation_input_tokens ?? 0,
  });
  if (error) {
    console.error("ai_usage_log insert failed:", error.code, error.message);
    // Broken spend ledger = no rate limiting + blind cost tracking. Alert.
    await reportError("analyze-hand", `ai_usage_log insert failed: ${error.code} ${error.message}`);
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

  // ── Straight draws (highest window first) ─────────────────────────────────
  const completingVals = new Set<number>();
  let madeStraight = false;
  let straightCards: string[] = [];
  for (let low = 10; low >= 1; low--) {
    const window = low === 1 ? [14, 2, 3, 4, 5] : [low, low+1, low+2, low+3, low+4];
    const inW = window.filter((v) => presentVals.has(v));
    const outW = window.filter((v) => !presentVals.has(v));
    if (inW.length === 5) {
      madeStraight = true;
      // Identify the specific cards forming this straight
      for (const v of window) {
        const card = allCards.find((c) => RANK_VAL[cRank(c)] === v);
        if (card) straightCards.push(card);
      }
      break;
    }
    if (!madeStraight && inW.length === 4 && outW.length === 1) completingVals.add(outW[0]);
  }
  // Also scan upward for draws if no made straight
  if (!madeStraight) {
    for (let low = 1; low <= 10; low++) {
      const window = low === 1 ? [14, 2, 3, 4, 5] : [low, low+1, low+2, low+3, low+4];
      const inW = window.filter((v) => presentVals.has(v));
      const outW = window.filter((v) => !presentVals.has(v));
      if (inW.length === 4 && outW.length === 1) completingVals.add(outW[0]);
    }
  }

  // Classify hole-card contribution to the straight draw
  const holeVals = new Set(holeCards.map((c) => RANK_VAL[cRank(c)]));
  const holeInDraw = [...completingVals].length > 0
    ? holeCards.filter((c) => {
        const v = RANK_VAL[cRank(c)];
        // Check if this hole card participates in any completing window
        return [...completingVals].some((cv) => {
          for (let low = 1; low <= 10; low++) {
            const w = low === 1 ? [14,2,3,4,5] : [low,low+1,low+2,low+3,low+4];
            if (!w.includes(cv)) continue;
            if (w.filter((x) => presentVals.has(x)).length === 4 && w.includes(v)) return true;
          }
          return false;
        });
      })
    : [];

  let straightLine: string;
  if (madeStraight) {
    const holeInStraight = straightCards.filter((c) => holeCards.includes(c));
    const boardInStraight = straightCards.filter((c) => boardCards.includes(c));
    straightLine = `STRAIGHT (made: ${straightCards.join("-")}; hero's hole cards in straight: ${holeInStraight.join(" ")}; board cards in straight: ${boardInStraight.join(" ")})`;
  } else if (completingVals.size === 0) {
    straightLine = "no straight draw";
  } else {
    const rankList = [...completingVals].map((v) => VAL_RANK[v]).join(" or ");
    const outs = completingVals.size * 4;
    const holeNote = holeInDraw.length ? ` [hero's hole cards in draw: ${holeInDraw.join(" ")}]` : "";
    straightLine = completingVals.size === 1
      ? `GUTSHOT — needs ${rankList} (${outs} outs)${holeNote}`
      : `OESD — needs ${rankList} (${outs} outs)${holeNote}`;
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
    const holeOfSuit = holeCards.filter((c) => cSuit(c) === s);
    if (cards.length >= 5) { madeFlush = true; flushParts.push(`FLUSH made (${suitName[s]}; hero's hole cards: ${holeOfSuit.join(" ")})`); }
    else if (cards.length === 4) flushParts.push(`FLUSH DRAW (${suitName[s]}, 9 outs; hero's hole cards of this suit: ${holeOfSuit.join(" ")}) [all: ${cards.join(" ")}]`);
    else if (cards.length === 3) flushParts.push(`backdoor flush draw only (${suitName[s]}; hero's hole cards of this suit: ${holeOfSuit.join(" ")}) [all: ${cards.join(" ")}]`);
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
    madeHand = straightLine; // already detailed above
  } else if (trips.length > 0) {
    const tr = trips[0];
    const isSet = holeRanks[0] === holeRanks[1] && holeRanks[0] === tr;
    madeHand = isSet ? `SET (pocket ${tr}s, hole cards: ${holeCards.join(" ")})` : `TRIPS (three ${tr}s; hero's hole card: ${holeCards.find((c) => cRank(c) === tr) ?? "?"}; other hole card: ${holeCards.find((c) => cRank(c) !== tr) ?? "?"})`;
  } else if (pairs.length >= 2) {
    const h0 = holeCards.find((c) => cRank(c) === pairs[0]);
    const h1 = holeCards.find((c) => cRank(c) === pairs[1]);
    const desc = h0 && h1 ? ` (both from hole cards)` : h0 || h1 ? ` (one from hole card ${h0 ?? h1})` : ` (both from board; hero plays kicker)`;
    madeHand = `TWO PAIR (${pairs[0]}s and ${pairs[1]}s${desc})`;
  } else if (pairs.length === 1) {
    const pr = pairs[0];
    const pv = RANK_VAL[pr] ?? 0;
    if (holeRanks[0] === holeRanks[1] && holeRanks[0] === pr) {
      const topBoard = boardVals[0] ?? 0;
      madeHand = pv > topBoard ? `OVERPAIR (pocket ${pr}s, hole cards: ${holeCards.join(" ")})` : `UNDERPAIR (pocket ${pr}s, hole cards: ${holeCards.join(" ")})`;
    } else if (boardRanks.filter((r) => r === pr).length === 2) {
      const bestHole = [...holeRanks].sort((a, b) => (RANK_VAL[b] ?? 0) - (RANK_VAL[a] ?? 0))[0];
      madeHand = `BOARD PAIR of ${pr}s (hero plays kicker ${bestHole}; hole cards: ${holeCards.join(" ")})`;
    } else {
      const pairingHoleCard = holeCards.find((c) => cRank(c) === pr) ?? "?";
      const kicker = holeCards.find((c) => cRank(c) !== pr) ?? holeCards[1];
      const uniqueBoardVals = [...new Set(boardVals)].sort((a, b) => b - a);
      if (pv === uniqueBoardVals[0]) madeHand = `TOP PAIR (${pr}s; hole card making the pair: ${pairingHoleCard}; kicker: ${kicker})`;
      else if (uniqueBoardVals.length >= 2 && pv === uniqueBoardVals[1]) madeHand = `MIDDLE PAIR (${pr}s; hole card making the pair: ${pairingHoleCard}; kicker: ${kicker})`;
      else madeHand = `BOTTOM PAIR (${pr}s; hole card making the pair: ${pairingHoleCard}; kicker: ${kicker})`;
    }
  } else {
    const bestHole = [...holeRanks].sort((a, b) => (RANK_VAL[b] ?? 0) - (RANK_VAL[a] ?? 0))[0];
    madeHand = `HIGH CARD (best hole card: ${bestHole}; hole cards: ${holeCards.join(" ")})`;
  }

  return `[FACT — hero's hole cards: ${holeCards.join(" ")} | board cards: ${boardCards.join(" ")} | made hand: ${madeHand} | straight status: ${straightLine} | flush status: ${flushLine}. These are pre-computed ground truth. Do not contradict or alter.]`;
}

// Board-level texture facts — hand-independent constraints on what ANY player
// can hold against this board. Grounds villain-range reasoning the hero-hand
// draw summary never touches (e.g. "a set boats up" on an unpaired board).
function computeBoardSummary(boardCards: string[]): string {
  if (boardCards.length < 3) return "";
  const cRank = (c: string) => c.slice(0, -1);
  const cSuit = (c: string) => c.slice(-1);

  // ── Board pairing → full house / quads possibility ───────────────────────
  const rankCnt: Record<string, number> = {};
  for (const c of boardCards) {
    const r = cRank(c);
    rankCnt[r] = (rankCnt[r] ?? 0) + 1;
  }
  const maxRankCnt = Math.max(...Object.values(rankCnt));
  const pairedRanks = Object.values(rankCnt).filter((n) => n >= 2).length;

  // ── Suits → flush possibility ─────────────────────────────────────────────
  const suitCnt: Record<string, number> = {};
  for (const c of boardCards) {
    const s = cSuit(c);
    suitCnt[s] = (suitCnt[s] ?? 0) + 1;
  }
  const maxSuit = Math.max(...Object.values(suitCnt));
  const suitName: Record<string, string> = {
    h: "hearts", d: "diamonds", c: "clubs", s: "spades",
  };
  const flushSuit = Object.entries(suitCnt).find(([, n]) => n === maxSuit)?.[0] ?? "";

  // ── Straight possibility: enumerate every 5-rank window a player can
  // complete with at most two hole cards (board supplies >=3 of the 5 ranks).
  // Listing the EXACT windows + the ranks needed stops the model inventing
  // straights the board can't make (and denying ones it can).
  const present = new Set<number>();
  for (const c of boardCards) {
    const v = RANK_VAL[cRank(c)];
    if (v) {
      present.add(v);
      if (v === 14) present.add(1); // wheel ace
    }
  }
  const rankLabel = (v: number) => VAL_RANK[v === 1 ? 14 : v];
  const straightWindows: string[] = [];
  for (let low = 1; low <= 10; low++) {
    const win: number[] = [];
    for (let v = low; v < low + 5; v++) win.push(v);
    const need = win.filter((v) => !present.has(v));
    // board supplies >=3 ranks (5 - need.length >= 3) → makeable with 2 cards
    if (need.length <= 2) {
      const label = win.map(rankLabel).join("-");
      const needStr = need.length === 0
        ? "already on the board"
        : need.length === 1
          ? `needs a ${rankLabel(need[0])}`
          : `needs ${need.map(rankLabel).join("+")}`;
      straightWindows.push(`${label} (${needStr})`);
    }
  }
  const straightPossible = straightWindows.length > 0;

  const parts: string[] = [];
  if (maxRankCnt >= 4) {
    parts.push("the board itself shows QUADS");
  } else if (maxRankCnt === 3) {
    parts.push("the board is TRIPLED — a full house or quads is possible");
  } else if (maxRankCnt === 2) {
    parts.push(pairedRanks >= 2
      ? "the board is DOUBLE-PAIRED — a full house is possible (and quads with the case card)"
      : "the board is PAIRED — a full house (a set plus the board pair) or quads is possible");
  } else {
    parts.push("the board is UNPAIRED — NO full house and NO quads is possible for ANY hand; a set does NOT improve to a full house here");
  }

  if (maxSuit >= 5) {
    parts.push(`all five board cards share ${suitName[flushSuit]} — a flush is on the board`);
  } else if (maxSuit === 4) {
    parts.push(`four ${suitName[flushSuit]} are on the board — a single ${suitName[flushSuit].slice(0, -1)} card makes a flush`);
  } else if (maxSuit === 3) {
    parts.push(`three ${suitName[flushSuit]} are present — a flush is possible (needs two ${suitName[flushSuit]} hole cards)`);
  } else {
    parts.push("no flush is possible (no suit has three or more cards on the board)");
  }

  parts.push(straightPossible
    ? `the ONLY possible straights are ${straightWindows.join(", ")} — no other straight exists on this board, so do not name one`
    : "no straight is possible");

  return `[FACT — Board texture (${boardCards.join(" ")}): ${parts.join("; ")}. Do NOT credit any hand — hero's or villain's — with a category the board does not allow.]`;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

function buildPrompt(
  hand: PokerHand,
  reads: PlayerRead[],
  equityFacts: string[] = [],
): { prompt: string; facts: string[] } {
  const { tableSetup: ts, players, streets } = hand;
  const seatMap = new Map(players.map((p) => [p.seat, p]));
  const readMap = new Map(reads.map((r) => [r.playerLabel.toLowerCase(), r]));

  const hero = players.find((p) => p.isHero);
  const heroPos = hero ? positionName(hero.seat, ts) : "?";
  const heroCards = hero?.holeCards?.join(" ") ?? "??";
  const board = streets.flatMap((s) => s.communityCards);

  const heroEffBb = hero && ts.bigBlind > 0
    ? Math.floor(hero.stack / ts.bigBlind)
    : null;

  const stageLabels: Record<string, string> = {
    early: "Early stages (Day 1/2)",
    middle: "Middle stages",
    late: "Late stages",
    bubble: "ON THE BUBBLE — ICM pressure critical",
    itm: "In the money (ITM)",
    ft_bubble: "FINAL TABLE BUBBLE — extreme ICM pressure",
    final_table: "Final table",
  };
  const stageLabel = hand.tournamentStage ? (stageLabels[hand.tournamentStage] ?? hand.tournamentStage) : null;
  const isTournament = !!stageLabel || ts.ante != null;

  const blindStr = isTournament
    ? `${ts.smallBlind}/${ts.bigBlind}${ts.ante != null ? ` (ante ${ts.ante})` : ""}`
    : `$${ts.smallBlind}/$${ts.bigBlind}${ts.straddle ? `/$${ts.straddle}` : ""}`;

  const stackStr = isTournament
    ? `${hero?.stack ?? "?"} chips${heroEffBb != null ? ` (${heroEffBb}bb effective)` : ""}`
    : `$${hero?.stack ?? "?"}`;

  const lines: string[] = [
    "HAND TO ANALYZE:",
    `Hero: [${heroCards}] in ${heroPos} | ${ts.numSeats}-handed | ${blindStr} blinds | Starting stack ${stackStr}`,
  ];

  if (stageLabel) {
    lines.push(`Tournament stage: ${stageLabel}`);
  }

  // Opponents — show reads where available
  const opponents = players.filter((p) => !p.isHero);
  if (opponents.length > 0) {
    lines.push("Opponents:");
    for (const p of opponents) {
      const pos = positionName(p.seat, ts);
      const r = readMap.get(p.name.toLowerCase());
      if (r) {
        const tagStr = r.tags.length ? ` [${r.tags.join(", ")}]` : "";
        const noteStr = r.notes ? ` — "${r.notes}"` : "";
        lines.push(`  ${p.name}(${pos}) — $${p.stack} stack${tagStr}${noteStr}`);
      } else {
        lines.push(`  ${p.name}(${pos}) — $${p.stack} stack — no read, use GTO defaults`);
      }
    }
  }

  if (board.length) lines.push(`Final board: ${board.join(" ")}`);

  // Street-by-street action log with pre-computed draw facts and pot tracking.
  // `amount` on HandAction is always the player's CUMULATIVE total contribution
  // for that street (not an incremental bet/call size). We track per-player
  // running totals so we can show incremental call amounts and inject the pot
  // size at each street header.
  const boardSoFar: string[] = [];
  let runningPot = 0;
  // Collected so the client can show "what the AI was told" verbatim.
  const facts: string[] = [];

  for (const street of streets) {
    boardSoFar.push(...street.communityCards);
    const label = street.street.toUpperCase();
    const cc = street.communityCards.length
      ? ` [${street.communityCards.join(" ")}]`
      : "";

    const potBeforeStreet = runningPot;
    // Per-player cumulative contributions on this street (reset each street)
    const streetContrib = new Map<number, number>();
    // Deterministic pot-odds FACTs for hero's calls on this street — the model
    // must not compute its own (it has fabricated wildly wrong percentages).
    const streetPotOdds: string[] = [];

    const actionParts: string[] = [];
    for (const a of street.actions) {
      const p = seatMap.get(a.seat);
      if (!p) continue;
      const who = p.isHero ? "Hero" : p.name;
      const pos = positionName(a.seat, ts);
      const whoStr = `${who}(${pos})`;

      let actionStr: string;
      if (a.amount != null && a.amount > 0) {
        const prevContrib = streetContrib.get(a.seat) ?? 0;
        const increment = Math.max(0, a.amount - prevContrib);
        streetContrib.set(a.seat, a.amount);
        runningPot += increment;

        // Hero calling a wager: emit the exact break-even price. runningPot now
        // includes hero's call AND the bet(s) hero is facing. When hero calls
        // all-in for LESS than a villain's bet, the uncalled excess is returned
        // (or side-potted) and is NOT part of the pot hero is getting odds on —
        // so subtract, from every other player, whatever they put in beyond
        // hero's matched amount this street. potBefore is then the live pot hero
        // can actually win; required equity = call / (potBefore + call).
        if (p.isHero && a.type === "call" && increment > 0) {
          const heroStreetTotal = a.amount;
          let uncalledExcess = 0;
          for (const [seat, contrib] of streetContrib) {
            if (seat !== a.seat && contrib > heroStreetTotal) {
              uncalledExcess += contrib - heroStreetTotal;
            }
          }
          const potBefore = runningPot - increment - uncalledExcess;
          const reqPct = Math.round((increment / (potBefore + increment)) * 100);

          // Direct pot odds are DECISIVE only when hero faces NO further
          // betting decision after this call — either it closes a river bet
          // (hand ends at showdown) or hero's own call is all-in (hero is
          // committed and the board just runs out). In both cases the street's
          // equity FACT already is hero's equity to showdown, so the price is a
          // verdict. Otherwise (hero has chips behind, more betting/streets to
          // come) implied / reverse-implied odds apply and the price is only a
          // floor; the FACT says which so the model applies the right rule.
          // NOTE: only HERO being all-in counts — another player's all-in does
          // not stop hero and a remaining deep player from betting a side pot
          // on later streets, so it must not be treated as decisive.
          const idx = street.actions.indexOf(a);
          const closesAction = street.actions
            .slice(idx + 1)
            .every((x) => x.type === "fold");
          const heroAllIn = a.allIn === true;
          const decisive =
            closesAction && (street.street === "river" || heroAllIn);
          const decisiveReason = street.street === "river"
            ? "the hand ends at showdown"
            : "hero is all-in, so the board simply runs out with no more betting decisions for hero";

          streetPotOdds.push(
            decisive
              ? `[FACT — Price for hero to call on the ${street.street}: call ${increment} into a ${potBefore} pot, so hero needs ~${reqPct}% equity to break even. After this call there is no further betting — ${decisiveReason} — so direct pot odds are DECISIVE: hero's equity FACT for this street is hero's equity all the way to showdown, so if it is at or above ${reqPct}%, calling is correct and is never a leak; if it is below ${reqPct}%, folding is correct. Use this number verbatim; do NOT compute your own pot-odds percentage.]`
              : `[FACT — Price for hero to call on the ${street.street}: call ${increment} into a ${potBefore} pot, so hero needs ~${reqPct}% direct equity to break even right now. This is a FLOOR, not the whole decision: betting and/or later streets remain, so implied odds (hero wins more when ahead) and reverse-implied odds (hero loses more when behind, or gets blown off the hand) also apply — meeting ${reqPct}% is necessary but not automatically sufficient, and falling slightly short can still be a call when implied odds are strong. Use this number verbatim; do NOT compute your own pot-odds percentage.]`,
          );
        }

        switch (a.type) {
          case "call":
            // Show incremental amount: "BB calls 6" not "BB calls 8" when BB already posted 2
            actionStr = `${whoStr} calls ${increment}`;
            break;
          case "raise":
            // Show total raise size (standard convention: "raises to X")
            actionStr = a.openingBet
              ? `${whoStr} bets ${a.amount}`
              : `${whoStr} raises to ${a.amount}${a.allIn ? " (all-in)" : ""}`;
            break;
          case "allIn":
            actionStr = `${whoStr} all-in for ${a.amount}`;
            break;
          case "post":
            actionStr = `${whoStr} posts ${a.amount}`;
            break;
          case "postStraddle":
            actionStr = `${whoStr} straddles ${a.amount}`;
            break;
          default:
            actionStr = `${whoStr} ${a.type} ${a.amount}`;
        }
      } else {
        switch (a.type) {
          case "fold": actionStr = `${whoStr} folds`; break;
          case "check": actionStr = `${whoStr} checks`; break;
          default: actionStr = `${whoStr} ${a.type}`; break;
        }
      }
      actionParts.push(actionStr);
    }

    const potLabel = potBeforeStreet > 0 ? ` (pot: ${potBeforeStreet})` : "";
    lines.push(`${label}${cc}${potLabel}: ${actionParts.join("; ")}`);

    // Board-texture FACT first (what's possible for anyone), then hero's
    // specific made hand / draws.
    if (boardSoFar.length >= 3) {
      const boardFact = computeBoardSummary(boardSoFar);
      if (boardFact) {
        lines.push(boardFact);
        facts.push(boardFact);
      }
    }
    if (hero?.holeCards?.length === 2 && boardSoFar.length > 0) {
      const fact = computeDrawSummary(hero.holeCards, boardSoFar);
      lines.push(fact);
      facts.push(fact);
    }
    // Pot-odds FACTs for hero's calls on this street (after the texture/draw
    // facts so they sit next to the street they apply to).
    for (const f of streetPotOdds) {
      lines.push(f);
      facts.push(f);
    }
  }

  if (hand.notes) lines.push(`Hand note: "${hand.notes}"`);

  // Deterministic equity cross-check (computed on-device, passed in the
  // request) — ground truth the coaching must agree with. Appended after the
  // hand context so the model reads it before the analysis instruction.
  for (const f of equityFacts) {
    lines.push(f);
    facts.push(f);
  }

  lines.push(
    "",
    "Analyze each street hero reached. When a read or tag exists for an opponent, base optimal play on that player profile (exploit accordingly). When no read exists, use GTO population defaults and state this. Use null for streets not reached.",
  );

  return { prompt: lines.join("\n"), facts };
}

// ── System prompt (cached) ────────────────────────────────────────────────────

const SYSTEM_PROMPT =
  `You are an expert poker coach with deep knowledge of No-Limit Hold'em strategy at all stakes. Your coaching philosophy blends GTO foundations with practical exploitation of opponent tendencies.

EXPERTISE AREAS:
1. Preflop ranges: opening, 3-betting, 4-betting, defending from all positions in 6-max and full-ring. Know solver-approved frequencies and adjust for live players who deviate from GTO.
2. Postflop: c-bet frequencies by board texture (dry/wet/paired/monotone), probe bets, check-raises, pot control, thin value, bluff selection. Think in ranges.
3. Opponent exploitation: when reads or tags exist, shift from GTO toward exploitative plays — size up vs calling stations, bluff less vs stations, 3-bet wider vs nits, etc.
4. Bet sizing: pot geometry, SPR, protection, polarisation vs merged ranges, sizing tells.

COACHING PRINCIPLES:
- Be specific. Reference actual cards, board texture, stack depth, position, and opponent tags in every coaching point.
- When a read exists: always name the player and tag ("Justin is tagged Calling Station — bluffing river is -EV, valuebet thin instead").
- When no read exists: state you are using GTO population defaults.
- keyMistake must be the single highest-impact error in the hand, written in 1-2 sentences, and it MUST reconcile with the per-street cards and the pot-odds rule below: it can only name a street you marked non-GTO (wasGto:false), and it must NOT call a decision a mistake that the equity/pot-odds FACTs show was correct. If every street was fine — including a call whose equity FACT meets its pot-odds price — set keyMistake to null and set verdict to highEV or neutral (never leakDetected).
- confidence per street: "high" only for standard spots with a well-established answer; "medium" when the verdict depends on reads or assumptions; "low" when the spot is genuinely close or key information is missing. Do not default everything to high.
- alternative per street: when a second line is genuinely defensible, state it in one sentence. Set it to null when the optimal play is clearly unique — do not invent alternatives for trivial spots.
- BE CONCISE: keep each rationale to roughly 3-4 sentences. State your conclusions about hero's made hand, the relevant draws, and villain's range. Do NOT spell out your rank-by-rank straight-window enumeration, pot-odds arithmetic, or other step-by-step working in the output — that reasoning is silent scratch work. A wall of "67 makes 4-5-6-7 needing a 3 or 8, 78 makes…" is a leak, not coaching.

RANGE-VS-EQUITY CONSISTENCY (critical — your recommendation MUST agree with the range you describe):
- Before calling any FOLD a mistake, confirm hero's hand actually beats a meaningful share of the villain range you just enumerated. If hero's hand loses to (almost) the entire range you listed, then FOLDING IS CORRECT — never label it an over-fold, and never claim hero "retains showdown value." A hand that beats nothing in the range has ~0% equity no matter how few bluffs villain has.
- Pot odds justify a call ONLY when hero's real equity against that range meets them. State hero's rough equity vs the range before invoking pot odds; do not assert an overpair/bluff-catcher "has enough showdown value" without checking it against the specific made hands you enumerated.
- "Villain rarely bluffs" makes calling WORSE, not better, when hero loses to villain's value hands: a non-bluffing range means a bluff-catcher beats nothing. Against nits and value-heavy players, exploitatively fold MORE to their aggression — their raises/shoves are near-pure value. The "don't over-fold vs nits" idea applies only to folding hands that still beat part of their value range, never to folding to a range that dominates hero.
- The CONVERSE is equally important — do NOT over-fold a +EV call. When a "Price for hero to call" FACT is present, hero's call CLOSES the action (e.g. calling a river bet), and hero's equity FACT meets or exceeds the required %, the call is CORRECT by direct pot odds: mark the street as fine (wasGto-aligned), never label it a leak, and do not recommend folding on vague "feels value-heavy / a GTO-default range skews to value / no reason to deviate" grounds. The equity FACT already counts villain's bluffs — if it clears the price, the bluff-catch is profitable. Recommend a fold over a price-meeting call ONLY when hero's equity is BELOW the required %, or (on a non-closing street) when a specific implied/reverse-implied-odds reason makes the direct price misleading — and then state that reason explicitly.
- Self-check before writing: (a) if your rationale enumerates hands and then recommends the opposite of what beating-or-losing-to those hands implies, fix it; (b) if you recommend a FOLD while hero's equity FACT meets or beats the pot-odds FACT on a closing-action call, fix it — that is the over-fold error; (c) keyMistake, the overall verdict, and every per-street optimal/wasGto must tell ONE consistent story — never call a decision a mistake in one field and correct in another.

TOURNAMENT COACHING (applies when tournament stage is provided):
5. ICM AWARENESS: When tournament stage is "bubble", "ft_bubble", or "final_table", ICM pressure fundamentally changes correct play. Calling off a big stack near the bubble is often a mistake even with strong equity. Pushing ranges tighten; calling ranges tighten more. State ICM implications explicitly.
6. STACK DEPTH IN BBs: Always frame decisions in terms of effective BBs, not chip counts. Push/fold charts apply sub-15bb. Shove/call ranges apply sub-25bb. Deep-stack play applies 50bb+.
7. TOURNAMENT-SPECIFIC ERRORS: Common leaks include: (a) calling off too wide near bubble, (b) not exploiting short stacks' ICM pain, (c) min-raising with a short stack when shoving is correct, (d) passing up chip equity for survival when chip equity is correct.

ACCURACY RULES:
1. CARD ACCURACY: Reproduce hole cards and board cards exactly as given. Never alter rank or suit.
2. BET-COUNTING: BB post is not a raise. A straddle post is also a blind, not a raise — the first raise after a straddle is still the open (2-bet). Open-raise = 2-bet, re-raise = 3-bet, re-raise over 3-bet = 4-bet, jam or raise over 4-bet = 5-bet. Never miscategorise.
2a. STRADDLES: The player marked STR posted a blind straddle. They act last preflop and defend like a big blind — wide, with a price discount — never assign them an early-position opening range just because they sit in the UTG seat. Postflop they are usually out of position. Straddle pots play at half the effective depth: frame stack-depth reasoning in straddle units when a straddle is present.
3. TEXT FORMATTING: Plain prose only. No escape characters (\\n, \\t), no markdown, no bullet symbols inside string fields.
4. HAND READING — silently work through these steps before writing any output field. Never include this reasoning in your output — only state the conclusions:

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

   STEP 5 — NEVER invent draws or made hands not supported by the cards listed in steps 1–4.

5. BOARD-TEXTURE CONSTRAINTS — apply to EVERY player's hand, hero AND villains alike, and honor the "Board texture" FACT line:
   • A full house or quads is possible ONLY when the board is paired or tripled. On an UNPAIRED board no one can have a full house or quads — a set does NOT become a full house unless the board itself pairs. Never list "full houses" or "boats" in a villain range on an unpaired board.
   • A flush is possible only when three or more cards of one suit are on the board; with two or fewer of every suit, no flush exists for anyone.
   • A straight is possible only when the board supplies enough connected ranks (three within a five-rank window).
   • When you enumerate a villain's value range, every hand you name must be makeable from two hole cards plus this exact board. If the board does not allow a category, do not put it in the range.

6. RESULT-INDEPENDENCE & GROUNDED NUMBERS:
   • You are NOT told who won the hand. Unless a villain's hole cards are explicitly listed in the input, you do not know them — reason only from ranges and the provided equity FACTs. Never assume hero won or lost, and never let an imagined outcome shade the verdict. Evaluate the decision on the information available when it was made.
   • The "Hero equity vs the modeled villain range" FACT already accounts for a GTO-balanced share of villain bluffs. Treat it as the true bluff-catch equity. Do not silently override it with a gut feeling that "villain always has it."
   • When a "Price for hero to call" FACT is present, use its stated threshold exactly as given — do NOT compute your own pot-odds percentage (your arithmetic has been unreliable). Follow the FACT's own framing: if it says the price is DECISIVE (no further betting can follow — a river call that closes the hand, or a call where hero is all-in and the board just runs out), then equity at or above the threshold means calling is correct and below means folding is correct — full stop. This applies on ANY street: a flop or turn call where hero is all-in is decided purely by whether hero's equity meets the price, never by implied odds. If it says the price is a FLOOR (a non-closing call with betting still to come), meeting the threshold is necessary but NOT automatically sufficient — implied and reverse-implied odds still apply, so a call can be right slightly under the price or a fold right slightly over it; in that case justify the deviation with a specific implied/reverse-implied-odds reason, not a vague "feels value-heavy". Never bless a preflop limp, complete, or cold-call purely because it clears the FLOOR price. State the comparison in one short clause, not a derivation.`;

// A stable signature of the reads that drive the analysis (and the modeled
// equity). The cache is keyed on (user_id, hand_id), but reads also shape the
// coaching and the injected equity FACTs — so a cached analysis is only valid
// if it was produced under the same reads. Stored in analysis_json so no
// schema change is needed; the client ignores the underscore-prefixed field.
function readsSignature(reads: PlayerRead[]): string {
  return reads
    .map((r) => `${r.playerLabel.toLowerCase()}:${[...r.tags].sort().join(",")}`)
    .sort()
    .join("|");
}

// ── Entry point ───────────────────────────────────────────────────────────────

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
      hand: PokerHand;
      reads?: PlayerRead[];
      forceRefresh?: boolean;
      equityFacts?: unknown;
    };

    const { hand, reads = [], forceRefresh = false } = body;

    if (!hand?.id) {
      return new Response(JSON.stringify({ error: "Missing required field: hand" }), {
        status: 400,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // On-device equity facts are client-computed; sanitise before trusting them
    // in the prompt (cap count + length — this is the user's own analysis, but
    // keep the payload bounded regardless).
    const equityFacts: string[] = Array.isArray(body.equityFacts)
      ? body.equityFacts
        .filter((f): f is string => typeof f === "string")
        .slice(0, 8)
        .map((f) => f.slice(0, 600))
      : [];

    // Only pass reads for opponents actually in this hand
    const opponentNames = new Set(
      hand.players.filter((p) => !p.isHero).map((p) => p.name.toLowerCase()),
    );
    const relevantReads = reads.filter((r) =>
      opponentNames.has(r.playerLabel.toLowerCase())
    );
    const sig = readsSignature(relevantReads);

    // ── Cache check ──────────────────────────────────────────────────────────
    if (!forceRefresh) {
      const { data: cached, error: cacheErr } = await db
        .from("ai_hand_analyses")
        .select("analysis_json")
        .eq("user_id", user.id)
        .eq("hand_id", hand.id)
        .maybeSingle();
      if (cacheErr) {
        console.error("ai_hand_analyses cache read failed:", cacheErr.code, cacheErr.message);
        await reportError("analyze-hand", `cache read failed: ${cacheErr.code} ${cacheErr.message}`);
      }

      // Only a cache entry produced under the SAME reads is valid — otherwise
      // the cached coaching/equity would contradict the freshly-computed
      // on-device equity chips. A reads edit (or a pre-signature legacy row)
      // falls through to a fresh analysis.
      if (cached && cached.analysis_json?._readsSignature === sig) {
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

    // ── Call Claude ──────────────────────────────────────────────────────────
    const anthropic = new Anthropic({
      apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    });

    const built = buildPrompt(hand, relevantReads, equityFacts);

    const claudeCall = anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 2000,
      temperature: 0,
      system: [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" },
        },
      ],
      tools: [COACHING_TOOL],
      tool_choice: { type: "tool", name: "provide_hand_coaching" },
      messages: [{ role: "user", content: built.prompt }],
    });

    const timeoutPromise = new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("CLAUDE_TIMEOUT")), 50000),
    );

    const message = await Promise.race([claudeCall, timeoutPromise]);

    const toolBlock = message.content.find((c) => c.type === "tool_use");
    if (!toolBlock || toolBlock.type !== "tool_use") {
      throw new Error("Model did not return coaching tool call");
    }
    // deno-lint-ignore no-explicit-any
    const analysis = (toolBlock as any).input as Record<string, unknown>;
    // Attach the deterministic [FACT] lines so the client can show "what the
    // AI was told" verbatim — not model output, never trusted to the model.
    analysis.facts = built.facts;
    // Stamp the reads signature so the cache entry is only reused under the
    // same reads (see readsSignature). Client ignores underscore-prefixed keys.
    analysis._readsSignature = sig;

    // ── Log usage ────────────────────────────────────────────────────────────
    await logUsage(db, user.id, message.usage);

    // ── Cache result ─────────────────────────────────────────────────────────
    const { error: cacheWriteErr } = await db.from("ai_hand_analyses").upsert(
      {
        user_id: user.id,
        hand_id: hand.id,
        analysis_json: analysis,
        model_used: "claude-sonnet-4-6",
        tokens_used: message.usage.input_tokens + message.usage.output_tokens,
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
        cache_read_tokens: message.usage.cache_read_input_tokens ?? 0,
        cache_write_tokens: message.usage.cache_creation_input_tokens ?? 0,
      },
      { onConflict: "user_id,hand_id" },
    );
    if (cacheWriteErr) {
      console.error("ai_hand_analyses upsert failed:", cacheWriteErr.code, cacheWriteErr.message);
      // A failed cache write means the next identical request pays for a fresh
      // Claude call (the exact FK bug that bit the smoke test). Alert.
      await reportError("analyze-hand", `ai_hand_analyses upsert failed: ${cacheWriteErr.code} ${cacheWriteErr.message}`);
    }

    return new Response(JSON.stringify(analysis), {
      headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("analyze-hand error:", msg);
    await reportError("analyze-hand", msg);
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
