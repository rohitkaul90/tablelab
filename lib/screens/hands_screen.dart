import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/hand_model.dart';
import '../models/hand_filter.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../widgets/app_drawer.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/ai_usage_pill.dart';
import 'hand_input/record_hand_sheet.dart';
import 'hand_replayer/hand_replayer_screen.dart';
import 'ai_analysis/hand_analysis_screen.dart';


class HandsScreen extends ConsumerStatefulWidget {
  const HandsScreen({super.key});

  @override
  ConsumerState<HandsScreen> createState() => _HandsScreenState();
}

class _HandsScreenState extends ConsumerState<HandsScreen> {
  // IDs optimistically removed from the list before the server round-trip
  // completes — prevents the "dismissed Dismissible still in tree" assertion.
  final _deletingIds = <String>{};

  Future<void> _deleteHand(String handId) async {
    final l10n = context.l10n;
    setState(() => _deletingIds.add(handId));
    try {
      await ref.read(handServiceProvider).deleteHand(handId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(handId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.handsDeleteFailed('$e'))),
      );
      return;
    }
    if (mounted) ref.invalidate(handsProvider);
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _HandFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handsAsync = ref.watch(handsProvider);
    final filter = ref.watch(handFilterProvider);
    final hasFilter = !filter.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(context.l10n.handsTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(hasFilter ? Icons.filter_list_off : Icons.filter_list),
            tooltip: context.l10n.handsFilterTooltip,
            color: hasFilter ? Theme.of(context).colorScheme.primary : null,
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AiUsagePill(kind: AiAnalysisKind.hand),
            ),
          ),
          Expanded(
            child: handsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.handsLoadError('$e'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ),
        ),
        data: (hands) {
          final visible =
              hands.where((h) => !_deletingIds.contains(h.id)).toList();
          if (visible.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.style_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.handsEmptyTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.handsEmptySubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.75)),
                  ),
                ],
              ),
            );
          }
          final filtered = visible.where(filter.matches).toList();
          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list_off,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 14),
                  Text(
                    context.l10n.handsNoMatchTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(handFilterProvider.notifier)
                        .state = const HandFilter(),
                    icon: const Icon(Icons.clear, size: 18),
                    label: Text(context.l10n.handsClearFilters),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) => _HandTile(
              hand: filtered[i],
              onDelete: () => _deleteHand(filtered[i].id),
            ),
          );
        },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_hands',
        onPressed: () async {
          await showRecordHandSheet(context);
          if (!mounted) return;
          ref.invalidate(handsProvider);
        },
        tooltip: context.l10n.handsRecordTooltip,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HandTile extends StatelessWidget {
  final PokerHand hand;
  final VoidCallback onDelete;

  const _HandTile({required this.hand, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hero = hand.hero;
    final fmt = DateFormat('MMM d · h:mm a');
    final setup = hand.tableSetup;
    final stakes = '\$${setup.smallBlind}/\$${setup.bigBlind}'
        '${setup.straddle != null ? '/\$${setup.straddle}' : ''}';
    // Built per call: a top-level NumberFormat freezes the locale that was
    // active on first use and would ignore a later language switch.
    final potStr = NumberFormat('#,###').format(hand.finalPot);

    return Dismissible(
      key: ValueKey(hand.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.handsDeleteTitle),
          content: Text(l10n.handsDeleteMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HandReplayerScreen(hand: hand),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Measure the text so the cards can be sized to fill exactly the
                // leftover width — never clipping the hand info, and clamped so
                // they can't exceed the 3-line text height (tile stays the same).
                final l1 = l10n.handsTilePot('\$$potStr');
                final l2 = l10n.handsTileSummary(
                    stakes, hand.streetReached, '${hand.isQuickEntry}');
                final l3 = fmt.format(hand.playedAt.toLocal());
                double measure(String t, double size, FontWeight weight) {
                  final tp = TextPainter(
                    text: TextSpan(
                        text: t,
                        style: TextStyle(fontSize: size, fontWeight: weight)),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                  )..layout();
                  return tp.width;
                }

                var textW = measure(l1, 14, FontWeight.bold);
                final w2 = measure(l2, 12, FontWeight.w400);
                final w3 = measure(l3, 11, FontWeight.w400);
                if (w2 > textW) textW = w2;
                if (w3 > textW) textW = w3;

                final board = hand.allCommunityCards.take(3).toList();
                final n = board.length;
                const menuW = 44.0; // ⋮ button
                const safety = 10.0;
                final fixed =
                    3 + 12 + textW + (n * 2) + (n > 0 ? 6 : 0) + menuW + safety;
                // Fill the leftover width across all 2+n cards, but never bigger
                // than 34w (keeps card height under the text block's height).
                final cw =
                    ((constraints.maxWidth - fixed) / (2 + n)).clamp(22.0, 34.0);
                final ch = cw / 0.71;

                final theme = Theme.of(context);
                return Row(
                  children: [
                    PlayingCard(
                      card: hero?.holeCards?.isNotEmpty == true
                          ? hero!.holeCards![0]
                          : null,
                      width: cw,
                      height: ch,
                    ),
                    const SizedBox(width: 3),
                    PlayingCard(
                      card: hero?.holeCards?.length == 2
                          ? hero!.holeCards![1]
                          : null,
                      width: cw,
                      height: ch,
                    ),
                    const SizedBox(width: 12),

                    // Info — natural width, no ellipsis: structurally can't clip.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l1,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(l2,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.60))),
                        const SizedBox(height: 2),
                        Text(l3,
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.75))),
                      ],
                    ),
                    const Spacer(),

                    // Community board — same size as the hole cards.
                    if (n > 0) ...[
                      for (final c in board)
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child:
                              PlayingCard(card: c, width: cw, height: ch),
                        ),
                      const SizedBox(width: 6),
                    ],

                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: Theme.of(context).colorScheme.outline),
                  tooltip: l10n.handsMenuTooltip,
                  padding: EdgeInsets.zero,
                  onSelected: (value) async {
                    if (value == 'ai') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HandAnalysisScreen(hand: hand),
                        ),
                      );
                    } else if (value == 'delete') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.handsDeleteTitle),
                          content: Text(l10n.handsDeleteMessage),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.commonCancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.redAccent),
                              child: Text(l10n.commonDelete),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'ai',
                      child: Row(children: [
                        const Icon(Icons.auto_awesome, size: 18),
                        const SizedBox(width: 10),
                        Text(l10n.handsMenuAiCoaching),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.redAccent),
                        const SizedBox(width: 10),
                        Text(l10n.commonDelete,
                            style: const TextStyle(color: Colors.redAccent)),
                      ]),
                    ),
                  ],
                ),
              ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hand filter sheet ─────────────────────────────────────────────────────────

