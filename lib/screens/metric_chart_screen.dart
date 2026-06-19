import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/session_model.dart';
import '../utils/helpers.dart';

/// The metrics that can be charted over time. Opened from the Stats tab
/// (Overview hero/stat tiles + Analytics summary rows).
enum StatMetric {
  profit,
  netAfterExpenses,
  winRate,
  hours,
  sessions,
  winLoss,
  buyIn,
  expenses,
  bb100,
  roi,
  itm,
  itmPct,
}

enum _Lookback { all, oneYear, sixMonths, threeMonths, oneMonth }

enum _Period { weekly, monthly, yearly }

// ─── Full-screen metric chart ─────────────────────────────────────────────────

/// Full-screen time-series chart for a single [StatMetric]. Every metric shares
/// the same shell: a Per-period/Cumulative toggle and a Graph/Table toggle, plus
/// a Weekly/Monthly/Yearly period and an All/1Y/6M/3M/1M lookback.
///
/// [sessions] must already be game-type filtered by the caller.
const _periodLabels = {
  _Period.weekly: 'Weekly',
  _Period.monthly: 'Monthly',
  _Period.yearly: 'Yearly',
};

const _lookbackLabels = {
  _Lookback.all: 'All',
  _Lookback.oneYear: '1Y',
  _Lookback.sixMonths: '6M',
  _Lookback.threeMonths: '3M',
  _Lookback.oneMonth: '1M',
};

class MetricChartScreen extends StatefulWidget {
  final StatMetric metric;
  final List<SessionModel> sessions;
  final String displayCurrency;

  /// Read-only labels for the Stats-tab filters that produced [sessions] (game
  /// type, date range, currency, country, venue, location). Rendered as chips
  /// under the title so the chart isn't "blind" to its filter context.
  final List<String> activeFilters;

  const MetricChartScreen({
    super.key,
    required this.metric,
    required this.sessions,
    required this.displayCurrency,
    this.activeFilters = const [],
  });

  @override
  State<MetricChartScreen> createState() => _MetricChartScreenState();
}

