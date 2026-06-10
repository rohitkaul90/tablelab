import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tournament_listing.dart';
import '../providers/providers.dart';
class TournamentCalendarScreen extends ConsumerStatefulWidget {
  const TournamentCalendarScreen({super.key});

  @override
  ConsumerState<TournamentCalendarScreen> createState() =>
      _TournamentCalendarScreenState();
}

class _TournamentCalendarScreenState
    extends ConsumerState<TournamentCalendarScreen> {
  String? _country;

  bool get _hasFilter => _country != null;

  void _openFilterSheet(List<String> countries) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _TournamentFilterSheet(
        allCountries: countries,
        selectedCountry: _country,
        onApply: (country) => setState(() => _country = country),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(tournamentListingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournaments'),
        actions: [
          listAsync.maybeWhen(
            data: (all) {
              final countries =
                  all.map((t) => t.country).toSet().toList()..sort();
              return IconButton(
                icon: Badge(
                  isLabelVisible: _hasFilter,
                  child: const Icon(Icons.filter_list),
                ),
                tooltip: 'Filter',
                onPressed: () => _openFilterSheet(countries),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_outlined, size: 48),
                const SizedBox(height: 12),
                const Text('Could not load tournaments'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(tournamentListingsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (all) => _buildBody(context, all),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TournamentListing> all) {
    final filtered = all.where((t) {
      if (t.isPast) return false;
      if (_country != null && t.country != _country) return false;
      return true;
    }).toList();

    // Build flat items list: String (month header) | TournamentListing (card)
    final items = <Object>[];
    String? lastMonth;
    for (final t in filtered) {
      if (t.monthKey != lastMonth) {
        items.add(t.monthKey);
        lastMonth = t.monthKey;
      }
      items.add(t);
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tournamentListingsProvider),
      child: filtered.isEmpty
          ? _buildEmpty(context)
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is String) return _MonthHeader(label: item);
                return _TournamentCard(tournament: item as TournamentListing);
              },
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                _hasFilter ? 'No tournaments match your filters' : 'No upcoming tournaments',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (_hasFilter) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _country = null),
                  child: const Text('Clear filters'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tournament filter sheet ────────────────────────────────────────────────────

class _TournamentFilterSheet extends StatefulWidget {
  final List<String> allCountries;
  final String? selectedCountry;
  final void Function(String? country) onApply;

  const _TournamentFilterSheet({
    required this.allCountries,
    required this.selectedCountry,
    required this.onApply,
  });

  @override
  State<_TournamentFilterSheet> createState() => _TournamentFilterSheetState();
}

class _TournamentFilterSheetState extends State<_TournamentFilterSheet> {
  late String? _country;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _country = widget.selectedCountry;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _search.isEmpty
        ? widget.allCountries
        : widget.allCountries
            .where((c) => c.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('Filter Tournaments',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() { _country = null; _search = ''; }),
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () {
                    widget.onApply(_country);
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                // Country filter
                Text('Country',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 10),

                // Search
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search countries…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),

                // All option
                _CountryTile(
                  label: 'All countries',
                  selected: _country == null,
                  onTap: () => setState(() => _country = null),
                ),

                // Country list
                ...filtered.map((c) => _CountryTile(
                      label: c,
                      selected: _country == c,
                      onTap: () => setState(() => _country = _country == c ? null : c),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CountryTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

// ── Month header ───────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

// ── Tournament card ────────────────────────────────────────────────────────────

class _TournamentCard extends StatelessWidget {
  final TournamentListing tournament;
  const _TournamentCard({required this.tournament});

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: t.url != null ? () => _openUrl(t.url!) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: series badge + dates + ongoing badge
              Row(
                children: [
                  if (t.series != null) ...[
                    _SeriesBadge(series: t.series!),
                    const SizedBox(width: 8),
                  ],
                  if (t.isOngoing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.green.withAlpha(100), width: 0.5),
                      ),
                      child: Text(
                        'LIVE NOW',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    t.formattedDates,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(180),
                    ),
                  ),
                  if (t.url != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // Name
              Text(
                t.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              // Venue + city
              Text(
                '${t.venue}  ·  ${t.city}, ${t.country}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160),
                ),
              ),
              // Buy-in / guarantee row
              if (t.buyIn != null || t.guarantee != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (t.buyIn != null) ...[
                      Icon(Icons.sell_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurface.withAlpha(140)),
                      const SizedBox(width: 4),
                      Text(
                        t.formattedBuyIn,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (t.buyIn != null && t.guarantee != null)
                      const SizedBox(width: 16),
                    if (t.guarantee != null)
                      Text(
                        t.formattedGuarantee,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade300,
                        ),
                      ),
                  ],
                ),
              ],
              if (t.notes != null && t.notes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  t.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

// ── Series badge ───────────────────────────────────────────────────────────────

class _SeriesBadge extends StatelessWidget {
  final String series;
  const _SeriesBadge({required this.series});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(series);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: bg.withAlpha(120), width: 0.5),
      ),
      child: Text(
        series.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  (Color, Color) _colors(String s) {
    switch (s.toUpperCase()) {
      case 'WSOP': return (Colors.amber, Colors.amber);
      case 'WPT': return (Colors.blue, Colors.blue.shade300);
      case 'EPT': return (Colors.green, Colors.green.shade400);
      case 'UKIPT': return (Colors.red, Colors.red.shade300);
      default: return (Colors.purple, Colors.purple.shade300);
    }
  }
}
