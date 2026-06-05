import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';
import '../widgets/app_drawer.dart';
import '../widgets/stat_card.dart';
import '../widgets/session_tile.dart';
import 'log_session_screen.dart';
import 'session_detail_screen.dart';
import 'import_source_screen.dart';
import 'analytics_screen.dart';
import 'ai_analysis/session_analysis_screen.dart';
import '../providers/profile_provider.dart';
import 'profile_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Overview filter state
  String? _gameFilter;
  String? _displayCurrency;

  // Analytics filter state
  String? _analyticsVenueFilter;
  String? _analyticsCountryFilter;
  String? _analyticsLocationFilter;
  String? _analyticsDisplayCurrency;
  String? _analyticsDateFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilter => _displayCurrency != null;

  bool get _hasActiveAnalyticsFilter =>
      _analyticsDisplayCurrency != null ||
      _analyticsCountryFilter != null ||
      _analyticsVenueFilter != null ||
      _analyticsLocationFilter != null ||
      _analyticsDateFilter != null;

  void _showFilterSheet(List<SessionModel> sessions) {
    final effectiveCurrency = _displayCurrency ??
        (sessions.isEmpty
            ? 'CAD'
            : ([...sessions]..sort((a, b) => b.date.compareTo(a.date)))
                .first
                .currency);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _DashboardFilterSheet(
        displayCurrency: effectiveCurrency,
        onCurrencyChanged: (c) => setState(() => _displayCurrency = c),
        onReset: () => setState(() => _displayCurrency = null),
      ),
    );
  }

  void _showAnalyticsFilterSheet(List<SessionModel> sessions) {
    final effectiveCurrency = _analyticsDisplayCurrency ??
        (sessions.isEmpty
            ? 'CAD'
            : ([...sessions]..sort((a, b) => b.date.compareTo(a.date)))
                .first
                .currency);

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
      builder: (_) => AnalyticsFilterSheet(
        displayCurrency: effectiveCurrency,
        countryFilter: _analyticsCountryFilter,
        venueFilter: _analyticsVenueFilter,
        locationFilter: _analyticsLocationFilter,
        dateFilter: _analyticsDateFilter,
        allCountries: allCountries,
        hasMultipleCountries: allCountries.length > 1,
        hasOnline: sessions.any((s) => isOnlineSession(s.location)),
        hasLive: sessions.any((s) => !isOnlineSession(s.location)),
        allLocations: allLocations,
        onApply: (currency, country, venue, location, date) => setState(() {
          _analyticsDisplayCurrency = currency;
          _analyticsCountryFilter = country;
          _analyticsVenueFilter = venue;
          _analyticsLocationFilter = location;
          _analyticsDateFilter = date;
        }),
        onReset: () => setState(() {
          _analyticsDisplayCurrency = null;
          _analyticsCountryFilter = null;
          _analyticsVenueFilter = null;
          _analyticsLocationFilter = null;
          _analyticsDateFilter = null;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider);
    final showFab = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Dashboard'),
        actions: [
          if (_tabController.index == 0)
            sessionsAsync.maybeWhen(
              data: (sessions) => IconButton(
                icon: Badge(
                  isLabelVisible: _hasActiveFilter,
                  child: const Icon(Icons.tune),
                ),
                tooltip: 'Display options',
                onPressed: () => _showFilterSheet(sessions),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          if (_tabController.index == 1)
            sessionsAsync.maybeWhen(
              data: (sessions) => IconButton(
                icon: Badge(
                  isLabelVisible: _hasActiveAnalyticsFilter,
                  child: const Icon(Icons.tune),
                ),
                tooltip: 'Display options',
                onPressed: () => _showAnalyticsFilterSheet(sessions),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              heroTag: 'fab_dashboard',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogSessionScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Log Session'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(
            gameFilter: _gameFilter,
            displayCurrency: _displayCurrency,
            onGameFilterChanged: (v) => setState(() => _gameFilter = v),
          ),
          AnalyticsScreen(
            venueFilter: _analyticsVenueFilter,
            countryFilter: _analyticsCountryFilter,
            locationFilter: _analyticsLocationFilter,
            displayCurrency: _analyticsDisplayCurrency,
            dateFilter: _analyticsDateFilter,
          ),
        ],
      ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  final String? gameFilter;
  final String? displayCurrency;
  final ValueChanged<String?> onGameFilterChanged;

  const _OverviewTab({
    required this.gameFilter,
    required this.displayCurrency,
    required this.onGameFilterChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (sessions) => _OverviewBody(
        sessions: sessions,
        gameFilter: gameFilter,
        displayCurrency: displayCurrency,
        onGameFilterChanged: onGameFilterChanged,
      ),
    );
  }
}

// ── Overview Body ─────────────────────────────────────────────────────────────

class _OverviewBody extends ConsumerWidget {
  final List<SessionModel> sessions;
  final String? gameFilter;
  final String? displayCurrency;
  final ValueChanged<String?> onGameFilterChanged;

  const _OverviewBody({
    required this.sessions,
    required this.gameFilter,
    required this.displayCurrency,
    required this.onGameFilterChanged,
  });

  bool get _hasCash => sessions.any((s) => s.gameType == 'cash');
  bool get _hasTournament =>
      sessions.any((s) => isTournamentType(s.gameType));
  bool get _showGameFilter => _hasCash && _hasTournament;

  String _effectiveCurrency() {
    if (displayCurrency != null) return displayCurrency!;
    if (sessions.isEmpty) return 'CAD';
    return ([...sessions]..sort((a, b) => b.date.compareTo(a.date)))
        .first
        .currency;
  }

  List<SessionModel> get _filtered {
    if (gameFilter == null) return sessions;
    if (gameFilter == 'tournament') {
      return sessions.where((s) => isTournamentType(s.gameType)).toList();
    }
    return sessions.where((s) => s.gameType == 'cash').toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = _filtered;
    final currency = _effectiveCurrency();
    final stats = _Stats.from(filtered, currency);
    final recent = ([...sessions]
          ..sort((a, b) => b.date.compareTo(a.date)))
        .take(5)
        .toList();
    final profile = ref.watch(profileProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        // ── Game-type chip strip ───────────────────────────────────────────
        if (_showGameFilter) ...[
          SingleChildScrollView(
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
                      selected: gameFilter == entry.$1,
                      onSelected: (_) => onGameFilterChanged(entry.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Total P&L hero card ────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                Text(
                  gameFilter == null
                      ? 'Total P&L'
                      : '${gameFilter == 'cash' ? 'Cash' : 'Tournament'} P&L',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  formatPLWithCurrency(stats.totalPL, currency),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: stats.totalPL >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Current Bankroll card (or prompt to set it) ───────────────────
        if (profile?.startingBankroll != null)
          _CurrentBankrollCard(
            startingBankroll: convertCurrency(
              profile!.startingBankroll!,
              profile.startingBankrollCurrency,
              currency,
            ),
            totalPL: stats.totalPL,
            currency: currency,
            stakes: profile.preferredStakes,
          )
        else
          _SetBankrollPrompt(),
        const SizedBox(height: 12),

        // ── Stat cards grid ────────────────────────────────────────────────
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: constraints.maxWidth > 520 ? 4 : 2,
            childAspectRatio: 2.0,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: gameFilter == 'tournament'
                ? [
                    StatCard(
                      label: 'Sessions',
                      value: '${stats.sessionCount}',
                      accentColor: Colors.deepPurple,
                    ),
                    StatCard(
                      label: 'ITM',
                      value: '${stats.itm}',
                      accentColor: Colors.teal,
                    ),
                    StatCard(
                      label: 'ITM %',
                      value: '${stats.itmPct.toStringAsFixed(0)}%',
                      accentColor: Colors.cyan,
                    ),
                    StatCard(
                      label: 'ROI',
                      value: formatROI(stats.roi),
                      valueColor: stats.roi >= 0 ? Colors.green : Colors.red,
                      accentColor: Colors.amber,
                    ),
                  ]
                : [
                    StatCard(
                      label: 'Hours Played',
                      value: '${stats.totalHours.round()}h',
                      accentColor: Colors.blue,
                    ),
                    StatCard(
                      label: 'Win Rate',
                      value:
                          '${formatPLWithCurrency(stats.hourlyRate, currency)}/hr',
                      valueColor:
                          stats.hourlyRate >= 0 ? Colors.green : Colors.red,
                      accentColor: Colors.teal,
                    ),
                    StatCard(
                      label: 'Sessions',
                      value: '${stats.sessionCount}',
                      accentColor: Colors.deepPurple,
                    ),
                    StatCard(
                      label: 'W / L',
                      value: '${stats.wins}W  ${stats.losses}L',
                      valueColor: stats.wins > stats.losses
                          ? Colors.green
                          : stats.losses > stats.wins
                              ? Colors.red
                              : null,
                      accentColor: Colors.orange,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Recent sessions ────────────────────────────────────────────────
        if (recent.isNotEmpty) ...[
          Text('Recent Sessions',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          ...recent.map(
            (s) => SessionTile(
              session: s,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(session: s)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AiCoachingCard(session: recent.first),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.casino_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No sessions yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Log your first session — or import your\nhistory from another app.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LogSessionScreen()),
                    ),
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
              ),
            ),
          ),
      ],
    );
  }
}

// ── Set Bankroll prompt ───────────────────────────────────────────────────────

class _SetBankrollPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: scheme.onSurface.withValues(alpha: 0.4), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Set your starting bankroll to track your current balance →',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Current Bankroll card ─────────────────────────────────────────────────────

class _CurrentBankrollCard extends StatelessWidget {
  final double startingBankroll;
  final double totalPL;
  final String currency;
  final String? stakes;

  const _CurrentBankrollCard({
    required this.startingBankroll,
    required this.totalPL,
    required this.currency,
    this.stakes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBankroll = startingBankroll + totalPL;
    final isUp = currentBankroll >= startingBankroll;
    final subtle =
        theme.colorScheme.onSurface.withValues(alpha: 0.6);

    // Growth % since the starting bankroll (guard divide-by-zero).
    final growthPct =
        startingBankroll > 0 ? (totalPL / startingBankroll) * 100 : null;
    final growthStr = growthPct == null
        ? ''
        : '  ·  ${growthPct >= 0 ? '+' : ''}'
            '${growthPct.toStringAsFixed(growthPct.abs() >= 10 ? 0 : 1)}%';

    // Buy-ins available at the player's stakes (~100bb cash buy-in). Only shown
    // when the stakes parse to a big blind — skips tournament / unset stakes.
    final bb = stakes != null ? parseBBFromStakes(stakes!) : null;
    final buyIns = (bb != null && bb > 0 && currentBankroll > 0)
        ? (currentBankroll / (bb * 100)).floor()
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Text('Current Bankroll', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              formatPLWithCurrency(currentBankroll, currency),
              style: theme.textTheme.displayMedium?.copyWith(
                    color: isUp ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Started with ${formatPLWithCurrency(startingBankroll, currency)}'
              '$growthStr',
              style: theme.textTheme.bodySmall?.copyWith(color: subtle),
            ),
            if (buyIns != null) ...[
              const SizedBox(height: 4),
              Text(
                '≈ $buyIns buy-in${buyIns == 1 ? '' : 's'} at $stakes',
                style: theme.textTheme.bodySmall?.copyWith(color: subtle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── AI Coaching card ──────────────────────────────────────────────────────────

class _AiCoachingCard extends StatelessWidget {
  final SessionModel session;
  const _AiCoachingCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SessionAnalysisScreen(session: session)),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.6),
                scheme.surface,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: scheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Get AI coaching',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: scheme.primary)),
                    const SizedBox(height: 2),
                    Text('Analyse your latest session for leaks & insights.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashboard filter sheet (currency) ─────────────────────────────────────────

class _DashboardFilterSheet extends StatefulWidget {
  final String displayCurrency;
  final ValueChanged<String> onCurrencyChanged;
  final VoidCallback onReset;

  const _DashboardFilterSheet({
    required this.displayCurrency,
    required this.onCurrencyChanged,
    required this.onReset,
  });

  @override
  State<_DashboardFilterSheet> createState() => _DashboardFilterSheetState();
}

class _DashboardFilterSheetState extends State<_DashboardFilterSheet> {
  late String _currency;

  @override
  void initState() {
    super.initState();
    _currency = widget.displayCurrency;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      maxChildSize: 0.7,
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
            Text('Display Options',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),

            Text('Currency', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: supportedDisplayCurrencies.map((c) {
                final selected = _currency == c;
                return ChoiceChip(
                  label: Text('$c ${currencySymbol(c)}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _currency = c),
                );
              }).toList(),
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
                      widget.onCurrencyChanged(_currency);
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
