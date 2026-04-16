import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../game_model.dart';
import 'game_screen.dart';

/// Screen 2: BLE scan → auto-connect to "Battleship-M5" → navigate to game.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _scanning = false;
  bool _connecting = false;
  String _statusText = 'Tap "Scan" to find the M5Stack';
  List<ScanResult> _results = [];
  StreamSubscription? _resultsSub;
  StreamSubscription? _scanDoneSub;

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((_) => _startScan());
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    _scanDoneSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // Permissions
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  // Scan
  Future<void> _startScan() async {
    if (_scanning || _connecting) return;
    setState(() {
      _scanning = true;
      _results = [];
      _statusText = 'Scanning for Battleship…';
    });

    // Cancel previous subs
    _resultsSub?.cancel();
    _scanDoneSub?.cancel();

    // Debug mode: simulate device after delay
    if (kDebugMode) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _scanning = false;
          _statusText = 'Found simulated device (Debug Mode)';
        });
      }
      return;
    }

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _statusText = 'Scan error: $e\n(Using physical device recommended)';
        });
      }
      return;
    }

    _resultsSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() => _results = results);

      // Auto-connect if we find "Battleship-M5"
      for (final r in results) {
        if (r.device.platformName.contains('Battleship') && !_connecting) {
          _connect(r.device);
          break;
        }
      }
    });

    _scanDoneSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!mounted) return;
      if (!scanning) {
        setState(() {
          _scanning = false;
          _statusText = _results.isEmpty
              ? 'No devices found — tap Scan to retry\n(Emulator may not support BLE)'
              : 'Tap a device to connect';
        });
      }
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    _resultsSub?.cancel();
    _scanDoneSub?.cancel();
    if (mounted) setState(() => _scanning = false);
  }

  // Connect
  Future<void> _connect(BluetoothDevice device) async {
    if (_connecting) return;
    await _stopScan();

    setState(() {
      _connecting = true;
      _statusText = 'Connecting to ${device.platformName}…';
    });

    final model = context.read<GameModel>();

    // Debug mode: skip actual BLE connection
    if (kDebugMode) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameScreen()),
        );
      }
      return;
    }

    try {
      await model.ble.connect(device);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _statusText = 'Connection failed: $e';
        });
      }
    }
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              color: kGridLine,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: kWhite),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'FIND OPPONENT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balance back button
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Radar animation / spinner
            if (_scanning || _connecting)
              const _RadarIcon()
            else
              const Icon(Icons.bluetooth, color: kSubtext, size: 64),

            const SizedBox(height: 24),

            // Status text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _statusText,
                style: const TextStyle(color: kWhite, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            // Scan / stop button
            if (!_connecting)
              ElevatedButton.icon(
                onPressed: _scanning ? _stopScan : _startScan,
                icon: Icon(_scanning ? Icons.stop : Icons.radar),
                label: Text(_scanning ? 'Stop' : 'Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scanning ? kRedBan : kGreen,
                  foregroundColor: _scanning ? kWhite : Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Device list
            if (_results.isNotEmpty && !_connecting)
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(color: kGridLine),
                  itemBuilder: (ctx, i) {
                    final r = _results[i];
                    final name = r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : r.device.remoteId.str;
                    final isBs = name.contains('Battleship');
                    return ListTile(
                      leading: Icon(
                        Icons.bluetooth,
                        color: isBs ? kGreen : kSubtext,
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          color: isBs ? kGreen : kWhite,
                          fontWeight:
                              isBs ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        'RSSI ${r.rssi} dBm',
                        style: kLabelStyle,
                      ),
                      trailing: ElevatedButton(
                        onPressed: () => _connect(r.device),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isBs ? kGreen : kGridLine,
                          foregroundColor: isBs ? Colors.black : kWhite,
                        ),
                        child: const Text('Connect'),
                      ),
                    );
                  },
                ),
              )
            else
              const Spacer(),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// Animated radar spinner

class _RadarIcon extends StatefulWidget {
  const _RadarIcon();

  @override
  State<_RadarIcon> createState() => _RadarIconState();
}

class _RadarIconState extends State<_RadarIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * 3.14159,
        child: const Icon(Icons.radar, color: kGreen, size: 72),
      ),
    );
  }
}
