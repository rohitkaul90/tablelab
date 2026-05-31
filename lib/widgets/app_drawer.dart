import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/profile_provider.dart';
import '../providers/providers.dart';
import '../providers/reads_provider.dart';
import '../screens/profile_screen.dart';
import '../screens/about_screen.dart';
import '../screens/data_privacy_screen.dart';
import '../screens/terms_of_service_screen.dart';
import '../screens/help_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tournament_calendar_screen.dart';

// Key for the root nav scaffold so any tab screen can open the drawer.
final mainScaffoldKey = GlobalKey<ScaffoldState>();

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final svc = ref.watch(profileServiceProvider);
    final profileAsync = ref.watch(profileProvider);

    final email = svc.email ?? '';
    final googleAvatarUrl = svc.googleAvatarUrl;
    final profile = profileAsync.valueOrNull;

    final displayName = profile?.displayName?.isNotEmpty == true
        ? profile!.displayName!
        : svc.googleName ?? email.split('@').first;

    final parts = displayName.trim().split(' ');
    final initials = parts.length >= 2 && parts[1].isNotEmpty
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : displayName.isNotEmpty
            ? displayName[0].toUpperCase()
            : '?';

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Profile header ─────────────────────────────────────────────
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary.withAlpha(60),
                      backgroundImage: googleAvatarUrl != null
                          ? NetworkImage(googleAvatarUrl)
                          : null,
                      child: googleAvatarUrl == null
                          ? Text(
                              initials,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            email,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white54),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined,
                        size: 14, color: Colors.white38),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // ── Scrollable middle section ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Home ─────────────────────────────────────────────
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('Home'),
                      subtitle: const Text('Dashboard, sessions, hands & more',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        mainScaffoldKey.currentState?.closeDrawer();
                      },
                    ),

                    const Divider(height: 1),

                    // ── Profile nav item ─────────────────────────────────
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Profile'),
                      subtitle: const Text('Name, phone, preferences',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfileScreen()),
                        );
                      },
                    ),

                    const Divider(height: 1),

                    // ── App section ──────────────────────────────────────
                    _SectionLabel('APP', theme),
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Tournament Calendar'),
                      subtitle: const Text('Upcoming live tournaments',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TournamentCalendarScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      subtitle: const Text('Account management, delete account',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.help_outline_rounded),
                      title: const Text('Help & FAQ'),
                      subtitle: const Text('Features, tips, common questions',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HelpScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About TableLab'),
                      subtitle: const Text('What we\'re building and why',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AboutScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Terms of Service'),
                      subtitle: const Text('Usage terms and conditions',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TermsOfServiceScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Data & Privacy'),
                      subtitle: const Text('What we store and how we use it',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DataPrivacyScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.feedback_outlined),
                      title: const Text('Send Feedback'),
                      subtitle: const Text('Bugs, ideas, suggestions',
                          style: TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        launchUrl(Uri(
                          scheme: 'mailto',
                          path: 'feedback@tablelab.app',
                          queryParameters: {'subject': 'TableLab Feedback'},
                        ));
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Sign out (pinned) ──────────────────────────────────────────
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Sign Out',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => _confirmSignOut(context, ref),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      // Providers watch authUserIdProvider and restart automatically on sign-out.
      // Explicit invalidation below is a belt-and-suspenders guard for edge cases
      // (e.g. rapid account switching). Swallow errors if the widget was already
      // disposed by the time AuthGate switches to LoginScreen.
      try {
        ref.invalidate(sessionsProvider);
        ref.invalidate(handsProvider);
        ref.invalidate(filterProvider);
        ref.invalidate(readsProvider);
        ref.invalidate(profileProvider);
      } catch (_) {}
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _SectionLabel(this.label, this.theme);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
