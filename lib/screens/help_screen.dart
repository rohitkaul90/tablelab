import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                0, 8, 0, 8 + MediaQuery.paddingOf(context).bottom),
            children: [
              _SectionHeader('Getting Started', Icons.flag_outlined, primary),
              ..._gettingStarted.map((faq) => _FaqTile(faq)),

              _SectionHeader('Sessions', Icons.receipt_long_outlined, primary),
              ..._sessions.map((faq) => _FaqTile(faq)),

              _SectionHeader('Analytics', Icons.bar_chart_rounded, primary),
              ..._analytics.map((faq) => _FaqTile(faq)),

              _SectionHeader('Hand Replayer', Icons.play_circle_outline_rounded, primary),
              ..._hands.map((faq) => _FaqTile(faq)),

              _SectionHeader('AI Analysis', Icons.auto_awesome_outlined, primary),
              ..._ai.map((faq) => _FaqTile(faq)),

              _SectionHeader('Player Reads', Icons.psychology_outlined, primary),
              ..._reads.map((faq) => _FaqTile(faq)),

              _SectionHeader('Tournament Calendar', Icons.event_outlined, primary),
              ..._calendar.map((faq) => _FaqTile(faq)),

              _SectionHeader('Tools', Icons.calculate_outlined, primary),
              ..._tools.map((faq) => _FaqTile(faq)),

              _SectionHeader('Import & Export', Icons.import_export_rounded, primary),
              ..._importExport.map((faq) => _FaqTile(faq)),

              _SectionHeader('Account & Data', Icons.security_outlined, primary),
              ..._account.map((faq) => _FaqTile(faq)),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FAQ data ─────────────────────────────────────────────────────────────────

const _gettingStarted = [
  _Faq(
    q: 'What is TableLab?',
    a: 'TableLab is a poker tracking and analysis app for serious players. '
        'Log every session you play, review performance trends, record and replay hands for study, '
        'build a personal database of opponent reads, and get AI-powered coaching — '
        'all synced to the cloud across devices.',
  ),
  _Faq(
    q: 'Do I need an account to use the app?',
    a: 'Yes. TableLab uses a secure cloud backend so your data is always backed up and accessible from any device. '
        'You can sign in with Google (one tap) or create a traditional email/password account.',
  ),
  _Faq(
    q: 'How do I navigate the app?',
    a: 'The bottom navigation bar has five tabs: Stats, Sessions, Hands, Reads, and Tools '
        '(Equity Calculator and ICM Deal Calculator). '
        'Tap the menu icon (☰) in the top-left of any screen to open the side drawer. '
        'The drawer contains your profile, Tournament Calendar, Settings, Help, About, and Data & Privacy.',
  ),
  _Faq(
    q: 'Is my data private?',
    a: 'Yes. Every query to the database enforces Row-Level Security — meaning you can only ever read or write '
        'your own data. No other user can see your sessions, hands, or reads.',
  ),
];

const _sessions = [
  _Faq(
    q: 'How do I log a session?',
    a: 'Go to the Sessions tab and tap the + button in the bottom-right. '
        'Select Cash Game or Tournament, fill in the details, and tap Save. '
        'Required fields are marked — everything else is optional but improves your analytics.',
  ),
  _Faq(
    q: 'What\'s the difference between Cash and Tournament logging?',
    a: 'Cash Games track profit/loss as cash-out minus buy-in. '
        'Tournaments track profit/loss as prize won minus buy-in, and display your ROI (return on investment) '
        'as a percentage. The log form adapts based on which type you select, showing only relevant fields.',
  ),
  _Faq(
    q: 'What is Rake and why should I track it?',
    a: 'Rake is the fee the house takes for running the game. '
        'It\'s recorded for informational purposes only — it doesn\'t change your profit, but it '
        'helps you understand the true cost of play at different venues. '
        'You can save rake presets per location so you never have to re-enter the same value.',
  ),
  _Faq(
    q: 'What is Table Quality?',
    a: 'Table Quality is your subjective 1–5 star rating of how good the game was — '
        'factoring in opponent skill level, game dynamics, or how soft the table felt. '
        'Analytics uses this to help you identify which games are most worth playing.',
  ),
  _Faq(
    q: 'What does "Hands/Hour" mean?',
    a: 'Hands per hour is the pace of the game — how many hands were dealt each hour. '
        'Cash game players often track this to compare speed across venues. '
        'A faster game means more decisions per hour, which amplifies both edges and leaks.',
  ),
  _Faq(
    q: 'Can I edit or delete a session?',
    a: 'Yes. In the Sessions tab, tap any session to open its detail view. '
        'Use the pencil icon in the top-right to edit, or the trash icon to delete. '
        'Deleted sessions are removed permanently.',
  ),
  _Faq(
    q: 'What currencies are supported?',
    a: 'CAD, USD, GBP, and EUR. The currency defaults to the same as your last logged session. '
        'When viewing analytics, all amounts are converted to your selected display currency '
        'at approximate exchange rates.',
  ),
];

const _analytics = [
  _Faq(
    q: 'Where do I find Analytics?',
    a: 'Go to the Stats tab and tap the "Analytics" chip at the top. '
        'The Analytics view lives alongside the Overview tab on the same screen.',
  ),
  _Faq(
    q: 'What is the Profit Over Time chart?',
    a: 'This chart tracks your cumulative profit and loss over time. '
        'A line trending upward means you\'re profitable — every session adds (or subtracts) from your running total. '
        'Switch between Cumulative, Weekly, Monthly, and Yearly views using the chips above the chart.',
  ),
  _Faq(
    q: 'How do Analytics filters work?',
    a: 'Tap the filter icon (sliders) in the top-right of the screen when on the Analytics tab. '
        'You can filter by date range, display currency, country, venue type (Live/Online), '
        'and specific location. All charts and insight cards update to reflect the filtered data.',
  ),
  _Faq(
    q: 'What are the Insight Cards?',
    a: 'Insight Cards break down your performance by different dimensions: stakes, buy-in level, '
        'game type, day of week, time of day, session length, table quality, and location. '
        'Each card shows your profit and win rate for that segment so you can see exactly where you perform best.',
  ),
  _Faq(
    q: 'What are Recommendations?',
    a: 'Recommendations uses Welch\'s t-test — a statistical method — to detect meaningful differences '
        'in your performance across conditions. For example, if your live results are significantly '
        'stronger than online, it flags that. Expand the section to see actionable suggestions.',
  ),
  _Faq(
    q: 'What is Hourly Rate?',
    a: 'Hourly rate is your average profit per hour of play, calculated from sessions where you logged '
        'both a start and end time (or a duration). It\'s one of the most useful metrics for '
        'cash game players to compare across stakes and locations.',
  ),
];

const _hands = [
  _Faq(
    q: 'How does the Hand Recorder work?',
    a: 'In the Hands tab, tap the + button. First set up the table: add player names, positions, '
        'and stack sizes. For cash games, select your stakes from the preset list. '
        'For tournament hands, enter the exact small blind and big blind (e.g. 500 / 1,000). '
        'Then step through each street — Pre-flop, Flop, Turn, River — '
        'recording each player\'s action and the community cards dealt.',
  ),
  _Faq(
    q: 'How do I record tournament hands?',
    a: 'When recording a hand, toggle the "Tournament hand" switch in the setup screen. '
        'Instead of a fixed stakes dropdown, you\'ll get two free-form fields for Small Blind and Big Blind — '
        'enter any value from 100/200 up to 5M/10M or beyond. '
        'Thousands formatting is applied automatically as you type.',
  ),
  _Faq(
    q: 'Do I have to record hands in real time?',
    a: 'No. The hand recorder is designed to be used from memory after a session. '
        'Record the key hands while they\'re fresh — what mattered was the decision-making, not the timing.',
  ),
  _Faq(
    q: 'What is the Hand Replayer?',
    a: 'Tap a recorded hand in the Hands list to open the replayer. '
        'It shows a top-down table view with player panels, chip counts, community cards, and action labels. '
        'Use the controls at the bottom to step forward/back through each action, '
        'or press Play to auto-advance. Speed can be adjusted with the speed chips.',
  ),
  _Faq(
    q: 'Can I link a hand to a session?',
    a: 'Yes. In the Hand Replayer, tap "Link to session" to connect a recorded hand to one of your saved sessions. '
        'This is useful if you recorded a hand from memory and want to tie it back to the session it came from.',
  ),
  _Faq(
    q: 'Can I share a hand?',
    a: 'Yes — in the Hand Replayer, tap the share icon in the top-right. '
        'This exports the hand as a formatted text hand history (street by street, pot sizes included) '
        'which you can share via any messaging or chat app.',
  ),
  _Faq(
    q: 'Can I delete a recorded hand?',
    a: 'Yes. In the Hands list, swipe left on any hand to reveal the delete action.',
  ),
];

const _ai = [
  _Faq(
    q: 'What is AI Hand Analysis?',
    a: 'In the Hand Replayer, tap the AI chip to get a full coaching breakdown of a recorded hand. '
        'The analysis covers pre-flop decisions, post-flop play, sizing tells, and specific spots '
        'where you may have deviated from optimal lines — with actionable suggestions.',
  ),
  _Faq(
    q: 'What is AI Session Analysis?',
    a: 'From a session detail view, tap Analyze to get an AI summary of your overall session performance. '
        'The analysis looks at your logged stats, notes, and context to identify patterns, '
        'tilt indicators, and areas of focus for your next session.',
  ),
  _Faq(
    q: 'Is there a limit on AI analysis?',
    a: 'Yes — AI analysis uses a cloud model and has daily usage limits to keep the service fast and fair: '
        '20 hand analyses and 5 session analyses per day. '
        'Results are cached, so re-opening the same analysis doesn\'t count against your limit.',
  ),
  _Faq(
    q: 'How accurate is the AI analysis?',
    a: 'The AI uses a state-of-the-art language model with strong poker fundamentals. '
        'It reasons well about common spots but can occasionally misjudge niche or highly exploitative lines. '
        'Treat it as a study partner, not an oracle — it\'s most useful for identifying patterns and blind spots.',
  ),
];

const _reads = [
  _Faq(
    q: 'What is the Reads tab?',
    a: 'Reads is your private database of opponent notes. '
        'Add any player you\'ve encountered and record tells, tendencies, bet-sizing patterns, '
        'or any observations from your time at the table with them.',
  ),
  _Faq(
    q: 'How do I add a read?',
    a: 'Go to the Reads tab and tap the + button. Enter the player\'s name and your notes. '
        'You can add and edit notes over time as you encounter the player in future sessions.',
  ),
  _Faq(
    q: 'Can I use Reads with the Hand Recorder?',
    a: 'Yes. When recording a hand, player name fields autocomplete from your Reads database. '
        'This lets you build a connected record of hands involving players you\'ve profiled.',
  ),
  _Faq(
    q: 'Can I share a player read?',
    a: 'Yes. Open a read\'s detail view and tap the share icon. '
        'This exports the player name and your notes as plain text to share via any app.',
  ),
];

const _calendar = [
  _Faq(
    q: 'What is the Tournament Calendar?',
    a: 'The Calendar tab shows upcoming live poker tournaments sourced from PokerNews — '
        'major series like WSOP, WPT, EPT, and regional events worldwide. '
        'Each listing shows dates, buy-in, guarantee, venue, and country.',
  ),
  _Faq(
    q: 'How current is the tournament data?',
    a: 'The calendar refreshes automatically every Monday from PokerNews. '
        'Pull down on the Calendar screen to force a refresh at any time.',
  ),
  _Faq(
    q: 'Can I filter by country?',
    a: 'Yes. Tap the country filter chips below the app bar to narrow the list to a specific country. '
        'Tap "Show past" in the top-right to also display tournaments that have already ended.',
  ),
  _Faq(
    q: 'Can I register or buy in through the app?',
    a: 'Not directly — TableLab is a tracking and study tool, not a registration platform. '
        'Each tournament card shows a link to the full PokerNews listing where registration details are available.',
  ),
];

const _tools = [
  _Faq(
    q: 'What is the Equity Calculator?',
    a: 'The Equity Calculator (under Tools in the drawer) lets you calculate hand vs. range equity. '
        'Enter a specific hand and one or more opponent ranges, and it computes each side\'s equity '
        'across all possible run-outs — useful for understanding how ahead or behind you are in a given spot.',
  ),
  _Faq(
    q: 'What is the ICM Deal Calculator?',
    a: 'The ICM Deal Calculator (under Tools in the drawer) helps final table players agree on a fair chip-chop deal. '
        'Enter each player\'s chip count and the remaining prize spots, and it computes two values: '
        'the ICM deal (which accounts for payout structure and risk of elimination) '
        'and a straight chip-chop (chips ÷ total chips × prize pool). '
        'The Diff column shows who gains or loses under each method.',
  ),
  _Faq(
    q: 'What is ICM and why does it differ from chip-chop?',
    a: 'ICM (Independent Chip Model) treats tournament chips differently from cash. '
        'A chip stack worth 30% of the chips doesn\'t guarantee 30% of the remaining prize money, '
        'because the short stack risks busting first and losing all equity in higher places. '
        'ICM accounts for this risk — short stacks receive proportionally more than their chip % suggests, '
        'while big stacks receive less. This makes ICM fairer for short stacks.',
  ),
  _Faq(
    q: 'How many players can the ICM calculator handle?',
    a: 'Up to 9 players and 9 prize places. The algorithm uses memoised recursion (Malmuth-Harville) '
        'and handles any realistic final table configuration in under a second.',
  ),
];

const _importExport = [
  _Faq(
    q: 'How do I export my sessions?',
    a: 'Go to the Sessions tab and tap the Import/Export button in the top-right. '
        'Choose Export, select CSV or Excel format, and the file will be generated and ready to save or share. '
        'CSV works with any spreadsheet app; Excel exports a formatted .xlsx file.',
  ),
  _Faq(
    q: 'How do I import sessions from a spreadsheet?',
    a: 'Tap Import on the Import/Export screen and pick a CSV or Excel file from your device. '
        'TableLab will show a column mapping UI — drag or assign your spreadsheet\'s columns to the '
        'correct session fields. Confirm the mapping and the sessions will be imported.',
  ),
  _Faq(
    q: 'What columns does the CSV export include?',
    a: 'The export includes all session fields: date, game type, stakes, location, buy-in, cash-out, '
        'profit/loss, duration, rake, table quality, hands/hour, notes, currency, and more.',
  ),
];

const _account = [
  _Faq(
    q: 'How do I reset my password?',
    a: 'On the login screen, tap "Forgot password?" below the password field and enter your email. '
        'A reset link will be sent to your inbox.',
  ),
  _Faq(
    q: 'Where is my data stored?',
    a: 'Your data lives in Supabase — a secure, cloud-hosted PostgreSQL database. '
        'Row-Level Security policies are enforced at the database level, '
        'so your data is accessible only to you.',
  ),
  _Faq(
    q: 'Can I use TableLab on multiple devices?',
    a: 'Yes. Sign in with the same account on any device — web, Android, or desktop — '
        'and all your sessions, hands, and reads sync automatically.',
  ),
  _Faq(
    q: 'Can I delete my account?',
    a: 'In-app account deletion is not yet supported. '
        'To request full deletion of your data, contact support.',
  ),
];

// ── Data class ────────────────────────────────────────────────────────────────

class _Faq {
  const _Faq({required this.q, required this.a});
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
      key: PageStorageKey('faq_${faq.q}'),
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
