import 'dart:math' as math;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../models/stats_filter.dart';
import '../utils/helpers.dart';
import '../widgets/ai_coaching_card.dart';
import '../widgets/game_type_filter.dart' show gameTypeChipLabel;
import 'import_source_screen.dart';
import 'live_session_screen.dart';
import 'metric_chart_screen.dart';

/// Std-dev explainer texts — ONE copy each, shown by both the single-type
/// summary list and the combined comparison card's info dialogs.
const kCashSdInfo =
    'How swingy your cash game is, in big blinds per 100 hands. '
    'Estimated from your per-session results and durations (hands '
    'assumed at 25 per hour unless a session records its own pace). '
    'Typical live no-limit hold\'em runs roughly 70–100.\n\n'
    'Shown once you have at least 10 qualifying cash sessions '
    '(cash game with parseable blinds and a duration).';

const kTournSdInfo =
    'How swingy your tournament results are, measured in buy-ins per '
    'tournament (each result divided by its buy-in, so mixed buy-in '
    'levels stay comparable).\n\nTournament results are heavily '
    'skewed by rare big scores — with few tournaments logged this '
    'UNDERSTATES the real swings. Shown once you have at least 10 '
    'tournaments with a buy-in.';

/// Tab-body padding shared by every Stats tab: 16px on phones, centered at a
/// 960px max content width on wide screens (web/desktop) — the old
/// _AnalyticsBody invariant, restored after the restructure dropped it.
EdgeInsets statsTabPadding(BuildContext context, {double top = 12}) {
  final w = MediaQuery.of(context).size.width;
  final h = w > 800 ? math.max(16.0, (w - 960) / 2) : 16.0;
  return EdgeInsets.fromLTRB(h, top, h, 96);
}

/// Everything the Stats tabs need, computed ONCE per build from the raw
/// session list + the screen's shared [StatsFilter]. There is deliberately no
/// game-type filter any more: the Summary tab shows the side-by-side
/// Cash|Tournament comparison when both types exist, and each factor tab
/// scopes its own sessions — the old pills were redundant with that.
class AnalyticsData {
  final List<SessionModel> sessions; // unfiltered (for empty-state wording)
  final List<SessionModel> filtered;
  final String displayCurrency;
  final String sym;
  final bool showingCash;
  final bool showingTournaments;
  final bool hasLiveInView;
  final bool hasOnlineInView;
  final List<SessionModel> cashSessions;
  final List<SessionModel> tSessions;
  final List<SummaryItem> summaryItems;
  final List<String> activeFilters;

  // Per-type derived metrics, computed ONCE here — the comparison card must
  // consume these, not re-derive them (two implementations drift).
  final double? cashBB100;
  final double? cashBB100StdDev;
  final double? cashHourlyStdDev;
  final double? tournStdDevBuyIns;
  final double? tournROI;
  final int? tournItmPct;

  AnalyticsData._({
    required this.sessions,
    required this.filtered,
    required this.displayCurrency,
    required this.sym,
    required this.showingCash,
    required this.showingTournaments,
    required this.hasLiveInView,
    required this.hasOnlineInView,
    required this.cashSessions,
    required this.tSessions,
    required this.summaryItems,
    required this.activeFilters,
    required this.cashBB100,
    required this.cashBB100StdDev,
    required this.cashHourlyStdDev,
    required this.tournStdDevBuyIns,
    required this.tournROI,
    required this.tournItmPct,
  });

