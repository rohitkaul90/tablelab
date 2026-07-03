// GTO Explorer — the cumulative equity-distribution chart: each player's
// range sorted worst→best (x = position in range, reach-weighted; y = equity
// vs the opponent's current range). The standard solver visual for who holds
// the nuts advantage vs the range advantage. CustomPaint (not fl_chart — the
// project's Windows touch gotcha, and this needs only two polylines).

import 'package:flutter/material.dart';

import '../../explorer/grid_aggregation.dart';

class EquityCurveSeries {
  final String label; // 'BTN'
  final Color color;
  final List<EquityCurvePoint> points;
  EquityCurveSeries(this.label, this.color, this.points);
}

class EquityChart extends StatelessWidget {
  final List<EquityCurveSeries> series;
  const EquityChart({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          children: [
            for (final s in series.where((s) => s.points.isNotEmpty))
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
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _EquityChartPainter(
                series,
                gridColor: scheme.outlineVariant.withValues(alpha: 0.35),
                labelColor: scheme.onSurfaceVariant,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text('range, worst → best hands',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _EquityChartPainter extends CustomPainter {
  final List<EquityCurveSeries> series;
  final Color gridColor;
  final Color labelColor;
  _EquityChartPainter(this.series,
      {required this.gridColor, required this.labelColor});

  static const _padLeft = 30.0;
  static const _padBottom = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
        _padLeft, 4, size.width - 4, size.height - _padBottom);
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

    for (final s in series) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final dx = plot.left + plot.width * p.x;
        final dy = plot.bottom - plot.height * p.y.clamp(0.0, 1.0);
        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EquityChartPainter old) => old.series != series;
}
