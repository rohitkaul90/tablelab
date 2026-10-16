import 'dart:math' as math;
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
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
  // en_US on purpose: this formats typed input, and the value is parsed
  // back by stripping ',' — a locale separator would corrupt it.
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
    final l10n = context.l10n;
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
        missing = l10n.varianceStatsNeedCash;
      } else {
        _cashWr.text = wr.toStringAsFixed(1);
        _cashHands.text = _ThousandsFormatter._fmt.format(hands.round());
        if (sd != null) {
          _cashSd.text = sd.toStringAsFixed(0);
        } else {
          missing = l10n.varianceStatsCashSdShort;
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
        missing = l10n.varianceStatsNeedTourneys;
      } else {
        _tRoi.text = (pl / buyIn * 100).toStringAsFixed(1);
        _tCount.text = _ThousandsFormatter._fmt.format(t.length);
        if (sd != null) {
          _tSd.text = sd.toStringAsFixed(1);
        } else {
          missing = l10n.varianceStatsTourneySdShort;
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
    final l10n = context.l10n; // before the await below

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
      fail(l10n.varianceErrorMissing);
      return;
    }
    if (sd <= 0 || count <= 0) {
      fail(mode == 0
          ? l10n.varianceErrorCashNonPositive
          : l10n.varianceErrorTourneyNonPositive);
      return;
    }
    if (_mode == 0 ? _cashBankroll.text.isNotEmpty : _tBankroll.text.isNotEmpty) {
      if (bankroll == null || bankroll <= 0) {
        fail(l10n.varianceErrorBankroll);
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

  /// Scrub position on the results chart as a 0..1 fraction of the x-axis,
  /// or null (no crosshair). Set by tap/horizontal drag; cleared on a new
  /// calculation or reroll.
  double? _scrubFrac;

  Future<void> _run() async {
    final it = _lastInputs!;
    // Deterministic per input set (the app's seeded-visual convention) so the
    // same numbers always draw the same curves; "reroll" bumps the offset.
    final seed = Object.hash(it.mode, it.mean, it.sd, it.count, _seedOffset);

    setState(() {
      _error = null;
      _running = true;
      _scrubFrac = null;
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
    final l10n = context.l10n;
    final isCash = _mode == 0;

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: [
            ButtonSegment(value: 0, label: Text(l10n.varianceModeCash)),
            ButtonSegment(value: 1, label: Text(l10n.varianceModeTournament)),
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
          _field(_cashWr, l10n.varianceCashWinrate, l10n.varianceCashWinrateHint,
              signed: true),
          _field(_cashSd, l10n.varianceCashSd, l10n.varianceCashSdHint),
          _field(_cashHands, l10n.varianceCashHands, l10n.varianceCashHandsHint,
              thousands: true),
          _field(_cashBankroll, l10n.varianceCashBankroll,
              l10n.varianceBankrollHint, thousands: true),
        ] else ...[
          _field(_tRoi, l10n.varianceTourneyRoi, l10n.varianceTourneyRoiHint,
              signed: true),
          _field(_tSd, l10n.varianceTourneySd, l10n.varianceTourneySdHint),
          _field(_tCount, l10n.varianceTourneyCount,
              l10n.varianceTourneyCountHint, thousands: true),
          _field(_tBankroll, l10n.varianceTourneyBankroll,
              l10n.varianceBankrollHint, thousands: true),
        ],

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _running ? null : () => _calculate(),
                icon: const Icon(Icons.calculate_outlined),
                label: Text(l10n.varianceCalculate),
              ),
            ),
            const SizedBox(width: 8),
            // Flexible + ellipsis: longer languages (es/it) overflowed this
            // row by ~30px on a 360-wide phone beside the Calculate button.
            Flexible(
              child: TextButton.icon(
                onPressed: _running ? null : _useMyStats,
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(l10n.varianceUseMyStats,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
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
          _resultsSection(theme, l10n),
        ],
      ],
    );

    if (!widget.showScaffold) return body;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: Text(l10n.varianceTitle)),
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

  Widget _resultsSection(ThemeData theme, AppLocalizations l10n) {
    final r = _result!;
    final cash = _resultMode == 0;
    final unit = cash ? l10n.varianceUnitBb : l10n.varianceUnitBuyIns;
    final xLabel = cash ? l10n.varianceXHands : l10n.varianceXTournaments;
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
    // Unit once, after the range ("-1,200 to 3,400 bb"), as before l10n.
    String range(double lo, double hi) =>
        l10n.varianceRange(fmt(lo, dp: dp), fmt(hi, dp: dp), unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.varianceExpectedHeadline('${fmt(r.ev, dp: dp)} $unit'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: r.ev >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.varianceReroll,
              icon: const Icon(Icons.casino_outlined),
              onPressed: _running ? null : _reroll,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Chart ───────────────────────────────────────────────────────────
        SizedBox(
          height: 220,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void setScrub(double dx) => setState(() => _scrubFrac =
                  (dx / constraints.maxWidth).clamp(0.0, 1.0));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // onTapUp, NOT onTapDown: a touch that turns into a page
                // scroll cancels the tap and must not arm the crosshair.
                // Tapping near the existing crosshair dismisses it.
                onTapUp: (d) {
                  final f = _scrubFrac;
                  if (f != null &&
                      (d.localPosition.dx - f * constraints.maxWidth)
                              .abs() <
                          16) {
                    setState(() => _scrubFrac = null);
                  } else {
                    setScrub(d.localPosition.dx);
                  }
                },
                // Horizontal-only drag: a vertical drag must fall through to
                // the page scroll (equity_chart.dart lesson, PR #41).
                onHorizontalDragStart: (d) => setScrub(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setScrub(d.localPosition.dx),
                // Clip: on very narrow charts the tooltip box can exceed the
                // chart width and would otherwise paint over neighboring UI.
                child: ClipRect(
                    child: CustomPaint(
                  painter: _VariancePathsPainter(
                    paths: _paths!,
                    ev: r.ev,
                    sdPerUnit: _sdPerUnit!,
                    units: _units!,
                    primary: theme.colorScheme.primary,
                    onSurface: theme.colorScheme.onSurface,
                    outline: theme.colorScheme.outline,
                    surface: theme.colorScheme.surface,
                    scrubFrac: _scrubFrac,
                    fmtValue: (v) => '${fmt(v, dp: dp)} $unit',
                    fmtX: (v) =>
                        '${_ThousandsFormatter._fmt.format(v.round())} $xLabel',
                    xMax: xMax.toDouble(),
                    labels: (
                      expected: l10n.varianceTooltipExpected,
                      band: l10n.varianceTooltipBand,
                    ),
                  ),
                  child: const SizedBox.expand(),
                )),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.varianceChartCaption(
                '0 → ${_ThousandsFormatter._fmt.format(xMax.round())} $xLabel'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        const SizedBox(height: 16),

        _row(theme, l10n.variance70, range(r.ci70Low, r.ci70High)),
        _row(theme, l10n.variance95, range(r.ci95Low, r.ci95High)),
        _row(theme, l10n.varianceChanceLosing,
            '${(r.pLoss * 100).toStringAsFixed(1)}%'),
        if (r.riskOfRuin != null)
          _row(theme, l10n.varianceRiskOfRuin, _pct(r.riskOfRuin!)),
        if (r.bankrollForRoR5 != null)
          _row(theme, l10n.varianceBankroll5,
              '${_ThousandsFormatter._fmt.format(r.bankrollForRoR5!.ceil())} $unit'),
        if (r.bankrollForRoR1 != null)
          _row(theme, l10n.varianceBankroll1,
              '${_ThousandsFormatter._fmt.format(r.bankrollForRoR1!.ceil())} $unit'),
        if (_downswings != null) ...[
          _row(theme, l10n.varianceTypicalDownswing,
              '${_ThousandsFormatter._fmt.format(_downswings!.medianMaxDrawdown.round())} $unit'),
          _row(theme, l10n.varianceBadDownswing,
              '${_ThousandsFormatter._fmt.format(_downswings!.p95MaxDrawdown.round())} $unit'),
          if (_downswings!.pBustDuringHorizon != null)
            _row(theme, l10n.varianceBustChance,
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
              ? l10n.varianceDisclaimerCash
              : l10n.varianceDisclaimerTourney,
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
  final Color surface;

  /// Crosshair scrub position (0..1 fraction of the x-axis) or null. The
  /// tooltip shows the ANALYTIC values at that point (EV + 70%/95% bands),
  /// not the individual sample paths.
  final double? scrubFrac;
  final String Function(double) fmtValue;
  final String Function(double) fmtX;
  final double xMax;

  /// Localized tooltip line templates (built from AppLocalizations by the
  /// screen; the painter has no BuildContext).
  final ({
    String Function(String value) expected,
    String Function(String pct, String low, String high) band,
  }) labels;

  _VariancePathsPainter({
    required this.paths,
    required this.ev,
    required this.sdPerUnit,
    required this.units,
    required this.primary,
    required this.onSurface,
    required this.outline,
    required this.surface,
    required this.scrubFrac,
    required this.fmtValue,
    required this.fmtX,
    required this.xMax,
    required this.labels,
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

    _paintScrub(canvas, size, y);
  }

  /// Crosshair + tooltip at [scrubFrac]: vertical line, a dot on the EV
  /// line, and a boxed readout of x / expected / 70% / 95% at that point.
  /// The box flips to the left of the line when it would overflow the right
  /// edge and is clamped inside the chart on both axes.
  void _paintScrub(Canvas canvas, Size size, double Function(double) y) {
    final f = scrubFrac;
    if (f == null) return;
    final t = units * f;
    final sd = sdPerUnit * _sqrt(t);
    final mid = ev * f;
    final lx = size.width * f;

    canvas.drawLine(
        Offset(lx, 0),
        Offset(lx, size.height),
        Paint()
          ..color = onSurface.withValues(alpha: 0.45)
          ..strokeWidth = 1);
    canvas.drawCircle(Offset(lx, y(mid)), 3.5, Paint()..color = primary);

    final bold = TextStyle(
        fontSize: 11,
        height: 1.4,
        color: onSurface,
        fontWeight: FontWeight.bold);
    // intl (NumberFormat) exports its own TextDirection — qualify dart:ui's.
    final text = TextPainter(
      textDirection: ui.TextDirection.ltr,
      text: TextSpan(
        style: TextStyle(fontSize: 11, height: 1.4, color: onSurface),
        children: [
          TextSpan(text: '${fmtX(xMax * f)}\n', style: bold),
          TextSpan(
              text: '${labels.expected(fmtValue(mid))}\n',
              style: bold.copyWith(
                  color: mid >= 0 ? Colors.green : Colors.red)),
          TextSpan(
              text: '${labels.band('70%', fmtValue(mid - z70 * sd), fmtValue(mid + z70 * sd))}\n'),
          TextSpan(
              text: labels.band(
                  '95%', fmtValue(mid - z95 * sd), fmtValue(mid + z95 * sd))),
        ],
      ),
    )..layout();

    const padH = 8.0, padV = 6.0;
    final w = text.width + padH * 2;
    final h = text.height + padV * 2;
    var bx = lx + 10;
    if (bx + w > size.width - 2) bx = lx - 10 - w;
    bx = bx.clamp(2.0, _max(2.0, size.width - w - 2));
    final by = (y(mid) - h / 2).clamp(2.0, _max(2.0, size.height - h - 2));

    final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, w, h), const Radius.circular(6));
    canvas.drawRRect(box, Paint()..color = surface.withValues(alpha: 0.94));
    canvas.drawRRect(
        box,
        Paint()
          ..color = outline.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    text.paint(canvas, Offset(bx + padH, by + padV));
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
      old.primary != primary ||
      old.scrubFrac != scrubFrac ||
      // Tear-off identity changes when the locale's AppLocalizations does.
      old.labels != labels;
}
