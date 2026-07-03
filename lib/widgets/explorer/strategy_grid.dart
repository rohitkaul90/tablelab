// GTO Explorer — the 13×13 strategy grid: one CustomPaint for all 169 cells,
// which is far cheaper than 169 widgets and repaints only when the node (or
// lens) changes. Two lenses:
//  - strategy: stacked per-action frequency bars (solver colors)
//  - handClass: solid fill by the cell's reach-dominant DCE hand class — the
//    SAME classes the AI coaching FACTs quote, so explorer and coaching tell
//    one story.
// Cell opacity tracks range presence in both lenses. Tap a cell for the
// combo drill-down (handled by the screen via [onCellTap]).

import 'package:flutter/material.dart';

import '../../equity/card.dart';
import '../../equity/decision_context.dart';
import '../../explorer/grid_aggregation.dart';

enum GridLens { strategy, handClass }

/// Lens colors for the DCE hand classes — deliberately DISTINCT from the
/// action colors (green/red/blue) so the two lenses never read as each other.
const Map<HandClass, Color> kHandClassColors = {
  HandClass.air: Color(0xFF5C6560),
  HandClass.weakDraw: Color(0xFF4FA8A0),
  HandClass.strongDraw: Color(0xFF3E7BB8),
  HandClass.marginalMade: Color(0xFFC9A040),
  HandClass.strongMade: Color(0xFF7A4FB5),
};

String handClassShortLabel(HandClass hc) => switch (hc) {
      HandClass.air => 'Air',
      HandClass.weakDraw => 'Weak draw',
      HandClass.strongDraw => 'Strong draw',
      HandClass.marginalMade => 'Marginal made',
      HandClass.strongMade => 'Strong made',
    };

class StrategyGrid extends StatelessWidget {
  final List<List<GridCellAgg?>> cells;
  final List<Color> actionColors;
  final GridLens lens;
  final void Function(GridCellAgg cell)? onCellTap;
  const StrategyGrid({
    super.key,
    required this.cells,
    required this.actionColors,
    this.lens = GridLens.strategy,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, constraints) {
        return GestureDetector(
          onTapUp: onCellTap == null
              ? null
              : (d) {
                  final col =
                      (d.localPosition.dx / constraints.maxWidth * 13).floor();
                  final row =
                      (d.localPosition.dy / constraints.maxHeight * 13).floor();
                  if (row < 0 || row > 12 || col < 0 || col > 12) return;
                  final cell = cells[row][col];
                  if (cell != null) onCellTap!(cell);
                },
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GridPainter(cells, actionColors, lens),
              size: Size.infinite,
            ),
          ),
        );
      }),
    );
  }
}

class _GridPainter extends CustomPainter {
  final List<List<GridCellAgg?>> cells;
  final List<Color> colors;
  final GridLens lens;
  _GridPainter(this.cells, this.colors, this.lens);

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
          _text(canvas, rect, _handAt(row, col, cell),
              labelStyle.copyWith(color: _labelDim));
          continue;
        }
        // Range presence dims cells that are mostly folded out already.
        final alpha = 0.30 + 0.70 * cell.presence;
        canvas.drawRect(rect, paintFill..color = _absent);
        if (lens == GridLens.handClass) {
          final hc = cell.dominantClass;
          if (hc != null) {
            canvas.drawRect(
              rect,
              paintFill
                ..color = kHandClassColors[hc]!.withValues(alpha: alpha),
            );
          }
        } else {
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
        }
        _text(canvas, rect, cell.hand, labelStyle);
      }
    }
  }

  // Absent cells still get their hand label (dimmed) for orientation — from
  // the SHARED cell→hand naming (card.dart), not a re-fork of it.
  String _handAt(int row, int col, GridCellAgg? cell) =>
      cell?.hand ?? cellToHand(row, col);

  void _text(Canvas canvas, Rect rect, String s, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left + 2, rect.top + 1));
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cells != cells || old.colors != colors || old.lens != lens;
}
