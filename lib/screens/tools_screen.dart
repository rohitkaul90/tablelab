import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'equity_calculator_screen.dart';
import 'explorer/gto_explorer_screen.dart';
import 'icm_calculator_screen.dart';
import '../providers/explorer_provider.dart';
import '../widgets/app_drawer.dart';

class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    // Discover GTO Study spots up front (cheap directory scan; no-op on web
    // until hosted packs land) so the Study segment's visibility is known
    // without the screen ever mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(explorerProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The Study segment only exists when there is something to study (or in
    // debug builds, where the empty state carries the developer setup hint).
    // Prod users must never see a permanently dead tab: today's only pack
    // source is a local dev directory; hosted packs light this up later.
    final showStudy =
        kDebugMode || ref.watch(explorerProvider).spots.isNotEmpty;
    final selected = showStudy ? _selected : (_selected == 2 ? 0 : _selected);
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
              segments: [
                const ButtonSegment(value: 0, label: Text('Equity')),
                const ButtonSegment(value: 1, label: Text('ICM')),
                if (showStudy)
                  const ButtonSegment(value: 2, label: Text('Study')),
              ],
              selected: {selected},
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
              index: selected,
              children: [
                const EquityCalculatorScreen(showScaffold: false),
                const IcmCalculatorScreen(showScaffold: false),
                if (showStudy) const GtoExplorerScreen(showScaffold: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
