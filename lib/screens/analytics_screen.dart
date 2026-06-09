import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';

class AnalyticsScreen extends ConsumerWidget {
  final String? venueFilter;
  final Set<String> countryFilter;
  final Set<String> locationFilter;
  final String? displayCurrency;
  final String? dateFilter;

  const AnalyticsScreen({
    super.key,
    this.venueFilter,
    this.countryFilter = const {},
    this.locationFilter = const {},
    this.displayCurrency,
    this.dateFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (sessions) {
        if (sessions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Log some sessions to see analytics here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return _AnalyticsBody(
          sessions: sessions,
          venueFilter: venueFilter,
          countryFilter: countryFilter,
          locationFilter: locationFilter,
          displayCurrency: displayCurrency,
          dateFilter: dateFilter,
        );
      },
    );
  }
}

class _AnalyticsBody extends StatefulWidget {
  final List<SessionModel> sessions;
  final String? venueFilter;
  final Set<String> countryFilter;
  final Set<String> locationFilter;
  final String? displayCurrency;
  final String? dateFilter;

  const _AnalyticsBody({
    required this.sessions,
    this.venueFilter,
    this.countryFilter = const {},
    this.locationFilter = const {},
    this.displayCurrency,
    this.dateFilter,
  });

  @override
  State<_AnalyticsBody> createState() => _AnalyticsBodyState();
}

class _AnalyticsBodyState extends State<_AnalyticsBody> {
  String? _gameFilter;

  String get _effectiveCurrency {
    if (widget.displayCurrency != null) return widget.displayCurrency!;
    if (widget.sessions.isEmpty) return 'CAD';
    return widget.sessions
        .reduce((a, b) => a.date.compareTo(b.date) >= 0 ? a : b)
        .currency;
  }

  List<SessionModel> get _filtered {
    var result = widget.sessions;
    if (widget.dateFilter != null) {
      final days = switch (widget.dateFilter!) {
        '1M' => 30,
        '3M' => 90,
        '6M' => 180,
        '1Y' => 365,
        _ => 0,
      };
      if (days > 0) {
        final cutoff = DateTime.now().subtract(Duration(days: days));
        result = result.where((s) {
          final d = DateTime.tryParse(s.date);
          return d != null && d.isAfter(cutoff);
        }).toList();
      }
    }
    if (widget.countryFilter.isNotEmpty) {
      result =
          result.where((s) => widget.countryFilter.contains(s.country)).toList();
    }
    if (_gameFilter != null) {
      if (_gameFilter == 'tournament') {
        result = result.where((s) => isTournamentType(s.gameType)).toList();
      } else {
        result = result.where((s) => s.gameType == 'cash').toList();
      }
    }
    if (widget.venueFilter == 'online') {
      result = result.where((s) => isOnlineSession(s.location)).toList();
    } else if (widget.venueFilter == 'live') {
      result = result.where((s) => !isOnlineSession(s.location)).toList();
    }
    if (widget.locationFilter.isNotEmpty) {
      result = result
          .where((s) =>
              s.location != null && widget.locationFilter.contains(s.location))
          .toList();
    }
    return result;
  }

  // Intentionally check ALL sessions (unfiltered) so the game-type chip strip
  // doesn't vanish when the active filter hides one type.
  bool get _hasCash => widget.sessions.any((s) => s.gameType == 'cash');
  bool get _hasTournament =>
      widget.sessions.any((s) => isTournamentType(s.gameType));

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final hPad = isWide ? math.max(16.0, (screenWidth - 960.0) / 2) : 16.0;
    final filtered = _filtered;
    final sorted = [...filtered]..sort((a, b) => a.date.compareTo(b.date));
    final displayCurrency = _effectiveCurrency;
    final showingTournaments = filtered.any((s) => isTournamentType(s.gameType));
    final showingCash = filtered.any((s) => s.gameType == 'cash');
    // Use filtered counts for insight-card visibility (not all-time counts).
    final hasLiveInView = filtered.any((s) => !isOnlineSession(s.location));
    final hasOnlineInView = filtered.any((s) => isOnlineSession(s.location));

    // ── Summary stats for pinned header ──────────────────────────────────────
    double toD(double amount, String from) =>
        convertCurrency(amount, from, displayCurrency);
    final sym = currencySymbol(displayCurrency);
    final totalHours =
        filtered.fold(0, (s, e) => s + e.durationMinutes) / 60.0;
    final totalPL =
        filtered.fold(0.0, (sum, s) => sum + toD(s.profitLoss, s.currency));
    final totalBuyIn =
        filtered.fold(0.0, (sum, s) => sum + toD(s.buyIn, s.currency));
    final hourlyRate = totalHours > 0 ? totalPL / totalHours : 0.0;
    final rateColor = hourlyRate >= 0 ? Colors.green : Colors.red;
    final plColor = totalPL >= 0 ? Colors.green : Colors.red;
    final tSessions =
        filtered.where((s) => isTournamentType(s.gameType)).toList();
    final hasTournaments = tSessions.isNotEmpty;
    final tournamentROI = hasTournaments
        ? tSessions.fold(
                0.0,
                (sum, s) =>
                    sum + (s.buyIn > 0 ? s.profitLoss / s.buyIn * 100 : 0.0)) /
            tSessions.length
        : null;
    final itmCount = hasTournaments
        ? tSessions
            .where((s) => isSessionItm(s.prizeWon, s.profitLoss))
            .length
        : null;
    final itmPct = (itmCount != null && tSessions.isNotEmpty)
        ? (itmCount / tSessions.length * 100).round()
        : null;
    final rateSign = hourlyRate >= 0 ? '+' : '-';
    final cashSessions = filtered.where((s) => s.gameType == 'cash').toList();
    final bb100 = calcBB100(cashSessions);

