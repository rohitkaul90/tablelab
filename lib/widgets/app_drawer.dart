import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/l10n.dart';
import '../providers/profile_provider.dart';
import '../providers/providers.dart';
import '../providers/reads_provider.dart';
import '../screens/profile_screen.dart';
import '../screens/about_screen.dart';
import '../screens/data_privacy_screen.dart';
import '../screens/terms_of_service_screen.dart';
import '../screens/help_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tools_screen.dart';
import '../screens/tournament_calendar_screen.dart';
import 'feedback_sheet.dart';
import 'profile_avatar.dart';

// Key for the root nav scaffold so any tab screen can open the drawer.
final mainScaffoldKey = GlobalKey<ScaffoldState>();

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                    ProfileAvatar(
                      imageUrl: googleAvatarUrl,
                      initials: initials,
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary.withAlpha(60),
                      initialsStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
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
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.75)),
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
                      title: Text(l10n.drawerHome),
                      subtitle: Text(l10n.drawerHomeSubtitle,
                          style: const TextStyle(fontSize: 11)),
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
                      title: Text(l10n.drawerProfile),
                      subtitle: Text(l10n.drawerProfileSubtitle,
                          style: const TextStyle(fontSize: 11)),
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
                    _SectionLabel(l10n.drawerSectionApp, theme),
                    ListTile(
                      leading: const Icon(Icons.construction_outlined),
                      title: Text(l10n.drawerTools),
                      subtitle: Text(l10n.drawerToolsSubtitle,
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ToolsScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(l10n.drawerTournamentCalendar),
                      subtitle: Text(l10n.drawerTournamentCalendarSubtitle,
                          style: const TextStyle(fontSize: 11)),
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
                      title: Text(l10n.drawerSettings),
                      subtitle: Text(l10n.drawerSettingsSubtitle,
                          style: const TextStyle(fontSize: 11)),
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
                      leading: const Icon(Icons.feedback_outlined),
                      title: Text(l10n.drawerSendFeedback),
                      subtitle: Text(l10n.drawerSendFeedbackSubtitle,
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        showFeedbackSheet(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.help_outline_rounded),
                      title: Text(l10n.drawerHelp),
                      subtitle: Text(l10n.drawerHelpSubtitle,
                          style: const TextStyle(fontSize: 11)),
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
                      title: Text(l10n.drawerAbout),
                      subtitle: Text(l10n.drawerAboutSubtitle,
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AboutScreen()),
                        );
                      },
                    ),
                    _SectionLabel(l10n.drawerSectionLegal, theme),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: Text(l10n.drawerTerms),
                      subtitle: Text(l10n.drawerTermsSubtitle,
                          style: const TextStyle(fontSize: 11)),
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
                      title: Text(l10n.drawerPrivacy),
                      subtitle: Text(l10n.drawerPrivacySubtitle,
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DataPrivacyScreen()),
                        );
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
                l10n.drawerSignOut,
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
    final l10n = context.l10n;
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.drawerSignOutTitle),
        content: Text(l10n.drawerSignOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.drawerSignOut),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {
        // GoTrue clears the local session and fires the signed-out event BEFORE
        // the network logout call, so the user is already signed out (AuthGate
        // routes to LoginScreen) even if that call fails. Swallow the offline
        // error (AuthRetryableFetchException / SocketException) so a network
        // blip during sign-out can't crash the app (crash-issues-11).
      }
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
