// GTO Explorer — the 13×13 strategy grid: one CustomPaint for all 169 cells
// (stacked per-action frequency bars, opacity by range presence), which is
// far cheaper than 169 widgets and repaints only when the node changes.

import 'package:flutter/material.dart';

import '../../explorer/grid_aggregation.dart';

class StrategyGrid extends StatelessWidget {
  final List<List<GridCellAgg?>> cells;
  final List<Color> actionColors;
  const StrategyGrid(
      {super.key, required this.cells, required this.actionColors});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GridPainter(cells, actionColors),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final List<List<GridCellAgg?>> cells;
  final List<Color> colors;
  _GridPainter(this.cells, this.colors);

  static const _bg = Color(0xFF141914);
  static const _absent = Color(0xFF1D231D);
  static const _label = Color(0xB3FFFFFF); // white70
  static const _labelDim = Color(0x40FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / 13;
    final ch = size.height / 13;
    final paintFill = Paint()..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, paintFill..color = _bg);

    final labelStyle = TextStyle(
      color: _label,
      fontSize: (ch * 0.24).clamp(7.0, 12.0),
      fontWeight: FontWeight.w600,
    );

    for (var row = 0; row < 13; row++) {
      for (var col = 0; col < 13; col++) {
        final rect = Rect.fromLTWH(col * cw, row * ch, cw - 1, ch - 1);
        final cell = cells[row][col];
        if (cell == null || cell.reach <= 0) {
          canvas.drawRect(rect, paintFill..color = _absent);
          _text(canvas, rect, _handAt(row, col, cell), labelStyle.copyWith(color: _labelDim));
          continue;
        }
        // Range presence dims cells that are mostly folded out already.
        final alpha = 0.30 + 0.70 * cell.presence;
        canvas.drawRect(rect, paintFill..color = _absent);
        var x = rect.left;
        for (var a = 0; a < cell.freqs.length && a < colors.length; a++) {
          final w = rect.width * cell.freqs[a].clamp(0.0, 1.0);
          if (w <= 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(x, rect.top, w, rect.height),
            paintFill..color = colors[a].withValues(alpha: alpha),
          );
          x += w;
        }
        _text(canvas, rect, cell.hand, labelStyle);
      }
    }
  }

  String _handAt(int row, int col, GridCellAgg? cell) {
    if (cell != null) return cell.hand;
    // Absent cells still get their hand label (dimmed) for orientation.
    const ranks = ['A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2'];
    if (row == col) return ranks[row] + ranks[col];
    return row < col
        ? '${ranks[row]}${ranks[col]}s'
        : '${ranks[col]}${ranks[row]}o';
  }

  void _text(Canvas canvas, Rect rect, String s, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left + 2, rect.top + 1));
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cells != cells || old.colors != colors;
}
