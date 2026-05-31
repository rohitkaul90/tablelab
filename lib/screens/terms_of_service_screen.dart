import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        children: [
          _Section(
            icon: Icons.check_circle_outline,
            title: 'Acceptance of terms',
            body:
                'By creating an account or using TableLab, you agree to these '
                'Terms of Service. If you do not agree, please do not use the app.',
          ),
          _Section(
            icon: Icons.person_outline,
            title: 'Your account',
            body:
                'You are responsible for maintaining the confidentiality of your '
                'account credentials and for all activity that occurs under your '
                'account. You must be 18 years of age or older to use TableLab. '
                'You agree to provide accurate information when registering.',
          ),
          _Section(
            icon: Icons.edit_note_outlined,
            title: 'Your content',
            body:
                'You retain ownership of all session records, hand histories, '
                'and other data you enter into TableLab. By using the app, you '
                'grant us a limited licence to store and process your content '
                'solely to provide the service to you.',
          ),
          _Section(
            icon: Icons.auto_awesome_outlined,
            title: 'AI features',
            body:
                'AI coaching features (Analyse Session, Analyse Hand) are '
                'provided for informational purposes only. Outputs are generated '
                'by a third-party AI model and may contain errors. They do not '
                'constitute professional gambling, financial, or legal advice. '
                'Use your own judgement at the table.',
          ),
          _Section(
            icon: Icons.block_outlined,
            title: 'Prohibited uses',
            body:
                'You agree not to use TableLab to: (a) violate any applicable '
                'law or regulation; (b) attempt to gain unauthorised access to '
                'other users\' data; (c) scrape, reverse-engineer, or copy the '
                'app; or (d) use the service in any way that could damage or '
                'impair it.',
          ),
          _Section(
            icon: Icons.warning_amber_outlined,
            title: 'Disclaimer of warranties',
            body:
                'TableLab is provided "as is" without warranties of any kind. '
                'We do not guarantee that the service will be uninterrupted, '
                'error-free, or that data will never be lost. You use the app '
                'at your own risk.',
          ),
          _Section(
            icon: Icons.gavel_outlined,
            title: 'Limitation of liability',
            body:
                'To the fullest extent permitted by law, TableLab and its '
                'developers shall not be liable for any indirect, incidental, '
                'or consequential damages arising from your use of the app, '
                'including loss of data or profits.',
          ),
          _Section(
            icon: Icons.update_outlined,
            title: 'Changes to these terms',
            body:
                'We may update these terms from time to time. Continued use of '
                'TableLab after changes are posted constitutes acceptance of the '
                'revised terms. We will notify users of material changes where '
                'reasonably practicable.',
          ),
          _Section(
            icon: Icons.cancel_outlined,
            title: 'Termination',
            body:
                'You may delete your account at any time via Settings → '
                'Delete Account in the app. We reserve the right to suspend '
                'or terminate accounts that violate these terms.',
          ),
          _Section(
            icon: Icons.balance_outlined,
            title: 'Governing law',
            body:
                'These Terms are governed by and construed in accordance with '
                'the laws of the Province of Ontario and the federal laws of '
                'Canada applicable therein. You agree that any dispute arising '
                'from these Terms or your use of TableLab shall be subject to '
                'the exclusive jurisdiction of the courts of Ontario, Canada, '
                'unless prohibited by your local consumer protection laws.',
          ),
          _Section(
            icon: Icons.contact_support_outlined,
            title: 'Contact',
            body:
                'For questions about these Terms, privacy requests, or to '
                'report a violation, contact us at privacy@tablelab.app. '
                'We aim to respond within 30 business days.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('Contact us'),
            onPressed: () => launchUrl(Uri(
              scheme: 'mailto',
              path: 'privacy@tablelab.app',
              queryParameters: {'subject': 'TableLab Terms Enquiry'},
            )),
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
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
