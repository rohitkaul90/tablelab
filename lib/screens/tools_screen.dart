import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'equity_calculator_screen.dart';
import 'icm_calculator_screen.dart';
import 'variance_calculator_screen.dart';

/// The Tools screen — the Equity, ICM and Variance calculators behind a pill
/// toggle.
/// Reached from the drawer's APP section (the GTO Study explorer graduated to
/// its own bottom-nav tab). Pushed as a route, so its AppBar shows the default
/// back button.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<int>(
              // Label-only + no selected checkmark (the SegmentedButton gotcha
              // in CLAUDE.md — the M3 checkmark can wrap the row on phones).
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Equity')),
                ButtonSegment(value: 1, label: Text('ICM')),
                ButtonSegment(value: 2, label: Text('Variance')),
              ],
              selected: {_selected},
              onSelectionChanged: (s) => setState(() => _selected = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: theme.colorScheme.primary,
                selectedForegroundColor: theme.colorScheme.onPrimary,
                foregroundColor: theme.colorScheme.onSurface.withAlpha(153),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: IndexedStack(
              index: _selected,
              children: const [
                EquityCalculatorScreen(showScaffold: false),
                IcmCalculatorScreen(showScaffold: false),
                VarianceCalculatorScreen(showScaffold: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
