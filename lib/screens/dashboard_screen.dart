import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../models/profile_model.dart';
import '../models/stats_filter.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';
import '../widgets/app_drawer.dart';
import '../widgets/approx_currency_chip.dart';
import '../widgets/stat_card.dart';
import '../widgets/ai_coaching_card.dart';
import '../widgets/game_type_filter.dart';
import 'live_session_screen.dart';
import 'import_source_screen.dart';
import 'analytics_screen.dart';
import 'metric_chart_screen.dart';
import '../providers/profile_provider.dart';
import 'profile_screen.dart';

/// Legacy Overview tab kill-switch. The Overview duplicated the Summary tab's
/// metrics (device-review decision 2026-07-10: retired; its unique pieces —
/// AI coaching card, Live-now card, first-session CTA — moved into the
/// Summary tab). Flip to `true` to restore the tab; the implementation below
/// (`_OverviewTab` and friends) is kept intact and referenced through this
/// flag so the analyzer never sees dead code.
const bool kShowOverviewTab = false;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // Overview game-type pills (legacy, flag-gated). null = not yet initialised
  // (defaults to the last-played game type once sessions load).
  Set<String>? _gameTypes;

  // ONE "Display Options" filter for the whole Stats screen — every tab
  // (Summary, factor tabs, Tips) reads the same selection. (The old
  // per-tab filter pair was an unsynced-state wart.)
  StatsFilter _filter = const StatsFilter();

  // Ordering applied to every factor tab's breakdown card.
  InsightSort _insightSort = InsightSort.rate;

  // Opens the shared Display Options sheet for whichever tab is active.
  void _openFilterSheet(
    List<SessionModel> sessions,
    StatsFilter current,
    ValueChanged<StatsFilter> onApply,
    VoidCallback onReset,
  ) {
    final allCountries = sessions
        .map((s) => s.country)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final allLocations = sessions
        .map((s) => s.location)
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatsFilterSheet(
        filter: current,
        effectiveCurrency: current.effectiveCurrency(sessions,
            homeCurrency:
                ref.read(profileProvider).valueOrNull?.displayCurrency),
        allCountries: allCountries,
        hasMultipleCountries: allCountries.length > 1,
        hasOnline: sessions.any((s) => isOnlineSession(s.location)),
        hasLive: sessions.any((s) => !isOnlineSession(s.location)),
        hasCash: sessions.any((s) => !isTournamentType(s.gameType)),
        hasTournaments: sessions.any((s) => isTournamentType(s.gameType)),
        allLocations: allLocations,
        onApply: onApply,
        onReset: onReset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(completedSessionsProvider);

    return sessionsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
          ),
          title: const Text('Stats'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
          ),
          title: const Text('Stats'),
        ),
        body: Center(child: Text('Error: $e')),
      ),
      data: (sessions) => _buildTabs(context, sessions),
    );
  }

  Widget _buildTabs(BuildContext context, List<SessionModel> sessions) {
    // Everything the tabs render is computed ONCE per build; the factor list
    // is data-gated, so the tab strip only shows breakdowns that exist.
    final homeCurrency =
        ref.watch(profileProvider).valueOrNull?.displayCurrency;
    final data = AnalyticsData.compute(sessions, _filter, homeCurrency);
    final factors = analyticsFactors(data);

    final tabs = <Tab>[
      if (kShowOverviewTab) const Tab(text: 'Overview'),
      const Tab(text: 'Summary'),
      for (final f in factors) Tab(text: f.tabLabel),
      const Tab(text: 'Tips'),
    ];
    final views = <Widget>[
      if (kShowOverviewTab)
        _OverviewTab(
          gameTypes: _gameTypes,
          filter: _filter,
          onGameTypesChanged: (v) => setState(() => _gameTypes = v),
        ),
      AnalyticsSummaryTab(
        data: data,
        gameTypes: _filter.gameTypes,
        onGameTypesChanged: (t) =>
            setState(() => _filter = _filter.withGameTypes(t)),
      ),
      for (final f in factors)
        AnalyticsFactorTab(
          data: data,
          factor: f,
          sort: _insightSort,
          onSortChanged: (v) => setState(() => _insightSort = v),
        ),
      AnalyticsTipsTab(data: data),
    ];

    // NOTE: DefaultTabController resets to the first tab when the tab COUNT
    // changes (e.g. a filter hides a factor) — acceptable; factor
    // availability rarely changes mid-session.
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
          ),
          title: const Text('Stats'),
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: _filter.isActive,
                child: const Icon(Icons.tune),
              ),
              tooltip: 'Display options',
              onPressed: () => _openFilterSheet(
                sessions,
                _filter,
                (f) => setState(() => _filter = f),
                () => setState(() => _filter = const StatsFilter()),
              ),
            ),
          ],
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'fab_dashboard',
          onPressed: () => showLogSessionChooser(context, ref),
          tooltip: 'Log session',
          child: const Icon(Icons.add),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  final Set<String>? gameTypes;
  final StatsFilter filter;
  final ValueChanged<Set<String>> onGameTypesChanged;

  const _OverviewTab({
    required this.gameTypes,
    required this.filter,
    required this.onGameTypesChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(completedSessionsProvider);
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (sessions) => _OverviewBody(
        sessions: sessions,
        gameTypes: gameTypes,
        filter: filter,
        onGameTypesChanged: onGameTypesChanged,
      ),
    );
  }
}

