import '../models/swing_capture.dart';
import 'gatt_protocol.dart';

enum SensorStatus { disconnected, connecting, connected, calibrating, armed }

/// Abstraction over the physical sensor. The app is written entirely
/// against this interface:
///  - [MockSensorLink] — synthetic swings, works today with no hardware.
///  - [BleSensorLink]  — real Nicla Sense ME over BLE (Phase 1 firmware).
///
/// Real sensors are added from the scan screen; simulated ones from the
/// + menu. Nothing else in the app knows which kind it is talking to.
abstract class SensorLink {
  SensorStatus get status;

  Stream<SensorStatus> get statusStream;

  /// Emits one complete capture per detected swing (post-impact burst).
  Stream<SwingCapture> get swings;

  /// Emits the ~12-byte instant-metrics packet the moment impact is
  /// detected — seconds before the full capture in [swings] finishes
  /// transferring. This is the <500 ms HUD source (and the payload the
  /// phone relays to the glasses in Phase 4).
  Stream<InstantMetrics> get instantMetrics;

  /// Battery level 0.0–1.0, if the sensor reports it.
  Stream<double> get batteryLevel;

  Future<void> connect();

  Future<void> disconnect();

  /// 1-second static address hold: zeroes the face-angle reference.
  Future<void> calibrateAddress();

  /// Arms swing detection (sensor watches for the gyro threshold trigger).
  Future<void> arm();

  void dispose();
}
