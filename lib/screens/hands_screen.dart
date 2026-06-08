import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/hand_model.dart';
import '../providers/providers.dart';
import '../widgets/app_drawer.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/ai_usage_pill.dart';
import 'hand_input/hand_input_screen.dart';
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
    setState(() => _deletingIds.add(handId));
    try {
      await ref.read(handServiceProvider).deleteHand(handId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(handId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete hand: $e')),
      );
      return;
    }
    if (mounted) ref.invalidate(handsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final handsAsync = ref.watch(handsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Hands'),
        centerTitle: true,
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
            child: Text('Error loading hands: $e',
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
                    'No hands recorded yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap + to record and replay a hand',
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
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visible.length,
            itemBuilder: (ctx, i) => _HandTile(
              hand: visible[i],
              onDelete: () => _deleteHand(visible[i].id),
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
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HandInputScreen()),
          );
          if (!mounted) return;
          ref.invalidate(handsProvider);
        },
        tooltip: 'Record hand',
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
    final hero = hand.hero;
    final fmt = DateFormat('MMM d, y · h:mm a');
    final setup = hand.tableSetup;
    final stakes = '\$${setup.smallBlind}/\$${setup.bigBlind}'
        '${setup.straddle != null ? '/\$${setup.straddle}' : ''}';

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
          title: const Text('Delete hand?'),
          content: const Text('This hand record will be permanently deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Delete'),
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
            child: Row(
              children: [
                // Hero hole cards
                Row(
                  children: [
                    PlayingCard(
                      card: hero?.holeCards?.isNotEmpty == true
                          ? hero!.holeCards![0]
                          : null,
                      width: 30,
                      height: 42,
                    ),
                    const SizedBox(width: 3),
                    PlayingCard(
                      card: hero?.holeCards?.length == 2 ? hero!.holeCards![1] : null,
                      width: 30,
                      height: 42,
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Info column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$stakes · ${setup.numSeats}-max',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${hand.streetReached} · ${hand.players.length} players',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.60),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmt.format(hand.playedAt.toLocal()),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),

                // Community cards preview (up to 3)
                if (hand.allCommunityCards.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: hand.allCommunityCards
                        .take(3)
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: PlayingCard(card: c, width: 22, height: 30),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(width: 4),
                ],

                IconButton(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.75),
                  tooltip: 'AI Coaching',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HandAnalysisScreen(hand: hand),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Theme.of(context).colorScheme.outline, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
