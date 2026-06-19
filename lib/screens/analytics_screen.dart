import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../models/stats_filter.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';
import '../widgets/game_type_filter.dart';
import 'metric_chart_screen.dart';

class AnalyticsScreen extends ConsumerWidget {
  final StatsFilter filter;

  const AnalyticsScreen({super.key, this.filter = const StatsFilter()});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(completedSessionsProvider);
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      // The body shows the game-type pills + summary metrics even with no
      // sessions (zeros), so new users see structure rather than a blank page.
      data: (sessions) => _AnalyticsBody(sessions: sessions, filter: filter),
    );
  }
}

class _AnalyticsBody extends StatefulWidget {
  final List<SessionModel> sessions;
  final StatsFilter filter;

  const _AnalyticsBody({required this.sessions, required this.filter});

  @override
  State<_AnalyticsBody> createState() => _AnalyticsBodyState();
}

class _AnalyticsBodyState extends State<_AnalyticsBody> {
  // null = not yet chosen (defaults to the last-played game type). An empty
  // set means "all game types".
  Set<String>? _gameTypes;

  Set<String> get _effectiveTypes =>
      _gameTypes ?? defaultGameTypes(widget.sessions);

  // Read-only labels describing the active filters, shown on each chart screen.
  List<String> _activeFilterLabels(String displayCurrency) {
    final gt = gameTypeChipLabel(_effectiveTypes);
    return [
      if (gt != null) gt,
      ...widget.filter.labels(),
      displayCurrency,
    ];
  }

  String get _effectiveCurrency => widget.filter.effectiveCurrency(widget.sessions);

