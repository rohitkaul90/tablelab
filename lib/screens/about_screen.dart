import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('About TableLab')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, 32, 24, 48 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/icon/app_icon.png', width: 88, height: 88),
                const SizedBox(height: 14),
                Text(
                  'TableLab',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your edge, quantified.',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 32),
                _Prose(
                  "Most players keep results in their head.\n"
                  "The best players keep them in a database.",
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _Prose(
                  "Poker rewards pattern recognition — and TableLab is built to surface yours. "
                  "Maybe your best game is live \$2/\$5 on Saturday nights. Maybe you leak chips "
                  "in every online session past midnight. Maybe you haven't noticed yet. "
                  "TableLab notices.",
                ),
                const SizedBox(height: 28),
                _FeatureTile(
                  icon: Icons.receipt_long_outlined,
                  color: Colors.teal,
                  title: 'Session Tracker',
                  body: 'Log every cash game and tournament — buy-ins, rake, duration, location, '
                      'table quality, and more. Your history, always at hand, never in a spreadsheet '
                      'named "poker stuff v3 FINAL.xlsx".',
                ),
                _FeatureTile(
                  icon: Icons.bar_chart_rounded,
                  color: Colors.indigo,
                  title: 'Deep Analytics',
                  body: 'Profit over time, win rates by stakes, location, game type, day of week, '
                      'and time of day. Statistical recommendations that flag where you\'re actually '
                      'making money — not where you think you are.',
                ),
                _FeatureTile(
                  icon: Icons.play_circle_outline_rounded,
                  color: Colors.orange,
                  title: 'Hand Replayer',
                  body: 'Record hands from memory and replay them frame-by-frame on a full table view. '
                      'Cash and tournament hands both supported — enter any blind level, from 100/200 '
                      'to 5M/10M. Study, share, and plug the leaks.',
                ),
                _FeatureTile(
                  icon: Icons.auto_awesome_outlined,
                  color: Colors.amber,
                  title: 'AI Coaching',
                  body: 'Get a coaching breakdown of any recorded hand or session. '
                      'The AI reviews your lines, flags sizing mistakes, and gives you something '
                      'to think about before your next session. Like a coach, but available at 2am.',
                ),
                _FeatureTile(
                  icon: Icons.psychology_outlined,
                  color: Colors.purple,
                  title: 'Player Reads',
                  body: 'Your private database of tells, tendencies, and opponent notes. '
                      'The felt has a memory — now so do you. Names autocomplete in the hand recorder '
                      'so your reads stay connected to the hands they came from.',
                ),
                _FeatureTile(
                  icon: Icons.event_outlined,
                  color: Colors.cyan,
                  title: 'Tournament Calendar',
                  body: 'Upcoming live tournaments worldwide, updated weekly from PokerNews. '
                      'WSOP, WPT, EPT, and regional series — filter by country and never miss '
                      'an event worth playing.',
                ),
                _FeatureTile(
                  icon: Icons.calculate_outlined,
                  color: Colors.green,
                  title: 'ICM Deal Calculator',
                  body: 'When the final table bubbles down to a deal, know your number. '
                      'The ICM calculator uses the Malmuth-Harville model to compute fair deals '
                      'based on chip counts and remaining prizes — up to 9 players, instantly.',
                ),
                _FeatureTile(
                  icon: Icons.percent,
                  color: Colors.lightBlue,
                  title: 'Equity Calculator',
                  body: 'Hand vs range equity, calculated across all run-outs. '
                      'Know whether you\'re 60/40 or 40/60 before you make the call.',
                ),
                _FeatureTile(
                  icon: Icons.currency_exchange_rounded,
                  color: Colors.blueGrey,
                  title: 'Multi-Currency Bankroll',
                  body: 'CAD, USD, GBP, EUR — play anywhere in the world and your bankroll '
                      'stays accurate across every currency.',
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primary.withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.rocket_launch_outlined, color: primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'The Vision',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "A full-stack poker intelligence platform — tracking, analysis, study tools, "
                        "real-time coaching, and eventually, community — for every player who takes "
                        "the game seriously enough to put in the work away from the table. "
                        "Built by a player, for players.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface.withAlpha(220),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                // Version is read from the build (package_info_plus) so this
                // line always reflects the installed app — no hardcoded number
                // to fall out of date.
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.hasData
                        ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
                        : '';
                    return Text(
                      'TableLab $version'.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Operated by MagpiQ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Prose extends StatelessWidget {
  const _Prose(this.text, {this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style ??
          Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(200),
                height: 1.55,
              ),
      textAlign: TextAlign.left,
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(180),
                    height: 1.5,
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