// ── Overview Body ─────────────────────────────────────────────────────────────

class _OverviewBody extends ConsumerWidget {
  final List<SessionModel> sessions;
  final Set<String>? gameTypes;
  final StatsFilter filter;
  final ValueChanged<Set<String>> onGameTypesChanged;

  const _OverviewBody({
    required this.sessions,
    required this.gameTypes,
    required this.filter,
    required this.onGameTypesChanged,
  });

  // The active selection. null (untouched) defaults to the last-played game
  // type; an empty set means "all game types".
  Set<String> get _effectiveTypes => gameTypes ?? defaultGameTypes(sessions);

  List<SessionModel> get _filtered =>
      filterByGameTypes(filter.apply(sessions), _effectiveTypes);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = _filtered;
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = filter.effectiveCurrency(sessions,
        homeCurrency: profile?.displayCurrency);
    final stats = _Stats.from(filtered, currency);
    final types = _effectiveTypes;
    // "All" = nothing selected (both pills off).
    final isAllTypes = types.isEmpty;
    final tournamentOnly = types.length == 1 && types.contains('tournament');

    final gtLabel = gameTypeChipLabel(types);
    final activeFilters = <String>[
      if (gtLabel != null) gtLabel,
      ...filter.labels(),
      currency,
    ];

    void openMetric(StatMetric metric) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MetricChartScreen(
              metric: metric,
              sessions: filtered,
              displayCurrency: currency,
              activeFilters: activeFilters,
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        const LiveSessionCard(),
        // ── Game-type filter pills (always shown) ──────────────────────────
        GameTypeFilterChips(
          selected: types,
          onChanged: onGameTypesChanged,
        ),
        const SizedBox(height: 12),

        // ── Profit hero card (bankroll folded in) ──────────────────────────
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openMetric(StatMetric.profit),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isAllTypes
                            ? 'Profit'
                            : '${tournamentOnly ? 'Tournament' : 'Cash'} Profit',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.show_chart,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.6)),
                      // Mixed-currency totals are FX-converted — one tappable
                      // marker for the whole card (not per number).
                      if (isMultiCurrency(filtered)) ...[
                        const SizedBox(width: 6),
                        ApproxCurrencyChip(currency: currency),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatPLWithCurrency(stats.totalPL, currency),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: stats.totalPL >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  // Bankroll is one overall figure (starting bankroll + total
                  // P&L across all game types) so it only makes sense
                  // unfiltered — hide it when a game-type pill or any
                  // session-narrowing filter (date/location/etc.) is active.
                  if (isAllTypes && !filter.narrowsSessions)
                    _InlineBankroll(
                      profile: profile,
                      totalPL: stats.totalPL,
                      currency: currency,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Stat cards grid (each tile opens its trend chart) ──────────────
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: constraints.maxWidth > 520 ? 4 : 2,
            childAspectRatio: 2.0,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: tournamentOnly
                ? [
                    StatCard(
                      label: 'Sessions',
                      value: '${stats.sessionCount}',
                      onTap: () => openMetric(StatMetric.sessions),
                    ),
                    StatCard(
                      label: 'ITM',
                      value: '${stats.itm}',
                      onTap: () => openMetric(StatMetric.itm),
                    ),
                    StatCard(
                      label: 'ITM %',
                      value: '${stats.itmPct.toStringAsFixed(0)}%',
                      onTap: () => openMetric(StatMetric.itmPct),
                    ),
                    StatCard(
                      label: 'ROI',
                      value: formatROI(stats.roi),
                      valueColor: stats.roi >= 0 ? Colors.green : Colors.red,
                      onTap: () => openMetric(StatMetric.roi),
                    ),
                  ]
                : [
                    StatCard(
                      label: 'Hours Played',
                      value: formatHours(stats.totalHours),
                      onTap: () => openMetric(StatMetric.hours),
                    ),
                    StatCard(
                      label: 'Win Rate',
                      value:
                          '${formatPLWithCurrency(stats.hourlyRate, currency)}/hr',
                      valueColor:
                          stats.hourlyRate >= 0 ? Colors.green : Colors.red,
                      onTap: () => openMetric(StatMetric.winRate),
                    ),
                    StatCard(
                      label: 'Sessions',
                      value: '${stats.sessionCount}',
                      onTap: () => openMetric(StatMetric.sessions),
                    ),
                    StatCard(
                      label: 'W / L',
                      value: '${stats.wins}W  ${stats.losses}L',
                      valueColor: stats.wins > stats.losses
                          ? Colors.green
                          : stats.losses > stats.wins
                              ? Colors.red
                              : null,
                      onTap: () => openMetric(StatMetric.winLoss),
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 20),

        // ── AI coaching (sessions logged) or a compact first-session CTA ───
        if (sessions.isNotEmpty)
          AiCoachingCard(
            session: ([...sessions]..sort((a, b) => b.date.compareTo(a.date)))
                .first,
          )
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
      ],
    );
  }
}

