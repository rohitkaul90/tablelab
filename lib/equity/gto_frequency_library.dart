// GTO frequency library (DCE Q1) — Phase 3: the LIVE lookup.
//
// Loads the offline-solved frequency library (assets/gto_freq_library.json,
// built by tool/solver/freq_grid.dart) and resolves a hand's decision node to a
// GTO action-frequency mix, with a graceful texture/SPR fallback hierarchy. The
// result grounds the live `[HEURISTIC — GTO frequency]` coaching FACT.
//
// PURE Dart — no Flutter, no dart:io — so it runs in the equity compute() isolate,
// under `dart run` for the eval baker, and on web. The CALLER loads the JSON
// (app: rootBundle, eval: File) and hands the decoded map to [fromJson]; this
// file never does I/O. Design: launch/GTO_FREQUENCY_LIBRARY.md §5–6.

import 'dart:convert';

import 'card.dart';
import 'decision_context.dart' show HandClass;
import 'texture_cell.dart';

/// One resolved lookup: the GTO action mix plus how far we had to fall back to
/// find it (so the FACT can phrase an interpolated value more softly).
class GtoFrequencyResult {
  /// Action label → frequency (0–1), e.g. {check: 0.62, bet_small: 0.30}.
  final Map<String, double> freqs;

  /// Reach mass behind the (possibly merged) aggregate.
  final double reachWeight;

  /// Texture relaxation used: 0 = exact texture, 1 = dropped connectedness,
  /// 2 = dropped high-card, 3 = suit-pattern only.
  final int textureFallback;

  /// True when the matched cell used the queried SPR bucket (false = nearest).
  final bool sprExact;

  const GtoFrequencyResult({
    required this.freqs,
    required this.reachWeight,
    required this.textureFallback,
    required this.sprExact,
  });

  /// Whether any fallback (texture or SPR) was used — i.e. not an exact hit.
  bool get isInterpolated => textureFallback > 0 || !sprExact;

  /// The dominant action (highest frequency), or null when empty.
  String? get topAction {
    if (freqs.isEmpty) return null;
    return freqs.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

/// One stored cell with its texture pre-split into the four axes for relaxation.
class _IndexedCell {
  final List<String> tex; // [suit, pairing, highcard, connectedness]
  final String spr;
  final Map<String, double> freqs;
  final double mass;
  _IndexedCell(this.tex, this.spr, this.freqs, this.mass);
}

class GtoFrequencyLibrary {
  final Map<String, dynamic> meta;
  final Set<String> scenarios;

  /// Cells grouped by the non-texture/non-SPR key
  /// (scenario|street|position|facing|handClass) → candidates to relax over.
  final Map<String, List<_IndexedCell>> _groups;

  GtoFrequencyLibrary._(this.meta, this.scenarios, this._groups);

  /// Build from the raw JSON string (app: rootBundle asset; eval: file read).
  /// dart:convert only — no I/O — so this stays isolate/dart-run/web safe.
  factory GtoFrequencyLibrary.fromJsonString(String s) =>
      GtoFrequencyLibrary.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// Build from the decoded library JSON (the map `jsonDecode` returns).
  factory GtoFrequencyLibrary.fromJson(Map<String, dynamic> json) {
    final groups = <String, List<_IndexedCell>>{};
    final scenarios = <String>{};
    final scen = (json['scenarios'] as Map?) ?? const {};
    scen.forEach((scenarioKey, sv) {
      scenarios.add(scenarioKey as String);
      final cells = ((sv as Map)['cells'] as List?) ?? const [];
      for (final cj in cells) {
        final c = cj as Map<String, dynamic>;
        final tex = (c['texture'] as String).split('|');
        if (tex.length != 4) continue;
        final groupKey = [
          scenarioKey,
          c['street'],
          c['position'],
          c['facing'],
          c['hand_class'],
        ].join('|');
        final freqs = <String, double>{
          for (final e in (c['freqs'] as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        };
        groups.putIfAbsent(groupKey, () => []).add(_IndexedCell(
              tex,
              c['spr_bucket'] as String,
              freqs,
              (c['reach_weight'] as num).toDouble(),
            ));
      }
    });
    return GtoFrequencyLibrary._(
        (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
        scenarios,
        groups);
  }

  bool get isEmpty => _groups.isEmpty;

  /// Resolve the GTO mix for a decision node, or null on a miss (no cell within
  /// the fallback hierarchy clears [minMass]). [board] is the street's cards.
  ///
  /// Fallback (design §6, tightened after review): SPR is matched EXACTLY — a
  /// bucket the library never solved (e.g. deep cash, where SPR>6) is a different
  /// strategic regime, NOT a near-neighbour, so it misses rather than borrowing
  /// the medium-SPR mix. Texture relaxes at most [maxTextureFallback] axes
  /// (default 1 = drop only connectedness, the lowest-impact axis); dropping
  /// pairing/high-card blends materially different boards, so it is off by
  /// default. Relaxed levels matching several cells are merged by reach mass.
  GtoFrequencyResult? lookup({
    required String scenario,
    required List<int> board,
    required String sprBucket,
    required String street,
    required String position,
    required String facing,
    required HandClass handClass,
    double minMass = 8.0,
    int maxTextureFallback = 1,
  }) {
    final tex = textureCell(board);
    if (tex == null) return null;
    final group = _groups[
        [scenario, street, position, facing, handClass.name].join('|')];
    if (group == null || group.isEmpty) return null;

    final want = tex.key.split('|'); // [suit, pairing, highcard, conn]
    final cap = maxTextureFallback.clamp(0, 3);

    // texFallback 0..cap: how many trailing texture axes to ignore (keep suit).
    // SPR is exact-only (no cross-regime borrowing).
    for (var texFallback = 0; texFallback <= cap; texFallback++) {
      final axesToMatch = 4 - texFallback; // 4,3,2,1
      final matches = group.where((c) {
        if (c.spr != sprBucket) return false;
        for (var a = 0; a < axesToMatch; a++) {
          if (c.tex[a] != want[a]) return false;
        }
        return true;
      }).toList();
      if (matches.isEmpty) continue;
      final merged = _merge(matches);
      if (merged.mass < minMass) continue;
      return GtoFrequencyResult(
        freqs: merged.freqs,
        reachWeight: merged.mass,
        textureFallback: texFallback,
        sprExact: true,
      );
    }
    return null;
  }

  ({Map<String, double> freqs, double mass}) _merge(List<_IndexedCell> cells) {
    if (cells.length == 1) return (freqs: cells.first.freqs, mass: cells.first.mass);
    final weighted = <String, double>{};
    var mass = 0.0;
    for (final c in cells) {
      mass += c.mass;
      c.freqs.forEach((a, f) => weighted[a] = (weighted[a] ?? 0) + f * c.mass);
    }
    return (
      freqs: {for (final e in weighted.entries) e.key: e.value / mass},
      mass: mass,
    );
  }
}

/// Convenience: parse a board of card strings (e.g. ["Ks","9h","4c"]) to ints
/// for [GtoFrequencyLibrary.lookup]. Skips unparseable entries.
List<int> boardInts(List<String> board) =>
    board.map(parseCard).where((c) => c >= 0).toList();