  List<SessionModel> get _filtered =>
      filterByGameTypes(widget.filter.apply(widget.sessions), _effectiveTypes);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final hPad = isWide ? math.max(16.0, (screenWidth - 960.0) / 2) : 16.0;
    final filtered = _filtered;
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
    final totalExpenses = filtered.fold(
        0.0, (sum, s) => sum + toD(s.totalExpenses, s.currency));
    final hasExpenses = totalExpenses > 0;
    final netAfterExpenses = totalPL - totalExpenses;
    final hourlyRate = totalHours > 0 ? totalPL / totalHours : 0.0;
    final rateColor = hourlyRate >= 0 ? Colors.green : Colors.red;
    final plColor = totalPL >= 0 ? Colors.green : Colors.red;
    final tSessions =
        filtered.where((s) => isTournamentType(s.gameType)).toList();
    final hasTournaments = tSessions.isNotEmpty;
    // Pooled ROI (total profit / total buy-in) — matches the Overview ROI tile
    // and the metric chart; a per-session average would overweight small
    // buy-ins and disagree with the chart it drills into.
    final tournamentBuyIn =
        tSessions.fold(0.0, (sum, s) => sum + toD(s.buyIn, s.currency));
    final tournamentPL =
        tSessions.fold(0.0, (sum, s) => sum + toD(s.profitLoss, s.currency));
    final tournamentROI = hasTournaments && tournamentBuyIn > 0
        ? tournamentPL / tournamentBuyIn * 100
        : (hasTournaments ? 0.0 : null);
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
      _SummaryItem('Sessions', '${filtered.length}', null, StatMetric.sessions),
      _SummaryItem('Hours', formatHours(totalHours), null, StatMetric.hours),
      _SummaryItem(
        'Win Rate',
        '$rateSign$sym${hourlyRate.abs().toStringAsFixed(0)}/hr',
        rateColor,
        StatMetric.winRate,
      ),
      _SummaryItem(
        'Total Profit',
        formatPLWithCurrency(totalPL, displayCurrency),
        plColor,
        StatMetric.profit,
      ),
      _SummaryItem(
          'Buy-In', formatAmount(totalBuyIn, displayCurrency), null,
          StatMetric.buyIn),
      if (hasExpenses)
        _SummaryItem('Expenses', '-$sym${totalExpenses.toStringAsFixed(0)}',
            null, StatMetric.expenses),
      if (hasExpenses)
        _SummaryItem(
          'Net Profit',
          formatPLWithCurrency(netAfterExpenses, displayCurrency),
          netAfterExpenses >= 0 ? Colors.green : Colors.red,
          StatMetric.netAfterExpenses,
        ),
      if (bb100 != null)
        _SummaryItem(
          'BB/100',
          formatBB100(bb100),
          bb100 >= 0 ? Colors.green : Colors.red,
          StatMetric.bb100,
        ),
      if (tournamentROI != null)
        _SummaryItem(
          'Tourn. ROI',
          formatROI(tournamentROI),
          tournamentROI >= 0 ? Colors.green : Colors.red,
          StatMetric.roi,
        ),
      if (itmPct != null)
        _SummaryItem('ITM', '$itmPct%', null, StatMetric.itmPct),
    ];

    return CustomScrollView(
      slivers: [
        // ── Game-type filter pills (always shown) ─────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
            child: GameTypeFilterChips(
              selected: _effectiveTypes,
              onChanged: (v) => setState(() => _gameTypes = v),
            ),
          ),
        ),

        // ── Metric summary (always) + data-dependent breakdowns ───────────
        SliverPadding(
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 88),
          sliver: SliverList.list(
            children: [
              _MetricSummaryList(
                items: summaryItems,
                sessions: filtered,
                displayCurrency: displayCurrency,
                activeFilters: _activeFilterLabels(displayCurrency),
              ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      // Distinguish "you have no data yet" from "your filters
                      // hid everything" — otherwise an established user who
                      // filters to an empty range is wrongly told to log a
                      // session.
                      widget.sessions.isEmpty
                          ? 'Log a session to unlock breakdowns and trends.'
                          : 'No sessions match these filters.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                )
              else ...[
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
                if (showingCash && showingTournaments) ...[
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
                if (showingCash && showingTournaments) ...[
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
            ],
          ),
        ),
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

// ─── Metric summary (one per row, tappable → full-screen trend chart) ─────────

class _SummaryItem {
  final String label;
  final String value;
  final Color? color;
  final StatMetric? metric;
  const _SummaryItem(this.label, this.value, [this.color, this.metric]);
}

/// The Analytics summary, rendered one metric per row. Each row is a CTA that
/// opens the metric's full-screen trend chart (mirrors the Overview tab).
class _MetricSummaryList extends StatelessWidget {
  final List<_SummaryItem> items;
  final List<SessionModel> sessions;
  final String displayCurrency;
  final List<String> activeFilters;

  const _MetricSummaryList({
    required this.items,
    required this.sessions,
    required this.displayCurrency,
    this.activeFilters = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            _row(context, items[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _SummaryItem item) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(item.label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(item.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: item.color,
              )),
          if (item.metric != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );

    if (item.metric == null) return body;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MetricChartScreen(
            metric: item.metric!,
            sessions: sessions,
            displayCurrency: displayCurrency,
            activeFilters: activeFilters,
          ),
        ),
      ),
      child: body,
    );
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
              const SizedBox(height: 16),
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

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label gets its own full-width line so long names (e.g. casinos,
        // "Evening (6pm–11pm)") aren't clipped by the figures beside them.
        Text(label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        // Figures: hours/entries on the left, $/hr + profit on the right.
        Row(
          children: [
            Text(
              isTournament ? '${stats.count}×' : formatHours(stats.totalHours),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const Spacer(),
            Text(
              isTournament
                  ? formatROI(stats.roi)
                  : '${formatPLWithCurrency(stats.hourlyRate, displayCurrency)}/hr',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: barColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Text(
              formatPLWithCurrency(stats.totalPL, displayCurrency),
              style: theme.textTheme.bodyMedium?.copyWith(
                    color: stats.totalPL >= 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (_, constraints) {
            const barHeight = 12.0;
            final totalWidth = constraints.maxWidth;
            final halfWidth = totalWidth / 2;
            final isPositive = primaryValue >= 0;
            final barWidth = (halfWidth * barFraction).clamp(0.0, halfWidth);
            return Stack(
              children: [
                // Background track
                Container(
                  height: barHeight,
                  width: totalWidth,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(barHeight / 2),
                  ),
                ),
                // Positive bar extends right from center; negative extends left
                Positioned(
                  left: isPositive ? halfWidth : halfWidth - barWidth,
                  child: Container(
                    height: barHeight,
                    width: barWidth,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),
                ),
                // Zero center tick
                Positioned(
                  left: halfWidth - 0.5,
                  child: Container(
                      height: barHeight,
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

// ─── Stats filter bottom sheet (shared by Overview + Analytics) ───────────────

class StatsFilterSheet extends StatefulWidget {
  final StatsFilter filter;
  final String effectiveCurrency;
  final List<String> allCountries;
  final bool hasMultipleCountries;
  final bool hasOnline;
  final bool hasLive;
  final List<String> allLocations;
  final ValueChanged<StatsFilter> onApply;
  final VoidCallback onReset;

  const StatsFilterSheet({
    super.key,
    required this.filter,
    required this.effectiveCurrency,
    required this.allCountries,
    required this.hasMultipleCountries,
    required this.hasOnline,
    required this.hasLive,
    required this.allLocations,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<StatsFilterSheet> createState() => _StatsFilterSheetState();
}

class _StatsFilterSheetState extends State<StatsFilterSheet> {
  late String _currency;
  late Set<String> _country;
  late String? _venue;
  late Set<String> _location;
  late String? _datePreset;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _currency = widget.filter.displayCurrency ?? widget.effectiveCurrency;
    _country = {...widget.filter.country};
    _venue = widget.filter.venue;
    _location = {...widget.filter.location};
    _datePreset = widget.filter.datePreset;
    _dateRange = widget.filter.dateRange;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _dateRange,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _dateRange = picked;
      _datePreset = null;
    });
  }

  String _summary(Set<String> sel, String allLabel, String noun) =>
      sel.isEmpty
          ? allLabel
          : (sel.length == 1 ? sel.first : '${sel.length} $noun');

  /// A collapsed filter section: only the parent (title + current-selection
  /// summary) shows until tapped — keeps the sheet compact even with 100+
  /// locations. Borders are suppressed for a clean list look.
  Widget _section({
    required String title,
    required String summary,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('filter_$title'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        initiallyExpanded: initiallyExpanded,
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(summary,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        children: children,
      ),
    );
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
            const SizedBox(height: 8),

            // ── Date Range (presets + custom range) ─────────────────────────
            _section(
              title: 'Date Range',
              summary: StatsFilter(
                      datePreset: _dateRange == null ? _datePreset : null,
                      dateRange: _dateRange)
                  .dateSummary,
              children: [
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
                        selected: _dateRange == null && _datePreset == entry.$1,
                        onSelected: (_) => setState(() {
                          _datePreset = entry.$1;
                          _dateRange = null;
                        }),
                      ),
                    ChoiceChip(
                      avatar: const Icon(Icons.event, size: 18),
                      label: Text(_dateRange == null
                          ? 'Custom…'
                          : StatsFilter(dateRange: _dateRange).dateLabel!),
                      selected: _dateRange != null,
                      onSelected: (_) => _pickRange(),
                    ),
                  ],
                ),
              ],
            ),

            // ── Currency ────────────────────────────────────────────────────
            _section(
              title: 'Currency',
              summary: '$_currency ${currencySymbol(_currency)}',
              children: [
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
              ],
            ),

            // ── Country (only if multiple) ──────────────────────────────────
            if (widget.hasMultipleCountries)
              _section(
                title: 'Country',
                summary: _summary(_country, 'All countries', 'selected'),
                children: [
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
              ),

            // ── Venue (only if both live and online exist) ──────────────────
            if (widget.hasLive && widget.hasOnline)
              _section(
                title: 'Venue',
                summary: _venue == null
                    ? 'All venues'
                    : (_venue == 'online' ? 'Online' : 'Live'),
                children: [
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
              ),

            // ── Location (only if multiple) ─────────────────────────────────
            if (widget.allLocations.length > 1)
              _section(
                title: 'Location',
                summary: _summary(_location, 'All locations', 'selected'),
                children: [
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
              ),

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
                      widget.onApply(StatsFilter(
                        displayCurrency: _currency,
                        country: _country,
                        venue: _venue,
                        location: _location,
                        datePreset: _dateRange == null ? _datePreset : null,
                        dateRange: _dateRange,
                      ));
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
