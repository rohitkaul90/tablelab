import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/profile_provider.dart';
import '../services/analytics_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _completing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _complete({bool skipped = false}) async {
    if (_completing) return;
    setState(() => _completing = true);
    if (skipped) {
      AnalyticsService.onboardingSkipped();
    } else {
      AnalyticsService.onboardingCompleted();
    }
    try {
      await ref.read(profileServiceProvider).markOnboardingComplete();
    } catch (_) {
      // Non-fatal — proceed regardless so user is never stuck.
    }
    if (!mounted) return;
    ref.invalidate(profileProvider);
  }

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: const [_Page1(), _Page2(), _Page3()],
                ),
              ),
              // Page indicator dots
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _page == i ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: _page == i
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withAlpha(60),
                      ),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _completing ? null : _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: _completing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_page < 2 ? 'Next' : 'Get Started'),
                    ),
                    if (_page == 2) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _completing ? null : () => _complete(skipped: true),
                        child: const Text('Skip'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page1 extends StatelessWidget {
  const _Page1();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/icon/app_icon.png', width: 96, height: 96),
          const SizedBox(height: 32),
          Text(
            'Track Every Session',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Log your cash games and tournaments. See exactly where you\'re winning — and where you\'re losing.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(180),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _Page2 extends StatelessWidget {
  const _Page2();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything You Need',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          _FeatureRow(
            icon: Icons.bar_chart_rounded,
            title: 'Deep Analytics',
            body:
                'Win rates by stakes, location, game type, and time of day.',
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            icon: Icons.auto_awesome_outlined,
            title: 'AI Coaching',
            body:
                'Get feedback on any session or hand from a built-in AI coach.',
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            icon: Icons.calculate_outlined,
            title: 'Equity & ICM Tools',
            body:
                'Hand-vs-range equity and ICM deal calculator, available offline.',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Page3 extends StatelessWidget {
  const _Page3();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded,
                color: theme.colorScheme.primary, size: 44),
          ),
          const SizedBox(height: 32),
          Text(
            'Ready to Go',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Log your first session after your next game. Your stats build automatically from there.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(180),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
