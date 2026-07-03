// GTO Explorer — solver-conventional action colors (dark-calibrated; the
// explorer is wrapped in AppTheme.dark like the other felt screens).
// Reds = aggression (darker = bigger), greens = passive continue, blue = fold.

import 'package:flutter/material.dart';

const Color _kFold = Color(0xFF4A7BB5);
const Color _kCheckCall = Color(0xFF3E9B4F);
const Color _kBetLight = Color(0xFFD96A5C);
const Color _kBetDark = Color(0xFFA23030);
const Color _kRaise = Color(0xFF8C2323);
const Color _kAllin = Color(0xFF641A1A);

double? _betAmount(String raw) {
  final m = RegExp(r'([0-9]+\.?[0-9]*)').firstMatch(raw);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// Colors for a node's actions, aligned 1:1 with [actions]. BET sizes ramp
/// light→dark by amount within the node.
List<Color> actionColors(List<String> actions) {
  // Rank the bet actions by size so multi-size nodes ramp consistently.
  final betIdx = <int>[];
  for (var i = 0; i < actions.length; i++) {
    if (actions[i].trim().toUpperCase().startsWith('BET')) betIdx.add(i);
  }
  betIdx.sort((a, b) =>
      (_betAmount(actions[a]) ?? 0).compareTo(_betAmount(actions[b]) ?? 0));
  final betRank = {for (var r = 0; r < betIdx.length; r++) betIdx[r]: r};

  return [
    for (var i = 0; i < actions.length; i++)
      switch (actions[i].trim().toUpperCase()) {
        final u when u.startsWith('FOLD') => _kFold,
        final u when u.startsWith('CHECK') || u.startsWith('CALL') =>
          _kCheckCall,
        final u when u.startsWith('RAISE') => _kRaise,
        final u
            when u.startsWith('ALLIN') ||
                u.startsWith('ALL_IN') ||
                u.startsWith('ALL IN') =>
          _kAllin,
        final u when u.startsWith('BET') => betIdx.length <= 1
            ? _kBetDark
            : Color.lerp(_kBetLight, _kBetDark,
                betRank[i]! / (betIdx.length - 1))!,
        _ => Colors.grey,
      },
  ];
}

/// Short human label for a raw solver action: 'BET 6.6' → 'Bet 6.6',
/// 'BET 10.000000' → 'Bet 10' (dump amounts carry float noise).
String actionDisplayLabel(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return u;
  u = u.toLowerCase().replaceAllMapped(RegExp(r'\d+(?:\.\d+)?'), (m) {
    final v = double.tryParse(m.group(0)!);
    if (v == null) return m.group(0)!;
    return v == v.roundToDouble()
        ? v.round().toString()
        : ((v * 10).roundToDouble() / 10).toString();
  });
  return u[0].toUpperCase() + u.substring(1);
}
