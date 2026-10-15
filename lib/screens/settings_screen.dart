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

  String _usageLabel(AppLocalizations l10n, {required bool isSession}) {
    if (_usageFailed) return '—';
    final u = _usage;
    if (u == null) return '…';
    if (u.exempt) return l10n.settingsUsageUnlimited;
    return isSession
        ? '${u.session} / ${AiService.sessionDailyLimit}'
        : '${u.hand} / ${AiService.handDailyLimit}';
  }

  Future<void> _deleteAccount() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteTitle),
        content: Text(l10n.settingsDeleteBody),
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
            child: Text(l10n.settingsDeleteConfirm),
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
        title: Text(l10n.settingsDeleteTitle2),
        content: Text(l10n.settingsDeleteBody2),
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
            child: Text(l10n.settingsDeleteConfirm2),
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
        SnackBar(content: Text(l10n.settingsDeleteFailed('$e'))),
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
                  if (!mounted) return;
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
    final l10n = context.l10n;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(l10n.settingsDisplayCurrency,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final c in options)
              ListTile(
                title: Text(c ?? l10n.settingsCurrencyAutoOption),
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
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: _deleting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(context.l10n.settingsDeletingAccount),
                ],
              ),
            )
          : ListView(
              children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(context.l10n.settingsVersion),
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
                    context.l10n.settingsSectionStats,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(context.l10n.settingsDisplayCurrency),
                  subtitle: Text(context.l10n.settingsDisplayCurrencySubtitle),
                  trailing: Text(
                    profile?.displayCurrency ?? context.l10n.settingsCurrencyAuto,
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
                    context.l10n.settingsSectionAiUsage,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(context.l10n.settingsSessionAnalyses),
                  trailing: Text(
                    _usageLabel(context.l10n, isSession: true),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(context.l10n.settingsHandAnalyses),
                  trailing: Text(
                    _usageLabel(context.l10n, isSession: false),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    context.l10n.settingsAiUsageNote,
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
                    context.l10n.settingsSectionData,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.import_export),
                  title: Text(context.l10n.settingsImportExport),
                  subtitle: Text(
                    context.l10n.settingsImportExportSubtitle,
                    style: const TextStyle(fontSize: 12),
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
                    context.l10n.settingsSectionDanger,
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
                    context.l10n.settingsDeleteAccount,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text(
                    context.l10n.settingsDeleteAccountSubtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: _deleteAccount,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.l10n.settingsDeleteAccountNote,
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