  factory AnalyticsData.compute(
    List<SessionModel> sessions,
    StatsFilter filter,
    String? homeCurrency,
  ) {
    final filtered = filter.apply(sessions);
    final displayCurrency =
        filter.effectiveCurrency(sessions, homeCurrency: homeCurrency);
    final showingTournaments =
        filtered.any((s) => isTournamentType(s.gameType));
    final showingCash = filtered.any((s) => s.gameType == 'cash');
    // Use filtered counts for factor-tab visibility (not all-time counts).
    final hasLiveInView = filtered.any((s) => !isOnlineSession(s.location));
    final hasOnlineInView = filtered.any((s) => isOnlineSession(s.location));

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
    // Pooled ROI (total profit / total buy-in) — matches the metric chart;
    // a per-session average would overweight small buy-ins and disagree with
    // the chart it drills into.
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
    final cashSessions = filtered.where((s) => s.gameType == 'cash').toList();
    final bb100 = calcBB100(cashSessions);
    // Standard deviations (null under 10 qualifying sessions → '—' rows).
    final bb100StdDev = calcBB100StdDev(cashSessions);
    final hourlyStdDev = calcHourlyStdDev(cashSessions, displayCurrency);
    final tournStdDev = calcTournamentStdDevBuyIns(tSessions);

    final summaryItems = <SummaryItem>[
      SummaryItem('Sessions', '${filtered.length}', null, StatMetric.sessions),
      SummaryItem('Hours', formatHours(totalHours), null, StatMetric.hours),
      SummaryItem(
        'Win Rate',
        '${formatPLWithCurrency(hourlyRate, displayCurrency)}/hr',
        rateColor,
        StatMetric.winRate,
      ),
      SummaryItem(
        'Total Profit',
        formatPLWithCurrency(totalPL, displayCurrency),
        plColor,
        StatMetric.profit,
      ),
      // AVERAGE buy-in per session — how much the user actually puts on the
      // table, not a volume total. ROI denominators stay pooled totals.
      if (filtered.isNotEmpty)
        SummaryItem(
            'Avg Buy-In',
            formatAmount(totalBuyIn / filtered.length, displayCurrency),
            null,
            StatMetric.buyIn),
      if (hasExpenses)
        SummaryItem('Expenses', '-$sym${totalExpenses.toStringAsFixed(0)}',
            null, StatMetric.expenses),
      if (hasExpenses)
        SummaryItem(
          'Net Profit',
          formatPLWithCurrency(netAfterExpenses, displayCurrency),
          netAfterExpenses >= 0 ? Colors.green : Colors.red,
          StatMetric.netAfterExpenses,
        ),
      if (bb100 != null)
        SummaryItem(
          'BB/100',
          formatBB100(bb100),
          bb100 >= 0 ? Colors.green : Colors.red,
          StatMetric.bb100,
        ),
      // Standard-deviation rows: session-estimated (Malmuth), info dialog
      // instead of a trend chart (an SD time series isn't meaningful).
      if (showingCash && cashSessions.isNotEmpty)
        SummaryItem(
          'Std Dev (BB/100)',
          bb100StdDev == null ? '—' : formatWholeNum(bb100StdDev),
          null,
          null,
          kCashSdInfo,
        ),
      if (showingCash && cashSessions.isNotEmpty)
        SummaryItem(
          'Std Dev ($sym/hr)',
          hourlyStdDev == null
              ? '—'
              : formatAmount(hourlyStdDev, displayCurrency),
          null,
          null,
          'How much a typical hour deviates from your average hourly rate, '
          'in $displayCurrency. Estimated from per-session results and '
          'durations.\n\nShown once you have at least 10 cash sessions with '
          'a recorded duration.',
        ),
      if (tournamentROI != null)
        SummaryItem(
          'Tourn. ROI',
          formatROI(tournamentROI),
          tournamentROI >= 0 ? Colors.green : Colors.red,
          StatMetric.roi,
        ),
      if (itmPct != null)
        SummaryItem('ITM', '$itmPct%', null, StatMetric.itmPct),
      if (showingTournaments && hasTournaments)
        SummaryItem(
          'Std Dev (buy-ins)',
          tournStdDev == null ? '—' : tournStdDev.toStringAsFixed(1),
          null,
          null,
          kTournSdInfo,
        ),
    ];

    return AnalyticsData._(
      sessions: sessions,
      filtered: filtered,
      displayCurrency: displayCurrency,
      sym: sym,
      showingCash: showingCash,
      showingTournaments: showingTournaments,
      hasLiveInView: hasLiveInView,
      hasOnlineInView: hasOnlineInView,
      cashSessions: cashSessions,
      tSessions: tSessions,
      summaryItems: summaryItems,
      activeFilters: [...filter.labels(), displayCurrency],
      cashBB100: bb100,
      cashBB100StdDev: bb100StdDev,
      cashHourlyStdDev: hourlyStdDev,
      tournStdDevBuyIns: tournStdDev,
      tournROI: tournamentROI,
      tournItmPct: itmPct,
    );
  }
}

