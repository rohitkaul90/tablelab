import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../equity/gto_frequency_library.dart';
import '../../equity/villain_range.dart';
import '../../models/hand_model.dart';
import '../../models/ai_analysis_model.dart';
import '../../providers/gto_frequency_provider.dart';
import '../../providers/providers.dart';
import '../../providers/reads_provider.dart';
import '../../services/ai_service.dart';
import '../../reads/tag_definitions.dart';
import '../../widgets/ai/analysis_feedback_bar.dart';
import '../../widgets/playing_card_widget.dart';

class HandAnalysisScreen extends ConsumerStatefulWidget {
  final PokerHand hand;

  const HandAnalysisScreen({super.key, required this.hand});

  @override
  ConsumerState<HandAnalysisScreen> createState() => _HandAnalysisScreenState();
}

class _HandAnalysisScreenState extends ConsumerState<HandAnalysisScreen> {
  HandCoachingAnalysis? _analysis;
  HandEquityCheck? _equityCheck;
  bool _loading = true;
  bool _running = false; // re-entry guard so a double-tap can't fire two paid calls
  String? _error;
  String _errorTitle = 'Analysis failed';
  bool _errorCanRetry = true;
  // When the error was a MALFORMED cached response, Retry must force a fresh
  // Claude call (forceRefresh:false would just re-serve the same garbage).
  bool _errorForceRefresh = false;