// Canonical position order for sorting the position chips.
const _posRank = [
  'BTN', 'SB', 'BB', 'UTG', 'UTG+1', 'UTG+2', 'MP', 'HJ', 'CO', 'STR'
];

int _comparePosition(String a, String b) {
  int rank(String p) {
    final i = _posRank.indexOf(p);
    return i < 0 ? _posRank.length : i;
  }

  return rank(a).compareTo(rank(b));
}

int _compareStakes(String a, String b) {
  int bb(String s) => int.tryParse(s.split('/').last) ?? 0;
  return bb(a).compareTo(bb(b));
}

class _HandFilterSheet extends ConsumerStatefulWidget {
  const _HandFilterSheet();

  @override
  ConsumerState<_HandFilterSheet> createState() => _HandFilterSheetState();
}

class _HandFilterSheetState extends ConsumerState<_HandFilterSheet> {
  late HandFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(handFilterProvider);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _chip(String label, bool selected, ValueChanged<bool> onSelected) =>
      FilterChip(label: Text(label), selected: selected, onSelected: onSelected);

  Future<void> _pickDate(String? current, ValueChanged<String?> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null ? DateTime.parse(current) : DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      onPicked('${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final hands = ref.watch(handsProvider).valueOrNull ?? const <PokerHand>[];

    final hasCash = hands.any((h) => !h.isTournament);
    final hasTourney = hands.any((h) => h.isTournament);
    final stakesOpts = hands.map(handStakesKey).toSet().toList()
      ..sort(_compareStakes);
    final sizeOpts = hands.map((h) => h.tableSetup.numSeats).toSet().toList()
      ..sort();
    final posOpts = hands.map(handHeroPosition).toSet().toList()
      ..sort(_comparePosition);

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
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(l10n.handsFilterTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            if (hasCash && hasTourney) ...[
              _label(l10n.handsFilterGameType),
              Wrap(spacing: 8, children: [
                _chip(l10n.handsFilterCash, _draft.gameType == 'cash',
                    (on) => setState(() => _draft = _draft.copyWith(gameType: on ? 'cash' : null))),
                _chip(l10n.handsFilterTournament, _draft.gameType == 'tournament',
                    (on) => setState(() => _draft = _draft.copyWith(gameType: on ? 'tournament' : null))),
              ]),
              const SizedBox(height: 16),
            ],

            _label(l10n.handsFilterMinPot),
            Wrap(spacing: 8, children: [
              for (final bb in const [20, 50, 100])
                _chip('≥ ${bb}bb', _draft.minPotBb == bb,
                    (on) => setState(() => _draft = _draft.copyWith(minPotBb: on ? bb : null))),
            ]),
            const SizedBox(height: 16),

            _label(l10n.handsFilterStreet),
            Wrap(spacing: 8, children: [
              for (final s in const ['Pre-flop', 'Flop', 'Turn', 'River'])
                _chip(s, _draft.streetReached == s,
                    (on) => setState(() => _draft = _draft.copyWith(streetReached: on ? s : null))),
            ]),
            const SizedBox(height: 16),

            if (stakesOpts.isNotEmpty) ...[
              _label(l10n.handsFilterStakes),
              Wrap(spacing: 8, children: [
                for (final s in stakesOpts)
                  _chip(s, _draft.stakes == s,
                      (on) => setState(() => _draft = _draft.copyWith(stakes: on ? s : null))),
              ]),
              const SizedBox(height: 16),
            ],

            if (sizeOpts.isNotEmpty) ...[
              _label(l10n.handsFilterTableSize),
              Wrap(spacing: 8, children: [
                for (final n in sizeOpts)
                  _chip(n == 2 ? l10n.handsFilterHeadsUp : l10n.handsFilterHanded(n), _draft.tableSize == n,
                      (on) => setState(() => _draft = _draft.copyWith(tableSize: on ? n : null))),
              ]),
              const SizedBox(height: 16),
            ],

            if (posOpts.isNotEmpty) ...[
              _label(l10n.handsFilterPosition),
              Wrap(spacing: 8, children: [
                for (final p in posOpts)
                  _chip(p, _draft.heroPosition == p,
                      (on) => setState(() => _draft = _draft.copyWith(heroPosition: on ? p : null))),
              ]),
              const SizedBox(height: 16),
            ],

            _label(l10n.handsFilterDateRange),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(_draft.dateFrom,
                      (v) => setState(() => _draft = _draft.copyWith(dateFrom: v))),
                  child: Text(_draft.dateFrom ?? l10n.handsFilterFrom,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(_draft.dateTo,
                      (v) => setState(() => _draft = _draft.copyWith(dateTo: v))),
                  child: Text(_draft.dateTo ?? l10n.handsFilterTo,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
            if (_draft.dateFrom != null || _draft.dateTo != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() =>
                      _draft = _draft.copyWith(dateFrom: null, dateTo: null)),
                  child: Text(l10n.handsFilterClearDates),
                ),
              ),
            const SizedBox(height: 24),

            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(handFilterProvider.notifier).state =
                        const HandFilter();
                    Navigator.pop(context);
                  },
                  child: Text(l10n.handsFilterClearAll),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    ref.read(handFilterProvider.notifier).state = _draft;
                    Navigator.pop(context);
                  },
                  child: Text(l10n.handsFilterApply),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