// ─── Factor configuration (one table drives the tab list AND the pages) ───────

/// One "What's Affecting Your Win Rate" breakdown, as data: the Stats screen
/// builds a TAB per factor from this list, so adding a factor here adds its
/// tab automatically.
class AnalyticsFactor {
  final String tabLabel; // short — the Tab text
  final String title; // the card title
  final List<SessionModel> sessions;
  final String Function(SessionModel) keyFn;
  final List<String>? orderedKeys;
  final bool isTournament;
  final int Function(String, String)? naturalCompare;

  const AnalyticsFactor({
    required this.tabLabel,
    required this.title,
    required this.sessions,
    required this.keyFn,
    this.orderedKeys,
    this.isTournament = false,
    this.naturalCompare,
  });
}

/// The available factors for the current data — each entry mirrors the old
/// single-scroll card's gate condition exactly.
List<AnalyticsFactor> analyticsFactors(AnalyticsData d) {
  final filtered = d.filtered;
  if (filtered.isEmpty) return const [];
  final mixedTournament = d.showingTournaments && !d.showingCash;
  return [
    if (d.showingCash)
      AnalyticsFactor(
        tabLabel: 'Stakes',
        title: 'By Stakes',
        sessions: d.cashSessions,
        keyFn: (s) => s.stakes,
        // Natural order for stakes = by blind size, small→big; unparseable
        // stakes sort last, then alphabetical.
        naturalCompare: (a, b) {
          final ba = parseBBFromStakes(a);
          final bb = parseBBFromStakes(b);
          if (ba != null && bb != null) {
            final c = ba.compareTo(bb);
            return c != 0 ? c : a.compareTo(b);
          }
          if (ba != null) return -1;
          if (bb != null) return 1;
          return a.compareTo(b);
        },
      ),
    if (d.showingTournaments)
      AnalyticsFactor(
        tabLabel: 'Buy-ins',
        title: 'By Buy-in Level',
        sessions: d.tSessions,
        keyFn: (s) => tournamentBuyInBucket(s.buyIn),
        orderedKeys: const [
          '< \$50',
          '\$50–\$100',
          '\$100–\$200',
          '\$200–\$500',
          '> \$500'
        ],
        isTournament: true,
      ),
    // Field size — only when enough sessions have entrant counts.
    if (d.showingTournaments &&
        d.tSessions.where((s) => (s.totalEntrants ?? 0) > 0).length >= 2)
      AnalyticsFactor(
        tabLabel: 'Field Size',
        title: 'By Field Size',
        sessions:
            d.tSessions.where((s) => (s.totalEntrants ?? 0) > 0).toList(),
        keyFn: (s) => fieldSizeBucket(s.totalEntrants),
        orderedKeys: const [
          'Small (<50)',
          'Medium (50–200)',
          'Large (200–500)',
          'Massive (500+)',
        ],
        isTournament: true,
      ),
    if (d.showingCash && d.showingTournaments)
      AnalyticsFactor(
        tabLabel: 'Game Type',
        title: 'By Game Type',
        sessions: filtered,
        keyFn: (s) => gameTypeLabel(s.gameType),
      ),
    AnalyticsFactor(
      tabLabel: 'Day',
      title: 'By Day of Week',
      sessions: filtered,
      keyFn: (s) => dayOfWeekLabel(s.date),
      orderedKeys: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      isTournament: mixedTournament,
    ),
    // Time of Day — cash only; less actionable for tournaments.
    if (d.showingCash)
      AnalyticsFactor(
        tabLabel: 'Time',
        title: 'By Time of Day',
        sessions: d.cashSessions,
        keyFn: (s) => timeOfDayBucket(s.startTime),
      ),
    // Session Length — cash only (tournament duration = finish depth).
    if (d.showingCash)
      AnalyticsFactor(
        tabLabel: 'Length',
        title: 'By Session Length',
        sessions: d.cashSessions,
        keyFn: (s) => sessionLengthBucket(s.durationMinutes),
        orderedKeys: const [
          '< 2 hours', '2–4 hours', '4–6 hours', '> 6 hours' //
        ],
      ),
    // Table Quality — cash only, when any session is rated.
    if (d.showingCash && d.cashSessions.any((s) => s.tableQuality != null))
      AnalyticsFactor(
        tabLabel: 'Table',
        title: 'By Table Quality',
        sessions:
            d.cashSessions.where((s) => s.tableQuality != null).toList(),
        keyFn: (s) =>
            '${s.tableQuality}★ ${tableQualityLabel(s.tableQuality)}',
        orderedKeys:
            List.generate(5, (i) => '${i + 1}★ ${tableQualityLabel(i + 1)}'),
      ),
    if (_hasMultipleLocations(filtered))
      AnalyticsFactor(
        tabLabel: 'Location',
        title: 'By Location',
        sessions:
            filtered.where((s) => s.location?.isNotEmpty == true).toList(),
        keyFn: (s) => s.location!,
        isTournament: mixedTournament,
      ),
    if (d.hasLiveInView && d.hasOnlineInView)
      AnalyticsFactor(
        tabLabel: 'Live/Online',
        title: 'Live vs Online',
        sessions: filtered,
        keyFn: (s) => isOnlineSession(s.location) ? 'Online' : 'Live',
        orderedKeys: const ['Live', 'Online'],
        isTournament: mixedTournament,
      ),
  ];
}

