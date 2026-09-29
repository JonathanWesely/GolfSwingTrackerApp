import 'dart:async';
import 'dart:typed_data';

/// One advertisement heard during a scan.
class BleScanHit {
  /// Stable device identity (BLE MAC on Android, CoreBluetooth UUID on iOS).
  final String remoteId;
  final String name;
  final int rssi;

  const BleScanHit({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });
}

/// The thin slice of BLE that [BleSensorLink] actually needs — nothing more.
///
/// Production code uses [FlutterBluePlusTransport]; unit tests substitute a
/// fake, so every line of protocol logic (chunk reassembly, reconnect,
/// control ops) is testable without a radio or hardware.
abstract class BleTransport {
  /// Streams advertisements until the listener cancels or [timeout]
  /// elapses (then the stream closes). Devices match by [serviceUuid]
  /// when given — the service id rides in the PRIMARY advertising packet
  /// — falling back to the advertised [name]. iOS often reports a device
  /// only once per scan and without its name (the name arrives in the
  /// separate scan-response packet), so name-only matching missed the
  /// sensor entirely (found 2026-09-30: nRF Connect saw GolfTracker, the
  /// app's scan never did).
  Stream<BleScanHit> scan({
    required String name,
    String? serviceUuid,
    Duration timeout = const Duration(seconds: 15),
  });

  /// Opens a connection to the device with BLE identity [remoteId].
  Future<BleDeviceSession> connect(
    String remoteId, {
    Duration timeout = const Duration(seconds: 15),
  });
}

/// An open connection to one device.
abstract class BleDeviceSession {
  String get remoteId;

  /// Requests a larger MTU; returns the negotiated value. Platforms that
  /// auto-negotiate (iOS) may ignore [desired] and report what they got.
  Future<int> requestMtu(int desired);

  /// Subscribes to notifications on a characteristic. The returned stream
  /// stays open for the life of the session.
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid);

  /// One-shot characteristic read (e.g. initial battery level).
  Future<Uint8List> read(String serviceUuid, String characteristicUuid);

  /// Writes to a characteristic (with response).
  Future<void> write(
      String serviceUuid, String characteristicUuid, List<int> data);

  /// Emits once when the link drops for any reason other than [close].
  Stream<void> get disconnected;

  Future<void> close();
}
