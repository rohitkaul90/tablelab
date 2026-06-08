import 'package:flutter/material.dart';

/// Central theme definitions for TableLab.
///
/// The app ships a dark theme (the original brand look) and a light theme,
/// switchable via [ThemeMode] (System / Light / Dark) — see `theme_provider.dart`.
///
/// **Immersive poker-table screens stay dark in both modes.** The hand-input
/// and hand-replayer screens paint a green-felt table; a poker table is dark
/// felt regardless of the surrounding app chrome, and a light AppBar over a
/// dark table looks broken. Wrap those screens in `Theme(data: AppTheme.dark…)`
/// rather than letting them follow the global mode. [feltGreen] / [feltGreenDark]
/// are the shared felt colors used by their painters.
class AppTheme {
  AppTheme._();

  /// Brand seed — the dark forest green used for the launcher icon + accents.
  static const Color seed = Color(0xFF1B5E20);

  // Poker-felt palette, theme-independent (used by the table painters).
  static const Color feltGreen = Color(0xFF1B5E20);
  static const Color feltGreenDark = Color(0xFF0A3D0A);

  /// Soft off-white scaffold for light mode — a faint green tint keeps it on
  /// brand and is warmer than stark white.
  static const Color _lightScaffold = Color(0xFFF6F8F4);

  // Cached as `static final` (not getters): `ColorScheme.fromSeed` runs a tonal-
  // palette computation, and the immersive table screens force `dark` on every
  // build — the replayer rebuilds each animation frame, so recomputing would be
  // wasteful.
  static final ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: _lightScaffold,
    // Match the scaffold tint so AppBars read as part of the page rather than
    // floating on a slightly different surface.
    appBarTheme: const AppBarTheme(
      backgroundColor: _lightScaffold,
      surfaceTintColor: _lightScaffold,
    ),
  );
}
