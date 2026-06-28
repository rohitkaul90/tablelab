// Decision-Context Engine (DCE) — Tier A, the EQUITY-REALIZATION (EQR) factor.
//
// Raw Monte-Carlo equity is only the INPUT to a decision: a hand rarely realizes
// its full all-in equity, because it has to navigate future streets (a marginal
// hand OOP gets bet off; a strong hand with initiative over-realizes by getting
// to showdown cheaply / denying equity). This module turns raw equity into a
// REALIZED-equity estimate via an EQR multiplier keyed on {hand class, position},
// so the `analyze-hand` prompt can reason from realized equity instead of the raw
// number. It does NOT decide the action — it emits a grounded `[HEURISTIC —]`
// FACT the model weighs (see launch/DECISION_CONTEXT_ENGINE.md §"Honesty
// constraint": these numbers are soft, labelled heuristic, and never override a
// hard `[FACT —]`).
//
// Pure Dart, isolate-safe (no Flutter import) so it runs inside the existing
// equity `compute()` isolate AND under `dart run` for the eval harness. Unit-
// tested in test/equity/decision_context_test.dart.
//
// EQR is RESULT-INDEPENDENT: it is computed a priori from position + hand class,
// never inspecting the runout — as result-independent as raw equity, so it is
// safe to bake into eval fixtures.
//
// SCOPE (v1): keyed on hand-class × position only. The spec also lists SPR as an
// input; an SPR adjustment is deliberately deferred (the SPR→EQR curve is itself
// an estimate and would add a confidently-wrong surface without an anchor). Add
// it as a later refinement once the eval shows EQR helps.

import 'card.dart';
import 'evaluator.dart';

/// Hero's position relative to the villain whose range drives the decision.
enum HeroPosition { ip, oop }

/// Coarse hand-class bucket that drives equity realization.
enum HandClass {
  /// No made hand and no meaningful draw — realizes almost nothing.
  air,

  /// A weak/marginal draw (gutshot, or a non-nut one-card-ish flush draw).
  weakDraw,

  /// A strong draw (nut flush draw, or an open-ended straight draw).
  strongDraw,

  /// A made hand that is at best one pair — realizes below raw, esp. OOP.
  marginalMade,

  /// Two pair or better (incl. sets/straights/flushes/boats) — over-realizes.
  strongMade,
}

// ── Hand-class classification (hero cards + board) ───────────────────────────

enum _FDraw { none, weak, nut }
enum _SDraw { none, gutshot, oesd }

/// Classify hero's hand on the given board (parsed card ints). Returns null
/// pre-flop (board < 3) — EQR is a postflop concept.
///
/// Order matters: a made hand that beats the board is classified by its made
/// strength; otherwise (high card, or hero merely "plays the board") it is a
/// draw or air. A made one-pair-or-better that also holds a draw is classified
/// by the made hand (v1 limitation — combo draws are under-credited; noted).
HandClass? classifyHandClass(List<int> hole, List<int> board) {
  if (board.length < 3) return null;
  final all = [...hole, ...board];
  if (all.length < 5 || all.length > 7) return null;

  // Hero's made hand, but ONLY if hero's hole cards actually contribute (a hero
  // who merely "plays the board" — e.g. overcards on a paired flop — has no made
  // hand). Returns strongMade / marginalMade / null.
  final made = _madeClass(hole, board);

  // Draws only matter while a card is still to come (flop/turn, board < 5). On
  // the river a busted flush/straight is just high-card air, not a draw.
  final fd = board.length < 5 ? _flushDraw(hole, board) : _FDraw.none;
  final sd = board.length < 5 ? _straightDraw(hole, board) : _SDraw.none;
  final strongDraw = fd == _FDraw.nut || sd == _SDraw.oesd;
  final weakDraw = fd == _FDraw.weak || sd == _SDraw.gutshot;

  // Combine. A one-pair hand that ALSO holds a strong draw is a combo that
  // OVER-realizes → strongMade, not the marginalMade discount.
  if (made == HandClass.strongMade) return HandClass.strongMade;
  if (made == HandClass.marginalMade) {
    return strongDraw ? HandClass.strongMade : HandClass.marginalMade;
  }
  // No real made hand → it's a draw or air.
  if (strongDraw) return HandClass.strongDraw;
  if (weakDraw) return HandClass.weakDraw;
  return HandClass.air;
}

