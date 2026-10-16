import 'dart:math' as math;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/poker_rooms.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import '../models/session_model.dart';
import '../models/stats_filter.dart';
import '../utils/helpers.dart';
import '../widgets/ai_coaching_card.dart';
import '../widgets/game_type_filter.dart' show gameTypeChipLabel;
import 'import_source_screen.dart';
import 'live_session_screen.dart';
import 'metric_chart_screen.dart';

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
    AppLocalizations l10n,
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
      SummaryItem(l10n.statsSessions, '${filtered.length}', null,
          StatMetric.sessions),
      SummaryItem(
          l10n.statsHours, formatHours(totalHours), null, StatMetric.hours),
      SummaryItem(
        l10n.statsWinRate,
        perHour(l10n, formatPLWithCurrency(hourlyRate, displayCurrency)),
        rateColor,
        StatMetric.winRate,
      ),
      SummaryItem(
        l10n.statsTotalProfit,
        formatPLWithCurrency(totalPL, displayCurrency),
        plColor,
        StatMetric.profit,
      ),
      // AVERAGE buy-in per session — how much the user actually puts on the
      // table, not a volume total. ROI denominators stay pooled totals.
      if (filtered.isNotEmpty)
        SummaryItem(
            l10n.statsAvgBuyIn,
            formatAmount(totalBuyIn / filtered.length, displayCurrency),
            null,
            StatMetric.buyIn),
      if (hasExpenses)
        SummaryItem(l10n.statsExpenses, '-${formatAmount(totalExpenses, displayCurrency)}',
            null, StatMetric.expenses),
      if (hasExpenses)
        SummaryItem(
          l10n.statsNetProfit,
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
          l10n.statsStdDevBb100,
          bb100StdDev == null ? '—' : formatWholeNum(bb100StdDev),
          null,
          null,
          l10n.statsCashSdInfo,
        ),
      if (showingCash && cashSessions.isNotEmpty)
        SummaryItem(
          l10n.statsStdDevPerHour(sym),
          hourlyStdDev == null
              ? '—'
              : formatAmount(hourlyStdDev, displayCurrency),
          null,
          null,
          l10n.statsHourlySdInfo(displayCurrency),
        ),
      if (tournamentROI != null)
        SummaryItem(
          l10n.statsTournRoi,
          formatROI(tournamentROI),
          tournamentROI >= 0 ? Colors.green : Colors.red,
          StatMetric.roi,
        ),
      if (itmPct != null)
        SummaryItem('ITM', '$itmPct%', null, StatMetric.itmPct),
      if (showingTournaments && hasTournaments)
        SummaryItem(
          l10n.statsStdDevBuyIns,
          tournStdDev == null ? '—' : tournStdDev.toStringAsFixed(1),
          null,
          null,
          l10n.statsTournSdInfo,
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
      activeFilters: [...filter.labels(l10n), displayCurrency],
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
  /// Stable, language-independent id — the Stats screen keys its tab
  /// controller on these, so a language switch can't look like a tab-set
  /// change (or vice versa).
  final String id;
  final String tabLabel; // short — the Tab text
  final String title; // the card title
  final List<SessionModel> sessions;

  /// STABLE grouping key per session (enum names, weekday ints, ids) — never
  /// display text, so the breakdown survives a language switch.
  final String Function(SessionModel) keyFn;
  final List<String>? orderedKeys;
  final bool isTournament;
  final int Function(String, String)? naturalCompare;

  /// Localized label for a key (null = the key is already display text, e.g.
  /// stakes or a location name).
  final String Function(AppLocalizations l10n, String key)? labelFn;

  const AnalyticsFactor({
    required this.id,
    required this.tabLabel,
    required this.title,
    required this.sessions,
    required this.keyFn,
    this.orderedKeys,
    this.isTournament = false,
    this.naturalCompare,
    this.labelFn,
  });
}

// ─── Shared grouping keys ───────────────────────────────────────────────────
// ONE definition per dimension, used by both the factor tabs and the Tips
// engine (_RecommendationsCard) so the two can never bucket a session
// differently. Keys are stable ids; display text comes from labels.dart.

/// Buy-in band, classified in USD (the band edges are USD amounts).
String buyInKey(SessionModel s, String displayCurrency) =>
    buyInBucketOfSession(s, displayCurrency).name;

/// Field-size band, or null when the entrant count is unknown.
String? fieldSizeKey(SessionModel s) => fieldSizeBucketOf(s.totalEntrants)?.name;