class _MetricChartScreenState extends State<MetricChartScreen> {
  // Period + lookback live here so they can sit in the AppBar (the
  // Per-period/Cumulative + Graph/Table toggles stay inside the chart body).
  _Period _period = _Period.monthly;
  _Lookback _lookback = _Lookback.all;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(widget.metric, widget.displayCurrency);
    return Scaffold(
      appBar: AppBar(
        title: Text(spec.title),
        // Period + timeframe live on a slim strip below the title so they
        // don't squeeze (and truncate) the title itself.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menu<_Period>(_period, _periodLabels,
                      (v) => setState(() => _period = v)),
                  const SizedBox(width: 8),
                  _menu<_Lookback>(_lookback, _lookbackLabels,
                      (v) => setState(() => _lookback = v)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.activeFilters.isNotEmpty) _filterChips(context),
            Expanded(
              child: spec.isWinLoss
                  ? _WinLossChart(
                      sessions: widget.sessions,
                      period: _period,
                      lookback: _lookback,
                    )
                  : _MetricChart(
                      sessions: widget.sessions,
                      displayCurrency: widget.displayCurrency,
                      spec: spec,
                      period: _period,
                      lookback: _lookback,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu<T>(
          T value, Map<T, String> labels, ValueChanged<T> onSelected) =>
      PopupMenuButton<T>(
        initialValue: value,
        tooltip: '',
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final e in labels.entries)
            PopupMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(labels[value]!,
                  style: Theme.of(context).textTheme.labelLarge),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      );

  Widget _filterChips(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final f in widget.activeFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(f,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

// ─── Metric spec (binds a metric to its aggregate + formatting) ───────────────

double _zeroAgg(List<SessionModel> _) => 0;
String _emptyFmt(double _) => '';

class _MetricSpec {
  final String title;
  final bool isWinLoss;

  /// Aggregates a window of sessions into the metric's value. Per-period mode
  /// passes that period's sessions; cumulative mode passes the expanding window
  /// of all sessions up to and including the period.
  final double Function(List<SessionModel>) aggregate;
  final String Function(double) headline; // tooltip + headline + value cell
  final String Function(double) axisLabel; // compact axis tick
  final String valueLabel; // table value-column header
  final bool signed; // green/red coloring
  final bool rich; // profit/net → extra $/hr + Hrs table columns

  const _MetricSpec({
    required this.title,
    required this.aggregate,
    required this.headline,
    required this.axisLabel,
    required this.valueLabel,
    this.signed = false,
    this.rich = false,
  }) : isWinLoss = false;

  const _MetricSpec.winLoss()
      : title = 'Wins vs Losses',
        isWinLoss = true,
        aggregate = _zeroAgg,
        headline = _emptyFmt,
        axisLabel = _emptyFmt,
        valueLabel = '',
        signed = false,
        rich = false;
}

_MetricSpec _specFor(StatMetric m, String cur) {
  final sym = currencySymbol(cur);
  double pl(SessionModel s) => convertCurrency(s.profitLoss, s.currency, cur);
  double exp(SessionModel s) => convertCurrency(s.totalExpenses, s.currency, cur);
  double buyin(SessionModel s) => convertCurrency(s.buyIn, s.currency, cur);
  double hours(List<SessionModel> l) =>
      l.fold(0, (a, s) => a + s.durationMinutes) / 60.0;

  String money(double v) => formatPL(v, sym);
  String moneyAxis(double v) => _compactMoney(v, sym);
  String plainAxis(double v) => _compactNum(v);

  switch (m) {
    case StatMetric.profit:
      return _MetricSpec(
        title: 'Profit',
        aggregate: (l) => l.fold(0.0, (a, s) => a + pl(s)),
        headline: money,
        axisLabel: moneyAxis,
        valueLabel: 'Profit',
        signed: true,
        rich: true,
      );
    case StatMetric.netAfterExpenses:
      return _MetricSpec(
        title: 'Net Profit',
        aggregate: (l) => l.fold(0.0, (a, s) => a + pl(s) - exp(s)),
        headline: money,
        axisLabel: moneyAxis,
        valueLabel: 'Net',
        signed: true,
        rich: true,
      );
    case StatMetric.winRate:
      return _MetricSpec(
        title: 'Win Rate',
        aggregate: (l) {
          final h = hours(l);
          final total = l.fold(0.0, (a, s) => a + pl(s));
          return h > 0 ? total / h : 0.0;
        },
        headline: (v) => '${money(v)}/hr',
        axisLabel: moneyAxis,
        valueLabel: '$sym/hr',
        signed: true,
      );
    case StatMetric.hours:
      return _MetricSpec(
        title: 'Hours Played',
        aggregate: hours,
        headline: (v) => formatHours(v),
        axisLabel: (v) => '${v.round()}',
        valueLabel: 'Hours',
      );
    case StatMetric.sessions:
      return _MetricSpec(
        title: 'Sessions',
        aggregate: (l) => l.length.toDouble(),
        headline: (v) => '${v.round()}',
        axisLabel: plainAxis,
        valueLabel: 'Sessions',
      );
    case StatMetric.buyIn:
      return _MetricSpec(
        title: 'Total Buy-In',
        aggregate: (l) => l.fold(0.0, (a, s) => a + buyin(s)),
        headline: (v) => formatAmount(v, cur),
        axisLabel: moneyAxis,
        valueLabel: 'Buy-In',
      );
    case StatMetric.expenses:
      return _MetricSpec(
        title: 'Expenses',
        aggregate: (l) => l.fold(0.0, (a, s) => a + exp(s)),
        headline: (v) => formatAmount(v, cur),
        axisLabel: moneyAxis,
        valueLabel: 'Expenses',
      );
    case StatMetric.bb100:
      return _MetricSpec(
        title: 'BB / 100',
        aggregate: (l) => calcBB100(l) ?? 0.0,
        headline: formatBB100,
        axisLabel: (v) => '${v.round()}',
        valueLabel: 'BB/100',
        signed: true,
      );
    case StatMetric.roi:
      return _MetricSpec(
        title: 'Tournament ROI',
        aggregate: (l) {
          final b = l.fold(0.0, (a, s) => a + buyin(s));
          final p = l.fold(0.0, (a, s) => a + pl(s));
          return b > 0 ? p / b * 100 : 0.0;
        },
        headline: formatROI,
        axisLabel: (v) => '${v.round()}%',
        valueLabel: 'ROI',
        signed: true,
      );
    case StatMetric.itm:
      return _MetricSpec(
        title: 'In the Money',
        aggregate: (l) => l
            .where((s) => isSessionItm(s.prizeWon, s.profitLoss))
            .length
            .toDouble(),
        headline: (v) => '${v.round()}',
        axisLabel: plainAxis,
        valueLabel: 'ITM',
      );
    case StatMetric.itmPct:
      return _MetricSpec(
        title: 'ITM %',
        aggregate: (l) {
          if (l.isEmpty) return 0.0;
          final itm =
              l.where((s) => isSessionItm(s.prizeWon, s.profitLoss)).length;
          return itm / l.length * 100;
        },
        headline: (v) => '${v.round()}%',
        axisLabel: (v) => '${v.round()}%',
        valueLabel: 'ITM %',
      );
    case StatMetric.winLoss:
      return const _MetricSpec.winLoss();
  }
}

// ─── Shared lookback / period helpers ─────────────────────────────────────────

List<SessionModel> _applyLookback(List<SessionModel> sessions, _Lookback lb) {
  if (lb == _Lookback.all) return sessions;
  final days = switch (lb) {
    _Lookback.oneMonth => 30,
    _Lookback.threeMonths => 90,
    _Lookback.sixMonths => 180,
    _Lookback.oneYear => 365,
    _Lookback.all => 0,
  };
  final cutoff = DateTime.now().subtract(Duration(days: days));
  return sessions.where((s) {
    final d = DateTime.tryParse(s.date);
    return d != null && d.isAfter(cutoff);
  }).toList();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _weekKey(String dateStr) {
  final date = DateTime.tryParse(dateStr) ?? DateTime.now();
  final monday = date.subtract(Duration(days: date.weekday - 1));
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

String _periodKey(String dateStr, _Period period) => switch (period) {
      _Period.weekly => _weekKey(dateStr),
      _Period.monthly =>
        dateStr.length >= 7 ? dateStr.substring(0, 7) : dateStr,
      _Period.yearly => dateStr.length >= 4 ? dateStr.substring(0, 4) : dateStr,
    };

String _periodLabel(String key, _Period period) {
  if (period == _Period.weekly) {
    final date = DateTime.tryParse(key) ?? DateTime.now();
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return "${_months[date.month - 1]} ${date.day} '$yy";
  }
  if (period == _Period.monthly) {
    final parts = key.split('-');
    final month =
        (int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1).clamp(1, 12);
    final yearSuffix = parts[0].length >= 4 ? parts[0].substring(2) : parts[0];
    return "${_months[month - 1]} '$yearSuffix";
  }
  return key; // yearly
}

String _compactMoney(double v, String sym) {
  final abs = v.abs();
  final sign = v >= 0 ? '+' : '-';
  if (abs >= 10000) return '$sign$sym${(abs / 1000).toStringAsFixed(0)}k';
  if (abs >= 1000) return '$sign$sym${(abs / 1000).toStringAsFixed(1)}k';
  return '$sign$sym${abs.toStringAsFixed(0)}';
}

String _compactNum(double v) {
  final abs = v.abs();
  if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return '${v.round()}';
}

Widget _emptyChart(BuildContext context, String message) => Center(
      child: Text(message,
          style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.75),
              fontSize: 13)),
    );

/// The two view toggles that stay below the chart: Per-period/Cumulative and
/// Graph/Table, on one horizontally-scrollable row (period + lookback live in
/// the AppBar).
Widget _aggViewRow(
  bool cumulative,
  bool table,
  ValueChanged<bool> onAgg,
  ValueChanged<bool> onView,
) {
  Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: selected,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
        ),
      );
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        chip('Per-period', !cumulative, () => onAgg(false)),
        chip('Cumulative', cumulative, () => onAgg(true)),
        const SizedBox(width: 16),
        chip('Graph', !table, () => onView(false)),
        chip('Table', table, () => onView(true)),
      ],
    ),
  );
}