/// Hero's made-hand class, or null when hero has no made hand of his own
/// (high card, or merely playing the board). strongMade = two pair+;
/// marginalMade = one pair using hero's cards.
HandClass? _madeClass(List<int> hole, List<int> board) {
  final heroVal = evaluateBest([...hole, ...board]);
  final heroCat = handCategory(heroVal);
  if (heroCat == 0) return null; // high card — no made hand
  if (!_heroContributesToMade(hole, board, heroVal, heroCat)) return null;
  return heroCat >= 2 ? HandClass.strongMade : HandClass.marginalMade;
}

/// Does hero's hole actually participate in the made hand (vs "playing the
/// board")? On a 5+ board we can compare against the board's own best 5; on the
/// flop/turn (board < 5, not evaluable alone) a rank-based made hand (pair / two
/// pair / trips) is the board's unless a hole card pairs in, while a
/// straight/flush/boat (cat ≥ 4) necessarily uses hole cards on so few board
/// cards.
bool _heroContributesToMade(
    List<int> hole, List<int> board, int heroVal, int heroCat) {
  if (board.length >= 5) return heroVal > evaluateBest(board);
  if (heroCat >= 4) return true;
  final hr = [for (final c in hole) cardRank(c)];
  final br = {for (final c in board) cardRank(c)};
  final pocketPair = hr.length == 2 && hr[0] == hr[1];
  return pocketPair || hr.any(br.contains);
}

/// A 4-to-a-flush that hero contributes to (≥1 hole card of the suit). A made
/// flush (5+) is handled upstream as strongMade. Nut = hero holds the ace.
_FDraw _flushDraw(List<int> hole, List<int> board) {
  final all = [...hole, ...board];
  for (var s = 0; s < 4; s++) {
    final cntAll = all.where((c) => cardSuit(c) == s).length;
    final cntHole = hole.where((c) => cardSuit(c) == s).length;
    if (cntAll == 4 && cntHole >= 1) {
      final hasNut = hole.any((c) => cardSuit(c) == s && cardRank(c) == 12);
      return hasNut ? _FDraw.nut : _FDraw.weak;
    }
  }
  return _FDraw.none;
}

/// Straight-draw strength by counting distinct ranks that would COMPLETE a
/// straight (rank-based; suits irrelevant for a straight). ≥2 completing ranks
/// (open-ender or double-gutshot, ~8 outs) → oesd; exactly 1 (gutshot, ~4) →
/// gutshot. A draw shared via the board counts (hero realizes it too).
_SDraw _straightDraw(List<int> hole, List<int> board) {
  final boardRanks = {for (final c in board) cardRank(c)};
  final allRanks = {...boardRanks, for (final c in hole) cardRank(c)};
  if (_hasStraight(allRanks)) return _SDraw.none; // already made — not a draw
  final outs = _straightOuts(allRanks);
  // Hero must CONTRIBUTE: the draw must improve once hero's cards are included.
  // A board-only open-ender (e.g. 5-6-7-8) that hero merely shares with air
  // (2-3) is not hero's draw — same hole-contribution guard _flushDraw enforces.
  if (outs <= _straightOuts(boardRanks)) return _SDraw.none;
  if (outs >= 2) return _SDraw.oesd;
  if (outs == 1) return _SDraw.gutshot;
  return _SDraw.none;
}

/// Count of distinct ranks that would complete a 5-straight from [ranks].
int _straightOuts(Set<int> ranks) {
  var outs = 0;
  for (var r = 0; r < 13; r++) {
    if (ranks.contains(r)) continue;
    if (_hasStraight({...ranks, r})) outs++;
  }
  return outs;
}

/// Any 5 consecutive ranks present, including the wheel (A-2-3-4-5).
bool _hasStraight(Set<int> ranks) {
  if (ranks.containsAll(const {12, 0, 1, 2, 3})) return true; // wheel
  for (var hi = 12; hi >= 4; hi--) {
    if (ranks.contains(hi) &&
        ranks.contains(hi - 1) &&
        ranks.contains(hi - 2) &&
        ranks.contains(hi - 3) &&
        ranks.contains(hi - 4)) {
      return true;
    }
  }
  return false;
}

// ── EQR multiplier table ─────────────────────────────────────────────────────
//
// realized equity = raw equity × this multiplier (clamped to [0,1]). The values
// are SOLVER-CALIBRATED (69-spot TexasSolver run, ~0.5% exploitability; see
// `tool/solver/` + memory/solver-engine-landscape), superseding the original
// hand-estimated anchors. Still a HEURISTIC (single-bet tree, Pluribus
// distribution, a few noisy buckets) — present as heuristic context, never a
// precise FACT. Pattern: in position hands realize ~fully (≈1.0+, so realized can
// EXCEED raw); out of position they realize below raw, scaled by strength. The
// per-cell provenance + the rounding/judgement calls are in the function below.

