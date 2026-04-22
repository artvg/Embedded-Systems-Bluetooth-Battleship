import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'ble_manager.dart';

enum CellState { empty, ship, hit, miss }
enum GamePhase { placement, scanning, battle, over }

class GameModel extends ChangeNotifier {
  final BleManager ble = BleManager();

  late List<List<CellState>> myGrid;
  late List<List<CellState>> attackGrid;

  int shipsPlaced = 0;
  bool get placementComplete => shipsPlaced >= kShipCount;

  int myShipsLeft = kTotalShipCells;
  int m5ShipsLeft = kTotalShipCells;

  // Scoreboard — persists across rounds
  int scoreWins   = 0;
  int scoreLosses = 0;

  GamePhase phase      = GamePhase.placement;
  bool      flutterTurn = false;
  bool      iWon        = false;

  String statusMsg = 'Deploy your fleet — tap to place ships';
  String detailMsg = '';

  int? lastEventRow;
  int? lastEventCol;

  int? _pendingRow;
  int? _pendingCol;
  int? _m5LeftBeforeFire;

  GameModel() {
    _initGrids();
    ble.onConnected     = _onConnected;
    ble.onDisconnected  = _onDisconnected;
    ble.onMoveReceived  = _onM5Move;
    ble.onStateReceived = _onM5State;
  }