  // Deterministic seed from the hand id so the equity Monte Carlo (and thus the
  // equity chips) is stable per hand across views, matching the cached coaching's
  // grounding (the coaching is cached server-side; the chips recompute on-device).
  int _equitySeed(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAnalysis());
  }

  Future<void> _runAnalysis({bool forceRefresh = false}) async {
    // Ignore taps while an analysis is already in flight, so a double-tap on
    // Re-analyze / Retry can't fire two live (paid) Claude calls and race.
    if (_running) return;
    _running = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reads = ref.read(readsProvider).value ?? [];

      // Compute the deterministic cross-check first so it can both feed the
      // equity chips AND ground the AI prompt (its numbers ride in as [FACT]
      // lines the coaching can't contradict). Best-effort: a hand the engine
      // can't model just yields no chips and no equity facts.
      HandEquityCheck? equity;
      try {
        equity = await computeHandEquityCheck(widget.hand, reads: reads,
            seed: _equitySeed(widget.hand.id));
      } catch (_) {
        equity = null;
      }
      if (!mounted) return;
      setState(() => _equityCheck = equity);

      // The offline GTO frequency library grounds the [HEURISTIC — GTO frequency]
      // line; best-effort (a load failure just drops that one FACT).
      GtoFrequencyLibrary? gtoLib;
      try {
        gtoLib = await ref.read(gtoFrequencyLibraryProvider.future);
      } catch (_) {
        gtoLib = null;
      }
      if (!mounted) return;

      final analysis = await ref.read(aiServiceProvider).analyzeHand(
            widget.hand,
            reads: reads,
            forceRefresh: forceRefresh,
            equityFacts: equity != null
                ? equityCheckFacts(equity, library: gtoLib)
                : const [],
          );
      if (mounted) {
        if (analysis.isEmpty) {
          // Claude malformed the tool call (e.g. streets as strings) — nothing
          // usable parsed. Surface a re-analyze prompt rather than a blank view.
          setState(() {
            _loading = false;
            _error = 'The AI returned an unreadable response. Please re-analyze.';
            _errorTitle = 'Analysis failed';
            _errorCanRetry = true;
            _errorForceRefresh = true;
          });
        } else {
          setState(() { _analysis = analysis; _loading = false; });
          // Refresh the quota indicators (no Realtime — manual invalidation).
          ref.invalidate(aiUsageProvider);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorForceRefresh = false;
        if (e is AiException) {
          _error = e.message;
          _errorTitle = e.isRateLimited
              ? 'Daily limit reached'
              : e.isAtCapacity
                  ? 'Temporarily at capacity'
                  : 'Analysis failed';
          // Retrying a daily limit won't help until tomorrow.
          _errorCanRetry = !e.isRateLimited;
        } else {
          _error = 'Something went wrong. Please try again.';
          _errorTitle = 'Analysis failed';
          _errorCanRetry = true;
        }
      });
    } finally {
      _running = false;
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
              // Disabled while a run is in flight (belt-and-suspenders with the
              // _running guard) so it can't kick off a second paid call.
              onPressed: _loading ? null : _confirmReanalyze,
            ),
        ],
      ),
      body: _loading
          ? _LoadingView()
          : _error != null
              ? _ErrorView(
                  title: _errorTitle,
                  error: _error!,
                  onRetry: _errorCanRetry
                      ? () => _runAnalysis(forceRefresh: _errorForceRefresh)
                      : null,
                )
              : _CoachingView(
                  hand: widget.hand,
                  analysis: _analysis!,
                  equityCheck: _equityCheck,
                  onRate: (rating) => ref
                      .read(aiServiceProvider)
                      .rateHandAnalysis(widget.hand.id, rating),
                ),
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
  final String title;
  final String error;
  final VoidCallback? onRetry;

  const _ErrorView({required this.title, required this.error, this.onRetry});

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
            Text(title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Coaching view ─────────────────────────────────────────────────────────────

class _StreetEntry {
  final Street street;
  final String name;
  final StreetFeedback feedback;
  final List<String> newCards;

  const _StreetEntry(this.street, this.name, this.feedback, this.newCards);
}

class _CoachingView extends StatelessWidget {
  final PokerHand hand;
  final HandCoachingAnalysis analysis;
  final HandEquityCheck? equityCheck;
  final Future<void> Function(int rating)? onRate;

  const _CoachingView({
    required this.hand,
    required this.analysis,
    this.equityCheck,
    this.onRate,
  });

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
        _StreetEntry(Street.preflop, 'Pre-flop', analysis.preflop!, []),
      if (analysis.flop != null)
        _StreetEntry(Street.flop, 'Flop', analysis.flop!,
            streetCardMap[Street.flop] ?? []),
      if (analysis.turn != null)
        _StreetEntry(Street.turn, 'Turn', analysis.turn!,
            streetCardMap[Street.turn] ?? []),
      if (analysis.river != null)
        _StreetEntry(Street.river, 'River', analysis.river!,
            streetCardMap[Street.river] ?? []),
    ];

    final equityByStreet = <Street, double>{
      for (final s in equityCheck?.streets ?? const <StreetEquityCheck>[])
        s.street: s.heroEquity,
    };

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
            _StreetCoachingCard(
              entry: entry,
              equity: equityByStreet[entry.street],
              onEquityTap: equityCheck != null
                  ? () => _showEquityAssumptions(context, equityCheck!)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (analysis.keyMistake != null && analysis.keyMistake!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _KeyMistakeCard(mistake: analysis.keyMistake!),
        ],
        if (analysis.facts.isNotEmpty) ...[
          const SizedBox(height: 8),
          _FactsCard(facts: analysis.facts),
        ],
        if (onRate != null) ...[
          const SizedBox(height: 8),
          AnalysisFeedbackBar(onRate: onRate!),
        ],
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'AI coaching can be wrong — verify big decisions.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
        const SizedBox(height: 24),
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

  /// Hero's deterministic equity on this street (0–1), when the on-device
  /// cross-check could model the hand.
  final double? equity;
  final VoidCallback? onEquityTap;

  const _StreetCoachingCard({
    required this.entry,
    this.equity,
    this.onEquityTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = entry.feedback;
    final outline = Theme.of(context).colorScheme.outline;

    return Card(
      child: ExpansionTile(
        // Unique key so this tile's expansion bool is stored under its own
        // PageStorage slot — keyless ExpansionTiles all write to the shared
        // default slot, which a later scrollable then reads as a scroll offset
        // and crashes ("bool is not a subtype of double?").
        key: PageStorageKey('street_${entry.name}'),
        initiallyExpanded: true,
        // Badges live on their own row below the title (a Wrap) rather than in
        // `trailing` — in trailing they overlapped the community cards in the
        // title on flop/turn/river. The Wrap re-flows instead of colliding.
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
              const SizedBox(width: 12),
              for (final c in entry.newCards)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: PlayingCard(card: c, width: 36, height: 50),
                ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (equity != null)
                _EquityChip(equity: equity!, onTap: onEquityTap),
              if (f.confidence != null)
                _ConfidenceBadge(confidence: f.confidence!),
              _GtoChip(wasGto: f.wasGto),
            ],
          ),
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
                if (f.alternative != null && f.alternative!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoRow(
                      label: 'Also',
                      value: f.alternative!,
                      color: outline),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GtoChip extends StatelessWidget {
  final bool wasGto;

  const _GtoChip({required this.wasGto});

  @override
  Widget build(BuildContext context) {
    final color = wasGto ? Colors.blueGrey : Colors.orange;
    return Tooltip(
      message: wasGto
          ? 'GTO: hero\'s play matches the game-theory-optimal baseline'
          : 'Exploit: the better play here deviates from GTO to exploit this opponent',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          wasGto ? 'GTO' : 'Exploit',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final String confidence; // 'high' | 'medium' | 'low'

  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final color = switch (confidence) {
      'high' => Colors.green,
      'low' => Colors.orange,
      _ => Theme.of(context).colorScheme.outline,
    };
    final label = confidence.isEmpty
        ? confidence
        : confidence[0].toUpperCase() + confidence.substring(1);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showConfidenceInfo(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              'Confidence: $label',
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showConfidenceInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('AI confidence'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text("How sure the AI is about this street's recommendation:"),
          SizedBox(height: 14),
          _ConfidenceLegendRow(
            level: 'High',
            color: Colors.green,
            meaning: 'Standard spot with a well-established answer.',
          ),
          SizedBox(height: 10),
          _ConfidenceLegendRow(
            level: 'Medium',
            color: Colors.grey,
            meaning: 'Depends on reads or assumptions about the opponent.',
          ),
          SizedBox(height: 10),
          _ConfidenceLegendRow(
            level: 'Low',
            color: Colors.orange,
            meaning: 'A genuinely close spot, or key information is missing.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _ConfidenceLegendRow extends StatelessWidget {
  final String level;
  final Color color;
  final String meaning;

  const _ConfidenceLegendRow({
    required this.level,
    required this.color,
    required this.meaning,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            level,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(meaning,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
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

// ── Facts card ────────────────────────────────────────────────────────────────
// The deterministic [FACT —] lines the Edge Function injected into the prompt
// — collapsed by default; "what the AI was told", verbatim.

class _FactsCard extends StatelessWidget {
  final List<String> facts;

  const _FactsCard({required this.facts});

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Card(
      child: ExpansionTile(
        // Unique PageStorage slot — see _StreetCoachingCard for why a keyless
        // ExpansionTile crashes a later scrollable.
        key: const PageStorageKey('ai_facts'),
        leading: Icon(Icons.fact_check_outlined,
            size: 20, color: Theme.of(context).colorScheme.primary),
        title: Text('What the AI was told',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Pre-computed card facts injected as ground truth',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: outline,
              ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final fact in facts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      fact,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Equity cross-check ────────────────────────────────────────────────────────

class _EquityChip extends StatelessWidget {
  final double equity;
  final VoidCallback? onTap;

  const _EquityChip({required this.equity, this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message:
          'Hero equity vs the modeled villain range — computed on-device, '
          'not by the AI. Tap for assumptions.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 11, color: primary),
              const SizedBox(width: 2),
              Text(
                'EQ ${(equity * 100).round()}%',
                style: TextStyle(
                  fontSize: 10,
                  color: primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showEquityAssumptions(BuildContext context, HandEquityCheck check) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final outline = theme.colorScheme.outline;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Text('Equity cross-check', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Computed on-device by TableLab\'s Monte Carlo engine '
              '(${check.streets.firstOrNull?.iterations ?? 10000} trials per '
              'street) — independent of the AI. Each opponent gets a GTO '
              'preset range from their preflop action, adjusted for your '
              'reads, then narrowed street by street by what they did.',
              style: theme.textTheme.bodySmall?.copyWith(color: outline),
            ),
            if (check.basedOnSynthesizedAction) ...[
              const SizedBox(height: 8),
              Text(
                'Quick Hand entry: action around the recorded decision is '
                'synthesized scaffolding, so these ranges are approximate.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('HERO EQUITY BY STREET',
                style: theme.textTheme.labelSmall?.copyWith(color: outline)),
            const SizedBox(height: 6),
            for (final s in check.streets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(s.street.label,
                          style: theme.textTheme.bodySmall),
                    ),
                    Text(
                      '${(s.heroEquity * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.boardSoFar.isEmpty
                            ? 'vs ${s.villainCount} '
                                'opponent${s.villainCount == 1 ? '' : 's'}'
                            : s.boardSoFar.join(' '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            for (final v in check.villains) ...[
              const SizedBox(height: 16),
              Text(
                'ASSUMED RANGE — ${v.name.toUpperCase()} (${v.position})',
                style: theme.textTheme.labelSmall?.copyWith(color: outline),
              ),
              if (v.appliedTags.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Reads: ${v.appliedTags.map(tagDisplayName).join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 4),
              for (final line in v.rangeTrail)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('•  $line', style: theme.textTheme.bodySmall),
                ),
            ],
          ],
        ),
      );
    },
  );
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
