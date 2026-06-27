// Pure prompt-assembly for analyze-hand — extracted from index.ts so the eval
// harness (tool/eval/score.ts) can import buildPrompt/SYSTEM_PROMPT/COACHING_TOOL
// without booting the Edge Function's serve() entry point. No side effects, no
// network/DB. index.ts re-uses everything here verbatim — keep prod and the
// eval scorer on ONE copy of the prompt (a second copy would silently drift).

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

export interface PokerHand {
  id: string;
  tableSetup: TableSetup;
  players: HandPlayer[];
  streets: StreetData[];
  notes?: string;
  tournamentStage?: string;
}

export interface PlayerRead {
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
export const COACHING_TOOL: any = {
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

// Board VOLATILITY (DCE Tier A, board-volatility factor): a deterministic COUNT of
// how many unseen next cards change the board's category possibilities (advance a
// flush, open a new straight window, or pair the board) → a STATIC (dry) vs DYNAMIC
// (wet) label the SIZING rule keys off. The COUNT is deterministic, but the
// STATIC/DYNAMIC label is a SOFT classification at the calibrated 0.50 threshold, so
// it ships as a [HEURISTIC —] line (like EQR/SPR), NOT a hard [FACT —] — the model
// must not be told it can never contradict a borderline label. Board-only +
// hand-independent (matches the calibration, which counted board-only). Mirrors
// lib/equity/decision_context.dart's boardDynamism (the Dart oracle) — keep in sync.
// Empty pre-flop / on the river (no next card). Threshold solver-calibrated; see
// tool/solver/VOLATILITY_FINDINGS.md.
const BOARD_DYNAMIC_THRESHOLD = 0.5;

function computeBoardDynamism(boardCards: string[]): string {
  if (boardCards.length !== 3 && boardCards.length !== 4) return "";
  const cRank = (c: string) => c.slice(0, -1);
  const cSuit = (c: string) => c.slice(-1);
  const RANKS = Object.keys(RANK_VAL); // "2".."A"
  const SUITS = ["c", "d", "h", "s"];

  const boardSet = new Set(boardCards);
  const boardRanks = new Set(boardCards.map(cRank));
  const suitCount: Record<string, number> = {};
  for (const c of boardCards) {
    const s = cSuit(c);
    suitCount[s] = (suitCount[s] ?? 0) + 1;
  }

  const presentVals = (cards: string[]) => {
    const p = new Set<number>();
    for (const c of cards) {
      const v = RANK_VAL[cRank(c)];
      if (v) {
        p.add(v);
        if (v === 14) p.add(1); // wheel ace plays low
      }
    }
    return p;
  };
  const supplyWindows = (present: Set<number>) => {
    const w = new Set<number>();
    for (let low = 1; low <= 10; low++) {
      let n = 0;
      for (let v = low; v < low + 5; v++) if (present.has(v)) n++;
      if (n >= 3) w.add(low);
    }
    return w;
  };
  const baseWindows = supplyWindows(presentVals(boardCards));

  let unseen = 0;
  let dynamic = 0;
  for (const r of RANKS) {
    for (const s of SUITS) {
      const card = r + s;
      if (boardSet.has(card)) continue;
      unseen++;
      const pairs = boardRanks.has(r);
      const flush = (suitCount[s] ?? 0) >= 2;
      const straight =
        supplyWindows(presentVals([...boardCards, card])).size > baseWindows.size;
      if (pairs || flush || straight) dynamic++;
    }
  }
  const frac = unseen === 0 ? 0 : dynamic / unseen;
  const label = frac >= BOARD_DYNAMIC_THRESHOLD ? "DYNAMIC (wet)" : "STATIC (dry)";
  const nextStreet = boardCards.length === 3 ? "turn" : "river";
  return `[HEURISTIC — Board dynamism (${boardCards.join(" ")}): ${dynamic} of ${unseen} unseen ${nextStreet} cards change the board (advance a flush, open a new straight, or pair it). This reads as a ${label} board — a calibrated classification, not a hard fact.]`;
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

// Postflop action runs clockwise from the SB (first seat left of the button),
// so the player closest to the button on its RIGHT acts last = is in position.
// Index 0 = first to act postflop, numSeats-1 = the button (last). Higher index
// = acts later = more in position. (Heads-up: BB acts first, button last — the
// same formula, since SB == button there.)
function postflopOrderIndex(seat: number, ts: TableSetup): number {
  const N = ts.numSeats;
  return (seat - (ts.buttonSeat + 1) + N) % N;
}

// FIX 1 — deterministic relative-position FACT. The model has stated hero's
// in/out-of-position relationship BACKWARDS (called a CO "out of position" vs
// the BB). Pin it from the seats so it can't. Only the opponents who saw the
// flop (didn't fold preflop) are relevant; emitted only when hero reached a
// postflop street.
function relativePositionFact(
  hand: PokerHand,
  ts: TableSetup,
  hero: HandPlayer | undefined,
): string | null {
  if (!hero || hand.streets.length < 2) return null;
  const pre = hand.streets[0];
  const foldedPre = new Set<number>();
  if (pre) for (const a of pre.actions) if (a.type === "fold") foldedPre.add(a.seat);
  if (foldedPre.has(hero.seat)) return null; // hero out preflop — no postflop position
  const heroIdx = postflopOrderIndex(hero.seat, ts);
  const heroPos = positionName(hero.seat, ts);
  const ipOver: string[] = []; // hero acts AFTER these (in position on them)
  const oopTo: string[] = []; // hero acts BEFORE these (out of position to them)
  for (const o of hand.players) {
    if (o.isHero || foldedPre.has(o.seat)) continue;
    (heroIdx > postflopOrderIndex(o.seat, ts) ? ipOver : oopTo).push(
      positionName(o.seat, ts),
    );
  }
  if (ipOver.length === 0 && oopTo.length === 0) return null;
  const parts: string[] = [];
  if (ipOver.length) {
    parts.push(`acts AFTER ${ipOver.join(", ")} → Hero is IN POSITION on ${ipOver.length > 1 ? "them" : "that opponent"}`);
  }
  if (oopTo.length) {
    parts.push(`acts BEFORE ${oopTo.join(", ")} → Hero is OUT OF POSITION to ${oopTo.length > 1 ? "them" : "that opponent"}`);
  }
  return `[FACT — Postflop position: Hero(${heroPos}) ${parts.join("; ")}. This is fixed by the seats; do NOT state hero's position the other way round (the player who acts last postflop is in position).]`;
}

// FIX 2 — deterministic preflop-roles FACT. The model has mislabeled the
// 3-bettor's range as a "calling range" (it swapped who raised vs who called).
// Pin the last preflop aggressor and hero's role from the action. Emitted only
// when there was at least one preflop raise (limped pots have no aggressor to
// confuse) and hero did not fold preflop.
function preflopRolesFact(
  hand: PokerHand,
  ts: TableSetup,
  hero: HandPlayer | undefined,
): string | null {
  if (!hero) return null;
  const pre = hand.streets[0];
  if (!pre) return null;
  // Each preflop raise escalates the bet level: 1st raise = open (2-bet),
  // 2nd = 3-bet, 3rd = 4-bet, … (an all-in raise counts as a raise).
  const raises: { seat: number; level: number }[] = [];
  let heroFinal: string | null = null;
  // The level of hero's OWN highest raise, if hero ever raised preflop — so a
  // hero who 3-bet and then called a 4-bet isn't mislabeled a capped caller.
  let heroRaiseLevel: number | null = null;
  for (const a of pre.actions) {
    if (a.type === "raise" || a.type === "allIn") {
      const level = raises.length + 2;
      raises.push({ seat: a.seat, level });
      if (a.seat === hero.seat) heroRaiseLevel = level;
    }
    if (a.seat === hero.seat && a.type !== "post" && a.type !== "postStraddle") {
      heroFinal = a.type;
    }
  }
  if (raises.length === 0 || heroFinal === "fold") return null;
  const last = raises[raises.length - 1];
  const levelLabel = (lvl: number) => lvl === 2 ? "open (2-bet)" : `${lvl}-bet`;
  const lvl = levelLabel(last.level);
  const aggrPos = positionName(last.seat, ts);
  const heroPos = positionName(hero.seat, ts);
  let heroClause: string;
  if (last.seat === hero.seat) {
    heroClause = `Hero(${heroPos}) made that ${lvl} and IS the preflop aggressor`;
  } else if (heroRaiseLevel != null) {
    // Hero raised earlier (e.g. 3-bet) then called a bigger raise — a strong
    // raise-and-call range, NOT a capped flat-calling range.
    heroClause =
      `Hero(${heroPos}) ${levelLabel(heroRaiseLevel)} then called the ${lvl} — a strong raise-and-call range, NOT a capped flat-calling range`;
  } else {
    heroClause =
      `Hero(${heroPos}) only called the ${lvl} and is the CALLER, holding a capped calling range`;
  }
  return `[FACT — Preflop roles: the last preflop raise was a ${lvl} by ${aggrPos}; ${heroClause}. The ${lvl} player is the aggressor; describe each player's range by the strongest action they took (raise = raising range, call-only = calling range). Do NOT describe a player who raised as having a 'calling range', and do not swap who raised vs who called.]`;
}

// Shared pot-odds math + FACT wording for any spot where hero faces a wager.
// Both the call site (hero continued) and the fold site (hero gave up, but we
// still want the break-even he was offered) resolve their inputs and call this,
// so the price formula, the uncalled-excess strip, and the DECISIVE/FLOOR
// wording live in ONE place and can never drift apart (they previously did:
// the fold path was missing the stack cap + excess strip the call path had).
//   • callAmount        — hero's effective chips to continue. The call caller
//     passes the real (already-recorded, inherently ≤ stack) call; the fold
//     caller reconstructs it and must stack-cap it itself (it has no recorded
//     amount). The helper does NOT cap — pass a value hero could actually put in.
//   • livePotBeforeCall  — pot hero can win EXCLUDING his own call, before the strip
//   • heroMatchTotal     — hero's total this-street contribution if he continues
// The caller decides `decisive` (no further betting decision for hero) and the
// cause clause; this function only formats and computes the price.
function heroPotOddsFact(opts: {
  street: string;
  mode: "call" | "fold";
  callAmount: number;
  livePotBeforeCall: number;
  heroMatchTotal: number;
  streetContrib: Map<number, number>;
  heroSeat: number;
  decisive: boolean;
  decisiveReason: string;
}): string {
  let uncalledExcess = 0;
  for (const [seat, contrib] of opts.streetContrib) {
    if (seat !== opts.heroSeat && contrib > opts.heroMatchTotal) {
      uncalledExcess += contrib - opts.heroMatchTotal;
    }
  }
  const potBefore = opts.livePotBeforeCall - uncalledExcess;
  const reqPct = Math.round(
    (opts.callAmount / (potBefore + opts.callAmount)) * 100,
  );
  const isFold = opts.mode === "fold";
  const lead = isFold
    ? `Price hero was getting when he folded on the ${opts.street}: to call ${opts.callAmount}`
    : `Price for hero to call on the ${opts.street}: call ${opts.callAmount}`;
  const needs = isFold ? "needed" : "needs";
  if (opts.decisive) {
    const verdict = isFold
      ? `if it is at or above ${reqPct}%, folding was a mistake (an over-fold) and calling was correct; if it is below ${reqPct}%, folding was correct`
      : `if it is at or above ${reqPct}%, calling is correct and is never a leak; if it is below ${reqPct}%, folding is correct`;
    return `[FACT — ${lead} into a ${potBefore} pot, so hero ${needs} ~${reqPct}% equity to break even. Because ${opts.decisiveReason}, direct pot odds are DECISIVE: hero's equity FACT for this street is hero's equity all the way to showdown, so ${verdict}. Use this number verbatim; do NOT compute your own pot-odds percentage.]`;
  }
  const floorBody = isFold
    ? `betting and/or later streets remain, so folding can still be correct below it when hero realises his equity poorly, and a large surplus over ${reqPct}% points to an over-fold`
    : `betting and/or later streets remain, so implied odds (hero wins more when ahead) and reverse-implied odds (hero loses more when behind, or gets blown off the hand) also apply — meeting ${reqPct}% is necessary but not automatically sufficient, and falling slightly short can still be a call when implied odds are strong`;
  return `[FACT — ${lead} into a ${potBefore} pot, so hero ${needs} ~${reqPct}% direct equity to break even right now. This is a FLOOR, not the whole decision: ${floorBody}. Use this number verbatim; do NOT compute your own pot-odds percentage.]`;
}

export function buildPrompt(
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
  // Hero's cumulative chips committed across the whole hand, so we can derive
  // his remaining stack at any point (hero.stack is the STARTING stack). Used
  // to cap a fold's pot-odds call amount at what hero could actually have put
  // in — a bet larger than hero's stack is only callable up to that stack.
  let heroPaid = 0;
  // Collected so the client can show "what the AI was told" verbatim.
  const facts: string[] = [];

  // Deterministic position + preflop-role FACTs (computed from seats + action),
  // placed before the street log so they ground the whole read. Fixes the
  // "CO is out of position vs BB" and "BB's 3-bet calling range" errors.
  for (
    const f of [
      relativePositionFact(hand, ts, hero),
      preflopRolesFact(hand, ts, hero),
    ]
  ) {
    if (f) {
      lines.push(f);
      facts.push(f);
    }
  }

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
        if (p.isHero) heroPaid += increment;

        // Hero calling a wager: emit the exact break-even price (the model must
        // not compute its own). runningPot already includes hero's call, so the
        // live pot before his call is runningPot - increment; the helper strips
        // any uncalled excess (when hero called all-in for less than the bet).
        if (p.isHero && a.type === "call" && increment > 0) {
          // Direct pot odds are DECISIVE only when hero faces NO further betting
          // decision after this call — it closes a river bet (hand ends at
          // showdown) or hero's own call is all-in (board just runs out). Only
          // HERO being all-in counts: another player's all-in does not stop hero
          // and a remaining deep player from betting a side pot on later streets.
          const idx = street.actions.indexOf(a);
          const closesAction = street.actions
            .slice(idx + 1)
            .every((x) => x.type === "fold");
          const heroAllIn = a.allIn === true;
          const decisive =
            closesAction && (street.street === "river" || heroAllIn);
          streetPotOdds.push(heroPotOddsFact({
            street: street.street,
            mode: "call",
            callAmount: increment,
            livePotBeforeCall: runningPot - increment,
            heroMatchTotal: a.amount,
            streetContrib,
            heroSeat: a.seat,
            decisive,
            decisiveReason: street.street === "river"
              ? "the hand ends at showdown"
              : "hero is already all-in and the board simply runs out with no more betting decisions",
          }));
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

        // Hero FOLDING to a wager: emit the same break-even price the fold was
        // getting, so the model judges over-folds against the correct number
        // instead of fabricating its own. Reconstruct hero's effective call
        // (capped at his remaining stack — hero.stack is the STARTING stack, so
        // hero.stack - heroPaid is what he had behind) and hand off to the shared
        // helper, which applies the same uncalled-excess strip as the call path.
        // Only when hero folded to a real WAGER (a bet/raise/all-in this street),
        // not when he merely open-folds to the posted blinds/straddle — pricing
        // a routine preflop open-fold would feed the model a meaningless price.
        const idx = p.isHero && a.type === "fold"
          ? street.actions.indexOf(a)
          : -1;
        const facedWager = idx > 0 &&
          street.actions
            .slice(0, idx)
            .some((x) => x.type === "raise" || x.type === "allIn");
        if (p.isHero && a.type === "fold" && facedWager) {
          const heroContrib = streetContrib.get(a.seat) ?? 0;
          let maxOther = 0;
          for (const [seat, contrib] of streetContrib) {
            if (seat !== a.seat && contrib > maxOther) maxOther = contrib;
          }
          const fullToCall = maxOther - heroContrib;
          const heroRemaining = typeof hero?.stack === "number"
            ? Math.max(0, hero.stack - heroPaid)
            : null;
          const callAmount = heroRemaining != null
            ? Math.min(fullToCall, heroRemaining)
            : fullToCall;
          if (callAmount > 0) {
            // DECISIVE only when the hypothetical call would leave hero no
            // further betting decision: nobody live acts behind him (the call
            // closes the action) AND either it is the river (hand ends at
            // showdown) or calling would put hero all-in (board just runs out).
            // Otherwise — a player still to act behind, or chips behind with
            // streets to come — it is only a floor. Mirrors the call-side guard.
            const closesAction = street.actions
              .slice(idx + 1)
              .every((x) => x.type === "fold");
            const heroWouldBeAllIn = heroRemaining != null &&
              fullToCall >= heroRemaining;
            const decisive = closesAction &&
              (street.street === "river" || heroWouldBeAllIn);
            streetPotOdds.push(heroPotOddsFact({
              street: street.street,
              mode: "fold",
              callAmount,
              livePotBeforeCall: runningPot,
              heroMatchTotal: heroContrib + callAmount,
              streetContrib,
              heroSeat: a.seat,
              decisive,
              decisiveReason: street.street === "river"
                ? "the fold closes the hand at showdown"
                : "calling here would put hero all-in and the board simply runs out with no more betting decisions",
            }));
          }
        }
      }
      actionParts.push(actionStr);
    }

    const potLabel = potBeforeStreet > 0 ? ` (pot: ${potBeforeStreet})` : "";
    lines.push(`${label}${cc}${potLabel}: ${actionParts.join("; ")}`);

    // NO-LOOKAHEAD FACT: when an opponent acted AFTER hero's last action on this
    // street (hero checks first → villain checks/bets behind), that later action
    // was UNKNOWN to hero when hero decided. The model otherwise rationalizes past
    // prose rules ("hero should have led because villain checked behind / capped
    // their range"), so ground it inline, next to the street, as a hard FACT.
    if (hero) {
      let lastHeroIdx = -1;
      street.actions.forEach((a, i) => {
        if (a.seat === hero.seat) lastHeroIdx = i;
      });
      // Fire only when hero's LAST action this street was a CHECK and an opponent
      // acted after it — i.e. the check-through / "villain checked behind" pattern
      // that triggers the lookahead hallucination. (If hero bet/called/raised last,
      // there's no "should have bet because villain acted behind" error to pre-empt.)
      const villainAfter = lastHeroIdx >= 0 &&
        street.actions[lastHeroIdx].type === "check" &&
        street.actions.slice(lastHeroIdx + 1).some((a) => a.seat !== hero.seat);
      if (villainAfter) {
        const lf =
          `[FACT — Action order on the ${street.street}: hero acted BEFORE the opponent's final action this street, so that later action (a check/bet/call/fold behind) was UNKNOWN to hero when hero decided. Judge hero's ${street.street} play only on what preceded it — do NOT claim hero should have bet/led/checked differently "because villain checked behind / folded / called / capped or weakened their range". Any hero lead is measured against villain's WHOLE range (the equity FACT), and is value ONLY if that equity is above ~50%; below 50% hero is behind and a bet is not value, so checking is correct.]`;
        lines.push(lf);
        facts.push(lf);
      }
    }

    // Board-texture FACT first (what's possible for anyone), then hero's
    // specific made hand / draws.
    if (boardSoFar.length >= 3) {
      const boardFact = computeBoardSummary(boardSoFar);
      if (boardFact) {
        lines.push(boardFact);
        facts.push(boardFact);
      }
      // Board dynamism (static/dynamic) — drives the sizing rule. Empty on the
      // river (no next card), so it only fires on the flop/turn.
      const dynFact = computeBoardDynamism(boardSoFar);
      if (dynFact) {
        lines.push(dynFact);
        facts.push(dynFact);
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

export const SYSTEM_PROMPT =
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
- The CONVERSE is equally important — do NOT over-fold a +EV call. When a pot-odds price FACT marks the price DECISIVE (a "Price for hero to call" FACT on a closing/all-in spot, OR a "Price hero was getting when he folded" FACT), and hero's equity FACT meets or exceeds the required %, continuing is CORRECT by direct pot odds: if hero called, mark the street fine (wasGto-aligned) and never label it a leak; if hero actually FOLDED, that fold was the over-fold error — recommend the call and mark the street non-GTO. Do not recommend folding on vague "feels value-heavy / a GTO-default range skews to value / no reason to deviate" grounds. The equity FACT already counts villain's bluffs — if it clears the price, the bluff-catch is profitable. Recommend a fold over a price-meeting call ONLY when hero's equity is BELOW the required %, or (on a non-closing street) when a specific implied/reverse-implied-odds reason makes the direct price misleading — and then state that reason explicitly.
- EQUITY REALIZATION (DCE): when a "[HEURISTIC — Equity REALIZATION]" FACT is present, it gives hero's realized equity (raw equity discounted for hero's position + hand class). Use the REALIZED figure as your read of how much equity hero actually captures for the continue / bluff-catch decision — a marginal hand out of position realizes LESS than its raw equity, a strong made hand MORE. It is a HEURISTIC, not ground truth: if it conflicts with a decisive pot-odds price FACT or the hard equity FACT, those WIN. Realization tells you how hard hero can push and how thin to value-bet — it must NOT trigger OVER-FOLDING a continue whose RAW equity already meets the pot-odds price; the over-fold protection in rule (b) still governs folds. Do not state the realized number as if it were hero's raw all-in equity.
- SPR & COMMITMENT (DCE): when a "[HEURISTIC — SPR & COMMITMENT]" FACT is present, it gives the stack-to-pot ratio per street and (heads-up) the equity needed to profitably get all-in. Use it for the call-vs-RAISE / stack-off decision, NOT the bluff-catch call/fold — pot odds govern bluff-catching. Low SPR favours getting a strong-enough made hand all-in; high SPR favours pot control with one-pair hands (do not stack off one pair at high SPR — villain's stack-off range skews to sets/two-pair, so the real requirement exceeds the raw price). The stated stack-off % is the equity to get all-in profitably versus a WILLING range, NOT hero's raw pot-odds price — never treat it as the price to call a bluff-catch. It is a HEURISTIC: a decisive pot-odds price FACT and the hard equity FACT still WIN. Multiway, the FACT omits a precise stack-off % — reason qualitatively from the SPR and the fact that hero must beat the whole field.
- BOARD DYNAMISM (DCE): a "[HEURISTIC — Board dynamism]" line flags the board as STATIC (dry) or DYNAMIC (wet) — soft texture context for your prose only. It is NEVER, by itself, a reason to mark a street wasGto:false, write a keyMistake, or set leakDetected.
- Self-check before writing: (a) if your rationale enumerates hands and then recommends the opposite of what beating-or-losing-to those hands implies, fix it; (b) if you bless a fold (or recommend folding) while hero's equity FACT meets or beats a DECISIVE pot-odds FACT — whether labelled "Price for hero to call" or "Price hero was getting when he folded" — fix it: that is the over-fold error, and the correct play is the call; (c) FIELD CONSISTENCY (mechanical — verify before returning; this is the most common self-contradiction): the verdict, keyMistake, and per-street wasGto MUST bind exactly. • If verdict=leakDetected, AT LEAST ONE street MUST be marked wasGto:false and keyMistake MUST name that street — declaring a leak while every street is wasGto:true is a contradiction. • If you write a non-null keyMistake, the street it names MUST be wasGto:false. • If EVERY street is wasGto:true, then keyMistake MUST be null and verdict MUST be highEV or neutral (never leakDetected). • A minor missed-value note on an otherwise-fine hand is verdict=neutral WITH that one street marked wasGto:false and keyMistake describing it — not leakDetected. Never call a decision a mistake in one field and correct in another.

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
   • NO LOOKAHEAD: judge each hero decision using ONLY what hero knew at that moment — never an action that came LATER in the hand. Honor any "Action order" FACT: a villain action that came AFTER hero's was unknown to hero and must not justify second-guessing hero (e.g. "hero should have led because villain checked behind / capped their range"). A lead is "value" only when the hero-equity FACT for that street is above ~50%; below 50% hero is behind and a bet is not value.
   • The "Hero equity vs the modeled villain range" FACT already accounts for a GTO-balanced share of villain bluffs. Treat it as the true bluff-catch equity. Do not silently override it with a gut feeling that "villain always has it."
   • When a pot-odds price FACT is present — either a "Price for hero to call" FACT (hero continued) or a "Price hero was getting when he folded" FACT (hero gave up) — use its stated threshold exactly as given — do NOT compute your own pot-odds percentage (your arithmetic has been unreliable). Both kinds are computed the same way and carry the same DECISIVE/FLOOR framing; the only difference is the verb. Follow the FACT's own framing: if it says the price is DECISIVE (no further betting can follow — a river spot that ends the hand, or a spot where calling leaves hero all-in and the board just runs out), then hero's equity at or above the threshold means CALLING is correct and equity below means FOLDING is correct — full stop. For a "folded" FACT that resolves to "calling was correct", hero's actual fold was the over-fold error: say so and recommend the call. This applies on ANY street: a flop or turn spot where calling is all-in is decided purely by whether hero's equity meets the price, never by implied odds. If it says the price is a FLOOR (a non-closing spot with betting still to come), meeting the threshold is necessary but NOT automatically sufficient — implied and reverse-implied odds still apply, so continuing can be right slightly under the price or folding right slightly over it; in that case justify the deviation with a specific implied/reverse-implied-odds reason, not a vague "feels value-heavy". Never bless a preflop limp, complete, or cold-call purely because it clears the FLOOR price. State the comparison in one short clause, not a derivation.

7. POSITION & PREFLOP ROLES: Honor the "Postflop position" and "Preflop roles" FACTs exactly — they are computed from the seats and the action, and your unaided read of them has been unreliable. Never state hero's in/out-of-position relationship backwards: the player who acts LAST postflop is IN position (a CO is in position vs the blinds; the BB is out of position postflop versus everyone, despite acting last preflop). Never swap who raised and who called: the last preflop raiser is the AGGRESSOR and holds the raising / 3-bet / 4-bet range, while a player who merely called holds the calling range. Do NOT describe the aggressor's range as a "calling range", and do not place hero out of position when the FACT puts him in position.`;

// A stable signature of the reads that drive the analysis (and the modeled
// equity). The cache is keyed on (user_id, hand_id), but reads also shape the
// coaching and the injected equity FACTs — so a cached analysis is only valid
// if it was produced under the same reads. Stored in analysis_json so no
// schema change is needed; the client ignores the underscore-prefixed field.
export function readsSignature(reads: PlayerRead[]): string {
  return reads
    .map((r) => `${r.playerLabel.toLowerCase()}:${[...r.tags].sort().join(",")}`)
    .sort()
    .join("|");
}
