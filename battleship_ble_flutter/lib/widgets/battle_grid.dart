import 'package:flutter/material.dart';
import '../constants.dart';
import '../game_model.dart';

//  BattleGrid — renders a 6×6 Battleship grid
class BattleGrid extends StatelessWidget {
  final List<List<CellState>> grid;
  final bool   showShips;     // true = show SHIP cells (defense grid)
  final bool   interactive;   // true = tap to fire (attack grid)
  final void Function(int row, int col)? onTap;

  /// Highlight one cell with the cursor color (for last event / selection).
  final int? glowRow;
  final int? glowCol;

  /// When false, draws a translucent overlay to signal "not your turn".
  final bool enabled;

  const BattleGrid({
    super.key,
    required this.grid,
    this.showShips  = true,
    this.interactive = false,
    this.onTap,
    this.glowRow,
    this.glowCol,
    this.enabled = true,
  });

  // Cell size scales with screen but we cap it for large tablets
  static double cellSize(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    return ((w - 64) / kGridSize).clamp(36.0, 48.0);
  }

  static const double _labelW = 18.0;

  @override
  Widget build(BuildContext context) {
    final cs = cellSize(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column labels (A – F) 
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: _labelW),
              ...List.generate(kGridSize, (c) => SizedBox(
                width: cs,
                child: Text(
                  String.fromCharCode('A'.codeUnitAt(0) + c),
                  textAlign: TextAlign.center,
                  style: kLabelStyle,
                ),
              )),
            ],
          ),
          // Rows
          ...List.generate(kGridSize, (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row label
              SizedBox(
                width: _labelW,
                child: Text(
                  '${r + 1}',
                  textAlign: TextAlign.center,
                  style: kLabelStyle,
                ),
              ),
              // Cells
              ...List.generate(kGridSize, (c) {
                final isGlow = r == glowRow && c == glowCol;
                return _GridCell(
                  size:        cs,
                  state:       grid[r][c],
                  showShip:    showShips,
                  glow:        isGlow,
                  onTap:       interactive && enabled
                                   ? () => onTap?.call(r, c)
                                   : null,
                );
              }),
            ],
          )),
        ],
      ),
    );
  }
}

//  _GridCell

class _GridCell extends StatelessWidget {
  final double    size;
  final CellState state;
  final bool      showShip;
  final bool      glow;
  final VoidCallback? onTap;

  const _GridCell({
    required this.size,
    required this.state,
    required this.showShip,
    required this.glow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:  size,
        height: size,
        decoration: BoxDecoration(
          color: _bg(),
          border: Border.all(
            color: glow ? kCursor : kGridLine,
            width: glow ? 2.5 : 1.0,
          ),
        ),
        child: _icon(),
      ),
    );
  }

  Color _bg() {
    switch (state) {
      case CellState.ship when showShip: return kShip;
      case CellState.hit:                return kHit;
      case CellState.miss:               return kMiss;
      default:                           return kWater;
    }
  }

  Widget? _icon() {
    if (state == CellState.miss) {
      return Center(
        child: Container(
          width: size * 0.18,
          height: size * 0.18,
          decoration: const BoxDecoration(
            color: kSubtext,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    if (state == CellState.hit) {
      return Center(
        child: CustomPaint(
          size: Size(size * 0.55, size * 0.55),
          painter: _CrossPainter(),
        ),
      );
    }
    return null;
  }
}

// X mark painter 
class _CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color      = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap  = StrokeCap.round;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height), p);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

//  ShipHealthBar — small block indicators at bottom of screen
class ShipHealthBar extends StatelessWidget {
  final String label;
  final int total;
  final int remaining;

  const ShipHealthBar({
    super.key,
    required this.label,
    required this.total,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: kLabelStyle.copyWith(color: kSubtext)),
        const SizedBox(width: 6),
        ...List.generate(total, (i) => Container(
          width:  9,
          height: 11,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color:        i < remaining ? kShip : const Color(0xFF501414),
            borderRadius: BorderRadius.circular(2),
          ),
        )),
      ],
    );
  }
}