  void _initGrids() {
    myGrid     = List.generate(kGridSize, (_) => List.filled(kGridSize, CellState.empty));
    attackGrid = List.generate(kGridSize, (_) => List.filled(kGridSize, CellState.empty));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Ship Placement
  // ═══════════════════════════════════════════════════════════════════════════

  bool canPlaceAt(int row, int col) {
    if (col + kShipLength > kGridSize) return false;
    for (int dc = 0; dc < kShipLength; dc++) {
      if (myGrid[row][col + dc] != CellState.empty) return false;
    }
    return true;
  }

  void placeShip(int row, int col) {
    if (placementComplete) return;
    if (canPlaceAt(row, col)) {
      _commitShip(row, col);
    } else if (col > 0 && canPlaceAt(row, col - 1)) {
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
      statusMsg = 'Ship $shipsPlaced placed — ${kShipCount - shipsPlaced} left';
      detailMsg = '';
    }
    notifyListeners();
  }

  void undoLastShip() {
    if (shipsPlaced == 0) return;
    outer:
    for (int r = kGridSize - 1; r >= 0; r--) {
      for (int c = kGridSize - kShipLength; c >= 0; c--) {
        bool isShipPair = true;
        for (int dc = 0; dc < kShipLength; dc++) {
          if (myGrid[r][c + dc] != CellState.ship) { isShipPair = false; break; }
        }
        if (isShipPair) {
          for (int dc = 0; dc < kShipLength; dc++) myGrid[r][c + dc] = CellState.empty;
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
    shipsPlaced   = 0;
    myShipsLeft   = kTotalShipCells;
    m5ShipsLeft   = kTotalShipCells;
    flutterTurn   = false;
    iWon          = false;
    lastEventRow  = null;
    lastEventCol  = null;
    _pendingRow   = null;
    _pendingCol   = null;
    _m5LeftBeforeFire = null;
    statusMsg = 'Deploy your fleet — tap to place ships';
    detailMsg = '';
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BLE Callbacks
  // ═══════════════════════════════════════════════════════════════════════════

  void _onConnected() {
    phase       = GamePhase.battle;
    flutterTurn = false;
    statusMsg   = 'INCOMING FIRE';
    detailMsg   = 'M5Stack is aiming — watch your fleet!';
    notifyListeners();
  }

  void _onDisconnected() {
    phase       = GamePhase.placement;
    flutterTurn = false;
    statusMsg   = 'Disconnected — restart to play again';
    detailMsg   = '';
    notifyListeners();
  }

  // M5Stack fired at Flutter's grid
  void _onM5Move(Map<String, dynamic> data) {
    // If we receive a move, we must be in battle — force phase if needed
    if (phase == GamePhase.placement || phase == GamePhase.scanning) {
      phase = GamePhase.battle;
      flutterTurn = false;
    }
    if (phase == GamePhase.over) return;

    final int r = (data['r'] as num?)?.toInt() ?? -1;
    final int c = (data['c'] as num?)?.toInt() ?? -1;
    if (r < 0 || r >= kGridSize || c < 0 || c >= kGridSize) return;

    // Clear pending Flutter shot so _onM5State doesn't double-resolve
    _pendingRow       = null;
    _pendingCol       = null;
    _m5LeftBeforeFire = null;

    final bool isHit = myGrid[r][c] == CellState.ship;
    myGrid[r][c] = isHit ? CellState.hit : CellState.miss;
    lastEventRow = r;
    lastEventCol = c;

    if (isHit) {
      myShipsLeft--;
      if (myShipsLeft <= 0) {
        phase       = GamePhase.over;
        iWon        = false;
        scoreLosses++;
        statusMsg   = 'Your fleet was destroyed!';
        detailMsg   = 'M5Stack wins this battle';
        ble.sendGameOver();
        notifyListeners();
        return;
      }
      statusMsg = 'Hit! M5Stack struck ${_col(c)}${r + 1}';
    } else {
      // M5 missed — calculate proximity to Flutter's ships and send to M5
      final prox = _proximityToShips(r, c);
      ble.sendProximity(prox);
      statusMsg = 'Miss — M5Stack splashed ${_col(c)}${r + 1}';
    }

    flutterTurn = true;
    detailMsg   = 'Tap the ATTACK grid below to fire!';
    notifyListeners();
  }

  // M5Stack sent a state update
  void _onM5State(Map<String, dynamic> data) {
    final int  phaseInt = (data['phase']  as num?)?.toInt() ?? 1;
    final int  m5Left   = (data['myLeft'] as num?)?.toInt() ?? m5ShipsLeft;
    final bool m5Won    = (data['won']    as bool?) ?? false;
    final bool m5Turn   = (data['myTurn'] as bool?) ?? true;

    // Guard: ignore impossible values
    if (m5Left < 0 || m5Left > kTotalShipCells) { notifyListeners(); return; }

    // Resolve pending shot result
    if (_pendingRow != null && _m5LeftBeforeFire != null) {
      final bool wasHit = m5Left < _m5LeftBeforeFire!;
      attackGrid[_pendingRow!][_pendingCol!] = wasHit ? CellState.hit : CellState.miss;

      if (wasHit) {
        detailMsg   = 'Direct hit on M5Stack!';
        m5ShipsLeft = m5Left;
        if (m5ShipsLeft <= 0) {
          phase     = GamePhase.over;
          iWon      = true;
          scoreWins++;
          statusMsg = 'You sank the M5Stack fleet!';
          detailMsg = 'Victory — you win!';
          _pendingRow = null; _pendingCol = null; _m5LeftBeforeFire = null;
          notifyListeners();
          return;
        }
      } else {
        detailMsg = 'Missed — keep trying!';
      }

      _pendingRow = null; _pendingCol = null; _m5LeftBeforeFire = null;
    }

    if (m5Left <= m5ShipsLeft) m5ShipsLeft = m5Left;

    // Check game over from M5 state packet
    if (phaseInt == 3) {
      phase     = GamePhase.over;
      iWon      = !m5Won;
      if (iWon) scoreWins++; else scoreLosses++;
      statusMsg = iWon ? 'You sank the M5Stack fleet!' : 'Defeated!';
      detailMsg = iWon ? 'Victory — you win!' : 'M5Stack wins';
      notifyListeners();
      return;
    }

    // Sync turn
    if (phaseInt == 1 || phaseInt == 2) {
      final bool shouldBeFlutterTurn = !m5Turn;
      if (shouldBeFlutterTurn && !flutterTurn && _pendingRow == null) {
        flutterTurn = true;
        statusMsg   = 'YOUR TURN';
        detailMsg   = 'Tap the ATTACK grid to fire!';
      }
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Flutter Fires
  // ═══════════════════════════════════════════════════════════════════════════

  void fireAt(int row, int col) {
    if (!flutterTurn)                            return;
    if (phase != GamePhase.battle)               return;
    if (attackGrid[row][col] != CellState.empty) return;

    flutterTurn       = false;
    _pendingRow       = row;
    _pendingCol       = col;
    _m5LeftBeforeFire = m5ShipsLeft;

    attackGrid[row][col] = CellState.miss;
    statusMsg = 'Fired at ${_col(col)}${row + 1}';
    detailMsg = 'Waiting for M5Stack response';

    ble.sendMove(row, col);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  String _col(int c) => String.fromCharCode('A'.codeUnitAt(0) + c);
  String colLabel(int c) => _col(c);

  // Calculate proximity level from (row,col) to nearest Flutter ship cell
  // Returns 3=very close, 2=medium, 1=far, 0=too far (no fan)
  int _proximityToShips(int row, int col) {
    int minDist = 999;
    for (int r = 0; r < kGridSize; r++) {
      for (int c = 0; c < kGridSize; c++) {
        if (myGrid[r][c] == CellState.ship) {
          final dist = (r - row).abs() + (c - col).abs();
          if (dist < minDist) minDist = dist;
        }
      }
    }
    if (minDist <= 1) return 3;  // very close — fast fan
    if (minDist == 2) return 2;  // medium
    if (minDist == 3) return 1;  // far — slow fan
    return 0;                    // too far — no fan
  }
}