// ─── Summary tab ──────────────────────────────────────────────────────────────

/// First Stats tab: Live-now card, the metric summary (side-by-side
/// Cash|Tournament comparison when both types are in view), the AI coaching
/// CTA, and the first-session empty state.
///
/// In-body game-type shortcuts: the comparison card's Cash/Tournament column
/// HEADERS narrow the whole screen to that type (via [onGameTypesChanged]),
/// and a dismissible chip appears in any single-type view to jump back to
/// combined.
class AnalyticsSummaryTab extends ConsumerWidget {
  final AnalyticsData data;
  final Set<String> gameTypes; // the shared filter's current game-type set
  final ValueChanged<Set<String>> onGameTypesChanged;
  const AnalyticsSummaryTab({
    super.key,
    required this.data,
    required this.gameTypes,
    required this.onGameTypesChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = data;
    final filtered = d.filtered;
    final typeLabel = gameTypeChipLabel(gameTypes);
    return ListView(
      padding: statsTabPadding(context),
      children: [
        const LiveSessionCard(),
        // Back-to-combined affordance whenever a game-type filter narrows
        // the view (set here via a column header OR via the sheet).
        if (typeLabel != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InputChip(
                avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                label: Text('$typeLabel only'),
                deleteButtonTooltipMessage: 'Show all game types',
                onDeleted: () => onGameTypesChanged(const {}),
              ),
            ),
          ),
        // (The converted-totals marker lives in the Stats AppBar — an
        // in-body line here cost a full row of screen space.)
        // Combined view: cash and tournament metrics don't blend meaningfully
        // (a $/hr pooled across both answers no real question) — with both
        // types in view, show the side-by-side per-type comparison instead of
        // a blended list. (The old game-type pills + "Combined" line were
        // redundant with this card and were removed.)
        if (d.showingCash && d.showingTournaments)
          _TypeComparisonCard(
            data: d,
            onSelectType: (t) => onGameTypesChanged(t),
          )
        else
          _MetricSummaryList(
            items: d.summaryItems,
            sessions: filtered,
            displayCurrency: d.displayCurrency,
            activeFilters: d.activeFilters,
          ),

        // AI coaching CTA (latest session) or the first-session empty state —
        // both carried over from the retired Overview tab.
        const SizedBox(height: 20),
        if (d.sessions.isNotEmpty)
          AiCoachingCard(session: mostRecentSession(d.sessions)!)
        else ...[
          Text(
            'No sessions yet — log your first to fill these in.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => showLogSessionChooser(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Log Session'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ImportSourceScreen()),
                ),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import'),
              ),
            ],
          ),
        ],
        // "Filters hid everything" (distinct from "no data yet").
        if (d.sessions.isNotEmpty && filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                'No sessions match these filters.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Factor tab ───────────────────────────────────────────────────────────────

/// One factor's page: legend + sort menu row, then the breakdown card.
class AnalyticsFactorTab extends StatelessWidget {
  final AnalyticsData data;
  final AnalyticsFactor factor;
  final InsightSort sort;
  final ValueChanged<InsightSort> onSortChanged;

  const AnalyticsFactorTab({
    super.key,
    required this.data,
    required this.factor,
    required this.sort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = factor.isTournament;
    return ListView(
      padding: statsTabPadding(context, top: 8),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // Legend for the card rows: count/hours · rate · profit.
                t ? '#  ·  ROI  ·  Profit' : 'hrs  ·  ${data.sym}/hr  ·  Profit',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            PopupMenuButton<InsightSort>(
              icon: Icon(Icons.sort, color: theme.colorScheme.onSurfaceVariant),
              tooltip: 'Sort',
              initialValue: sort,
              onSelected: onSortChanged,
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: InsightSort.rate,
                  checked: sort == InsightSort.rate,
                  child: Text(t ? 'ROI' : 'Win rate'),
                ),
                CheckedPopupMenuItem(
                  value: InsightSort.profit,
                  checked: sort == InsightSort.profit,
                  child: const Text('Profit'),
                ),
                CheckedPopupMenuItem(
                  value: InsightSort.volume,
                  checked: sort == InsightSort.volume,
                  child: Text(t ? 'Volume' : 'Hours'),
                ),
                CheckedPopupMenuItem(
                  value: InsightSort.natural,
                  checked: sort == InsightSort.natural,
                  child: const Text('Natural order'),
                ),
              ],
            ),
          ],
        ),
        _InsightCard(
          title: factor.title,
          sessions: factor.sessions,
          keyFn: factor.keyFn,
          orderedKeys: factor.orderedKeys,
          displayCurrency: data.displayCurrency,
          isTournament: factor.isTournament,
          sort: sort,
          naturalCompare: factor.naturalCompare,
        ),
      ],
    );
  }
}

