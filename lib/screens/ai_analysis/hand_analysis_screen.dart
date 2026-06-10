import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/hand_model.dart';
import '../../models/ai_analysis_model.dart';
import '../../providers/providers.dart';
import '../../providers/reads_provider.dart';
import '../../widgets/playing_card_widget.dart';

class HandAnalysisScreen extends ConsumerStatefulWidget {
  final PokerHand hand;

  const HandAnalysisScreen({super.key, required this.hand});

  @override
  ConsumerState<HandAnalysisScreen> createState() => _HandAnalysisScreenState();
}

class _HandAnalysisScreenState extends ConsumerState<HandAnalysisScreen> {
  HandCoachingAnalysis? _analysis;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAnalysis());
  }

  Future<void> _runAnalysis({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reads = ref.read(readsProvider).value ?? [];
      final analysis = await ref.read(aiServiceProvider).analyzeHand(
            widget.hand,
            reads: reads,
            forceRefresh: forceRefresh,
          );
      if (mounted) {
        setState(() { _analysis = analysis; _loading = false; });
        // Refresh the quota indicators (no Realtime — manual invalidation).
        ref.invalidate(aiUsageProvider);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _confirmReanalyze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-analyze hand?'),
        content: const Text(
          'This will use AI credits and overwrite the existing analysis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-analyze'),
          ),
        ],
      ),
    );
    if (confirmed == true) _runAnalysis(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hand Coaching'),
        actions: [
          if (_analysis != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-analyze',
              onPressed: _confirmReanalyze,
            ),
        ],
      ),
      body: _loading
          ? _LoadingView()
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _runAnalysis)
              : _CoachingView(hand: widget.hand, analysis: _analysis!),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Your coach is analyzing this hand…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This usually takes 5–10 seconds',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('Analysis failed',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ── Coaching view ─────────────────────────────────────────────────────────────

class _StreetEntry {
  final String name;
  final StreetFeedback feedback;
  final List<String> newCards;

  const _StreetEntry(this.name, this.feedback, this.newCards);
}

class _CoachingView extends StatelessWidget {
  final PokerHand hand;
  final HandCoachingAnalysis analysis;

  const _CoachingView({required this.hand, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final streetCardMap = <Street, List<String>>{};
    for (final s in hand.streets) {
      if (s.communityCards.isNotEmpty) {
        streetCardMap[s.street] = s.communityCards;
      }
    }

    final streets = <_StreetEntry>[
      if (analysis.preflop != null)
        _StreetEntry('Pre-flop', analysis.preflop!, []),
      if (analysis.flop != null)
        _StreetEntry('Flop', analysis.flop!, streetCardMap[Street.flop] ?? []),
      if (analysis.turn != null)
        _StreetEntry('Turn', analysis.turn!, streetCardMap[Street.turn] ?? []),
      if (analysis.river != null)
        _StreetEntry('River', analysis.river!, streetCardMap[Street.river] ?? []),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        _HandHeaderCard(hand: hand, analysis: analysis),
        if (streets.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Street-by-Street Coaching',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final entry in streets) ...[
            _StreetCoachingCard(entry: entry),
            const SizedBox(height: 8),
          ],
        ],
        if (analysis.keyMistake != null && analysis.keyMistake!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _KeyMistakeCard(mistake: analysis.keyMistake!),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Hand header ───────────────────────────────────────────────────────────────

class _HandHeaderCard extends StatelessWidget {
  final PokerHand hand;
  final HandCoachingAnalysis analysis;

  const _HandHeaderCard({required this.hand, required this.analysis});

  Color _verdictColor(BuildContext context) {
    switch (analysis.verdict) {
      case 'highEV':
        return Colors.green;
      case 'leakDetected':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _verdictLabel() {
    switch (analysis.verdict) {
      case 'highEV':
        return 'Well played';
      case 'leakDetected':
        return 'Leak detected';
      default:
        return 'Neutral';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hero = hand.hero;
    final setup = hand.tableSetup;
    final heroPos =
        hero != null ? setup.positionName(hero.seatIndex) : '?';
    final stakes =
        '\$${setup.smallBlind}/\$${setup.bigBlind}'
        '${setup.straddle != null ? '/\$${setup.straddle}' : ''}';
    final vc = _verdictColor(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hero?.holeCards?.length == 2) ...[
                  PlayingCard(
                      card: hero!.holeCards![0], width: 38, height: 54),
                  const SizedBox(width: 4),
                  PlayingCard(
                      card: hero.holeCards![1], width: 38, height: 54),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$heroPos · $stakes · ${setup.numSeats}-max',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        analysis.summary,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: vc.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: vc.withValues(alpha: 0.4)),
              ),
              child: Text(
                _verdictLabel(),
                style: TextStyle(
                  fontSize: 12,
                  color: vc,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Street coaching card ──────────────────────────────────────────────────────

class _StreetCoachingCard extends StatelessWidget {
  final _StreetEntry entry;

  const _StreetCoachingCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final f = entry.feedback;
    final outline = Theme.of(context).colorScheme.outline;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Text(
              entry.name,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (entry.newCards.isNotEmpty) ...[
              const SizedBox(width: 8),
              for (final c in entry.newCards)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: PlayingCard(card: c, width: 20, height: 28),
                ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: f.wasGto
                    ? Colors.blueGrey.withValues(alpha: 0.15)
                    : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                f.wasGto ? 'GTO' : 'Exploit',
                style: TextStyle(
                  fontSize: 10,
                  color: f.wasGto ? Colors.blueGrey : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 10),
                _InfoRow(
                    label: 'You',
                    value: f.decision,
                    color: outline),
                const SizedBox(height: 6),
                _InfoRow(
                    label: 'Optimal',
                    value: f.optimal,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 6),
                _InfoRow(
                    label: 'Why',
                    value: f.rationale,
                    color: outline),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Key mistake card ──────────────────────────────────────────────────────────

class _KeyMistakeCard extends StatelessWidget {
  final String mistake;

  const _KeyMistakeCard({required this.mistake});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .errorContainer
          .withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text('Key Mistake',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              mistake
                  .replaceAll(r'\n', ' ')
                  .replaceAll('\n', ' ')
                  .replaceAll(r'\t', ' '),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoRow(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value
                .replaceAll(r'\n', ' ')
                .replaceAll('\n', ' ')
                .replaceAll(r'\t', ' '),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }
}