// ── Inline bankroll (secondary line under the Profit hero) ────────────────────

/// Bankroll shown as a quiet line inside the Profit card rather than its own
/// card. When a starting bankroll is set it shows the current balance + growth
/// %; otherwise it offers an unobtrusive link to set one (deliberately
/// low-key — most players don't track a poker-specific bankroll).
class _InlineBankroll extends StatelessWidget {
  final ProfileModel? profile;
  final double totalPL;
  final String currency;

  const _InlineBankroll({
    required this.profile,
    required this.totalPL,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.colorScheme.onSurfaceVariant;
    final starting = profile?.startingBankroll;

    if (starting == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: subtle,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: const Text('Set starting bankroll'),
        ),
      );
    }

    final startConverted =
        convertCurrency(starting, profile!.startingBankrollCurrency, currency);
    final current = startConverted + totalPL;
    final growthPct =
        startConverted > 0 ? (totalPL / startConverted) * 100 : null;
    final growthStr = growthPct == null
        ? ''
        : '  ·  ${growthPct >= 0 ? '+' : ''}'
            '${growthPct.toStringAsFixed(growthPct.abs() >= 10 ? 0 : 1)}%';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Bankroll ${formatAmount(current, currency)}$growthStr',
        style: theme.textTheme.bodySmall?.copyWith(color: subtle),
      ),
    );
  }
}

// ── Stats Model ───────────────────────────────────────────────────────────────

class _Stats {
  final double totalPL;
  final double totalHours;
  final double hourlyRate;
  final int sessionCount;
  final int wins;
  final int losses;
  final int itm;
  final double itmPct;
  final double roi;

  _Stats({
    required this.totalPL,
    required this.totalHours,
    required this.hourlyRate,
    required this.sessionCount,
    required this.wins,
    required this.losses,
    required this.itm,
    required this.itmPct,
    required this.roi,
  });

  factory _Stats.from(List<SessionModel> sessions, String displayCurrency) {
    if (sessions.isEmpty) {
      return _Stats(
        totalPL: 0, totalHours: 0, hourlyRate: 0, sessionCount: 0,
        wins: 0, losses: 0, itm: 0, itmPct: 0, roi: 0,
      );
    }

    double toDisplay(double amount, String from) =>
        convertCurrency(amount, from, displayCurrency);

    final totalPL = sessions.fold(
        0.0, (sum, s) => sum + toDisplay(s.profitLoss, s.currency));
    final totalMinutes = sessions.fold(0, (s, e) => s + e.durationMinutes);
    final totalHours = totalMinutes / 60.0;
    final hourlyRate = totalHours > 0 ? totalPL / totalHours : 0.0;
    final wins = sessions.where((s) => s.profitLoss > 0).length;
    final losses = sessions.where((s) => s.profitLoss <= 0).length;
    final totalBuyIn = sessions.fold(
        0.0, (sum, s) => sum + toDisplay(s.buyIn, s.currency));
    final roi = totalBuyIn > 0 ? totalPL / totalBuyIn * 100 : 0.0;
    final itm = sessions.where((s) => isSessionItm(s.prizeWon, s.profitLoss)).length;
    final itmPct = sessions.isNotEmpty ? itm / sessions.length * 100 : 0.0;

    return _Stats(
      totalPL: totalPL,
      totalHours: totalHours,
      hourlyRate: hourlyRate,
      sessionCount: sessions.length,
      wins: wins,
      losses: losses,
      itm: itm,
      itmPct: itmPct,
      roi: roi,
    );
  }
}