bool get _touchEnabled => kIsWeb || !Platform.isWindows;

int _labelEvery(double width, int count) {
  final maxLabels = (width / 48).floor().clamp(2, count);
  return (count / maxLabels).ceil().clamp(1, count);
}

/// Rotated, thinned bottom-axis label — prevents weekly/monthly labels from
/// overlapping. Only every [labelEvery]-th label is shown.
Widget _rotatedBottomTitle(TitleMeta meta, List<String> keys, _Period period,
    int index, int labelEvery) {
  if (index < 0 || index >= keys.length || index % labelEvery != 0) {
    return const SizedBox.shrink();
  }
  return SideTitleWidget(
    axisSide: meta.axisSide,
    space: 6,
    child: Transform.rotate(
      angle: -0.6, // ~ -34°
      alignment: Alignment.topRight,
      child: Text(_periodLabel(keys[index], period),
          maxLines: 1, style: const TextStyle(fontSize: 9)),
    ),
  );
}

// ─── Generic metric chart (per-period / cumulative × graph / table) ───────────

class _MetricChart extends StatefulWidget {
  final List<SessionModel> sessions;
  final String displayCurrency;
  final _MetricSpec spec;
  final _Period period;
  final _Lookback lookback;

  const _MetricChart({
    required this.sessions,
    required this.displayCurrency,
    required this.spec,
    required this.period,
    required this.lookback,
  });

