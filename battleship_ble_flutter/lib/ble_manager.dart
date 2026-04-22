import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'constants.dart';

/// Handles all BLE communication with the M5Stack Battleship firmware.
///
/// Protocol (from M5 firmware):
///   movChar (WRITE + NOTIFY)
///     → M5 notifies: {"r": row, "c": col}     (M5 fired a shot)
///     → Flutter writes: {"r": row, "c": col}   (Flutter fires a shot)
///   stateChar (NOTIFY)
///     → M5 notifies: {"phase": 0-2, "myTurn": bool, "myLeft": int,
///                      "enLeft": int, "won": bool}
class BleManager {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _moveChar;
  BluetoothCharacteristic? _stateChar;
  StreamSubscription<List<int>>? _moveSub;
  StreamSubscription<List<int>>? _stateSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool _connected = false;
  bool get connected => _connected;

  // ── Callbacks set by GameModel ────────────────────────────────────────────
  void Function(Map<String, dynamic>)? onMoveReceived;
  void Function(Map<String, dynamic>)? onStateReceived;
  void Function()? onConnected;
  void Function()? onDisconnected;

  // ── Connect to a scanned device ──────────────────────────────────────────
  Future<void> connect(BluetoothDevice device) async {
    _device = device;

    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && _connected) {
        _connected = false;
        _cleanup();
        onDisconnected?.call();
      }
    });

    await device.connect(
      timeout: const Duration(seconds: 15),
      autoConnect: false,
    );

    final services = await device.discoverServices();
    bool found = false;

    for (final svc in services) {
      if (_uuidEq(svc.uuid.toString(), kServiceUUID)) {
        found = true;

        for (final ch in svc.characteristics) {
          final uuid = ch.uuid.toString();

          if (_uuidEq(uuid, kMoveCharUUID)) {
            _moveChar = ch;
            await ch.setNotifyValue(true);
            _moveSub = ch.lastValueStream.listen(_handleMove);
            // ignore: avoid_print
            print('[BLE] Move notify subscribed');
          } else if (_uuidEq(uuid, kStateCharUUID)) {
            _stateChar = ch;
            await ch.setNotifyValue(true);
            _stateSub = ch.lastValueStream.listen(_handleState);
            // ignore: avoid_print
            print('[BLE] State notify subscribed');
          }
        }
        break;
      }
    }

    if (!found) {
      throw Exception('Battleship BLE service not found on device.');
    }
    if (_moveChar == null) {
      throw Exception('Move characteristic not found.');
    }

    _connected = true;
    // ignore: avoid_print
    print('[BLE] Connected');
    onConnected?.call();
  }

  // ── Send Flutter's move to M5Stack ────────────────────────────────────────
  Future<void> sendMove(int row, int col) async {
    if (_moveChar == null || !_connected) return;
    try {
      final payload = utf8.encode(jsonEncode({'r': row, 'c': col}));
      await _moveChar!.write(payload, withoutResponse: false);
      // ignore: avoid_print
      print('[BLE] Sent move: r=$row c=$col');
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] Write error: $e');
    }
  }

  // ── Send game over signal to M5 so it shows WINNER screen ─────────────────
  Future<void> sendGameOver() async {
    if (_moveChar == null || !_connected) return;
    try {
      final payload = utf8.encode(jsonEncode({'gameover': true}));
      await _moveChar!.write(payload, withoutResponse: false);
      // ignore: avoid_print
      print('[BLE] Sent gameover signal');
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] Write error (gameover): $e');
    }
  }

  // ── Send proximity hint to M5 so fan spins after M5 misses ────────────────
  Future<void> sendProximity(int prox) async {
    if (_moveChar == null || !_connected) return;
    try {
      final payload = utf8.encode(jsonEncode({'prox': prox}));
      await _moveChar!.write(payload, withoutResponse: false);
      // ignore: avoid_print
      print('[BLE] Sent proximity: $prox');
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] Write error (prox): $e');
    }
  }

  // ── Disconnect cleanly ────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _connected = false;
    await _device?.disconnect();
    _cleanup();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _handleMove(List<int> data) {
    if (data.isEmpty) return;
    try {
      final raw = utf8.decode(data);
      // ignore: avoid_print
      print('[BLE] Move raw: $raw');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map.containsKey('r') && map.containsKey('c')) {
        onMoveReceived?.call(map);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] Move parse error: $e  raw=${utf8.decode(data)}');
    }
  }

  void _handleState(List<int> data) {
    if (data.isEmpty) return;
    try {
      final raw = utf8.decode(data);
      // ignore: avoid_print
      print('[BLE] State raw: $raw');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      onStateReceived?.call(map);
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] State parse error: $e  raw=${utf8.decode(data)}');
    }
  }

  void _cleanup() {
    _moveSub?.cancel();
    _stateSub?.cancel();
    _connSub?.cancel();
    _moveSub = null;
    _stateSub = null;
    _connSub = null;
    _moveChar = null;
    _stateChar = null;
    _device = null;
  }

  /// Case-insensitive UUID comparison, ignoring dashes.
  bool _uuidEq(String a, String b) =>
      a.toLowerCase().replaceAll('-', '') ==
      b.toLowerCase().replaceAll('-', '');
}