// ─── Tips tab ─────────────────────────────────────────────────────────────────

/// The Recommendations cards — the takeaway drawn from the factor breakdowns.
class AnalyticsTipsTab extends StatelessWidget {
  final AnalyticsData data;
  const AnalyticsTipsTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final filtered = d.filtered;
    return ListView(
      padding: statsTabPadding(context),
      children: [
        if (d.showingCash && d.showingTournaments) ...[
          _RecommendationsCard(
            sessions: d.cashSessions,
            gameLabel: 'cash',
            displayCurrency: d.displayCurrency,
          ),
          const SizedBox(height: 8),
          _RecommendationsCard(
            sessions: d.tSessions,
            gameLabel: 'tournament',
            displayCurrency: d.displayCurrency,
          ),
        ] else if (d.showingCash)
          _RecommendationsCard(
            sessions: d.cashSessions,
            gameLabel: 'cash',
            displayCurrency: d.displayCurrency,
          )
        else if (d.showingTournaments)
          _RecommendationsCard(
            sessions: d.tSessions,
            gameLabel: 'tournament',
            displayCurrency: d.displayCurrency,
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                filtered.isEmpty && d.sessions.isEmpty
                    ? 'Log a few sessions to unlock recommendations.'
                    : 'No sessions match these filters.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ),
      ],
    );
  }

}

bool _hasMultipleLocations(List<SessionModel> sessions) {
  final locs = sessions
      .map((s) => s.location)
      .whereType<String>()
      .where((l) => l.isNotEmpty)
      .toSet();
  return locs.length > 1;
}

// ─── Metric summary (one per row, tappable → full-screen trend chart) ─────────

