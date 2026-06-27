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
// realized equity = raw equity × this multiplier. HARD anchors are cited; every
// other cell is ESTIMATED and must be presented as heuristic (never as a precise
// FACT). Sourced anchors (launch/DECISION_CONTEXT_ENGINE.md §"Key sourced
// constants"): NFD IP ≈ 1.00; weak FD ≈ 0.87; BB-defend (one pair OOP) ≈ 0.79;
// strong made over-realizes (extreme ≈ 1.8 for a nutted hand WITH initiative —
// intentionally capped lower here as a flat per-class value, see note); air OOP
// realizes ≈ nothing.

/// EQR multiplier for a hand class at a position. Ignores SPR (separate factor).
///
/// Values are SOLVER-CALIBRATED from a 69-spot TexasSolver run (~0.5%
/// exploitability) measuring showdown realization (check/call line, fold equity
/// stripped) per {hand class × position}; see `tool/solver/` + memory. The
/// headline: in position hands realize ~fully (multipliers ~1.0+), out of
/// position they realize much worse, scaled by strength. Caveats: single-bet
/// tree abstraction + Pluribus distribution + a few noisy buckets — so a couple
/// of values are judgment calls (noted), not raw measurements.
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
