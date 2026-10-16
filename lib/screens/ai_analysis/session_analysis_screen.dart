import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/session_model.dart';
import '../../models/ai_analysis_model.dart';
import '../../providers/providers.dart';
import '../../providers/reads_provider.dart';
import '../../services/ai_service.dart';
import '../../l10n/l10n.dart';
import '../../widgets/ai/ai_disclaimer_footer.dart';
import '../../widgets/ai/analysis_feedback_bar.dart';

class SessionAnalysisScreen extends ConsumerStatefulWidget {
  final SessionModel session;

  const SessionAnalysisScreen({super.key, required this.session});

  @override
  ConsumerState<SessionAnalysisScreen> createState() =>
      _SessionAnalysisScreenState();
}

class _SessionAnalysisScreenState extends ConsumerState<SessionAnalysisScreen> {
  SessionAnalysis? _analysis;
  bool _loading = true;
  bool _running = false; // re-entry guard so a double-tap can't fire two paid calls
  String? _error;
  String _errorTitle = '';
  bool _errorCanRetry = true;

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
    // Captured before the first await (runs post-frame, so context is live).
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reads = ref.read(readsProvider).value ?? [];
      final allHands = await ref.read(handServiceProvider).fetchHands();
      if (!mounted) return;
      final sessionHands = allHands
          .where((h) => h.sessionId == widget.session.id)
          .toList();

      final analysis = await ref.read(aiServiceProvider).analyzeSession(
            widget.session,
            hands: sessionHands,
            reads: reads,
            forceRefresh: forceRefresh,
          );
      if (mounted) {
        setState(() { _analysis = analysis; _loading = false; });
        // Refresh the quota indicators (no Realtime — manual invalidation).
        ref.invalidate(aiUsageProvider);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final text = aiErrorText(l10n, e);
        _error = text.body;
        _errorTitle = text.title;
        // Retrying a daily limit won't help until tomorrow.
        _errorCanRetry = !(e is AiException && e.isRateLimited);
      });
    } finally {
      _running = false;
    }
  }

  Future<void> _confirmReanalyze() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiSessionReanalyzeTitle),
        content: Text(l10n.aiReanalyzeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.aiReanalyze),
          ),
        ],
      ),
    );
    // The screen can be popped while the dialog is open; _runAnalysis reads
    // context.l10n, which throws on an unmounted element.
    if (confirmed == true && mounted) _runAnalysis(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.aiSessionTitle),
        actions: [
          if (_analysis != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.l10n.aiReanalyze,
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
                  onRetry: _errorCanRetry ? _runAnalysis : null,
                )
              : _AnalysisView(
                  analysis: _analysis!,
                  onRate: (rating) => ref
                      .read(aiServiceProvider)
                      .rateSessionAnalysis(widget.session.id, rating),
                ),
    );
  }
}

// ── Loading ──────────────────────────────────────────────────────────────────

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
            context.l10n.aiSessionLoading,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.aiSessionLoadingHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Error ────────────────────────────────────────────────────────────────────

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
              FilledButton(
                  onPressed: onRetry, child: Text(context.l10n.commonRetry)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Analysis ─────────────────────────────────────────────────────────────────

class _AnalysisView extends StatelessWidget {
  final SessionAnalysis analysis;
  final Future<void> Function(int rating)? onRate;

  const _AnalysisView({required this.analysis, this.onRate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        _NarrativeCard(narrative: analysis.narrative),
        if (analysis.leaksIdentified.isNotEmpty) ...[
          const SizedBox(height: 16),
          _LeaksSection(leaks: analysis.leaksIdentified),
        ],
        if (analysis.actionableTip.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TipCard(tip: analysis.actionableTip),
        ],
        if (onRate != null) ...[
          const SizedBox(height: 8),
          AnalysisFeedbackBar(onRate: onRate!),
        ],
        const SizedBox(height: 8),
        const AiDisclaimerFooter(),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Narrative card ───────────────────────────────────────────────────────────

class _NarrativeCard extends StatelessWidget {
  final String narrative;

  const _NarrativeCard({required this.narrative});

  @override
  Widget build(BuildContext context) {
    // Normalise any stray escape sequences the model may have emitted literally,
    // then split on paragraph breaks (two or more newlines).
    final cleaned = narrative
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', ' ');
    final paragraphs = cleaned
        .split(RegExp(r'\n\n+'))
        .map((p) => p.trim().replaceAll('\n', ' '))
        .where((p) => p.isNotEmpty)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(context.l10n.aiSessionDebrief,
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < paragraphs.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Text(
                paragraphs[i],
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Key themes ───────────────────────────────────────────────────────────────

// ── Leaks ────────────────────────────────────────────────────────────────────

class _LeaksSection extends StatelessWidget {
  final List<String> leaks;

  const _LeaksSection({required this.leaks});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
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
                Text(context.l10n.aiSessionLeaks,
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            for (final leak in leaks) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(leak,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                            )),
                  ),
                ],
              ),
              if (leak != leaks.last) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Actionable tip ───────────────────────────────────────────────────────────

class _TipCard extends StatelessWidget {
  final String tip;

  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline,
                color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.aiSessionFocusNext,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          )),
                  const SizedBox(height: 4),
                  Text(tip,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            height: 1.4,
                          )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