    final summaryItems = <_SummaryItem>[
      _SummaryItem('Sessions', '${filtered.length}'),
      _SummaryItem('Hours', formatHours(totalHours)),
      _SummaryItem(
        'Win Rate',
        '$rateSign$sym${hourlyRate.abs().toStringAsFixed(0)}/hr',
        rateColor,
      ),
      _SummaryItem(
        'Total Profit',
        formatPLWithCurrency(totalPL, displayCurrency),
        plColor,
      ),
      _SummaryItem('Buy-In', formatAmount(totalBuyIn, displayCurrency)),
      if (bb100 != null)
        _SummaryItem(
          'BB/100',
          formatBB100(bb100),
          bb100 >= 0 ? Colors.green : Colors.red,
        ),
      if (tournamentROI != null)
        _SummaryItem(
          'Tourn. ROI',
          formatROI(tournamentROI),
          tournamentROI >= 0 ? Colors.green : Colors.red,
        ),
      if (itmPct != null) _SummaryItem('ITM', '$itmPct%'),
    ];

    final summaryCols =
        isWide ? (summaryItems.length <= 6 ? summaryItems.length : 4) : 3;

    return CustomScrollView(
      slivers: [
        // ── Game-type chip strip (scrolls away) ───────────────────────────
        if (_hasCash && _hasTournament)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in [
                      (null, 'All'),
                      ('cash', 'Cash'),
                      ('tournament', 'Tournament'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(entry.$2),
                          selected: _gameFilter == entry.$1,
                          onSelected: (_) =>
                              setState(() => _gameFilter = entry.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

        if (filtered.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text('No sessions match this filter.')),
          )
        else ...[
          // ── Compact pinned summary ─────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _SummaryDelegate(
              items: summaryItems,
              columns: summaryCols,
              labelSize: isWide ? 12.0 : 11.0,
              valueSize: isWide ? 16.0 : 15.0,
              rowHeight: isWide ? 52.0 : 48.0,
              hPad: hPad,
            ),
          ),

          // ── Charts and insight cards ───────────────────────────────────
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 88),
            sliver: SliverList.list(
              children: [
                _PLChart(
                    sessions: sorted, displayCurrency: displayCurrency),
                const SizedBox(height: 20),

                // Section header changes based on the primary game type in view.
                _sectionHeader(
                  context,
                  (showingTournaments && !showingCash)
                      ? "What's Affecting Your ROI"
                      : "What's Affecting Your Win Rate",
                ),
                Text(
                  (showingTournaments && !showingCash)
                      ? 'entries  ·  ROI  ·  Profit'
                      : 'hrs  ·  $sym/hr  ·  Profit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 8),

                // ── Cash-only insight cards ──────────────────────────────────
                if (showingCash) ...[
                  _InsightCard(
                    title: 'By Stakes',
                    sessions: filtered
                        .where((s) => s.gameType == 'cash')
                        .toList(),
                    keyFn: (s) => s.stakes,
                    displayCurrency: displayCurrency,
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Tournament insight cards ─────────────────────────────────
                if (showingTournaments) ...[
                  _InsightCard(
                    title: 'By Buy-in Level',
                    sessions: filtered
                        .where((s) => isTournamentType(s.gameType))
                        .toList(),
                    keyFn: (s) => tournamentBuyInBucket(s.buyIn),
                    orderedKeys: const [
                      '< \$50',
                      '\$50–\$100',
                      '\$100–\$200',
                      '\$200–\$500',
                      '> \$500'
                    ],
                    displayCurrency: displayCurrency,
                    isTournament: true,
                  ),
                  const SizedBox(height: 8),
                  // Field size — only shown when enough sessions have entrant counts
                  if (filtered
                          .where((s) =>
                              isTournamentType(s.gameType) &&
                              (s.totalEntrants ?? 0) > 0)
                          .length >=
                      2) ...[
                    _InsightCard(
                      title: 'By Field Size',
                      sessions: filtered
                          .where((s) =>
                              isTournamentType(s.gameType) &&
                              (s.totalEntrants ?? 0) > 0)
                          .toList(),
                      keyFn: (s) => fieldSizeBucket(s.totalEntrants),
                      orderedKeys: const [
                        'Small (<50)',
                        'Medium (50–200)',
                        'Large (200–500)',
                        'Massive (500+)',
                      ],
                      displayCurrency: displayCurrency,
                      isTournament: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],

                // ── Mixed game-type card (shown when both are in view) ───────
                if (_gameFilter == null &&
                    showingCash &&
                    showingTournaments) ...[
                  _InsightCard(
                    title: 'By Game Type',
                    sessions: filtered,
                    keyFn: (s) => gameTypeLabel(s.gameType),
                    displayCurrency: displayCurrency,
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Shared insight cards ─────────────────────────────────────
                _InsightCard(
                  title: 'By Day of Week',
                  sessions: filtered,
                  keyFn: (s) => dayOfWeekLabel(s.date),
                  orderedKeys: const [
                    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
                  ],
                  displayCurrency: displayCurrency,
                  isTournament: showingTournaments && !showingCash,
                ),
                const SizedBox(height: 8),

                // Time of Day — cash or mixed only; less actionable for tournaments
                if (showingCash) ...[
                  _InsightCard(
                    title: 'By Time of Day',
                    sessions: filtered
                        .where((s) => s.gameType == 'cash')
                        .toList(),
                    keyFn: (s) => timeOfDayBucket(s.startTime),
                    displayCurrency: displayCurrency,
                  ),
                  const SizedBox(height: 8),
                ],

                // Session Length — cash only (for tournaments duration = finish depth, not actionable input)
                if (showingCash) ...[
                  _InsightCard(
                    title: 'By Session Length',
                    sessions: filtered
                        .where((s) => s.gameType == 'cash')
                        .toList(),
                    keyFn: (s) => sessionLengthBucket(s.durationMinutes),
                    orderedKeys: const [
                      '< 2 hours', '2–4 hours', '4–6 hours', '> 6 hours'
                    ],
                    displayCurrency: displayCurrency,
                  ),
                  const SizedBox(height: 8),
                ],

                // Table Quality — cash only
                if (showingCash &&
                    filtered.any((s) =>
                        s.tableQuality != null &&
                        s.gameType == 'cash')) ...[
                  _InsightCard(
                    title: 'By Table Quality',
                    sessions: filtered
                        .where((s) =>
                            s.tableQuality != null &&
                            s.gameType == 'cash')
                        .toList(),
                    keyFn: (s) =>
                        '${s.tableQuality}★ ${tableQualityLabel(s.tableQuality)}',
                    orderedKeys: List.generate(
                        5, (i) => '${i + 1}★ ${tableQualityLabel(i + 1)}'),
                    displayCurrency: displayCurrency,
                  ),
                  const SizedBox(height: 8),
                ],

                if (_hasMultipleLocations(filtered)) ...[
                  _InsightCard(
                    title: 'By Location',
                    sessions: filtered
                        .where((s) => s.location?.isNotEmpty == true)
                        .toList(),
                    keyFn: (s) => s.location!,
                    displayCurrency: displayCurrency,
                    isTournament: showingTournaments && !showingCash,
                  ),
                  const SizedBox(height: 8),
                ],
                if (hasLiveInView && hasOnlineInView) ...[
                  _InsightCard(
                    title: 'Live vs Online',
                    sessions: filtered,
                    keyFn: (s) =>
                        isOnlineSession(s.location) ? 'Online' : 'Live',
                    orderedKeys: const ['Live', 'Online'],
                    displayCurrency: displayCurrency,
                    isTournament: showingTournaments && !showingCash,
                  ),
                ],

                // ── Recommendations (the takeaway drawn from the breakdowns
                //    above — lives at the bottom as a conclusion). ──────────
                const SizedBox(height: 20),
                _sectionHeader(context, 'Recommendations'),
                const SizedBox(height: 8),
                if (_gameFilter == null &&
                    showingCash &&
                    showingTournaments) ...[
                  _RecommendationsCard(
                    sessions:
                        filtered.where((s) => s.gameType == 'cash').toList(),
                    gameLabel: 'cash',
                    displayCurrency: displayCurrency,
                  ),
                  const SizedBox(height: 8),
                  _RecommendationsCard(
                    sessions: filtered
                        .where((s) => isTournamentType(s.gameType))
                        .toList(),
                    gameLabel: 'tournament',
                    displayCurrency: displayCurrency,
                  ),
                ] else if (showingCash)
                  _RecommendationsCard(
                    sessions:
                        filtered.where((s) => s.gameType == 'cash').toList(),
                    gameLabel: 'cash',
                    displayCurrency: displayCurrency,
                  )
                else if (showingTournaments)
                  _RecommendationsCard(
                    sessions: filtered
                        .where((s) => isTournamentType(s.gameType))
                        .toList(),
                    gameLabel: 'tournament',
                    displayCurrency: displayCurrency,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool _hasMultipleLocations(List<SessionModel> sessions) {
    final locs = sessions
        .map((s) => s.location)
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toSet();
    return locs.length > 1;
  }

  Widget _sectionHeader(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

// ─── Compact Pinned Summary ───────────────────────────────────────────────────

class _SummaryItem {
  final String label;
  final String value;
  final Color? color;
  const _SummaryItem(this.label, this.value, [this.color]);
}

class _SummaryDelegate extends SliverPersistentHeaderDelegate {
  final List<_SummaryItem> items;
  final int columns;
  final double labelSize;
  final double valueSize;
  final double rowHeight;
  final double hPad;

  static const double _vPad = 6.0;
  static const double _borderH = 1.0;

  const _SummaryDelegate({
    required this.items,
    this.columns = 3,
    this.labelSize = 10.0,
    this.valueSize = 12.0,
    this.rowHeight = 38.0,
    this.hPad = 16.0,
  });

  int get _rowCount => (items.length / columns).ceil();

  @override
  double get minExtent => _rowCount * rowHeight + _vPad * 2 + _borderH;

  @override
  double get maxExtent => minExtent;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate old) => true;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final rows = <List<_SummaryItem>>[];
    for (int i = 0; i < items.length; i += columns) {
      rows.add(items.sublist(i, math.min(i + columns, items.length)));
    }
    return Material(
      color: theme.colorScheme.surface,
      elevation: overlapsContent ? 2 : 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: _vPad, horizontal: hPad),
            child: Column(
              children: rows
                  .map((row) => SizedBox(
                        height: rowHeight,
                        child: Row(
                          children: List.generate(
                            columns,
                            (i) => Expanded(
                              child: i < row.length
                                  ? _cell(theme, row[i])
                                  : const SizedBox(),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Divider(
            height: _borderH,
            thickness: _borderH,
            color: theme.colorScheme.outline.withAlpha(40),
          ),
        ],
      ),
    );
  }

  Widget _cell(ThemeData theme, _SummaryItem item) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(item.label,
              style: TextStyle(fontSize: labelSize, color: theme.colorScheme.outline)),
          Text(item.value,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.bold,
                color: item.color,
              )),
        ],
      );
}

// ─── P&L Chart ────────────────────────────────────────────────────────────────

enum _PLMode { cumulative, weekly, monthly, yearly }

enum _Lookback { all, oneYear, sixMonths, threeMonths, oneMonth }

class _PLChart extends StatefulWidget {
  final List<SessionModel> sessions;
  final String displayCurrency;
  // When true, render the cumulative graph filling the available height (used
  // by the full-screen view) — no card, no title, no mode toggle.
  final bool fullScreen;
  final _Lookback initialLookback;
  const _PLChart({
    required this.sessions,
    required this.displayCurrency,
    this.fullScreen = false,
    this.initialLookback = _Lookback.all,
  });

  @override
  State<_PLChart> createState() => _PLChartState();
}

class _PLChartFullScreen extends StatelessWidget {
  final List<SessionModel> sessions;
  final String displayCurrency;
  final _Lookback initialLookback;
  const _PLChartFullScreen({
    required this.sessions,
    required this.displayCurrency,
    this.initialLookback = _Lookback.all,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profit Over Time')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _PLChart(
          sessions: sessions,
          displayCurrency: displayCurrency,
          fullScreen: true,
          initialLookback: initialLookback,
        ),
      ),
    );
  }
}

class _PLChartState extends State<_PLChart> {
  _PLMode _mode = _PLMode.cumulative;
  late _Lookback _lookback = widget.initialLookback;
  final Set<String> _expandedYears = {DateTime.now().year.toString()};

  static const _modeLabels = {
    _PLMode.cumulative: 'Cumulative',
    _PLMode.weekly: 'Weekly',
    _PLMode.monthly: 'Monthly',
    _PLMode.yearly: 'Yearly',
  };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  double _toD(double amount, String from) =>
      convertCurrency(amount, from, widget.displayCurrency);

  List<SessionModel> get _lookbackSessions {
    if (_lookback == _Lookback.all) return widget.sessions;
    final now = DateTime.now();
    final days = switch (_lookback) {
      _Lookback.oneMonth => 30,
      _Lookback.threeMonths => 90,
      _Lookback.sixMonths => 180,
      _Lookback.oneYear => 365,
      _Lookback.all => 0,
    };
    final cutoff = now.subtract(Duration(days: days));
    return widget.sessions.where((s) {
      final d = DateTime.tryParse(s.date);
      return d != null && d.isAfter(cutoff);
    }).toList();
  }

  // Lookback (All / 1Y / 6M / 3M / 1M) chip row — shared by the card and the
  // full-screen view.
  Widget _lookbackSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in [
              (_Lookback.all, 'All'),
              (_Lookback.oneYear, '1Y'),
              (_Lookback.sixMonths, '6M'),
              (_Lookback.threeMonths, '3M'),
              (_Lookback.oneMonth, '1M'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(entry.$2, style: const TextStyle(fontSize: 11)),
                  selected: _lookback == entry.$1,
                  onSelected: (_) => setState(() => _lookback = entry.$1),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sym = currencySymbol(widget.displayCurrency);

    // Full-screen: cumulative graph filling the height, with the lookback row.
    if (widget.fullScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCumulative(context, sym)),
          const SizedBox(height: 12),
          _lookbackSelector(),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Profit Over Time',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (_mode == _PLMode.cumulative)
                  IconButton(
                    icon: const Icon(Icons.open_in_full, size: 18),
                    tooltip: 'Full screen',
                    visualDensity: VisualDensity.compact,
                    color: Theme.of(context).colorScheme.outline,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _PLChartFullScreen(
                          sessions: widget.sessions,
                          displayCurrency: widget.displayCurrency,
                          initialLookback: _lookback,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Graph first — sits directly under the title so it (and its x-axis)
            // clears the fold. The view/timeframe controls live below it.
            if (_mode == _PLMode.cumulative)
              SizedBox(
                height: (MediaQuery.of(context).size.height * 0.27)
                    .clamp(170.0, 260.0),
                child: _buildCumulative(context, sym),
              )
            else
              _buildTable(context),
            const SizedBox(height: 10),
            // Mode toggle (below the graph)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _PLMode.values
                    .map((mode) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_modeLabels[mode]!,
                                style: const TextStyle(fontSize: 11)),
                            selected: _mode == mode,
                            onSelected: (_) => setState(() => _mode = mode),
                            visualDensity: VisualDensity.compact,
                          ),
                        ))
                    .toList(),
              ),
            ),
            // Lookback period selector (cumulative only, below)
            if (_mode == _PLMode.cumulative) ...[
              const SizedBox(height: 8),
              _lookbackSelector(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCumulative(BuildContext context, String sym) {
    final sessions = _lookbackSessions;
    if (sessions.length < 2) {
      return _emptyChart(context, 'Need at least 2 sessions');
    }
    double cum = 0;
    final spots = sessions.asMap().entries.map((e) {
      cum += _toD(e.value.profitLoss, e.value.currency);
      return FlSpot(e.key.toDouble(), cum);
    }).toList();
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY).abs() * 0.1 + 50;
    final color = cum >= 0 ? Colors.green : Colors.red;
    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withAlpha(30)),
        ),
      ],
      lineTouchData: LineTouchData(
        // fl_chart hover crashes on Windows — disable there, keep on web/Android.
        enabled: kIsWeb || !Platform.isWindows,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
          getTooltipItems: (spots) => spots.map((spot) {
            final idx = spot.x.toInt().clamp(0, sessions.length - 1);
            final date = DateTime.tryParse(sessions[idx].date) ?? DateTime.now();
            final label = '${_months[date.month - 1]} ${date.day}, ${date.year}';
            final sign = spot.y >= 0 ? '+' : '-';
            return LineTooltipItem(
              '$label\n$sign$sym${spot.y.abs().toStringAsFixed(0)}',
              TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  fontSize: 11,
                  height: 1.4),
            );
          }).toList(),
        ),
      ),
      minY: minY - padding,
      maxY: maxY + padding,
      titlesData: _leftTitlesOnly(sym),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Theme.of(context).colorScheme.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
    ));
  }

  Widget _buildTable(BuildContext context) {
    final sym = currencySymbol(widget.displayCurrency);
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
      fontWeight: FontWeight.bold,
    );

    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Period', style: headerStyle)),
          Expanded(
              flex: 2,
              child: Text('Profit ($sym)',
                  style: headerStyle, textAlign: TextAlign.right)),
          Expanded(
              flex: 1,
              child: Text('#',
                  style: headerStyle, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('$sym/hr',
                  style: headerStyle, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('Hrs',
                  style: headerStyle, textAlign: TextAlign.right)),
        ],
      ),
    );

    if (_mode == _PLMode.yearly) {
      return _buildFlatTable(context, header, theme);
    }
    return _buildNestedTable(context, header, theme);
  }

  Widget _buildFlatTable(
      BuildContext context, Widget header, ThemeData theme) {
    final periodMap = <String, ({double pl, int count, double hours})>{};
    for (final s in widget.sessions) {
      final key = _periodKey(s.date);
      final pl = _toD(s.profitLoss, s.currency);
      final hours = s.durationMinutes / 60.0;
      final existing = periodMap[key];
      if (existing == null) {
        periodMap[key] = (pl: pl, count: 1, hours: hours);
      } else {
        periodMap[key] = (
          pl: existing.pl + pl,
          count: existing.count + 1,
          hours: existing.hours + hours,
        );
      }
    }
    final entries = periodMap.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    if (entries.isEmpty) {
      return Center(
          child: Text('Not enough sessions for this view',
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.75))));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const Divider(height: 1),
        for (final e in entries) ...[
          _tableDataRow(context, _periodLabel(e.key), e.value, theme),
          Divider(
              height: 1,
              color:
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      ],
    );
  }

