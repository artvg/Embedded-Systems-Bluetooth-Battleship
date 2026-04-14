import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../game_model.dart';
import '../widgets/battle_grid.dart';
import 'scan_screen.dart';

/// Screen 1: Player places 3 horizontal ships on their 6×6 grid.
/// Tap a cell to place a 2-cell horizontal ship starting at that position.
class PlacementScreen extends StatelessWidget {
  const PlacementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Consumer<GameModel>(
          builder: (context, model, _) {
            return Column(
              children: [
                // Header 
                _header(context, model),

                const SizedBox(height: 12),

                // Instructions 
                _instructions(model),

                const SizedBox(height: 16),

                // Grid 
                Center(
                  child: BattleGrid(
                    grid:        model.myGrid,
                    showShips:   true,
                    interactive: !model.placementComplete,
                    onTap:       model.placeShip,
                  ),
                ),

                const SizedBox(height: 16),

                // Ship progress dots 
                _progressDots(model),

                const Spacer(),

                // Action buttons 
                _actionBar(context, model),

                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  // Widgets 

  Widget _header(BuildContext ctx, GameModel model) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: kGridLine,
      child: Column(
        children: [
          const Text(
            'B A T T L E S H I P',
            style: TextStyle(
              color:   kWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'DEPLOY YOUR FLEET',
            style: kLabelStyle.copyWith(color: kCursor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _instructions(GameModel model) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(
            model.statusMsg,
            style: const TextStyle(color: kWhite, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (model.detailMsg.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              model.detailMsg,
              style: kLabelStyle.copyWith(color: kGreen),
              textAlign: TextAlign.center,
            ),
          ],
          if (!model.placementComplete) ...[
            const SizedBox(height: 8),
            const Text(
              'Tap a cell to place a 2-cell horizontal ship',
              style: TextStyle(color: kSubtext, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _progressDots(GameModel model) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(kShipCount, (i) {
        final placed = i < model.shipsPlaced;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width:  placed ? 28 : 20,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color:        placed ? kShip : kGridLine,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: placed ? kShip : kSubtext),
          ),
        );
      }),
    );
  }

  Widget _actionBar(BuildContext ctx, GameModel model) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Undo button
          if (model.shipsPlaced > 0 && !model.placementComplete)
            TextButton.icon(
              onPressed: model.undoLastShip,
              icon: const Icon(Icons.undo, color: kSubtext, size: 16),
              label: const Text('Undo last ship', style: TextStyle(color: kSubtext)),
            ),

          // Reset button (if all placed)
          if (model.placementComplete)
            TextButton.icon(
              onPressed: model.resetPlacement,
              icon: const Icon(Icons.refresh, color: kSubtext, size: 16),
              label: const Text('Reset placement', style: TextStyle(color: kSubtext)),
            ),

          const SizedBox(height: 8),

          // Main action: Find M5Stack
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: model.placementComplete
                  ? () => Navigator.of(ctx).push(
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                      )
                  : null,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text(
                'Find M5Stack →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: model.placementComplete ? kGreen : kGridLine,
                foregroundColor: model.placementComplete ? Colors.black : kSubtext,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