/// ISO weekday 1–7 as a string, or null for an unparseable date.
String? weekdayKey(SessionModel s) => weekdayOf(s.date)?.toString();

/// Start-time band, or null for a blank/unparseable start time.
String? timeOfDayKey(SessionModel s) => timeOfDayBucketOf(s.startTime)?.name;

String sessionLengthKey(SessionModel s) =>
    sessionLengthBucketOf(s.durationMinutes).name;

/// 'live' | 'online'.
String venueKey(SessionModel s) =>
    isOnlineSession(s.location) ? 'online' : 'live';

/// The location, or null when the session has none.
String? locationKey(SessionModel s) =>
    s.location?.isNotEmpty == true ? s.location : null;

/// The available factors for the current data — each entry mirrors the old
/// single-scroll card's gate condition exactly.
List<AnalyticsFactor> analyticsFactors(
    AnalyticsData d, AppLocalizations l10n) {
  final filtered = d.filtered;
  if (filtered.isEmpty) return const [];
  final mixedTournament = d.showingTournaments && !d.showingCash;
  return [
    if (d.showingCash)
      AnalyticsFactor(
        id: 'stakes',
        tabLabel: l10n.statsFactorStakes,
        title: l10n.statsFactorStakesTitle,
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
        id: 'buyIns',
        tabLabel: l10n.statsFactorBuyIns,
        title: l10n.statsFactorBuyInsTitle,
        sessions: d.tSessions,
        // Bucketed in USD (the edges are USD amounts); the label converts the
        // edges into the display currency so it matches the converted ROI.
        keyFn: (s) => buyInKey(s, d.displayCurrency),
        orderedKeys: [for (final b in BuyInBucket.values) b.name],
        labelFn: (l10n, k) => buyInBucketLabel(
            l10n, BuyInBucket.values.byName(k), d.displayCurrency),
        isTournament: true,
      ),
    // Field size — only when enough sessions have entrant counts.
    if (d.showingTournaments &&
        d.tSessions.where((s) => (s.totalEntrants ?? 0) > 0).length >= 2)
      AnalyticsFactor(
        id: 'fieldSize',
        tabLabel: l10n.statsFactorFieldSize,
        title: l10n.statsFactorFieldSizeTitle,
        sessions:
            d.tSessions.where((s) => (s.totalEntrants ?? 0) > 0).toList(),
        keyFn: (s) => fieldSizeKey(s) ?? '',
        orderedKeys: [for (final b in FieldSizeBucket.values) b.name],
        labelFn: (l10n, k) =>
            fieldSizeBucketLabel(l10n, FieldSizeBucket.values.byName(k)),
        isTournament: true,
      ),
    if (d.showingCash && d.showingTournaments)
      AnalyticsFactor(
        id: 'gameType',
        tabLabel: l10n.statsFactorGameType,
        title: l10n.statsFactorGameTypeTitle,
        sessions: filtered,
        // Tournament variants fold together; any other raw game_type value
        // (legacy / import-edited) stays its own row, as before.
        keyFn: (s) => isTournamentType(s.gameType) ? 'tournament' : s.gameType,
        labelFn: gameTypeKeyLabel,
      ),
    AnalyticsFactor(
      id: 'day',
      tabLabel: l10n.statsFactorDay,
      title: l10n.statsFactorDayTitle,
      sessions: filtered,
      // '' = unparseable date → the row is skipped by _InsightCard.
      keyFn: (s) => weekdayKey(s) ?? '',
      orderedKeys: const ['1', '2', '3', '4', '5', '6', '7'],
      labelFn: (l10n, k) => weekdayShortLabel(l10n, int.parse(k)),
      isTournament: mixedTournament,
    ),
    // Time of Day — cash only; less actionable for tournaments. Data-gated:
    // imported sessions often have no start time, and those are skipped.
    if (d.showingCash &&
        d.cashSessions.where((s) => timeOfDayKey(s) != null).length >= 2)
      AnalyticsFactor(
        id: 'time',
        tabLabel: l10n.statsFactorTime,
        title: l10n.statsFactorTimeTitle,
        sessions: d.cashSessions,
        // '' = no usable start time → skipped (not counted as late night).
        keyFn: (s) => timeOfDayKey(s) ?? '',
        orderedKeys: [for (final b in TimeOfDayBucket.values) b.name],
        labelFn: (l10n, k) =>
            timeOfDayBucketLabel(l10n, TimeOfDayBucket.values.byName(k)),
      ),
    // Session Length — cash only (tournament duration = finish depth).
    if (d.showingCash)
      AnalyticsFactor(
        id: 'length',
        tabLabel: l10n.statsFactorLength,
        title: l10n.statsFactorLengthTitle,
        sessions: d.cashSessions,
        keyFn: sessionLengthKey,
        orderedKeys: [for (final b in SessionLengthBucket.values) b.name],
        labelFn: (l10n, k) =>
            sessionLengthBucketLabel(l10n, SessionLengthBucket.values.byName(k)),
      ),
    // Table Quality — cash only, when any session is rated.
    if (d.showingCash && d.cashSessions.any((s) => s.tableQuality != null))
      AnalyticsFactor(
        id: 'table',
        tabLabel: l10n.statsFactorTable,
        title: l10n.statsFactorTableTitle,
        sessions:
            d.cashSessions.where((s) => s.tableQuality != null).toList(),
        keyFn: (s) => '${s.tableQuality}',
        orderedKeys: const ['1', '2', '3', '4', '5'],
        labelFn: (l10n, k) =>
            '$k★ ${tableQualityKeyLabel(l10n, int.tryParse(k))}',
      ),
    if (_hasMultipleLocations(filtered))
      AnalyticsFactor(
        id: 'location',
        tabLabel: l10n.statsFactorLocation,
        title: l10n.statsFactorLocationTitle,
        sessions:
            filtered.where((s) => s.location?.isNotEmpty == true).toList(),
        keyFn: (s) => locationKey(s)!,
        isTournament: mixedTournament,
      ),
    if (d.hasLiveInView && d.hasOnlineInView)
      AnalyticsFactor(
        id: 'venue',
        tabLabel: l10n.statsFactorVenue,
        title: l10n.statsFactorVenueTitle,
        sessions: filtered,
        keyFn: venueKey,
        orderedKeys: const ['live', 'online'],
        labelFn: venueLabel,
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
    final l10n = context.l10n;
    final filtered = d.filtered;
    final typeLabel = gameTypeChipLabel(l10n, gameTypes);
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
                label: Text(l10n.statsTypeOnly(typeLabel)),
                deleteButtonTooltipMessage: l10n.statsShowAllGameTypes,
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
            l10n.statsNoSessionsYet,
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
                label: Text(l10n.commonLogSession),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ImportSourceScreen()),
                ),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(l10n.commonImport),
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
                l10n.statsNoMatch,
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
    final l10n = context.l10n;
    final t = factor.isTournament;
    return ListView(
      padding: statsTabPadding(context, top: 8),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // Legend for the card rows: count/hours · rate · profit.
                t ? l10n.statsLegendTournament : l10n.statsLegendCash(data.sym),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            PopupMenuButton<InsightSort>(
              icon: Icon(Icons.sort, color: theme.colorScheme.onSurfaceVariant),
              tooltip: l10n.statsSort,
              initialValue: sort,
              onSelected: onSortChanged,
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: InsightSort.rate,
                  checked: sort == InsightSort.rate,
                  child: Text(t ? 'ROI' : l10n.statsSortWinRate),
                ),
                CheckedPopupMenuItem(
                  value: InsightSort.profit,
                  checked: sort == InsightSort.profit,
                  child: Text(l10n.statsProfit),
                ),
                CheckedPopupMenuItem(
                  value: InsightSort.volume,
                  checked: sort == InsightSort.volume,
                  child: Text(t ? l10n.statsSortVolume : l10n.statsHours),
                ),
                CheckedPopupMenuItem(
                  value: InsightSort.natural,
                  checked: sort == InsightSort.natural,
                  child: Text(l10n.statsSortNatural),
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
          labelFn: factor.labelFn,
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
                    ? context.l10n.statsTipsEmpty
                    : context.l10n.statsNoMatch,
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
                  child: Text(context.l10n.commonGotIt)),
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
    final l10n = context.l10n;
    final cash = data.cashSessions;
    final tournaments = data.tSessions;
    // Chart filter-chip labels for the per-type cells.
    final cashChip = l10n.statsCash;
    final tChip = l10n.statsTournaments;
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
    // The $/hr SD has no cell of its own here — fold it into the cash SD
    // dialog so the combined view loses no information vs the type lists.
    final cashSdInfo = hourlyStdDev == null
        ? l10n.statsCashSdInfo
        : '${l10n.statsSdMoneyTerms(formatAmount(hourlyStdDev, displayCurrency))}'
            '\n\n${l10n.statsCashSdInfo}';

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
                    child: Text(context.l10n.commonGotIt)),
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
              header(l10n.statsCash, const {'cash'}),
              header(l10n.statsTournament, const {'tournament'}),
            ]),
            const SizedBox(height: 4),
            row(
              l10n.statsProfit,
              cell(formatPL(cashPL, ''), StatMetric.profit, cash, cashChip,
                  color: signColor(cashPL)),
              cell(formatPL(tPL, ''), StatMetric.profit, tournaments,
                  tChip,
                  color: signColor(tPL)),
            ),
            row(
              l10n.statsRate,
              cell(
                  perHour(l10n, formatPLWithCurrency(cashRate, displayCurrency)),
                  StatMetric.winRate,
                  cash,
                  cashChip,
                  color: signColor(cashRate)),
              cell('${formatROI(tROI)} ROI', StatMetric.roi, tournaments,
                  tChip,
                  color: signColor(tROI)),
            ),
            // Session COUNT for both types (the hours-only Volume row hid
            // the cash count in combined view). Tournaments deliberately
            // repeat the number in Volume below.
            row(
              l10n.statsSessions,
              cell('${cash.length}', StatMetric.sessions, cash, cashChip),
              cell('${tournaments.length}', StatMetric.sessions, tournaments,
                  tChip),
            ),
            row(
              l10n.statsSortVolume,
              cell(formatHours(cashHours), StatMetric.hours, cash, cashChip),
              // Hours for BOTH types — the Sessions row above already
              // carries the tournament count (device-review call).
              cell(formatHours(hrs(tournaments)), StatMetric.hours,
                  tournaments, tChip),
            ),
            row(
              l10n.statsAvgBuyIn,
              cell(formatAmount(avgBuyIn(cash), displayCurrency),
                  StatMetric.buyIn, cash, cashChip),
              cell(formatAmount(avgBuyIn(tournaments), displayCurrency),
                  StatMetric.buyIn, tournaments, tChip),
            ),
            row(
              l10n.statsEdge,
              bb100 == null
                  ? cell('—', StatMetric.bb100, const [], cashChip)
                  : cell('${formatBB100(bb100)} BB/100', StatMetric.bb100,
                      cash, cashChip,
                      color: signColor(bb100)),
              cell('$itm% ITM', StatMetric.itmPct, tournaments, tChip),
            ),
            if (hasExpenses) ...[
              row(
                l10n.statsExpenses,
                cashExp > 0
                    ? cell('-${formatAmount(cashExp, displayCurrency)}',
                        StatMetric.expenses, cash, cashChip)
                    : cell('—', StatMetric.expenses, const [], cashChip),
                tExp > 0
                    ? cell('-${formatAmount(tExp, displayCurrency)}',
                        StatMetric.expenses, tournaments, tChip)
                    : cell('—', StatMetric.expenses, const [], tChip),
              ),
              row(
                l10n.statsNetProfit,
                cell(formatPL(cashPL - cashExp, ''),
                    StatMetric.netAfterExpenses, cash, cashChip,
                    color: signColor(cashPL - cashExp)),
                cell(formatPL(tPL - tExp, ''), StatMetric.netAfterExpenses,
                    tournaments, tChip,
                    color: signColor(tPL - tExp)),
              ),
            ],
            // Std dev per type (info dialogs, no trend chart). '—' until the
            // 10-qualifying-session threshold — the dialog explains it.
            row(
              l10n.statsStdDev,
              infoCell(
                  bb100StdDev == null
                      ? '—'
                      : '${formatWholeNum(bb100StdDev)} BB/100',
                  l10n.statsCashStdDevTitle,
                  cashSdInfo),
              infoCell(
                  tournStdDev == null
                      ? '—'
                      : l10n.statsBuyInsValue(tournStdDev.toStringAsFixed(1)),
                  l10n.statsTournStdDevTitle,
                  l10n.statsTournSdInfo),
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

  /// Localized label for a group key; null = the key is display text.
  final String Function(AppLocalizations l10n, String key)? labelFn;

  const _InsightCard({
    required this.title,
    required this.sessions,
    required this.keyFn,
    required this.displayCurrency,
    this.orderedKeys,
    this.isTournament = false,
    this.sort = InsightSort.rate,
    this.naturalCompare,
    this.labelFn,
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
                label: labelFn?.call(context.l10n, key) ?? key,
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
                  : perHour(context.l10n,
                      formatPLWithCurrency(stats.hourlyRate, displayCurrency)),
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
            context.l10n.statsRecsNeedMore(typeLabel),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
    }
    final recs = _buildRecommendations(context.l10n);
    if (recs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.statsRecsNone(typeLabel),
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
              context.l10n.statsRecsBasedOn,
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

  String _actionTitle(AppLocalizations l10n, String dimension, String best,
      String worst, double bestScore) {
    if (_isTournament) {
      switch (dimension) {
        case 'buy-in level':
          return l10n.statsRecTargetTournaments(best);
        case 'field size':
          return l10n.statsRecFocusFields(best);
        case 'day':
          return l10n.statsRecPrioritiseTournaments(best);
        case 'location':
          return l10n.statsRecStrongestVenue(best);
        case 'live/online':
          if (bestScore > 0) return l10n.statsRecStrongerFormat(best);
          return worst == best
              ? l10n.statsRecShiftFocusOther
              : l10n.statsRecShiftFocusTo(worst);
        default:
          return l10n.statsRecFavour(best, worst);
      }
    }
    switch (dimension) {
      case 'time slot':
        return bestScore > 0
            ? l10n.statsRecScheduleIn(best)
            : l10n.statsRecShiftAway(worst);
      case 'day':
        return l10n.statsRecPrioritiseSessions(best);
      case 'session length':
        return l10n.statsRecTargetSessions(best);
      case 'table quality':
        return l10n.statsRecSeekTables(best);
      case 'location':
        return l10n.statsRecStrongestVenue(best);
      case 'game type':
        return l10n.statsRecFocusMore(best);
      default:
        return l10n.statsRecFavour(best, worst);
    }
  }

  String _explanation(AppLocalizations l10n, String bestKey, String worstKey,
      double bestScore, double worstScore, double overallScore) {
    final diff = bestScore - worstScore;
    if (_isTournament) {
      final best = formatROI(bestScore);
      final overall = formatROI(overallScore);
      return diff > 0
          ? l10n.statsRecExplainTournBetter(best, bestKey, formatROI(diff),
              worstKey, formatROI(worstScore), overall)
          : l10n.statsRecExplainTourn(best, bestKey, overall);
    }
    String money(double v) => formatPLWithCurrency(v, displayCurrency);
    return diff > 0
        ? l10n.statsRecExplainCashBetter(money(bestScore), bestKey, money(diff),
            worstKey, money(worstScore), money(overallScore))
        : l10n.statsRecExplainCash(money(bestScore), bestKey, money(overallScore));
  }

  List<_Rec> _buildRecommendations(AppLocalizations l10n) {
    final recs = <_Rec>[];
    final overallScore = _overallScore();

    // [keyFn] yields a STABLE key (enum name / id); [labelFn] turns it into
    // the localized text embedded in the sentences (null = key is the text).
    void checkFactor({
      required String? Function(SessionModel) keyFn,
      required IconData icon,
      required String dimension,
      String Function(String key)? labelFn,
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

      final bestLabel = labelFn?.call(best.key) ?? best.key;
      final worstLabel = labelFn?.call(worst.key) ?? worst.key;
      recs.add(_Rec(
        icon: icon,
        title: _actionTitle(l10n, dimension, bestLabel, worstLabel, best.mean),
        explanation: _explanation(
            l10n, bestLabel, worstLabel, best.mean, worst.mean, overallScore),
        tStat: tStat,
      ));
    }

    if (_isTournament) {
      // Tournament factors — scored by ROI
      checkFactor(
        keyFn: (s) => buyInKey(s, displayCurrency),
        labelFn: (k) => buyInBucketLabel(
            l10n, BuyInBucket.values.byName(k), displayCurrency),
        icon: Icons.attach_money,
        dimension: 'buy-in level',
      );
      checkFactor(
        keyFn: fieldSizeKey,
        labelFn: (k) =>
            fieldSizeBucketLabel(l10n, FieldSizeBucket.values.byName(k)),
        icon: Icons.people_outline,
        dimension: 'field size',
      );
      checkFactor(
        keyFn: weekdayKey,
        labelFn: (k) => weekdayShortLabel(l10n, int.parse(k)),
        icon: Icons.calendar_today,
        dimension: 'day',
      );
      checkFactor(
        keyFn: locationKey,
        icon: Icons.location_on_outlined,
        dimension: 'location',
      );
      checkFactor(
        keyFn: venueKey,
        labelFn: (k) => venueLabel(l10n, k),
        icon: Icons.wifi_outlined,
        dimension: 'live/online',
      );
    } else {
      // Cash factors — scored by hourly rate
      checkFactor(
        keyFn: timeOfDayKey,
        labelFn: (k) => timeOfDayBucketLabel(
            l10n, TimeOfDayBucket.values.byName(k),
            short: true),
        icon: Icons.access_time,
        dimension: 'time slot',
      );
      checkFactor(
        keyFn: weekdayKey,
        labelFn: (k) => weekdayShortLabel(l10n, int.parse(k)),
        icon: Icons.calendar_today,
        dimension: 'day',
      );
      checkFactor(
        keyFn: sessionLengthKey,
        labelFn: (k) =>
            sessionLengthBucketLabel(l10n, SessionLengthBucket.values.byName(k)),
        icon: Icons.timer_outlined,
        dimension: 'session length',
      );
      checkFactor(
        keyFn: (s) => s.tableQuality?.toString(),
        labelFn: (k) => '$k★',
        icon: Icons.star_border,
        dimension: 'table quality',
      );
      checkFactor(
        keyFn: locationKey,
        icon: Icons.location_on_outlined,
        dimension: 'location',
      );
    }

    recs.sort((a, b) => b.tStat.compareTo(a.tStat));
    final top = recs.take(4).toList();

    if (sessions.length < 20) {
      top.add(_Rec(
        icon: Icons.trending_up,
        title: l10n.statsRecSampleTitle,
        explanation: _isTournament
            ? l10n.statsRecSampleTourn(sessions.length)
            : l10n.statsRecSampleCash(sessions.length),
        tStat: 0,
      ));
    }

    return top;
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

  String _summary(Set<String> sel, String allLabel) => sel.isEmpty
      ? allLabel
      : (sel.length == 1
          ? sel.first
          : context.l10n.statsNSelected(sel.length));

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
    final l10n = context.l10n;

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
            Text(l10n.statsDisplayOptionsTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),

            // ── Game Type — both types exist, OR a game-type filter is
            // already set (else a lingering filter over vanished data blanks
            // every tab with no visible control to clear it) ─────────────────
            if ((widget.hasCash && widget.hasTournaments) ||
                _gameTypes.isNotEmpty)
              _section(
                title: l10n.statsFilterGameType,
                summary:
                    gameTypeChipLabel(l10n, _gameTypes) ?? l10n.statsAllGameTypes,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in [
                        (const <String>{}, l10n.statsAllGames),
                        (const {'cash'}, l10n.statsCash),
                        (const {'tournament'}, l10n.statsTournament),
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
              title: l10n.statsDateRange,
              summary: StatsFilter(
                      datePreset: _dateRange == null ? _datePreset : null,
                      dateRange: _dateRange)
                  .dateSummary(l10n),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in [
                      (null, l10n.statsAllTime),
                      ('1Y', l10n.stats1Year),
                      ('6M', l10n.stats6Months),
                      ('3M', l10n.stats3Months),
                      ('1M', l10n.stats1Month),
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
                          ? l10n.statsCustomRange
                          : StatsFilter(dateRange: _dateRange).dateLabel(l10n)!),
                      selected: _dateRange != null,
                      onSelected: (_) => _pickRange(),
                    ),
                  ],
                ),
              ],
            ),

            // ── Currency ────────────────────────────────────────────────────
            _section(
              title: l10n.statsCurrency,
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
                title: l10n.statsCountry,
                summary: _summary(_country, l10n.statsAllCountriesSummary),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: Text(l10n.statsAllCountries),
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
                title: l10n.statsVenue,
                summary: _venue == null
                    ? l10n.statsAllVenuesSummary
                    : venueLabel(l10n, _venue!),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in [
                        (null, l10n.statsAllVenues),
                        ('live', l10n.venueLive),
                        ('online', l10n.venueOnline),
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
                title: l10n.statsLocation,
                summary: _summary(_location, l10n.statsAllLocationsSummary),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: Text(l10n.statsAllLocations),
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
                    child: Text(l10n.commonReset),
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
                    child: Text(l10n.filterApply),
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
