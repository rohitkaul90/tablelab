// Forced-decision ground truth for verdict-agreement scoring (PR 3, part 2).
//
// On a DECISIVE spot — hero faces a wager that closes the action (a river call,
// or a call/fold that puts hero all-in) — direct pot odds force the answer:
// call is correct iff hero's equity meets the break-even price, otherwise fold.
// This replays the hand in Dart to find that decision and compute the price,
// mirroring the Edge Function's `heroPotOddsFact` DECISIVE branch — an
// INDEPENDENT implementation, so a mismatch with the TS pot-odds FACT is itself
// a real bug. The per-street equity comes from the on-device cross-check.
//
// The scorer then checks whether the model's verdict for the decision street
// agrees with whether hero's actual action was the forced-correct one.

import 'dart:math';

import 'package:tablelab/equity/villain_range.dart';
import 'package:tablelab/models/hand_model.dart';

class ForcedDecision {
  final String street; // decision street name (matches the coach's keys)
  final bool heroCalled; // hero's actual action: true=call, false=fold
  final int requiredPct; // break-even equity % from pot odds
  final int heroEquityPct; // hero's equity vs the modeled range, that street
  final String forcedAction; // 'call' | 'fold' — the math-forced correct action
  final bool heroActionCorrect; // did hero's actual action match the forced one

  const ForcedDecision({
    required this.street,
    required this.heroCalled,
    required this.requiredPct,
    required this.heroEquityPct,
    required this.forcedAction,
    required this.heroActionCorrect,
  });

  Map<String, dynamic> toJson() => {
        'street': street,
        'heroCalled': heroCalled,
        'requiredPct': requiredPct,
        'heroEquityPct': heroEquityPct,
        'forcedAction': forcedAction,
        'heroActionCorrect': heroActionCorrect,
      };
}

/// Returns hero's forced decision, or null when the hand has no decisive,
/// pot-odds-determined spot (multiway side pots, non-closing streets, or no
/// equity label for the decision street → unscorable, not guessed).
ForcedDecision? computeForcedDecision(PokerHand hand, HandEquityCheck equity) {
  final hero = hand.hero;
  if (hero == null) return null;
  final heroSeat = hero.seatIndex;
  final equityByStreet = {for (final s in equity.streets) s.street: s.heroEquity};

  var runningPot = 0;
  var heroPaid = 0; // hero's cumulative chips committed across the hand

  for (final street in hand.streets) {
    final streetContrib = <int, int>{};
    final actions = street.actions;
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      final amt = a.amount;

      if (amt != null && amt > 0) {
        final prev = streetContrib[a.seat] ?? 0;
        final inc = max(0, amt - prev);
        streetContrib[a.seat] = amt;
        runningPot += inc;
        if (a.seat == heroSeat) heroPaid += inc;

        // Hero calling a wager that closes the action.
        if (a.seat == heroSeat && a.type == ActionType.call && inc > 0) {
          final closes =
              actions.skip(i + 1).every((x) => x.type == ActionType.fold);
          final decisive =
              closes && (street.street == Street.river || a.isAllIn);
          if (decisive) {
            return _build(
              street.street,
              heroCalled: true,
              callAmount: inc,
              livePotBeforeCall: runningPot - inc,
              heroMatchTotal: amt,
              streetContrib: streetContrib,
              heroSeat: heroSeat,
              equityByStreet: equityByStreet,
            );
          }
        }
      } else if (a.seat == heroSeat && a.type == ActionType.fold) {
        // Hero folding to a real wager this street that would close the action.
        final faced = actions.take(i).any(
            (x) => x.type == ActionType.raise || x.type == ActionType.allIn);
        if (!faced) continue;
        final heroContrib = streetContrib[heroSeat] ?? 0;
        var maxOther = 0;
        streetContrib.forEach((seat, c) {
          if (seat != heroSeat && c > maxOther) maxOther = c;
        });
        final fullToCall = maxOther - heroContrib;
        final heroRemaining = max(0, hero.startingStack - heroPaid);
        final callAmount = min(fullToCall, heroRemaining);
        if (callAmount <= 0) continue;
        final closes =
            actions.skip(i + 1).every((x) => x.type == ActionType.fold);
        final heroWouldBeAllIn = fullToCall >= heroRemaining;
        final decisive =
            closes && (street.street == Street.river || heroWouldBeAllIn);
        if (decisive) {
          return _build(
            street.street,
            heroCalled: false,
            callAmount: callAmount,
            livePotBeforeCall: runningPot,
            heroMatchTotal: heroContrib + callAmount,
            streetContrib: streetContrib,
            heroSeat: heroSeat,
            equityByStreet: equityByStreet,
          );
        }
      }
    }
  }
  return null;
}

ForcedDecision? _build(
  Street street, {
  required bool heroCalled,
  required int callAmount,
  required int livePotBeforeCall,
  required int heroMatchTotal,
  required Map<int, int> streetContrib,
  required int heroSeat,
  required Map<Street, double> equityByStreet,
}) {
  // Strip chips a deeper player put in beyond what hero is matching (the same
  // uncalled-excess correction heroPotOddsFact applies).
  var uncalledExcess = 0;
  streetContrib.forEach((seat, contrib) {
    if (seat != heroSeat && contrib > heroMatchTotal) {
      uncalledExcess += contrib - heroMatchTotal;
    }
  });
  final potBefore = livePotBeforeCall - uncalledExcess;
  final denom = potBefore + callAmount;
  if (denom <= 0) return null;
  final requiredPct = ((callAmount / denom) * 100).round();

  final eq = equityByStreet[street];
  if (eq == null) return null; // no equity label for this street → unscorable
  final heroEquityPct = (eq * 100).round();

  final forcedCall = heroEquityPct >= requiredPct;
  return ForcedDecision(
    street: street.name,
    heroCalled: heroCalled,
    requiredPct: requiredPct,
    heroEquityPct: heroEquityPct,
    forcedAction: forcedCall ? 'call' : 'fold',
    heroActionCorrect: heroCalled == forcedCall,
  );
}
