import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../l10n/l10n.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
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
                  l10n.aboutTagline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 32),
                _Prose(
                  l10n.aboutQuote,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _Prose(l10n.aboutIntro),
                const SizedBox(height: 28),
                _FeatureTile(
                  icon: Icons.receipt_long_outlined,
                  color: Colors.teal,
                  title: l10n.aboutFeatureSessionTrackerTitle,
                  body: l10n.aboutFeatureSessionTrackerBody,
                ),
                _FeatureTile(
                  icon: Icons.bar_chart_rounded,
                  color: Colors.indigo,
                  title: l10n.aboutFeatureAnalyticsTitle,
                  body: l10n.aboutFeatureAnalyticsBody,
                ),
                _FeatureTile(
                  icon: Icons.play_circle_outline_rounded,
                  color: Colors.orange,
                  title: l10n.aboutFeatureReplayerTitle,
                  body: l10n.aboutFeatureReplayerBody,
                ),
                _FeatureTile(
                  icon: Icons.auto_awesome_outlined,
                  color: Colors.amber,
                  title: l10n.aboutFeatureAiTitle,
                  body: l10n.aboutFeatureAiBody,
                ),
                _FeatureTile(
                  icon: Icons.psychology_outlined,
                  color: Colors.purple,
                  title: l10n.aboutFeatureReadsTitle,
                  body: l10n.aboutFeatureReadsBody,
                ),
                _FeatureTile(
                  icon: Icons.event_outlined,
                  color: Colors.cyan,
                  title: l10n.aboutFeatureCalendarTitle,
                  body: l10n.aboutFeatureCalendarBody,
                ),
                _FeatureTile(
                  icon: Icons.calculate_outlined,
                  color: Colors.green,
                  title: l10n.aboutFeatureIcmTitle,
                  body: l10n.aboutFeatureIcmBody,
                ),
                _FeatureTile(
                  icon: Icons.percent,
                  color: Colors.lightBlue,
                  title: l10n.aboutFeatureEquityTitle,
                  body: l10n.aboutFeatureEquityBody,
                ),
                _FeatureTile(
                  icon: Icons.currency_exchange_rounded,
                  color: Colors.blueGrey,
                  title: l10n.aboutFeatureCurrencyTitle,
                  body: l10n.aboutFeatureCurrencyBody,
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
                            l10n.aboutVisionTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.aboutVisionBody,
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
                  l10n.aboutOperatedBy,
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