/// User-selectable ordering for the insight breakdown cards. One global
/// choice (held by the Stats screen) applies to every factor tab. PUBLIC —
/// the Stats screen owns the state; the factor tabs render the menu.
enum InsightSort {
  rate, // $/hr (cash cards) or ROI (tournament cards) — the old fixed order
  profit, // total profit desc
  volume, // hours (cash) or tournament count desc
  natural, // the category's own order: declared orderedKeys (days Mon–Sun,
  // buy-in buckets), stakes by blind size, else A–Z
}

class SummaryItem {
  final String label;
  final String value;
  final Color? color;
  final StatMetric? metric;

  /// Explainer for metrics with no trend chart (e.g. the SD rows): tapping
  /// the row shows this text in a dialog instead of pushing a chart.
  final String? info;
  const SummaryItem(this.label, this.value,
      [this.color, this.metric, this.info]);
}

/// The Analytics summary, rendered one metric per row. Each row is a CTA that
/// opens the metric's full-screen trend chart (mirrors the Overview tab).
class _MetricSummaryList extends StatelessWidget {
  final List<SummaryItem> items;
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

  Widget _row(BuildContext context, SummaryItem item) {
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
          ] else if (item.info != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );

    if (item.metric == null) {
      final info = item.info;
      if (info == null) return body;
      return InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(item.label),
            content: Text(info),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it')),
            ],
          ),
        ),
        child: body,
      );
    }
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

// ─── Combined Cash + Tournament view ──────────────────────────────────────────

/// Side-by-side Cash | Tournament metric comparison for the combined view.
/// Each VALUE CELL is tappable and opens that metric's trend chart scoped to
/// its game type ([MetricChartScreen] takes pre-filtered sessions — there is
/// no game-type filter on the chart itself, so the scoping happens here and
/// is disclosed via the chart's filter chips).
class _TypeComparisonCard extends StatelessWidget {
  final AnalyticsData data;

  /// Tapping a column HEADER narrows the Stats screen to that game type
  /// ({'cash'} / {'tournament'}) — the headers render in the primary color
  /// as the tappable affordance.
  final ValueChanged<Set<String>> onSelectType;

  const _TypeComparisonCard({
    required this.data,
    required this.onSelectType,
  });

