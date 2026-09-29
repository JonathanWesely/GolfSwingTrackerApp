import 'dart:async';
import 'dart:typed_data';

import 'package:golf_tracker_app/src/sensor/ble_transport.dart';
import 'package:golf_tracker_app/src/sensor/gatt_protocol.dart';

/// In-memory BLE stack implementing docs/BLE_PROTOCOL.md from the firmware
/// side. Every piece of BleSensorLink's protocol logic runs against this.
class FakeTransport implements BleTransport {
  final List<BleScanHit> advertised;
  final List<FakeSession> sessions = [];
  int connectCalls = 0;
  bool failNextConnect = false;

  FakeTransport({this.advertised = const []});

  @override
  Stream<BleScanHit> scan({
    required String name,
    String? serviceUuid,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      Stream.fromIterable(advertised.where((h) => h.name == name));

  @override
  Future<BleDeviceSession> connect(
    String remoteId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    connectCalls++;
    if (failNextConnect) {
      failNextConnect = false;
      throw Exception('simulated connect failure');
    }
    final s = FakeSession(remoteId);
    sessions.add(s);
    return s;
  }

  FakeSession get current => sessions.last;
}

class FakeSession implements BleDeviceSession {
  @override
  final String remoteId;

  final swingData = StreamController<Uint8List>.broadcast();
  final instant = StreamController<Uint8List>.broadcast();
  final battery = StreamController<Uint8List>.broadcast();
  final disconnectCtrl = StreamController<void>.broadcast();

  final List<List<int>> controlWrites = [];
  final List<String> subscribed = [];
  int? requestedMtu;
  bool closed = false;
  Uint8List batteryReadValue = Uint8List.fromList([87]);

  FakeSession(this.remoteId);

  @override
  Future<int> requestMtu(int desired) async {
    requestedMtu = desired;
    return 247;
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String charUuid) {
    subscribed.add(charUuid);
    if (charUuid == GattIds.swingDataChar) return swingData.stream;
    if (charUuid == GattIds.instantMetricsChar) return instant.stream;
    if (charUuid == GattIds.batteryLevelChar) return battery.stream;
    throw StateError('unexpected subscribe: $charUuid');
  }

  @override
  Future<Uint8List> read(String serviceUuid, String charUuid) async {
    if (charUuid == GattIds.batteryLevelChar) return batteryReadValue;
    throw StateError('unexpected read: $charUuid');
  }

  @override
  Future<void> write(
      String serviceUuid, String charUuid, List<int> data) async {
    if (charUuid == GattIds.controlChar) {
      controlWrites.add(data);
      return;
    }
    throw StateError('unexpected write: $charUuid');
  }

  @override
  Stream<void> get disconnected => disconnectCtrl.stream;

  @override
  Future<void> close() async {
    closed = true;
  }

  /// Simulates the firmware dropping the link.
  void dropLink() => disconnectCtrl.add(null);
}
