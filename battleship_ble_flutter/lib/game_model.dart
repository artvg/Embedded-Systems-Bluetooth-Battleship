import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'ble_manager.dart';

// Enumerations
enum CellState { empty, ship, hit, miss }

/// Mirrors M5Stack phase values:  0 = waiting, 1 = battle, 2 = over
enum GamePhase { placement, scanning, battle, over }

// GameModel — central ChangeNotifier consumed by all screens
class GameModel extends ChangeNotifier {
  final BleManager ble = BleManager();

  // Flutter's defense grid (Flutter's ships + enemy hits)
  late List<List<CellState>> myGrid;

  // Flutter's attack grid (Flutter's shots at M5)
  late List<List<CellState>> attackGrid;

  // Ship placement state
  int shipsPlaced = 0;
  bool get placementComplete => shipsPlaced >= kShipCount;

  // Game stats
  int myShipsLeft = kTotalShipCells;
  int m5ShipsLeft = kTotalShipCells;

  // Phase / turn
  GamePhase phase = GamePhase.placement;
  bool flutterTurn = false; // true = Flutter may fire
  bool iWon = false;

  // Status messages (shown in game screen banner)
  String statusMsg = 'Deploy your fleet — tap to place ships';
  String detailMsg = '';

  // Last event row/col (for cell highlight animations)
  int? lastEventRow;
  int? lastEventCol;

  // Pending shot tracking (to detect hit vs miss from M5 state updates)
  int? _pendingRow;
  int? _pendingCol;
  int? _m5LeftBeforeFire;

  GameModel() {
    _initGrids();
    ble.onConnected = _onConnected;
    ble.onDisconnected = _onDisconnected;
    ble.onMoveReceived = _onM5Move;
    ble.onStateReceived = _onM5State;
  }

  void _initGrids() {
    myGrid = List.generate(
        kGridSize, (_) => List.filled(kGridSize, CellState.empty));
    attackGrid = List.generate(
        kGridSize, (_) => List.filled(kGridSize, CellState.empty));
  }

  //  Ship Placement
  /// Returns true if a horizontal 2-cell ship can start at (row, col).
  bool canPlaceAt(int row, int col) {
    if (col + kShipLength > kGridSize) return false;
    for (int dc = 0; dc < kShipLength; dc++) {
      if (myGrid[row][col + dc] != CellState.empty) return false;
    }
    return true;
  }

  /// Place a horizontal ship. Tries (row, col) first, then (row, col-1).
  void placeShip(int row, int col) {
    if (placementComplete) return;

    if (canPlaceAt(row, col)) {
      _commitShip(row, col);
    } else if (col > 0 && canPlaceAt(row, col - 1)) {
      // User tapped the right cell of a valid pair — shift left
      _commitShip(row, col - 1);
    } else {
      statusMsg = 'Cannot place here — try another spot';
      notifyListeners();
    }
  }

  void _commitShip(int row, int col) {
    for (int dc = 0; dc < kShipLength; dc++) {
      myGrid[row][col + dc] = CellState.ship;
    }
    shipsPlaced++;
    if (placementComplete) {
      statusMsg = 'Fleet deployed! Find your opponent.';
      detailMsg = 'Tap "Find M5Stack" to connect via BLE';
    } else {
      statusMsg =
          'Ship ${shipsPlaced} placed — ${kShipCount - shipsPlaced} left';
      detailMsg = '';
    }
    notifyListeners();
  }

  /// Remove the most recently placed ship.
  void undoLastShip() {
    if (shipsPlaced == 0) return;
    // Scan grid bottom-to-top, right-to-left for last placed pair
    outer:
    for (int r = kGridSize - 1; r >= 0; r--) {
      for (int c = kGridSize - kShipLength; c >= 0; c--) {
        bool isShipPair = true;
        for (int dc = 0; dc < kShipLength; dc++) {
          if (myGrid[r][c + dc] != CellState.ship) {
            isShipPair = false;
            break;
          }
        }
        if (isShipPair) {
          for (int dc = 0; dc < kShipLength; dc++) {
            myGrid[r][c + dc] = CellState.empty;
          }
          shipsPlaced--;
          statusMsg = 'Place ship ${shipsPlaced + 1} of $kShipCount';
          detailMsg = '';
          notifyListeners();
          break outer;
        }
      }
    }
  }

  void resetPlacement() {
    _initGrids();
    shipsPlaced = 0;
    statusMsg = 'Deploy your fleet — tap to place ships';
    detailMsg = '';
    notifyListeners();
  }

  //  BLE Callbacks
  void _onConnected() {
    phase = GamePhase.battle;
    flutterTurn = false; // M5 always goes first
    statusMsg = '🛡 Waiting for M5Stack…';
    detailMsg = 'M5Stack is aiming — watch your fleet!';
    notifyListeners();
  }

  void _onDisconnected() {
    // Keep placement data but reset game state
    phase = GamePhase.placement;
    flutterTurn = false;
    statusMsg = 'Disconnected — restart to play again';
    detailMsg = '';
    notifyListeners();
  }