  @override
  State<_MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<_MetricChart> {
  bool _cumulative = false;
  bool _table = false;
  _Period get _period => widget.period;
  _Lookback get _lookback => widget.lookback;
  // Weekly/monthly tables group by year, expanded by default; a year is
  // collapsed only if the user taps it (so this starts empty).
  final Set<String> _collapsedYears = {};

  _MetricSpec get _spec => widget.spec;

  double _hours(List<SessionModel> l) =>
      l.fold(0, (a, s) => a + s.durationMinutes) / 60.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lb = _applyLookback(widget.sessions, _lookback);

    // Group by period (chronological — keys are sortable strings).
    final groups = <String, List<SessionModel>>{};
    for (final s in lb) {
      groups.putIfAbsent(_periodKey(s.date, _period), () => []).add(s);
    }
    final keys = groups.keys.toList()..sort();

    // Expanding windows for cumulative mode.
    final cum = <String, List<SessionModel>>{};
    final acc = <SessionModel>[];
    for (final k in keys) {
      acc.addAll(groups[k]!);
      cum[k] = List.of(acc);
    }

    List<SessionModel> windowFor(String k) =>
        _cumulative ? cum[k]! : groups[k]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lb.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _spec.headline(_spec.aggregate(lb)),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: _table
              ? SingleChildScrollView(
                  child: _buildTable(context, keys, windowFor))
              : (keys.length < 2
                  ? _emptyChart(context, 'Need at least 2 periods of data')
                  : LayoutBuilder(
                      builder: (_, c) =>
                          _graph(context, groups, cum, keys, c.maxWidth))),
        ),
        const SizedBox(height: 12),
        _aggViewRow(
          _cumulative,
          _table,
          (v) => setState(() => _cumulative = v),
          (v) => setState(() => _table = v),
        ),
      ],
    );
  }

  // ── Graph ───────────────────────────────────────────────────────────────

  Widget _graph(BuildContext context, Map<String, List<SessionModel>> groups,
      Map<String, List<SessionModel>> cum, List<String> keys, double width) {
    return _cumulative
        ? _lineChart(context, cum, keys, width)
        : _barChart(context, groups, keys, width);
  }

  Widget _barChart(BuildContext context, Map<String, List<SessionModel>> groups,
      List<String> keys, double width) {
    final theme = Theme.of(context);
    final values = [for (final k in keys) _spec.aggregate(groups[k]!)];
    final maxV = values.fold(0.0, (a, v) => math.max(a, v));
    final minV = values.fold(0.0, (a, v) => math.min(a, v));
    final positive = theme.colorScheme.primary;
    final labelEvery = _labelEvery(width, keys.length);

    Color colorFor(double v) =>
        _spec.signed ? (v >= 0 ? Colors.green : Colors.red) : positive;

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxV <= 0 ? 1 : maxV * 1.15,
      minY: minV < 0 ? minV * 1.15 : 0,
      barTouchData: BarTouchData(
        enabled: _touchEnabled,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => theme.colorScheme.inverseSurface,
          getTooltipItem: (group, _, rod, _) => BarTooltipItem(
            '${_periodLabel(keys[group.x], _period)}\n${_spec.headline(rod.toY)}',
            TextStyle(
                color: theme.colorScheme.onInverseSurface,
                fontSize: 11,
                height: 1.4),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < keys.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: values[i],
              color: colorFor(values[i]),
              width: math.max(4, (220 / keys.length)).clamp(4, 18).toDouble(),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ]),
      ],
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, _) => Text(_spec.axisLabel(v),
                style: const TextStyle(fontSize: 9),
                textAlign: TextAlign.right),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => _rotatedBottomTitle(
                meta, keys, _period, v.toInt(), labelEvery),
          ),
        ),
      ),
    ));
  }

  Widget _lineChart(BuildContext context, Map<String, List<SessionModel>> cum,
      List<String> keys, double width) {
    final theme = Theme.of(context);
    final values = [for (final k in keys) _spec.aggregate(cum[k]!)];
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])
    ];
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs();
    final pad = span == 0 ? (maxV.abs() * 0.2 + 1) : span * 0.15;
    final color = _spec.signed
        ? (values.last >= 0 ? Colors.green : Colors.red)
        : theme.colorScheme.primary;
    final labelEvery = _labelEvery(width, keys.length);

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withAlpha(30)),
        ),
      ],
      lineTouchData: LineTouchData(
        enabled: _touchEnabled,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => theme.colorScheme.inverseSurface,
          getTooltipItems: (touched) => touched.map((spot) {
            final idx = spot.x.toInt().clamp(0, keys.length - 1);
            return LineTooltipItem(
              '${_periodLabel(keys[idx], _period)}\n${_spec.headline(spot.y)}',
              TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontSize: 11,
                  height: 1.4),
            );
          }).toList(),
        ),
      ),
      minY: minV - pad,
      maxY: maxV + pad,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (v, _) => Text(_spec.axisLabel(v),
                style: const TextStyle(fontSize: 9),
                textAlign: TextAlign.right),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => _rotatedBottomTitle(
                meta, keys, _period, v.toInt(), labelEvery),
          ),
        ),
      ),
    ));
  }

  // ── Table ────────────────────────────────────────────────────────────────
  // Yearly → flat. Weekly/monthly → grouped under collapsible year headers,
  // expanded by default (the full screen has room to show everything).

  Widget _buildTable(
    BuildContext context,
    List<String> keys,
    List<SessionModel> Function(String) windowFor,
  ) {
    final theme = Theme.of(context);
    if (keys.isEmpty) return _emptyChart(context, 'No data for this view');

    if (_period == _Period.yearly) {
      final ordered = [...keys]..sort((a, b) => b.compareTo(a));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tableHeader(theme),
          const Divider(height: 1),
          for (final k in ordered) ...[
            _dataRow(theme, _periodLabel(k, _period), windowFor(k)),
            Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],
        ],
      );
    }

    final byYear = <String, List<String>>{};
    for (final k in keys) {
      byYear.putIfAbsent(k.substring(0, 4), () => []).add(k);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tableHeader(theme),
        const Divider(height: 1),
        for (final year in years)
          _yearSection(theme, year, byYear[year]!, windowFor),
      ],
    );
  }

  Widget _yearSection(ThemeData theme, String year, List<String> periodKeys,
      List<SessionModel> Function(String) windowFor) {
    final isExpanded = !_collapsedYears.contains(year);
    final sortedKeys = [...periodKeys]..sort((a, b) => b.compareTo(a));
    final lastKey = periodKeys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    final yearWindow = _cumulative
        ? windowFor(lastKey)
        : [for (final k in periodKeys) ...windowFor(k)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _collapsedYears.add(year);
            } else {
              _collapsedYears.remove(year);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(year,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                ..._valueCells(theme, yearWindow),
              ],
            ),
          ),
        ),
        if (isExpanded)
          for (final k in sortedKeys) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _dataRow(theme, _periodLabel(k, _period), windowFor(k)),
            ),
            Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],
      ],
    );
  }

  Widget _tableHeader(ThemeData theme) {
    final sym = currencySymbol(widget.displayCurrency);
    final hs = theme.textTheme.titleSmall
        ?.copyWith(color: theme.colorScheme.outline, fontWeight: FontWeight.bold);
    Widget h(String t, int flex, {bool right = true}) => Expanded(
          flex: flex,
          child: Text(t,
              style: hs,
              maxLines: 2,
              textAlign: right ? TextAlign.right : TextAlign.left),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _spec.rich
            ? [
                h('Period', 3, right: false),
                h('${_spec.valueLabel} ($sym)', 3),
                h('#', 1),
                h('$sym/hr', 2),
                h('Hrs', 2),
              ]
            : [
                h('Period', 3, right: false),
                h(_spec.valueLabel, 3),
                h('#', 1),
              ],
      ),
    );
  }

  List<Widget> _valueCells(ThemeData theme, List<SessionModel> w) {
    final value = _spec.aggregate(w);
    final count = w.length;
    final color = _spec.signed ? (value >= 0 ? Colors.green : Colors.red) : null;
    final outline = theme.colorScheme.outline;
    // FittedBox.scaleDown keeps each value on ONE line — large cumulative
    // figures shrink to fit rather than wrapping to a second row.
    Widget cell(String t, int flex,
            {Color? c, bool bold = false, bool big = true}) =>
        Expanded(
          flex: flex,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(t,
                maxLines: 1,
                style: (big
                        ? theme.textTheme.bodyLarge
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                        color: c, fontWeight: bold ? FontWeight.bold : null)),
          ),
        );

    if (_spec.rich) {
      final hours = _hours(w);
      final perHr = hours > 0 ? value / hours : 0.0;
      return [
        cell(formatPL(value, ''), 3, c: color, bold: true),
        cell('$count', 1, c: outline, big: false),
        cell(formatPL(perHr, ''), 2,
            c: perHr >= 0 ? Colors.green : Colors.red, bold: true),
        cell(hours.toStringAsFixed(0), 2, c: outline, big: false),
      ];
    }
    return [
      cell(_spec.headline(value), 3, c: color, bold: true),
      cell('$count', 1, c: outline, big: false),
    ];
  }

  Widget _dataRow(ThemeData theme, String label, List<SessionModel> window) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
                flex: 3,
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge)),
            ..._valueCells(theme, window),
          ],
        ),
      );
}