/// EQR multiplier for a hand class at a position. Ignores SPR (separate factor).
///
/// Values are SOLVER-CALIBRATED from a 69-spot TexasSolver run (~0.5%
/// exploitability) measuring showdown realization (check/call line, fold equity
/// stripped) per {hand class × position}; see `tool/solver/` + memory. The
/// headline: in position hands realize ~fully (multipliers ~1.0+), out of
/// position they realize much worse, scaled by strength. Caveats: single-bet
/// tree abstraction + Pluribus distribution + a few noisy buckets. Returned
/// values are ROUNDED to clean ~0.05 steps from the per-cell measurements cited
/// inline (slightly conservative); `air` and `strongMade/OOP` are additional
/// judgment calls (noted inline), not raw measurements.
double eqrMultiplier(HandClass hc, HeroPosition pos) {
  final ip = pos == HeroPosition.ip;
  switch (hc) {
    case HandClass.air:
      // IP measured 0.77 (true air) – 1.08 (overcards); blended to one value
      // since `air` isn't equity-split. OOP confirmed ≈ 0.10 (realizes ~nothing).
      return ip ? 0.85 : 0.10;
    case HandClass.weakDraw:
      return ip ? 1.00 : 0.45; // IP measured 1.05; OOP 0.39 (draws OOP realize poorly)
    case HandClass.strongDraw:
      return ip ? 1.05 : 0.55; // IP tight 1.08 (1.03–1.12); OOP 0.49
    case HandClass.marginalMade:
      return ip ? 1.15 : 0.75; // IP tight 1.18; OOP 0.74
    case HandClass.strongMade:
      // IP measured 1.16 — lowers the old 1.30 cap. OOP keeps 1.12: the measured
      // 1.53 is outlier-driven (spread 0.98–2.27) and would break IP ≥ OOP, so
      // it's treated as noise.
      return ip ? 1.18 : 1.12;
  }
}

/// Realized equity = raw × EQR multiplier, clamped to [0, 1].
double realizedEquity(
  double rawEquity, {
  required HandClass handClass,
  required HeroPosition position,
}) =>
    (rawEquity * eqrMultiplier(handClass, position)).clamp(0.0, 1.0);

/// Human label for a hand class (used in the FACT prose).
String handClassLabel(HandClass hc) {
  switch (hc) {
    case HandClass.air:
      return 'air (no real equity)';
    case HandClass.weakDraw:
      return 'a weak draw';
    case HandClass.strongDraw:
      return 'a strong draw';
    case HandClass.marginalMade:
      return 'a marginal made hand';
    case HandClass.strongMade:
      return 'a strong made hand';
  }
}

/// Helper used by both the FACT path and the eval baker so they classify
/// identically. Returns null when not classifiable (pre-flop / bad input).
HandClass? classifyFromStrings(List<String> holeCards, List<String> boardCards) {
  final hole = holeCards.map(parseCard).where((c) => c >= 0).toList();
  final board = boardCards.map(parseCard).where((c) => c >= 0).toList();
  if (hole.length < 2) return null;
  return classifyHandClass(hole, board);
}

// ── SPR & commitment (DCE Tier A, the SPR factor) ────────────────────────────
//
// SPR (stack-to-pot ratio) = effective stack ÷ pot, measured at the START of a
// street. It drives COMMITMENT: at low SPR a strong-enough made hand should get
// all-in; at high SPR a one-pair hand favours pot control.
//
// The HEADS-UP equity required to profitably stack off derives in closed form:
// hero risks the effective stack E to win the pot P plus villain's matching E,
// so reqStackOff = E / (P + 2E) = SPR / (1 + 2·SPR). This matches the sourced
// anchors (launch/DECISION_CONTEXT_ENGINE.md §"Key sourced constants"):
//   SPR 1 → 33%, SPR 2 → 40%, SPR 3 → 43%, SPR → ∞ → 50% (asymptote).
// MULTIWAY the all-in price is HIGHER (hero must beat the whole field) and
// depends on caller count + coverage, so the precise % is heads-up-only — the
// FACT path suppresses it multiway and reasons qualitatively from SPR instead.

/// Heads-up required equity (0–1) to profitably get all-in at this [spr].
/// reqStackOff = spr / (1 + 2·spr); asymptotes to (and is clamped at) 0.5.
double requiredEquityToStackOff(double spr) {
  if (spr <= 0) return 0.0;
  return (spr / (1 + 2 * spr)).clamp(0.0, 0.5);
}

