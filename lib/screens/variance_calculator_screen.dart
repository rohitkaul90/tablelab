import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/profile_provider.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../utils/helpers.dart';
import '../utils/variance_math.dart';
import '../widgets/app_drawer.dart';

/// Poker variance calculator (primedope-style): winrate + standard deviation
/// + sample size → expected result with 70%/95% confidence envelopes, ~20
/// simulated sample runs, probability of loss, risk of ruin and bankroll
/// requirements, plus a Monte-Carlo downswing estimate.
///
/// Two modes: Cash (bb/100 units) and Tournament (buy-in units). The
/// differentiator over the standalone web calculators: **"Use my stats"**
/// prefills winrate/SD/sample from the user's own logged sessions (the
/// Malmuth session estimators in helpers.dart).
///
/// Dual-mode like the other calculators: `showScaffold: false` returns body
/// content only, for embedding in the Tools screen's IndexedStack.
class VarianceCalculatorScreen extends ConsumerStatefulWidget {
  final bool showScaffold;
  const VarianceCalculatorScreen({super.key, this.showScaffold = true});

  @override
  ConsumerState<VarianceCalculatorScreen> createState() =>
      _VarianceCalculatorScreenState();
}

class _ThousandsFormatter extends TextInputFormatter {
  static final _fmt = NumberFormat('#,###', 'en_US');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    // int.parse throws past 19 digits on native 64-bit platforms (a long
    // paste would crash the input pipeline) — no poker sample needs more
    // than 12 digits; keep the previous value instead.
    if (digits.length > 12) return oldValue;
    final formatted = _fmt.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _VarianceCalculatorScreenState
    extends ConsumerState<VarianceCalculatorScreen> {
  // 0 = cash, 1 = tournament.
  int _mode = 0;

  // Cash inputs.
  final _cashWr = TextEditingController(text: '2.5');
  final _cashSd = TextEditingController(text: '90');
  final _cashHands = TextEditingController(text: '50,000');
  final _cashBankroll = TextEditingController();

  // Tournament inputs.
  final _tRoi = TextEditingController(text: '20');
  final _tSd = TextEditingController(text: '3');
  final _tCount = TextEditingController(text: '200');
  final _tBankroll = TextEditingController();

  String? _error;
  bool _running = false;
  int _seedOffset = 0;

  // Results (all in units of bb / buy-ins).
  VarianceResult? _result;
  List<List<double>>? _paths;
  DownswingStats? _downswings;
  double? _units;
  double? _sdPerUnit;
  int _resultMode = 0;

  @override
  void dispose() {
    for (final c in [
      _cashWr, _cashSd, _cashHands, _cashBankroll, //
      _tRoi, _tSd, _tCount, _tBankroll,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parse a field, handling BOTH comma roles: "2,500" is a thousands
  /// separator, "2,5" is an EU-keyboard decimal comma (many Android numeric
  /// keyboards offer ',' not '.' — stripping it silently read 2,5 as 25, a
  /// 10× error feeding every output). Heuristic: a single comma NOT followed
  /// by exactly three digits is a decimal point; anything else is grouping.
  double? _num(TextEditingController c) {
    var t = c.text.trim();
    if (t.contains(',') && !t.contains('.')) {
      final commas = ','.allMatches(t).length;
      if (commas == 1 && !RegExp(r',\d{3}$').hasMatch(t)) {
        t = t.replaceAll(',', '.');
      } else {
        t = t.replaceAll(',', '');
      }
    } else {
      t = t.replaceAll(',', '');
    }
    return double.tryParse(t);
  }

  /// Prefill from the user's own sessions (needs ≥10 qualifying sessions for
  /// the SD estimators — see helpers.dart).
  void _useMyStats() {
    final sessions =
        ref.read(completedSessionsProvider).valueOrNull ?? const [];
    String? missing;
    if (_mode == 0) {
      final cash = sessions.where((s) => s.gameType == 'cash').toList();
      final wr = calcBB100(cash);
      final sd = calcBB100StdDev(cash);
      final hands = cash.where(countsForBB100).fold<double>(
          0, (a, s) => a + (s.handsPerHour ?? 25) * s.durationMinutes / 60.0);
      if (wr == null || hands <= 0) {
        missing = 'Need cash sessions with parseable blinds and durations to '
            'estimate a winrate.';
      } else {
        _cashWr.text = wr.toStringAsFixed(1);
        _cashHands.text = _ThousandsFormatter._fmt.format(hands.round());
        if (sd != null) {
          _cashSd.text = sd.toStringAsFixed(0);
        } else {
          missing = 'Winrate and hands filled. Standard deviation needs at '
              'least 10 qualifying cash sessions — kept the current value.';
        }
      }
    } else {
      final t =
          sessions.where((s) => isTournamentType(s.gameType)).toList();
      // Pooled ROI needs ONE common currency — raw sums across mixed-currency
      // logs blend rupees with dollars (review finding). Convert per session
      // into the profile's display currency (the target cancels out of the
      // ratio; it just has to be consistent).
      final cur =
          ref.read(profileProvider).valueOrNull?.displayCurrency ?? 'USD';
      final buyIn = t.fold(
          0.0, (a, s) => a + convertCurrency(s.buyIn, s.currency, cur));
      final pl = t.fold(
          0.0, (a, s) => a + convertCurrency(s.profitLoss, s.currency, cur));
      final sd = calcTournamentStdDevBuyIns(t);
      if (t.isEmpty || buyIn <= 0) {
        missing = 'Need logged tournaments with buy-ins to estimate an ROI.';
      } else {
        _tRoi.text = (pl / buyIn * 100).toStringAsFixed(1);
        _tCount.text = _ThousandsFormatter._fmt.format(t.length);
        if (sd != null) {
          _tSd.text = sd.toStringAsFixed(1);
        } else {
          missing = 'ROI and entries filled. Standard deviation needs at '
              'least 10 tournaments with buy-ins — kept the current value.';
        }
      }
    }
    setState(() {});
    if (missing != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(missing)));
    }
  }

  Future<void> _calculate() async {
    if (_running) return;

    final int mode = _mode;
    final double? mean, sd, count, bankroll;
    if (mode == 0) {
      mean = _num(_cashWr);
      sd = _num(_cashSd);
      final hands = _num(_cashHands);
      count = hands == null ? null : hands / 100.0; // units of 100 hands
      bankroll = _num(_cashBankroll);
    } else {
      final roi = _num(_tRoi);
      mean = roi == null ? null : roi / 100.0; // buy-ins per tournament
      sd = _num(_tSd);
      count = _num(_tCount);
      bankroll = _num(_tBankroll);
    }

    // On any validation failure, CLEAR stale results — an error banner over
    // the previous inputs' chart reads as if the figures were current
    // (review finding).
    void fail(String msg) => setState(() {
          _error = msg;
          _result = null;
          _paths = null;
          _downswings = null;
          _lastInputs = null;
        });

    if (mean == null || sd == null || count == null) {
      fail('Enter a winrate, standard deviation and sample size '
          '(numbers only).');
      return;
    }
    if (sd <= 0 || count <= 0) {
      fail(mode == 0
          ? 'Hands and standard deviation must both be above zero.'
          : 'Tournaments and standard deviation must both be above zero.');
      return;
    }
    if (_mode == 0 ? _cashBankroll.text.isNotEmpty : _tBankroll.text.isNotEmpty) {
      if (bankroll == null || bankroll <= 0) {
        fail('Bankroll must be a positive number (or leave it empty).');
        return;
      }
    }

    _seedOffset = 0;
    _lastInputs =
        (mode: mode, mean: mean, sd: sd, count: count, bankroll: bankroll);
    AnalyticsService.varianceCalculatorUsed(
        mode: mode == 0 ? 'cash' : 'tournament');
    await _run();
  }

  /// Re-simulate the sample runs for the DISPLAYED result — uses the captured
  /// inputs, not the live fields (the user may have switched modes or edited
  /// fields since; a reroll must never silently recompute — review finding).
  /// Also does not re-fire the analytics event.
  Future<void> _reroll() async {
    if (_running || _lastInputs == null) return;
    _seedOffset++;
    await _run();
  }

  ({int mode, double mean, double sd, double count, double? bankroll})?
      _lastInputs;

  Future<void> _run() async {
    final it = _lastInputs!;
    // Deterministic per input set (the app's seeded-visual convention) so the
    // same numbers always draw the same curves; "reroll" bumps the offset.
    final seed = Object.hash(it.mode, it.mean, it.sd, it.count, _seedOffset);

    setState(() {
      _error = null;
      _running = true;
      _result = computeVariance(
          meanPerUnit: it.mean,
          sdPerUnit: it.sd,
          units: it.count,
          bankroll: it.bankroll);
      _paths = simulatePaths(
          meanPerUnit: it.mean,
          sdPerUnit: it.sd,
          units: it.count,
          seed: seed);
      _units = it.count;
      _sdPerUnit = it.sd;
      _resultMode = it.mode;
      _downswings = null;
    });

    // The downswing Monte Carlo (2,000 trials) runs off the UI thread.
    final ds = await compute(
        simulateDownswings,
        DownswingParams(
            meanPerUnit: it.mean,
            sdPerUnit: it.sd,
            units: it.count,
            bankroll: it.bankroll,
            seed: seed));
    if (!mounted) return;
    setState(() {
      _downswings = ds;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCash = _mode == 0;

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Cash')),
            ButtonSegment(value: 1, label: Text('Tournament')),
          ],
          selected: {_mode},
          // Clear any validation error on mode switch — a cash-specific
          // message hovering over the tournament form (or vice versa) reads
          // as a live problem with inputs it never examined (review finding).
          onSelectionChanged: (s) => setState(() {
            _mode = s.first;
            _error = null;
          }),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: theme.colorScheme.primary,
            selectedForegroundColor: theme.colorScheme.onPrimary,
            foregroundColor: theme.colorScheme.onSurface.withAlpha(153),
          ),
        ),
        const SizedBox(height: 16),

        if (isCash) ...[
          _field(_cashWr, 'Winrate (bb/100)', 'e.g. 2.5', signed: true),
          _field(_cashSd, 'Std deviation (bb/100)',
              'typical live NLHE ≈ 70–100'),
          _field(_cashHands, 'Hands', 'e.g. 50,000', thousands: true),
          _field(_cashBankroll, 'Bankroll in bb (optional)',
              'for risk of ruin', thousands: true),
        ] else ...[
          _field(_tRoi, 'ROI (%)', 'e.g. 20', signed: true),
          _field(_tSd, 'Std deviation (buy-ins)', 'SNG ≈ 1.5–2 · MTT ≈ 3–6+'),
          _field(_tCount, 'Tournaments', 'e.g. 200', thousands: true),
          _field(_tBankroll, 'Bankroll in buy-ins (optional)',
              'for risk of ruin', thousands: true),
        ],

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _running ? null : () => _calculate(),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Calculate'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _running ? null : _useMyStats,
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('Use my stats'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ),

        if (_result != null) ...[
          const SizedBox(height: 20),
          _resultsSection(theme),
        ],
      ],
    );

