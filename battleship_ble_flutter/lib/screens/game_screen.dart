import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../game_model.dart';
import '../widgets/battle_grid.dart';
import 'placement_screen.dart';

/// Screen 3: Main game screen.
/// Top half = Flutter's defense grid ("MY FLEET").
/// Bottom half = Flutter's attack grid ("ATTACK").
/// Touch attack grid to fire when it's Flutter's turn.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Consumer<GameModel>(
        builder: (context, model, _) {
          return Stack(
            children: [
              SafeArea(child: _GameBody(model: model)),
              if (model.phase == GamePhase.over)
                _GameOverOverlay(model: model),
            ],
          );
        },
      ),
    );
  }
}

//  Main game body
class _GameBody extends StatelessWidget {
  final GameModel model;
  const _GameBody({required this.model});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Turn banner 
        _TurnBanner(model: model),

        // Scrollable content 
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                // MY FLEET (defense) 
                _SectionLabel(
                  label:    'MY FLEET',
                  iconData: Icons.anchor,
                  color:    kShip,
                ),
                const SizedBox(height: 4),
                Center(
                  child: BattleGrid(
                    grid:      model.myGrid,
                    showShips: true,
                    glowRow:   model.lastEventRow,
                    glowCol:   model.lastEventCol,
                  ),
                ),

                const SizedBox(height: 10),

                // Status bar 
                _StatusBar(model: model),

                const SizedBox(height: 10),

                // ATTACK grid 
                _SectionLabel(
                  label:    model.flutterTurn ? 'ATTACK — TAP TO FIRE!' : 'ATTACK',
                  iconData: Icons.gps_fixed,
                  color:    model.flutterTurn ? kCursor : kSubtext,
                ),
                const SizedBox(height: 4),
                Center(
                  child: BattleGrid(
                    grid:        model.attackGrid,
                    showShips:   false,
                    interactive: model.flutterTurn,
                    enabled:     model.flutterTurn,
                    onTap:       model.fireAt,
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

//  Turn banner

class _TurnBanner extends StatelessWidget {
  final GameModel model;
  const _TurnBanner({required this.model});

  @override
  Widget build(BuildContext context) {
    final isFlutterTurn = model.flutterTurn;
    final bg   = isFlutterTurn ? kGreen   : kRedBan;
    final fg   = isFlutterTurn ? Colors.black : kWhite;
    final text = isFlutterTurn ? '⚔  YOUR TURN' : '🛡  INCOMING FIRE';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            text,
            style: TextStyle(
              color:       fg,
              fontSize:    13,
              fontWeight:  FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Text(
            model.statusMsg,
            style: TextStyle(
              color:    fg.withOpacity(0.85),
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

//  Status bar

class _StatusBar extends StatelessWidget {
  final GameModel model;
  const _StatusBar({required this.model});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color:        kStatusBg,
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: kGridLine),
      ),
      child: Column(
        children: [
          // Detail message
          if (model.detailMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                model.detailMsg,
                style: const TextStyle(color: kGreen, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

          // Ship health rows
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ShipHealthBar(
                label:     'MY FLEET',
                total:     kTotalShipCells,
                remaining: model.myShipsLeft,
              ),
              ShipHealthBar(
                label:     'ENEMY',
                total:     kTotalShipCells,
                remaining: model.m5ShipsLeft,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

//  Section label
class _SectionLabel extends StatelessWidget {
  final String   label;
  final IconData iconData;
  final Color    color;

  const _SectionLabel({
    required this.label,
    required this.iconData,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(iconData, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: kLabelStyle.copyWith(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

//  Game Over Overlay

class _GameOverOverlay extends StatelessWidget {
  final GameModel model;
  const _GameOverOverlay({required this.model});

  @override
  Widget build(BuildContext context) {
    final won  = model.iWon;
    final bg   = won ? kGreen.withOpacity(0.15)  : kRedBan.withOpacity(0.15);
    final card = won ? const Color(0xFF003010)    : const Color(0xFF300010);
    final iconColor = won ? kGreen : kHit;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: 1.0,
      child: Container(
        color: kBg.withOpacity(0.88),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color:        card,
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: iconColor, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Icon(
                  won ? Icons.emoji_events : Icons.sentiment_very_dissatisfied,
                  color: iconColor,
                  size: 72,
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  won ? 'VICTORY!' : 'DEFEATED',
                  style: TextStyle(
                    color:       iconColor,
                    fontSize:    30,
                    fontWeight:  FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  model.statusMsg,
                  style: const TextStyle(color: kWhite, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  won
                      ? 'You sank the M5Stack fleet! ⚓'
                      : 'M5Stack destroyed your fleet!',
                  style: const TextStyle(color: kSubtext, fontSize: 12),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatChip(
                      label: 'Your ships',
                      value: '${model.myShipsLeft}/${kTotalShipCells}',
                      color: kShip,
                    ),
                    _StatChip(
                      label: "M5 ships",
                      value: '${model.m5ShipsLeft}/${kTotalShipCells}',
                      color: kSubtext,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Play again button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Disconnect and go back to placement
                      model.ble.disconnect();
                      model.resetPlacement();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const PlacementScreen(),
                        ),
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Play Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: won ? Colors.black : kWhite,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: kLabelStyle),
      ],
    );
  }
}
