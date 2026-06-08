import 'package:flutter/material.dart';
import '../../equity/card.dart';

class RangeMatrix extends StatefulWidget {
  final Set<int> selectedCells; // row * 13 + col
  final ValueChanged<Set<int>> onChanged;

  const RangeMatrix({super.key, required this.selectedCells, required this.onChanged});

  @override
  State<RangeMatrix> createState() => _RangeMatrixState();
}

class _RangeMatrixState extends State<RangeMatrix> {
  final _key = GlobalKey();
  bool _dragAdding = true;

  static const double _labelW = 18.0;
  static const double _headerH = 14.0;

  // Convert a global pointer position to a matrix (row, col), or null if outside cells.
  (int, int)? _cellAt(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final p = box.globalToLocal(global);
    final cellSize = (box.size.width - _labelW) / 13;
    if (cellSize <= 0) return null;
    if (p.dx < _labelW || p.dy < _headerH) return null;
    if (p.dx > box.size.width || p.dy > _headerH + 13 * cellSize) return null;
    final c = ((p.dx - _labelW) / cellSize).floor().clamp(0, 12);
    final r = ((p.dy - _headerH) / cellSize).floor().clamp(0, 12);
    return (r, c);
  }

  void _onTapUp(TapUpDetails d) {
    final cell = _cellAt(d.globalPosition);
    if (cell == null) return;
    final k = cell.$1 * 13 + cell.$2;
    final s = Set<int>.from(widget.selectedCells);
    if (s.contains(k)) { s.remove(k); } else { s.add(k); }
    widget.onChanged(s);
  }

  void _onPanStart(DragStartDetails d) {
    final cell = _cellAt(d.globalPosition);
    if (cell == null) return;
    final k = cell.$1 * 13 + cell.$2;
    _dragAdding = !widget.selectedCells.contains(k);
    _apply(k);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final cell = _cellAt(d.globalPosition);
    if (cell == null) return;
    _apply(cell.$1 * 13 + cell.$2);
  }

  void _apply(int k) {
    final s = Set<int>.from(widget.selectedCells);
    final before = s.length;
    if (_dragAdding) { s.add(k); } else { s.remove(k); }
    if (s.length != before) widget.onChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurface.withAlpha(110);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalW = constraints.maxWidth;
          final cellSize = (totalW - _labelW) / 13;

          return Column(
            key: _key,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  SizedBox(width: _labelW, height: _headerH),
                  for (int c = 0; c < 13; c++)
                    SizedBox(
                      width: cellSize,
                      height: _headerH,
                      child: Center(
                        child: Text(
                          kMatrixRanks[c],
                          style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: labelColor),
                        ),
                      ),
                    ),
                ],
              ),
              // Data rows
              for (int r = 0; r < 13; r++)
                Row(
                  children: [
                    SizedBox(
                      width: _labelW,
                      height: cellSize,
                      child: Center(
                        child: Text(
                          kMatrixRanks[r],
                          style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: labelColor),
                        ),
                      ),
                    ),
                    for (int c = 0; c < 13; c++)
                      _CellView(
                        row: r, col: c,
                        size: cellSize,
                        selected: widget.selectedCells.contains(r * 13 + c),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CellView extends StatelessWidget {
  final int row, col;
  final double size;
  final bool selected;

  const _CellView({required this.row, required this.col, required this.size, required this.selected});

  Color _bg(BuildContext context) {
    if (!selected) {
      return Theme.of(context).colorScheme.onSurface.withAlpha(18);
    }
    if (row == col) return Colors.amber;
    if (row < col) return Colors.green.shade600;
    return Colors.blue.shade600;
  }

  @override
  Widget build(BuildContext context) {
    // Show full hand name: "AA", "AKs", "AKo"
    final name = cellToHand(row, col);
    return Container(
      width: size - 0.8,
      height: size - 0.8,
      margin: const EdgeInsets.all(0.4),
      decoration: BoxDecoration(color: _bg(context), borderRadius: BorderRadius.circular(1)),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            name,
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.30),
            ),
          ),
        ),
      ),
    );
  }
}

// Tiny 39×39 matrix preview for player cards
class MiniRangeMatrix extends StatelessWidget {
  final Set<int> selectedCells;

  const MiniRangeMatrix({super.key, required this.selectedCells});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(52, 52),
      painter: _MiniPainter(
          selectedCells, Theme.of(context).colorScheme.onSurface.withAlpha(18)),
    );
  }
}

class _MiniPainter extends CustomPainter {
  final Set<int> cells;
  final Color emptyColor;
  _MiniPainter(this.cells, this.emptyColor);

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / 13;
    for (int r = 0; r < 13; r++) {
      for (int c = 0; c < 13; c++) {
        final k = r * 13 + c;
        Color color;
        if (cells.contains(k)) {
          if (r == c) { color = Colors.amber; }
          else if (r < c) { color = Colors.green.shade600; }
          else { color = Colors.blue.shade600; }
        } else {
          color = emptyColor;
        }
        canvas.drawRect(
          Rect.fromLTWH(c * cs, r * cs, cs - 0.3, cs - 0.3),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) =>
      old.cells != cells || old.emptyColor != emptyColor;
}

// Stats widget
class RangeStats extends StatelessWidget {
  final Set<int> selectedCells;

  const RangeStats({super.key, required this.selectedCells});

  @override
  Widget build(BuildContext context) {
    int total = 0;
    for (final k in selectedCells) {
      total += cellComboCount(k ~/ 13, k % 13);
    }
    final pct = (total / 1326 * 100).toStringAsFixed(1);
    return Text(
      '$total combos ($pct%)',
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(180)),
    );
  }
}