    if (!widget.showScaffold) return body;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('Variance Calculator')),
      body: body,
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {bool signed = false, bool thousands = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(
            decimal: !thousands, signed: signed),
        inputFormatters: [
          if (thousands)
            _ThousandsFormatter()
          else
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _resultsSection(ThemeData theme) {
    final r = _result!;
    final cash = _resultMode == 0;
    final unit = cash ? 'bb' : 'buy-ins';
    final xLabel = cash ? 'hands' : 'tournaments';
    final xMax = cash ? (_units! * 100) : _units!;

    String fmt(double v, {int dp = 0}) {
      final sign = v >= 0 ? '+' : '−';
      final a = v.abs();
      final s = dp == 0
          ? _ThousandsFormatter._fmt.format(a.round())
          : a.toStringAsFixed(dp);
      return '$sign$s';
    }

    final dp = cash ? 0 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Expected: ${fmt(r.ev, dp: dp)} $unit',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: r.ev >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Reroll sample runs',
              icon: const Icon(Icons.casino_outlined),
              onPressed: _running ? null : _reroll,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Chart ───────────────────────────────────────────────────────────
        SizedBox(
          height: 220,
          child: CustomPaint(
            painter: _VariancePathsPainter(
              paths: _paths!,
              ev: r.ev,
              sdPerUnit: _sdPerUnit!,
              units: _units!,
              primary: theme.colorScheme.primary,
              onSurface: theme.colorScheme.onSurface,
              outline: theme.colorScheme.outline,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '0 → ${_ThousandsFormatter._fmt.format(xMax.round())} $xLabel · '
            'shaded: 70% and 95% of outcomes · lines: 20 simulated runs',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        const SizedBox(height: 16),

        _row(theme, '70% of outcomes',
            '${fmt(r.ci70Low, dp: dp)} to ${fmt(r.ci70High, dp: dp)} $unit'),
        _row(theme, '95% of outcomes',
            '${fmt(r.ci95Low, dp: dp)} to ${fmt(r.ci95High, dp: dp)} $unit'),
        _row(theme, 'Chance of losing overall',
            '${(r.pLoss * 100).toStringAsFixed(1)}%'),
        if (r.riskOfRuin != null)
          _row(theme, 'Risk of ruin', _pct(r.riskOfRuin!)),
        if (r.bankrollForRoR5 != null)
          _row(theme, 'Bankroll for 5% risk of ruin',
              '${_ThousandsFormatter._fmt.format(r.bankrollForRoR5!.ceil())} $unit'),
        if (r.bankrollForRoR1 != null)
          _row(theme, 'Bankroll for 1% risk of ruin',
              '${_ThousandsFormatter._fmt.format(r.bankrollForRoR1!.ceil())} $unit'),
        if (_downswings != null) ...[
          _row(theme, 'Typical worst downswing',
              '${_ThousandsFormatter._fmt.format(_downswings!.medianMaxDrawdown.round())} $unit'),
          _row(theme, 'Bad-run downswing (95th pct)',
              '${_ThousandsFormatter._fmt.format(_downswings!.p95MaxDrawdown.round())} $unit'),
          if (_downswings!.pBustDuringHorizon != null)
            _row(theme, 'Chance of going broke during this sample',
                _pct(_downswings!.pBustDuringHorizon!)),
        ] else if (_running)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        const SizedBox(height: 12),
        Text(
          _resultMode == 0
              ? 'Estimates use a normal approximation of your winrate as a '
                  'random walk. Real results vary; treat these as guides, '
                  'not guarantees.'
              : 'Estimates use a normal approximation. Tournament results '
                  'are heavily skewed by rare big scores, so real tail risk '
                  'is HIGHER than shown — especially over small samples.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  String _pct(double p) {
    if (p < 0.0005) return '< 0.1%';
    return '${(p * 100).toStringAsFixed(1)}%';
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(value,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Paints the EV line, the 70%/95% envelopes (parabolic in √t) and the
/// simulated sample paths. CustomPaint, not fl_chart — only polylines are
/// needed and it sidesteps the fl_chart Windows touch gotcha entirely
/// (equity_chart.dart precedent).
class _VariancePathsPainter extends CustomPainter {
  final List<List<double>> paths;
  final double ev;
  final double sdPerUnit;
  final double units;
  final Color primary;
  final Color onSurface;
  final Color outline;

  _VariancePathsPainter({
    required this.paths,
    required this.ev,
    required this.sdPerUnit,
    required this.units,
    required this.primary,
    required this.onSurface,
    required this.outline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (paths.isEmpty || paths.first.length < 2) return;
    final steps = paths.first.length - 1;

    // Y range: cover the 95% envelope AND every sample path.
    var yMin = 0.0, yMax = 0.0;
    for (var k = 0; k <= steps; k++) {
      final t = units * k / steps;
      final sd = sdPerUnit * _sqrt(t);
      final mid = ev * k / steps;
      yMin = _min(yMin, mid - z95 * sd);
      yMax = _max(yMax, mid + z95 * sd);
    }
    for (final p in paths) {
      for (final v in p) {
        yMin = _min(yMin, v);
        yMax = _max(yMax, v);
      }
    }
    if (yMax - yMin < 1e-9) {
      yMax += 1;
      yMin -= 1;
    }
    final pad = (yMax - yMin) * 0.05;
    yMin -= pad;
    yMax += pad;

    double x(int k) => size.width * k / steps;
    double y(double v) => size.height * (1 - (v - yMin) / (yMax - yMin));

    Path envelope(double z) {
      final up = Path()..moveTo(0, y(0));
      for (var k = 0; k <= steps; k++) {
        final t = units * k / steps;
        up.lineTo(x(k), y(ev * k / steps + z * sdPerUnit * _sqrt(t)));
      }
      for (var k = steps; k >= 0; k--) {
        final t = units * k / steps;
        up.lineTo(x(k), y(ev * k / steps - z * sdPerUnit * _sqrt(t)));
      }
      return up..close();
    }

    canvas.drawPath(
        envelope(z95), Paint()..color = primary.withValues(alpha: 0.08));
    canvas.drawPath(
        envelope(z70), Paint()..color = primary.withValues(alpha: 0.14));

    // Zero line.
    final zeroPaint = Paint()
      ..color = outline.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), zeroPaint);

    // Sample paths.
    final pathPaint = Paint()
      ..color = onSurface.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final p in paths) {
      final poly = Path()..moveTo(0, y(p[0]));
      for (var k = 1; k <= steps; k++) {
        poly.lineTo(x(k), y(p[k]));
      }
      canvas.drawPath(poly, pathPaint);
    }

    // EV line on top.
    final evPaint = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(ev)), evPaint);
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
  static double _sqrt(double v) => v <= 0 ? 0 : math.sqrt(v);

  @override
  bool shouldRepaint(_VariancePathsPainter old) =>
      old.paths != paths ||
      old.ev != ev ||
      old.sdPerUnit != sdPerUnit ||
      old.units != units ||
      old.primary != primary;
}
