import 'package:flutter/material.dart';

/// Shared layout for the GTO Explorer's inspect panels (the Overview panel and
/// the preflop action panel).
///
/// When [embedded] is true the CALLER owns the scroll (the narrow single-column
/// layout puts the panel inside one outer ListView, so a second inner ListView
/// would trap the scroll gesture) — render a non-scrolling Column. When false
/// (the wide layout's fixed-height Expanded pane) the panel scrolls itself.
///
/// Both panels share this one helper so the embedded↔scroll contract can't
/// drift between them — a change here (padding, physics) applies to both, and
/// there's no second copy to forget and silently reintroduce the nested-scroll
/// trap in one panel.
Widget explorerPanelBody({
  required bool embedded,
  required List<Widget> children,
}) {
  if (embedded) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
  return ListView(padding: const EdgeInsets.all(12), children: children);
}
