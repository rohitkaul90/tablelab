import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/session_model.dart';
import '../models/hand_model.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/ai_usage_pill.dart';
import 'log_session_screen.dart';
import 'ai_analysis/session_analysis_screen.dart';
import 'hand_input/record_hand_sheet.dart';
import 'hand_replayer/hand_replayer_screen.dart';

class SessionDetailScreen extends ConsumerWidget {
  final SessionModel session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plColor = session.profitLoss >= 0 ? Colors.green : Colors.red;
    final dateStr =
        DateFormat('EEEE, MMMM d, yyyy').format(DateTime.parse(session.date));
    final isTournament = isTournamentType(session.gameType);
    final currency = session.currency;
    final sym = currencySymbol(currency);
    final roi = isTournament && session.buyIn > 0
        ? calcROI(session.profitLoss, session.buyIn)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => LogSessionScreen(session: session),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Text(dateStr,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    gameTypeLabel(session.gameType),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatPLWithCurrency(session.profitLoss, currency),
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(
                      color: plColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (roi != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ROI: ${formatROI(roi)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: plColor,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (!isTournament)
            _Row(label: 'Stakes', value: session.stakes),

          if (!isTournament && session.tableSize != null)
            _Row(label: 'Table Size', value: tableSizeLabel(session.tableSize!)),

          _Row(label: 'Buy-in', value: '$sym${session.buyIn.toStringAsFixed(0)}'),

          if (isTournament) ...[
            _Row(
                label: 'Prize Won',
                value: '$sym${(session.prizeWon ?? 0).toStringAsFixed(0)}'),
            if (session.finishPosition != null)
              _Row(
                label: 'Finish',
                value: session.totalEntrants != null
                    ? '${session.finishPosition} / ${session.totalEntrants}'
                    : '${session.finishPosition}',
              ),
          ] else
            _Row(
                label: 'Cash-out',
                value: '$sym${session.cashOut.toStringAsFixed(0)}'),

          if (session.rakePaid != null)
            _Row(
                label: 'Rake / Fees',
                value: '$sym${session.rakePaid!.toStringAsFixed(0)}'),

          if (session.expenseEvents.isNotEmpty) ...[
            _Row(
                label: 'Expenses',
                value: '-$sym${session.totalExpenses.toStringAsFixed(0)}'),
            _Row(
                label: 'Net (after exp.)',
                value: formatPLWithCurrency(
                    session.netAfterExpenses, currency)),
          ],

          _Row(label: 'Currency', value: currency),
          _Row(
              label: 'Duration',
              value: formatDuration(session.durationMinutes)),
          if ((session.breakMinutes ?? 0) > 0)
            _Row(
                label: 'Break',
                value: formatDuration(session.breakMinutes!)),
          _Row(label: 'Time',
              value: '${session.startTime} → ${session.endTime}'),

          if (session.handsPerHour != null)
            _Row(
                label: 'Hands/hr',
                value: '${session.handsPerHour}'),

          if (session.tableQuality != null && !isTournament) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Table',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < session.tableQuality!
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: i < session.tableQuality!
                                ? Colors.amber
                                : Theme.of(context).colorScheme.outline,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tableQualityLabel(session.tableQuality),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (session.location != null && session.location!.isNotEmpty)
            _Row(label: 'Location', value: session.location!),
          if (session.country != null && session.country!.isNotEmpty)
            _Row(label: 'Country', value: session.country!),
          if (session.notes != null && session.notes!.isNotEmpty)
            _Row(label: 'Notes', value: session.notes!),

          if (session.expenseEvents.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'EXPENSES',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            for (final e in session.expenseEvents)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${expenseCategoryLabel(e.category)}'
                        '${e.note != null && e.note!.isNotEmpty ? ' · ${e.note}' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$sym${e.amount.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 24),
          _HandsSection(sessionId: session.id),

          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('AI Analysis'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionAnalysisScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(child: AiUsagePill(kind: AiAnalysisKind.session)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.style_outlined),
            label: const Text('Record a Hand'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () async {
              await showRecordHandSheet(
                context,
                prefilledSessionId: session.id,
                prefilledStakes: session.stakes,
                prefilledSessionLabel:
                    '${DateFormat('MMM d').format(DateTime.parse(session.date))}  ·  ${session.stakes}',
                isTournamentSession: isTournament,
              );
              // No Realtime — refresh so a newly recorded hand shows in the
              // "Hands this session" list above.
              ref.invalidate(handsProvider);
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Delete Session',
                style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref.read(supabaseServiceProvider).deleteSession(session.id);
        if (context.mounted) {
          ref.invalidate(sessionsProvider);
          Navigator.pop(context);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete session: $e')),
          );
        }
      }
    }
  }
}

/// Lists the hands recorded against this session (linked via `sessionId`,
/// set when recording from this screen's "Record a Hand" button or via the
/// session picker during hand input). Display-only — tapping opens the replayer.
class _HandsSection extends ConsumerWidget {
  final String sessionId;

  const _HandsSection({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final handsAsync = ref.watch(handsProvider);

    final header = handsAsync.maybeWhen(
      data: (hands) =>
          hands.where((h) => h.sessionId == sessionId).length.toString(),
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            header == null ? 'HANDS THIS SESSION' : 'HANDS THIS SESSION ($header)',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        handsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Could not load hands.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          data: (hands) {
            final sessionHands = hands
                .where((h) => h.sessionId == sessionId)
                .toList()
              ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
            if (sessionHands.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No hands linked to this session yet. Use "Record a Hand" '
                  'below and they\'ll appear here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final h in sessionHands) _SessionHandTile(hand: h),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Compact hand row for the session detail — hero cards, street/players, time,
/// a board preview, and a tap target into the replayer. Leaner than the Hands
/// tab tile (no swipe-delete or per-hand AI button here).
class _SessionHandTile extends StatelessWidget {
  final PokerHand hand;

  const _SessionHandTile({required this.hand});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = hand.hero;
    final fmt = DateFormat('MMM d · h:mm a');
    final potStr = NumberFormat('#,###').format(hand.finalPot);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => HandReplayerScreen(hand: hand)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              PlayingCard(
                card: hero?.holeCards?.isNotEmpty == true
                    ? hero!.holeCards![0]
                    : null,
                width: 26,
                height: 36,
              ),
              const SizedBox(width: 3),
              PlayingCard(
                card: hero?.holeCards?.length == 2 ? hero!.holeCards![1] : null,
                width: 26,
                height: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pot \$$potStr · ${hand.streetReached}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fmt.format(hand.playedAt.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (hand.allCommunityCards.isNotEmpty) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: hand.allCommunityCards
                      .take(3)
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: PlayingCard(card: c, width: 26, height: 36),
                          ))
                      .toList(),
                ),
                const SizedBox(width: 4),
              ],
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