// ─── Wins-vs-Losses chart (two series) ────────────────────────────────────────

class _WinLossChart extends StatefulWidget {
  final List<SessionModel> sessions;
  final _Period period;
  final _Lookback lookback;

  const _WinLossChart({
    required this.sessions,
    required this.period,
    required this.lookback,
  });

  @override
  State<_WinLossChart> createState() => _WinLossChartState();
}

class _WinLossChartState extends State<_WinLossChart> {
  bool _cumulative = false;
  bool _table = false;
  _Period get _period => widget.period;
  _Lookback get _lookback => widget.lookback;
  final Set<String> _collapsedYears = {};

  ({int wins, int losses}) _tally(List<SessionModel> sessions) {
    final wins = sessions.where((s) => s.profitLoss > 0).length;
    return (wins: wins, losses: sessions.length - wins);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lb = _applyLookback(widget.sessions, _lookback);

    final groups = <String, List<SessionModel>>{};
    for (final s in lb) {
      groups.putIfAbsent(_periodKey(s.date, _period), () => []).add(s);
    }
    final keys = groups.keys.toList()..sort();
    final cum = <String, List<SessionModel>>{};
    final acc = <SessionModel>[];
    for (final k in keys) {
      acc.addAll(groups[k]!);
      cum[k] = List.of(acc);
    }
    List<SessionModel> windowFor(String k) =>
        _cumulative ? cum[k]! : groups[k]!;

    final total = _tally(lb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lb.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                _legendDot(Colors.green),
                Text('  ${total.wins} W',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                _legendDot(Colors.red),
                Text('  ${total.losses} L',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        Expanded(
          child: _table
              ? SingleChildScrollView(
                  child: _buildTable(context, keys, windowFor))
              : (keys.length < 2
                  ? _emptyChart(context, 'Need at least 2 periods of data')
                  : LayoutBuilder(
                      builder: (_, c) =>
                          _graph(context, groups, cum, keys, c.maxWidth))),
        ),
        const SizedBox(height: 12),
        _aggViewRow(
          _cumulative,
          _table,
          (v) => setState(() => _cumulative = v),
          (v) => setState(() => _table = v),
        ),
      ],
    );
  }

  Widget _legendDot(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  // ── Graph ───────────────────────────────────────────────────────────────

  Widget _graph(BuildContext context, Map<String, List<SessionModel>> groups,
      Map<String, List<SessionModel>> cum, List<String> keys, double width) {
    return _cumulative
        ? _lineChart(context, cum, keys, width)
        : _barChart(context, groups, keys, width);
  }

  Widget _barChart(BuildContext context, Map<String, List<SessionModel>> groups,
      List<String> keys, double width) {
    final theme = Theme.of(context);
    final tallies = [for (final k in keys) _tally(groups[k]!)];
    final maxV = tallies
        .fold(0, (a, t) => math.max(a, math.max(t.wins, t.losses)))
        .toDouble();
    final labelEvery = _labelEvery(width, keys.length);
    final rodWidth = math.max(3, (160 / keys.length)).clamp(3, 12).toDouble();

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxV <= 0 ? 1 : maxV * 1.15,
      barTouchData: BarTouchData(
        enabled: _touchEnabled,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => theme.colorScheme.inverseSurface,
          getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
            '${_periodLabel(keys[group.x], _period)}\n'
            '${rod.toY.round()} ${rodIndex == 0 ? 'wins' : 'losses'}',
            TextStyle(
                color: theme.colorScheme.onInverseSurface,
                fontSize: 11,
                height: 1.4),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < keys.length; i++)
          BarChartGroupData(x: i, barsSpace: 2, barRods: [
            BarChartRodData(
                toY: tallies[i].wins.toDouble(),
                color: Colors.green,
                width: rodWidth),
            BarChartRodData(
                toY: tallies[i].losses.toDouble(),
                color: Colors.red,
                width: rodWidth),
          ]),
      ],
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (v, _) =>
                Text('${v.round()}', style: const TextStyle(fontSize: 9)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => _rotatedBottomTitle(
                meta, keys, _period, v.toInt(), labelEvery),
          ),
        ),
      ),
    ));
  }

  Widget _lineChart(BuildContext context, Map<String, List<SessionModel>> cum,
      List<String> keys, double width) {
    final theme = Theme.of(context);
    final tallies = [for (final k in keys) _tally(cum[k]!)];
    final winSpots = [
      for (var i = 0; i < tallies.length; i++)
        FlSpot(i.toDouble(), tallies[i].wins.toDouble())
    ];
    final lossSpots = [
      for (var i = 0; i < tallies.length; i++)
        FlSpot(i.toDouble(), tallies[i].losses.toDouble())
    ];
    final maxV = tallies
        .fold(0, (a, t) => math.max(a, math.max(t.wins, t.losses)))
        .toDouble();
    final labelEvery = _labelEvery(width, keys.length);

    LineChartBarData line(List<FlSpot> spots, Color c) => LineChartBarData(
          spots: spots,
          isCurved: true,
          color: c,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        );

    return LineChart(LineChartData(
      lineBarsData: [line(winSpots, Colors.green), line(lossSpots, Colors.red)],
      lineTouchData: LineTouchData(
        enabled: _touchEnabled,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => theme.colorScheme.inverseSurface,
          getTooltipItems: (touched) => touched.map((spot) {
            final idx = spot.x.toInt().clamp(0, keys.length - 1);
            final isWin = spot.barIndex == 0;
            return LineTooltipItem(
              '${_periodLabel(keys[idx], _period)}\n'
              '${spot.y.round()} ${isWin ? 'wins' : 'losses'}',
              TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontSize: 11,
                  height: 1.4),
            );
          }).toList(),
        ),
      ),
      minY: 0,
      maxY: maxV <= 0 ? 1 : maxV * 1.15,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (v, _) =>
                Text('${v.round()}', style: const TextStyle(fontSize: 9)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => _rotatedBottomTitle(
                meta, keys, _period, v.toInt(), labelEvery),
          ),
        ),
      ),
    ));
  }

  // ── Table (yearly flat; weekly/monthly grouped by year, expanded) ─────────

  Widget _buildTable(
    BuildContext context,
    List<String> keys,
    List<SessionModel> Function(String) windowFor,
  ) {
    final theme = Theme.of(context);
    if (keys.isEmpty) return _emptyChart(context, 'No data for this view');

    if (_period == _Period.yearly) {
      final ordered = [...keys]..sort((a, b) => b.compareTo(a));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tableHeader(theme),
          const Divider(height: 1),
          for (final k in ordered) ...[
            _wlRow(theme, _periodLabel(k, _period), windowFor(k)),
            Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],
        ],
      );
    }

    final byYear = <String, List<String>>{};
    for (final k in keys) {
      byYear.putIfAbsent(k.substring(0, 4), () => []).add(k);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tableHeader(theme),
        const Divider(height: 1),
        for (final year in years)
          _yearSection(theme, year, byYear[year]!, windowFor),
      ],
    );
  }

  Widget _yearSection(ThemeData theme, String year, List<String> periodKeys,
      List<SessionModel> Function(String) windowFor) {
    final isExpanded = !_collapsedYears.contains(year);
    final sortedKeys = [...periodKeys]..sort((a, b) => b.compareTo(a));
    final lastKey = periodKeys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    final yearWindow = _cumulative
        ? windowFor(lastKey)
        : [for (final k in periodKeys) ...windowFor(k)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _collapsedYears.add(year);
            } else {
              _collapsedYears.remove(year);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(year,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                ..._wlCells(theme, yearWindow),
              ],
            ),
          ),
        ),
        if (isExpanded)
          for (final k in sortedKeys) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _wlRow(theme, _periodLabel(k, _period), windowFor(k)),
            ),
            Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],
      ],
    );
  }

  Widget _tableHeader(ThemeData theme) {
    final hs = theme.textTheme.titleSmall
        ?.copyWith(color: theme.colorScheme.outline, fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Period', style: hs)),
          Expanded(
              flex: 2,
              child: Text('W', style: hs, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('L', style: hs, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  List<Widget> _wlCells(ThemeData theme, List<SessionModel> w) {
    final t = _tally(w);
    Widget cell(int n, Color c) => Expanded(
        flex: 2,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text('$n',
              maxLines: 1,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: c, fontWeight: FontWeight.bold)),
        ));
    return [cell(t.wins, Colors.green), cell(t.losses, Colors.red)];
  }

  Widget _wlRow(ThemeData theme, String label, List<SessionModel> window) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
                flex: 3,
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge)),
            ..._wlCells(theme, window),
          ],
        ),
      );
}
