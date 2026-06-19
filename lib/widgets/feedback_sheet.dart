import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../services/feedback_service.dart';

/// Opens the in-app feedback sheet. [initialCategory] preselects a chip and
/// [prefillMessage] seeds the text field (used by the AI screens' "tell us
/// more" entry point). Returns true if feedback was submitted.
Future<bool?> showFeedbackSheet(
  BuildContext context, {
  String? initialCategory,
  String? prefillMessage,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FeedbackSheet(
      initialCategory: initialCategory,
      prefillMessage: prefillMessage,
    ),
  );
}

const _categories = <String, ({String label, IconData icon})>{
  'bug': (label: 'Bug', icon: Icons.bug_report_outlined),
  'idea': (label: 'Idea', icon: Icons.lightbulb_outline),
  'praise': (label: 'Praise', icon: Icons.favorite_outline),
  'other': (label: 'Other', icon: Icons.chat_bubble_outline),
};

class _FeedbackSheet extends ConsumerStatefulWidget {
  final String? initialCategory;
  final String? prefillMessage;

  const _FeedbackSheet({this.initialCategory, this.prefillMessage});

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  late String _category;
  late final TextEditingController _controller;
  int? _rating;
  bool _shareEmail = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category = _categories.containsKey(widget.initialCategory)
        ? widget.initialCategory!
        : 'bug';
    _controller = TextEditingController(text: widget.prefillMessage ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    // Captured before any pop so the success snackbar lands on the app's
    // ScaffoldMessenger, not this sheet's (defunct) context.
    final messenger = ScaffoldMessenger.of(context);
    if (message.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please write a little something first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(feedbackServiceProvider).submit(
            category: _category,
            message: message,
            rating: _rating,
            shareEmail: _shareEmail,
          );
      AnalyticsService.feedbackSubmitted(category: _category);
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks for the feedback! 🙏')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  String _friendlyError(Object e) {
    if (e is FeedbackException) {
      if (e.status == 429) {
        return 'Daily feedback limit reached — try again tomorrow.';
      }
      // 4xx validation errors carry a useful server message; show it verbatim.
      if (e.status < 500 && (e.message?.isNotEmpty ?? false)) {
        return e.message!;
      }
      return "Couldn't send feedback. Please try again.";
    }
    // Network / transport error — couldn't reach the server.
    return "Couldn't send feedback. Check your connection and try again.";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      // Lift above the keyboard when the text field is focused.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send feedback', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Bugs, ideas, suggestions — it all helps shape TableLab.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _categories.entries)
                  ChoiceChip(
                    label: Text(entry.value.label),
                    avatar: Icon(entry.value.icon, size: 18),
                    selected: _category == entry.key,
                    onSelected:
                        _saving ? null : (_) => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_saving,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What happened, or what would make TableLab better?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Rate your experience (optional)',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      (_rating ?? 0) >= i ? Icons.star : Icons.star_border,
                      color: (_rating ?? 0) >= i ? Colors.amber : cs.outline,
                    ),
                    onPressed: _saving
                        ? null
                        // Tapping the current rating clears it.
                        : () => setState(() => _rating = _rating == i ? null : i),
                  ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _shareEmail,
              onChanged:
                  _saving ? null : (v) => setState(() => _shareEmail = v ?? false),
              title: const Text("It's OK to email me about this"),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () => launchUrl(Uri(
                          scheme: 'mailto',
                          path: 'feedback@tablelab.app',
                          queryParameters: {'subject': 'TableLab Feedback'},
                        )),
                child: const Text('Email support instead'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
