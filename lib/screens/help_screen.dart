import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final sections = _sections(l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                0, 8, 0, 8 + MediaQuery.paddingOf(context).bottom),
            children: [
              for (final s in sections) ...[
                _SectionHeader(s.title, s.icon, primary),
                ...s.faqs.map((faq) => _FaqTile(faq)),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FAQ data ─────────────────────────────────────────────────────────────────
// Copy lives in lib/l10n/app_*.arb (faq<Section><N>Q/A). Each FAQ carries a
// STABLE id used for its PageStorageKey — never derive that key from the
// (translated) question text.

List<_Section> _sections(AppLocalizations l10n) => [
    _Section(l10n.helpSectionGettingStarted, Icons.flag_outlined, [
        _Faq('faq_getting_started_1', l10n.faqGettingStarted1Q, l10n.faqGettingStarted1A),
        _Faq('faq_getting_started_2', l10n.faqGettingStarted2Q, l10n.faqGettingStarted2A),
        _Faq('faq_getting_started_3', l10n.faqGettingStarted3Q, l10n.faqGettingStarted3A),
        _Faq('faq_getting_started_4', l10n.faqGettingStarted4Q, l10n.faqGettingStarted4A),
      ]),
    _Section(l10n.helpSectionSessions, Icons.receipt_long_outlined, [
        _Faq('faq_sessions_1', l10n.faqSessions1Q, l10n.faqSessions1A),
        _Faq('faq_sessions_2', l10n.faqSessions2Q, l10n.faqSessions2A),
        _Faq('faq_sessions_3', l10n.faqSessions3Q, l10n.faqSessions3A),
        _Faq('faq_sessions_4', l10n.faqSessions4Q, l10n.faqSessions4A),
        _Faq('faq_sessions_5', l10n.faqSessions5Q, l10n.faqSessions5A),
        _Faq('faq_sessions_6', l10n.faqSessions6Q, l10n.faqSessions6A),
        _Faq('faq_sessions_7', l10n.faqSessions7Q, l10n.faqSessions7A),
      ]),
    _Section(l10n.helpSectionAnalytics, Icons.bar_chart_rounded, [
        _Faq('faq_analytics_1', l10n.faqAnalytics1Q, l10n.faqAnalytics1A),
        _Faq('faq_analytics_2', l10n.faqAnalytics2Q, l10n.faqAnalytics2A),
        _Faq('faq_analytics_3', l10n.faqAnalytics3Q, l10n.faqAnalytics3A),
        _Faq('faq_analytics_4', l10n.faqAnalytics4Q, l10n.faqAnalytics4A),
        _Faq('faq_analytics_5', l10n.faqAnalytics5Q, l10n.faqAnalytics5A),
        _Faq('faq_analytics_6', l10n.faqAnalytics6Q, l10n.faqAnalytics6A),
      ]),
    _Section(l10n.helpSectionHands, Icons.play_circle_outline_rounded, [
        _Faq('faq_hands_1', l10n.faqHands1Q, l10n.faqHands1A),
        _Faq('faq_hands_2', l10n.faqHands2Q, l10n.faqHands2A),
        _Faq('faq_hands_3', l10n.faqHands3Q, l10n.faqHands3A),
        _Faq('faq_hands_4', l10n.faqHands4Q, l10n.faqHands4A),
        _Faq('faq_hands_5', l10n.faqHands5Q, l10n.faqHands5A),
        _Faq('faq_hands_6', l10n.faqHands6Q, l10n.faqHands6A),
        _Faq('faq_hands_7', l10n.faqHands7Q, l10n.faqHands7A),
      ]),
    _Section(l10n.helpSectionAi, Icons.auto_awesome_outlined, [
        _Faq('faq_ai_1', l10n.faqAi1Q, l10n.faqAi1A),
        _Faq('faq_ai_2', l10n.faqAi2Q, l10n.faqAi2A),
        _Faq('faq_ai_3', l10n.faqAi3Q, l10n.faqAi3A),
        _Faq('faq_ai_4', l10n.faqAi4Q, l10n.faqAi4A),
      ]),
    _Section(l10n.helpSectionReads, Icons.psychology_outlined, [
        _Faq('faq_reads_1', l10n.faqReads1Q, l10n.faqReads1A),
        _Faq('faq_reads_2', l10n.faqReads2Q, l10n.faqReads2A),
        _Faq('faq_reads_3', l10n.faqReads3Q, l10n.faqReads3A),
        _Faq('faq_reads_4', l10n.faqReads4Q, l10n.faqReads4A),
      ]),
    _Section(l10n.helpSectionCalendar, Icons.event_outlined, [
        _Faq('faq_calendar_1', l10n.faqCalendar1Q, l10n.faqCalendar1A),
        _Faq('faq_calendar_2', l10n.faqCalendar2Q, l10n.faqCalendar2A),
        _Faq('faq_calendar_3', l10n.faqCalendar3Q, l10n.faqCalendar3A),
        _Faq('faq_calendar_4', l10n.faqCalendar4Q, l10n.faqCalendar4A),
      ]),
    _Section(l10n.helpSectionTools, Icons.calculate_outlined, [
        _Faq('faq_tools_1', l10n.faqTools1Q, l10n.faqTools1A),
        _Faq('faq_tools_2', l10n.faqTools2Q, l10n.faqTools2A),
        _Faq('faq_tools_3', l10n.faqTools3Q, l10n.faqTools3A),
        _Faq('faq_tools_4', l10n.faqTools4Q, l10n.faqTools4A),
      ]),
    _Section(l10n.helpSectionImportExport, Icons.import_export_rounded, [
        _Faq('faq_import_export_1', l10n.faqImportExport1Q, l10n.faqImportExport1A),
        _Faq('faq_import_export_2', l10n.faqImportExport2Q, l10n.faqImportExport2A),
        _Faq('faq_import_export_3', l10n.faqImportExport3Q, l10n.faqImportExport3A),
      ]),
    _Section(l10n.helpSectionAccount, Icons.security_outlined, [
        _Faq('faq_account_1', l10n.faqAccount1Q, l10n.faqAccount1A),
        _Faq('faq_account_2', l10n.faqAccount2Q, l10n.faqAccount2A),
        _Faq('faq_account_3', l10n.faqAccount3Q, l10n.faqAccount3A),
        _Faq('faq_account_4', l10n.faqAccount4Q, l10n.faqAccount4A),
      ]),
    ];

// ── Data classes ──────────────────────────────────────────────────────────────

class _Section {
  const _Section(this.title, this.icon, this.faqs);
  final String title;
  final IconData icon;
  final List<_Faq> faqs;
}

class _Faq {
  const _Faq(this.id, this.q, this.a);
  final String id;
  final String q;
  final String a;
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile(this.faq);
  final _Faq faq;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      // Unique PageStorage slot per FAQ — keyless ExpansionTiles share the
      // default slot and store a bool there, which a later scrollable reads as
      // a scroll offset and crashes ("bool is not a subtype of double?").
      key: PageStorageKey(faq.id),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        faq.q,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          faq.a,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(200),
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
