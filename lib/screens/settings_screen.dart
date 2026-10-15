import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'import_export_screen.dart';
import '../models/profile_model.dart';
import '../services/analytics_service.dart';
import '../services/ai_service.dart';
import '../utils/helpers.dart' show supportedDisplayCurrencies;
import '../l10n/l10n.dart';
import '../providers/locale_provider.dart';
import '../providers/providers.dart';
import '../providers/reads_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  /// When set to `'ai_usage'`, the screen scrolls to and briefly highlights the
  /// AI USAGE section on open — used by the contextual AI quota indicators.
  final String? scrollToSection;

  const SettingsScreen({super.key, this.scrollToSection});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _deleting = false;
  String _version = '…';
  AiUsage? _usage;
  bool _usageFailed = false;
  final _aiUsageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadUsage();
    if (widget.scrollToSection == 'ai_usage') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _aiUsageKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            alignment: 0.1,
          );
        }
      });
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = '${info.version} (${info.buildNumber})');
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await ref.read(aiServiceProvider).fetchUsageLast24h();
      if (!mounted) return;
      setState(() => _usage = usage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _usageFailed = true);
    }
  }

  String _usageLabel({required bool isSession}) {
    if (_usageFailed) return '—';
    final u = _usage;
    if (u == null) return '…';
    if (u.exempt) return 'Unlimited';
    return isSession
        ? '${u.session} / ${AiService.sessionDailyLimit}'
        : '${u.hand} / ${AiService.handDailyLimit}';
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This permanently deletes your account and ALL data — sessions, '
          'hands, player reads, and AI analyses. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Second confirmation — require an explicit tap on a destructive button.
    if (!mounted) return;
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: const Text(
          'Your account and all poker data will be permanently erased. '
          'There is no recovery option.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete My Account'),
          ),
        ],
      ),
    );

    if (doubleConfirmed != true) return;
    if (!mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(supabaseServiceProvider).deleteAccount();
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      ref.invalidate(sessionsProvider);
      ref.invalidate(handsProvider);
      ref.invalidate(filterProvider);
      ref.invalidate(readsProvider);
      ref.invalidate(profileProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: $e')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _pickLanguage() async {
    // null = System (follow the device). Same plain-ListTile sheet as the
    // currency picker: a 6-segment SegmentedButton would overflow on phones
    // and RadioListTile trips a deprecation under `--fatal-infos`. Endonyms
    // are deliberately untranslated so a user stuck in the wrong language can
    // still find their own.
    final l10n = context.l10n;
    final current = ref.read(localeProvider);
    final options = <Locale?>[null, ...AppLocalizations.supportedLocales];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(l10n.settingsLanguage,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final loc in options)
              ListTile(
                title: Text(
                    loc == null ? l10n.languageSystem : localeEndonym(loc)),
                trailing: loc == current
                    ? Icon(Icons.check,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(localeProvider.notifier).set(loc);
                  AnalyticsService.languageChanged(
                    language: loc?.languageCode ?? 'system',
                    resolved: ref.read(resolvedLocaleProvider).languageCode,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDisplayCurrency(ProfileModel profile) async {
    // null = Auto (follow the most-recent session). Plain ListTiles (not
    // RadioListTile) to dodge the Radio groupValue deprecation that would trip
    // `flutter analyze --fatal-infos`.
    final options = <String?>[null, ...supportedDisplayCurrencies];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Display currency',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final c in options)
              ListTile(
                title: Text(c ?? 'Auto (most recent session)'),
                trailing: c == profile.displayCurrency
                    ? Icon(Icons.check,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _setDisplayCurrency(profile, c);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setDisplayCurrency(
      ProfileModel profile, String? currency) async {
    if (currency == profile.displayCurrency) return;
    final updated = currency == null
        ? profile.copyWith(clearDisplayCurrency: true)
        : profile.copyWith(displayCurrency: currency);
    await ref.read(profileServiceProvider).upsertProfile(updated);
    if (!mounted) return;
    ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _deleting
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Deleting account…'),
                ],
              ),
            )
          : ListView(
              children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Version'),
                  trailing: Text(
                    _version,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    context.l10n.settingsAppearance,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: Text(context.l10n.settingsTheme),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<ThemeMode>(
                      // Label-only (no per-segment icons): icon+label on three
                      // segments overflowed the row and wrapped "System" onto a
                      // second line on narrower phones.
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(context.l10n.themeModeSystem),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(context.l10n.themeModeLight),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(context.l10n.themeModeDark),
                        ),
                      ],
                      selected: {ref.watch(themeModeProvider)},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        ref.read(themeModeProvider.notifier).set(s.first);
                        AnalyticsService.themeChanged(mode: s.first.name);
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: Text(context.l10n.settingsLanguage),
                  trailing: Text(
                    switch (ref.watch(localeProvider)) {
                      null => context.l10n.languageSystem,
                      final loc => localeEndonym(loc),
                    },
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: _pickLanguage,
                ),
                const Divider(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'STATS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Display currency'),
                  subtitle: const Text(
                      'Currency stats totals are shown in. "Auto" follows your most recent session.'),
                  trailing: Text(
                    profile?.displayCurrency ?? 'Auto',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  onTap: profile == null
                      ? null
                      : () => _pickDisplayCurrency(profile),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Padding(
                  key: _aiUsageKey,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'AI USAGE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Session analyses'),
                  trailing: Text(
                    _usageLabel(isSession: true),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Hand analyses'),
                  trailing: Text(
                    _usageLabel(isSession: false),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Free daily limits, on a rolling 24-hour window.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'DATA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.import_export),
                  title: const Text('Import / Export Sessions'),
                  subtitle: const Text(
                    'Migrate from another app, or back up your data',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ImportExportScreen()),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'DANGER ZONE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined,
                      color: theme.colorScheme.error),
                  title: Text(
                    'Delete Account',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Permanently delete your account and all data',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: _deleteAccount,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Deleting your account is permanent. All sessions, hands, '
                    'player reads, and AI analyses will be erased immediately '
                    'and cannot be recovered. Export your data first if needed.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
