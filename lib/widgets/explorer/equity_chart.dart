// GTO Explorer — the cumulative equity-distribution chart: each player's
// range sorted worst→best (x = position in range, reach-weighted; y = equity
// vs the opponent's current range). The standard solver visual for who holds
// the nuts advantage vs the range advantage. CustomPaint (not fl_chart — the
// project's Windows touch gotcha, and this needs only two polylines).
//
// Interactive: hovering (or press-dragging on touch) shows a crosshair with
// each curve's combo + equity at that range percentile, and reports the
// primary (acting player's) hovered combo upward so the strategy grid can
// illuminate its cell; [highlightCombos] does the reverse (grid hover →
// emphasized dots on the primary curve).

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import '../../explorer/grid_aggregation.dart';

class EquityCurveSeries {
  final String label; // 'BTN (to act)'
  final Color color;
  final List<EquityCurvePoint> points;
  final List<String> comboNames; // comboId → 'AhKs' (for the tooltip)
  EquityCurveSeries(this.label, this.color, this.points, this.comboNames);
}

class EquityChart extends StatefulWidget {
  final List<EquityCurveSeries> series;

  /// Combo ids (of the FIRST series — the acting player) to emphasize,
  /// driven by grid-cell hover.
  final Set<int>? highlightCombos;

  /// Fired with the first series' combo under the crosshair (null on exit).
  final void Function(int? comboId)? onHoverCombo;
  const EquityChart({
    super.key,
    required this.series,
    this.highlightCombos,
    this.onHoverCombo,
  });

  @override
  State<EquityChart> createState() => _EquityChartState();
}

class _EquityChartState extends State<EquityChart> {
  double? _hoverX; // 0..1 in plot space

  void _setHover(double? x) {
    if (x == _hoverX) return;
    setState(() => _hoverX = x);
    final onHover = widget.onHoverCombo;
    if (onHover == null) return;
    if (x == null || widget.series.isEmpty) {
      onHover(null);
      return;
    }
    final p = _nearestPoint(widget.series.first.points, x);
    onHover(p?.comboId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          children: [
            for (final s in widget.series.where((s) => s.points.isNotEmpty))
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 14, height: 3, color: s.color),
                const SizedBox(width: 5),
                Text(s.label,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ]),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            double? toPlotX(Offset local) {
              final w = constraints.maxWidth -
                  _EquityChartPainter.padLeft -
                  _EquityChartPainter.padRight;
              if (w <= 0) return null;
              return ((local.dx - _EquityChartPainter.padLeft) / w)
                  .clamp(0.0, 1.0);
            }

            return MouseRegion(
              onHover: (e) => _setHover(toPlotX(e.localPosition)),
              onExit: (_) => _setHover(null),
              child: GestureDetector(
                // Touch: press-drag scrubs the crosshair.
                onPanDown: (d) => _setHover(toPlotX(d.localPosition)),
                onPanUpdate: (d) => _setHover(toPlotX(d.localPosition)),
                onPanEnd: (_) => _setHover(null),
                onPanCancel: () => _setHover(null),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _EquityChartPainter(
                      widget.series,
                      gridColor: scheme.outlineVariant.withValues(alpha: 0.35),
                      labelColor: scheme.onSurfaceVariant,
                      tooltipBg: scheme.surfaceContainerHighest,
                      hoverX: _hoverX,
                      highlightCombos: widget.highlightCombos,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 2),
        Text('range, worst → best hands',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

EquityCurvePoint? _nearestPoint(List<EquityCurvePoint> points, double x) {
  EquityCurvePoint? best;
  var bestD = double.infinity;
  for (final p in points) {
    final d = (p.x - x).abs();
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

/// 'AhKs' → 'A♥K♠' for the tooltip.
String _prettyCombo(String name) {
  if (name.length != 4) return name;
  final s1 = kSuitChars.indexOf(name[1]);
  final s2 = kSuitChars.indexOf(name[3]);
  if (s1 < 0 || s2 < 0) return name;
  return '${name[0]}${kSuitSymbols[s1]}${name[2]}${kSuitSymbols[s2]}';
}

class _EquityChartPainter extends CustomPainter {
  final List<EquityCurveSeries> series;
  final Color gridColor;
  final Color labelColor;
  final Color tooltipBg;
  final double? hoverX;
  final Set<int>? highlightCombos;
  _EquityChartPainter(
    this.series, {
    required this.gridColor,
    required this.labelColor,
    required this.tooltipBg,
    required this.hoverX,
    required this.highlightCombos,
  });

  static const padLeft = 30.0;
  static const padRight = 4.0;
  static const _padBottom = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
        padLeft, 4, size.width - padRight, size.height - _padBottom);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizontal gridlines + y labels at 0/25/50/75/100% equity.
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = TextPainter(
        text: TextSpan(
            text: '${i * 25}',
            style: TextStyle(fontSize: 9, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plot.left - tp.width - 5, y - tp.height / 2));
    }

    Offset toCanvas(EquityCurvePoint p) => Offset(
          plot.left + plot.width * p.x,
          plot.bottom - plot.height * p.y.clamp(0.0, 1.0),
        );

    for (final s in series) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final o = toCanvas(s.points[i]);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    // Grid-hover emphasis: dots on the PRIMARY curve's points for the
    // hovered cell's combos.
    final hl = highlightCombos;
    if (hl != null && hl.isNotEmpty && series.isNotEmpty) {
      final dot = Paint()..color = series.first.color;
      final ring = Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final p in series.first.points) {
        if (!hl.contains(p.comboId)) continue;
        final o = toCanvas(p);
        canvas.drawCircle(o, 4, dot);
        canvas.drawCircle(o, 4, ring);
      }
    }

    // Crosshair + tooltip.
    final hx = hoverX;
    if (hx == null) return;
    final cx = plot.left + plot.width * hx;
    canvas.drawLine(
      Offset(cx, plot.top),
      Offset(cx, plot.bottom),
      Paint()
        ..color = labelColor.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    final lines = <(Color, String)>[];
    for (final s in series) {
      final p = _nearestPoint(s.points, hx);
      if (p == null) continue;
      canvas.drawCircle(toCanvas(p), 3.5, Paint()..color = s.color);
      final name =
          p.comboId < s.comboNames.length ? s.comboNames[p.comboId] : '?';
      lines.add((
        s.color,
        '${s.label.split(' ').first} ${_prettyCombo(name)} '
            '${(p.y * 100).toStringAsFixed(1)}%'
      ));
    }
    if (lines.isEmpty) return;
    final tps = [
      for (final l in lines)
        TextPainter(
          text: TextSpan(
              text: l.$2,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: l.$1)),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final boxW = tps.fold(0.0, (m, t) => t.width > m ? t.width : m) + 16;
    final boxH = tps.fold(0.0, (s, t) => s + t.height) + 12;
    // Side-aware: keep the box inside the plot.
    final left = cx + 8 + boxW > plot.right ? cx - 8 - boxW : cx + 8;
    final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, plot.top + 4, boxW, boxH),
        const Radius.circular(6));
    canvas.drawRRect(box, Paint()..color = tooltipBg.withValues(alpha: 0.95));
    var y = plot.top + 10;
    for (final t in tps) {
      t.paint(canvas, Offset(left + 8, y));
      y += t.height;
    }
  }

  @override
  bool shouldRepaint(_EquityChartPainter old) =>
      old.series != series ||
      old.hoverX != hoverX ||
      old.highlightCombos != highlightCombos;
}
