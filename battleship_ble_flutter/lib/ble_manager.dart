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
  BluetoothDevice?            _device;
  BluetoothCharacteristic?    _moveChar;
  BluetoothCharacteristic?    _stateChar;
  StreamSubscription<List<int>>?              _moveSub;
  StreamSubscription<List<int>>?              _stateSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool _connected = false;
  bool get connected => _connected;

  // Callbacks set by GameModel 
  void Function(Map<String, dynamic>)? onMoveReceived;
  void Function(Map<String, dynamic>)? onStateReceived;
  void Function()?                      onConnected;
  void Function()?                      onDisconnected;

  // Connect to a scanned device
  Future<void> connect(BluetoothDevice device) async {
    _device = device;

    // Listen for disconnection
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

    // Discover services and subscribe to characteristics
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
            _moveSub = ch.onValueReceived.listen(_handleMove);
          } else if (_uuidEq(uuid, kStateCharUUID)) {
            _stateChar = ch;
            await ch.setNotifyValue(true);
            _stateSub = ch.onValueReceived.listen(_handleState);
          }
        }
        break;
      }
    }

    if (!found) throw Exception('Battleship BLE service not found on device.');
    if (_moveChar == null) throw Exception('Move characteristic not found.');

    _connected = true;
    onConnected?.call();
  }

  // Send Flutter's move to M5Stack
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

  // Disconnect cleanly
  Future<void> disconnect() async {
    _connected = false;
    await _device?.disconnect();
    _cleanup();
  }

  // Private helpers

  void _handleMove(List<int> data) {
    if (data.isEmpty) return;
    try {
      final map = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
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
      final map = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
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
    _moveSub    = null;
    _stateSub   = null;
    _connSub    = null;
    _moveChar   = null;
    _stateChar  = null;
    _device     = null;
  }

  /// Case-insensitive UUID comparison, ignoring dashes.
  bool _uuidEq(String a, String b) =>
      a.toLowerCase().replaceAll('-', '') ==
      b.toLowerCase().replaceAll('-', '');
}
