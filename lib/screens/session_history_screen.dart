import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/session_model.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';
import '../widgets/app_drawer.dart';
import '../widgets/session_tile.dart';
import 'live_session_screen.dart';
import 'session_detail_screen.dart';
import 'import_export_screen.dart';
import 'import_source_screen.dart';

class SessionHistoryScreen extends ConsumerWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(filteredSessionsProvider);
    final filter = ref.watch(filterProvider);
    final hasFilter = !filter.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Sessions'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: hasFilter,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filter',
            onPressed: () => _showFilterSheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Import / Export',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImportExportScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_sessions',
        onPressed: () => showLogSessionChooser(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Log Session'),
      ),
      body: Column(
        children: [
          const LiveSessionCard(),
          Expanded(
            child: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasFilter ? Icons.filter_list_off : Icons.style_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasFilter
                          ? 'No sessions match your filters'
                          : 'No sessions yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasFilter
                          ? 'Try adjusting or clearing your filters.'
                          : 'Log your first session — or import your\nhistory from another app.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                    const SizedBox(height: 24),
                    if (hasFilter)
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(filterProvider.notifier)
                            .state = const SessionFilter(),
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Filters'),
                      )
                    else ...[
                      FilledButton.icon(
                        onPressed: () => showLogSessionChooser(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Log Session'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ImportSourceScreen()),
                        ),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Import from another app'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return _SessionList(sessions: sessions);
        },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late SessionFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(filterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final stakesAsync = ref.watch(distinctStakesProvider);
    final locationsAsync = ref.watch(distinctLocationsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Filter Sessions',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Game Type
            Text('Game Type',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in [
                  ('cash', 'Cash Game'),
                  ('tournament', 'Tournament'),
                ])
                  FilterChip(
                    label: Text(entry.$2),
                    selected: _draft.gameType == entry.$1,
                    onSelected: (on) => setState(() => _draft = _draft.copyWith(
                        gameType: on ? entry.$1 : null)),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Result
            Text('Result', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Winning'),
                  selected: _draft.result == SessionResult.win,
                  onSelected: (on) => setState(() => _draft = _draft.copyWith(
                      result: on ? SessionResult.win : null)),
                ),
                FilterChip(
                  label: const Text('Losing'),
                  selected: _draft.result == SessionResult.loss,
                  onSelected: (on) => setState(() => _draft = _draft.copyWith(
                      result: on ? SessionResult.loss : null)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stakes
            stakesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
              data: (stakes) {
                if (stakes.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stakes',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: stakes
                          .map((s) => FilterChip(
                                label: Text(s),
                                selected: _draft.stakes.contains(s),
                                onSelected: (on) => setState(() {
                                  final next = {..._draft.stakes};
                                  if (on) {
                                    next.add(s);
                                  } else {
                                    next.remove(s);
                                  }
                                  _draft = _draft.copyWith(stakes: next);
                                }),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

            // Location
            locationsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
              data: (locs) {
                if (locs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Location',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: locs
                          .map((l) => FilterChip(
                                label: Text(l),
                                selected: _draft.locations.contains(l),
                                onSelected: (on) => setState(() {
                                  final next = {..._draft.locations};
                                  if (on) {
                                    next.add(l);
                                  } else {
                                    next.remove(l);
                                  }
                                  _draft = _draft.copyWith(locations: next);
                                }),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

            // Date range
            Text('Date Range',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: 'From',
                    value: _draft.dateFrom,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _draft.dateFrom != null
                            ? DateTime.parse(_draft.dateFrom!)
                            : DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _draft = _draft.copyWith(
                            dateFrom: DateFormat('yyyy-MM-dd').format(picked)));
                      }
                    },
                    onClear: () => setState(
                        () => _draft = _draft.copyWith(dateFrom: null)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateButton(
                    label: 'To',
                    value: _draft.dateTo,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _draft.dateTo != null
                            ? DateTime.parse(_draft.dateTo!)
                            : DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _draft = _draft.copyWith(
                            dateTo: DateFormat('yyyy-MM-dd').format(picked)));
                      }
                    },
                    onClear: () =>
                        setState(() => _draft = _draft.copyWith(dateTo: null)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref
                          .read(filterProvider.notifier)
                          .state = const SessionFilter();
                      Navigator.pop(context);
                    },
                    child: const Text('Clear All'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      ref.read(filterProvider.notifier).state = _draft;
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final display = value != null
        ? DateFormat('MMM d, yyyy').format(DateTime.parse(value!))
        : 'Any';
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          Text(display, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  final List<SessionModel> sessions;

  const _SessionList({required this.sessions});

  Map<String, List<SessionModel>> _groupByMonth() {
    final map = <String, List<SessionModel>>{};
    for (final s in sessions) {
      final key = DateFormat('MMMM yyyy').format(DateTime.parse(s.date));
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByMonth();
    // One display currency for the month subtotals (sessions can be mixed-
    // currency); mirror StatsFilter's choice — the most recent session's.
    final displayCurrency = mostRecentSession(sessions)?.currency ?? 'USD';
    final slivers = <Widget>[
      const SliverPadding(padding: EdgeInsets.only(top: 8))
    ];

    for (final entry in groups.entries) {
      // Native subtotal per currency — the header renders these honestly
      // (exact when the month is single-currency, both when two, converted
      // ≈ with a tap-to-break-down when 3+). See _MonthHeaderDelegate.
      final byCurrency = <String, double>{};
      for (final s in entry.value) {
        byCurrency.update(s.currency, (v) => v + s.profitLoss,
            ifAbsent: () => s.profitLoss);
      }
      slivers.add(SliverPersistentHeader(
        pinned: true,
        delegate: _MonthHeaderDelegate(
          month: entry.key,
          byCurrency: byCurrency,
          count: entry.value.length,
          displayCurrency: displayCurrency,
        ),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => SessionTile(
            session: entry.value[i],
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) =>
                    SessionDetailScreen(session: entry.value[i]),
              ),
            ),
          ),
          childCount: entry.value.length,
        ),
      ));
    }

    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 88)));
    return CustomScrollView(slivers: slivers);
  }
}

class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String month;

  /// Native profit subtotal per currency for the month.
  final Map<String, double> byCurrency;
  final int count;

  /// Currency the 3+-currency case converts to (the app-wide display currency).
  final String displayCurrency;

  _MonthHeaderDelegate({
    required this.month,
    required this.byCurrency,
    required this.count,
    required this.displayCurrency,
  });

  @override
  double get maxExtent => 40;
  @override
  double get minExtent => 40;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    // Largest (by magnitude) currency first, for a stable, sensible order.
    final entries = byCurrency.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    Widget netText(double net, String cur) => Text(
          formatPLWithCurrency(net, cur),
          style: theme.textTheme.labelLarge?.copyWith(
            color: net >= 0 ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        );

    // Tiered: 1 currency → exact native; 2 → both native subtotals; 3+ →
    // converted ≈ total, tappable for the per-currency breakdown.
    Widget summary;
    VoidCallback? onTap;
    if (entries.length <= 1) {
      final e = entries.isEmpty ? null : entries.first;
      summary = netText(e?.value ?? 0, e?.key ?? displayCurrency);
    } else if (entries.length == 2) {
      summary = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          netText(entries[0].value, entries[0].key),
          Text('  ·  ',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          netText(entries[1].value, entries[1].key),
        ],
      );
    } else {
      final converted = entries.fold<double>(
          0, (a, e) => a + convertCurrency(e.value, e.key, displayCurrency));
      onTap = () => _showBreakdown(context, entries, converted);
      summary = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('≈ ',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          netText(converted, displayCurrency),
          const SizedBox(width: 3),
          Icon(Icons.info_outline,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
        ],
      );
    }

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Flexible + ellipsis so a long month label can't overflow the row
        // (the FittedBox only scales the summary side, not the month).
        Flexible(
          child: Text(
            month,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Scale the (possibly two-currency) summary down rather than overflow.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                summary,
                const SizedBox(width: 6),
                Text('· $count',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(child: content),
        ),
      ),
    );
  }

  void _showBreakdown(BuildContext context,
      List<MapEntry<String, double>> entries, double converted) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        Color c(double v) => v >= 0 ? Colors.green : Colors.red;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$month · $count sessions',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key, style: theme.textTheme.bodyLarge),
                        Text(formatPLWithCurrency(e.value, e.key),
                            style: theme.textTheme.bodyLarge?.copyWith(
                                color: c(e.value),
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('≈ Total ($displayCurrency)',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(formatPLWithCurrency(converted, displayCurrency),
                        style: theme.textTheme.bodyLarge?.copyWith(
                            color: c(converted),
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Converted at approximate static rates.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  bool shouldRebuild(_MonthHeaderDelegate old) =>
      old.month != month ||
      old.count != count ||
      old.displayCurrency != displayCurrency ||
      !mapEquals(old.byCurrency, byCurrency);
}
