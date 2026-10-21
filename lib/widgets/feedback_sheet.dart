import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../services/feedback_service.dart';

/// Opens the in-app feedback sheet. [initialCategory] preselects a chip and
/// [prefillMessage] seeds the text field (used by the AI screens' "tell us
/// more" entry point). Returns true if feedback was submitted, false if the
/// user closed it with the X, null if it was swiped away / barrier-dismissed.
Future<bool?> showFeedbackSheet(
  BuildContext context, {
  String? initialCategory,
  String? prefillMessage,
}) {
  AnalyticsService.feedbackOpened(category: initialCategory);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // A tall sheet (large Dynamic Type + keyboard) must not slide under the
    // iPhone status bar.
    useSafeArea: true,
    builder: (_) => _FeedbackSheet(
      initialCategory: initialCategory,
      prefillMessage: prefillMessage,
    ),
  );
}

// Category ids are the wire format (feedback.category); labels are localized.
const _categoryIcons = <String, IconData>{
  'bug': Icons.bug_report_outlined,
  'idea': Icons.lightbulb_outline,
  'praise': Icons.favorite_outline,
  'other': Icons.chat_bubble_outline,
};

String _categoryLabel(AppLocalizations l10n, String id) => switch (id) {
  'bug' => l10n.feedbackCategoryBug,
  'idea' => l10n.feedbackCategoryIdea,
  'praise' => l10n.feedbackCategoryPraise,
  _ => l10n.feedbackCategoryOther,
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
    _category = _categoryIcons.containsKey(widget.initialCategory)
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
    final l10n = context.l10n;
    if (message.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.feedbackWriteSomething)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(feedbackServiceProvider)
          .submit(
            category: _category,
            message: message,
            rating: _rating,
            shareEmail: _shareEmail,
          );
      AnalyticsService.feedbackSubmitted(category: _category);
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.feedbackThanks)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(l10n, e))));
    }
  }

  String _friendlyError(AppLocalizations l10n, Object e) {
    if (e is FeedbackException) {
      if (e.status == 429) {
        return l10n.feedbackLimitReached;
      }
      // The server's 4xx text is English-only, so show it verbatim only in
      // English; other locales get the localized generic failure.
      if (e.status < 500 &&
          (e.message?.isNotEmpty ?? false) &&
          l10n.localeName.startsWith('en')) {
        return e.message!;
      }
      return l10n.feedbackSendFailed;
    }
    // Network / transport error — couldn't reach the server.
    return l10n.feedbackSendFailedNetwork;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    return Padding(
      // Lift above the keyboard when the text field is focused.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pinned header with an explicit close button, OUTSIDE the scroll
          // body so it can't scroll off the top on a large-text phone. With
          // the keyboard up (autofocus) the sheet fills the screen, so there
          // is no scrim to tap and the scroll body eats drags. Android's back
          // gesture still pops the sheet, but iOS has no system back for a
          // modal, so without this the only way out was killing the app
          // (iPhone QA, 2026-10-20). Deliberately NOT disabled while saving:
          // a stalled submit must never trap the user again (the in-flight
          // future already guards with `if (!mounted) return`).
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.feedbackTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.commonClose,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.feedbackSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in _categoryIcons.entries)
                        ChoiceChip(
                          label: Text(_categoryLabel(l10n, entry.key)),
                          avatar: Icon(entry.value, size: 18),
                          selected: _category == entry.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _category = entry.key),
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
                    decoration: InputDecoration(
                      hintText: l10n.feedbackHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.feedbackRate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            (_rating ?? 0) >= i
                                ? Icons.star
                                : Icons.star_border,
                            color: (_rating ?? 0) >= i
                                ? Colors.amber
                                : cs.outline,
                          ),
                          onPressed: _saving
                              ? null
                              // Tapping the current rating clears it.
                              : () => setState(
                                  () => _rating = _rating == i ? null : i,
                                ),
                        ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: _shareEmail,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _shareEmail = v ?? false),
                    title: Text(l10n.feedbackOkToEmail),
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
                          : Text(l10n.feedbackSend),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => launchUrl(
                              Uri(
                                scheme: 'mailto',
                                path: 'feedback@tablelab.app',
                                queryParameters: {
                                  'subject': 'TableLab Feedback',
                                },
                              ),
                            ),
                      child: Text(l10n.feedbackEmailInstead),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