  Widget _buildNestedTable(
      BuildContext context, Widget header, ThemeData theme) {
    final byYear =
        <String, Map<String, ({double pl, int count, double hours})>>{};
    for (final s in widget.sessions) {
      final year = s.date.length >= 4 ? s.date.substring(0, 4) : s.date;
      final key = _periodKey(s.date);
      final pl = _toD(s.profitLoss, s.currency);
      final hours = s.durationMinutes / 60.0;
      byYear.putIfAbsent(year, () => {});
      final existing = byYear[year]![key];
      if (existing == null) {
        byYear[year]![key] = (pl: pl, count: 1, hours: hours);
      } else {
        byYear[year]![key] = (
          pl: existing.pl + pl,
          count: existing.count + 1,
          hours: existing.hours + hours,
        );
      }
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) {
      return Center(
          child: Text('Not enough sessions for this view',
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.75))));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const Divider(height: 1),
        for (final year in years)
          _buildYearSection(context, year, byYear[year]!, theme),
      ],
    );
  }

  Widget _buildYearSection(
    BuildContext context,
    String year,
    Map<String, ({double pl, int count, double hours})> periods,
    ThemeData theme,
  ) {
    double yearPL = 0;
    int yearCount = 0;
    double yearHours = 0;
    for (final p in periods.values) {
      yearPL += p.pl;
      yearCount += p.count;
      yearHours += p.hours;
    }
    final yearRate = yearHours > 0 ? yearPL / yearHours : 0.0;
    final plColor = yearPL >= 0 ? Colors.green : Colors.red;
    final rateColor = yearRate >= 0 ? Colors.green : Colors.red;
    final isExpanded = _expandedYears.contains(year);

    final sortedPeriods = periods.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _expandedYears.remove(year);
            } else {
              _expandedYears.add(year);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(year,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(_fmtNum(yearPL),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: plColor, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 1,
                  child: Text('$yearCount',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 2,
                  child: Text(_fmtNum(yearRate),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: rateColor, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 2,
                  child: Text(yearHours.toStringAsFixed(0),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          for (final e in sortedPeriods) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _tableDataRow(context, _periodLabel(e.key), e.value, theme),
            ),
            Divider(
                height: 1,
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],
      ],
    );
  }

  Widget _tableDataRow(
    BuildContext context,
    String label,
    ({double pl, int count, double hours}) data,
    ThemeData theme,
  ) {
    final plColor = data.pl >= 0 ? Colors.green : Colors.red;
    final hourlyRate = data.hours > 0 ? data.pl / data.hours : 0.0;
    final rateColor = hourlyRate >= 0 ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            flex: 2,
            child: Text(_fmtNum(data.pl),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: plColor, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('${data.count}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(_fmtNum(hourlyRate),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: rateColor, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(data.hours.toStringAsFixed(0),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  String _fmtNum(double v) => formatPL(v, '');

  String _periodKey(String dateStr) {
    return switch (_mode) {
      _PLMode.weekly => _weekKey(dateStr),
      _PLMode.monthly => dateStr.substring(0, 7),
      _PLMode.yearly => dateStr.substring(0, 4),
      _PLMode.cumulative => dateStr,
    };
  }

  String _weekKey(String dateStr) {
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  String _periodLabel(String key) {
    if (_mode == _PLMode.weekly) {
      final date = DateTime.tryParse(key) ?? DateTime.now();
      return 'Wk ${_months[date.month - 1]} ${date.day}';
    }
    if (_mode == _PLMode.monthly) {
      final parts = key.split('-');
      final month = (int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1)
          .clamp(1, 12);
      final yearSuffix =
          parts[0].length >= 4 ? parts[0].substring(2) : parts[0];
      return "${_months[month - 1]} '$yearSuffix";
    }
    return key; // yearly (cumulative never calls _buildTable)
  }

  FlTitlesData _leftTitlesOnly(String sym) => FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 64,
            getTitlesWidget: (v, _) => Text(
              _compact(v, sym),
              style: const TextStyle(fontSize: 9),
              textAlign: TextAlign.right,
            ),
          ),
        ),
      );

  String _compact(double v, String sym) {
    final abs = v.abs();
    final sign = v >= 0 ? '+' : '-';
    if (abs >= 10000) return '$sign$sym${(abs / 1000).toStringAsFixed(0)}k';
    if (abs >= 1000) return '$sign$sym${(abs / 1000).toStringAsFixed(1)}k';
    return '$sign$sym${abs.toStringAsFixed(0)}';
  }
}

// ─── Insight Cards ────────────────────────────────────────────────────────────

class _GroupStats {
  final double totalPL;
  final int count;
  final double hourlyRate;
  final double totalHours;
  final double totalBuyIn;

  _GroupStats({
    required this.totalPL,
    required this.count,
    required this.hourlyRate,
    required this.totalHours,
    required this.totalBuyIn,
  });

  double get roi => totalBuyIn > 0 ? totalPL / totalBuyIn * 100 : 0;

  factory _GroupStats.from(List<SessionModel> sessions, String displayCurrency) {
    double toD(double amount, String from) =>
        convertCurrency(amount, from, displayCurrency);
    final total =
        sessions.fold(0.0, (sum, s) => sum + toD(s.profitLoss, s.currency));
    final hours = sessions.fold(0, (s, e) => s + e.durationMinutes) / 60.0;
    final buyIn =
        sessions.fold(0.0, (sum, s) => sum + toD(s.buyIn, s.currency));
    return _GroupStats(
      totalPL: total,
      count: sessions.length,
      hourlyRate: hours > 0 ? total / hours : 0,
      totalHours: hours,
      totalBuyIn: buyIn,
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final List<SessionModel> sessions;
  final String Function(SessionModel) keyFn;
  final List<String>? orderedKeys;
  final String displayCurrency;
  final bool isTournament;

  const _InsightCard({
    required this.title,
    required this.sessions,
    required this.keyFn,
    required this.displayCurrency,
    this.orderedKeys,
    this.isTournament = false,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SessionModel>>{};
    for (final s in sessions) {
      final k = keyFn(s);
      if (k.isEmpty) continue;
      groups.putIfAbsent(k, () => []).add(s);
    }
    if (groups.length < 2) return const SizedBox.shrink();

    final stats =
        groups.map((k, v) => MapEntry(k, _GroupStats.from(v, displayCurrency)));

    List<String> keys;
    if (orderedKeys != null) {
      keys = orderedKeys!.where((k) => stats.containsKey(k)).toList();
      for (final k in stats.keys) {
        if (!keys.contains(k)) keys.add(k);
      }
    } else {
      keys = stats.keys.toList();
    }

    if (isTournament) {
      keys.sort((a, b) => stats[b]!.roi.compareTo(stats[a]!.roi));
    } else {
      keys.sort((a, b) => stats[b]!.hourlyRate.compareTo(stats[a]!.hourlyRate));
    }

    final maxAbsValue = isTournament
        ? stats.values.map((s) => s.roi.abs()).reduce((a, b) => a > b ? a : b)
        : stats.values
            .map((s) => s.hourlyRate.abs())
            .reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            for (final key in keys) ...[
              _InsightRow(
                label: key,
                stats: stats[key]!,
                maxAbsValue: maxAbsValue,
                displayCurrency: displayCurrency,
                isTournament: isTournament,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final String label;
  final _GroupStats stats;
  final double maxAbsValue;
  final String displayCurrency;
  final bool isTournament;

  const _InsightRow({
    required this.label,
    required this.stats,
    required this.maxAbsValue,
    required this.displayCurrency,
    this.isTournament = false,
  });

  @override
  Widget build(BuildContext context) {
    final primaryValue = isTournament ? stats.roi : stats.hourlyRate;
    final barColor = primaryValue >= 0 ? Colors.green : Colors.red;
    final barFraction = maxAbsValue > 0
        ? (primaryValue.abs() / maxAbsValue).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
            if (isTournament)
              Text('${stats.count}×',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ))
            else
              Text('${stats.totalHours.toStringAsFixed(1)}h',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      )),
            const SizedBox(width: 8),
            Text(
              isTournament
                  ? formatROI(stats.roi)
                  : '${formatPLWithCurrency(stats.hourlyRate, displayCurrency)}/hr',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: barColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            Text(
              formatPLWithCurrency(stats.totalPL, displayCurrency),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: stats.totalPL >= 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        LayoutBuilder(
          builder: (_, constraints) {
            final totalWidth = constraints.maxWidth;
            final halfWidth = totalWidth / 2;
            final isPositive = primaryValue >= 0;
            final barWidth = (halfWidth * barFraction).clamp(0.0, halfWidth);
            return Stack(
              children: [
                // Background track
                Container(
                  height: 4,
                  width: totalWidth,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Positive bar extends right from center; negative extends left
                Positioned(
                  left: isPositive ? halfWidth : halfWidth - barWidth,
                  child: Container(
                    height: 4,
                    width: barWidth,
                    color: barColor,
                  ),
                ),
                // Zero center tick
                Positioned(
                  left: halfWidth - 0.5,
                  child: Container(
                      height: 4,
                      width: 1,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.30)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Shared ───────────────────────────────────────────────────────────────────

Widget _emptyChart(BuildContext context, String message) => Center(
      child: Text(message,
          style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.75),
              fontSize: 13)),
    );

// ─── Recommendations (Welch's t-test, actionable) ─────────────────────────────

class _Rec {
  final IconData icon;
  final String title;
  final String explanation;
  final double tStat;

  _Rec({
    required this.icon,
    required this.title,
    required this.explanation,
    required this.tStat,
  });
}

class _RecommendationsCard extends StatelessWidget {
  final List<SessionModel> sessions;
  final String typeLabel;
  final String displayCurrency;

  const _RecommendationsCard({
    required this.sessions,
    required String gameLabel,
    required this.displayCurrency,
  }) : typeLabel = gameLabel;

  @override
  Widget build(BuildContext context) {
    if (sessions.length < 5) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Log at least 5 $typeLabel sessions to get personalised recommendations.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
    }
    final recs = _buildRecommendations();
    if (recs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No strong patterns detected yet in your $typeLabel sessions. '
            'Results become more reliable as you log more sessions across different days, locations, and stakes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Based on your session history',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < recs.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              _RecRow(rec: recs[i]),
            ],
          ],
        ),
      ),
    );
  }

  bool get _isTournament => typeLabel == 'tournament';

  double _score(SessionModel s) {
    if (_isTournament) {
      return s.buyIn > 0 ? s.profitLoss / s.buyIn * 100 : 0;
    }
    final hours = s.durationMinutes / 60.0;
    if (hours <= 0) return 0;
    return convertCurrency(s.profitLoss, s.currency, displayCurrency) / hours;
  }

  double _overallScore() {
    if (_isTournament) {
      final totalBuyIn = sessions.fold(0.0, (sum, s) => sum + s.buyIn);
      final totalPL = sessions.fold(0.0, (sum, s) => sum + s.profitLoss);
      return totalBuyIn > 0 ? totalPL / totalBuyIn * 100 : 0;
    }
    final rates = sessions.map(_score).toList();
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  double _welchT(List<double> a, List<double> b) {
    if (a.length < 2 || b.length < 2) return 0;
    final meanA = a.reduce((x, y) => x + y) / a.length;
    final meanB = b.reduce((x, y) => x + y) / b.length;
    final varA = a
            .map((x) => (x - meanA) * (x - meanA))
            .reduce((x, y) => x + y) /
        (a.length - 1);
    final varB = b
            .map((x) => (x - meanB) * (x - meanB))
            .reduce((x, y) => x + y) /
        (b.length - 1);
    final se = math.sqrt(varA / a.length + varB / b.length);
    if (se == 0) return 0;
    return (meanA - meanB) / se;
  }

  String _actionTitle(
      String dimension, String bestKey, String worstKey, double bestScore) {
    if (_isTournament) {
      switch (dimension) {
        case 'buy-in level':
          return 'Target $bestKey tournaments';
        case 'field size':
          return 'Focus on $bestKey fields';
        case 'day':
          return 'Prioritise $bestKey tournaments';
        case 'location':
          return '$bestKey is your strongest venue';
        case 'live/online':
          return bestScore > 0
              ? '$bestKey poker is your stronger format'
              : 'Shift focus to ${worstKey == bestKey ? 'the other format' : worstKey}';
        default:
          return 'Favour $bestKey over $worstKey';
      }
    }
    switch (dimension) {
      case 'time slot':
        return bestScore > 0
            ? 'Schedule more sessions in the $bestKey'
            : 'Shift sessions away from $worstKey';
      case 'day':
        return 'Prioritise $bestKey sessions';
      case 'session length':
        return 'Target $bestKey sessions';
      case 'table quality':
        return 'Seek out $bestKey tables';
      case 'location':
        return '$bestKey is your strongest venue';
      case 'game type':
        return 'Focus more on ${bestKey.toLowerCase()}';
      default:
        return 'Favour $bestKey over $worstKey';
    }
  }

  String _explanation(
      String dimension, String bestKey, String worstKey, double bestScore,
      double worstScore, double overallScore) {
    if (_isTournament) {
      final bestFmt = formatROI(bestScore);
      final worstFmt = formatROI(worstScore);
      final overallFmt = formatROI(overallScore);
      final diff = bestScore - worstScore;
      final diffFmt = formatROI(diff);
      return '$bestFmt ROI in $bestKey'
          '${diff > 0 ? ' — $diffFmt better than $worstKey ($worstFmt)' : ''}.'
          ' Your overall ROI is $overallFmt.';
    }
    final bestFmt = formatPLWithCurrency(bestScore, displayCurrency);
    final worstFmt = formatPLWithCurrency(worstScore, displayCurrency);
    final overallFmt = formatPLWithCurrency(overallScore, displayCurrency);
    final diff = bestScore - worstScore;
    final diffFmt = formatPLWithCurrency(diff, displayCurrency);
    return '$bestFmt/hr in $bestKey sessions'
        '${diff > 0 ? ' — $diffFmt/hr more than $worstKey ($worstFmt/hr)' : ''}.'
        ' Your overall rate is $overallFmt/hr.';
  }

  List<_Rec> _buildRecommendations() {
    final recs = <_Rec>[];
    final overallScore = _overallScore();

    void checkFactor({
      required String? Function(SessionModel) keyFn,
      required IconData icon,
      required String dimension,
    }) {
      if (sessions.length < 4) return;

      final grouped = <String, List<SessionModel>>{};
      for (final s in sessions) {
        final k = keyFn(s);
        if (k == null || k.isEmpty) continue;
        grouped.putIfAbsent(k, () => []).add(s);
      }

      final qualified = grouped.entries
          .where((e) => e.value.length >= 2)
          .map((e) {
            final scores = e.value.map(_score).toList();
            return (
              key: e.key,
              scores: scores,
              mean: scores.reduce((a, b) => a + b) / scores.length,
            );
          })
          .toList()
        ..sort((a, b) => b.mean.compareTo(a.mean));

      if (qualified.length < 2) return;

      final best = qualified.first;
      final worst = qualified.last;

      final restSessions = sessions
          .where((s) {
            final k = keyFn(s);
            return k != null && k != best.key;
          })
          .toList();
      if (restSessions.length < 2) return;

      final restScores = restSessions.map(_score).toList();
      final tStat = _welchT(best.scores, restScores);
      if (tStat < 1.8) return;

      recs.add(_Rec(
        icon: icon,
        title: _actionTitle(dimension, best.key, worst.key, best.mean),
        explanation: _explanation(
            dimension, best.key, worst.key, best.mean, worst.mean, overallScore),
        tStat: tStat,
      ));
    }

    if (_isTournament) {
      // Tournament factors — scored by ROI
      checkFactor(
        keyFn: (s) => tournamentBuyInBucket(s.buyIn),
        icon: Icons.attach_money,
        dimension: 'buy-in level',
      );
      checkFactor(
        keyFn: (s) => fieldSizeBucket(s.totalEntrants),
        icon: Icons.people_outline,
        dimension: 'field size',
      );
      checkFactor(
        keyFn: (s) => dayOfWeekLabel(s.date),
        icon: Icons.calendar_today,
        dimension: 'day',
      );
      checkFactor(
        keyFn: (s) => s.location?.isNotEmpty == true ? s.location : null,
        icon: Icons.location_on_outlined,
        dimension: 'location',
      );
      checkFactor(
        keyFn: (s) => isOnlineSession(s.location) ? 'Online' : 'Live',
        icon: Icons.wifi_outlined,
        dimension: 'live/online',
      );
    } else {
      // Cash factors — scored by hourly rate
      checkFactor(
        keyFn: (s) => _shortTime(timeOfDayBucket(s.startTime)),
        icon: Icons.access_time,
        dimension: 'time slot',
      );
      checkFactor(
        keyFn: (s) => dayOfWeekLabel(s.date),
        icon: Icons.calendar_today,
        dimension: 'day',
      );
      checkFactor(
        keyFn: (s) => sessionLengthBucket(s.durationMinutes),
        icon: Icons.timer_outlined,
        dimension: 'session length',
      );
      checkFactor(
        keyFn: (s) => s.tableQuality != null ? '${s.tableQuality}★' : null,
        icon: Icons.star_border,
        dimension: 'table quality',
      );
      checkFactor(
        keyFn: (s) => s.location?.isNotEmpty == true ? s.location : null,
        icon: Icons.location_on_outlined,
        dimension: 'location',
      );
    }

    recs.sort((a, b) => b.tStat.compareTo(a.tStat));
    final top = recs.take(4).toList();

    if (sessions.length < 20) {
      top.add(_Rec(
        icon: Icons.trending_up,
        title: 'Keep building your sample size',
        explanation:
            'You have ${sessions.length} $typeLabel sessions. Patterns become more reliable and actionable at 20+ sessions.',
        tStat: 0,
      ));
    }

    return top;
  }

  String _shortTime(String? bucket) {
    if (bucket == null) return '';
    if (bucket.startsWith('Morning')) return 'Morning';
    if (bucket.startsWith('Afternoon')) return 'Afternoon';
    if (bucket.startsWith('Evening')) return 'Evening';
    return 'Late Night';
  }
}

// ─── Analytics filter bottom sheet ───────────────────────────────────────────

class AnalyticsFilterSheet extends StatefulWidget {
  final String displayCurrency;
  final Set<String> countryFilter;
  final String? venueFilter;
  final Set<String> locationFilter;
  final String? dateFilter;
  final List<String> allCountries;
  final bool hasMultipleCountries;
  final bool hasOnline;
  final bool hasLive;
  final List<String> allLocations;
  final void Function(String? currency, Set<String> country, String? venue,
      Set<String> location, String? date) onApply;
  final VoidCallback onReset;

  const AnalyticsFilterSheet({
    super.key,
    required this.displayCurrency,
    required this.countryFilter,
    required this.venueFilter,
    required this.locationFilter,
    required this.dateFilter,
    required this.allCountries,
    required this.hasMultipleCountries,
    required this.hasOnline,
    required this.hasLive,
    required this.allLocations,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<AnalyticsFilterSheet> createState() => _AnalyticsFilterSheetState();
}

class _AnalyticsFilterSheetState extends State<AnalyticsFilterSheet> {
  late String _currency;
  late Set<String> _country;
  late String? _venue;
  late Set<String> _location;
  late String? _date;

  @override
  void initState() {
    super.initState();
    _currency = widget.displayCurrency;
    _country = {...widget.countryFilter};
    _venue = widget.venueFilter;
    _location = {...widget.locationFilter};
    _date = widget.dateFilter;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListView(
          controller: scroll,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Display Options', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),

            // Date Range
            Text('Date Range', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in [
                  (null, 'All Time'),
                  ('1Y', '1 Year'),
                  ('6M', '6 Months'),
                  ('3M', '3 Months'),
                  ('1M', '1 Month'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _date == entry.$1,
                    onSelected: (_) => setState(() => _date = entry.$1),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Currency
            Text('Currency', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: supportedDisplayCurrencies
                  .map((c) => ChoiceChip(
                        label: Text('$c ${currencySymbol(c)}'),
                        selected: _currency == c,
                        onSelected: (_) => setState(() => _currency = c),
                      ))
                  .toList(),
            ),

            // Country (only if multiple)
            if (widget.hasMultipleCountries) ...[
              const SizedBox(height: 20),
              Text('Country', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All Countries'),
                    selected: _country.isEmpty,
                    onSelected: (_) => setState(() => _country = {}),
                  ),
                  ...widget.allCountries.map((c) => FilterChip(
                        label: Text(c),
                        selected: _country.contains(c),
                        onSelected: (on) => setState(() {
                          final next = {..._country};
                          if (on) {
                            next.add(c);
                          } else {
                            next.remove(c);
                          }
                          _country = next;
                        }),
                      )),
                ],
              ),
            ],

            // Venue (only if both live and online exist)
            if (widget.hasLive && widget.hasOnline) ...[
              const SizedBox(height: 20),
              Text('Venue', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in [
                    (null, 'All Venues'),
                    ('live', 'Live'),
                    ('online', 'Online'),
                  ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: _venue == entry.$1,
                      onSelected: (_) => setState(() => _venue = entry.$1),
                    ),
                ],
              ),
            ],

            // Location (only if multiple locations exist)
            if (widget.allLocations.length > 1) ...[
              const SizedBox(height: 20),
              Text('Location', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All Locations'),
                    selected: _location.isEmpty,
                    onSelected: (_) => setState(() => _location = {}),
                  ),
                  ...widget.allLocations.map((l) => FilterChip(
                        label: Text(l),
                        selected: _location.contains(l),
                        onSelected: (on) => setState(() {
                          final next = {..._location};
                          if (on) {
                            next.add(l);
                          } else {
                            next.remove(l);
                          }
                          _location = next;
                        }),
                      )),
                ],
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onReset();
                      Navigator.pop(context);
                    },
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      widget.onApply(_currency, _country, _venue, _location, _date);
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

// ─── Recommendation rows ──────────────────────────────────────────────────────

class _RecRow extends StatelessWidget {
  final _Rec rec;
  const _RecRow({required this.rec});

  @override
  Widget build(BuildContext context) {
    final iconColor = rec.tStat >= 3.0
        ? Colors.green
        : rec.tStat >= 2.0
            ? Colors.amber
            : Theme.of(context).colorScheme.onSurface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(rec.icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rec.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(
                rec.explanation,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(180),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