  // M5Stack fired at Flutter's grid
  void _onM5Move(Map<String, dynamic> data) {
    final int r = (data['r'] as num?)?.toInt() ?? -1;
    final int c = (data['c'] as num?)?.toInt() ?? -1;
    if (r < 0 || r >= kGridSize || c < 0 || c >= kGridSize) return;

    final bool isHit = myGrid[r][c] == CellState.ship;
    myGrid[r][c] = isHit ? CellState.hit : CellState.miss;
    lastEventRow = r;
    lastEventCol = c;

    if (isHit) {
      myShipsLeft--;
      if (myShipsLeft <= 0) {
        phase = GamePhase.over;
        iWon = false;
        statusMsg = ' Your fleet was destroyed!';
        detailMsg = 'M5Stack wins this battle';
        notifyListeners();
        return;
      }
      statusMsg = ' Hit! M5Stack struck ${_col(c)}${r + 1}';
    } else {
      statusMsg = ' Miss — M5Stack splashed ${_col(c)}${r + 1}';
    }

    // After M5 fires, it's Flutter's turn
    flutterTurn = true;
    detailMsg = 'Tap the ATTACK grid below to fire!';
    notifyListeners();
  }

  // M5Stack sent a state update
  void _onM5State(Map<String, dynamic> data) {
    final int phaseInt = (data['phase'] as num?)?.toInt() ?? 1;
    final int m5Left = (data['myLeft'] as num?)?.toInt() ?? m5ShipsLeft;
    final bool m5Won = (data['won'] as bool?) ?? false;
    // myTurn is from M5's perspective — invert it for Flutter's turn
    final bool m5Turn = (data['myTurn'] as bool?) ?? true;
    final bool nowFlutterTurn = !m5Turn;

    // Resolve pending shot result
    // After Flutter fires, M5 responds with a state update.
    // If m5Left decreased, our shot was a HIT.
    if (_pendingRow != null && _m5LeftBeforeFire != null) {
      final bool wasHit = m5Left < _m5LeftBeforeFire!;
      attackGrid[_pendingRow!][_pendingCol!] =
          wasHit ? CellState.hit : CellState.miss;

      if (wasHit) {
        statusMsg = ' Direct hit on M5Stack!';
        detailMsg = ' Your shot was accurate!';
        if (m5Left <= 0) {
          statusMsg = ' Victory! M5Stack fleet destroyed!';
          detailMsg = 'You sank all enemy ships!';
        }
      } else {
        statusMsg = ' Missed — keep trying!';
        detailMsg = 'M5Stack is defending…';
      }

      _pendingRow = null;
      _pendingCol = null;
      _m5LeftBeforeFire = null;
    }

    m5ShipsLeft = m5Left;

    // Sync turn from M5 state (authoritative source of truth)
    // Only update flutterTurn mid-battle to avoid overwriting pending state
    if (phaseInt == 1) {
      final bool newFlutterTurn = nowFlutterTurn;
      // Only update status messages if turn actually changed
      // This prevents overwriting hit/miss messages when state arrives after move
      if (newFlutterTurn != flutterTurn && _pendingRow == null) {
        flutterTurn = newFlutterTurn;
        if (flutterTurn) {
          // Flutter's turn to attack
          statusMsg = '⚔ Your turn to fire!';
          detailMsg = 'Tap the ATTACK grid below to fire!';
        } else {
          // M5's turn to attack - waiting for M5 to fire
          statusMsg = '🛡 Waiting for M5Stack…';
          detailMsg = 'Watch your fleet!';
        }
      } else {
        // Just update the turn variable without changing messages
        flutterTurn = newFlutterTurn;
      }
    }

    // Check game over (M5 phase = 2 means M5 lost = Flutter won)
    if (phaseInt == 2) {
      phase = GamePhase.over;
      // M5 sends phase=2 + won=false when its own ships are gone (M5 lost)
      // M5 never sends phase=2 for Flutter losing (Flutter detects that itself)
      iWon = !m5Won; // M5 didn't win ⇒ Flutter won
      statusMsg = iWon
          ? ' You sank the M5Stack fleet! RAAAAH'
          : ' Defeated! u suck lol';
      detailMsg = iWon ? 'Victory - you win!' : 'M5Stack wins';
      notifyListeners();
      return;
    }

    notifyListeners();
  }

  //  Flutter Fires
  void fireAt(int row, int col) {
    if (!flutterTurn) return;
    if (phase != GamePhase.battle) return;
    if (attackGrid[row][col] != CellState.empty) return;

    flutterTurn = false;

    // Mark as pending — will be confirmed when M5 state arrives
    _pendingRow = row;
    _pendingCol = col;
    _m5LeftBeforeFire = m5ShipsLeft;

    // Temporary placeholder (updated when state comes back)
    attackGrid[row][col] = CellState.miss;

    statusMsg = ' Fired at ${_col(col)}${row + 1}…';
    detailMsg = 'Waiting for M5Stack response';

    ble.sendMove(row, col);
    notifyListeners();
  }

  //  Helpers
  String _col(int c) => String.fromCharCode('A'.codeUnitAt(0) + c);

  String colLabel(int c) => _col(c);
}
