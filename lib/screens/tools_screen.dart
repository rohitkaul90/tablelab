import 'package:flutter/material.dart';
import 'equity_calculator_screen.dart';
import 'explorer/gto_explorer_screen.dart';
import 'icm_calculator_screen.dart';
import '../widgets/app_drawer.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Tools'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<int>(
              // Label-only + no selected checkmark: at three segments the M3
              // checkmark widens the selected segment enough to wrap the row
              // on phones (the SegmentedButton gotcha in CLAUDE.md).
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Equity')),
                ButtonSegment(value: 1, label: Text('ICM')),
                ButtonSegment(value: 2, label: Text('Study')),
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
                GtoExplorerScreen(showScaffold: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