  void _open(BuildContext context, StatMetric metric,
      List<SessionModel> sessions, String typeLabel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MetricChartScreen(
          metric: metric,
          sessions: sessions,
          displayCurrency: data.displayCurrency,
          activeFilters: [...data.activeFilters, typeLabel],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cash = data.cashSessions;
    final tournaments = data.tSessions;
    final displayCurrency = data.displayCurrency;
    double toD(double amount, String from) =>
        convertCurrency(amount, from, displayCurrency);
    double pl(List<SessionModel> l) =>
        l.fold(0.0, (a, s) => a + toD(s.profitLoss, s.currency));
    double hrs(List<SessionModel> l) =>
        l.fold(0, (a, s) => a + s.durationMinutes) / 60.0;
    double avgBuyIn(List<SessionModel> l) => l.isEmpty
        ? 0
        : l.fold(0.0, (a, s) => a + toD(s.buyIn, s.currency)) / l.length;

    final cashPL = pl(cash);
    final cashHours = hrs(cash);
    final cashRate = cashHours > 0 ? cashPL / cashHours : 0.0;
    final tPL = pl(tournaments);

    // Derived metrics (BB/100, ROI, ITM%, std devs) come from AnalyticsData —
    // ONE implementation; this card only does the cheap per-type folds.
    final bb100 = data.cashBB100;
    final tROI = data.tournROI ?? 0.0;
    final itm = data.tournItmPct ?? 0;
    final bb100StdDev = data.cashBB100StdDev;
    final hourlyStdDev = data.cashHourlyStdDev;
    final tournStdDev = data.tournStdDevBuyIns;

    // Per-type extras — everything the summary shows lives IN the two
    // columns (nothing renders below the card in combined view).
    double exp(List<SessionModel> l) =>
        l.fold(0.0, (a, s) => a + toD(s.totalExpenses, s.currency));
    final cashExp = exp(cash);
    final tExp = exp(tournaments);
    final hasExpenses = cashExp > 0 || tExp > 0;
    final sym = currencySymbol(displayCurrency);
    // The $/hr SD has no cell of its own here — fold it into the cash SD
    // dialog so the combined view loses no information vs the type lists.
    final cashSdInfo = hourlyStdDev == null
        ? kCashSdInfo
        : 'In money terms: about '
            '${formatAmount(hourlyStdDev, displayCurrency)} per hour.'
            '\n\n$kCashSdInfo';

    Color? signColor(double v) => v >= 0 ? Colors.green : Colors.red;

    Widget header(String t, Set<String> types) => Expanded(
          flex: 3,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onSelectType(types),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(t,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        );

    Widget cell(String text, StatMetric metric, List<SessionModel> sessions,
        String typeLabel,
        {Color? color}) {
      return Expanded(
        flex: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: sessions.isEmpty
              ? null
              : () => _open(context, metric, sessions, typeLabel),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(text,
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: color)),
            ),
          ),
        ),
      );
    }

    Widget label(String t) => Expanded(
          flex: 2,
          child: Text(t,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        );

    // Info-dialog cell for metrics with no trend chart (the SD cells) —
    // mirrors _MetricSummaryList's info rows.
    Widget infoCell(String text, String title, String info) {
      return Expanded(
        flex: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(info),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Got it')),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(text,
                  maxLines: 1,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
    }

    Widget row(String name, Widget cashCell, Widget tournCell) => Row(
          children: [label(name), cashCell, tournCell],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            Row(children: [
              const Expanded(flex: 2, child: SizedBox()),
              header('Cash', const {'cash'}),
              header('Tournament', const {'tournament'}),
            ]),
            const SizedBox(height: 4),
            row(
              'Profit',
              cell(formatPL(cashPL, ''), StatMetric.profit, cash, 'Cash',
                  color: signColor(cashPL)),
              cell(formatPL(tPL, ''), StatMetric.profit, tournaments,
                  'Tournaments',
                  color: signColor(tPL)),
            ),
            row(
              'Rate',
              cell(
                  '${formatPLWithCurrency(cashRate, displayCurrency)}/hr',
                  StatMetric.winRate,
                  cash,
                  'Cash',
                  color: signColor(cashRate)),
              cell('${formatROI(tROI)} ROI', StatMetric.roi, tournaments,
                  'Tournaments',
                  color: signColor(tROI)),
            ),
            // Session COUNT for both types (the hours-only Volume row hid
            // the cash count in combined view). Tournaments deliberately
            // repeat the number in Volume below.
            row(
              'Sessions',
              cell('${cash.length}', StatMetric.sessions, cash, 'Cash'),
              cell('${tournaments.length}', StatMetric.sessions, tournaments,
                  'Tournaments'),
            ),
            row(
              'Volume',
              cell(formatHours(cashHours), StatMetric.hours, cash, 'Cash'),
              // Hours for BOTH types — the Sessions row above already
              // carries the tournament count (device-review call).
              cell(formatHours(hrs(tournaments)), StatMetric.hours,
                  tournaments, 'Tournaments'),
            ),
            row(
              'Avg Buy-In',
              cell(formatAmount(avgBuyIn(cash), displayCurrency),
                  StatMetric.buyIn, cash, 'Cash'),
              cell(formatAmount(avgBuyIn(tournaments), displayCurrency),
                  StatMetric.buyIn, tournaments, 'Tournaments'),
            ),
            row(
              'Edge',
              bb100 == null
                  ? cell('—', StatMetric.bb100, const [], 'Cash')
                  : cell('${formatBB100(bb100)} BB/100', StatMetric.bb100,
                      cash, 'Cash',
                      color: signColor(bb100)),
              cell('$itm% ITM', StatMetric.itmPct, tournaments, 'Tournaments'),
            ),
            if (hasExpenses) ...[
              row(
                'Expenses',
                cashExp > 0
                    ? cell('-$sym${cashExp.toStringAsFixed(0)}',
                        StatMetric.expenses, cash, 'Cash')
                    : cell('—', StatMetric.expenses, const [], 'Cash'),
                tExp > 0
                    ? cell('-$sym${tExp.toStringAsFixed(0)}',
                        StatMetric.expenses, tournaments, 'Tournaments')
                    : cell('—', StatMetric.expenses, const [], 'Tournaments'),
              ),
              row(
                'Net Profit',
                cell(formatPL(cashPL - cashExp, ''),
                    StatMetric.netAfterExpenses, cash, 'Cash',
                    color: signColor(cashPL - cashExp)),
                cell(formatPL(tPL - tExp, ''), StatMetric.netAfterExpenses,
                    tournaments, 'Tournaments',
                    color: signColor(tPL - tExp)),
              ),
            ],
            // Std dev per type (info dialogs, no trend chart). '—' until the
            // 10-qualifying-session threshold — the dialog explains it.
            row(
              'Std Dev',
              infoCell(
                  bb100StdDev == null
                      ? '—'
                      : '${formatWholeNum(bb100StdDev)} BB/100',
                  'Cash Std Dev (BB/100)',
                  cashSdInfo),
              infoCell(
                  tournStdDev == null
                      ? '—'
                      : '${tournStdDev.toStringAsFixed(1)} buy-ins',
                  'Tournament Std Dev (buy-ins)',
                  kTournSdInfo),
            ),
          ],
        ),
      ),
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
  final InsightSort sort;

  /// Category order for [InsightSort.natural] when there is no declared
  /// [orderedKeys] (e.g. By Stakes sorts by blind size). Falls back to A–Z.
  final int Function(String a, String b)? naturalCompare;

  const _InsightCard({
    required this.title,
    required this.sessions,
    required this.keyFn,
    required this.displayCurrency,
    this.orderedKeys,
    this.isTournament = false,
    this.sort = InsightSort.rate,
    this.naturalCompare,
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

    switch (sort) {
      case InsightSort.rate:
        if (isTournament) {
          keys.sort((a, b) => stats[b]!.roi.compareTo(stats[a]!.roi));
        } else {
          keys.sort(
              (a, b) => stats[b]!.hourlyRate.compareTo(stats[a]!.hourlyRate));
        }
      case InsightSort.profit:
        keys.sort((a, b) => stats[b]!.totalPL.compareTo(stats[a]!.totalPL));
      case InsightSort.volume:
        if (isTournament) {
          keys.sort((a, b) => stats[b]!.count.compareTo(stats[a]!.count));
        } else {
          keys.sort(
              (a, b) => stats[b]!.totalHours.compareTo(stats[a]!.totalHours));
        }
      case InsightSort.natural:
        // Declared orderedKeys already ordered `keys` above — keep it.
        if (orderedKeys == null) {
          final cmp = naturalCompare;
          keys.sort(cmp ?? (a, b) => a.compareTo(b));
        }
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
  final bool hasCash;
  final bool hasTournaments;
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
    required this.hasCash,
    required this.hasTournaments,
    required this.allLocations,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<StatsFilterSheet> createState() => _StatsFilterSheetState();
}

class _StatsFilterSheetState extends State<StatsFilterSheet> {
  late Set<String> _gameTypes;
  late String _currency;
  late Set<String> _country;
  late String? _venue;
  late Set<String> _location;
  late String? _datePreset;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _gameTypes = {...widget.filter.gameTypes};
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

            // ── Game Type — both types exist, OR a game-type filter is
            // already set (else a lingering filter over vanished data blanks
            // every tab with no visible control to clear it) ─────────────────
            if ((widget.hasCash && widget.hasTournaments) ||
                _gameTypes.isNotEmpty)
              _section(
                title: 'Game Type',
                summary: gameTypeChipLabel(_gameTypes) ?? 'All game types',
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in [
                        (const <String>{}, 'All Games'),
                        (const {'cash'}, 'Cash'),
                        (const {'tournament'}, 'Tournament'),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: setEquals(_gameTypes, entry.$1),
                          onSelected: (_) =>
                              setState(() => _gameTypes = entry.$1),
                        ),
                    ],
                  ),
                ],
              ),

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
                        gameTypes: _gameTypes,
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
