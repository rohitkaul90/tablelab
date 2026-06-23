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

  final heroVal = evaluateBest(all);
  final heroCat = handCategory(heroVal);

  // "Plays the board": on turn/river (board ≥ 5) a hero whose best 5 doesn't beat
  // the board alone has no real made hand (e.g. high card on a paired board) —
  // fall through to the draw/air check rather than mislabel it marginalMade.
  var playsBoard = false;
  if (board.length >= 5) {
    final boardVal = evaluateBest(board);
    if (heroVal <= boardVal) playsBoard = true;
  }

  if (!playsBoard) {
    if (heroCat >= 2) return HandClass.strongMade; // two pair → straight flush
    if (heroCat == 1) return HandClass.marginalMade; // one pair using hole cards
  }

  final fd = _flushDraw(hole, board);
  final sd = _straightDraw(hole, board);
  if (fd == _FDraw.nut || sd == _SDraw.oesd) return HandClass.strongDraw;
  if (fd == _FDraw.weak || sd == _SDraw.gutshot) return HandClass.weakDraw;
  return HandClass.air;
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
  final ranks = {for (final c in [...hole, ...board]) cardRank(c)};
  if (_hasStraight(ranks)) return _SDraw.none; // already made — not a draw
  var outs = 0;
  for (var r = 0; r < 13; r++) {
    if (ranks.contains(r)) continue;
    if (_hasStraight({...ranks, r})) outs++;
  }
  if (outs >= 2) return _SDraw.oesd;
  if (outs == 1) return _SDraw.gutshot;
  return _SDraw.none;
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

/// EQR multiplier for a hand class at a position. v1 ignores SPR (deferred).
double eqrMultiplier(HandClass hc, HeroPosition pos) {
  final ip = pos == HeroPosition.ip;
  switch (hc) {
    case HandClass.air:
      return ip ? 0.30 : 0.10; // ESTIMATED (pure air OOP vs aggression → near 0)
    case HandClass.weakDraw:
      return ip ? 0.88 : 0.78; // IP ≈ weak-FD anchor 0.87; OOP estimated
    case HandClass.strongDraw:
      return ip ? 1.00 : 0.88; // IP = NFD anchor 1.00; OOP estimated
    case HandClass.marginalMade:
      return ip ? 0.92 : 0.79; // OOP = BB-defend anchor 0.79; IP estimated
    case HandClass.strongMade:
      // Over-realizes. Spec's 1.8 is the extreme (nutted + initiative); capped
      // to a conservative flat value here — ESTIMATED.
      return ip ? 1.30 : 1.12;
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

/// The `[HEURISTIC —]` FACT line for one street. Deliberately a HEURISTIC (not a
/// `[FACT —]`) — the multiplier is mostly estimated, so the model must treat it
/// as advisory context that never overrides a hard equity / pot-odds FACT.
String realizedEquityFact({
  required String street,
  required double rawEquity,
  required HandClass handClass,
  required HeroPosition position,
}) {
  final realized =
      realizedEquity(rawEquity, handClass: handClass, position: position);
  final raw = (rawEquity * 100).round();
  final rel = (realized * 100).round();
  final posLabel = position == HeroPosition.ip ? 'in position' : 'out of position';
  return '[HEURISTIC — On the $street, hero\'s raw all-in equity is ~$raw%, but '
      '$posLabel with ${handClassLabel(handClass)}, hero typically REALIZES closer '
      'to ~$rel% (estimated equity-realization multiplier, not exact). Weigh the '
      'continue decision against the realized figure, not the raw number. This is '
      'heuristic context — it does NOT override a decisive pot-odds price FACT or '
      'a hard equity FACT.]';
}

/// Helper used by both the FACT path and the eval baker so they classify
/// identically. Returns null when not classifiable (pre-flop / bad input).
HandClass? classifyFromStrings(List<String> holeCards, List<String> boardCards) {
  final hole = holeCards.map(parseCard).where((c) => c >= 0).toList();
  final board = boardCards.map(parseCard).where((c) => c >= 0).toList();
  if (hole.length < 2) return null;
  return classifyHandClass(hole, board);
}