/// Commitment buckets by SPR. The boundaries are heuristic (estimated, not
/// hard-sourced) — used only for the prose framing in the SPR FACT.
enum SprBucket { committed, shallow, medium, deep }

SprBucket sprBucket(double spr) {
  if (spr <= 1.0) return SprBucket.committed;
  if (spr <= 3.0) return SprBucket.shallow;
  if (spr <= 6.0) return SprBucket.medium;
  return SprBucket.deep;
}

/// Human label for an SPR commitment bucket (used in the FACT prose).
String sprBucketLabel(SprBucket b) {
  switch (b) {
    case SprBucket.committed:
      return 'very low SPR — hero is near-committed';
    case SprBucket.shallow:
      return 'low SPR — favours stacking off strong made hands';
    case SprBucket.medium:
      return 'medium SPR — strength-dependent';
    case SprBucket.deep:
      return 'high SPR — favours pot control with one-pair hands';
  }
}

// ── MDF & alpha (DCE Tier A, the MDF factor) ─────────────────────────────────
//
// Minimum Defense Frequency: facing a bet of [bet] into a pot of [pot] (the pot
// BEFORE the bet), a player must continue with at least pot/(pot+bet) of their
// range, or a pure-bluff betting range prints by auto-profit. Alpha is the
// complementary maximum fold frequency a bluff needs to break even, and the
// value:bluff ratio the bettor is offering. Both are closed-form and exact, and —
// unlike a heads-up pot-odds price — apply at any player count (the FIELD's
// COLLECTIVE defense must meet MDF, so each individual defends LESS multiway).
//
// MDF is a RANGE-defense ceiling, NOT a hand-specific call price: a specific
// bluff-catcher calls on its realized equity vs the pot-odds price, and vs a
// capped / value-heavy range a player correctly OVER-folds below MDF. So MDF is
// context for how often to defend, never an instruction to call a given hand —
// the pot-odds / equity FACTs decide the individual spot.

/// Minimum defense frequency facing [bet] into [pot] (pot before the bet):
/// pot/(pot+bet), clamped to [0,1]. 0 when there is no bet.
double minDefenseFrequency(double pot, double bet) {
  if (bet <= 0 || pot < 0) return 0.0;
  return (pot / (pot + bet)).clamp(0.0, 1.0);
}

/// Alpha = bet/(pot+bet): the maximum fold frequency at which a bluff of size
/// [bet] into [pot] breaks even (= 1 − MDF). Clamped to [0,1].
double alpha(double pot, double bet) {
  if (bet <= 0 || pot < 0) return 0.0;
  return (bet / (pot + bet)).clamp(0.0, 1.0);
}

// ── Board volatility (DCE Tier A, the BOARD-VOLATILITY factor) ────────────────
//
// How much does the next card change the board? A STATIC board (equities locked
// in) favours small bets / flatting; a DYNAMIC board (many next cards complete a
// flush or straight, or pair the board) favours protection raises + larger
// sizing. It moves the CALL-vs-RAISE / sizing decision, NOT the bluff-catch call.
//
// [boardDynamism] is a deterministic COUNT of unseen next cards that change what
// hands are possible (a flush becomes makeable, a new straight window opens, or the
// board pairs → boats). BOARD-ONLY and hand-independent by design — it does not
// exclude any player's hole cards — so every observer reads the same dynamism and,
// critically, it matches the Phase-2 calibration, which counted board-only. The
// COUNT is exact; the static/dynamic THRESHOLD and the sizing PRESCRIPTION are the
// soft parts (solver-calibrated, tool/solver/VOLATILITY_FINDINGS.md), so the prompt
// emits the static/dynamic label as a [HEURISTIC —] line, not a hard [FACT —].
// Pure Dart, isolate-safe; unit-tested in decision_context_test.dart.

/// A board is "dynamic" when at least this fraction of the unseen next cards
/// change the board's category possibilities. SOLVER-CALIBRATED: a 30-spot
/// TexasSolver run (`tool/solver/VOLATILITY_FINDINGS.md`) found the GTO c-bet
/// sizing regime transitions around a dynamic-fraction of ~0.50 — below it strong
/// hands size small (~49–52%), above it they size up (~60–63%). The count metric
/// saturates above ~0.65 (most wet boards clip near 0.76), so in practice this
/// threshold separates truly-dry boards from the rest, which is the distinction
/// that matters ("don't size up on a dry board").
const double kBoardDynamicThreshold = 0.50;

