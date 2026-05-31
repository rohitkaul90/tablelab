import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DataPrivacyScreen extends StatelessWidget {
  const DataPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Data & Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        children: [
          _Section(
            icon: Icons.storage_outlined,
            title: 'What we collect',
            body:
                'TableLab stores the data you enter: your email address (for '
                'account login), session records (stakes, buy-ins, cash-outs, '
                'locations, dates, and notes), hand histories you record, '
                'player reads, and your account profile including bankroll '
                'information.\n\n'
                'On Android, crash data is collected automatically by Firebase '
                'Crashlytics when the app encounters an error. This includes '
                'device model, OS version, and anonymised crash identifiers — '
                'no personal poker data is included in crash reports.',
          ),
          _Section(
            icon: Icons.cloud_outlined,
            title: 'Where it\'s stored',
            body:
                'Your session and hand data is stored in a Supabase-managed '
                'Postgres database hosted on Amazon Web Services (outside '
                'Canada). Row-Level Security (RLS) policies ensure only your '
                'authenticated account can read or write your records. '
                'TableLab staff cannot query individual user data.\n\n'
                'Crash data (Android) is processed by Firebase Crashlytics, '
                'a Google service, on Google Cloud infrastructure.',
          ),
          _Section(
            icon: Icons.auto_awesome_outlined,
            title: 'AI features',
            body:
                'When you use Analyze Hand or Analyze Session, the relevant '
                'hand history or session details are sent to Anthropic\'s '
                'Claude API to generate the coaching analysis. Anthropic\'s '
                'data usage policy applies to this data in transit. '
                'Analysis results are cached in your account so repeat '
                'requests don\'t re-send your data. AI features are '
                'opt-in — your data is never sent unless you tap "Analyse".',
          ),
          _Section(
            icon: Icons.block_outlined,
            title: 'No tracking, no ads',
            body:
                'TableLab does not use advertising SDKs or third-party data '
                'brokers. Your poker data is yours. We do not sell, rent, or '
                'share your personal information with any third party for '
                'marketing purposes. We may add anonymous usage analytics in '
                'future — this page will be updated when that occurs.',
          ),
          _Section(
            icon: Icons.manage_accounts_outlined,
            title: 'Your rights',
            body:
                'You have the right to access, export, and delete your data.\n\n'
                'Export: Use the Import/Export screen to download all your '
                'session data as CSV or Excel at any time.\n\n'
                'Deletion: Delete your account and all associated data '
                'directly in the app via Settings → Delete Account. '
                'Deletion is permanent and cannot be undone. '
                'Alternatively, contact us at the address below.\n\n'
                'EU/EEA users (GDPR): You also have the right to data '
                'portability, the right to restrict processing, and the right '
                'to lodge a complaint with your local data protection '
                'authority.\n\n'
                'California users (CCPA): You have the right to know what '
                'personal information we hold and to request its deletion.\n\n'
                'Canadian users (PIPEDA): You have the right to access your '
                'personal information and to challenge its accuracy.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('Contact for data requests'),
            onPressed: () => launchUrl(Uri(
              scheme: 'mailto',
              path: 'privacy@tablelab.app',
              queryParameters: {'subject': 'TableLab Data Request'},
            )),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Full Privacy Policy (tablelab.app/privacy)'),
            onPressed: () => launchUrl(
              Uri.parse('https://tablelab.app/privacy'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Last updated: May 2026',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Section({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 16),
            child: Icon(icon, size: 22, color: theme.colorScheme.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(200),
                    height: 1.55,
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
