import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_model.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stakesCtrl = TextEditingController();
  final _sincCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _bankrollCtrl = TextEditingController();

  String? _preferredGame;
  String _bankrollCurrency = 'CAD';
  bool _loading = true;
  bool _saving = false;
  String? _uid;
  // Preserve the existing onboarding flag so saving the profile never resets it
  // (a fresh ProfileModel defaults hasSeenOnboarding to false, which would bounce
  // the user back into the onboarding flow via _OnboardingGate). Defaults to true
  // since any user on this screen has already passed onboarding.
  bool _hasSeenOnboarding = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _stakesCtrl.dispose();
    _sincCtrl.dispose();
    _rateCtrl.dispose();
    _bankrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final svc = ref.read(profileServiceProvider);
    _uid = svc.uid;
    final profile = await svc.fetchProfile();
    if (!mounted) return;
    if (profile != null) {
      _nameCtrl.text = profile.displayName ?? '';
      _phoneCtrl.text = profile.phone ?? '';
      _cityCtrl.text = profile.homeCity ?? '';
      _stakesCtrl.text = profile.preferredStakes ?? '';
      _sincCtrl.text = profile.playingSince?.toString() ?? '';
      _rateCtrl.text = profile.hourlyRateGoal?.toString() ?? '';
      _bankrollCtrl.text = profile.startingBankroll?.toString() ?? '';
      _hasSeenOnboarding = profile.hasSeenOnboarding;
      setState(() {
        _preferredGame = profile.preferredGame;
        _bankrollCurrency = profile.startingBankrollCurrency;
        _loading = false;
      });
    } else {
      // Pre-fill name from Google if available
      _nameCtrl.text = svc.googleName ?? '';
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final id = _uid;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      final profile = ProfileModel(
        id: id,
        displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        homeCity: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        preferredGame: _preferredGame,
        preferredStakes: _stakesCtrl.text.trim().isEmpty ? null : _stakesCtrl.text.trim(),
        playingSince: int.tryParse(_sincCtrl.text.trim()),
        hourlyRateGoal: double.tryParse(_rateCtrl.text.trim()),
        startingBankroll: double.tryParse(_bankrollCtrl.text.trim()),
        startingBankrollCurrency: _bankrollCurrency,
        hasSeenOnboarding: _hasSeenOnboarding,
      );
      await ref.read(profileServiceProvider).upsertProfile(profile);
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = ref.read(profileServiceProvider);
    final email = svc.email ?? '';
    final avatarUrl = svc.googleAvatarUrl;
    final initials = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()[0].toUpperCase()
        : email.isNotEmpty
            ? email[0].toUpperCase()
            : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      16, 24, 16, 32 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    // ── Avatar + email ───────────────────────────────────────
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor:
                                theme.colorScheme.primary.withAlpha(60),
                            backgroundImage: avatarUrl != null
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null
                                ? Text(initials,
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ))
                                : null,
                          ),
                          if (avatarUrl != null)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.verified,
                                  size: 16, color: theme.colorScheme.primary),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        email,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Basic Info ───────────────────────────────────────────
                    _SectionHeader('Basic Info'),
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _field(
                              controller: _nameCtrl,
                              label: 'Display Name',
                              hint: 'How you want to be known',
                              icon: Icons.badge_outlined,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 14),
                            _field(
                              controller: _phoneCtrl,
                              label: 'Phone Number',
                              hint: '+1 555 000 0000',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 14),
                            _field(
                              controller: _cityCtrl,
                              label: 'Home City',
                              hint: 'e.g. Las Vegas, Toronto',
                              icon: Icons.location_city_outlined,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Game Preferences ─────────────────────────────────────
                    _SectionHeader('Game Preferences'),
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Preferred Game',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final entry in [
                                  ('cash', 'Cash'),
                                  ('tournament', 'Tournament'),
                                  ('both', 'Both'),
                                ])
                                  ChoiceChip(
                                    label: Text(entry.$2),
                                    selected: _preferredGame == entry.$1,
                                    onSelected: (on) => setState(() =>
                                        _preferredGame = on ? entry.$1 : null),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _field(
                              controller: _stakesCtrl,
                              label: 'Preferred Stakes',
                              hint: 'e.g. 1/2 NL, 2/5 PLO',
                              icon: Icons.attach_money_outlined,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Goals & Background ───────────────────────────────────
                    _SectionHeader('Goals & Background'),
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _field(
                              controller: _sincCtrl,
                              label: 'Playing Since (year)',
                              hint: 'e.g. 2018',
                              icon: Icons.history_outlined,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 14),
                            _field(
                              controller: _rateCtrl,
                              label: 'Hourly Rate Goal (\$/hr)',
                              hint: 'e.g. 25',
                              icon: Icons.trending_up_outlined,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Bankroll ─────────────────────────────────────────────
                    _SectionHeader('Bankroll'),
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Starting bankroll',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    controller: _bankrollCtrl,
                                    label: 'Amount',
                                    hint: 'e.g. 5000',
                                    icon: Icons.account_balance_wallet_outlined,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                DropdownButton<String>(
                                  value: _bankrollCurrency,
                                  items: ['CAD', 'USD', 'EUR', 'GBP', 'AUD']
                                      .map((c) => DropdownMenuItem(
                                          value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: (v) => setState(
                                      () => _bankrollCurrency = v ?? 'CAD'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Used to calculate your Current Bankroll on the dashboard.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Save button ──────────────────────────────────────────
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save Profile'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          isDense: true,
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}
