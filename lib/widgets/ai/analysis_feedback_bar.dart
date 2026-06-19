import 'package:flutter/material.dart';
import '../feedback_sheet.dart';

/// Thumbs up/down row shown under an AI analysis. Persists via [onRate]
/// (1 = up, -1 = down) with a saving guard against double-taps; the rating
/// can be changed but not cleared. Feedback is best-effort — failures revert
/// the selection silently.
///
/// A "Tell us more" link opens the full feedback sheet so users can describe
/// what the AI got wrong/right — richer signal than a thumb.
class AnalysisFeedbackBar extends StatefulWidget {
  final Future<void> Function(int rating) onRate;

  const AnalysisFeedbackBar({super.key, required this.onRate});

  @override
  State<AnalysisFeedbackBar> createState() => _AnalysisFeedbackBarState();
}

class _AnalysisFeedbackBarState extends State<AnalysisFeedbackBar> {
  int? _rating;
  bool _saving = false;

  Future<void> _rate(int rating) async {
    if (_saving || _rating == rating) return;
    final previous = _rating;
    setState(() {
      _saving = true;
      _rating = rating;
    });
    try {
      await widget.onRate(rating);
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _rating = previous;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _rating == null ? 'Was this analysis helpful?' : 'Thanks for the feedback!',
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: outline),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            _rating == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
            size: 18,
            color: _rating == 1 ? primary : outline,
          ),
          tooltip: 'Helpful',
          onPressed: () => _rate(1),
        ),
        IconButton(
          icon: Icon(
            _rating == -1 ? Icons.thumb_down : Icons.thumb_down_outlined,
            size: 18,
            color: _rating == -1 ? primary : outline,
          ),
          tooltip: 'Not helpful',
          onPressed: () => _rate(-1),
        ),
        TextButton(
          onPressed: () => showFeedbackSheet(
            context,
            initialCategory: 'other',
            prefillMessage: 'About the AI coaching: ',
          ),
          child: const Text('Tell us more'),
        ),
      ],
    );
  }
}