/// Deterministic board-volatility measurement for one street: of the unseen next
/// cards, how many materially change what is possible on the board. Valid only
/// on the flop (3) or turn (4) — there is a next card to come; null otherwise
/// (pre-flop, or the river where nothing is left to come).
///
/// A next card counts as DYNAMIC when it does at least one of: pairs the board (a
/// rank already present → boats/quads change), advances a flush (its suit already
/// has ≥2 on the board → 3+ makes a flush makeable / shifts the nut flush), or
/// opens a new straight window (a 5-rank window the board now supplies ≥3 of that
/// it did not before). The three subset counts can overlap (one card may pair AND
/// bring a flush), so they sum to ≥ [dynamic]; [dynamic] is the union.
class BoardDynamism {
  /// Board length this was computed for (3 = flop→turn, 4 = turn→river).
  final int street;

  /// Number of unseen next cards considered (52 − the board cards).
  final int unseen;

  /// Unseen cards that change the board's category possibilities (the union of
  /// the three subsets below — a card is counted once even if it does several).
  final int dynamic;

  /// Subset: cards that advance a flush (suit already ≥2 on board).
  final int flushCards;

  /// Subset: cards that open a straight window the board did not supply before.
  final int straightCards;

  /// Subset: cards that pair (or further pair) the board.
  final int pairCards;

  const BoardDynamism({
    required this.street,
    required this.unseen,
    required this.dynamic,
    required this.flushCards,
    required this.straightCards,
    required this.pairCards,
  });

  /// Fraction of unseen cards that are dynamic (0 when there are no unseen cards).
  double get dynamicFraction => unseen == 0 ? 0.0 : dynamic / unseen;

  /// Whether the board reads as dynamic at the solver-calibrated 0.50 threshold
  /// ([kBoardDynamicThreshold]).
  bool get isDynamic => dynamicFraction >= kBoardDynamicThreshold;
}

/// Compute [BoardDynamism] for [board] (parsed card ints). BOARD-ONLY by design:
/// it counts every one of the 52 − board cards as a possible next card (it does
/// NOT exclude hero's hole cards), so the result is hand-independent and matches
/// the Phase-2 calibration. Returns null for boards that are not the flop or turn.
BoardDynamism? boardDynamism(List<int> board) {
  if (board.length != 3 && board.length != 4) return null;

  final boardSet = board.toSet();
  final boardRanks = {for (final c in board) cardRank(c)};
  final suitCount = <int, int>{};
  for (final c in board) {
    final s = cardSuit(c);
    suitCount[s] = (suitCount[s] ?? 0) + 1;
  }
  final baseWindows = _supplyWindows(_presentValues(board));

  var unseen = 0, dynamic = 0, flushCards = 0, straightCards = 0, pairCards = 0;
  for (var c = 0; c < 52; c++) {
    if (boardSet.contains(c)) continue;
    unseen++;

    final pairs = boardRanks.contains(cardRank(c));
    final flush = (suitCount[cardSuit(c)] ?? 0) >= 2;
    final straight = _opensWindow(board, c, baseWindows);

    if (pairs) pairCards++;
    if (flush) flushCards++;
    if (straight) straightCards++;
    if (pairs || flush || straight) dynamic++;
  }

  return BoardDynamism(
    street: board.length,
    unseen: unseen,
    dynamic: dynamic,
    flushCards: flushCards,
    straightCards: straightCards,
    pairCards: pairCards,
  );
}

/// Does adding card [c] open a straight window the [board] did not already
/// supply (≥3 of a 5-rank window)? [baseWindows] is the board's existing window
/// set, passed in so we compute it once per board, not once per unseen card.
bool _opensWindow(List<int> board, int c, Set<int> baseWindows) {
  final after = _supplyWindows(_presentValues([...board, c]));
  return after.length > baseWindows.length;
}

/// Rank VALUES (2..14, ace high) present on the cards, plus 1 for the wheel ace —
/// mirrors the prompt's computeBoardSummary so straight reasoning lines up.
Set<int> _presentValues(List<int> cards) {
  final present = <int>{};
  for (final c in cards) {
    final v = cardRank(c) + 2; // rank 0..12 → value 2..14
    present.add(v);
    if (v == 14) present.add(1); // ace also plays low
  }
  return present;
}

/// Low ends (1..10) of every 5-rank window the [present] values supply ≥3 of —
/// i.e. windows a player could complete with at most two hole cards.
Set<int> _supplyWindows(Set<int> present) {
  final windows = <int>{};
  for (var low = 1; low <= 10; low++) {
    var onBoard = 0;
    for (var v = low; v < low + 5; v++) {
      if (present.contains(v)) onBoard++;
    }
    if (onBoard >= 3) windows.add(low);
  }
  return windows;
}
