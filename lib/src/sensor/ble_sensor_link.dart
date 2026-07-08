import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/swing_capture.dart';
import 'gatt_protocol.dart';
import 'sensor_link.dart';

/// Real Nicla Sense ME link. NOT functional until Phase 1 firmware exists —
/// this stub compiles and documents exactly what the firmware must implement
/// (see docs/BLE_PROTOCOL.md). The rest of the app never touches BLE
/// directly, so finishing this class is the only app-side hardware task.
class BleSensorLink implements SensorLink {
  static const String advertisedName = 'GolfTracker';

  /// When set, connect() targets this exact device (BLE address) — required
  /// for multi-sensor setups where several devices advertise the same name.
  /// When null, connects to the first device matching [advertisedName].
  final String? targetRemoteId;

  BleSensorLink({this.targetRemoteId});

  final _statusCtrl = StreamController<SensorStatus>.broadcast();
  final _swingCtrl = StreamController<SwingCapture>.broadcast();
  final _batteryCtrl = StreamController<double>.broadcast();

  SensorStatus _status = SensorStatus.disconnected;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  List<Uint8List?> _chunks = [];

  @override
  SensorStatus get status => _status;
  @override
  Stream<SensorStatus> get statusStream => _statusCtrl.stream;
  @override
  Stream<SwingCapture> get swings => _swingCtrl.stream;
  @override
  Stream<double> get batteryLevel => _batteryCtrl.stream;

  void _setStatus(SensorStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    _setStatus(SensorStatus.connecting);

    // 1. Scan for the advertised name (optionally a specific device).
    await FlutterBluePlus.startScan(
      withNames: const [advertisedName],
      timeout: const Duration(seconds: 10),
    );
    final result = await FlutterBluePlus.scanResults.expand((r) => r).firstWhere(
        (r) =>
            r.device.platformName == advertisedName &&
            (targetRemoteId == null ||
                r.device.remoteId.str == targetRemoteId));
    await FlutterBluePlus.stopScan();
    _device = result.device;

    // 2. Connect + discover.
    await _device!.connect();
    final services = await _device!.discoverServices();
    final swingService = services.firstWhere(
        (s) => s.uuid.str128.toLowerCase() == GattIds.swingService);

    for (final c in swingService.characteristics) {
      final id = c.uuid.str128.toLowerCase();
      if (id == GattIds.swingDataChar) {
        await c.setNotifyValue(true);
        c.onValueReceived.listen(_onSwingChunk);
      } else if (id == GattIds.controlChar) {
        _control = c;
      }
    }

    // 3. Battery notifications (standard service).
    for (final s in services) {
      if (s.uuid.str128.toLowerCase() == GattIds.batteryService) {
        for (final c in s.characteristics) {
          if (c.uuid.str128.toLowerCase() == GattIds.batteryLevelChar) {
            await c.setNotifyValue(true);
            c.onValueReceived
                .listen((v) => _batteryCtrl.add(v.isEmpty ? 0 : v[0] / 100));
          }
        }
      }
    }

    _setStatus(SensorStatus.connected);
  }

  void _onSwingChunk(List<int> value) {
    final data = Uint8List.fromList(value);
    if (data.length < 4) return;
    final seq = ByteData.sublistView(data).getUint16(0, Endian.little);
    final total = ByteData.sublistView(data).getUint16(2, Endian.little);
    if (_chunks.length != total) {
      _chunks = List<Uint8List?>.filled(total, null);
    }
    if (seq < total) _chunks[seq] = data;

    final capture = SwingPacketCodec.decode(_chunks);
    if (capture != null) {
      _chunks = [];
      _swingCtrl.add(capture);
    }
  }

  @override
  Future<void> calibrateAddress() async {
    _setStatus(SensorStatus.calibrating);
    await _control?.write([ControlOp.calibrateAddress]);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    _setStatus(SensorStatus.connected);
  }

  @override
  Future<void> arm() async {
    await _control?.write([ControlOp.arm]);
    _setStatus(SensorStatus.armed);
  }

  @override
  Future<void> disconnect() async {
    await _device?.disconnect();
    _setStatus(SensorStatus.disconnected);
  }

  @override
  void dispose() {
    _statusCtrl.close();
    _swingCtrl.close();
    _batteryCtrl.close();
  }
}
